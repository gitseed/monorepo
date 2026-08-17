package main

// Turns runtime notifications into display lines. The event vocabulary is
// being discovered by this spike, so unrecognized shapes fall through to a
// dimmed type + truncated payload line rather than being dropped.

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var (
	styleAssistant = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "22", Dark: "115"})
	styleTool      = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "94", Dark: "179"})
	styleMeta      = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "245", Dark: "243"})
	styleErr       = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "124", Dark: "203"})
	styleUser      = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "25", Dark: "111"}).Bold(true)
)

func compactJSON(v any, max int) string {
	b, err := json.Marshal(v)
	if err != nil {
		return fmt.Sprintf("%v", v)
	}
	s := string(b)
	if len(s) > max {
		s = s[:max] + "…"
	}
	return s
}

// textContent joins the text blocks of an assistant/message event, handling
// both data.message.content and data.content layouts (same fallback as the
// Python SDK's final_response).
func textContent(data map[string]any) string {
	owner := data
	if msg, ok := data["message"].(map[string]any); ok {
		owner = msg
	}
	blocks, ok := owner["content"].([]any)
	if !ok {
		return ""
	}
	var parts []string
	for _, b := range blocks {
		block, ok := b.(map[string]any)
		if !ok {
			continue
		}
		if block["type"] == "text" {
			if t, ok := block["text"].(string); ok {
				parts = append(parts, t)
			}
		}
	}
	return strings.Join(parts, "")
}

// chunkDelta extracts streaming text from an assistant/chunk notification,
// or "" — feeds the live-region preview.
func chunkDelta(n Notification) string {
	if n.Method != "session.event" {
		return ""
	}
	event, ok := n.Payload["event"].(map[string]any)
	if !ok || event["type"] != "assistant/chunk" {
		return ""
	}
	data, _ := event["data"].(map[string]any)
	chunk, _ := data["chunk"].(map[string]any)
	if chunk["type"] != "text-delta" {
		return ""
	}
	text, _ := chunk["text"].(string)
	return text
}

// summarize renders one notification, or returns "" to drop it.
func summarize(n Notification) string {
	switch n.Method {
	case "session.status":
		status, _ := n.Payload["status"].(string)
		return styleMeta.Render(fmt.Sprintf("· status: %s", status))
	case "subagent.started":
		return styleMeta.Render(fmt.Sprintf("· subagent started: %v → %v",
			n.Payload["parentSessionId"], n.Payload["childSessionId"]))
	case "subagent.finished":
		return styleMeta.Render(fmt.Sprintf("· subagent finished: %v", n.Payload["childSessionId"]))
	case "session.event":
		event, ok := n.Payload["event"].(map[string]any)
		if !ok {
			break
		}
		typ, _ := event["type"].(string)
		data, _ := event["data"].(map[string]any)
		switch {
		case typ == "assistant/message":
			if text := textContent(data); text != "" {
				return styleAssistant.Render("dsh ▸ ") + strings.TrimRight(text, "\n")
			}
			return styleMeta.Render("· assistant/message (no text) " + compactJSON(data, 200))
		case typ == "assistant/chunk":
			// Streaming deltas; the full text lands as assistant/message.
			// Only failures are worth a line — see the rest with ctrl+r.
			chunk, _ := data["chunk"].(map[string]any)
			if reason, ok := chunk["reason"].(map[string]any); ok && reason["kind"] == "error" {
				return styleErr.Render("✗ model error ") + compactJSON(reason, 400)
			}
			return ""
		case typ == "turn/end":
			kind := "?"
			if reason, ok := data["reason"].(map[string]any); ok {
				kind, _ = reason["kind"].(string)
			}
			line := fmt.Sprintf("— turn end (%s)", kind)
			if kind == "error" {
				return styleErr.Render(line + " " + compactJSON(data, 400))
			}
			return styleMeta.Render(line)
		case typ == "agent/inbox/spliced":
			return "" // our own prompt echoing back
		case strings.Contains(typ, "tool"):
			return styleTool.Render(fmt.Sprintf("⚙ %s ", typ)) + compactJSON(data, 200)
		default:
			return styleMeta.Render(fmt.Sprintf("· %s %s", typ, compactJSON(data, 200)))
		}
	}
	return styleMeta.Render(fmt.Sprintf("· %s %s", n.Method, compactJSON(n.Payload, 200)))
}
