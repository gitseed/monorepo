package realtime

import "encoding/json"

// Event is the union of the server-event fields the driver reads; unknown
// event types decode with just Type set. The raw fields (error, response
// details, usage) are relogged verbatim rather than modeled.
type Event struct {
	Type    string          `json:"type"`
	Error   json.RawMessage `json:"error"`
	Session struct {
		Model        string `json:"model"`
		Instructions string `json:"instructions"`
	} `json:"session"`
	Response struct {
		Status        string          `json:"status"`
		StatusDetails json.RawMessage `json:"status_details"`
		Usage         json.RawMessage `json:"usage"`
	} `json:"response"`
}

// ParseEvent decodes one server event.
func ParseEvent(data []byte) (Event, error) {
	var event Event
	err := json.Unmarshal(data, &event)
	return event, err
}
