# Spec Forms (YAML)

creation.yaml:
task: create
type: greenfield
fields:
  - spec: [overview]
  - requirements: [tech stack, features]
  - extras: [tests, docs, perf targets]

update.yaml:
task: update
type: targeted
fields:
  - base: [existing code/context]
  - enhancements: [bullet list]
  - invariants: [must-preserve]

Usage: Form → JSON spec → Delegate to grok-code-fast-1.
