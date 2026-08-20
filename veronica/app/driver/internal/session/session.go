// Package session is the driver's flow: take the one call this container
// was started for, pick it up (the accept is here, not in the Worker, so
// the driver is attached from the call's first moment), hold the line —
// greeting, logging the session's events, re-checking the caller against
// the allowlist — until the call ends, then report done so the process
// exits and the container stops. Tool handling (function_call events, the
// Cassandra bridge) will grow here.
package session

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/paulcdejean/veronica/driver/internal/contacts"
	"github.com/paulcdejean/veronica/driver/internal/realtime"
)

// Realtime sessions cap at 60 minutes; leave on our own terms before then.
// The container's sleepAfter fuse (wrangler.jsonc) must stay above this.
const sessionCap = 55 * time.Minute

// How often to re-check the caller against the allowlist mid-call.
const allowlistInterval = 1 * time.Minute

// Config is the driver's deployment: the persona it answers with. The call
// itself arrives by request, not environment — the same image drives every
// call.
type Config struct {
	APIKey       string
	Greeting     string
	Model        string
	Voice        string
	Instructions string
	// How long to let the audio path bridge after accept before speaking
	// the greeting: the SIP answer and Twilio's bridging take a beat, and
	// a greeting spoken too early reaches the caller clipped ("...ronica
	// speaking"). Tuned in workspace.tf (voice_greeting_settle_ms).
	GreetingSettle time.Duration
}

// call is the dispatch the Worker POSTs to /call.
type call struct {
	ID     string `json:"call_id"`
	Caller string `json:"caller"`
}

// Handler serves the driver's one call. The first /call dispatch picks up
// and holds; redeliveries of the same dispatch (OpenAI retrying the
// webhook) are acknowledged idempotently.
type Handler struct {
	cfg  Config
	done chan int

	mu      sync.Mutex
	current *call
}

func NewHandler(cfg Config) *Handler {
	return &Handler{cfg: cfg, done: make(chan int, 1)}
}

// Done yields the process's exit code once the call has ended (or failed
// in a way a fresh container should retry).
func (h *Handler) Done() <-chan int {
	return h.done
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost || r.URL.Path != "/call" {
		http.NotFound(w, r)
		return
	}

	var c call
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil || c.ID == "" || c.Caller == "" {
		http.Error(w, "malformed dispatch", http.StatusBadRequest)
		return
	}

	h.mu.Lock()
	if h.current != nil {
		defer h.mu.Unlock()
		if h.current.ID == c.ID {
			// A webhook redelivery caught up with a call already in hand.
			fmt.Fprint(w, "already driving")
			return
		}
		// Containers are named by call_id, so this should be unreachable.
		http.Error(w, "another call owns this driver", http.StatusConflict)
		return
	}
	h.current = &c
	h.mu.Unlock()

	// The call runs on its own context: the Worker's dispatch request may
	// come and go, but the line stays held until the call ends or the cap
	// says we leave (dropping the socket detaches; the call itself
	// survives to OpenAI's own 60-minute limit).
	ctx, cancel := context.WithTimeout(context.Background(), sessionCap)

	// The accept is what answers the phone: it gives the Realtime session
	// Veronica's persona and bridges the audio. Until it runs the caller
	// hears ringing, and once it runs the driver is already here —
	// nothing, greeting included, will escape the transcript when
	// transcripts land.
	err := realtime.Accept(ctx, h.cfg.APIKey, c.ID, map[string]any{
		"type":         "realtime",
		"model":        h.cfg.Model,
		"instructions": h.cfg.Instructions,
		"audio":        map[string]any{"output": map[string]any{"voice": h.cfg.Voice}},
	})
	if errors.Is(err, realtime.ErrCallNotFound) {
		// The caller hung up, or Twilio stopped ringing, while the
		// container started.
		cancel()
		log.Printf("call %s from %s already gone, dropping it", c.ID, c.Caller)
		fmt.Fprint(w, "gone")
		h.exit(0)
		return
	}
	if err != nil {
		// A non-2xx response sends OpenAI a webhook retry; exiting non-zero
		// hands the retry a fresh container.
		cancel()
		log.Printf("accepting call %s: %v", c.ID, err)
		http.Error(w, "accept failed", http.StatusInternalServerError)
		h.exit(1)
		return
	}

	conn, err := realtime.Attach(ctx, c.ID, h.cfg.APIKey)
	if err != nil {
		// The phone is answered but the driver can't get on the line. The
		// call goes on driverless — degraded (no greeting, no mid-call
		// enforcement, no tools) but alive — so this is still a pickup
		// from the webhook's point of view.
		cancel()
		log.Printf("attaching to call %s: %v (call continues driverless)", c.ID, err)
		fmt.Fprint(w, "picked up, attach failed")
		h.exit(0)
		return
	}
	log.Printf("picked up call %s from %s", c.ID, c.Caller)

	go h.hold(ctx, cancel, conn, c)
	fmt.Fprint(w, "picked up")
}

