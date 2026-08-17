package main

// Replay a captured notification stream (-probe output NDJSON) through the
// UI without a runtime or model — deterministic frames for the screenshot
// harness (scripts/screenshot.bash) and offline styling work.

import (
	"bufio"
	"encoding/json"
	"os"
	"time"
)

type replayConn struct {
	notifs chan Notification
	reqs   chan IncomingRequest
	died   chan error
}

func (r *replayConn) Prompt(sessionID, text string) (string, error) { return "replay-message", nil }
func (r *replayConn) RespondError(id json.RawMessage, code int, message string) error {
	return nil
}
func (r *replayConn) NotifCh() <-chan Notification  { return r.notifs }
func (r *replayConn) ReqCh() <-chan IncomingRequest { return r.reqs }
func (r *replayConn) DiedCh() <-chan error          { return r.died }

func startReplay(path string) (*replayConn, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	r := &replayConn{
		notifs: make(chan Notification, 16),
		reqs:   make(chan IncomingRequest),
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
			r.notifs <- Notification{Method: msg.Method, Payload: msg.Params}
		}
	}()
	return r, nil
}
