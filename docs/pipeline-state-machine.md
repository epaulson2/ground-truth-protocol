# Pipeline State Machine

The pipeline state machine enforces that work progresses through defined stages in order. Each transition has requirements that must be met. The machine prevents skipping stages, prevents premature completion, and creates an auditable trail of how each piece of work moved from start to finish.

---

## State Diagram

```
    +---------------+
    |               |
    | NOT_STARTED   |  Task exists but no work has begun.
    |               |  No gate definitions. No code changes.
    +-------+-------+
            |
            | Trigger: Task assigned to agent
            |
            v
    +---------------+
    |               |
    | IN_PROGRESS   |  Agent is working on the feature.
    |               |  Code is being written. No acceptance
    |               |  gates defined yet.
    +-------+-------+
            |
            | Trigger: At least one YAML gate file created
            |          in .hold-point/gates/
            |
            v
    +---------------+
    |               |
    | GATES_DEFINED |  Acceptance criteria exist in YAML.
    |               |  Human reviews and approves criteria.
    |               |  (Approval Gate G1)
    +-------+-------+
            |
            | Trigger: G1 approved AND gate runner shows
            |          all criteria passing
            |
            v
    +---------------+
    |               |
    | GATES_PASSING |  All acceptance criteria pass against
    |               |  the live system. Agent or human
    |               |  requests review. (Gate G2 = automated,
    |               |  Gate G3 = review requested)
    +-------+-------+
            |
            | Trigger: Judge agent completes review AND
            |          human provides final sign-off (G4)
            |
            v
    +---------------+
    |               |
    |     DONE      |  All gates pass. Judge approved.
    |               |  Human signed off. Feature is verified
    |               |  complete with evidence.
    +---------------+


    Special states:

    +---------------+
    |               |
    |   BLOCKED     |  External dependency or issue prevents
    |               |  progress. Can transition to/from any
    |               |  state except DONE.
    +---------------+

    +---------------+
    |               |
    |   REJECTED    |  Reviewer rejected the work during
    |               |  REVIEW stage. Transitions back to
    |               |  IN_PROGRESS with feedback.
    +---------------+
```

---

## Stage Definitions

### NOT_STARTED

The initial state. A task has been identified but no work has begun.

**Entry conditions:** Task created in the tracking system.
**Exit conditions:** Work begins (agent starts writing code or definitions).
**What exists:** Task description, possibly a design spec.
**What does not exist:** Code, gate definitions, test data.

### IN_PROGRESS

Active work is happening. The agent is writing code, creating configurations, setting up infrastructure.

**Entry conditions:** Agent has begun implementation.
**Exit conditions:** At least one YAML gate file exists in `.hold-point/gates/`.
**What exists:** Code (potentially incomplete), possibly database changes.
**What does not exist:** Formal acceptance criteria.

**Key requirement:** Gate definitions should be written early in the IN_PROGRESS stage, ideally before or alongside the first code. Writing gates after the code is finished defeats the purpose -- the agent will write gates that match whatever it built rather than gates that verify what was specified.

### GATES_DEFINED

Acceptance criteria exist in YAML format. They define what "done" looks like in verifiable terms. The criteria are reviewed by a human before they are used for evaluation.

**Entry conditions:** YAML gate files exist with valid syntax and at least one criterion.
**Exit conditions:** Human approves criteria (G1) AND all criteria pass when run.
**What exists:** Gate YAML files, code (potentially incomplete).
**What does not exist:** Passing gate results.

**Human Approval Gate G1:** A human reviews the YAML gate definitions and confirms they are appropriate:
- Do the criteria test behavior, not just file existence?
- Do they test the live system, not just unit tests?
- Do they cover edge cases, not just happy paths?
- Are they independent of each other (not order-dependent)?

### GATES_PASSING

All acceptance criteria pass against the live system. The feature works as verified by the gate runner. This is the first state where the system has evidence of correct behavior.

**Entry conditions:** Gate runner shows all criteria passing (or passing above `pass_threshold`).
**Exit conditions:** Review requested (G3) and completed by judge agent.
**What exists:** Passing gate results (cached with source hashes), working feature.
**What does not exist:** Independent verification, human sign-off.

**Automated Gate G2:** The gate runner produces a PASS result. This is automated -- no human action required.

**Review Request Gate G3:** The agent or human explicitly requests review, triggering the judge agent. This prevents premature review.

### REVIEW

The judge agent has been invoked and is evaluating the work from three perspectives: structural integrity, behavioral correctness, and specification alignment.

**Entry conditions:** Judge agent has been triggered.
**Exit conditions:** Judge approves AND human signs off (G4), OR reviewer rejects (back to IN_PROGRESS).
**What exists:** Gate results, judge report.

### DONE

The feature is verified complete with full evidence chain: gate results, judge report, human sign-off.

**Entry conditions:** Judge approved, human signed off (G4).
**What exists:** Gate results (cached), judge report, approval record, code.

**This state is terminal.** Once DONE, the feature stays DONE unless a gate result is invalidated by code changes (in which case continuous verification flags it).

### BLOCKED

