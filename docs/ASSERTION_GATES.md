# Designing Assertion Gates

Assertion gates are pre-condition checks that run automatically before the AI agent performs a create, modify, or delete action. If the pre-condition fails, the action is blocked and the agent receives an explanation of why.

## The Core Principle

Every assertion gate follows the same pattern:

```
BEFORE the agent does X, VERIFY that Y is true.
If Y is false, BLOCK X and TELL the agent why.
```

This transforms failures from "agent forgot to check" (unpredictable) to "agent was told the check failed" (deterministic, actionable).

## Pre-Condition Patterns

### Before CREATE: Assert Resource Does Not Exist

The most common drift failure is creating something that already exists.

```bash
#!/bin/bash
# assert-not-exists.sh
# Usage: ./assert-not-exists.sh <type> <name>

TYPE="$1"
NAME="$2"

case "$TYPE" in
  database)
    if psql -c "SELECT 1" "$NAME" 2>/dev/null; then
      TABLE_COUNT=$(psql -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" "$NAME" | tr -d ' ')
      echo "GATE BLOCKED: Database '$NAME' already exists with $TABLE_COUNT tables."
      echo "ACTION: Query the existing database. Do not create a new one."
      exit 1
    fi
    ;;

  table)
    DB="${3:-$(echo $DATABASE_URL | sed 's/.*\///')}"
    if psql -d "$DB" -c "SELECT 1 FROM $NAME LIMIT 0" 2>/dev/null; then
      ROW_COUNT=$(psql -t -d "$DB" -c "SELECT count(*) FROM $NAME" | tr -d ' ')
      echo "GATE BLOCKED: Table '$NAME' already exists with $ROW_COUNT rows."
      echo "ACTION: Use the existing table. If you need to modify it, use ALTER TABLE."
      exit 1
    fi
    ;;

  file)
    if [ -f "$NAME" ]; then
      LINE_COUNT=$(wc -l < "$NAME")
      echo "GATE BLOCKED: File '$NAME' already exists ($LINE_COUNT lines)."
      echo "ACTION: Edit the existing file instead of creating a new one."
      exit 1
    fi
    ;;

  directory)
    if [ -d "$NAME" ]; then
      FILE_COUNT=$(find "$NAME" -type f | wc -l)
      echo "GATE BLOCKED: Directory '$NAME' already exists with $FILE_COUNT files."
      echo "ACTION: Use the existing directory."
      exit 1
    fi
    ;;

  service)
    if systemctl is-active --quiet "$NAME" 2>/dev/null; then
      echo "GATE BLOCKED: Service '$NAME' is already running."
      echo "ACTION: Use the existing service. If you need to reconfigure, use systemctl restart."
      exit 1
    fi
    ;;

  docker)
    if docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then
      echo "GATE BLOCKED: Docker container '$NAME' is already running."
      echo "ACTION: Use the existing container. If you need to recreate, stop it first."
      exit 1
    fi
    ;;
esac

echo "GATE PASSED: $TYPE '$NAME' does not exist. Proceed with creation."
exit 0
```

### Before Asking User: Assert Answer Is Not in Docs

Prevents the agent from asking users questions that are already documented.

```bash
#!/bin/bash
# assert-not-documented.sh
# Usage: ./assert-not-documented.sh "question text" [docs_directory]

QUESTION="$1"
DOCS_DIR="${2:-docs}"

# Extract meaningful keywords (skip common words)
STOP_WORDS="the|a|an|is|are|was|were|how|what|where|when|why|do|does|did|can|could|should|would|to|in|on|at|for|of|with|and|or|not|it|this|that"
KEYWORDS=$(echo "$QUESTION" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alpha:]' '\n' | grep -v -E "^($STOP_WORDS)$" | sort -u | head -8)

MATCHES=0
MATCHING_FILES=""

for keyword in $KEYWORDS; do
  FILES=$(grep -ril "$keyword" "$DOCS_DIR" 2>/dev/null | head -5)
  if [ -n "$FILES" ]; then
    MATCHES=$((MATCHES + 1))
    MATCHING_FILES="$MATCHING_FILES $FILES"
  fi
done

if [ "$MATCHES" -ge 3 ]; then
  UNIQUE_FILES=$(echo "$MATCHING_FILES" | tr ' ' '\n' | sort -u | head -5)
  echo "GATE BLOCKED: This question is likely answered in project documentation."
  echo ""
  echo "Relevant files:"
  for file in $UNIQUE_FILES; do
    echo "  - $file"
  done
  echo ""
  echo "ACTION: Read these files before asking the user."
  exit 1
fi

echo "GATE PASSED: Question does not appear to be documented."
exit 0
```

### Before Implementing: Assert Spec Has Been Read

Prevents code implementation without reading the design specification.

