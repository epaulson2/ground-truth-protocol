# Hold Point System Architecture

## Overview

The Hold Point system is a machine-enforced completion verification framework for AI agent software development. It ensures that work marked as "done" actually meets pre-defined acceptance criteria, verified independently against the live system, with blocking enforcement and bypass prevention.

The system comprises five components that work together. Removing any one component creates a gap that agents will exploit (intentionally or not).

---

## Component Diagram

```
+------------------------------------------------------------------+
|                        HOLD POINT SYSTEM                          |
|                                                                    |
|  +------------------+    +---------------------+                   |
|  | Acceptance Gate   |    | Pipeline State      |                  |
|  | Engine            |    | Machine             |                  |
|  |                   |    |                     |                   |
|  | - YAML gate defs  |    | - Stage tracking    |                  |
|  | - Gate runner      |    | - Transition rules  |                  |
|  | - Result cache     |    | - Approval gates    |                  |
|  | - Hash tracking    |    | - State persistence |                  |
|  +--------+----------+    +----------+----------+                  |
|           |                          |                              |
|           v                          v                              |
|  +------------------+    +---------------------+                   |
|  | Judge Agent       |    | Bypass Guards        |                  |
|  |                   |    |                     |                   |
|  | - Independent     |    | - PreToolUse hooks   |                  |
|  |   verifier        |    | - PostToolUse hooks  |                  |
|  | - 3-perspective   |    | - Stop hooks         |                  |
|  |   review          |    | - Gate invalidation  |                  |
|  | - Structural +    |    | - Path coverage      |                  |
|  |   behavioral +    |    |                     |                   |
|  |   spec checks     |    |                     |                   |
|  +--------+----------+    +----------+----------+                  |
|           |                          |                              |
|           v                          v                              |
|  +-------------------------------------------------------+        |
|  | Continuous Verification                                 |        |
|  |                                                         |        |
|  | - Code hash tracking per gate                           |        |
|  | - Automatic invalidation on change                      |        |
|  | - Regression detection                                  |        |
|  | - CI/CD integration                                     |        |
|  +---------------------------------------------------------+        |
+------------------------------------------------------------------+
```

---

## Data Flow

```
                    Developer assigns task
                           |
                           v
                +--------------------+
                |  1. DEFINE GATES   |
                |                    |
                | Write YAML gate    |
                | definitions with   |
                | acceptance criteria|
                +--------+-----------+
                         |
                         v
                +--------------------+
                |  2. WORK BEGINS    |
                |                    |
                | Agent implements   |
                | the feature        |
                | (bypass guards     |
                |  active)           |
                +--------+-----------+
                         |
                         v
                +--------------------+
                |  3. GATE CHECK     |
                |                    |
                | Gate runner         |
                | executes all       |
                | criteria against   |
                | LIVE system        |
                +--------+-----------+
                         |
              +----------+----------+
              |                     |
         GATES FAIL            GATES PASS
              |                     |
              v                     v
    +------------------+  +------------------+
    | Agent fixes      |  | 4. JUDGE REVIEW  |
    | issues, re-runs  |  |                  |
    | gates            |  | Independent      |
    | (loop back to 3) |  | verification     |
    +------------------+  | from 3 angles    |
                          +--------+---------+
                                   |
                        +----------+----------+
                        |                     |
                   JUDGE REJECTS         JUDGE APPROVES
                        |                     |
                        v                     v
              +------------------+  +------------------+
              | Agent addresses  |  | 5. HUMAN REVIEW  |
              | judge feedback   |  |                  |
              | (loop back to 3) |  | Final sign-off   |
              +------------------+  | (approval gate)  |
                                    +--------+---------+
                                             |
                                             v
                                    +------------------+
                                    |  6. DONE         |
                                    |                  |
                                    | Gate results     |
                                    | cached with      |
                                    | code hashes      |
                                    +------------------+
```

---

## Component 1: Acceptance Gate Engine

### Purpose

Defines verifiable acceptance criteria in YAML and executes them against the live system. This is the foundation -- without criteria, there is nothing to verify.

### YAML Gate Schema

