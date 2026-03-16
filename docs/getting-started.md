# Getting Started with Hold Point

Add machine-enforced completion verification to any project that uses AI coding agents. This guide assumes you are using Claude Code, but the concepts apply to any AI coding tool.

**Time estimate:** 1-2 hours for basic setup, half a day for full integration.

---

## Step 1: Install the Gate Runner

The gate runner is a shell script that reads YAML gate definitions and executes criteria against the live system.

```bash
# Create the scripts directory
mkdir -p scripts/guards

# Copy the gate runner
cp examples/gate-runner.sh scripts/gate-runner.sh
chmod +x scripts/gate-runner.sh

# Create the hold point directory structure
mkdir -p .hold-point/gates
mkdir -p .hold-point/results
mkdir -p .hold-point/judge-reports
mkdir -p .hold-point/audit
```

Verify it works:

```bash
./scripts/gate-runner.sh --help
# Usage: gate-runner.sh [options] <gate-file-or-directory>
# Options:
#   --verbose       Show detailed output for each criterion
#   --check-stale   Check if cached results are stale (don't re-run)
#   --json          Output results as JSON
```

---

## Step 2: Write Your First Acceptance Gate

Pick the feature you are currently working on. Write a YAML gate file that defines what "done" looks like in verifiable terms.

### Choose the Right Criteria

Think about how a human would verify this feature is complete. Not "does the code exist?" but "does it work?"

**Example: A user authentication feature**

```yaml
# .hold-point/gates/auth.yaml
gate:
  name: user-authentication
  stage: backend
  description: |
    User login with email/password returning a JWT token.
    Matches spec: docs/design/auth-spec.md

  criteria:
    # 1. Can a user log in?
    - name: login-returns-token
      type: http
      description: Valid credentials return a JWT token
      method: POST
      url: http://localhost:8000/api/auth/login
      headers:
        Content-Type: application/json
      body: '{"email": "test@example.com", "password": "testpass123"}'
      expect_status: 200
      expect_body: '"token"'

    # 2. Does it reject bad credentials?
    - name: login-rejects-wrong-password
      type: http
      description: Wrong password returns 401
      method: POST
      url: http://localhost:8000/api/auth/login
      headers:
        Content-Type: application/json
      body: '{"email": "test@example.com", "password": "WRONG"}'
      expect_status: 401

    # 3. Is the password properly hashed?
    - name: password-is-hashed
      type: sql
      description: Password in database is bcrypt hashed, not plaintext
      connection: $DATABASE_URL
      query: |
        SELECT password_hash FROM users
        WHERE email = 'test@example.com'
      expect_rows: 1
      expect_value: "$2b$"

    # 4. Does the JWT token actually work?
    - name: token-grants-access
      type: command
      description: JWT token from login grants access to protected endpoint
      run: |
        TOKEN=$(curl -s -X POST http://localhost:8000/api/auth/login \
          -H 'Content-Type: application/json' \
          -d '{"email":"test@example.com","password":"testpass123"}' \
          | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
        curl -s -o /dev/null -w '%{http_code}' \
          http://localhost:8000/api/users/me \
          -H "Authorization: Bearer $TOKEN" \
          | grep -q "200"
      expect_exit: 0
```

### Guidelines for Your First Gate

1. **Start with 3-5 criteria.** Do not try to cover everything. Cover the critical paths.
2. **Test behavior, not files.** "Does login work?" not "Does login.py exist?"
3. **Test the live system.** HTTP requests to running services, SQL queries to the real database.
4. **Include at least one failure case.** Not just "login works" but "login fails correctly."
5. **Make criteria independent.** Each criterion should pass or fail on its own, not depend on others running first.

---

## Step 3: Run Gates

```bash
# Run your gate
./scripts/gate-runner.sh .hold-point/gates/auth.yaml
```

Expected output (when things are working):

```
=== HOLD POINT GATE: user-authentication ===
[PASS] login-returns-token (HTTP POST -> 200, body matches)
[PASS] login-rejects-wrong-password (HTTP POST -> 401)
[PASS] password-is-hashed (SQL: 1 row, value matches)
[PASS] token-grants-access (command exit 0)
RESULT: 4/4 criteria passing. Gate OPEN.
```

Expected output (when things need work):

```
=== HOLD POINT GATE: user-authentication ===
[PASS] login-returns-token (HTTP POST -> 200, body matches)
[PASS] login-rejects-wrong-password (HTTP POST -> 401)
[FAIL] password-is-hashed (SQL: 0 rows returned, expected 1)
[FAIL] token-grants-access (command exit 1)
RESULT: 2/4 criteria passing. Gate CLOSED.

Failed criteria:
  password-is-hashed: No rows returned. Is the test user seeded? Run: scripts/seed-test-data.sh
  token-grants-access: Token not accepted. Check JWT secret configuration.
```