```bash
#!/bin/bash
# assert-spec-read.sh
# Usage: ./assert-spec-read.sh <feature_name> [spec_directory]

FEATURE="$1"
SPEC_DIR="${2:-docs/design}"
SESSION_LOG="${3:-.ground-truth/session.log}"

# Check if any spec files have been read in this session
if [ -f "$SESSION_LOG" ]; then
  SPECS_READ=$(grep -c "READ_SPEC:" "$SESSION_LOG" 2>/dev/null || echo "0")
else
  SPECS_READ=0
fi

if [ "$SPECS_READ" -eq 0 ]; then
  echo "GATE WARNING: No spec documents have been read in this session."
  echo ""
  echo "Available specs in $SPEC_DIR:"
  ls -1 "$SPEC_DIR"/*.md 2>/dev/null | while read -r spec; do
    echo "  - $(basename "$spec"): $(head -1 "$spec" | sed 's/^#\s*//')"
  done
  echo ""
  echo "ACTION: Read the relevant spec document before writing code."
  echo "Rule: Spec before code. No spec, no code."
  exit 1
fi

echo "GATE PASSED: $SPECS_READ spec document(s) read in this session."
exit 0
```

### Before Deploying: Assert Tests Pass

Prevents deployment without passing tests.

```bash
#!/bin/bash
# assert-tests-pass.sh
# Usage: ./assert-tests-pass.sh [test_command]

TEST_CMD="${1:-npm test}"
TIMEOUT="${2:-120}"

echo "Running tests: $TEST_CMD"
if timeout "$TIMEOUT" $TEST_CMD 2>&1; then
  echo "GATE PASSED: All tests pass."
  exit 0
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 124 ]; then
    echo "GATE BLOCKED: Tests timed out after ${TIMEOUT}s."
  else
    echo "GATE BLOCKED: Tests failed (exit code: $EXIT_CODE)."
  fi
  echo "ACTION: Fix failing tests before deploying."
  exit 1
fi
```

### Before Deleting: Assert No References Exist

Prevents deleting code that is still referenced elsewhere.

```bash
#!/bin/bash
# assert-no-references.sh
# Usage: ./assert-no-references.sh <symbol_name> <file_being_deleted>

SYMBOL="$1"
FILE="$2"

# Search for references to this symbol outside the file being deleted
REFS=$(grep -rn "$SYMBOL" . --include="*.py" --include="*.ts" --include="*.tsx" --include="*.js" \
  | grep -v "$FILE" \
  | grep -v "node_modules" \
  | grep -v ".git" \
  | head -10)

if [ -n "$REFS" ]; then
  REF_COUNT=$(echo "$REFS" | wc -l)
  echo "GATE BLOCKED: Symbol '$SYMBOL' has $REF_COUNT references outside '$FILE'."
  echo ""
  echo "References found:"
  echo "$REFS"
  echo ""
  echo "ACTION: Remove or update all references before deleting this code."
  exit 1
fi

echo "GATE PASSED: No external references to '$SYMBOL' found."
exit 0
```

## Implementation as Hooks

### Claude Code Hook Configuration

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "name": "assert-no-existing-db",
        "match_tool": "Bash",
        "match_command": "CREATE DATABASE|createdb|initdb",
        "command": "./scripts/gates/assert-not-exists.sh database",
        "description": "Blocks database creation if one already exists"
      },
      {
        "name": "assert-no-existing-table",
        "match_tool": "Bash",
        "match_command": "CREATE TABLE",
        "command": "./scripts/gates/assert-not-exists.sh table",
        "description": "Blocks table creation if it already exists"
      },
      {
        "name": "assert-spec-before-code",
        "match_tool": "Write",
        "match_file": "src/**/*.{py,ts,tsx,js}",
        "command": "./scripts/gates/assert-spec-read.sh",
        "description": "Warns if code is written without reading a spec"
      },
      {
        "name": "assert-tests-before-deploy",
        "match_tool": "Bash",
        "match_command": "deploy|push.*production|systemctl.*restart",
        "command": "./scripts/gates/assert-tests-pass.sh",
        "description": "Blocks deployment if tests have not passed"
      }
    ],
    "PostToolUse": [
      {
        "name": "log-spec-reads",
        "match_tool": "Read",
        "match_file": "docs/design/**",
        "command": "echo \"READ_SPEC: $FILE_PATH $(date -Iseconds)\" >> .ground-truth/session.log",
        "description": "Logs when spec documents are read"
      }
    ]
  }
}
```

### Git Hook Implementation

For tools that do not support PreToolUse hooks, use git hooks as a fallback:

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "=== Ground Truth Protocol: Pre-Commit Gates ==="

# Gate 1: No duplicate files
NEW_FILES=$(git diff --cached --name-only --diff-filter=A)
GATE_FAILED=0

for file in $NEW_FILES; do
  BASENAME=$(basename "$file" | sed 's/\.[^.]*$//')
  EXISTING=$(find . -name "*${BASENAME}*" \
    -not -path "./.git/*" \
    -not -path "./node_modules/*" \
    | grep -v "^./$file$" \
    | head -3)
  if [ -n "$EXISTING" ]; then
    echo "WARNING: New file '$file' may duplicate existing files:"
    echo "$EXISTING"
    GATE_FAILED=1
  fi
done

# Gate 2: No direct LLM SDK imports (if your project requires an abstraction layer)
BANNED_IMPORTS=$(git diff --cached -U0 | grep '^+' | grep -E 'import (openai|anthropic|cohere)' | head -5)
if [ -n "$BANNED_IMPORTS" ]; then
  echo "GATE BLOCKED: Direct LLM SDK imports detected. Use the abstraction layer instead."
  echo "$BANNED_IMPORTS"
  GATE_FAILED=1
fi

# Gate 3: No hardcoded localhost (if your project uses 127.0.0.1)
LOCALHOST=$(git diff --cached -U0 | grep '^+' | grep -E 'localhost' | grep -v '//localhost' | head -5)
if [ -n "$LOCALHOST" ]; then
  echo "GATE WARNING: 'localhost' found in changes. Use '127.0.0.1' instead."
  echo "$LOCALHOST"
fi

if [ "$GATE_FAILED" -eq 1 ]; then
  echo ""
  echo "Commit blocked by Ground Truth Protocol assertion gates."
  echo "Fix the issues above and try again."
  exit 1
fi

echo "All gates passed."
exit 0
```

