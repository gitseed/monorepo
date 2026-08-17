package harness

// Locates the dsh SDK runtime executable. The deepseek-harness-runtime-bin
// wheel ships a single-file dsh-jsonrpc-agent binary plus its default cordis
// config; installing deepseek-harness-sdk into ./.venv puts them under
// site-packages (see README for the uv one-liner).

import (
	"fmt"
	"os"
	"path/filepath"
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
