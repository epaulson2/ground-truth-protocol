# Case Study: Project Redline

This case study describes real failures in a production AI-assisted software project and how the Ground Truth Protocol addresses each one. The project name and some details have been changed, but the failures, their root causes, and the guardrail escalation timeline are real.

## Project Background

Project Redline is a full-stack application with:
- A FastAPI backend (Python 3.12)
- A Next.js 15 frontend
- A PostgreSQL database with 38 tables and 50,000+ records
- 14 design specification documents
- 8 defined agent roles for multi-agent development
- A comprehensive knowledge base with drug information, clinical guidelines, and caregiving resources

The project used AI coding agents extensively for development, with Claude Code as the primary tool.

## The Failures

### Failure 1: Database Recreation

**What happened**: The agent was asked to "set up the database" for a new feature. It responded with `CREATE DATABASE` and `CREATE TABLE` statements -- for a database that already existed with 38 tables and 50,000+ records.

**Root cause**: The agent had no awareness of the existing database. It applied its training prior (how to set up databases in general) because the project's actual database state was not in its context.

**Guardrail that should have prevented it**: Rule 10 in CLAUDE.md -- "DOCS BEFORE QUESTIONS: Before asking the user ANY question about infrastructure... read the relevant doc for the answer."

**Why the guardrail failed**: Rule 10 required the agent to voluntarily remember the rule, voluntarily decide to follow it, voluntarily find the right document, and voluntarily read it. At each step, the agent could (and did) skip to the faster path: just create the database.

### Failure 2: Credential Requests

**What happened**: The agent asked the user for API keys (OpenAI, Anthropic, Google) that were already documented in `PRE_BUILD_OWNER_CHECKLIST.md` with exact configuration instructions.

**Root cause**: Same as Failure 1 -- the agent had no awareness that the answer was documented. Its default behavior when needing information is to ask the user, not to search documentation.

**Guardrail that should have prevented it**: Rule 10 again. Also Rule 11 -- "SESSION START PROTOCOL: At the start of every conversation, reread QCR_COMPASS.md before doing any work."

**Why the guardrail failed**: Rule 11 was added *after* Rule 10 failed. The theory was that if the agent read the master context document at session start, it would know where to find API key documentation. But the master context document was 759 lines -- and research shows that information in middle positions of long documents receives diminishing attention.

### Failure 3: 18% Spec Alignment

**What happened**: A comprehensive audit revealed that despite 757 tests passing, the implemented code matched design specifications at only an 18% alignment rate. The code worked. It did the right things technically. But it did not match what was designed.

**Root cause**: Agents jumped from task description to implementation without reading the design specification documents. They built features based on their training knowledge of "how to build X" rather than the project's specific design for X.

**Guardrail that should have prevented it**: Rule 9 -- "SPEC-DRIVEN IMPLEMENTATION: Before implementing ANY feature, check SPEC_REGISTRY.md for relevant specs, read them IN FULL, cite sections in your implementation plan."

**Why the guardrail failed**: Rule 9 was the most complex rule -- a 6-step process involving checking a registry, reading documents in full, citing sections, using a template, updating alignment percentages, and running a verification script. This is exactly the kind of multi-step rule that research shows is most likely to be abandoned under cognitive load.

### Failure 4: Redundant Questions

**What happened**: The agent asked questions about project architecture, business decisions, and technical constraints that were already answered in project documentation. The user had to repeatedly say "this is documented in X."

**Root cause**: The agent's default behavior is to ask when uncertain. It does not search documentation unless specifically instructed and motivated to do so.

**Guardrail that should have prevented it**: Rules 10 and 11 (again), plus the 759-line QCR_COMPASS.md document that was supposed to contain all essential project context.

**Why the guardrail failed**: By this point, the guardrail system had accumulated so much content that the agent's ability to follow any individual rule was degraded by the total cognitive load.

## The Guardrail Escalation Timeline

Each failure led to a new guardrail. Each guardrail was individually rational. The collection was self-defeating.

| Event | Guardrail Added | Total Rules After |
|-------|----------------|-------------------|
| Project start | 8 rules in CLAUDE.md (code style, build commands, technical constraints) | 8 |
| Database recreation | Rule 9: SPEC-DRIVEN IMPLEMENTATION (6-step process) | 9 |
| 18% spec alignment | Added SPEC_COMPLIANCE.md + verify-spec-compliance.py + SPEC_REGISTRY.md | 9 + 3 docs |
| API key requests | Rule 10: DOCS BEFORE QUESTIONS (multi-step doc search) | 10 |
| Redundant questions | Rule 11: SESSION START PROTOCOL + QCR_COMPASS.md (759 lines) | 11 + 759-line doc |
| Continued failures | 6-layer defense-in-depth system (memory files, invariants, hooks, mistake ledger) | 11 + 6 layers |

