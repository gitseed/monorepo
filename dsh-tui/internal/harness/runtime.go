package harness

// Locates the dsh SDK runtime executable. The deepseek-harness-runtime-bin
// wheel ships a single-file dsh-jsonrpc-agent binary plus its default cordis
// config; installing deepseek-harness-sdk into ./.venv puts them under
// site-packages (see README for the uv one-liner).

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Runtime struct {
	Bin           string
	DefaultConfig string
}

func ResolveRuntime() (*Runtime, error) {
	if bin := os.Getenv("DSH_RUNTIME_BIN"); bin != "" {
		return &Runtime{Bin: bin, DefaultConfig: filepath.Join(filepath.Dir(bin), "cordis.yml")}, nil
	}
	roots := []string{"."}
	if exe, err := os.Executable(); err == nil {
		roots = append(roots, filepath.Dir(exe))
	}
	for _, root := range roots {
		pattern := filepath.Join(root, ".venv", "lib", "python*", "site-packages",
			"deepseek_harness_runtime", "runtime", "dsh-jsonrpc-agent-pkg-*")
		matches, _ := filepath.Glob(pattern)
		if len(matches) > 0 {
			// The subprocess launches with its cwd set to the agent
			// workspace, so a cwd-relative bin path would break.
			bin, err := filepath.Abs(matches[0])
			if err != nil {
				return nil, err
			}
			return &Runtime{
				Bin:           bin,
				DefaultConfig: filepath.Join(filepath.Dir(bin), "cordis.yml"),
			}, nil
		}
	}
	return nil, fmt.Errorf("dsh-jsonrpc-agent not found; install it with:\n" +
		"  uv venv .venv && uv pip install --python .venv/bin/python deepseek-harness-sdk\n" +
		"or set DSH_RUNTIME_BIN")
}

// ResolveCancelPlugin locates plugin/cancel-server.ts (the session/cancel
// routing plugin, loaded by the runtime via absolute path). Empty string
// means not found — the caller must say so, since esc then degrades to
// kill+restart.
func ResolveCancelPlugin() string {
	if p := os.Getenv("DSH_TUI_CANCEL_PLUGIN"); p != "" {
		return p
	}
	roots := []string{"."}
	if exe, err := os.Executable(); err == nil {
		roots = append(roots, filepath.Dir(exe))
	}
	for _, root := range roots {
		p := filepath.Join(root, "plugin", "cancel-server.ts")
		if _, err := os.Stat(p); err == nil {
			abs, err := filepath.Abs(p)
			if err == nil {
				return abs
			}
		}
	}
	return ""
}

// PatchComposition rewrites a composition to load the cancel plugin in
// place of the stock sdk-jsonrpc-server row, returning the path of the
// patched copy. An error is a real failure; a composition without the
// stock row returns ("", nil) — nothing to patch, caller announces the
// degraded esc.
func PatchComposition(cordisPath, pluginPath, dir string) (string, error) {
	content, err := os.ReadFile(cordisPath)
	if err != nil {
		return "", fmt.Errorf("read composition: %w", err)
	}
	const stockRow = "name: '@deepseek-ai/dsh-sdk-jsonrpc-server'"
	if !strings.Contains(string(content), stockRow) {
		return "", nil
	}
	patched := strings.Replace(string(content), stockRow, "name: '"+pluginPath+"'", 1)
	out := filepath.Join(dir, "composition-cancel.yml")
	if err := os.WriteFile(out, []byte(patched), 0o644); err != nil {
		return "", fmt.Errorf("write patched composition: %w", err)
	}
	return out, nil
}
