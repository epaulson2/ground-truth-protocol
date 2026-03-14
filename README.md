# Ground Truth Protocol

**A framework for preventing context drift in AI-assisted multi-agent software development.**

AI coding agents forget what exists. They suggest creating databases that already have 38 tables. They ask for API keys already documented in project files. They build features to specifications they never read. They pass 757 tests while achieving only 18% alignment with design specs.

More rules do not fix this. More documents do not fix this. Research shows that adding instructions past a threshold causes AI agents to *abandon* rules entirely rather than approximately following them. The Ground Truth Protocol replaces passive documentation with mechanical state verification.

---

## The Problem

AI coding agents suffer from **context drift** -- progressive degradation of awareness about project state during extended interactions. This manifests as:

- **Duplicate creation**: Suggesting `CREATE DATABASE` when one already exists with dozens of tables
- **Redundant questions**: Asking users for information already documented in project files
- **Spec misalignment**: Producing code that works but does not match design specifications
- **Rule abandonment**: Ignoring instructions as the instruction count grows

The instinctive response -- adding more rules after each failure -- makes things worse. Research on instruction-following capacity (IFScale, arXiv:2507.11538) shows three degradation patterns: threshold decay, linear decay, and exponential decay. At 500 instructions, even frontier models achieve only 68% accuracy. More critically, models shift from *modification errors* to *complete omission* as instruction density increases. They do not follow the rule incorrectly; they stop following it at all.

## The Solution

The Ground Truth Protocol is a five-component framework that replaces "read this document and follow these rules" with mechanical verification:

| Component | What It Does | Why It Works |
|-----------|-------------|--------------|
| **Pre-Flight Probe** | Script that queries actual system state at session start | Agent receives facts, not instructions to find facts |
| **Assertion Gates** | Pre-condition checks before create/modify actions | Blocks impossible actions mechanically, not advisorily |
| **Three Rules** | Exactly 3 rules, each backed by a hook | Stays within cognitive load limits; hooks enforce compliance |
| **Compaction Directives** | Instructions for what survives context summarization | Critical state information persists across compaction events |
| **Checkpoint Quizzes** | Periodic state re-verification during long sessions | Re-grounds the agent when drift has occurred |

The core insight: **documents are not mechanisms.** A rule that says "check the database before creating one" requires voluntary compliance. A hook that runs `psql -c "SELECT count(*) FROM information_schema.tables"` and injects the result is involuntary. The aviation industry learned this distinction decades ago. Software development with AI agents is learning it now.

## Quick Start

### 1. Create a Pre-Flight Probe (15 minutes)

Write a script that queries your project's actual state and outputs a concise summary:

```bash
#!/bin/bash
echo "=== GROUND TRUTH PROBE ==="
echo "Database: $(psql -c '\dt' 2>/dev/null | tail -n +4 | head -n -2 | wc -l) tables"
echo "Services: $(systemctl list-units --type=service --state=running | grep -c 'myapp')"
echo "Git: $(git log --oneline -1)"
echo "=== END PROBE ==="
```

### 2. Wire It to Session Start

Configure your AI tool to run the probe automatically:

- **Claude Code**: Add a session-start hook in `.claude/settings.json`
- **Cursor**: Reference probe output in `.cursorrules`
- **Aider**: Add to `.aider.conf.yml` conventions

### 3. Add Assertion Gates (30 minutes)

Create pre-condition checks for your most common failure modes:

```bash
# Before any database creation
DB_EXISTS=$(psql -c "SELECT 1" mydb 2>/dev/null && echo "yes" || echo "no")
if [ "$DB_EXISTS" = "yes" ]; then
  echo "BLOCKED: Database already exists."
  exit 1
fi
```

### 4. Reduce Rules to Three

Replace your growing list of AI rules with exactly three:

1. **Probe before act** -- Verify system state before starting any task
2. **Assert before create** -- Check that resources do not already exist before creating them
3. **Spec before code** -- Read the design document before implementing

Back each rule with a mechanical enforcement hook.

### 5. Set Compaction Directives

Tell your AI tool what must survive context summarization:

```markdown
When compacting context, ALWAYS preserve:
1. The most recent probe output
2. All assertion gate results
3. The current task definition and completion criteria
```

## Why Existing Approaches Fail

| Approach | Why It Fails |
|----------|-------------|
| More documentation | Documents require voluntary reading; AI attention distributes across all tokens equally |
| More rules | Each rule adds cognitive load; past a threshold, adding rules decreases compliance on all rules |
| Longer context files | "Lost in the middle" effect: information in middle positions receives minimal attention |
| Post-failure rules | Each new rule is individually rational but collectively self-defeating |
| Trust-based verification | "Did you read the spec?" produces "yes" regardless of whether the spec was read |

## Documentation

| Document | Description |
|----------|-------------|
| [docs/WHY.md](docs/WHY.md) | The context drift problem in depth |
| [docs/FRAMEWORK.md](docs/FRAMEWORK.md) | The five components explained in detail |
| [docs/IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md) | Step-by-step implementation guide |
| [docs/PRE_FLIGHT_PROBE_DESIGN.md](docs/PRE_FLIGHT_PROBE_DESIGN.md) | Designing effective probes for any stack |
| [docs/ASSERTION_GATES.md](docs/ASSERTION_GATES.md) | Pre-condition patterns and hook implementation |
| [docs/THREE_RULES.md](docs/THREE_RULES.md) | Why 3 rules, not 11 or 30 |
| [docs/CASE_STUDY.md](docs/CASE_STUDY.md) | Real-world case study with before/after comparison |
| [docs/ANTI_PATTERNS.md](docs/ANTI_PATTERNS.md) | Common mistakes to avoid |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Academic and industry research citations |

## Examples

| Example | Description |
|---------|-------------|
| [examples/pre-flight-probe.sh](examples/pre-flight-probe.sh) | Generic pre-flight probe script |
| [examples/assertion-gate.sh](examples/assertion-gate.sh) | Generic assertion gate script |
| [examples/claude-code-hooks.json](examples/claude-code-hooks.json) | Hook configuration for Claude Code |
| [examples/cursor-rules.md](examples/cursor-rules.md) | .cursorrules integration |
| [examples/aider-conventions.md](examples/aider-conventions.md) | .aider.conf.yml integration |

## Research Foundation

This framework is grounded in peer-reviewed research:

- **Agent Drift**: 42% task success decline in drifting systems, onset at median 73 interactions (Chen et al., arXiv:2601.04170)
- **Instruction Compliance Degradation**: 68% accuracy at 500 instructions, shift from modification errors to complete omission (IFScale, arXiv:2507.11538)
- **Context Rot**: Accuracy drops from 70-75% to 55-60% based on information placement alone (Chroma Research)
- **Multi-Turn Degradation**: 39% performance drop in multi-turn vs. single-turn conversations (arXiv:2510.07777)
- **Cognitive Load Theory**: Extraneous load accumulation degrades performance independent of information positioning (Sweller, 1988)

See [docs/RESEARCH.md](docs/RESEARCH.md) for full citations.

## License

MIT License. See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
