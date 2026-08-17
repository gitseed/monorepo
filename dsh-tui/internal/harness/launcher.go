package harness

import "fmt"

// Launcher restarts the runtime with the same config — the interrupt path
// (kill + relaunch, since nothing routes session/cancel) needs it.
type Launcher struct {
	Bin       string
	Workspace string
	Env       []string
	Provider  string
	Model     string
}

func (l *Launcher) Start() (*Client, error) {
	client, err := StartClient([]string{l.Bin}, l.Workspace, l.Env)
	if err != nil {
		return nil, fmt.Errorf("failed to launch runtime: %w", err)
	}
	if err := client.Initialize(l.Workspace, l.Provider, l.Model, 0); err != nil {
		client.Close()
		return nil, fmt.Errorf("initialize failed: %w", err)
	}
	return client, nil
}
