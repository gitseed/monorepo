package tui

import (
	"testing"

	"github.com/gitseed/monorepo/dsh-tui/internal/harness"
)

func statusEvent(status string) harness.Notification {
	return harness.Notification{Method: "session.status", Payload: map[string]any{
		"sessionId": "s", "status": status,
	}}
}

// The "interrupting…" note must clear when the cancelled turn settles —
// it lingered after successful interruption (found in sandbox QA).
func TestInterruptingNoteClearsOnIdle(t *testing.T) {
	m := newModel(Options{SessionID: "s", ModelName: "m"})
	m.status = "running"
	m.note = "interrupting…"
	m.notified(statusEvent("idle"))
	if m.note != "" {
		t.Fatalf("note not cleared on working→idle: %q", m.note)
	}
}

// Other notes survive the same transition — only the transient one clears.
func TestOtherNotesSurviveIdle(t *testing.T) {
	m := newModel(Options{SessionID: "s", ModelName: "m"})
	m.status = "running"
	m.note = "unknown command /foo"
	m.notified(statusEvent("idle"))
	if m.note != "unknown command /foo" {
		t.Fatalf("unrelated note wrongly cleared: %q", m.note)
	}
}
