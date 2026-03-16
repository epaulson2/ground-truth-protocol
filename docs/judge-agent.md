# Independent Verification: The Judge Agent

The judge agent is an independent verifier that evaluates completed work from three perspectives. It never asks the builder "are you done?" It checks the evidence directly.

---

## Why Self-Verification Fails

The single most reliable failure in AI agent development is self-assessment. When you ask an agent "is this done?" it will almost always say yes. This is not deception -- it is a structural problem.

### The Evidence

**From safety rule compliance research** (LessWrong, 2025):
> "High adherence scores often masked incidental non-violation rather than deliberate compliance."

The agent is not deliberately lying. It genuinely believes the work is done because it has no mechanism for checking its own blind spots. It wrote the code, so the code looks correct to it. It ran the tests it wrote, so the tests pass. The circularity is invisible from inside.

**From the Queen City Redline audit:**
- 757 tests passed
- 7 of 14 plan sections marked DONE
- Actual spec alignment: 18%

The agent's self-assessment was "tests pass, therefore done." The reality was "tests pass, but the tests only verify what was built, not what was specified."

**From cognitive bias research:**
Self-assessment suffers from:
- **Confirmation bias**: The builder looks for evidence that the work is complete, not evidence that it is incomplete.
- **IKEA effect**: Having built something makes it seem more valuable and complete than it is.
- **Dunning-Kruger**: The entity with the least perspective on what is missing is the entity that did the work.

**From aerospace (DO-178C):**
> "Verification must be performed by a person or team independent of the development team."

This is not a suggestion. It is a certification requirement. Software that flies in airplanes cannot be verified by the people who wrote it. The independence requirement exists because decades of aviation accidents proved that self-verification is unreliable.

**From nuclear (NRC ITAAC):**
> "Acceptance criteria shall be verified by inspections, tests, or analyses performed by qualified individuals independent of those who performed the work."

---

## The Three-Perspective Review

The judge evaluates work from three angles. A feature that looks complete from one angle may be incomplete from another.

### Perspective 1: Structural Integrity

Does the implementation physically exist as expected?

**What the judge checks:**
- Do the expected files exist?
- Are files non-trivial (not stubs with `pass` or `// TODO`)?
- Do imports resolve? (No `ImportError` on load)
- Are there dead code paths (functions defined but never called)?
- Is the code connected to the application (routes registered, components exported)?
- Do configuration files reference the new feature?

**Example structural checks:**

```bash
# Files exist and are non-trivial
for file in src/auth/login.py src/auth/models.py src/auth/utils.py; do
  if [ ! -f "$file" ]; then
    echo "STRUCTURAL FAIL: $file does not exist"
  elif [ $(wc -l < "$file") -lt 10 ]; then
    echo "STRUCTURAL FAIL: $file is a stub ($(wc -l < "$file") lines)"
  fi
done

# Imports resolve
python -c "
from src.auth.login import LoginHandler
from src.auth.models import User
from src.auth.utils import hash_password, verify_password
print('All imports resolve')
"

# Feature is wired into application
python -c "
from src.app import create_app
app = create_app()
routes = [r.rule for r in app.url_map.iter_rules()]
assert '/api/auth/login' in routes, 'Login route not registered'
assert '/api/auth/register' in routes, 'Register route not registered'
print('Routes registered')
"
```

**Why this perspective matters:** The most common agent failure is creating files that are syntactically correct but not connected to anything. The login handler exists, the route is defined in the handler file, but the route is never registered with the application. Structural checks catch this.

### Perspective 2: Behavioral Correctness

Does the feature actually work when you use it?

**What the judge checks:**
- Do the acceptance gate criteria pass?
- Do edge cases work? (Invalid input, missing data, concurrent access)
- Does error handling function? (Wrong password returns 401, not 500)
- Do side effects occur correctly? (Database writes, cache invalidation, event emission)
- Does the feature work under realistic conditions? (Not just with test fixtures)

**Example behavioral checks:**

