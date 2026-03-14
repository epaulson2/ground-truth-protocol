# The Ground Truth Protocol Framework

## Design Principles

The Ground Truth Protocol is built on five principles derived from academic research on agent drift, cognitive load theory, and real-world failure analysis:

1. **Mechanisms over documents.** If a behavior must always happen, implement it as a script or hook, not as a rule to follow.
2. **State injection over state reading.** Instead of telling the agent to read a document, run a script that injects actual state into the context.
3. **Fewer rules, mechanically enforced.** Replace many advisory rules with few rules backed by deterministic hooks.
4. **Verification artifacts over verbal claims.** Every verification step produces a timestamped artifact that proves it happened.
5. **Smallest effective context.** Load only what the agent needs for the current task, not everything that might possibly be relevant.

---

## Component 1: Pre-Flight Probe

### What It Does

A script that runs at the start of every AI session, queries the actual state of the project (database, services, files, credentials, git state), and injects a concise summary into the AI agent's context.

### Why It Works

The probe replaces a large context document (which the agent may or may not read) with a small, factual output (which is automatically present in context). The agent does not need to be instructed to "check the database" -- the probe output already tells it what the database contains.

This is the difference between:
- **Advisory**: "Before starting, read PROJECT_STATE.md to understand what exists" (agent may skip this)
- **Mechanical**: Probe output is injected automatically, showing "Database: 38 tables, 50,279 drug records" (agent cannot avoid seeing this)

The probe addresses three root causes simultaneously:
- **Context rot**: Fresh state information is at the top of context (high attention position)
- **Staleness**: The probe runs live queries, so the output is always current
- **Voluntary compliance**: The probe runs automatically via hook, requiring no agent decision

### How to Implement

1. Write a shell script that queries your project's key state indicators
2. Keep the output under 2,000 tokens (concise summaries, not raw data)
3. Configure it as a session-start hook in your AI tool
4. Verify the output appears in the agent's context at the beginning of every session

### Example

```bash
#!/bin/bash
echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

echo "## Database"
TABLE_COUNT=$(psql -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" mydb 2>/dev/null || echo "0")
echo "Tables: $TABLE_COUNT"

echo "## Services"
systemctl list-units --type=service --state=running --no-pager | grep -E 'api|web|worker' || echo "No app services running"

echo "## Git"
git log --oneline -3
git status --short | head -10

echo "## Environment"
for key in DATABASE_URL API_KEY SECRET_KEY; do
  if [ -n "${!key}" ]; then
    echo "  $key: CONFIGURED"
  else
    echo "  $key: NOT SET"
  fi
done

echo "=== END PROBE ==="
```

See [PRE_FLIGHT_PROBE_DESIGN.md](PRE_FLIGHT_PROBE_DESIGN.md) for detailed probe design guidance.

---

## Component 2: Assertion Gates

### What It Does

Pre-condition checks that run automatically before the agent performs create, modify, or delete actions. If the pre-condition fails, the action is blocked and the agent receives an explanation of why.

### Why It Works

Assertion gates implement the aviation principle of **positive confirmation**: before a critical action, verify that conditions support the action. Unlike advisory rules that rely on the agent choosing to check, assertion gates are wired into the tool execution pipeline and fire regardless of the agent's intent.

The gate transforms the failure mode from:
- "Agent forgot to check" (common, unpredictable) to
- "Agent was told the check failed" (deterministic, actionable)

When an assertion gate blocks an action, the agent receives specific information about why (e.g., "Database already exists with 38 tables") and can adjust its approach. This is fundamentally different from hoping the agent remembers to check on its own.

### How to Implement

1. Identify your most common failure modes (duplicate creation, missing prerequisites, etc.)
2. Write a script for each that checks the pre-condition and exits non-zero if it fails
3. Wire the scripts as PreToolUse hooks that match the relevant tool and command patterns
4. Include informative error messages that tell the agent what to do instead

### Example

