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
	"time"

	"github.com/charmbracelet/bubbles/cursor"
	"github.com/charmbracelet/bubbles/spinner"
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
	replay := flag.String("replay", "", "replay a captured -probe NDJSON stream instead of launching a runtime")
	flag.Parse()

	sessionID := *session
	if sessionID == "" {
		sessionID = newSessionID()
	}

	var c conn
	var lc *launcher
	if *replay != "" {
		rc, err := startReplay(*replay)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		c = rc
	} else {
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

		lc = &launcher{
			bin: rt.Bin,
			ws:  ws,
			env: []string{
				"DSH_CORDIS_CONFIG=" + config,
				"DSH_CWD=" + ws,
				"DSH_SESSION_ROOT=" + sr,
				"DSH_MODEL=" + *model,
			},
			provider: *provider,
			model:    *model,
		}
		client, err := lc.start()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer client.Close()
		if *probe {
			if err := runProbe(client, sessionID, *prompt); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			return
		}
		c = client
	}

	// Inline renderer, deliberately no alt screen: finalized lines are
	// committed to native scrollback unwrapped (tea.Println) so the
	// terminal soft-wraps them and native selection-copy re-joins them
	// (the finalization-emission design from oh-my-pi#7879). Only the
	// live region below — streaming preview, status, input — is
	// managed/pre-wrapped repainting.
	m := newModel(c, sessionID, *model)
	m.launch = lc
	if lc != nil {
		sr, _ := filepath.Abs(*sessionRoot)
		trans := newTranscript(sr, sessionID)
		if *session != "" {
			renderResume(trans.path)
		}
		m.trans = trans
	}
	p := tea.NewProgram(m)
	m.program = p
	go pump(p, c)
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// conn is what the UI needs from a session backend: the real jsonrpc
// runtime (Client) or a canned replay (replayConn).
type conn interface {
	Prompt(sessionID, text string) (string, error)
	RespondError(id json.RawMessage, code int, message string) error
	Kill()
	NotifCh() <-chan Notification
	ReqCh() <-chan IncomingRequest
	DiedCh() <-chan error
}

// launcher restarts the runtime with the same config — the interrupt path
// (kill + relaunch) needs it, and it keeps main() as the only other caller.
type launcher struct {
	bin      string
	ws       string
	env      []string
	provider string
	model    string
}

