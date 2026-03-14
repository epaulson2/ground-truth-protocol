# Implementation Guide

A step-by-step guide for adding the Ground Truth Protocol to any software project that uses AI coding agents.

## Prerequisites

- A software project with at least a database, file structure, or running services
- An AI coding tool (Claude Code, Cursor, aider, Copilot Workspace, or similar)
- Shell access to the development environment
- 2-4 hours for initial setup

## Step 1: Audit Your Current Failures (30 minutes)

Before implementing the protocol, identify your most common failure modes. Review your recent sessions and look for:

- [ ] Agent suggested creating a resource that already existed
- [ ] Agent asked a question already answered in project documentation
- [ ] Agent built something that did not match the specification
- [ ] Agent ignored a rule you had explicitly written
- [ ] Agent forgot context from earlier in the session

Write down the top 3 failures. These become your first assertion gates.

## Step 2: Write Your Pre-Flight Probe (30 minutes)

Create a script that answers the questions your agent most commonly gets wrong. The probe should cover:

### What to Probe

| Category | What to Check | Example Command |
|----------|--------------|----------------|
| Database | Table count, key row counts | `psql -c "\dt" mydb \| wc -l` |
| Services | What is running | `systemctl list-units --state=running \| grep myapp` |
| Git | Current branch, recent commits, uncommitted changes | `git status --short && git log --oneline -3` |
| Environment | Which credentials are configured (not their values) | `env \| grep API_KEY \| sed 's/=.*/=SET/'` |
| Files | Key directory structure | `find src -maxdepth 2 -type d` |

### Probe Template

```bash
#!/bin/bash
# Ground Truth Protocol — Pre-Flight Probe
# Run at the start of every AI session
# Output: injected into AI context automatically

set -euo pipefail

echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

echo ""
echo "## Database State"
if command -v psql &>/dev/null; then
  TABLE_COUNT=$(psql -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" "$DB_NAME" 2>/dev/null || echo "0")
  echo "Tables in public schema: $TABLE_COUNT"
else
  echo "psql not available"
fi

echo ""
echo "## Running Services"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -E 'api|web|redis|worker' || echo "No app services detected"

echo ""
echo "## Git State"
if [ -d .git ]; then
  echo "Branch: $(git branch --show-current)"
  echo "Status:"
  git status --short | head -10
  echo "Recent commits:"
  git log --oneline -5
else
  echo "Not a git repository"
fi

echo ""
echo "## Configured Credentials"
for key in DATABASE_URL API_KEY SECRET_KEY OPENAI_API_KEY ANTHROPIC_API_KEY; do
  if [ -n "${!key:-}" ]; then
    echo "  $key: SET"
  else
    echo "  $key: NOT SET"
  fi
done

echo ""
echo "=== END GROUND TRUTH PROBE ==="
```

### Rules for Probe Design

1. **Under 2,000 tokens.** The probe should be concise. Do not dump raw table schemas or full file listings.
2. **Under 5 seconds.** If the probe takes longer, the agent (and user) will be tempted to skip it.
3. **Facts only.** The probe outputs what *is*, not what *should be*. No instructions, no rules, no advice.
4. **Current state.** Every output line comes from a live query, not a cached file.

## Step 3: Wire the Probe to Session Start

### Claude Code

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "name": "ground-truth-probe",
        "command": "./scripts/ground-truth-probe.sh",
        "description": "Injects current project state into context"
      }
    ]
  }
}
```

### Cursor

Add to `.cursorrules`:

```markdown
## Session Start

Before beginning any task, run `./scripts/ground-truth-probe.sh` and review the output.
The probe shows the current state of the database, services, and git repository.
Do not assume state — verify it from the probe output.
```

### Aider

Add to `.aider.conf.yml`:

```yaml
conventions:
  - "Before starting work, run ./scripts/ground-truth-probe.sh to verify project state"
  - "The probe output shows actual database tables, running services, and configured credentials"
  - "Never assume infrastructure state — the probe is the source of truth"
```

### Generic (Any Tool)

If your tool does not support hooks, instruct users to paste the probe output at the start of every session:

```
Before we begin, here is the current project state:

[paste output of ./scripts/ground-truth-probe.sh]
```

## Step 4: Create Your Assertion Gates (45 minutes)

For each failure mode identified in Step 1, create an assertion gate.

### Pattern: Before CREATE, Assert Not Exists

```bash
#!/bin/bash
# Assert: resource does not already exist before creating it
RESOURCE_TYPE="$1"  # e.g., "database", "table", "file"
RESOURCE_NAME="$2"  # e.g., "mydb", "users", "config.yaml"

case "$RESOURCE_TYPE" in
  database)
    if psql -c "SELECT 1" "$RESOURCE_NAME" 2>/dev/null; then
      TABLE_COUNT=$(psql -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" "$RESOURCE_NAME")
      echo "ASSERTION FAILED: Database '$RESOURCE_NAME' exists with $TABLE_COUNT tables."
      exit 1
    fi
    ;;
  file)
    if [ -f "$RESOURCE_NAME" ]; then
      echo "ASSERTION FAILED: File '$RESOURCE_NAME' already exists ($(wc -l < "$RESOURCE_NAME") lines)."
      exit 1
    fi
    ;;
  service)
    if systemctl is-active --quiet "$RESOURCE_NAME"; then
      echo "ASSERTION FAILED: Service '$RESOURCE_NAME' is already running."
      exit 1
    fi
    ;;
esac

echo "ASSERTION PASSED: $RESOURCE_TYPE '$RESOURCE_NAME' does not exist."
exit 0
```

### Pattern: Before Asking User, Assert Not Documented

```bash
#!/bin/bash
# Assert: answer is not already in project documentation
QUESTION="$1"
DOCS_DIR="${2:-docs}"

# Search documentation for keywords from the question
KEYWORDS=$(echo "$QUESTION" | tr ' ' '\n' | grep -v -E '^(the|a|an|is|are|how|what|where|do|does)$' | head -5)

FOUND=0
for keyword in $KEYWORDS; do
  if grep -ril "$keyword" "$DOCS_DIR" 2>/dev/null | head -3 | grep -q .; then
    FOUND=$((FOUND + 1))
    echo "Keyword '$keyword' found in:"
    grep -ril "$keyword" "$DOCS_DIR" 2>/dev/null | head -3
  fi
done

if [ "$FOUND" -ge 2 ]; then
  echo "ASSERTION FAILED: This question may already be answered in documentation."
  echo "Check the files listed above before asking the user."
  exit 1
fi

exit 0
```

### Pattern: Before Implementing, Assert Spec Exists

```bash
#!/bin/bash
# Assert: a spec document exists and has been read before code is written
FEATURE="$1"
SPEC_DIR="${2:-docs/design}"

