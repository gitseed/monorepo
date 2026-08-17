package main

// TUI-owned transcript: every notification the UI receives is appended as
// NDJSON under <session-root>/tui/<session-id>.ndjson, and -session resume
// renders it back through summarize() into native scrollback before the
// live region starts. Runtime-side JSONL persistence is composition-
// dependent (the minimal composition doesn't reliably write it), so the
// TUI records what it saw — same shape as -probe output, so a transcript
// is also a valid -replay input.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type transcript struct {
	path string
	f    *os.File
	enc  *json.Encoder
}

func newTranscript(sessionRoot, sessionID string) *transcript {
	return &transcript{path: filepath.Join(sessionRoot, "tui", sessionID+".ndjson")}
}

func (t *transcript) append(n Notification) {
	if t == nil {
		return
	}
	if t.f == nil {
		if err := os.MkdirAll(filepath.Dir(t.path), 0o755); err != nil {
			return
		}
		f, err := os.OpenFile(t.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
		if err != nil {
			return
		}
		t.f = f
		t.enc = json.NewEncoder(f)
	}
	t.enc.Encode(map[string]any{"method": n.Method, "params": n.Payload})
}

// renderResume prints a stored transcript through the same renderer as the
// live stream, directly into the normal-screen flow before the TUI starts —
// unwrapped logical lines, so the copy semantics of resumed history match
// live history.
func renderResume(path string) {
	f, err := os.Open(path)
	if err != nil {
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
		if line := summarize(Notification{Method: msg.Method, Payload: msg.Params}); line != "" {
			fmt.Println(line)
		}
	}
	if count > 0 {
		fmt.Println("\n" + styleDim.Render(fmt.Sprintf("— resumed (%d earlier events)", count)))
	}
}
