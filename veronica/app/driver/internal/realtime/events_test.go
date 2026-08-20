package realtime

import "testing"

func TestParseEvent(t *testing.T) {
	data := []byte(`{
		"type": "session.updated",
		"session": {"model": "gpt-realtime-2.1-mini", "instructions": "You are Veronica."},
		"response": {"status": "completed", "usage": {"output_tokens": 28}}
	}`)
	event, err := ParseEvent(data)
	if err != nil {
		t.Fatalf("ParseEvent() error: %v", err)
	}
	if event.Type != "session.updated" {
		t.Errorf("Type = %q, want session.updated", event.Type)
	}
	if event.Session.Model != "gpt-realtime-2.1-mini" {
		t.Errorf("Session.Model = %q", event.Session.Model)
	}
	if event.Session.Instructions != "You are Veronica." {
		t.Errorf("Session.Instructions = %q", event.Session.Instructions)
	}
	if string(event.Response.Usage) != `{"output_tokens": 28}` {
		t.Errorf("Response.Usage = %s", event.Response.Usage)
	}
}
