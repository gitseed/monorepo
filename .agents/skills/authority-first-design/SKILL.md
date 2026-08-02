---
name: authority-first-design
description: Anchor new mechanisms on the value's authoritative owner, not the consumer's default input shape; treat bridges, guards, and ordering steps as unanswered questions to eliminate, not accept. Load before writing any plumbing — a script that reformats one value, a gitignore entry protecting a file from git, a mount widened to reach one path, a run-this-before-that instruction.
---

# Authority-first design

Every mechanism answers "where does this value live, and how do its
consumers reach it?" Two answers are available at design time, and the
choice determines everything that ships after.

## Start at the source, not the default shape

The default input shape is where gross begins: envoy "reads files", so
a CA gets manufactured on this host, written into the repo, guarded by
gitignore, and the build context widens to reach it. None of that is
the feature; all of it is lodging for a decision nobody examined.

The authority-first question: *who already owns this value?* The vault
owns certificates. The embedded resolver owns container naming. The
daemon owns host mappings. Anchoring there, each consumer asks for its
native intake path — `environment_variable`, `buildkit --secret`, a
network alias — and the scaffolding never gets written because nothing
needs lodging.

## Scaffolding is the tell at construction time

The following are never features. Each one, the moment it's added,
means one layer up hasn't been asked its question yet:

- a script whose entire job is rehydrating one value into a file
- a `.gitignore` entry defending a file from version control
- a placeholder directory that exists to receive a secret
- a widened build context or mount for exactly one artifact
- a sequencing instruction: "run X first", "rerun after restart"

Clean mechanisms are subtractive: questioning the constraint deletes
lines; accommodating it adds them, and each added line is a future
"why is this here" from whoever reads the diff cold.

## The wiring

This is not a review gate — by review time the scaffolding is already
load-bearing. The trigger is the fleeting thought *while building*:
"why does this file exist", "why must this run first", "why is this
script's job so thin". Pause there. Walk one hop toward the owner of
the value. The cost of rerouting is minutes; the cost of not rerouting
is a mechanism that survives three replacements before it's named what
it was all along.