**Final state**: 11 numbered rules, a 759-line master context document, a spec registry, a spec compliance system, a 6-layer defense-in-depth system, 76+ research documents, and 14 design documents.

**Result**: Failures continued. The system had crossed the threshold where adding more guardrails degraded rather than improved compliance.

## How Ground Truth Protocol Would Have Prevented Each Failure

### Failure 1 Prevention: Pre-Flight Probe

Instead of Rule 10 ("read docs before asking about infrastructure"), a pre-flight probe runs automatically at session start:

```
=== GROUND TRUTH PROBE 2026-03-14T10:30:00Z ===

## Database (redline_db@127.0.0.1)
Connection: OK
Tables: 38 (public schema)
Key counts: drugs=50279, supplements=1503, interactions=10966

...

=== END PROBE ===
```

The agent's context now contains "38 tables, 50,279 drug records" as injected state. When asked to "set up the database," the agent sees from its own context that the database exists and is populated. No rule needed. No voluntary compliance needed. The state is just there.

Additionally, an assertion gate blocks any `CREATE DATABASE` command by checking whether the database exists:

```
GATE BLOCKED: Database 'redline_db' already exists with 38 tables.
ACTION: Query the existing database. Do not create a new one.
```

Even if the agent somehow ignores the probe output, the assertion gate mechanically blocks the action.

### Failure 2 Prevention: Pre-Flight Probe + Assertion Gate

The probe output includes:

```
## Configured Credentials
  OPENAI_API_KEY: SET (51 chars)
  ANTHROPIC_API_KEY: SET (98 chars)
  GOOGLE_API_KEY: SET (39 chars)
```

When the agent considers asking about API keys, the answer is already in its context: they are configured. If the agent still attempts to ask, an assertion gate searches project documentation for the keywords in the question and responds:

```
GATE BLOCKED: This question may already be answered in documentation.
Relevant files:
  - docs/PRE_BUILD_OWNER_CHECKLIST.md
ACTION: Read these files before asking the user.
```

### Failure 3 Prevention: Spec-Before-Code Rule + Hook

Instead of a 6-step process (Rule 9), a single rule: "Spec before code."

A PostToolUse hook monitors file writes. When a source code file is written, the hook checks whether any spec document was read earlier in the session. If not:

```
GATE WARNING: No spec documents have been read in this session.
Available specs:
  - KNOWLEDGE_BASE_ARCHITECTURE.md
  - API_DESIGN.md
  - FRONTEND_COMPONENT_SPEC.md
ACTION: Read the relevant spec before writing code.
```

The agent cannot ignore this warning because it is injected into its context by the hook system. And the rule is simple enough to hold in active attention: read spec, then write code.

### Failure 4 Prevention: Smallest Effective Context

Instead of loading a 759-line master context document, the probe injects ~100 lines of verified state. Instead of 11 rules, 3 rules backed by hooks. Instead of advisory compliance, mechanical enforcement.

The total cognitive load drops from:
- 11 rules + 759-line document + 6 guardrail layers = thousands of instruction tokens

To:
- 3 rules + ~100-line probe output + hooks that fire automatically = hundreds of instruction tokens

With less cognitive load, the agent has more attention budget for the actual task. With mechanical enforcement, compliance does not depend on attention.

## Before and After

| Metric | Before (11 Rules + Guardrails) | After (Ground Truth Protocol) |
|--------|-------------------------------|-------------------------------|
| Advisory rules | 11 | 3 |
| Context document size | 759 lines | ~100 lines (probe output) |
| Guardrail layers | 6 | 2 (probes + gates) |
| Database recreation | Occurred | Mechanically impossible |
| Credential questions | Occurred | Answered from probe output |
| Spec alignment | 18% | Enforced by hook |
| Redundant questions | Frequent | Blocked by assertion gate |
| Enforcement mechanism | Voluntary (read + decide) | Mechanical (hook + block) |
| Failure response | Add another rule | Add another gate |

## Lessons Learned

1. **Correct rules are not enough.** Every rule in the Redline project was correct. The rules were well-written, specific, and addressed real failures. They failed because they relied on voluntary compliance in an environment where compliance degrades with instruction count.

2. **The escalation trap is real.** Each new guardrail was a rational response to a real failure. But the collection was self-defeating. Recognizing the escalation pattern early is critical.

3. **The distinction between documents and mechanisms is the key insight.** Documents say what should happen. Mechanisms make it happen. When the cost of failure is high, mechanisms are the only reliable defense.

4. **Fewer instructions, mechanically enforced, outperform many instructions, voluntarily followed.** This is not intuitive. The instinct is to be thorough, to cover every case, to document every rule. The research says the opposite: pare down to the essential few and enforce them mechanically.

5. **State injection replaces state instruction.** Instead of "go find out what the database looks like," inject what the database looks like. Instead of "read the docs for API keys," inject whether API keys are configured. The agent does not need to be told to look -- the answer is already in its context.
