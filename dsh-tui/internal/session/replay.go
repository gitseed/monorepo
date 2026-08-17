package session

// Replay a captured notification stream (-probe output NDJSON, or a
// transcript — same shape) through the UI without a runtime or model:
// deterministic frames for the screenshot harness and offline styling work.

import (
	"bufio"
	"encoding/json"
	"os"
	"time"

	"github.com/gitseed/monorepo/dsh-tui/internal/harness"
)

type Replay struct {
	notifs chan harness.Notification
	reqs   chan harness.IncomingRequest
	died   chan error
}

func (r *Replay) Prompt(sessionID, text string) (string, error) { return "replay-message", nil }
func (r *Replay) Kill()                                         {}
func (r *Replay) RespondError(id json.RawMessage, code int, message string) error {
	return nil
}
func (r *Replay) NotifCh() <-chan harness.Notification  { return r.notifs }
func (r *Replay) ReqCh() <-chan harness.IncomingRequest { return r.reqs }
func (r *Replay) DiedCh() <-chan error                  { return r.died }

// StartReplay implements harness.Conn from a recorded stream, pacing events
// by their recorded timestamps (capped; DSH_REPLAY_FAST=1 disables sleeps).
func StartReplay(path string) (*Replay, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	r := &Replay{
		notifs: make(chan harness.Notification, 16),
		reqs:   make(chan harness.IncomingRequest),
		died:   make(chan error, 1),
	}
	go func() {
		defer f.Close()
		scanner := bufio.NewScanner(f)
		scanner.Buffer(make([]byte, 0, 64*1024), 32*1024*1024)
		var prev int64
		for scanner.Scan() {
			var msg struct {
				Method string         `json:"method"`
				Params map[string]any `json:"params"`
			}
			if json.Unmarshal(scanner.Bytes(), &msg) != nil || msg.Method == "" {
				continue
			}
			// Pace by the recorded event timestamps, capped so replays of
			// slow model turns stay watchable.
			if event, ok := msg.Params["event"].(map[string]any); ok {
				if t, ok := event["time"].(float64); ok {
					if prev > 0 {
						delay := time.Duration(int64(t)-prev) * time.Millisecond
						if delay > 300*time.Millisecond {
							delay = 300 * time.Millisecond
						}
						if delay > 0 && os.Getenv("DSH_REPLAY_FAST") == "" {
							time.Sleep(delay)
						}
					}
					prev = int64(t)
				}
			}
			r.notifs <- harness.Notification{Method: msg.Method, Payload: msg.Params}
		}
	}()
	return r, nil
}
