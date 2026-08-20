// Package realtime is a minimal client for the OpenAI Realtime API's
// sideband channel: the WebSocket attached to an in-progress SIP call by
// its call_id, plus the REST call-control endpoints. It speaks only the
// protocol; what to say over it is the session package's business.
package realtime

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/coder/websocket"
)

// ErrCallNotFound reports that the call id no longer names a live call:
// the caller hung up, or the SIP leg stopped ringing, before we got here.
var ErrCallNotFound = errors.New("call not found")

// Accept answers an incoming call, configuring the Realtime session that
// runs it ({"type": "realtime", "model": ..., "instructions": ...}); the
// caller's ringing stops and the audio bridges once this returns.
func Accept(ctx context.Context, apiKey, callID string, session map[string]any) error {
	body, err := json.Marshal(session)
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.openai.com/v1/realtime/calls/"+url.PathEscape(callID)+"/accept",
		bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+apiKey)
	request.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNotFound {
		return ErrCallNotFound
	}
	if response.StatusCode >= 300 {
		detail, _ := io.ReadAll(response.Body)
		return fmt.Errorf("accept: %d %s", response.StatusCode, detail)
	}
	return nil
}

// Conn is the sideband WebSocket attached to one call. It carries JSON
// events both ways; the audio flows elsewhere (Twilio<->OpenAI over SIP).
type Conn struct {
	ws *websocket.Conn
}

// Attach opens the call's sideband WebSocket.
func Attach(ctx context.Context, callID, apiKey string) (*Conn, error) {
	ws, response, err := websocket.Dial(ctx,
		"wss://api.openai.com/v1/realtime?call_id="+url.QueryEscape(callID),
		&websocket.DialOptions{HTTPHeader: http.Header{
			"Authorization": {"Bearer " + apiKey},
		}},
	)
	if err != nil {
		// On a refused handshake the response body says why; the library's
		// error alone only carries the status code.
		if response != nil && response.Body != nil {
			if body, _ := io.ReadAll(io.LimitReader(response.Body, 2048)); len(body) > 0 {
				return nil, fmt.Errorf("%w: %s", err, body)
			}
		}
		return nil, err
	}
	// A session config echo can outgrow the library's 32 KiB default.
	ws.SetReadLimit(1 << 20)
	return &Conn{ws: ws}, nil
}

// Send marshals one client event onto the socket.
func (c *Conn) Send(ctx context.Context, event map[string]any) error {
	data, err := json.Marshal(event)
	if err != nil {
		return err
	}
	return c.ws.Write(ctx, websocket.MessageText, data)
}

// Read blocks for the next server event.
func (c *Conn) Read(ctx context.Context) ([]byte, error) {
	_, data, err := c.ws.Read(ctx)
	return data, err
}

// Close drops the socket without a closing handshake; detaching does not
// end the call.
func (c *Conn) Close() {
	c.ws.CloseNow()
}

// Hangup ends the call via the REST control endpoint. It runs on its own
// timeout rather than the session's context because it is called when the
// session is already being torn down; a 404 means the call already ended
// on its own, which is not an error.
func Hangup(apiKey, callID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.openai.com/v1/realtime/calls/"+url.PathEscape(callID)+"/hangup", nil)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+apiKey)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode >= 300 && response.StatusCode != http.StatusNotFound {
		body, _ := io.ReadAll(response.Body)
		return fmt.Errorf("hangup: %d %s", response.StatusCode, body)
	}
	return nil
}
