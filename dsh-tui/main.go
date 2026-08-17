package main

// dsh-tui: Bubble Tea frontend spike for the DeepSeek Harness SDK runtime.
// Speaks NDJSON JSON-RPC 2.0 to a dsh-jsonrpc-agent subprocess. -probe runs
// one headless turn and dumps every notification as NDJSON instead.

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/bubbles/textarea"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

func newSessionID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return "session-" + hex.EncodeToString(b)
}

func main() {
	probe := flag.Bool("probe", false, "headless: run one prompt, dump notifications as NDJSON, exit")
	prompt := flag.String("prompt", "", "prompt for -probe mode")
	provider := flag.String("provider", "deepseek-official", "provider route registered by the cordis composition")
	model := flag.String("model", envOr("DSH_MODEL", "deepseek-v4-flash"), "model id (also exported as DSH_MODEL for the minimal composition)")
	cordis := flag.String("cordis", "", "cordis config path (default: runtime's bundled cordis.yml)")
	workspace := flag.String("workspace", ".", "agent workspace directory")
	sessionRoot := flag.String("session-root", ".dsh-sessions", "JSONL session directory")
	session := flag.String("session", "", "session id to resume (default: new)")
	flag.Parse()

	rt, err := ResolveRuntime()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	ws, err := filepath.Abs(*workspace)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	sr, _ := filepath.Abs(*sessionRoot)
	config := *cordis
	if config == "" {
		config = envOr("DSH_CORDIS_CONFIG", rt.DefaultConfig)
	}
	config, _ = filepath.Abs(config)

	env := []string{
		"DSH_CORDIS_CONFIG=" + config,
		"DSH_CWD=" + ws,
		"DSH_SESSION_ROOT=" + sr,
		"DSH_MODEL=" + *model,
	}
	client, err := StartClient([]string{rt.Bin}, ws, env)
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to launch runtime:", err)
		os.Exit(1)
	}
	defer client.Close()
	if err := client.Initialize(ws, *provider, *model, 0); err != nil {
		fmt.Fprintln(os.Stderr, "initialize failed:", err)
		os.Exit(1)
	}

	sessionID := *session
	if sessionID == "" {
		sessionID = newSessionID()
	}

	if *probe {
		if err := runProbe(client, sessionID, *prompt); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	// Inline renderer, deliberately no alt screen: finalized lines are
	// committed to native scrollback unwrapped (tea.Println) so the
	// terminal soft-wraps them and native selection-copy re-joins them
	// (the finalization-emission design from oh-my-pi#7879). Only the
	// live region below — streaming preview, status, input — is
	// managed/pre-wrapped repainting.
	m := newModel(client, sessionID, *model)
	if _, err := tea.NewProgram(m).Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// runProbe drives one turn and prints the raw notification stream, one JSON
// object per line, until the session goes idle.
func runProbe(client *Client, sessionID, prompt string) error {
	if prompt == "" {
		prompt = "Reply with exactly: dsh-tui probe ok"
	}
	if _, err := client.Prompt(sessionID, prompt); err != nil {
		return fmt.Errorf("session/prompt failed: %w", err)
	}
	enc := json.NewEncoder(os.Stdout)
	for {
		select {
		case n := <-client.Notifications:
			enc.Encode(map[string]any{"method": n.Method, "params": n.Payload})
			if n.Method == "session.status" &&
				n.Payload["sessionId"] == sessionID &&
				n.Payload["status"] == "idle" {
				return nil
			}
		case r := <-client.Requests:
			enc.Encode(map[string]any{"incomingRequest": r.Method, "params": r.Payload})
			client.RespondError(r.ID, -32601, "dsh-tui probe: client-side method not supported")
		case err := <-client.Died:
			return err
		}
	}
}

// --- Bubble Tea model ---

type notifMsg Notification
type reqMsg IncomingRequest
type diedMsg struct{ err error }
type promptDoneMsg struct{ err error }

type uiModel struct {
	client    *Client
	sessionID string
	modelName string

	ta        textarea.Model
	streamBuf string // in-flight assistant text, live-region only
	raw       bool
	status    string
	events    int
	width     int
}

func newModel(client *Client, sessionID, modelName string) *uiModel {
	ta := textarea.New()
	ta.Placeholder = "Prompt (enter to send, ctrl+j for newline, ctrl+c to quit)"
	ta.SetHeight(3)
	ta.Focus()
	ta.ShowLineNumbers = false
	return &uiModel{
		client:    client,
		sessionID: sessionID,
		modelName: modelName,
		ta:        ta,
		status:    "ready",
	}
}

func (m *uiModel) listen() tea.Cmd {
	return func() tea.Msg {
		select {
		case n := <-m.client.Notifications:
			return notifMsg(n)
		case r := <-m.client.Requests:
			return reqMsg(r)
		case err := <-m.client.Died:
			return diedMsg{err}
		}
	}
}

func (m *uiModel) Init() tea.Cmd {
	return tea.Batch(textarea.Blink, m.listen())
}

// commit finalizes a logical line into native scrollback, unwrapped — the
// terminal soft-wraps it, so native selection-copy re-joins the rows.
// Each logical line ends with erase-to-end-of-row (CSI K): the live
// region's pre-wrapped rows may have painted where a committed line's
// final soft row ends, and any stale tail glyphs would be joined into the
// logical line by selection-copy.
func commit(line string) tea.Cmd {
	if line == "" {
		return nil
	}
	return tea.Println(strings.ReplaceAll(line, "\n", "\x1b[K\n") + "\x1b[K")
}

func (m *uiModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.ta.SetWidth(max(msg.Width-2, 1))
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "ctrl+r":
			m.raw = !m.raw
			return m, nil
		case "ctrl+j":
			m.ta.InsertString("\n")
			return m, nil
		case "enter":
			text := strings.TrimSpace(m.ta.Value())
			if text == "" {
				return m, nil
			}
			m.ta.Reset()
			m.status = "working"
			return m, tea.Batch(
				commit(styleUser.Render("you ▸ ")+text),
				func() tea.Msg {
					_, err := m.client.Prompt(m.sessionID, text)
					return promptDoneMsg{err}
				},
			)
		}

	case notifMsg:
		m.events++
		n := Notification(msg)
		cmds := []tea.Cmd{m.listen()}
		if n.Method == "session.status" && n.Payload["sessionId"] == m.sessionID {
			if s, ok := n.Payload["status"].(string); ok {
				m.status = s
			}
		}
		if delta := chunkDelta(n); delta != "" {
			m.streamBuf += delta
		}
		if line := summarize(n); line != "" {
			// summarize returns non-"" for assistant/message and turn/end
			// (among others): the stream is settled, drop the preview.
			m.streamBuf = ""
			cmds = append(cmds, commit(line))
		}
		if m.raw {
			cmds = append(cmds, commit(styleMeta.Render(
				compactJSON(map[string]any{"method": n.Method, "params": n.Payload}, 4000))))
		}
		return m, tea.Batch(cmds...)

	case reqMsg:
		m.client.RespondError(msg.ID, -32601, "dsh-tui spike: client-side method not supported")
		return m, tea.Batch(m.listen(),
			commit(styleErr.Render(fmt.Sprintf("? incoming request %s ", msg.Method))+compactJSON(msg.Payload, 300)))

	case promptDoneMsg:
		if msg.err != nil {
			m.status = "error"
			return m, commit(styleErr.Render("prompt failed: " + msg.err.Error()))
		}
		return m, nil

	case diedMsg:
		m.status = "dead"
		return m, commit(styleErr.Render("runtime died: " + msg.err.Error()))
	}

	var cmd tea.Cmd
	m.ta, cmd = m.ta.Update(msg)
	return m, cmd
}

var styleStatusBar = lipgloss.NewStyle().Faint(true)

const previewRows = 8

// View is the live region: streaming preview (pre-wrapped, erasable — never
// committed to the tape), status bar, input.
func (m *uiModel) View() string {
	preview := ""
	if m.streamBuf != "" {
		wrapped := lipgloss.NewStyle().Width(max(m.width, 20)).Render(
			styleAssistant.Render("dsh ▸ ") + m.streamBuf)
		rows := strings.Split(wrapped, "\n")
		if len(rows) > previewRows {
			rows = rows[len(rows)-previewRows:]
		}
		preview = strings.Join(rows, "\n") + "\n"
	}
	mode := ""
	if m.raw {
		mode = "  [raw]"
	}
	bar := styleStatusBar.Render(fmt.Sprintf(
		" %s  ·  %s  ·  %s  ·  %d events%s  ·  ctrl+r raw log",
		m.sessionID, m.modelName, m.status, m.events, mode))
	return preview + bar + "\n" + m.ta.View()
}