// hold keeps the line until the call ends, the session cap lands, or the
// caller loses their allowlist entry, then reports the process done.
func (h *Handler) hold(ctx context.Context, cancel context.CancelFunc, conn *realtime.Conn, c call) {
	defer cancel()
	defer conn.Close()

	// Attaching does not replay session.created, so nudge the server into
	// echoing session.updated (a no-op update) to get the effective
	// instructions into the logs.
	if err := conn.Send(ctx, map[string]any{
		"type":    "session.update",
		"session": map[string]any{"type": "realtime"},
	}); err != nil {
		log.Printf("sending session probe: %v", err)
	}

	select {
	case <-time.After(h.cfg.GreetingSettle):
	case <-ctx.Done():
		h.exit(0)
		return
	}

	// The model only speaks when a response is created, so nudge the
	// greeting out rather than waiting for the caller's "hello?". The
	// token cap keeps the greeting from growing a monologue; output audio
	// runs ~20 tokens per spoken second, so 100 is ~5 seconds of speech.
	if err := conn.Send(ctx, map[string]any{
		"type": "response.create",
		"response": map[string]any{
			"instructions":      fmt.Sprintf("Say exactly this and then pause and wait to hear from the user: %q", h.cfg.Greeting),
			"max_output_tokens": 300,
		},
	}); err != nil {
		log.Printf("sending greeting: %v", err)
	}

	events := make(chan []byte)
	readErr := make(chan error, 1)
	go func() {
		defer close(events)
		for {
			data, err := conn.Read(ctx)
			if err != nil {
				readErr <- err
				return
			}
			events <- data
		}
	}()

	allowlist := time.NewTicker(allowlistInterval)
	defer allowlist.Stop()

	for {
		select {
		case data, ok := <-events:
			if !ok {
				err := <-readErr
				if ctx.Err() != nil {
					log.Printf("detaching: %v", context.Cause(ctx))
				} else {
					// The server closing the socket is how a finished call
					// looks from here.
					log.Printf("call %s ended (%v)", c.ID, err)
				}
				h.exit(0)
				return
			}
			handleEvent(data)

		case <-allowlist.C:
			allowed, err := contacts.AllowedNumbers(ctx)
			if err != nil {
				// A transient allowlist read failure must not end the call.
				log.Printf("allowlist re-check failed, keeping the call: %v", err)
				continue
			}
			if !allowed[c.Caller] {
				log.Printf("caller %s removed from allowlist, hanging up call %s", c.Caller, c.ID)
				if err := realtime.Hangup(h.cfg.APIKey, c.ID); err != nil {
					log.Printf("hangup for call %s: %v", c.ID, err)
				}
				h.exit(0)
				return
			}
		}
	}
}

// exit reports the process's exit code; only the first report counts.
func (h *Handler) exit(code int) {
	select {
	case h.done <- code:
	default:
	}
}

// handleEvent logs the events worth seeing; tool handling (function_call
// events, the Cassandra bridge) will grow here.
func handleEvent(data []byte) {
	event, err := realtime.ParseEvent(data)
	if err != nil {
		return
	}
	switch event.Type {
	case "session.created", "session.updated":
		// The echoed config shows exactly which instructions the live call
		// runs on — the whole system prompt, nothing hidden.
		log.Printf("%s: model=%s instructions=%q", event.Type, event.Session.Model, event.Session.Instructions)
	case "error":
		log.Printf("realtime error: %s", event.Error)
	case "response.done":
		log.Printf("response done: status=%s details=%s usage=%s",
			event.Response.Status, event.Response.StatusDetails, event.Response.Usage)
	}
}