```yaml
gate:
  name: string                    # Unique gate identifier
  stage: string                   # Pipeline stage (design, backend, frontend, integration, deploy)
  description: string             # Human-readable description
  pass_threshold: float           # 0.0-1.0, fraction of criteria that must pass (default: 1.0)

  criteria:
    - name: string                # Criterion identifier
      type: enum                  # file_exists | command | http | sql
      description: string         # What this criterion verifies

      # For type: file_exists
      path: string                # File path to check
      contains: string            # Optional: content the file must contain
      min_lines: int              # Optional: minimum line count

      # For type: command
      run: string                 # Shell command to execute
      expect_exit: int            # Expected exit code (default: 0)
      expect_output: string       # Optional: regex the output must match
      timeout: int                # Optional: timeout in seconds (default: 30)

      # For type: http
      method: string              # GET | POST | PUT | DELETE
      url: string                 # Full URL to request
      headers: map                # Optional: HTTP headers
      body: string                # Optional: request body
      expect_status: int          # Expected HTTP status code
      expect_body: string         # Optional: regex the response body must match

      # For type: sql
      connection: string          # Connection string or env var name
      query: string               # SQL query to execute
      expect_rows: int            # Optional: expected row count
      expect_value: string        # Optional: expected value in first column of first row

  status_rules:
    all_pass: GATES_PASSING       # Status when all criteria pass
    some_fail: IN_PROGRESS        # Status when some criteria fail
    none_run: GATES_DEFINED       # Status when criteria exist but have not been run
```

### Gate Runner

The gate runner is a script (or binary) that:

1. Reads YAML gate definitions from a directory
2. Executes each criterion against the live system
3. Produces a pass/fail result with evidence
4. Caches results with the hash of relevant source files
5. Outputs structured results for pipeline state updates

```bash
# Run all gates in a directory
./scripts/gate-runner.sh .hold-point/gates/

# Run a specific gate
./scripts/gate-runner.sh .hold-point/gates/auth.yaml

# Run with verbose output
./scripts/gate-runner.sh --verbose .hold-point/gates/
```

### Result Cache

Gate results are stored in `.hold-point/results/` with the following structure:

```json
{
  "gate": "user-authentication",
  "timestamp": "2026-03-15T10:30:00Z",
  "result": "PASS",
  "criteria": [
    {
      "name": "login-endpoint-exists",
      "result": "PASS",
      "evidence": "HTTP 200 in 45ms",
      "source_hash": "a1b2c3d4"
    }
  ],
  "source_files_hashed": [
    "src/auth/login.py:a1b2c3d4",
    "src/auth/models.py:e5f6g7h8"
  ]
}
```

---

## Component 2: Pipeline State Machine

### Purpose

Enforces that work progresses through defined stages in order, with hold points at each transition. The state machine prevents advancing to a later stage without satisfying the requirements of the current stage.

### State Diagram

```
+---------------+     +---------------+     +------------------+
| NOT_STARTED   |---->| IN_PROGRESS   |---->| GATES_DEFINED    |
|               |     |               |     |                  |
| No work       |     | Work begun,   |     | YAML gates       |
| has started   |     | no gates yet  |     | written, not     |
|               |     |               |     | yet run          |
+---------------+     +---------------+     +--------+---------+
                                                     |
                                                     | G1: Criteria
                                                     |     approved
                                                     v
+---------------+     +---------------+     +------------------+
|    DONE       |<----| REVIEW        |<----| GATES_PASSING    |
|               |     |               |     |                  |
| All gates     |     | Human review  |     | All criteria     |
| pass, review  |     | in progress   |     | passing against  |
| approved      |     |               |     | live system      |
+---------------+     +---------------+     +------------------+
       ^                     |  ^                    |
       |                     |  |                    |
       | G4: Final           |  | G3: Review         | G2: Gates
       |     sign-off        |  |     requested      |     pass
       +---------------------+  +--------------------+
```

### Transition Rules

| From | To | Required |
|------|----|----------|
| NOT_STARTED | IN_PROGRESS | Task assigned |
| IN_PROGRESS | GATES_DEFINED | At least one YAML gate file exists |
| GATES_DEFINED | GATES_PASSING | All criteria pass (G1: criteria approved) |
| GATES_PASSING | REVIEW | G2: gates pass + G3: review requested |
| REVIEW | DONE | G4: human sign-off |
| REVIEW | IN_PROGRESS | Reviewer rejects (back to work) |
| Any | BLOCKED | External dependency or issue |