```bash
#!/bin/bash
# Assertion: Database does not already exist
# Trigger: Before any Bash command containing "CREATE DATABASE" or "createdb"

DB_NAME="${1:-mydb}"
if psql -c "SELECT 1" "$DB_NAME" 2>/dev/null; then
  TABLE_COUNT=$(psql -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" "$DB_NAME")
  echo "ASSERTION FAILED: Database '$DB_NAME' already exists with ${TABLE_COUNT} tables."
  echo "Query the existing database instead of creating a new one."
  exit 1
fi
echo "ASSERTION PASSED: Database '$DB_NAME' does not exist."
exit 0
```

See [ASSERTION_GATES.md](ASSERTION_GATES.md) for comprehensive assertion gate patterns.

---

## Component 3: Three Rules

### What It Does

Replaces a growing list of advisory rules (11, 20, 30...) with exactly three rules, each backed by a mechanical enforcement mechanism.

### Why It Works

Cognitive load research shows that working memory has limits. The IFScale benchmark demonstrates that AI model compliance degrades as instruction count increases, with frontier models achieving only 68% accuracy at 500 instructions. More critically, models shift from modification errors to complete omission -- they abandon instructions rather than approximately following them.

Three rules can be held in active attention simultaneously. Each rule has exactly one action. Each rule is backed by a hook that enforces compliance mechanically. The rules are not the primary defense -- the hooks are. The rules exist as cognitive anchors that help the agent understand why the hooks are running.

### The Three Meta-Rules

These three rules apply to any project. They can be customized, but the count should remain at three:

**Rule 1: Probe Before Act**
> Before starting any task, verify that the pre-flight probe output is in your context. If it is not, run it.

*Enforcement*: Session-start hook runs the probe automatically. The rule is a fallback for mid-session tasks.

**Rule 2: Assert Before Create**
> Before creating any resource (database, file, service, infrastructure), assert that it does not already exist.

*Enforcement*: PreToolUse hooks intercept create actions and run assertion scripts.

**Rule 3: Spec Before Code**
> Before implementing any feature, read the design specification. No spec, no code.

*Enforcement*: PostToolUse hook checks whether spec files were read before code files were modified.

### What Happened to the Other Rules?

The rules you used to have do not get deleted. They get **demoted from instructions to assertions**. A rule like "use 127.0.0.1 not localhost for PostgreSQL" becomes an assertion gate that checks connection strings, not a rule the agent must remember. A rule like "run tests before deploying" becomes a CI gate, not an instruction.

The principle: if a rule can be mechanically enforced, it should not be an instruction. Instructions are for things that require judgment. Mechanical facts are for hooks.

See [THREE_RULES.md](THREE_RULES.md) for detailed guidance on distilling your rules.

---

## Component 4: Compaction Directives

### What It Does

Specifies what information must survive when the AI tool's context is summarized (compacted) due to approaching token limits.

### Why It Works

AI coding tools like Claude Code automatically compact conversation history when it approaches the context window limit. The compaction algorithm decides what to keep based on its assessment of relevance. Without explicit directives, it may discard the probe output ("implementation detail") or assertion gate results ("resolved issue") -- exactly the information that prevents context drift.

Compaction directives tell the summarization algorithm: "This is not an implementation detail. This is a precondition for correct behavior. Keep it."

### How to Implement

Add a short section to your AI tool's configuration (CLAUDE.md, .cursorrules, etc.):

```markdown
## Compaction Directives

When compacting context, ALWAYS preserve:
1. The most recent pre-flight probe output (database state, service state, credentials)
2. All assertion gate results (pass or fail) from the current session
3. The list of spec documents read in this session
4. The current task definition and its completion criteria
```

### Why This Component Is Critical

Without compaction directives, a session can proceed correctly for hours (probe was run, assertions passed, specs were read) and then lose all of that context during a compaction event. After compaction, the agent is back to its training prior -- suggesting `CREATE DATABASE` for a database it verified 45 minutes ago but no longer remembers verifying.

