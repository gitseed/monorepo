package main

import (
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

// go test runs without a tty, where lipgloss degrades to no-op styles;
// force a profile so styling assertions mean something.
func TestMain(m *testing.M) {
	lipgloss.SetColorProfile(termenv.TrueColor)
	os.Exit(m.Run())
}

var ansiRe = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

func plain(s string) string { return ansiRe.ReplaceAllString(s, "") }

func sessionEvent(typ string, data map[string]any) Notification {
	return Notification{Method: "session.event", Payload: map[string]any{
		"sessionId": "s", "event": map[string]any{"type": typ, "data": data},
	}}
}

func TestSummarizeAssistantMessage(t *testing.T) {
	n := sessionEvent("assistant/message", map[string]any{
		"message": map[string]any{"content": []any{map[string]any{"type": "text", "text": "hello\n\nworld"}}},
	})
	got := plain(summarize(n))
	if !strings.Contains(got, "hello") || !strings.Contains(got, "world") {
		t.Fatalf("assistant text lost: %q", got)
	}
	// Logical lines only: source newlines survive, none are added mid-text.
	if strings.Count(got, "\n") != strings.Count("\n● hello\n\nworld", "\n") {
		t.Fatalf("line structure changed: %q", got)
	}
}

func TestSummarizeSuppressesToolRoleUserMessage(t *testing.T) {
	n := sessionEvent("user/message", map[string]any{
		"message": map[string]any{
			"source":  map[string]any{"kind": "tool"},
			"content": []any{map[string]any{"type": "text", "text": "tool output"}},
		},
	})
	if got := summarize(n); got != "" {
		t.Fatalf("tool-role user message should be suppressed, got %q", got)
	}
}

func TestSummarizeUserMessage(t *testing.T) {
	n := sessionEvent("user/message", map[string]any{
		"content": []any{map[string]any{"type": "text", "text": "hi"}},
		"source":  map[string]any{"kind": "user"},
	})
	if got := plain(summarize(n)); !strings.Contains(got, "❯ hi") {
		t.Fatalf("user message not rendered: %q", got)
	}
}

func TestSummarizeErrorChunkAndCleanFinish(t *testing.T) {
	errChunk := sessionEvent("assistant/chunk", map[string]any{
		"chunk": map[string]any{"type": "finish", "reason": map[string]any{"kind": "error", "message": "boom"}},
	})
	if got := plain(summarize(errChunk)); !strings.Contains(got, "model error") {
		t.Fatalf("error finish not surfaced: %q", got)
	}
	okChunk := sessionEvent("assistant/chunk", map[string]any{
		"chunk": map[string]any{"type": "finish", "reason": map[string]any{"kind": "stop"}},
	})
	if got := summarize(okChunk); got != "" {
		t.Fatalf("clean finish should be silent, got %q", got)
	}
}

func TestSummarizeTurnEnd(t *testing.T) {
	completed := sessionEvent("turn/end", map[string]any{"reason": map[string]any{"kind": "completed"}})
	if got := summarize(completed); got != "" {
		t.Fatalf("completed turn/end should be silent, got %q", got)
	}
	failed := sessionEvent("turn/end", map[string]any{"reason": map[string]any{"kind": "error"}})
	if got := plain(summarize(failed)); !strings.Contains(got, "turn ended: error") {
		t.Fatalf("error turn/end not surfaced: %q", got)
	}
}

func TestSummarizeToolCall(t *testing.T) {
	n := sessionEvent("tool/call", map[string]any{
		"name": "bash", "arguments": `{"command": "echo hi"}`,
	})
	got := plain(summarize(n))
	if !strings.Contains(got, "bash") || !strings.Contains(got, "echo hi") {
		t.Fatalf("tool call rendering lost the command: %q", got)
	}
}

func TestMdInlineCodeSpanIsSelfContained(t *testing.T) {
	got := mdInline("via `x` after")
	// The reset must land before " after" so no color leaks to end of line.
	idx := strings.Index(got, "after")
	if idx == -1 || !strings.Contains(got[:idx], "\x1b[") {
		t.Fatalf("code span not styled: %q", got)
	}
	if plain(got) != "via x after" {
		t.Fatalf("source text mutated: %q", plain(got))
	}
}

func TestMdInlineFences(t *testing.T) {
	text := "before\n```go\nx := 1\n```\nafter `code`"
	got := mdInline(text)
	p := plain(got)
	// Contract: fence delimiters and interiors are byte-exact (code must
	// copy exactly); prose lines may apply display transforms (the span
	// backticks drop, like bullets becoming •).
	want := "before\n```go\nx := 1\n```\nafter code"
	if p != want {
		t.Fatalf("fence styling mutated text:\n want %q\n got  %q", want, p)
	}
}

func TestMdInlineBullets(t *testing.T) {
	if p := plain(mdInline("- item")); p != "• item" {
		t.Fatalf("bullet not replaced: %q", p)
	}
}

func TestChunkAndToolDeltas(t *testing.T) {
	text := sessionEvent("assistant/chunk", map[string]any{
		"chunk": map[string]any{"type": "text-delta", "text": "abc"},
	})
	if d := chunkDelta(text); d != "abc" {
		t.Fatalf("chunkDelta = %q", d)
	}
	tool := sessionEvent("assistant/chunk", map[string]any{
		"chunk": map[string]any{"type": "tool-call-delta", "name": "bash", "argumentsDelta": "{\"c"},
	})
	name, delta, ok := toolDelta(tool)
	if !ok || name != "bash" || delta != "{\"c" {
		t.Fatalf("toolDelta = %q %q %v", name, delta, ok)
	}
}

func TestUsageFrom(t *testing.T) {
	n := sessionEvent("assistant/chunk", map[string]any{
		"chunk": map[string]any{"type": "usage", "usage": map[string]any{"inputTokens": 10.0, "outputTokens": 3.0}},
	})
	in, out, ok := usageFrom(n)
	if !ok || in != 10 || out != 3 {
		t.Fatalf("usageFrom = %d %d %v", in, out, ok)
	}
}