func (l *launcher) start() (*Client, error) {
	client, err := StartClient([]string{l.bin}, l.ws, l.env)
	if err != nil {
		return nil, fmt.Errorf("failed to launch runtime: %w", err)
	}
	if err := client.Initialize(l.ws, l.provider, l.model, 0); err != nil {
		client.Close()
		return nil, fmt.Errorf("initialize failed: %w", err)
	}
	return client, nil
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
type disarmMsg struct{}

// pendingPrompt is a prompt awaiting its user/message echo; queued marks
// ones sent while a turn was already running (steering).
type pendingPrompt struct {
	text   string
	queued bool
}
type restartedMsg struct {
	client *Client
	err    error
}

type uiModel struct {
	client    conn
	sessionID string
	modelName string

	ta        textarea.Model
	spin      spinner.Model
	toolName  string          // in-flight tool call, live-region only
	toolBuf   string          // its arguments JSON, streamed
	streamBuf string          // in-flight assistant text, live-region only
	pending   []pendingPrompt // sent but not yet echoed back by the runtime
	raw       bool
	status    string
	note      string // transient status-bar hint
	events    int
	tokIn     int
	tokOut    int
	ctxWindow int    // from request/context
	ctxUsed   int    // latest step's input+output tokens ~ occupancy
	title     string // from session/title
	turnStart time.Time
	width     int

	program    *tea.Program
	launch     *launcher   // nil in replay mode
	trans      *transcript // nil in replay mode
	armed      bool        // first esc pressed, second interrupts
	restarting bool        // runtime killed on purpose, relaunch under way
}

func newModel(client conn, sessionID, modelName string) *uiModel {
	ta := textarea.New()
	ta.Placeholder = "Message dsh — enter sends · ctrl+j newline · esc interrupts · /quit"
	ta.SetHeight(1)
	ta.Focus()
	ta.ShowLineNumbers = false
	ta.Prompt = "❯ "
	ta.FocusedStyle.Prompt = styleUser
	ta.BlurredStyle.Prompt = styleDim
	ta.FocusedStyle.CursorLine = lipgloss.NewStyle()
	ta.Cursor.SetMode(cursor.CursorStatic)
	sp := spinner.New(spinner.WithSpinner(spinner.MiniDot))
	sp.Style = lipgloss.NewStyle().Foreground(colTool)
	return &uiModel{
		client:    client,
		sessionID: sessionID,
		modelName: modelName,
		ta:        ta,
		spin:      sp,
		status:    "ready",
	}
}

// pump forwards a conn's channels into the program. Unlike a listen-cmd
// per message, Send drains as fast as events arrive, so a tool-output
// burst can't fill the client's channel and backpressure the runtime's
// stdout reader. Exits after the conn dies (a restart starts a new pump).
func pump(p *tea.Program, c conn) {
	for {
		select {
		case n := <-c.NotifCh():
			p.Send(notifMsg(n))
		case r := <-c.ReqCh():
			p.Send(reqMsg(r))
		case err := <-c.DiedCh():
			p.Send(diedMsg{err})
			return
		}
	}
}

func (m *uiModel) Init() tea.Cmd {
	return nil
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
		case "esc", "ctrl+c":
			// ctrl+c is esc, per Paul: interrupt when working, clear the
			// input when idle. Quitting is /quit — never a control chord.
			return m.escape()
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
			switch text {
			case "/quit", "/exit", "exit", "quit":
				return m, tea.Quit
			case "/help":
				m.ta.Reset()
				return m, commit(styleDim.Render(strings.Join([]string{
					"",
					"enter    send (mid-turn = steering, queues into the inbox)",
					"ctrl+j   newline",
					"esc esc  interrupt the running turn (ctrl+c = esc)",
					"ctrl+r   raw NDJSON logging of subsequent events",
					"/quit    exit (also /exit, exit)",
					"/help    this",
				}, "\n")))
			}
			if strings.HasPrefix(text, "/") {
				m.note = "unknown command " + text
				m.ta.Reset()
				return m, nil
			}
			m.ta.Reset()
			m.status = "working"
			m.note = ""
			// The user line commits when the runtime echoes it back as a
			// user/message event; until then it shows in the live region.
			m.pending = append(m.pending, pendingPrompt{text: text, queued: m.working()})
			return m, tea.Batch(
				m.spin.Tick,
				func() tea.Msg {
					_, err := m.client.Prompt(m.sessionID, text)
					return promptDoneMsg{err}
				},
			)
		}

	case disarmMsg:
		m.armed = false
		if m.note == "esc again to interrupt" {
			m.note = ""
		}
		return m, nil

	case restartedMsg:
		m.restarting = false
		if msg.err != nil {
			m.status = "dead"
			return m, commit(styleErr.Render("restart failed: " + msg.err.Error()))
		}
		m.client = msg.client
		m.status = "idle"
		m.note = ""
		go pump(m.program, m.client)
		return m, nil

	case spinner.TickMsg:
		if m.working() {
			var cmd tea.Cmd
			m.spin, cmd = m.spin.Update(msg)
			return m, cmd
		}
		return m, nil

	case notifMsg:
		m.events++
		n := Notification(msg)
		m.trans.append(n)
		var cmds []tea.Cmd
		// Single-session UI: no session filter, so replayed and resumed
		// streams drive the status too.
		if n.Method == "session.status" {
			if s, ok := n.Payload["status"].(string); ok {
				wasWorking := m.working()
				m.status = s
				if !wasWorking && m.working() {
					m.turnStart = time.Now()
					cmds = append(cmds, m.spin.Tick)
				}
			}
		}
		if in, out, ok := usageFrom(n); ok {
			m.tokIn += in
			m.tokOut += out
			m.ctxUsed = in + out
		}
		if event := eventOf(n); event != nil && event["type"] == "session/title" {
			if data, ok := event["data"].(map[string]any); ok {
				if t, ok := data["title"].(string); ok && t != "" {
					m.title = t
				}
			}
		}
		if event := eventOf(n); event != nil && event["type"] == "request/context" {
			if data, ok := event["data"].(map[string]any); ok {
				if w, ok := data["contextWindow"].(float64); ok {
					m.ctxWindow = int(w)
				}
			}
		}
		if event := eventOf(n); event != nil && event["type"] == "user/message" {
			if len(m.pending) > 0 {
				m.pending = m.pending[1:]
			}
		}
		if delta := chunkDelta(n); delta != "" {
			m.streamBuf += delta
		}
		if name, delta, ok := toolDelta(n); ok {
			m.toolName = name
			m.toolBuf += delta
		}
		if line := summarize(n); line != "" {
			// summarize returns non-"" for assistant/message, tool/call and
			// turn/end errors (among others): the stream is settled, drop
			// the previews.
			m.streamBuf = ""
			m.toolBuf, m.toolName = "", ""
			cmds = append(cmds, commit(line))
		}
		if m.raw {
			cmds = append(cmds, commit(styleMeta.Render(
				compactJSON(map[string]any{"method": n.Method, "params": n.Payload}, 4000))))
		}
		return m, tea.Batch(cmds...)

	case reqMsg:
		m.client.RespondError(msg.ID, -32601, "dsh-tui spike: client-side method not supported")
		return m, commit(styleErr.Render(fmt.Sprintf("? incoming request %s ", msg.Method)) + compactJSON(msg.Payload, 300))

	case promptDoneMsg:
		if msg.err != nil {
			m.status = "error"
			m.pending = nil
			return m, commit(styleErr.Render("prompt failed: " + msg.err.Error()))
		}
		return m, nil

	case diedMsg:
		m.pending = nil
		m.streamBuf = ""
		m.toolBuf, m.toolName = "", ""
		if m.restarting {
			m.status = "restarting"
			launch := m.launch
			return m, tea.Batch(
				commit(styleErr.Render("✗ interrupted")),
				func() tea.Msg {
					client, err := launch.start()
					return restartedMsg{client, err}
				},
			)
		}
		m.status = "dead"
		return m, commit(styleErr.Render("runtime died: " + msg.err.Error()))
	}

	var cmd tea.Cmd
	m.ta, cmd = m.ta.Update(msg)
	// Grow the input with its content, up to four rows.
	m.ta.SetHeight(min(max(m.ta.LineCount(), 1), 4))
	return m, cmd
}

