<p align="center">
  <h1 align="center">Hold Point</h1>
  <p align="center">
    <strong>Machine-Enforced Completion Verification for AI Agents</strong>
  </p>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
  <a href="docs/architecture.md"><img alt="Architecture" src="https://img.shields.io/badge/docs-architecture-green.svg"></a>
  <a href="docs/getting-started.md"><img alt="Getting Started" src="https://img.shields.io/badge/docs-getting%20started-orange.svg"></a>
  <a href="docs/research-summary.md"><img alt="Research" src="https://img.shields.io/badge/research-grounded-purple.svg"></a>
</p>

---

## The Problem

AI agents mark work as "done" when it is 25-75% complete.

This is not a minor inconvenience. In a real production project (the [Queen City Redline case study](docs/real-world-case-study.md)), an audit revealed that **7 of 14 plan sections marked DONE were actually skeletons** -- stub files, missing wiring, untested code. The agent had written code, declared victory, and moved on. 757 tests passed. Spec alignment was 18%.

The instinctive response is to add rules. "Always verify before marking done." "Run tests before claiming complete." "Check that the feature is wired into the application." Each rule is correct. Each rule addresses a real failure. Each rule is ignored under pressure.

Adding more rules does not work. Research shows that AI agents do not approximately follow more rules -- they **abandon rules entirely** as instruction density increases. At 500 instructions, even frontier models achieve only 68% accuracy. The error type shifts from doing the wrong thing to **not doing the thing at all**.

The problem is not that agents are sloppy. The problem is that **completion verification is voluntary**.

## The Research

Hold Point is grounded in research across six domains that have already solved this problem:

| Domain | System | Key Insight |
|--------|--------|-------------|
| **Aerospace** | DO-178C, NASA RVM | Software cannot fly without independent verification against requirements |
| **Nuclear** | ITAAC | Reactors cannot operate until every acceptance criterion has physical evidence |
| **Manufacturing** | Toyota Jidoka, Poka-yoke | The production line physically stops when quality fails; errors are made impossible by design |
| **Big Tech** | Google Canary, Netflix Chaos Engineering, Spotify Honk | Verification runs continuously against live systems, not test environments |
| **AI Research** | OpenAI Process Reward Models | Verifying each step outperforms verifying only the final answer |
| **Software QA** | The 5-layer QA system (68 documented failures) | Rules, checklists, and self-verification all fail; only mechanical enforcement works |

Full research: [docs/research-summary.md](docs/research-summary.md)

What does not work (and why): [docs/what-doesnt-work.md](docs/what-doesnt-work.md)

## The Core Finding

Reliable completion verification requires exactly **5 properties**. Remove any one and the system fails:

```
                    +-----------------------------------------+
                    |         HOLD POINT SYSTEM                |
                    |                                          |
                    |  1. PRE-DEFINED ACCEPTANCE CRITERIA      |
                    |     (before work starts)                 |
                    |              |                            |
                    |              v                            |
                    |  2. INDEPENDENT VERIFICATION             |
                    |     (not self-assessed)                  |
                    |              |                            |
                    |              v                            |
                    |  3. VERIFICATION AGAINST LIVE SYSTEM     |
                    |     (not mocks, not docs)                |
                    |              |                            |
                    |              v                            |
                    |  4. BLOCKING ENFORCEMENT                 |
                    |     (cannot advance without passing)     |
                    |              |                            |
                    |              v                            |
                    |  5. BYPASS PREVENTION                    |
                    |     (all tool paths guarded)             |
                    |                                          |
                    +-----------------------------------------+
```

**Why each property is necessary:**

1. **Pre-defined criteria** -- Without them, the agent defines its own success. It will always succeed by its own definition.
2. **Independent verification** -- Self-assessment always passes. The entity that did the work cannot objectively evaluate the work.
3. **Live system verification** -- Mocks, docs, and unit tests can all pass while the feature is broken in production. Only the live system is ground truth.
4. **Blocking enforcement** -- Advisory verification ("you should check...") is skipped under pressure. The pipeline must physically stop.
5. **Bypass prevention** -- An agent blocked on one tool path will switch to another. Every path must be guarded.

## Architecture