SPEC_FILES=$(find "$SPEC_DIR" -name "*.md" -newer /tmp/.last-code-edit 2>/dev/null | head -5)
if [ -z "$SPEC_FILES" ]; then
  echo "ASSERTION WARNING: No spec documents have been accessed since the last code edit."
  echo "Available specs:"
  ls -1 "$SPEC_DIR"/*.md 2>/dev/null || echo "  No spec files found in $SPEC_DIR"
  echo "Read the relevant spec before implementing."
  exit 1
fi

echo "ASSERTION PASSED: Spec documents accessed: $SPEC_FILES"
exit 0
```

## Step 5: Wire Assertion Gates as Hooks

### Claude Code Hooks

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "name": "assert-no-existing-db",
        "match_tool": "Bash",
        "match_command": "CREATE DATABASE|createdb|initdb",
        "command": "./scripts/assert-resource.sh database $DB_NAME",
        "description": "Blocks database creation if database already exists"
      },
      {
        "name": "assert-no-existing-file",
        "match_tool": "Write",
        "command": "./scripts/assert-resource.sh file $FILE_PATH",
        "description": "Warns if creating a file that already exists"
      }
    ]
  }
}
```

### Git Hooks (Any Tool)

```bash
#!/bin/bash
# .git/hooks/pre-commit
# Assert: no files were created that duplicate existing functionality

NEW_FILES=$(git diff --cached --name-only --diff-filter=A)
for file in $NEW_FILES; do
  BASENAME=$(basename "$file" | sed 's/\.[^.]*$//')
  EXISTING=$(find . -name "*${BASENAME}*" -not -path "./.git/*" | grep -v "$file" | head -3)
  if [ -n "$EXISTING" ]; then
    echo "WARNING: New file '$file' may duplicate:"
    echo "$EXISTING"
    echo "Verify this is intentional."
  fi
done
```

## Step 6: Reduce Your Rules to Three (30 minutes)

### The Process

1. List all your current AI rules (CLAUDE.md, .cursorrules, system prompts, etc.)
2. For each rule, ask: "Can this be mechanically enforced?"
3. If yes: convert it to an assertion gate or hook. Remove it from the rule list.
4. If no: it requires judgment. Keep it as a candidate rule.
5. From the remaining candidates, select the three most important.
6. Phrase each rule as a single positive action.
7. Back each rule with a mechanical enforcement mechanism.

### Example Transformation

**Before (11 rules):**
1. Never edit generated files
2. Run code generator after schema changes
3. Write tests before implementing
4. Use LiteLLM for all LLM calls
5. Knowledge base is the core asset
6. Check CODEOWNERS before editing
7. Use 127.0.0.1 not localhost
8. Read design specs before implementing
9. Read docs before asking questions
10. Reread master context at session start
11. Verify before marking complete

**After (3 rules + 8 assertion gates):**

Rules:
1. Verify before acting
2. Spec before code
3. Evidence before done

Assertion gates:
- Gate: Block edits to generated/ directory
- Gate: Warn if schema changed without running generator
- Gate: Check for test file before allowing implementation file
- Gate: Scan imports for direct anthropic/openai usage
- Gate: Verify CODEOWNERS before file edit
- Gate: Replace localhost with 127.0.0.1 in connection strings
- Gate: Verify spec was read before code was written
- Gate: Search docs before allowing user questions

## Step 7: Set Compaction Directives (10 minutes)

Add to your AI tool's configuration:

```markdown
## Compaction Directives

When compacting context, ALWAYS preserve:
1. The most recent ground-truth-probe output
2. All assertion gate results (pass or fail) from this session
3. The list of spec documents read in this session
4. The current task definition and completion criteria
```

## Step 8: Add Checkpoint Quizzes (15 minutes)

Create a periodic verification hook:

```bash
#!/bin/bash
# Checkpoint quiz — runs every 50 tool calls
echo "=== CHECKPOINT: VERIFY STATE ==="
echo "Run these commands before continuing:"
echo ""
echo "1. Database state:"
echo "   psql -t -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema='public'\" mydb"
echo ""
echo "2. Service state:"
echo "   systemctl list-units --type=service --state=running | grep myapp"
echo ""
echo "3. Git state:"
echo "   git status --short"
echo ""
echo "Run these now. Do not answer from memory."
echo "=== END CHECKPOINT ==="
```

## Step 9: Validate (1 hour)

Deliberately test each failure mode:

1. **Duplicate creation test**: Ask the agent to "set up the database." It should be blocked by the probe output + assertion gate.
2. **Redundant question test**: Ask the agent a question documented in your project files. It should answer from probe output or documentation, not ask you.
3. **Spec alignment test**: Ask the agent to implement a feature. It should load the spec before coding.
4. **Compaction survival test**: Run a long session until compaction occurs. After compaction, ask the agent about database state. It should still know (from preserved probe output).

## Step 10: Iterate

- Monitor assertion gate triggers: gates that never trigger can be removed
- Monitor checkpoint quiz accuracy: if results always match, increase the interval
- Add new assertion gates only when a new failure mode is discovered (not preemptively)
- Resist the urge to add more rules. If something fails, add a mechanism, not an instruction.

## Integration Quick Reference

| Tool | Probe Integration | Hook Integration | Rules Location |
|------|------------------|-----------------|---------------|
| Claude Code | `.claude/settings.json` SessionStart hook | `.claude/settings.json` PreToolUse/PostToolUse hooks | `CLAUDE.md` |
| Cursor | `.cursorrules` instruction | `.cursorrules` instruction (advisory only) | `.cursorrules` |
| Aider | `.aider.conf.yml` convention | `.aider.conf.yml` convention (advisory only) | `.aider.conf.yml` |
| Copilot Workspace | Manual paste at session start | Not supported (use git hooks) | `.github/copilot-instructions.md` |
| Generic | Manual paste | Git hooks, CI gates | System prompt |
