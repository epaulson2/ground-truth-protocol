# Ground Truth Protocol — Cursor Integration

Save this content as `.cursorrules` in your project root.

---

## Ground Truth Protocol

### Session Start

Before beginning any task, run `./scripts/ground-truth-probe.sh` and review the output.
The probe shows the current state of the database, services, git repository, and credentials.
Do not assume infrastructure state. The probe output is the source of truth.

### Three Rules

1. **Verify before acting.** Before creating, modifying, or asking about ANY resource (database, table, file, service, API key), check actual state first. Run `./scripts/ground-truth-probe.sh` if uncertain. Never assume. Never ask the user what exists without checking first.

2. **Spec before code.** Before implementing ANY feature, read the relevant design spec in `docs/design/`. If no spec exists, flag this before proceeding. Do not implement from memory or assumption.

3. **Evidence before done.** Never claim a task is complete without observable proof: file exists on disk, database rows exist, tests pass, service responds. "Code written" does not equal "done."

### Assertion Gates

Before creating any resource, run the assertion gate:

```bash
# Before creating a database
./scripts/assertion-gate.sh database mydb

# Before creating a file
./scripts/assertion-gate.sh file path/to/file.py

# Before creating a service
./scripts/assertion-gate.sh service myservice
```

If the gate returns "BLOCKED", do not proceed. Follow the ACTION instruction in the gate output.

### Compaction

When summarizing or condensing context, always preserve:
- The most recent probe output (database tables, services, credentials)
- All assertion gate results from this session
- The current task definition and completion criteria
- Which spec documents have been read

### What Not to Do

- Do not suggest creating databases without running the probe first
- Do not ask the user for information that the probe output already shows
- Do not implement features without reading the design spec
- Do not add new rules to this file after a failure — add an assertion gate script instead
