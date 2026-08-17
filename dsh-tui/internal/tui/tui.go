// Package tui is the Bubble Tea frontend: an inline renderer, deliberately
// no alt screen. Finalized lines are committed to native scrollback
// unwrapped (tea.Println) so the terminal soft-wraps them and native
// selection-copy re-joins them — the finalization-emission design from
// oh-my-pi#7879. Only the live region below (pending prompts, streaming
// previews, input, status bar) is managed, pre-wrapped repainting.
package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/cursor"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textarea"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/gitseed/monorepo/dsh-tui/internal/harness"
	"github.com/gitseed/monorepo/dsh-tui/internal/render"
	"github.com/gitseed/monorepo/dsh-tui/internal/session"
)

// Options wires a Model. Launch and Trans are nil in replay mode: no
// runtime to restart, nothing to record.
type Options struct {
	Conn         harness.Conn
	SessionID    string
	ModelName    string
	Launch       *harness.Launcher
	Trans        *session.Transcript
	NeedsRestore bool // resumed session: inject transcript context on next prompt
}

// Run blocks until the UI exits.
func Run(o Options) error {
	m := newModel(o)
	p := tea.NewProgram(m)
	m.program = p
	go pump(p, o.Conn)
	_, err := p.Run()
	return err
}

type notifMsg harness.Notification
type reqMsg harness.IncomingRequest
type diedMsg struct{ err error }
type promptDoneMsg struct{ err error }
type cancelDoneMsg struct{ err error }
type disarmMsg struct{}
type restartedMsg struct {
	client *harness.Client
	err    error
}

// pendingPrompt is a prompt awaiting its user/message echo; queued marks
// ones sent while a turn was already running (steering).
type pendingPrompt struct {
	text   string
	queued bool
}

type model struct {
	client    harness.Conn
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
	tokIn     int
	tokOut    int
	ctxWindow int    // from request/context
	ctxUsed   int    // latest step's input+output tokens ~ occupancy
	title     string // from session/title
	turnStart time.Time
	width     int

	program      *tea.Program
	launch       *harness.Launcher   // nil in replay mode
	trans        *session.Transcript // nil in replay mode, or after a write failure
	needsRestore bool                // runtime restarted/resumed: inject transcript context on next prompt
	armed        bool                // first esc pressed, second interrupts
	restarting   bool                // runtime killed on purpose, relaunch under way
}

func newModel(o Options) *model {
	ta := textarea.New()
	ta.Placeholder = "Message dsh — /help for keys"
	ta.SetHeight(1)
	ta.Focus()
	ta.ShowLineNumbers = false
	ta.Prompt = "❯ "
	ta.FocusedStyle.Prompt = render.StyleUser
	ta.BlurredStyle.Prompt = render.StyleDim
	ta.FocusedStyle.CursorLine = lipgloss.NewStyle()
	ta.Cursor.SetMode(cursor.CursorStatic)
	sp := spinner.New(spinner.WithSpinner(spinner.MiniDot))
	sp.Style = lipgloss.NewStyle().Foreground(render.ColTool)
	return &model{
		client:       o.Conn,
		sessionID:    o.SessionID,
		modelName:    o.ModelName,
		launch:       o.Launch,
		trans:        o.Trans,
		needsRestore: o.NeedsRestore,
		ta:           ta,
		spin:         sp,
		status:       "ready",
	}
}