### CI Pipeline Gates

For deployment-critical assertions, implement as CI steps:

```yaml
# .github/workflows/ground-truth-gates.yml
name: Ground Truth Gates

on: [pull_request]

jobs:
  assertion-gates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: "Gate: No duplicate resources"
        run: |
          # Check for duplicate file names
          find src -name "*.py" -o -name "*.ts" | sort | uniq -d | while read dup; do
            echo "GATE FAILED: Duplicate file name found: $dup"
            exit 1
          done

      - name: "Gate: No banned imports"
        run: |
          if grep -rn "import openai\|import anthropic" src/ --include="*.py"; then
            echo "GATE FAILED: Direct LLM SDK imports found. Use the abstraction layer."
            exit 1
          fi

      - name: "Gate: Spec referenced in PR"
        run: |
          PR_BODY=$(gh pr view ${{ github.event.pull_request.number }} --json body -q .body)
          if ! echo "$PR_BODY" | grep -qi "spec\|design doc\|specification"; then
            echo "GATE WARNING: No spec reference found in PR description."
            echo "Ensure the implementation matches a design specification."
          fi
```

## Making Gates Non-Bypassable

The value of assertion gates is that they are mechanical, not advisory. To maintain this:

### 1. Run Gates in the Tool Pipeline, Not the Agent Context

Gates implemented as hooks run at the tool execution level, below the agent's control. The agent cannot choose to skip a PreToolUse hook -- it fires automatically when the matching tool and command pattern are detected.

### 2. Exit Non-Zero on Failure

A gate that prints a warning but exits 0 is advisory, not mechanical. Always `exit 1` when the assertion fails:

```bash
# Wrong: advisory warning
echo "WARNING: Database exists"
exit 0  # Agent can proceed anyway

# Right: mechanical block
echo "GATE BLOCKED: Database exists with 38 tables."
exit 1  # Tool execution is blocked
```

### 3. Include Actionable Guidance in Block Messages

When a gate blocks an action, tell the agent what to do instead. A bare "BLOCKED" message may cause the agent to try a workaround. A message that says "BLOCKED: Database exists. Query the existing database instead" guides the agent to the correct action.

### 4. Log All Gate Activations

Record every gate activation (pass or fail) for auditing:

```bash
# Add to every gate script
LOG_DIR=".ground-truth/gate-log"
mkdir -p "$LOG_DIR"
echo "$(date -Iseconds) | $GATE_NAME | $RESULT | $DETAILS" >> "$LOG_DIR/gates.log"
```

### 5. Do Not Provide Override Flags

If a gate has a `--force` or `--skip` flag, it will be used. Gates should not have escape hatches accessible to the AI agent. If a human needs to override a gate, they should modify the gate script directly -- a deliberate action, not a command-line flag the agent can discover.

## Common Gate Recipes

| Failure Mode | Gate Pattern | Check |
|-------------|-------------|-------|
| Duplicate database | Before CREATE DATABASE | `psql -c "SELECT 1" dbname` |
| Duplicate table | Before CREATE TABLE | `psql -c "\dt tablename"` |
| Duplicate file | Before Write tool | `test -f filepath` |
| Missing spec | Before Write to src/ | Check session log for spec reads |
| Missing tests | Before deploy command | Run test suite |
| Stale references | Before delete/rename | `grep -rn symbol .` |
| Banned imports | Before git commit | `grep -E 'import (openai\|anthropic)'` |
| Wrong host | Before connection string | Check for 'localhost' vs '127.0.0.1' |
| Missing env vars | Before service start | Check required env vars are set |
| Uncommitted changes | Before branch switch | `git status --short` |
