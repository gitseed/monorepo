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
	"github.com/charmbracelet/bubbles/viewport"
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

	m := newModel(client, sessionID, *model)
	if _, err := tea.NewProgram(m, tea.WithAltScreen()).Run(); err != nil {
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

	vp     viewport.Model
	ta     textarea.Model
	lines  []string
	rawLog []string
	raw    bool
	status string
	events int
	ready  bool
	fatal  error
	width  int
	height int
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

func (m *uiModel) push(line string) {
	if line == "" {
		return
	}
	m.lines = append(m.lines, line)
	m.refresh()
}

func (m *uiModel) refresh() {
	content := m.lines
	if m.raw {
		content = m.rawLog
	}
	m.vp.SetContent(lipgloss.NewStyle().Width(m.vp.Width).Render(strings.Join(content, "\n")))
	m.vp.GotoBottom()
}

func (m *uiModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		// A pty can report zero size before its first real resize; a
		// negative height panics the viewport.
		vpHeight := max(msg.Height-m.ta.Height()-3, 1)
		vpWidth := max(msg.Width, 1)
		if !m.ready {
			m.vp = viewport.New(vpWidth, vpHeight)
			m.ready = true
		} else {
			m.vp.Width, m.vp.Height = vpWidth, vpHeight
		}
		m.ta.SetWidth(max(msg.Width-2, 1))
		m.refresh()
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "ctrl+r":
			m.raw = !m.raw
			m.refresh()
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
			m.push(styleUser.Render("you ▸ ") + text)
			m.status = "working"
			return m, func() tea.Msg {
				_, err := m.client.Prompt(m.sessionID, text)
				return promptDoneMsg{err}
			}
		}

	case notifMsg:
		m.events++
		n := Notification(msg)
		m.rawLog = append(m.rawLog, compactJSON(map[string]any{"method": n.Method, "params": n.Payload}, 4000))
		if n.Method == "session.status" && n.Payload["sessionId"] == m.sessionID {
			if s, ok := n.Payload["status"].(string); ok {
				m.status = s
			}
		}
		m.push(summarize(n))
		if m.raw {
			m.refresh()
		}
		return m, m.listen()

	case reqMsg:
		m.push(styleErr.Render(fmt.Sprintf("? incoming request %s ", msg.Method)) + compactJSON(msg.Payload, 300))
		m.client.RespondError(msg.ID, -32601, "dsh-tui spike: client-side method not supported")
		return m, m.listen()

	case promptDoneMsg:
		if msg.err != nil {
			m.status = "error"
			m.push(styleErr.Render("prompt failed: " + msg.err.Error()))
		}
		return m, nil

	case diedMsg:
		m.fatal = msg.err
		m.push(styleErr.Render("runtime died: " + msg.err.Error()))
		m.status = "dead"
		return m, nil
	}

	var cmds []tea.Cmd
	var cmd tea.Cmd
	m.ta, cmd = m.ta.Update(msg)
	cmds = append(cmds, cmd)
	m.vp, cmd = m.vp.Update(msg)
	cmds = append(cmds, cmd)
	return m, tea.Batch(cmds...)
}

var styleStatusBar = lipgloss.NewStyle().Faint(true)

func (m *uiModel) View() string {
	if !m.ready {
		return "starting…"
	}
	mode := ""
	if m.raw {
		mode = "  [raw]"
	}
	bar := styleStatusBar.Render(fmt.Sprintf(
		" %s  ·  %s  ·  %s  ·  %d events%s  ·  ctrl+r raw view",
		m.sessionID, m.modelName, m.status, m.events, mode))
	return m.vp.View() + "\n" + bar + "\n" + m.ta.View()
}