```bash
# Happy path works
curl -s -X POST http://localhost:8000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"testpass"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'token' in d, 'No token'"

# Error cases handled correctly
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"WRONG"}')
[ "$STATUS" = "401" ] || echo "BEHAVIORAL FAIL: Wrong password returned $STATUS, expected 401"

# SQL injection attempt handled
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"x'\'' OR 1=1 --","password":"x"}')
[ "$STATUS" = "401" ] || [ "$STATUS" = "422" ] || echo "BEHAVIORAL FAIL: SQL injection returned $STATUS"
```

**Why this perspective matters:** Code can be structurally complete (files exist, imports resolve, routes registered) and still not work. The handler might throw an unhandled exception. The database query might be wrong. The response format might not match what the frontend expects.

### Perspective 3: Specification Alignment

Does the implementation match what was specified?

**What the judge checks:**
- Every feature listed in the spec is implemented
- No unspecified features were added (scope creep)
- Behavior matches spec descriptions (not just "works somehow")
- Data models match spec schemas
- Error responses match spec definitions
- Performance requirements met (if specified)

**Example specification checks:**

```bash
# Check spec requirements against implementation
python3 -c "
spec_requirements = [
    'Login with email and password',
    'Return JWT token on success',
    'Return 401 on invalid credentials',
    'Rate limit: 5 attempts per minute',
    'Password must be bcrypt hashed',
    'Token expires in 24 hours',
]

implemented = {
    'Login with email and password': True,      # Verified by behavioral check
    'Return JWT token on success': True,         # Verified by behavioral check
    'Return 401 on invalid credentials': True,   # Verified by behavioral check
    'Rate limit: 5 attempts per minute': False,  # NOT FOUND in implementation
    'Password must be bcrypt hashed': True,      # Verified by gate
    'Token expires in 24 hours': False,          # Token has no expiry claim
}

missing = [r for r, ok in implemented.items() if not ok]
if missing:
    print(f'SPEC ALIGNMENT FAIL: {len(missing)} requirements not implemented:')
    for m in missing:
        print(f'  - {m}')
else:
    print('All spec requirements implemented')
"
```

**Why this perspective matters:** This is where the 18% alignment problem lives. The feature can be structurally complete and behaviorally correct for what it does, but it may not do what was specified. Rate limiting was in the spec. Token expiry was in the spec. Neither was implemented. Without specification alignment checks, these gaps are invisible.

---

## Writing a Judge Agent Definition

A judge agent can be implemented as:
- A shell script that runs verification commands
- A Python script with structured checks
- An AI agent with a specific prompt and tool access
- A combination of automated checks and AI review

### Shell Script Judge

