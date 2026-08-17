// Package session owns conversation continuity — the invariant that makes
// it necessary: the dsh jsonrpc composition routes no session-loading
// method and its persistence plugin writes files nothing reads back, so a
// restarted runtime remembers NOTHING. The TUI-owned transcript here is
// the only real history: every notification is appended as NDJSON under
// <session-root>/tui/<session-id>.ndjson; resume renders it back into
// scrollback and RestoreContext injects it into a fresh runtime's first
// prompt. Every failure here is loud — a silently dead transcript means
// restore silently injects nothing, and the model's amnesia hides behind
// a rendered scrollback that looks fine.
package session

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/gitseed/monorepo/dsh-tui/internal/harness"
	"github.com/gitseed/monorepo/dsh-tui/internal/render"
)

type Transcript struct {
	Path string
	f    *os.File
	enc  *json.Encoder
}

// NewTranscript opens the transcript for appending immediately — a
// recording that can't work should fail at launch, not on first event.
func NewTranscript(sessionRoot, sessionID string) (*Transcript, error) {
	path := filepath.Join(sessionRoot, "tui", sessionID+".ndjson")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("transcript dir: %w", err)
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return nil, fmt.Errorf("transcript open: %w", err)
	}
	return &Transcript{Path: path, f: f, enc: json.NewEncoder(f)}, nil
}

func (t *Transcript) Append(n harness.Notification) error {
	if err := t.enc.Encode(map[string]any{"method": n.Method, "params": n.Payload}); err != nil {
		return fmt.Errorf("transcript write: %w", err)
	}
	return nil
}

// RestoreContext rebuilds the conversation from a transcript for injection
// into a fresh runtime. A missing file is a valid empty history; any other
// failure is the caller's to surface. Kept compact: turns plus one-line
// tool summaries, tail-clamped.
func RestoreContext(path string) (string, error) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("transcript read: %w", err)
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 32*1024*1024)
	var parts []string
	for scanner.Scan() {
		var msg struct {
			Method string         `json:"method"`
			Params map[string]any `json:"params"`
		}
		if json.Unmarshal(scanner.Bytes(), &msg) != nil {
			continue
		}
		n := harness.Notification{Method: msg.Method, Payload: msg.Params}
		event := render.EventOf(n)
		if event == nil {
			continue
		}
		typ, _ := event["type"].(string)
		data, _ := event["data"].(map[string]any)
		switch typ {
		case "user/message":
			if msg, ok := data["message"].(map[string]any); ok {
				if src, ok := msg["source"].(map[string]any); ok && src["kind"] == "tool" {
					continue
				}
			}
			if src, ok := data["source"].(map[string]any); ok && src["kind"] != "user" {
				continue
			}
			if t := render.TextContent(data); t != "" {
				parts = append(parts, "user: "+t)
			}
		case "assistant/message":
			if t := render.TextContent(data); t != "" {
				parts = append(parts, "assistant: "+t)
			}
		case "tool/call":
			name, _ := data["name"].(string)
			args, _ := data["arguments"].(string)
			parts = append(parts, "assistant ran tool "+name+" "+render.TruncateRunes(args, 200))
		}
	}
	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("transcript read: %w", err)
	}
	if len(parts) == 0 {
		return "", nil
	}
	history := strings.Join(parts, "\n\n")
	const maxRestore = 16000
	if len(history) > maxRestore {
		history = "(earlier history truncated)\n…" + render.TailRunes(history, maxRestore)
	}
	return "<session-restore>\nThe runtime restarted; your in-context memory of this session was lost. " +
		"This is the conversation so far, restored from the client's transcript:\n\n" +
		history + "\n</session-restore>\n\n", nil
}

// RenderResume prints a stored transcript through the same renderer as the
// live stream, directly into the normal-screen flow before the TUI starts —
// unwrapped logical lines, so the copy semantics of resumed history match
// live history. A missing transcript reports itself: resuming a session
// nobody recorded should not look like an empty session.
func RenderResume(path string) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		fmt.Println(render.StyleErr.Render("no transcript for this session — nothing to resume, the model starts blank"))
		return
	}
	if err != nil {
		fmt.Println(render.StyleErr.Render("resume failed: " + err.Error()))
		return
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 32*1024*1024)
	count := 0
	for scanner.Scan() {
		var msg struct {
			Method string         `json:"method"`
			Params map[string]any `json:"params"`
		}
		if json.Unmarshal(scanner.Bytes(), &msg) != nil || msg.Method == "" {
			continue
		}
		count++
		if line := render.Summarize(harness.Notification{Method: msg.Method, Payload: msg.Params}); line != "" {
			fmt.Println(line)
		}
	}
	if err := scanner.Err(); err != nil {
		fmt.Println(render.StyleErr.Render("resume truncated: " + err.Error()))
	}
	if count > 0 {
		fmt.Println("\n" + render.StyleDim.Render(fmt.Sprintf("— resumed (%d earlier events)", count)))
	}
}
