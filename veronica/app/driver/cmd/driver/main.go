// Command driver is Veronica's session driver: one Cloudflare Container
// per phone call, existing only while its call does.
//
// The voice Worker screens each incoming call, then dispatches {call_id,
// caller} to this container's POST /call — starting the container is what
// the dispatch does, so this process boots knowing nothing and learns its
// call from that first request. The pickup happens here: the accept (which
// stops the caller's ringing) and the sideband WebSocket attach both run
// inside the /call request, so the driver is on the line for the call's
// entire life — the audio itself flows Twilio<->OpenAI over SIP and never
// touches this process. When the call ends the process exits, and with it
// the container: nothing runs, or bills, between calls.
//
// The work is split across the internal packages: realtime is the OpenAI
// client, contacts reads the allowlist back through the Worker, and
// session is the driver's actual flow. This command only turns the
// environment into a session.Config and serves it — listening immediately,
// before any call-specific work, because the Worker's dispatch is already
// waiting on the port.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/paulcdejean/veronica/driver/internal/session"
)

func main() {
	log.SetFlags(0) // Workers Logs supplies timestamps.

	cfg, err := configFromEnv()
	if err != nil {
		log.Fatalf("session driver failed: %v", err)
	}

	handler := session.NewHandler(cfg)
	server := &http.Server{Addr: ":8080", Handler: handler}
	go func() {
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("session driver failed: %v", err)
		}
	}()

	// The handler reports the call's end (or a failure that should hand
	// the container back to the platform); exiting stops the container.
	// Shutdown first so an in-flight /call response reaches the Worker.
	code := <-handler.Done()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
	os.Exit(code)
}

func configFromEnv() (session.Config, error) {
	cfg := session.Config{
		APIKey:       os.Getenv("OPENAI_API_KEY"),
		Greeting:     os.Getenv("VOICE_GREETING"),
		Model:        os.Getenv("VOICE_MODEL"),
		Voice:        os.Getenv("VOICE_VOICE"),
		Instructions: os.Getenv("VOICE_INSTRUCTIONS"),
	}
	for name, value := range map[string]string{
		"OPENAI_API_KEY":           cfg.APIKey,
		"VOICE_GREETING":           cfg.Greeting,
		"VOICE_MODEL":              cfg.Model,
		"VOICE_VOICE":              cfg.Voice,
		"VOICE_INSTRUCTIONS":       cfg.Instructions,
		"VOICE_GREETING_SETTLE_MS": os.Getenv("VOICE_GREETING_SETTLE_MS"),
	} {
		if value == "" {
			return session.Config{}, fmt.Errorf("%s must be set", name)
		}
	}
	settle, err := strconv.Atoi(os.Getenv("VOICE_GREETING_SETTLE_MS"))
	if err != nil || settle < 0 {
		return session.Config{}, fmt.Errorf("VOICE_GREETING_SETTLE_MS must be a non-negative integer, got %q", os.Getenv("VOICE_GREETING_SETTLE_MS"))
	}
	cfg.GreetingSettle = time.Duration(settle) * time.Millisecond
	return cfg, nil
}