The gate runner exits non-zero when any criterion fails, making it suitable for use in hooks, CI pipelines, and scripts.

---

## Step 4: Set Up Pipeline State Machine

Initialize the pipeline state for your feature:

```bash
# Copy the pipeline management script
cp examples/pipeline-advance.sh scripts/pipeline-advance.sh
chmod +x scripts/pipeline-advance.sh

# Initialize pipeline state
./scripts/pipeline-advance.sh auth IN_PROGRESS
```

This creates `.hold-point/pipeline.json` with the initial state.

### Typical Workflow

```bash
# 1. Start working
./scripts/pipeline-advance.sh auth IN_PROGRESS

# 2. Write gate definitions (you already did this in Step 2)
./scripts/pipeline-advance.sh auth GATES_DEFINED

# 3. Have a human review and approve the criteria
#    (Review .hold-point/gates/auth.yaml, then:)
./scripts/pipeline-advance.sh auth GATES_PASSING --approve-g1 --by yourname

# 4. Gates are run automatically. When all pass:
./scripts/pipeline-advance.sh auth REVIEW --request-review

# 5. Judge reviews. When approved, human signs off:
./scripts/pipeline-advance.sh auth DONE --approve-g4 --by yourname
```

For solo projects, you can simplify by acting as both builder and reviewer. The key is that you review the gate criteria (G1) and the final result (G4) as a separate mental step from building.

---

## Step 5: Configure Hooks

Add Hold Point hooks to your Claude Code configuration.

### Basic Configuration

Create or update `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "name": "hold-point-no-deploy-without-gates",
        "match_tool": "Bash",
        "match_command": "deploy|systemctl.*restart|docker.*up",
        "command": "./scripts/guards/require-gates-pass.sh",
        "timeout_ms": 10000,
        "description": "Blocks deployment if acceptance gates have not passed"
      },
      {
        "name": "hold-point-protect-state",
        "match_tool": "Write|Edit",
        "match_file": ".hold-point/pipeline.json|.hold-point/results/**",
        "command": "echo 'BLOCKED: Modify pipeline state via pipeline-advance.sh, not direct edit.' && exit 1",
        "timeout_ms": 2000,
        "description": "Prevents direct edits to pipeline state and gate results"
      }
    ],
    "PostToolUse": [
      {
        "name": "hold-point-invalidate-on-change",
        "match_tool": "Write|Edit",
        "match_file": "src/**",
        "command": "./scripts/guards/invalidate-gates.sh",
        "timeout_ms": 5000,
        "description": "Invalidates gate results when source code changes"
      }
    ],
    "Stop": [
      {
        "name": "hold-point-check-before-done",
        "command": "./scripts/guards/check-open-gates.sh",
        "timeout_ms": 10000,
        "description": "Warns if gates are stale or failing before session ends"
      }
    ]
  }
}
```

### Guard Scripts

Create the guard scripts referenced by the hooks:

**`scripts/guards/require-gates-pass.sh`:**

```bash
#!/bin/bash
# Blocks action if any acceptance gates are not passing

GATE_DIR=".hold-point/gates"
RESULT_DIR=".hold-point/results"

if [ ! -d "$GATE_DIR" ] || [ -z "$(ls -A "$GATE_DIR" 2>/dev/null)" ]; then
  echo "WARNING: No acceptance gates defined. Define gates before deploying."
  exit 1
fi

# Check each gate
FAILING=0
for gate in "$GATE_DIR"/*.yaml; do
  NAME=$(basename "$gate" .yaml)
  RESULT_FILE="$RESULT_DIR/${NAME}.json"

  if [ ! -f "$RESULT_FILE" ]; then
    echo "BLOCKED: Gate '$NAME' has never been run."
    FAILING=1
  elif grep -q '"result": "FAIL"' "$RESULT_FILE"; then
    echo "BLOCKED: Gate '$NAME' is failing."
    FAILING=1
  fi
done

if [ "$FAILING" -eq 1 ]; then
  echo ""
  echo "ACTION: Run ./scripts/gate-runner.sh $GATE_DIR and fix failing criteria."
  exit 1
fi

echo "All gates passing. Proceeding."
exit 0
```

**`scripts/guards/invalidate-gates.sh`:**

