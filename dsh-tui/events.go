package main

// Turns runtime notifications into committed scrollback lines. Hierarchy:
// user prompts and assistant text are the content; tool activity is a
// one-line summary; protocol bookkeeping (steps, request headers, titles)
// is suppressed — ctrl+r's raw log has all of it. Every returned string is
// logical lines only: styling is inline SGR, never width-wrapping, so the
// scrollback-commit copy semantics hold.

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var (
	colAccent = lipgloss.AdaptiveColor{Light: "26", Dark: "75"}   // user prompt
	colText   = lipgloss.AdaptiveColor{Light: "235", Dark: "252"} // assistant text
	colMark   = lipgloss.AdaptiveColor{Light: "29", Dark: "115"}  // assistant bullet
	colTool   = lipgloss.AdaptiveColor{Light: "94", Dark: "179"}  // tool name
	colDim    = lipgloss.AdaptiveColor{Light: "245", Dark: "243"}
	colErr    = lipgloss.AdaptiveColor{Light: "124", Dark: "203"}
	colCode   = lipgloss.AdaptiveColor{Light: "90", Dark: "216"}

	styleUser   = lipgloss.NewStyle().Foreground(colAccent).Bold(true)
	styleText   = lipgloss.NewStyle().Foreground(colText)
	styleMark   = lipgloss.NewStyle().Foreground(colMark)
	styleTool   = lipgloss.NewStyle().Foreground(colTool)
	styleDim    = lipgloss.NewStyle().Foreground(colDim)
	styleErr    = lipgloss.NewStyle().Foreground(colErr)
	styleCode   = lipgloss.NewStyle().Foreground(colCode)
	styleItalic = lipgloss.NewStyle().Foreground(colDim).Italic(true)
)

// Kept for the raw log and diagnostics lines.
var styleMeta = styleDim

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