Work cannot proceed due to an external dependency or issue. Can be entered from any state except DONE.

**Entry conditions:** External blocker identified.
**Exit conditions:** Blocker resolved, returns to previous state.
**What exists:** A description of the blocker and the state to return to when resolved.

### REJECTED

The reviewer (human or judge) rejected the work. Includes feedback about what needs to change.

**Entry conditions:** Reviewer rejects during REVIEW stage.
**Exit conditions:** Transitions to IN_PROGRESS with feedback attached.
**What exists:** Rejection reason, specific feedback, gate results that may need updating.

---

## Human Approval Gates (G1-G4)

Four gates require explicit human action. These cannot be automated or self-approved by the agent.

### G1: Criteria Approval

**When:** Before gates are evaluated (GATES_DEFINED -> GATES_PASSING transition).
**Who:** Human (project owner, tech lead, or reviewer).
**What they review:** The YAML gate definitions.
**What they approve:** That the criteria are appropriate, complete, and test the right things.

**Why this gate exists:** Without G1, the agent can write trivially-passing criteria. "Does the file exist? Yes. Gate passes." G1 ensures that a human has reviewed the criteria and confirmed they actually verify completion.

```bash
# Human approves criteria
./scripts/pipeline-advance.sh auth GATES_PASSING --approve-g1 --by epaulson2
```

### G2: Gates Pass

**When:** After criteria are approved (automated).
**Who:** Gate runner (automated).
**What it checks:** All criteria pass against the live system.

**Why this gate exists:** This is the mechanical verification. No human judgment required -- the gates either pass or they do not.

### G3: Review Requested

**When:** After gates pass (GATES_PASSING -> REVIEW transition).
**Who:** Agent or human.
**What it triggers:** The judge agent begins its three-perspective review.

**Why this gate exists:** Prevents the judge from running before the work is ready. The agent explicitly signals "I believe this is done" by requesting review.

```bash
# Request review
./scripts/pipeline-advance.sh auth REVIEW --request-review
```

### G4: Final Sign-off

**When:** After judge approves (REVIEW -> DONE transition).
**Who:** Human (project owner, tech lead, or reviewer).
**What they review:** Gate results, judge report, and the feature itself.
**What they approve:** That the feature is truly complete and ready to ship.

**Why this gate exists:** The final defense. Even with gates passing and the judge approving, a human reviews the evidence and makes the final call.

```bash
# Final sign-off
./scripts/pipeline-advance.sh auth DONE --approve-g4 --by epaulson2
```

---

## How `pipeline-advance.sh` Enforces Transitions

The `pipeline-advance.sh` script is the only way to change pipeline state. It validates every transition against the rules.

### Valid Transitions

```bash
# Start work
./scripts/pipeline-advance.sh auth IN_PROGRESS
# OK: NOT_STARTED -> IN_PROGRESS (no requirements)

# Define gates
./scripts/pipeline-advance.sh auth GATES_DEFINED
# OK: IN_PROGRESS -> GATES_DEFINED (requires: gate YAML files exist)

# Gates pass + criteria approved
./scripts/pipeline-advance.sh auth GATES_PASSING --approve-g1 --by epaulson2
# OK: GATES_DEFINED -> GATES_PASSING (requires: G1 approval + gates pass)

# Request review
./scripts/pipeline-advance.sh auth REVIEW --request-review
# OK: GATES_PASSING -> REVIEW (requires: gates still passing)

# Final sign-off
./scripts/pipeline-advance.sh auth DONE --approve-g4 --by epaulson2
# OK: REVIEW -> DONE (requires: judge approved + G4 sign-off)
```

### Invalid Transitions (Blocked)

```bash
# Skip from IN_PROGRESS to DONE
./scripts/pipeline-advance.sh auth DONE
# ERROR: Cannot transition from IN_PROGRESS to DONE.
# Required path: IN_PROGRESS -> GATES_DEFINED -> GATES_PASSING -> REVIEW -> DONE
# Current state: IN_PROGRESS
# Next required state: GATES_DEFINED (requires: gate YAML files exist)

# Advance without approval
./scripts/pipeline-advance.sh auth GATES_PASSING
# ERROR: Cannot transition to GATES_PASSING without G1 approval.
# Run: ./scripts/pipeline-advance.sh auth GATES_PASSING --approve-g1 --by <your-name>

# Mark done without review
./scripts/pipeline-advance.sh auth DONE --approve-g4 --by epaulson2
# ERROR: Cannot transition from GATES_PASSING to DONE.
# Must pass through REVIEW first.
```

---