### Human Approval Gates

Four approval gates require explicit human action:

- **G1 (Criteria Approved)**: Human reviews and approves the YAML gate definitions before work is evaluated against them. Prevents the agent from writing trivially-passing criteria.
- **G2 (Gates Pass)**: Automated -- all acceptance criteria pass against the live system.
- **G3 (Review Requested)**: Agent or human requests review, triggering the judge agent.
- **G4 (Final Sign-off)**: Human reviews judge output and gate results, approves completion.

### Pipeline State Persistence

Pipeline state is stored in `.hold-point/pipeline.json`:

```json
{
  "version": 1,
  "stages": {
    "user-authentication": {
      "status": "GATES_PASSING",
      "entered_at": "2026-03-15T10:30:00Z",
      "gate_file": ".hold-point/gates/auth.yaml",
      "last_gate_run": "2026-03-15T14:22:00Z",
      "gate_result": "PASS",
      "approvals": {
        "G1": { "by": "epaulson2", "at": "2026-03-15T09:00:00Z" },
        "G2": { "by": "gate-runner", "at": "2026-03-15T14:22:00Z" }
      },
      "history": [
        { "from": "NOT_STARTED", "to": "IN_PROGRESS", "at": "2026-03-15T08:00:00Z" },
        { "from": "IN_PROGRESS", "to": "GATES_DEFINED", "at": "2026-03-15T08:45:00Z" },
        { "from": "GATES_DEFINED", "to": "GATES_PASSING", "at": "2026-03-15T14:22:00Z" }
      ]
    }
  }
}
```

### Pipeline Advance Script

```bash
# Advance a stage (validates transition rules)
./scripts/pipeline-advance.sh user-authentication REVIEW

# Check current state
./scripts/pipeline-advance.sh user-authentication --status

# View history
./scripts/pipeline-advance.sh user-authentication --history
```

The script enforces transition rules: attempting to jump from IN_PROGRESS to DONE produces an error explaining that GATES_DEFINED, GATES_PASSING, and REVIEW must be completed first.

---

## Component 3: Judge Agent

### Purpose

An independent verifier that evaluates completed work from three perspectives. The judge never sees the builder's self-assessment and never asks the builder "are you done?" -- it checks the evidence directly.

### Three-Perspective Review

1. **Structural Integrity**: Do the expected files exist? Are they non-trivial (not stubs)? Do imports resolve? Are there dead code paths?
2. **Behavioral Correctness**: Do the acceptance gate criteria pass? Do edge cases work? Does error handling function?
3. **Specification Alignment**: Does the implementation match the design spec? Are all specified features present? Are there unspecified additions?

### Integration Point

The judge runs when the pipeline transitions from GATES_PASSING to REVIEW (G3). It produces a structured report:

```json
{
  "judge": "hold-point-judge",
  "timestamp": "2026-03-15T15:00:00Z",
  "gate": "user-authentication",
  "verdict": "APPROVE",
  "perspectives": {
    "structural": { "pass": true, "findings": [] },
    "behavioral": { "pass": true, "findings": [] },
    "specification": {
      "pass": true,
      "findings": [
        "NOTE: Password reset endpoint not in spec but implemented. Verify if intentional."
      ]
    }
  }
}
```

See [docs/judge-agent.md](docs/judge-agent.md) for detailed judge agent design.

---

## Component 4: Bypass Guards

### Purpose

Prevents agents from circumventing the gate system through tool switching, direct file manipulation, or premature completion claims.

### Hook Integration Points

Hold Point integrates with Claude Code's hook system at three levels:

**PreToolUse Hooks** -- Fire before a tool executes:
- Block `pipeline-advance.sh` calls that skip stages
- Block deployment commands when gates have not passed
- Block "mark done" actions without gate evidence

**PostToolUse Hooks** -- Fire after a tool executes:
- Detect code changes that invalidate cached gate results
- Log actions that affect gated features
- Trigger gate re-runs when source files change

**Stop Hooks** -- Fire when the agent attempts to end a conversation:
- Verify all in-progress gates are passing before the session ends
- Warn if gates were passing but source code changed since last run
- Prevent "done" claims without gate evidence

### Gate Invalidation