// textContent joins the text blocks of a message event, handling both
// data.message.content and data.content layouts (same fallback as the
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
	event := eventOf(n)
	if event == nil || event["type"] != "assistant/chunk" {
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

// usageFrom extracts per-step token usage from an assistant/chunk usage
// event; ok is false otherwise.
func usageFrom(n Notification) (in, out int, ok bool) {
	event := eventOf(n)
	if event == nil || event["type"] != "assistant/chunk" {
		return 0, 0, false
	}
	data, _ := event["data"].(map[string]any)
	chunk, _ := data["chunk"].(map[string]any)
	usage, uok := chunk["usage"].(map[string]any)
	if chunk["type"] != "usage" || !uok {
		return 0, 0, false
	}
	i, _ := usage["inputTokens"].(float64)
	o, _ := usage["outputTokens"].(float64)
	return int(i), int(o), true
}

func eventOf(n Notification) map[string]any {
	if n.Method != "session.event" {
		return nil
	}
	event, _ := n.Payload["event"].(map[string]any)
	return event
}

var (
	reBold   = regexp.MustCompile(`\*\*([^*]+)\*\*`)
	reCode   = regexp.MustCompile("`([^`]+)`")
	reBullet = regexp.MustCompile(`^(\s*)[-*] `)
	reHeader = regexp.MustCompile(`^#{1,4} `)
)

// mdInline applies inline markdown styling per logical line — colors and
// weights only, never reflow, so commit()'s copy semantics survive. The
// body text deliberately stays the terminal's default foreground: lipgloss
// styles don't nest (an inner reset kills any outer color for the rest of
// the line), so styled spans must be self-contained islands in unstyled
// text — which is also what keeps the body readable on any theme.
func mdInline(text string) string {
	lines := strings.Split(text, "\n")
	boldStyle := lipgloss.NewStyle().Bold(true)
	for i, line := range lines {
		switch {
		case reHeader.MatchString(line):
			line = boldStyle.Render(reHeader.ReplaceAllString(line, ""))
		default:
			line = reCode.ReplaceAllString(line, styleCode.Render("$1"))
			line = reBold.ReplaceAllStringFunc(line, func(m string) string {
				return boldStyle.Render(reBold.FindStringSubmatch(m)[1])
			})
			line = reBullet.ReplaceAllString(line, "$1"+styleMark.Render("•")+" ")
		}
		lines[i] = line
	}
	return strings.Join(lines, "\n")
}

// toolCallLine renders "▸ name  detail" — for bash, the actual command.
func toolCallLine(data map[string]any) string {
	name, _ := data["name"].(string)
	detail := ""
	if rawArgs, ok := data["arguments"].(string); ok {
		var args map[string]any
		if json.Unmarshal([]byte(rawArgs), &args) == nil {
			if cmd, ok := args["command"].(string); ok {
				detail = cmd
			} else {
				detail = compactJSON(args, 120)
			}
		}
	}
	detail = strings.ReplaceAll(detail, "\n", " ⏎ ")
	if len(detail) > 120 {
		detail = detail[:120] + "…"
	}
	return styleTool.Render("▸ "+name) + "  " + styleDim.Render(detail)
}

// toolResultLines renders up to two dim lines of output plus a count of
// what was elided.
func toolResultLines(data map[string]any) string {
	text := strings.TrimRight(textContent(data), "\n")
	isErr := false
	if msg, ok := data["message"].(map[string]any); ok {
		if blocks, ok := msg["content"].([]any); ok {
			for _, b := range blocks {
				if block, ok := b.(map[string]any); ok {
					if e, ok := block["isError"].(bool); ok && e {
						isErr = true
					}
					// tool-result blocks nest their text one level deeper.
					if inner, ok := block["content"].([]any); ok {
						text = strings.TrimRight(textContent(map[string]any{"content": inner}), "\n")
					}
				}
			}
		}
	}
	if text == "" {
		return ""
	}
	style := styleDim
	if isErr {
		style = styleErr
	}
	lines := strings.Split(text, "\n")
	shown := lines
	if len(shown) > 2 {
		shown = shown[:2]
	}
	for i, l := range shown {
		shown[i] = style.Render("  " + l)
	}
	out := strings.Join(shown, "\n")
	if len(lines) > 2 {
		out += "\n" + styleDim.Render(fmt.Sprintf("  … +%d lines", len(lines)-2))
	}
	return out
}

// summarize renders one notification as committed lines, or "" to drop it.
func summarize(n Notification) string {
	switch n.Method {
	case "session.status":
		return "" // lives in the status bar
	case "subagent.started":
		return styleDim.Render(fmt.Sprintf("▸ subagent %v", n.Payload["childSessionId"]))
	case "subagent.finished":
		return styleDim.Render(fmt.Sprintf("▪ subagent done %v", n.Payload["childSessionId"]))
	case "session.event":
	default:
		return styleDim.Render(fmt.Sprintf("· %s %s", n.Method, compactJSON(n.Payload, 200)))
	}

	event := eventOf(n)
	if event == nil {
		return ""
	}
	typ, _ := event["type"].(string)
	data, _ := event["data"].(map[string]any)
	switch typ {
	case "user/message":
		// Tool results also arrive as user-role messages; tool/result
		// already rendered them.
		if msg, ok := data["message"].(map[string]any); ok {
			if src, ok := msg["source"].(map[string]any); ok && src["kind"] == "tool" {
				return ""
			}
		}
		if src, ok := data["source"].(map[string]any); ok && src["kind"] != "user" {
			return ""
		}
		if text := textContent(data); text != "" {
			return "\n" + styleUser.Render("❯ "+strings.ReplaceAll(text, "\n", "\n  "))
		}
		return ""
	case "assistant/message":
		if text := strings.TrimRight(textContent(data), "\n"); text != "" {
			return "\n" + styleMark.Render("● ") + mdInline(text)
		}
		return "" // tool-call-only message; tool/call renders it
	case "tool/call":
		return toolCallLine(data)
	case "tool/result":
		return toolResultLines(data)
	case "assistant/chunk":
		chunk, _ := data["chunk"].(map[string]any)
		if reason, ok := chunk["reason"].(map[string]any); ok && reason["kind"] == "error" {
			return styleErr.Render("✗ model error ") + compactJSON(reason, 400)
		}
		return ""
	case "turn/end":
		if reason, ok := data["reason"].(map[string]any); ok {
			if kind, _ := reason["kind"].(string); kind != "completed" && kind != "" {
				return styleErr.Render(fmt.Sprintf("✗ turn ended: %s ", kind)) + styleDim.Render(compactJSON(reason, 300))
			}
		}
		return ""
	case "turn/start", "step/start", "step/end", "request/header", "request/context",
		"session/title", "agent/inbox/spliced":
		return ""
	default:
		return styleDim.Render(fmt.Sprintf("· %s %s", typ, compactJSON(data, 160)))
	}
}
