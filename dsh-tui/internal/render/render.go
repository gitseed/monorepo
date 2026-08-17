// Package render turns runtime notifications into committed scrollback
// lines. Hierarchy: user prompts and assistant text are the content; tool
// activity is a one-line summary; protocol bookkeeping (steps, request
// headers, titles) is suppressed — the raw log has all of it.
//
// The contract every function here upholds: output is logical lines only.
// Styling is inline SGR, never width-wrapping, so the scrollback-commit
// copy semantics hold (the terminal soft-wraps; selection-copy re-joins).
// Styles never nest — an inner reset kills any outer color for the rest of
// the line — so styled spans are self-contained islands in default-fg text.
// Fence delimiters and interiors are byte-exact; prose lines may apply
// display transforms (span backticks drop, bullets become •).
package render

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"github.com/gitseed/monorepo/dsh-tui/internal/harness"
)

var (
	colAccent = lipgloss.AdaptiveColor{Light: "26", Dark: "75"}  // user prompt
	colMark   = lipgloss.AdaptiveColor{Light: "29", Dark: "115"} // assistant bullet
	ColTool   = lipgloss.AdaptiveColor{Light: "94", Dark: "179"} // tool name
	colDim    = lipgloss.AdaptiveColor{Light: "245", Dark: "243"}
	colErr    = lipgloss.AdaptiveColor{Light: "124", Dark: "203"}
	colCode   = lipgloss.AdaptiveColor{Light: "90", Dark: "216"}

	StyleUser   = lipgloss.NewStyle().Foreground(colAccent).Bold(true)
	StyleMark   = lipgloss.NewStyle().Foreground(colMark)
	StyleTool   = lipgloss.NewStyle().Foreground(ColTool)
	StyleDim    = lipgloss.NewStyle().Foreground(colDim)
	StyleErr    = lipgloss.NewStyle().Foreground(colErr)
	styleCode   = lipgloss.NewStyle().Foreground(colCode)
	StyleItalic = lipgloss.NewStyle().Foreground(colDim).Italic(true)
)

// Kept for the raw log and diagnostics lines.
var StyleMeta = StyleDim