const previewRows = 8

// escape handles esc/ctrl+c: double-press interrupts a running turn (kill +
// relaunch, since the composition routes no session/cancel); when idle it
// clears the input.
func (m *uiModel) escape() (tea.Model, tea.Cmd) {
	if m.working() && !m.restarting {
		if m.launch == nil {
			m.note = "replay: nothing to interrupt"
			return m, nil
		}
		if !m.armed {
			m.armed = true
			m.note = "esc again to interrupt"
			return m, func() tea.Msg {
				time.Sleep(2 * time.Second)
				return disarmMsg{}
			}
		}
		m.armed = false
		m.restarting = true
		m.note = "interrupting…"
		m.client.Kill()
		return m, nil
	}
	if m.ta.Value() != "" {
		m.ta.Reset()
		return m, nil
	}
	m.note = "quit with /quit"
	return m, nil
}

func (m *uiModel) working() bool {
	return m.status == "running" || m.status == "working"
}

func fmtTokens(n int) string {
	if n >= 1000000 {
		return fmt.Sprintf("%.0fM", float64(n)/1000000)
	}
	if n >= 10000 {
		return fmt.Sprintf("%.0fk", float64(n)/1000)
	}
	if n >= 1000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%d", n)
}

// View is the live region: pending prompt + streaming preview (pre-wrapped,
// erasable — never committed to the tape), input, status bar.
func (m *uiModel) View() string {
	live := ""
	for _, p := range m.pending {
		tag := ""
		if p.queued {
			tag = styleDim.Render("  (queued)")
		}
		live += styleUser.Render("❯ ") + styleDim.Render(p.text) + tag + "\n"
	}
	if m.toolName != "" {
		// The arguments JSON building up live, tail-clamped to one row.
		args := strings.ReplaceAll(m.toolBuf, "\n", " ")
		if avail := max(m.width-len(m.toolName)-6, 10); len(args) > avail {
			args = "…" + args[len(args)-avail:]
		}
		live += styleTool.Render("▸ "+m.toolName+" ") + styleDim.Render(args) + "\n"
	}
	if m.streamBuf != "" {
		wrapped := lipgloss.NewStyle().Width(max(m.width, 20)).Render(
			styleItalic.Render(m.streamBuf))
		rows := strings.Split(wrapped, "\n")
		if len(rows) > previewRows {
			rows = rows[len(rows)-previewRows:]
		}
		live += strings.Join(rows, "\n") + "\n"
	}

	glyph := styleDim.Render("●")
	state := m.status
	switch {
	case m.status == "dead" || m.status == "error":
		glyph = styleErr.Render("●")
	case m.working():
		glyph = m.spin.View()
		state = "working"
	case m.status == "idle" || m.status == "ready":
		glyph = styleMark.Render("●")
	}
	// Styles don't nest: render every segment separately or the glyph's
	// color bleeds across the whole bar.
	if m.working() && !m.turnStart.IsZero() {
		state += fmt.Sprintf(" %ds", int(time.Since(m.turnStart).Seconds()))
	}
	parts := []string{glyph + " " + styleDim.Render(state), styleDim.Render(m.modelName)}
	if m.tokIn+m.tokOut > 0 {
		parts = append(parts, styleDim.Render(fmt.Sprintf("↑%s ↓%s", fmtTokens(m.tokIn), fmtTokens(m.tokOut))))
	}
	if m.ctxWindow > 0 && m.ctxUsed > 0 {
		parts = append(parts, styleDim.Render(fmt.Sprintf("ctx %s/%s", fmtTokens(m.ctxUsed), fmtTokens(m.ctxWindow))))
	}
	short := m.sessionID
	if m.title != "" {
		short = m.title
	}
	if len(short) > 28 {
		short = short[:28] + "…"
	}
	parts = append(parts, styleDim.Render(short))
	if m.raw {
		parts = append(parts, styleDim.Render("raw log on"))
	}
	if m.note != "" {
		parts = append(parts, styleTool.Render(m.note))
	}
	bar := " " + strings.Join(parts, styleDim.Render("  ·  "))
	return live + "\n" + m.ta.View() + "\n" + bar
}
