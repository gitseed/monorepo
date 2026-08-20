// Package contacts reads the caller allowlist. The container holds no
// Cloudflare credentials: its plain-HTTP request to the contacts.internal
// virtual host is intercepted by the voice Worker's outbound handler and
// answered from the contacts KV namespace. The allowlist stays a
// Worker-side concern, and a number change lands on the next check.
package contacts

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// AllowedNumbers returns the E.164 numbers currently authorized to talk to
// Veronica.
func AllowedNumbers(ctx context.Context) (map[string]bool, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet,
		"http://contacts.internal/allowlist", nil)
	if err != nil {
		return nil, err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 2048))
		return nil, fmt.Errorf("allowlist: %d %s", response.StatusCode, body)
	}
	var numbers []string
	if err := json.NewDecoder(response.Body).Decode(&numbers); err != nil {
		return nil, err
	}
	allowed := make(map[string]bool, len(numbers))
	for _, number := range numbers {
		allowed[number] = true
	}
	return allowed, nil
}