```
                          HOLD POINT ARCHITECTURE

    +-----------------+     +-------------------+     +------------------+
    | ACCEPTANCE GATE |     |  PIPELINE STATE   |     |   JUDGE AGENT    |
    |     ENGINE      |     |    MACHINE        |     |                  |
    |                 |     |                   |     |  Independent     |
    |  YAML gate      |     |  NOT_STARTED -->  |     |  verifier that   |
    |  definitions    |     |  IN_PROGRESS -->  |     |  checks work     |
    |  with criteria  |     |  GATES_DEFINED -->|     |  against criteria|
    |  and checks     |     |  GATES_PASSING -->|     |  from 3 angles   |
    |                 |     |  REVIEW --> DONE  |     |                  |
    +---------+-------+     +---------+---------+     +--------+---------+
              |                       |                         |
              |                       |                         |
              v                       v                         v
    +---------------------------------------------------------+----------+
    |                     BYPASS GUARDS                                   |
    |                                                                     |
    |  PreToolUse hooks  |  PostToolUse hooks  |  Stop hooks              |
    |  Block tool calls  |  Validate outputs   |  Verify before           |
    |  that skip gates   |  match criteria     |  marking done            |
    +---------------------------------------------------------------------+
              |                       |                         |
              v                       v                         v
    +---------------------------------------------------------------------+
    |                  CONTINUOUS VERIFICATION                             |
    |                                                                     |
    |  Gate results cached with code hashes                               |
    |  Code changes invalidate relevant gates                             |
    |  Regression detection on every commit                               |
    +---------------------------------------------------------------------+
```

See [docs/architecture.md](docs/architecture.md) for the full technical architecture.

## Quick Start

Add Hold Point to any Claude Code project in 15 minutes:

### 1. Define acceptance criteria for your current task

```yaml
# .hold-point/gates/my-feature.yaml
gate:
  name: user-authentication
  stage: backend
  criteria:
    - name: login-endpoint-exists
      type: http
      method: POST
      url: http://localhost:8000/api/auth/login
      body: '{"email": "test@example.com", "password": "test"}'
      expect_status: 200

    - name: password-hashed-in-db
      type: command
      run: |
        psql -t -c "SELECT password FROM users WHERE email='test@example.com'" mydb \
          | grep -q '^\$2b\$'
      expect_exit: 0

    - name: jwt-token-returned
      type: command
      run: |
        curl -s -X POST http://localhost:8000/api/auth/login \
          -H 'Content-Type: application/json' \
          -d '{"email": "test@example.com", "password": "test"}' \
          | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" \
          | grep -qE '^eyJ'
      expect_exit: 0
```

### 2. Run the gates

```bash
./scripts/gate-runner.sh .hold-point/gates/my-feature.yaml
```

Output:
```
=== HOLD POINT GATE: user-authentication ===
[PASS] login-endpoint-exists (HTTP POST -> 200)
[PASS] password-hashed-in-db (bcrypt hash found)
[PASS] jwt-token-returned (JWT token in response)
RESULT: 3/3 criteria passing. Gate OPEN.
```

### 3. Configure hooks to enforce it

```json
{
  "hooks": {
    "PreToolUse": [{
      "name": "hold-point-gate-check",
      "match_tool": "Bash",
      "match_command": "deploy|push|release",
      "command": "./scripts/gate-runner.sh .hold-point/gates/"
    }],
    "Stop": [{
      "name": "hold-point-completion-check",
      "command": "./scripts/verify-gates-before-done.sh"
    }]
  }
}
```

For the full setup guide, see [docs/getting-started.md](docs/getting-started.md).

## Components

### 1. Acceptance Gate Engine

YAML-defined acceptance criteria with a runner that executes checks against the live system.

Gate types: `file_exists`, `command`, `http`, `sql`

See [docs/acceptance-gates.md](docs/acceptance-gates.md)

### 2. Pipeline State Machine

Enforced state transitions that prevent advancing without passing gates. Each stage has human approval gates (G1-G4) that require explicit sign-off.

```
NOT_STARTED -> IN_PROGRESS -> GATES_DEFINED -> GATES_PASSING -> REVIEW -> DONE
                                    |                |              |
                                    G1               G2             G3
                               (criteria          (gates        (human
                                approved)          pass)        sign-off)
```

See [docs/pipeline-state-machine.md](docs/pipeline-state-machine.md)

### 3. Judge Agent

