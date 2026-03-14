# Ground Truth Protocol — Aider Integration

Add the following to your `.aider.conf.yml` file.

---

## .aider.conf.yml

```yaml
# Ground Truth Protocol configuration for Aider
# See: https://github.com/epaulson2/ground-truth-protocol

conventions:
  # Rule 1: Verify before acting
  - |
    Before starting any task, run ./scripts/ground-truth-probe.sh to verify
    current project state. The probe shows database tables, running services,
    git state, and configured credentials. Do not assume state — verify it.

  # Rule 2: Spec before code
  - |
    Before implementing any feature, read the relevant design spec in
    docs/design/. If no spec exists for the feature, flag this as a problem
    before proceeding. Do not implement from memory or training knowledge.

  # Rule 3: Evidence before done
  - |
    Before marking any task complete, produce observable evidence: file exists,
    tests pass, service responds, database rows exist. "Code written" is not
    evidence of completion.

  # Assertion gates
  - |
    Before creating any new resource (database, table, file, service), run
    the assertion gate: ./scripts/assertion-gate.sh <type> <name>
    If the gate returns BLOCKED, do not proceed. Follow the ACTION instruction.

  # Probe output is truth
  - |
    The ground-truth-probe.sh output is the authoritative source for project
    state. If the probe shows 38 database tables, do not suggest creating a
    database. If the probe shows API keys as SET, do not ask the user for them.

  # Context preservation
  - |
    When context is condensed, always preserve: the most recent probe output,
    all assertion gate results, and which spec documents have been read.

# Optional: auto-run probe at session start
# auto_test:
#   - ./scripts/ground-truth-probe.sh
```

## Usage Notes

### Aider Conventions vs. Mechanisms

Aider conventions are advisory — Aider does not support deterministic hooks like Claude Code. To add mechanical enforcement with Aider:

1. **Use git hooks** for pre-commit assertion gates (see `examples/assertion-gate.sh`)
2. **Use CI gates** for deployment assertions
3. **Paste probe output** at the start of each session manually

### Recommended Workflow with Aider

1. Run `./scripts/ground-truth-probe.sh` and paste the output into the chat
2. Define the task clearly with explicit scope boundaries
3. Ask Aider to read the relevant spec before coding: `/read docs/design/FEATURE_SPEC.md`
4. Implement in small steps with verification at each step
5. Run assertion gates before creating new resources
6. Run tests before claiming completion

### Combining with Git Hooks

For mechanical enforcement, add assertion gates as git hooks:

```bash
# .git/hooks/pre-commit
#!/bin/bash
# Run assertion gates on staged changes

# Check for duplicate files
NEW_FILES=$(git diff --cached --name-only --diff-filter=A)
for file in $NEW_FILES; do
  ./scripts/assertion-gate.sh file "$file" || exit 1
done

# Check for banned patterns (customize for your project)
if git diff --cached -U0 | grep -E '^\+.*localhost' | grep -v '//localhost'; then
  echo "GATE BLOCKED: Use 127.0.0.1 instead of localhost"
  exit 1
fi
```
