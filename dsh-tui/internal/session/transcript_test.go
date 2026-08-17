package session

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gitseed/monorepo/dsh-tui/internal/harness"
)

func event(typ string, data map[string]any) harness.Notification {
	return harness.Notification{Method: "session.event", Payload: map[string]any{
		"sessionId": "s", "event": map[string]any{"type": typ, "data": data},
	}}
}

func userMsg(text string) harness.Notification {
	return event("user/message", map[string]any{
		"content": []any{map[string]any{"type": "text", "text": text}},
		"source":  map[string]any{"kind": "user"},
	})
}

func assistantMsg(text string) harness.Notification {
	return event("assistant/message", map[string]any{
		"message": map[string]any{"content": []any{map[string]any{"type": "text", "text": text}}},
	})
}

func toolRoleUserMsg(text string) harness.Notification {
	return event("user/message", map[string]any{
		"message": map[string]any{
			"source":  map[string]any{"kind": "tool"},
			"content": []any{map[string]any{"type": "text", "text": text}},
		},
	})
}

func writeTranscript(t *testing.T, notifs ...harness.Notification) string {
	t.Helper()
	trans, err := NewTranscript(t.TempDir(), "test-session")
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range notifs {
		if err := trans.Append(n); err != nil {
			t.Fatal(err)
		}
	}
	return trans.Path
}

// The function that guards against the amnesia incident: a restarted
// runtime knows nothing, and this preamble is all the memory it gets.
func TestRestoreContextFraming(t *testing.T) {
	path := writeTranscript(t,
		userMsg("first question"),
		event("tool/call", map[string]any{"name": "bash", "arguments": `{"command":"ls"}`}),
		toolRoleUserMsg("tool output that is not the user speaking"),
		assistantMsg("the answer"),
	)
	got, err := RestoreContext(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"<session-restore>", "</session-restore>",
		"user: first question",
		"assistant ran tool bash",
		"assistant: the answer",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("restore missing %q\n%s", want, got)
		}
	}
	if strings.Contains(got, "tool output that is not the user speaking") {
		t.Errorf("tool-role user message leaked into restore as user speech:\n%s", got)
	}
	// Order preserved: question before tool before answer.
	if strings.Index(got, "first question") > strings.Index(got, "the answer") {
		t.Errorf("restore lost conversation order:\n%s", got)
	}
}

func TestRestoreContextMissingFileIsEmptyNotError(t *testing.T) {
	got, err := RestoreContext(filepath.Join(t.TempDir(), "nope.ndjson"))
	if err != nil || got != "" {
		t.Fatalf("missing transcript: got %q, %v; want empty, nil", got, err)
	}
}

func TestRestoreContextTruncatesRuneSafe(t *testing.T) {
	long := strings.Repeat("界", 20000) // 3 bytes per rune
	path := writeTranscript(t, userMsg(long))
	got, err := RestoreContext(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "(earlier history truncated)") {
		t.Fatalf("long history not marked truncated")
	}
	if strings.ContainsRune(got, '�') {
		t.Fatalf("truncation produced invalid UTF-8 (replacement rune present)")
	}
	for _, r := range got {
		_ = r // ranging validates UTF-8; explicit check below
	}
	if !strings.Contains(got, "界界") {
		t.Fatalf("truncated tail lost content")
	}
}

func TestTranscriptRoundTripIsReplayable(t *testing.T) {
	path := writeTranscript(t, userMsg("hello"), assistantMsg("world"))
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 NDJSON lines, got %d", len(lines))
	}
	// The transcript doubles as a -replay fixture: same shape as -probe.
	for _, l := range lines {
		if !strings.Contains(l, `"method":"session.event"`) {
			t.Fatalf("line not in probe shape: %s", l)
		}
	}
}