## Pipeline State JSON Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "version": { "type": "integer", "const": 1 },
    "stages": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["status", "entered_at"],
        "properties": {
          "status": {
            "type": "string",
            "enum": ["NOT_STARTED", "IN_PROGRESS", "GATES_DEFINED",
                     "GATES_PASSING", "REVIEW", "DONE", "BLOCKED", "REJECTED"]
          },
          "entered_at": { "type": "string", "format": "date-time" },
          "gate_file": { "type": "string" },
          "last_gate_run": { "type": "string", "format": "date-time" },
          "gate_result": { "type": "string", "enum": ["PASS", "FAIL", "STALE", "NEVER_RUN"] },
          "approvals": {
            "type": "object",
            "properties": {
              "G1": { "$ref": "#/$defs/approval" },
              "G2": { "$ref": "#/$defs/approval" },
              "G3": { "$ref": "#/$defs/approval" },
              "G4": { "$ref": "#/$defs/approval" }
            }
          },
          "judge_report": { "type": "string" },
          "rejection_reason": { "type": "string" },
          "blocker": { "type": "string" },
          "return_to": { "type": "string" },
          "history": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["from", "to", "at"],
              "properties": {
                "from": { "type": "string" },
                "to": { "type": "string" },
                "at": { "type": "string", "format": "date-time" },
                "by": { "type": "string" },
                "reason": { "type": "string" }
              }
            }
          }
        }
      }
    }
  },
  "$defs": {
    "approval": {
      "type": "object",
      "required": ["by", "at"],
      "properties": {
        "by": { "type": "string" },
        "at": { "type": "string", "format": "date-time" },
        "notes": { "type": "string" }
      }
    }
  }
}
```

---

## Examples

### Example 1: Feature from start to finish

```bash
# 1. Start work on authentication
./scripts/pipeline-advance.sh auth IN_PROGRESS
# State: IN_PROGRESS

# 2. Agent writes code and creates gate definitions
# ... agent creates .hold-point/gates/auth.yaml ...
./scripts/pipeline-advance.sh auth GATES_DEFINED
# State: GATES_DEFINED

# 3. Human reviews criteria, approves G1. Gates are run and pass.
./scripts/pipeline-advance.sh auth GATES_PASSING --approve-g1 --by epaulson2
# Running gates: .hold-point/gates/auth.yaml
# [PASS] login-endpoint (HTTP 200)
# [PASS] password-hashing (bcrypt detected)
# [PASS] jwt-token (valid JWT)
# RESULT: 3/3 passing
# State: GATES_PASSING (G1 approved, G2 automated)

# 4. Request review
./scripts/pipeline-advance.sh auth REVIEW --request-review
# Judge agent running...
# Structural: PASS (3 files, 245 lines, no stubs)
# Behavioral: PASS (3/3 gates, edge cases covered)
# Specification: PASS (matches auth-spec.md)
# Judge verdict: APPROVE
# State: REVIEW (G3 complete)

# 5. Human final sign-off
./scripts/pipeline-advance.sh auth DONE --approve-g4 --by epaulson2
# State: DONE
```

### Example 2: Rejection and rework

```bash
# Agent submits for review
./scripts/pipeline-advance.sh auth REVIEW --request-review
# Judge agent running...
# Structural: PASS
# Behavioral: FAIL — password reset endpoint returns 500
# Specification: FAIL — rate limiting not implemented (required by spec)
# Judge verdict: REJECT

# Pipeline transitions back to IN_PROGRESS
./scripts/pipeline-advance.sh auth IN_PROGRESS --reason "Judge rejected: missing rate limiting, broken password reset"
# State: IN_PROGRESS

# Agent fixes issues, gates re-run
./scripts/pipeline-advance.sh auth GATES_PASSING --approve-g1 --by epaulson2
# All gates pass including new ones for rate limiting
# State: GATES_PASSING

# Second review attempt
./scripts/pipeline-advance.sh auth REVIEW --request-review
# Judge verdict: APPROVE
# State: REVIEW

# Final sign-off
./scripts/pipeline-advance.sh auth DONE --approve-g4 --by epaulson2
# State: DONE
```

### Example 3: Blocked by external dependency

```bash
# Feature depends on third-party API that is down
./scripts/pipeline-advance.sh payment BLOCKED --reason "Stripe sandbox API unavailable since 2026-03-14"
# State: BLOCKED (previous state: IN_PROGRESS)

# Stripe comes back online
./scripts/pipeline-advance.sh payment IN_PROGRESS --unblock
# State: IN_PROGRESS (restored from BLOCKED)
```

---

## Viewing Pipeline State

```bash
# Check status of a specific feature
./scripts/pipeline-advance.sh auth --status
# auth: GATES_PASSING
#   Entered: 2026-03-15T14:22:00Z
#   Gates: 3/3 passing
#   G1: approved by epaulson2 at 2026-03-15T14:20:00Z
#   G2: automated PASS at 2026-03-15T14:22:00Z
#   G3: not yet requested
#   G4: not yet approved

# View full history
./scripts/pipeline-advance.sh auth --history
# 2026-03-15T08:00:00Z  NOT_STARTED -> IN_PROGRESS
# 2026-03-15T08:45:00Z  IN_PROGRESS -> GATES_DEFINED
# 2026-03-15T14:20:00Z  GATES_DEFINED -> GATES_PASSING (G1: epaulson2)

# View all features
./scripts/pipeline-advance.sh --all
# auth:       GATES_PASSING (3/3 gates passing)
# profile:    IN_PROGRESS (no gates defined)
# payment:    BLOCKED (Stripe API down)
# settings:   DONE (completed 2026-03-14)
```