When source files change, the continuous verification system invalidates affected gates:

```
Agent modifies src/auth/login.py
    |
    v
PostToolUse hook detects file change
    |
    v
Hash of src/auth/login.py has changed
    |
    v
Gate "user-authentication" referenced this file
    |
    v
Gate result INVALIDATED — must re-run before advancing
```

See [docs/bypass-prevention.md](docs/bypass-prevention.md) for comprehensive bypass vector analysis.

---

## Component 5: Continuous Verification

### Purpose

Ensures that gate results remain valid over time. A gate that passed yesterday may fail after today's code changes. Continuous verification detects this regression.

### How It Works

1. **Hash Tracking**: When a gate passes, the runner records the SHA-256 hash of every source file relevant to that gate.
2. **Change Detection**: PostToolUse hooks and pre-commit hooks compare current file hashes against the cached gate result.
3. **Invalidation**: If any relevant file has changed, the gate result is marked STALE and must be re-run.
4. **CI Integration**: The gate runner can be added to CI pipelines to verify gates on every push.

### Staleness Detection

```bash
# Check if any gate results are stale
./scripts/gate-runner.sh --check-stale .hold-point/gates/

# Output:
# user-authentication: STALE (src/auth/login.py changed since last run)
# user-profile: CURRENT (no changes since last run)
# payment-flow: NEVER_RUN (no cached results)
```

### CI/CD Integration

```yaml
# .github/workflows/hold-point.yml
name: Hold Point Gates
on: [push, pull_request]

jobs:
  gate-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run all gates
        run: ./scripts/gate-runner.sh .hold-point/gates/
      - name: Check for stale results
        run: ./scripts/gate-runner.sh --check-stale .hold-point/gates/
```

---

## Integration with Claude Code Hooks

The complete hook configuration for Hold Point:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "name": "hold-point-no-skip-stages",
        "match_tool": "Bash",
        "match_command": "pipeline-advance",
        "command": "./scripts/guards/validate-transition.sh",
        "description": "Validates pipeline state transitions"
      },
      {
        "name": "hold-point-no-deploy-without-gates",
        "match_tool": "Bash",
        "match_command": "deploy|push.*production|systemctl.*restart",
        "command": "./scripts/guards/require-gates-pass.sh",
        "description": "Blocks deployment if gates have not passed"
      }
    ],
    "PostToolUse": [
      {
        "name": "hold-point-invalidate-on-change",
        "match_tool": "Write|Edit",
        "match_file": "src/**",
        "command": "./scripts/guards/invalidate-gates.sh",
        "description": "Invalidates gate results when source code changes"
      }
    ],
    "Stop": [
      {
        "name": "hold-point-verify-before-done",
        "command": "./scripts/guards/check-open-gates.sh",
        "description": "Warns if gates are stale or failing before session ends"
      }
    ]
  }
}
```

---

## Directory Structure

```
.hold-point/
  gates/                  # YAML gate definitions
    auth.yaml
    profile.yaml
    payment.yaml
  results/                # Cached gate results (JSON)
    auth.json
    profile.json
  pipeline.json           # Pipeline state machine
  judge-reports/          # Judge agent output
    auth-2026-03-15.json

scripts/
  gate-runner.sh          # Executes gate criteria
  pipeline-advance.sh     # Manages pipeline transitions
  guards/
    validate-transition.sh
    require-gates-pass.sh
    invalidate-gates.sh
    check-open-gates.sh
```

---

## Design Principles

1. **Criteria before code.** Acceptance criteria are defined before implementation begins, not after. This prevents the agent from defining criteria that match whatever it built.

2. **Live system only.** All verification runs against the actual running system -- not mocks, not unit tests, not documentation. The live system is ground truth.

3. **Independent verification.** The entity that built the feature does not verify it. The judge agent, the gate runner, and the human reviewer are all independent of the builder.

4. **No escape hatches.** There are no `--force` flags, no `--skip-gates` options, no override commands accessible to the AI agent. If a gate must be bypassed, a human modifies the gate definition -- a deliberate, auditable action.

5. **Evidence over claims.** Every state transition produces a timestamped artifact: a gate result JSON, a judge report, an approval record. "It works" is not evidence. A gate result showing HTTP 200 with the expected response body is evidence.
