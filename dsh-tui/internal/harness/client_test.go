package harness

import (
	"encoding/json"
	"testing"
	"time"
)

func testClient() *Client {
	return &Client{
		pending:       map[string]chan rpcResult{},
		Notifications: make(chan Notification, 4),
		Requests:      make(chan IncomingRequest, 4),
		Died:          make(chan error, 1),
	}
}

// Three message shapes share the pipe; dispatch must split them exactly:
// id+method = server-initiated request, id only = response, method only =
// notification.
func TestDispatchThreeWaySplit(t *testing.T) {
	c := testClient()
	waiter := make(chan rpcResult, 1)
	c.pending["7"] = waiter

	c.dispatch(&wireMessage{ID: json.RawMessage(`"7"`), Result: json.RawMessage(`{"ok":true}`)})
	select {
	case r := <-waiter:
		if r.err != nil || string(r.result) != `{"ok":true}` {
			t.Fatalf("response misrouted: %+v", r)
		}
	default:
		t.Fatal("response not delivered to waiter")
	}

	c.dispatch(&wireMessage{ID: json.RawMessage(`"9"`), Method: "approval/request", Params: map[string]any{"a": 1.0}})
	select {
	case r := <-c.Requests:
		if r.Method != "approval/request" {
			t.Fatalf("incoming request misrouted: %+v", r)
		}
	default:
		t.Fatal("server-initiated request not delivered")
	}

	c.dispatch(&wireMessage{Method: "session.status", Params: map[string]any{"status": "idle"}})
	select {
	case n := <-c.Notifications:
		if n.Method != "session.status" {
			t.Fatalf("notification misrouted: %+v", n)
		}
	default:
		t.Fatal("notification not delivered")
	}
}

func TestDispatchErrorResponse(t *testing.T) {
	c := testClient()
	waiter := make(chan rpcResult, 1)
	c.pending["1"] = waiter
	c.dispatch(&wireMessage{ID: json.RawMessage(`"1"`), Error: &rpcError{Code: -32603, Message: "unknown DeepSeek Harness SDK runtime method: session/cancel"}})
	select {
	case r := <-waiter:
		if r.err == nil || !IsUnknownMethod(r.err) {
			t.Fatalf("unknown-method error not detected: %v", r.err)
		}
	case <-time.After(time.Second):
		t.Fatal("error response not delivered")
	}
}