// pump forwards a conn's channels into the program. Unlike a listen-cmd
// per message, Send drains as fast as events arrive, so a tool-output
// burst can't fill the client's channel and backpressure the runtime's
// stdout reader. Exits after the conn dies (a restart starts a new pump).
func pump(p *tea.Program, c harness.Conn) {
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

func (m *model) Init() tea.Cmd {
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

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.ta.SetWidth(max(msg.Width-2, 1))
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "ctrl+c":
			// ctrl+c is esc: interrupt when working, clear the input when
			// idle. Quitting is /quit — never a control chord.
			return m.escape()
		case "ctrl+r":
			m.raw = !m.raw
			return m, nil
		case "alt+enter", "ctrl+j":
			// shift+enter is the convention, but a plain terminal sends it
			// as enter; see README for the emulator mapping to LF.
			m.ta.InsertString("\n")
			return m, nil
		case "enter":
			return m.submit()
		}

	case disarmMsg:
		m.armed = false
		if m.note == "esc again to interrupt" {
			m.note = ""
		}
		return m, nil

	case cancelDoneMsg:
		if msg.err == nil {
			// The stream reports the rest: turn/end aborted, then idle.
			return m, nil
		}
		if harness.IsUnknownMethod(msg.err) && m.launch != nil {
			// Stock composition without the cancel plugin: the old
			// mechanism, named for what it costs.
			m.restarting = true
			m.note = "runtime lacks session/cancel — restarting (context restores from transcript)"
			m.client.Kill()
			return m, nil
		}
		m.note = ""
		m.status = "error"
		return m, commit(render.StyleErr.Render("cancel failed: " + msg.err.Error()))

	case restartedMsg:
		m.restarting = false
		if msg.err != nil {
			m.status = "dead"
			return m, commit(render.StyleErr.Render("restart failed: " + msg.err.Error()))
		}
		m.client = msg.client
		m.status = "idle"
		m.note = ""
		m.needsRestore = true
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
		return m.notified(harness.Notification(msg))

	case reqMsg:
		m.client.RespondError(msg.ID, -32601, "dsh-tui: client-side method not supported")
		return m, commit(render.StyleErr.Render(fmt.Sprintf("? incoming request %s ", msg.Method)) + render.CompactJSON(msg.Payload, 300))

	case promptDoneMsg:
		if msg.err != nil {
			m.status = "error"
			m.pending = nil
			return m, commit(render.StyleErr.Render("prompt failed: " + msg.err.Error()))
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
				commit(render.StyleErr.Render("✗ interrupted")),
				func() tea.Msg {
					client, err := launch.Start()
					return restartedMsg{client, err}
				},
			)
		}
		m.status = "dead"
		return m, commit(render.StyleErr.Render("runtime died: " + msg.err.Error()))
	}

	var cmd tea.Cmd
	m.ta, cmd = m.ta.Update(msg)
	// Grow the input with its content, up to four rows.
	m.ta.SetHeight(min(max(m.ta.LineCount(), 1), 4))
	return m, cmd
}