```bash
#!/bin/bash
# Invalidates gate results when source files change

RESULT_DIR=".hold-point/results"
[ -d "$RESULT_DIR" ] || exit 0

for result_file in "$RESULT_DIR"/*.json; do
  [ -f "$result_file" ] || continue

  # Check if any source files in the result have changed
  STALE=false
  while IFS= read -r line; do
    FILE=$(echo "$line" | cut -d: -f1)
    CACHED_HASH=$(echo "$line" | cut -d: -f2)
    if [ -f "$FILE" ]; then
      CURRENT_HASH=$(sha256sum "$FILE" | cut -d' ' -f1 | head -c8)
      if [ "$CACHED_HASH" != "$CURRENT_HASH" ]; then
        STALE=true
        break
      fi
    fi
  done < <(python3 -c "
import json,sys
with open('$result_file') as f:
  d = json.load(f)
for s in d.get('source_files_hashed', []):
  print(s)
" 2>/dev/null)

  if [ "$STALE" = true ]; then
    GATE_NAME=$(basename "$result_file" .json)
    echo "Gate '$GATE_NAME' result INVALIDATED (source files changed). Must re-run."
    # Mark as stale in the result file
    python3 -c "
import json
with open('$result_file') as f:
  d = json.load(f)
d['result'] = 'STALE'
d['stale_reason'] = 'Source files changed since last run'
with open('$result_file', 'w') as f:
  json.dump(d, f, indent=2)
"
  fi
done
```

**`scripts/guards/check-open-gates.sh`:**

```bash
#!/bin/bash
# Checks for open/failing gates before session ends

PIPELINE_FILE=".hold-point/pipeline.json"
[ -f "$PIPELINE_FILE" ] || exit 0

WARNINGS=0

python3 -c "
import json
with open('$PIPELINE_FILE') as f:
  pipeline = json.load(f)

for name, stage in pipeline.get('stages', {}).items():
  status = stage.get('status', 'UNKNOWN')
  if status in ('IN_PROGRESS', 'GATES_DEFINED'):
    print(f'WARNING: {name} is {status} (gates not yet passing)')
  elif status == 'GATES_PASSING':
    gate_result = stage.get('gate_result', 'UNKNOWN')
    if gate_result == 'STALE':
      print(f'WARNING: {name} gates are STALE (source code changed since last run)')
" 2>/dev/null

# Always exit 0 (warnings, not blocks) for Stop hooks
exit 0
```

---

## Step 6: Set Up Continuous Verification

### Pre-Commit Hook

Add gate checking to your git pre-commit hook:

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Check for stale gate results
if [ -d ".hold-point/results" ]; then
  STALE=$(./scripts/gate-runner.sh --check-stale .hold-point/gates/ 2>/dev/null | grep -c "STALE")
  if [ "$STALE" -gt 0 ]; then
    echo "WARNING: $STALE gate result(s) are stale. Run gate-runner.sh to re-verify."
    echo "Commit proceeding, but re-run gates before deployment."
  fi
fi
```

### CI Integration

Add to your CI pipeline:

```yaml
# .github/workflows/hold-point.yml
name: Hold Point Verification
on: [push, pull_request]

jobs:
  verify-gates:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4

      - name: Start application
        run: |
          # Your app startup commands here
          docker compose up -d
          sleep 5

      - name: Run acceptance gates
        run: ./scripts/gate-runner.sh .hold-point/gates/

      - name: Check for stale results
        run: ./scripts/gate-runner.sh --check-stale .hold-point/gates/
```

---

## What You Should Have Now

After completing these steps:

```
your-project/
  .claude/
    settings.json          # Updated with Hold Point hooks
  .hold-point/
    gates/
      auth.yaml            # Your first acceptance gate
    results/               # Gate results (auto-generated)
    pipeline.json          # Pipeline state (auto-generated)
    judge-reports/         # Judge output (later)
    audit/                 # Guard audit logs
  scripts/
    gate-runner.sh         # Runs acceptance gates
    pipeline-advance.sh    # Manages pipeline state
    guards/
      require-gates-pass.sh
      invalidate-gates.sh
      check-open-gates.sh
```

---

## Next Steps

1. **Add more gates** as you work on new features. One YAML file per feature.
2. **Set up the judge agent** for independent verification (see [docs/judge-agent.md](judge-agent.md)).
3. **Add bypass guards** for your specific workflow (see [docs/bypass-prevention.md](bypass-prevention.md)).
4. **Integrate with CI** to run gates on every push.
5. **Review gate quality** periodically. Gates that never fail may be too easy. Gates that always fail may be misconfigured.

---

## Troubleshooting

### "Gate runner can't find YAML files"

Check that your gate files have the `.yaml` extension (not `.yml`) and are in `.hold-point/gates/`.

### "HTTP criteria fail with connection refused"

The service must be running when gates are executed. Gates test the live system, not the code. Start your service before running gates.

### "SQL criteria fail with authentication error"

Set the `DATABASE_URL` environment variable or update the `connection` field in your gate YAML to match your database configuration.

### "PostToolUse hooks slow down editing"

The `invalidate-gates.sh` script runs after every file edit in `src/`. If it is too slow, optimize it to only check files that are referenced in gate results (check the `source_files_hashed` field).

### "Agent complains about being blocked"

This is the system working as intended. The agent is being blocked because gates have not passed. The agent should fix the issues that cause gates to fail, not work around the blocks. If the agent is being blocked incorrectly, review the guard scripts for false positives.