func CompactJSON(v any, max int) string {
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
func TextContent(data map[string]any) string {
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
func ChunkDelta(n harness.Notification) string {
	event := EventOf(n)
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

// toolDelta extracts a streaming tool-call fragment from an assistant/chunk
// tool-call-delta notification; ok is false otherwise. The runtime streams
// the arguments JSON over several chunks while the model generates it.
func ToolDelta(n harness.Notification) (name, delta string, ok bool) {
	event := EventOf(n)
	if event == nil || event["type"] != "assistant/chunk" {
		return "", "", false
	}
	data, _ := event["data"].(map[string]any)
	chunk, _ := data["chunk"].(map[string]any)
	if chunk["type"] != "tool-call-delta" {
		return "", "", false
	}
	name, _ = chunk["name"].(string)
	delta, _ = chunk["argumentsDelta"].(string)
	return name, delta, true
}

// usageFrom extracts per-step token usage from an assistant/chunk usage
// event; ok is false otherwise.
func UsageFrom(n harness.Notification) (in, out int, ok bool) {
	event := EventOf(n)
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

func EventOf(n harness.Notification) map[string]any {
	if n.Method != "session.event" {
		return nil
	}
	event, _ := n.Payload["event"].(map[string]any)
	return event
}

var (
	reBold   = regexp.MustCompile(`\*\*([^*]+)\*\*`)
	reItalic = regexp.MustCompile(`\*([^*]+)\*`)
	reCode   = regexp.MustCompile("`([^`]+)`")
	reBullet = regexp.MustCompile(`^(\s*)[-*] `)
	reHeader = regexp.MustCompile(`^#{1,4} `)
	reFence  = regexp.MustCompile("^\\s*```")
	reQuote  = regexp.MustCompile(`^\s*> `)
)

// mdInline applies inline markdown styling per logical line — colors and
// weights only, never reflow, so commit()'s copy semantics survive. The
// body text deliberately stays the terminal's default foreground: lipgloss
// styles don't nest (an inner reset kills any outer color for the rest of
// the line), so styled spans must be self-contained islands in unstyled
// text — which is also what keeps the body readable on any theme.
func MdInline(text string) string {
	lines := strings.Split(text, "\n")
	boldStyle := lipgloss.NewStyle().Bold(true)
	italicStyle := lipgloss.NewStyle().Italic(true)
	inFence := false
	for i, line := range lines {
		switch {
		case reFence.MatchString(line):
			// The literal ``` stays in the text (copy fidelity); only dim it.
			inFence = !inFence
			line = StyleDim.Render(line)
		case inFence:
			// No markdown transforms inside a fence — code is code.
			line = styleCode.Render(line)
		case reQuote.MatchString(line):
			line = StyleItalic.Render(line)
		case reHeader.MatchString(line):
			line = boldStyle.Render(reHeader.ReplaceAllString(line, ""))
		default:
			line = reCode.ReplaceAllString(line, styleCode.Render("$1"))
			line = reBold.ReplaceAllStringFunc(line, func(m string) string {
				return boldStyle.Render(reBold.FindStringSubmatch(m)[1])
			})
			line = reItalic.ReplaceAllStringFunc(line, func(m string) string {
				return italicStyle.Render(reItalic.FindStringSubmatch(m)[1])
			})
			line = reBullet.ReplaceAllString(line, "$1"+StyleMark.Render("•")+" ")
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
				detail = CompactJSON(args, 120)
			}
		}
	}
	detail = strings.ReplaceAll(detail, "\n", " ⏎ ")
	if len(detail) > 120 {
		detail = detail[:120] + "…"
	}
	return StyleTool.Render("▸ "+name) + "  " + StyleDim.Render(detail)
}

// toolResultLines renders up to two dim lines of output plus a count of
// what was elided.
func toolResultLines(data map[string]any) string {
	text := strings.TrimRight(TextContent(data), "\n")
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
						text = strings.TrimRight(TextContent(map[string]any{"content": inner}), "\n")
					}
				}
			}
		}
	}
	if text == "" {
		return ""
	}
	style := StyleDim
	if isErr {
		style = StyleErr
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
		out += "\n" + StyleDim.Render(fmt.Sprintf("  … +%d lines", len(lines)-2))
	}
	return out
}

// summarize renders one notification as committed lines, or "" to drop it.
func Summarize(n harness.Notification) string {
	switch n.Method {
	case "session.status":
		return "" // lives in the status bar
	case "subagent.started":
		return StyleDim.Render(fmt.Sprintf("▸ subagent %v", n.Payload["childSessionId"]))
	case "subagent.finished":
		return StyleDim.Render(fmt.Sprintf("▪ subagent done %v", n.Payload["childSessionId"]))
	case "session.event":
	default:
		return StyleDim.Render(fmt.Sprintf("· %s %s", n.Method, CompactJSON(n.Payload, 200)))
	}

	event := EventOf(n)
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
		if text := TextContent(data); text != "" {
			return "\n" + StyleUser.Render("❯ "+strings.ReplaceAll(text, "\n", "\n  "))
		}
		return ""
	case "assistant/message":
		if text := strings.TrimRight(TextContent(data), "\n"); text != "" {
			return "\n" + StyleMark.Render("● ") + MdInline(text)
		}
		return "" // tool-call-only message; tool/call renders it
	case "tool/call":
		return toolCallLine(data)
	case "tool/result":
		return toolResultLines(data)
	case "assistant/chunk":
		chunk, _ := data["chunk"].(map[string]any)
		if reason, ok := chunk["reason"].(map[string]any); ok && reason["kind"] == "error" {
			return StyleErr.Render("✗ model error ") + CompactJSON(reason, 400)
		}
		return ""
	case "turn/end":
		if reason, ok := data["reason"].(map[string]any); ok {
			if kind, _ := reason["kind"].(string); kind != "completed" && kind != "" {
				return StyleErr.Render(fmt.Sprintf("✗ turn ended: %s ", kind)) + StyleDim.Render(CompactJSON(reason, 300))
			}
		}
		return ""
	case "turn/start", "step/start", "step/end", "request/header", "request/context",
		"session/title", "agent/inbox/spliced":
		return ""
	default:
		return StyleDim.Render(fmt.Sprintf("· %s %s", typ, CompactJSON(data, 160)))
	}
}