Compaction directives are the persistence layer for the Ground Truth Protocol. They ensure that the protocol's artifacts survive the context lifecycle.

---

## Component 5: Checkpoint Quizzes

### What It Does

At regular intervals during a session (e.g., every 50 tool calls), a hook injects a brief quiz that forces the agent to re-verify its understanding of project state by running specific commands.

### Why It Works

Even with probes, assertions, and compaction directives, context drift can occur during long sessions. The agent accumulates conversation history, code context, and intermediate results that gradually push the original probe output further from active attention. The checkpoint quiz re-anchors the agent to actual state.

The quiz does not ask the agent what it remembers. It tells the agent to run specific verification commands. This ensures that the agent's context is refreshed with current state, not with its potentially stale memory of state.

### How to Implement

Create a hook that triggers periodically and injects verification commands:

```bash
#!/bin/bash
echo "=== CHECKPOINT: RE-VERIFY STATE ==="
echo "Run these commands before continuing:"
echo "1. Database: psql -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema='public'\" mydb"
echo "2. Services: systemctl list-units --type=service --state=running | grep myapp"
echo "3. Current spec: ls -la docs/design/ | head -5"
echo "=== RUN THESE NOW ==="
```

The key design choice: the quiz includes the **specific commands to run**, not questions to answer from memory. "How many tables exist?" is a memory question that can be answered incorrectly. "Run `psql -c 'SELECT count(*)'`" is an action that produces verified output.

### Frequency Tuning

- Start at every 50 tool calls
- If checkpoint results consistently match expectations, increase the interval
- If checkpoints reveal drift (agent's actions contradicted actual state), decrease the interval
- In critical sessions (deploying, migrating), decrease to every 25 tool calls

---

## Architecture Diagram

```
Session Start
     |
     v
[Pre-Flight Probe] -----> State injected into context
     |
     v
[Agent receives task]
     |
     v
[Rule 3: Load spec] -----> PostToolUse hook verifies spec was read
     |
     v
[Agent plans implementation]
     |
     v
[Agent attempts action]
     |
     v
[Rule 2: Assertion Gate] --> PreToolUse hook checks preconditions
     |                        |
     | (pass)                 | (fail)
     v                        v
[Action executes]       [Action blocked, agent informed why]
     |
     v
[Every N actions: Checkpoint Quiz] --> Agent re-probes state
     |
     v
[Context approaching limit]
     |
     v
[Compaction with directives] --> Probe results, gates, specs preserved
     |
     v
[Continue with verified state]
```

## Cognitive Load Theory Backing

The framework is informed by Cognitive Load Theory (Sweller, 1988, 1994):

- **Intrinsic load**: The complexity of the task itself (building a feature). This is irreducible.
- **Extraneous load**: Complexity from how instructions are presented (11 rules, 6 layers, 759 lines of context). This is reducible.
- **Germane load**: Effort devoted to building understanding. This is desirable.

The Ground Truth Protocol reduces extraneous load by:
- Replacing 11 rules with 3 (fewer items in working memory)
- Replacing document reading with state injection (no effort to find and read)
- Replacing advisory compliance with mechanical enforcement (no cognitive decision to comply)

The result: more cognitive budget is available for intrinsic and germane load -- actually understanding the task and building the solution.

### The Aviation Analogy

Before every flight, pilots run a pre-flight checklist. They do not rely on memory. They do not read a 759-line document about how airplanes work. They execute a specific, short checklist that verifies the actual state of the actual aircraft in front of them.

The aviation industry learned that:
- Checklists must be short (human working memory limits)
- Checklists must verify actual state (not recall from memory)
- Checklists must be mandatory (not voluntary)
- Checklists must be mechanical (physical confirmation, not mental acknowledgment)

The Ground Truth Protocol applies these principles to AI-assisted development. The pre-flight probe is the checklist. The assertion gates are the go/no-go decisions. The three rules are the emergency procedures. The compaction directives are the flight recorder. The checkpoint quizzes are the in-flight verification.