// submit handles enter: slash commands, then a prompt send. A restarted or
// resumed runtime has no memory (nothing routes session loading), so the
// first prompt after one carries the transcript as restored context — and
// says so out loud when there is no transcript to restore.
func (m *model) submit() (tea.Model, tea.Cmd) {
	text := strings.TrimSpace(m.ta.Value())
	if text == "" {
		return m, nil
	}
	switch text {
	case "/quit", "/exit", "exit", "quit":
		return m, tea.Quit
	case "/help":
		m.ta.Reset()
		return m, commit(render.StyleDim.Render(strings.Join([]string{
			"",
			"enter    send (mid-turn = steering, queues into the inbox)",
			"shift+enter  newline — map it to send LF in your terminal (see README); ctrl+j always works",
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
	m.note = ""
	// The user line commits when the runtime echoes it back as a
	// user/message event; until then it shows in the live region.
	m.pending = append(m.pending, pendingPrompt{text: text, queued: m.working()})
	m.status = "working"
	var cmds []tea.Cmd
	send := text
	if m.needsRestore {
		m.needsRestore = false
		restore, err := m.restorePreamble()
		switch {
		case err != nil:
			cmds = append(cmds, commit(render.StyleErr.Render("context restore failed: "+err.Error()+" — the model starts without prior context")))
		case restore == "":
			cmds = append(cmds, commit(render.StyleDim.Render("no transcript to restore — the model starts without prior context")))
		default:
			send = restore + text
		}
	}
	cmds = append(cmds,
		m.spin.Tick,
		func() tea.Msg {
			_, err := m.client.Prompt(m.sessionID, send)
			return promptDoneMsg{err}
		},
	)
	return m, tea.Batch(cmds...)
}

func (m *model) restorePreamble() (string, error) {
	if m.trans == nil {
		return "", nil
	}
	return session.RestoreContext(m.trans.Path)
}

// notified folds one runtime notification into the model.
func (m *model) notified(n harness.Notification) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd
	if m.trans != nil {
		if err := m.trans.Append(n); err != nil {
			// Without the transcript, restore and resume are dead — say so
			// once and stop pretending to record.
			m.trans = nil
			cmds = append(cmds, commit(render.StyleErr.Render(err.Error()+" — transcript recording stopped; interrupt/resume will lose model context")))
		}
	}
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
			// "interrupting…" is transient: the cancellation is done when
			// the turn stops being a turn.
			if wasWorking && !m.working() && m.note == "interrupting…" {
				m.note = ""
			}
		}
	}
	if in, out, ok := render.UsageFrom(n); ok {
		m.tokIn += in
		m.tokOut += out
		m.ctxUsed = in + out
	}
	if event := render.EventOf(n); event != nil {
		data, _ := event["data"].(map[string]any)
		switch event["type"] {
		case "session/title":
			if t, ok := data["title"].(string); ok && t != "" {
				m.title = t
			}
		case "request/context":
			if w, ok := data["contextWindow"].(float64); ok {
				m.ctxWindow = int(w)
			}
		case "user/message":
			if len(m.pending) > 0 {
				m.pending = m.pending[1:]
			}
		}
	}
	if delta := render.ChunkDelta(n); delta != "" {
		m.streamBuf += delta
	}
	if name, delta, ok := render.ToolDelta(n); ok {
		m.toolName = name
		m.toolBuf += delta
	}
	if line := render.Summarize(n); line != "" {
		// Summarize returns non-"" for assistant/message, tool/call and
		// turn/end errors (among others): the stream is settled, drop the
		// previews.
		m.streamBuf = ""
		m.toolBuf, m.toolName = "", ""
		cmds = append(cmds, commit(line))
	}
	if m.raw {
		cmds = append(cmds, commit(render.StyleMeta.Render(
			render.CompactJSON(map[string]any{"method": n.Method, "params": n.Payload}, 4000))))
	}
	return m, tea.Batch(cmds...)
}

// escape handles esc/ctrl+c: double-press interrupts a running turn (kill +
// relaunch, since the composition routes no session/cancel); when idle it
// clears the input.
func (m *model) escape() (tea.Model, tea.Cmd) {
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
		m.note = "interrupting…"
		// Cancel first: with the dsh-tui plugin loaded the turn settles as
		// aborted and the session keeps its context. Kill is the labeled
		// fallback for a stock composition (see cancelDoneMsg).
		client, id := m.client, m.sessionID
		return m, func() tea.Msg { return cancelDoneMsg{client.Cancel(id)} }
	}
	if m.ta.Value() != "" {
		m.ta.Reset()
		return m, nil
	}
	m.note = "quit with /quit"
	return m, nil
}

func (m *model) working() bool {
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

const previewRows = 8

// View is the live region: pending prompts + streaming previews
// (pre-wrapped, erasable — never committed to the tape), input, status bar.
func (m *model) View() string {
	live := ""
	for _, p := range m.pending {
		tag := ""
		if p.queued {
			tag = render.StyleDim.Render("  (queued)")
		}
		live += render.StyleUser.Render("❯ ") + render.StyleDim.Render(p.text) + tag + "\n"
	}
	if m.toolName != "" {
		// The arguments JSON building up live, tail-clamped to one row.
		args := strings.ReplaceAll(m.toolBuf, "\n", " ")
		if avail := max(m.width-len(m.toolName)-6, 10); len(args) > avail {
			args = "…" + args[len(args)-avail:]
		}
		live += render.StyleTool.Render("▸ "+m.toolName+" ") + render.StyleDim.Render(args) + "\n"
	}
	if m.streamBuf != "" {
		wrapped := lipgloss.NewStyle().Width(max(m.width, 20)).Render(
			render.StyleItalic.Render(m.streamBuf))
		rows := strings.Split(wrapped, "\n")
		if len(rows) > previewRows {
			rows = rows[len(rows)-previewRows:]
		}
		live += strings.Join(rows, "\n") + "\n"
	}
	return live + "\n" + m.ta.View() + "\n" + m.statusBar()
}

func (m *model) statusBar() string {
	glyph := render.StyleDim.Render("●")
	state := m.status
	switch {
	case m.status == "dead" || m.status == "error":
		glyph = render.StyleErr.Render("●")
	case m.working():
		glyph = m.spin.View()
		state = "working"
	case m.status == "idle" || m.status == "ready":
		glyph = render.StyleMark.Render("●")
	}
	if m.working() && !m.turnStart.IsZero() {
		state += fmt.Sprintf(" %ds", int(time.Since(m.turnStart).Seconds()))
	}
	// Styles don't nest: render every segment separately or the glyph's
	// color bleeds across the whole bar.
	parts := []string{glyph + " " + render.StyleDim.Render(state), render.StyleDim.Render(m.modelName)}
	if m.tokIn+m.tokOut > 0 {
		parts = append(parts, render.StyleDim.Render(fmt.Sprintf("↑%s ↓%s", fmtTokens(m.tokIn), fmtTokens(m.tokOut))))
	}
	if m.ctxWindow > 0 && m.ctxUsed > 0 {
		parts = append(parts, render.StyleDim.Render(fmt.Sprintf("ctx %s/%s", fmtTokens(m.ctxUsed), fmtTokens(m.ctxWindow))))
	}
	short := m.sessionID
	if m.title != "" {
		short = m.title
	}
	if len(short) > 28 {
		short = short[:28] + "…"
	}
	parts = append(parts, render.StyleDim.Render(short))
	if m.raw {
		parts = append(parts, render.StyleDim.Render("raw log on"))
	}
	if m.note != "" {
		parts = append(parts, render.StyleTool.Render(m.note))
	}
	return " " + strings.Join(parts, render.StyleDim.Render("  ·  "))
}
