// Package harness is the Go client for the DeepSeek Harness SDK runtime:
// process lifecycle, the NDJSON JSON-RPC 2.0 wire protocol, and the event
// types the runtime emits. It has no UI knowledge.
//
// Protocol surface (probed against dsh 0.1.0-rc.6): the jsonrpc composition
// routes exactly initialize, session/prompt, and shutdown. In particular
// there is NO session/cancel (interrupting means killing the process) and
// NO session/load/list/resume/history — a fresh runtime never remembers a
// prior session, whatever the persistence plugin wrote to disk. Session
// continuity is the client's problem; see internal/session.
package harness

import "encoding/json"

// Notification is a server-initiated JSON-RPC notification: session.status,
// session.event, subagent lifecycle.
type Notification struct {
	Method  string
	Payload map[string]any
}

// IncomingRequest is a server-initiated request that expects a response
// (approval flows in richer compositions; none in jsonrpc-agent today).
type IncomingRequest struct {
	ID      json.RawMessage
	Method  string
	Payload map[string]any
}

// Conn is what a UI needs from a session backend: the live runtime
// (*Client) or a canned replay (session.Replay).
type Conn interface {
	Prompt(sessionID, text string) (string, error)
	Cancel(sessionID string) error
	RespondError(id json.RawMessage, code int, message string) error
	Kill()
	NotifCh() <-chan Notification
	ReqCh() <-chan IncomingRequest
	DiedCh() <-chan error
}
