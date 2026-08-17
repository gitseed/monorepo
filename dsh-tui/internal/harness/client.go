package harness

// Minimal JSON-RPC 2.0 client for the dsh SDK runtime: newline-delimited
// messages over the subprocess's stdio. Mirrors the Python SDK's
// HarnessClient (python/sdk/src/deepseek_harness/client.py) — three message
// shapes share the pipe: responses (id, no method), server-initiated
// requests (id + method), and notifications (method, no id).

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (e *rpcError) Error() string {
	return fmt.Sprintf("jsonrpc error %d: %s", e.Code, e.Message)
}

type rpcResult struct {
	result json.RawMessage
	err    error
}

type wireMessage struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  map[string]any  `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type Client struct {
	cmd   *exec.Cmd
	stdin io.WriteCloser

	writeMu sync.Mutex
	mu      sync.Mutex
	nextID  int
	pending map[string]chan rpcResult

	Notifications chan Notification
	Requests      chan IncomingRequest
	Died          chan error

	stderrMu   sync.Mutex
	stderrTail []string
}

// StartClient launches the runtime subprocess and begins reading its stdout.
// env entries are appended to the inherited environment.
func StartClient(launchArgs []string, dir string, env []string) (*Client, error) {
	cmd := exec.Command(launchArgs[0], launchArgs[1:]...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), env...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	c := &Client{
		cmd:           cmd,
		stdin:         stdin,
		pending:       make(map[string]chan rpcResult),
		Notifications: make(chan Notification, 256),
		Requests:      make(chan IncomingRequest, 16),
		Died:          make(chan error, 1),
	}
	go c.readLoop(stdout)
	go c.stderrLoop(stderr)
	return c, nil
}

func (c *Client) readLoop(stdout io.Reader) {
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 32*1024*1024)
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}
		var msg wireMessage
		if err := json.Unmarshal(line, &msg); err != nil {
			continue
		}
		c.dispatch(&msg)
	}
	err := scanner.Err()
	c.failPending(fmt.Errorf("runtime stdout closed: %w (stderr tail: %s)", err, c.StderrTail()))
	select {
	case c.Died <- fmt.Errorf("runtime exited: %s", c.StderrTail()):
	default:
	}
}

func (c *Client) dispatch(msg *wireMessage) {
	hasID := len(msg.ID) > 0 && string(msg.ID) != "null"
	switch {
	case hasID && msg.Method != "":
		c.Requests <- IncomingRequest{ID: msg.ID, Method: msg.Method, Payload: msg.Params}
	case hasID:
		var id string
		if err := json.Unmarshal(msg.ID, &id); err != nil {
			id = string(msg.ID)
		}
		c.mu.Lock()
		waiter := c.pending[id]
		delete(c.pending, id)
		c.mu.Unlock()
		if waiter == nil {
			return
		}
		if msg.Error != nil {
			waiter <- rpcResult{err: msg.Error}
		} else {
			waiter <- rpcResult{result: msg.Result}
		}
	case msg.Method != "":
		c.Notifications <- Notification{Method: msg.Method, Payload: msg.Params}
	}
}

func (c *Client) stderrLoop(stderr io.Reader) {
	scanner := bufio.NewScanner(stderr)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		c.stderrMu.Lock()
		c.stderrTail = append(c.stderrTail, scanner.Text())
		if len(c.stderrTail) > 100 {
			c.stderrTail = c.stderrTail[len(c.stderrTail)-100:]
		}
		c.stderrMu.Unlock()
	}
}

func (c *Client) StderrTail() string {
	c.stderrMu.Lock()
	defer c.stderrMu.Unlock()
	if len(c.stderrTail) == 0 {
		return "(empty)"
	}
	tail := c.stderrTail
	if len(tail) > 5 {
		tail = tail[len(tail)-5:]
	}
	out := ""
	for _, l := range tail {
		out += "\n  " + l
	}
	return out
}

func (c *Client) failPending(err error) {
	c.mu.Lock()
	waiters := c.pending
	c.pending = make(map[string]chan rpcResult)
	c.mu.Unlock()
	for _, w := range waiters {
		w <- rpcResult{err: err}
	}
}

func (c *Client) write(msg map[string]any) error {
	payload, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_, err = c.stdin.Write(append(payload, '\n'))
	return err
}

// Call issues a request and waits for its response.
func (c *Client) Call(method string, params map[string]any, timeout time.Duration) (json.RawMessage, error) {
	c.mu.Lock()
	c.nextID++
	id := strconv.Itoa(c.nextID)
	waiter := make(chan rpcResult, 1)
	c.pending[id] = waiter
	c.mu.Unlock()

	msg := map[string]any{"jsonrpc": "2.0", "id": id, "method": method}
	if params != nil {
		msg["params"] = params
	}
	if err := c.write(msg); err != nil {
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
		return nil, err
	}
	var timeoutCh <-chan time.Time
	if timeout > 0 {
		timeoutCh = time.After(timeout)
	}
	select {
	case r := <-waiter:
		return r.result, r.err
	case <-timeoutCh:
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
		return nil, fmt.Errorf("%s timed out; stderr tail: %s", method, c.StderrTail())
	}
}

// Respond answers a server-initiated request.
func (c *Client) Respond(id json.RawMessage, result any) error {
	return c.write(map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
}

func (c *Client) RespondError(id json.RawMessage, code int, message string) error {
	return c.write(map[string]any{
		"jsonrpc": "2.0", "id": id,
		"error": map[string]any{"code": code, "message": message},
	})
}

func (c *Client) NotifCh() <-chan Notification  { return c.Notifications }
func (c *Client) ReqCh() <-chan IncomingRequest { return c.Requests }
func (c *Client) DiedCh() <-chan error          { return c.Died }

func (c *Client) Initialize(cwd, provider, model string, maxTokens int) error {
	params := map[string]any{"cwd": cwd, "provider": provider, "model": model}
	if maxTokens > 0 {
		params["maxTokens"] = maxTokens
	}
	_, err := c.Call("initialize", params, 60*time.Second)
	return err
}

// Cancel asks the runtime to cancel the addressed session's running turn
// (dsh-tui's plugin routes it; the stock server answers unknown-method —
// detect that with IsUnknownMethod and fall back). The agent survives with
// its context; the turn settles as aborted.
func (c *Client) Cancel(sessionID string) error {
	_, err := c.Call("session/cancel", map[string]any{"sessionId": sessionID}, 10*time.Second)
	return err
}

// IsUnknownMethod reports whether err is the runtime's unknown-method
// rejection — the signal that the composition lacks the cancel plugin.
func IsUnknownMethod(err error) bool {
	return err != nil && strings.Contains(err.Error(), "unknown DeepSeek Harness SDK runtime method")
}

// Prompt queues text into a session's inbox and returns the message id.
// Progress arrives as notifications; session.status "idle" marks the end.
func (c *Client) Prompt(sessionID, text string) (string, error) {
	raw, err := c.Call("session/prompt", map[string]any{
		"sessionId":     sessionID,
		"contentBlocks": []map[string]any{{"type": "text", "text": text}},
	}, 60*time.Second)
	if err != nil {
		return "", err
	}
	var resp struct {
		MessageID string `json:"messageId"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return "", err
	}
	return resp.MessageID, nil
}

// Kill terminates the runtime subprocess immediately (interrupt path: the
// jsonrpc composition routes no session/cancel, so stopping a turn means
// stopping the process — tool children die with it, the JSONL session
// survives on disk).
func (c *Client) Kill() {
	if c.cmd != nil && c.cmd.Process != nil {
		c.cmd.Process.Kill()
	}
}

// Close attempts a graceful shutdown and then reaps the subprocess.
func (c *Client) Close() {
	c.Call("shutdown", nil, 2*time.Second)
	c.stdin.Close()
	done := make(chan struct{})
	go func() {
		c.cmd.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		c.cmd.Process.Kill()
		<-done
	}
}
