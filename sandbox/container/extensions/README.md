# OMP Sandbox Extensions

Custom [oh-my-pi](https://omp.sh/) extensions loaded into the sandboxed agent. Each extension lives in its own folder; the `.ts` entry point stays at the top level so omp's flat extension scanner picks it up.

| Extension | Entry point | What it does |
|-----------|------------|--------------|
| [memory](memory/) | `memory.ts` | Captures heard/said/thought memories to pgvector; `recollect`/`recall`/`remember`/`suppress` tools + unprompted surfacing |
| [morph](morph/) | `morph.ts` | Morph Fast Apply — merges partial edit snippets into full files via OpenRouter |
| [openrouter-advisor](openrouter-advisor/) | `openrouter-advisor.ts` | Mid-generation advisor tools (e.g. `consult_fable`, `openrouter_advisor`), each defined by a JSON in `advisors/` |

## Layout

```
extensions/
├── memory.ts                    # entry: tools, capture, surfacing
├── memory/
│   ├── config.ts                # config types, defaults, loader
│   ├── openrouter.ts            # summarize + embed API calls
│   ├── memory.json              # runtime config (models, limits, postgres)
│   └── APPEND_SYSTEM.md         # model-facing system prompt contract
├── morph.ts                     # entry: edit tool via Morph Fast Apply
├── morph/                       # docs
├── openrouter-advisor.ts        # entry: loads advisor JSONs, registers tools
├── openrouter-advisor/
│   └── advisors/                # one JSON per advisor tool
│       ├── openrouter-advisor.json
│       └── consult-fable.json
├── package.json                 # shared typecheck infra
└── tsconfig.json
```

## Type checking

```sh
bun install && bun run typecheck
```