```bash
#!/bin/bash
# judge.sh — Three-perspective review for auth feature

GATE_FILE=".hold-point/gates/auth.yaml"
SPEC_FILE="docs/design/auth-spec.md"
VERDICT="APPROVE"
FINDINGS=()

echo "=== JUDGE REVIEW: Authentication Feature ==="
echo "Date: $(date -Iseconds)"
echo ""

# --- PERSPECTIVE 1: STRUCTURAL INTEGRITY ---
echo "## Structural Integrity"

EXPECTED_FILES=(
  "src/auth/login.py"
  "src/auth/models.py"
  "src/auth/utils.py"
  "src/auth/routes.py"
)

for f in "${EXPECTED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "  FAIL: $f does not exist"
    FINDINGS+=("STRUCTURAL: $f missing")
    VERDICT="REJECT"
  elif [ $(wc -l < "$f") -lt 10 ]; then
    echo "  FAIL: $f is a stub ($(wc -l < "$f") lines)"
    FINDINGS+=("STRUCTURAL: $f is a stub")
    VERDICT="REJECT"
  else
    echo "  PASS: $f exists ($(wc -l < "$f") lines)"
  fi
done

# Check imports resolve
if python3 -c "from src.auth.login import LoginHandler" 2>/dev/null; then
  echo "  PASS: Imports resolve"
else
  echo "  FAIL: Import errors"
  FINDINGS+=("STRUCTURAL: Import errors in auth module")
  VERDICT="REJECT"
fi

echo ""

# --- PERSPECTIVE 2: BEHAVIORAL CORRECTNESS ---
echo "## Behavioral Correctness"

# Run the acceptance gates
if ./scripts/gate-runner.sh "$GATE_FILE" 2>/dev/null; then
  echo "  PASS: All acceptance gates passing"
else
  echo "  FAIL: Acceptance gates failing"
  FINDINGS+=("BEHAVIORAL: Gates not passing")
  VERDICT="REJECT"
fi

echo ""

# --- PERSPECTIVE 3: SPECIFICATION ALIGNMENT ---
echo "## Specification Alignment"

if [ -f "$SPEC_FILE" ]; then
  echo "  Spec: $SPEC_FILE"
  # Check for key spec requirements
  # (In practice, this would be more sophisticated)
  echo "  Checking spec requirements..."
else
  echo "  WARN: No spec file found at $SPEC_FILE"
  FINDINGS+=("SPEC: No specification document found")
fi

echo ""

# --- VERDICT ---
echo "## Verdict: $VERDICT"
if [ ${#FINDINGS[@]} -gt 0 ]; then
  echo ""
  echo "Findings:"
  for f in "${FINDINGS[@]}"; do
    echo "  - $f"
  done
fi

echo ""
echo "=== END JUDGE REVIEW ==="

# Exit code reflects verdict
[ "$VERDICT" = "APPROVE" ] && exit 0 || exit 1
```

### AI Agent Judge

When using an AI agent as the judge, the prompt must enforce independence:

```markdown
You are a JUDGE AGENT reviewing completed work. You are independent of the builder.

RULES:
1. You have NEVER seen this code before. You have no context from the building process.
2. You do NOT ask the builder if the work is done. You verify it yourself.
3. You check THREE perspectives: structural, behavioral, specification alignment.
4. You produce a verdict: APPROVE or REJECT with specific findings.
5. You are SKEPTICAL by default. The burden of proof is on the work, not on you.

REVIEW PROCESS:
1. Read the specification document.
2. Read the acceptance gate YAML.
3. Inspect the implementation files.
4. Run the acceptance gates.
5. Compare implementation to specification.
6. Produce your verdict.

You MUST NOT:
- Trust any claim made by the builder
- Accept "tests pass" as proof of completion
- Skip the specification alignment check
- Approve work with stub files or TODO comments
- Approve work that adds features not in the spec without flagging it
```

---

## Key Principles

### Independence Is Non-Negotiable

The judge must be independent of the builder. This means:
- The judge does not share context with the builder
- The judge does not ask the builder questions
- The judge does not read the builder's self-assessment
- The judge verifies against the spec and the live system, not against the builder's description

### Skepticism Is the Default

The judge assumes the work is incomplete until proven otherwise. This is the opposite of the builder's default (which is to assume the work is complete). The asymmetry is intentional -- it counteracts confirmation bias.

### Evidence Over Claims

The judge does not accept verbal claims. "I implemented rate limiting" is not evidence. A gate criterion that makes 6 rapid requests and verifies the 6th returns 429 is evidence.

### The Judge Can Be Wrong

The judge is not infallible. It may reject work that is actually complete (false negative) or approve work that has subtle issues (false positive). That is why G4 (human sign-off) exists after the judge. The judge reduces the human's review burden by catching obvious issues, but the human makes the final call.

---

## Integration with the Pipeline

```
GATES_PASSING -----> REVIEW -----> DONE
                  |           |
                  | G3: Judge | G4: Human
                  | reviews   | approves
                  |           |
                  +--> REJECT --> IN_PROGRESS
                       (back to work with feedback)
```

The judge runs when the pipeline transitions from GATES_PASSING to REVIEW. Its output is stored in `.hold-point/judge-reports/` and referenced by the pipeline state machine.

If the judge rejects, the pipeline transitions to IN_PROGRESS with the judge's findings attached as feedback. The agent addresses the findings, gates are re-run, and review is re-requested.
