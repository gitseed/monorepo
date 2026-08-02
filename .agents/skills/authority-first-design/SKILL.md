---
name: authority-first-design
description: Load before writing plumbing — a script rehydrating one value into a file, a gitignore'd secret, a mount widened for one path, a "run X first" step. Anchor on the value's owner and the consumer's native intake path instead.
---

# Authority-first design

Every mechanism answers "where does this value live, and how do its
consumers reach it?" Two answers are available at design time, and the
choice determines everything that ships after.

## Start at the source, not the default shape

The default input shape is where gross begins. Scaffolded version: the
vault holds the CA, but envoy "reads files", so a script exports the
cert into the repo, gitignore defends it, the build context widens to
reach it, and the README grows "run the export first". Anchored
version: the vault feeds envoy through an intake path envoy already
has — an environment variable, an SDS endpoint, a `buildkit --secret`
mount — and none of that scaffolding is ever written, because nothing
needs lodging.

Same feature. The difference is which end of the pipe the design
started from.

## The procedure

1. Name the value and the consumer that needs it.
2. Name the owner — the system where the value is born or managed
   (the vault owns certificates; the embedded resolver owns container
   naming; the daemon owns host mappings).
3. List the consumer's native intake paths — environment variable,
   `--secret` mount, network alias, API call — and pick the one the
   owner can feed directly.
4. Only if step 3 comes up empty after one hop toward the owner may a
   bridge be written. See "When the bridge is forced" below.

## Scaffolding is the tell at construction time

Each of these, the moment it's added, means one layer up hasn't been
asked its question yet:

- a script whose entire job is rehydrating one value into a file
- a `.gitignore` entry defending a manufactured secret or value
  (ignoring build output is normal; ignoring a credential a script
  wrote is the tell)
- a placeholder directory that exists to receive a secret
- a widened build context or mount for exactly one artifact
- a sequencing instruction: "run X first", "rerun after restart"

Clean mechanisms are subtractive: questioning the constraint deletes
lines; accommodating it adds them, and each added line is a future
"why is this here" from whoever reads the diff cold.

## When the bridge is forced

Sometimes no native intake path exists — a third-party binary that
only reads files, an owner outside the ask's scope. Then keep the
bridge, keep it minimal, and write the forcing constraint in one line
at the scaffolding site: "tool X only reads files; vault cannot
push". Do not rewrite the owner to create an intake path the ask
didn't name — scope stays where the ask put it. A documented bridge
is a decision; an undocumented one is residue.

## The wiring

This is not a review gate — by review time the scaffolding is already
load-bearing. The trigger is the fleeting thought *while building*:
"why does this file exist", "why must this run first", "why is this
script's job so thin". Pause there and run the procedure. The cost of
rerouting is minutes; the cost of not rerouting is a mechanism that
survives three replacements before it's named what it was all along.