An independent AI agent (or script) that verifies work from three perspectives: structural integrity, behavioral correctness, and specification alignment. The judge never sees the builder's self-assessment.

See [docs/judge-agent.md](docs/judge-agent.md)

### 4. Bypass Guards

Hook-based prevention of the ways agents circumvent verification: tool switching, direct file writes, output manipulation, and premature completion claims.

See [docs/bypass-prevention.md](docs/bypass-prevention.md)

### 5. Continuous Verification

Gate results are cached with code hashes. When code changes, affected gates are automatically invalidated and must re-pass. This prevents regression -- a gate that passed yesterday may fail after today's changes.

See [docs/architecture.md#continuous-verification](docs/architecture.md#continuous-verification)

## Why "Hold Point"?

In manufacturing quality control, a **hold point** is a stage in production where work physically cannot proceed without an inspector's sign-off. The production line stops. The part does not move to the next station. No amount of schedule pressure, verbal assurance, or self-certification can release the hold.

This is the opposite of a "checkpoint" or a "review" -- which are advisory. A hold point is mechanical. The work is physically blocked until an independent party verifies it meets acceptance criteria.

AI agent development needs hold points, not checkpoints. When an agent says "I'm done with the authentication system," the system should not take the agent's word for it. It should run the acceptance gates, verify against the live system, and only release the hold when every criterion passes.

The name is borrowed from:
- **Manufacturing**: ISO 10005 quality plans define hold points as mandatory inspection stages
- **Nuclear construction**: NRC ITAAC (Inspections, Tests, Analyses, and Acceptance Criteria) are hold points for reactor operation
- **Aerospace**: DO-178C defines verification hold points where software cannot advance without evidence
- **Construction**: ITP (Inspection and Test Plans) define hold points before concrete pours, structural welds, and critical assemblies

In every industry where failure is catastrophic, hold points replaced trust-based verification decades ago. Software development with AI agents is learning the same lesson now.

## Documentation

| Document | Description |
|----------|-------------|
| [docs/architecture.md](docs/architecture.md) | System architecture, component diagrams, data flow |
| [docs/acceptance-gates.md](docs/acceptance-gates.md) | Writing acceptance gate YAML files |
| [docs/pipeline-state-machine.md](docs/pipeline-state-machine.md) | Pipeline stages, transitions, enforcement |
| [docs/judge-agent.md](docs/judge-agent.md) | Independent verification pattern |
| [docs/bypass-prevention.md](docs/bypass-prevention.md) | Guarding against agent workarounds |
| [docs/getting-started.md](docs/getting-started.md) | Step-by-step setup guide |
| [docs/research-summary.md](docs/research-summary.md) | Research foundation across 6 domains |
| [docs/what-doesnt-work.md](docs/what-doesnt-work.md) | Approaches that fail (with evidence) |
| [docs/real-world-case-study.md](docs/real-world-case-study.md) | The Queen City Redline story |

## Existing Framework Documentation

Hold Point builds on the Ground Truth Protocol, which addresses context drift:

| Document | Description |
|----------|-------------|
| [docs/WHY.md](docs/WHY.md) | The context drift problem in depth |
| [docs/FRAMEWORK.md](docs/FRAMEWORK.md) | The five Ground Truth Protocol components |
| [docs/IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md) | Step-by-step implementation guide |
| [docs/PRE_FLIGHT_PROBE_DESIGN.md](docs/PRE_FLIGHT_PROBE_DESIGN.md) | Designing effective probes |
| [docs/ASSERTION_GATES.md](docs/ASSERTION_GATES.md) | Pre-condition patterns and hooks |
| [docs/THREE_RULES.md](docs/THREE_RULES.md) | Why 3 rules, not 11 or 30 |
| [docs/CASE_STUDY.md](docs/CASE_STUDY.md) | Context drift case study |
| [docs/ANTI_PATTERNS.md](docs/ANTI_PATTERNS.md) | Common mistakes to avoid |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Academic and industry citations |

## Status

Born from the [Queen City Redline](docs/real-world-case-study.md) project, March 2026.

The Ground Truth Protocol addresses context drift (agents forgetting what exists). Hold Point addresses the completion gap (agents claiming work is done when it is not). Together, they provide mechanical verification at two critical failure points: **before work starts** (probe the system) and **before work is accepted** (verify the criteria).

## License

MIT License. See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
