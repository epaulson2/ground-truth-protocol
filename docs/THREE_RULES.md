# The Three Rules Principle

## Why 3, Not 11 or 30

### The Research

The IFScale benchmark (arXiv:2507.11538) measured how AI models handle increasing numbers of instructions. The findings are clear:

- **Threshold decay models** (o3, Gemini 2.5 Pro): Near-perfect compliance until ~150 instructions, then sharp collapse
- **Linear decay models** (GPT-4.1, Claude 3.7 Sonnet): Steady, predictable accuracy reduction with each additional instruction
- **Exponential decay models** (Claude 3.5 Haiku, LLaMA 4 Scout): Rapid early collapse, stabilizing at 7-15% accuracy

Even the best models achieve only 68% accuracy at 500 instructions. More critically, the *type* of error shifts: models go from modification errors (doing the wrong thing) to **complete omission** (not doing the thing at all). Past the threshold, the model does not try to follow the rule incorrectly -- it abandons the rule entirely.

### The Human Parallel

Miller's Law (1956) establishes that human working memory holds 7 +/- 2 items. While AI models are not human, the empirical evidence shows analogous limits. The cognitive load research (Sweller, 1988) distinguishes between:

- **Intrinsic load**: The complexity of the task (irreducible)
- **Extraneous load**: Complexity from how instructions are presented (reducible)
- **Germane load**: Effort devoted to building understanding (desirable)

Each advisory rule adds extraneous load. 11 rules means 11 items competing for attention with the task itself. Three rules mean three items -- well within cognitive capacity limits, leaving more budget for the actual work.

### The Practical Argument

Consider a project with 11 rules:

1. Never edit generated files
2. Run code generator after schema changes
3. Write tests before implementing
4. Use the LLM abstraction layer
5. Knowledge base is the core asset
6. Check file ownership before editing
7. Use 127.0.0.1 not localhost
8. Read design specs before implementing
9. Read docs before asking questions
10. Read master context at session start
11. Verify before marking complete

Each rule is correct. Each rule addresses a real failure. But the agent must hold all 11 in active attention while also understanding the task, reading code, and planning implementation. If each rule has 3-5 sub-steps (rule 9: "reread compass, find doc, read doc, extract answer, only then ask"), the effective instruction count is 33-55 -- well into the degradation zone.

Three rules can be recited from memory. Three rules can be checked before every action. Three rules leave cognitive space for the actual work.

## The Three Meta-Rules

These three rules apply to any project. They can be customized in wording, but the structure should remain: one verification rule, one preparation rule, one completion rule.

### Rule 1: Verify Before Acting

> Never assume state. Probe it.

**What it means**: Before starting any task, before creating any resource, before making any claim about what exists -- verify actual state by running a check command or reviewing probe output.

**What it prevents**:
- Creating databases that already exist
- Setting up services that are already running
- Asking about credentials that are already configured
- Making changes to files without knowing their current state

**Mechanical enforcement**: The pre-flight probe runs automatically at session start, injecting verified state into context. Assertion gates run before create/modify actions, blocking them if pre-conditions are not met.

**Without this rule**: The agent relies on its training prior ("databases need to be created") instead of project reality ("this database has 38 tables"). The training prior is always available in model weights. Project reality requires active verification.

### Rule 2: Specs Before Code

> Never implement from memory. Read the spec.

**What it means**: Before writing any implementation code, load and read the relevant design specification document. If no spec exists, flag that as a problem before proceeding.

**What it prevents**:
- Code that works but does not match the design
- Features that pass tests but solve the wrong problem
- Implementations based on the agent's assumption of what was intended rather than what was specified
- The 18%-spec-alignment-despite-757-passing-tests failure

**Mechanical enforcement**: A PostToolUse hook on file writes checks whether spec documents were read before code files were modified. If not, the hook emits a warning.

**Without this rule**: The agent jumps from task description to implementation, using its training knowledge of "how to build X" instead of the project's specific design for X. The result passes tests (because the tests test what was built, not what was designed) but does not match the specification.

### Rule 3: Evidence Before Done

> Never mark complete without proof.

**What it means**: Before claiming any task, feature, or step is complete, produce observable evidence: a file exists on disk, database rows exist, tests pass, a service responds to a health check. "I wrote the code" is not evidence of completion. "The tests pass and the API returns 200" is evidence.

**What it prevents**:
- "Done" claims that are actually "code written but not tested"
- Features marked complete that are not wired into the application
- Deployments that succeed on paper but fail in practice
- The gap between "code ready" and "actually working"

**Mechanical enforcement**: Completion criteria are defined at task start. A checkpoint verifies that evidence artifacts exist before the task can be marked done.

**Without this rule**: The agent produces code, declares victory, and moves on. The code may compile, may even pass unit tests, but may not be wired into the application, may not handle edge cases, or may not work in the actual deployment environment.

## How to Distill Your Rules to Three

### Step 1: List All Current Rules

Gather every rule, guideline, convention, and instruction currently given to your AI agent. Include:
- Configuration files (CLAUDE.md, .cursorrules, .aider.conf.yml)
- System prompts
- README instructions referenced during sessions
- Verbal conventions ("always do X before Y")

### Step 2: Classify Each Rule

For each rule, determine its category:

| Category | Description | Example |
|----------|-------------|---------|
| **Verification** | "Check X before doing Y" | "Verify database exists before creating tables" |
| **Preparation** | "Read/load X before doing Y" | "Read the spec before implementing" |
| **Completion** | "Prove X before claiming Y" | "Run tests before marking done" |
| **Technical constraint** | "Always/never do X" | "Use 127.0.0.1 not localhost" |
| **Process** | "Follow steps 1-2-3" | "Write test, implement, verify" |

### Step 3: Convert Technical Constraints to Assertion Gates

Rules in the "technical constraint" category are the easiest to mechanically enforce. They have a clear condition and a clear action:

| Rule | Assertion Gate |
|------|---------------|
| "Never edit generated files" | PreToolUse hook: block Write to `generated/` directory |
| "Use 127.0.0.1 not localhost" | Pre-commit hook: scan for 'localhost' in connection strings |
| "Use LLM abstraction layer" | Pre-commit hook: scan for direct SDK imports |
| "Run generator after schema changes" | PostToolUse hook: detect schema file edits, run generator |

Once converted to gates, these rules are removed from the advisory rule list. They are now mechanisms, not instructions.

### Step 4: Convert Process Rules to Hooks

Rules that describe a sequence ("do A then B then C") can often be enforced by checking that the prerequisite step happened:

| Rule | Hook |
|------|------|
| "Write test before implementing" | PostToolUse: warn if src/ file written without test file in session |
| "Check CODEOWNERS before editing" | PreToolUse: look up file ownership before allowing Write |
| "Run tests before deploying" | PreToolUse: run test suite before deploy commands |

### Step 5: Select Three Remaining Rules

From the rules that genuinely require judgment (not mechanical checks), select three. These should be:

1. **One verification rule**: Covers all "check before act" behaviors
2. **One preparation rule**: Covers all "read before write" behaviors
3. **One completion rule**: Covers all "prove before claim" behaviors

### Step 6: Phrase Each as a Single Positive Action

Rules should tell the agent what TO DO, not what NOT to do. Research on safety rules (LessWrong) found that positive framing ("Always do X") outperforms negative framing ("Never do Y").

| Negative (weaker) | Positive (stronger) |
|-------------------|---------------------|
| "Never assume state" | "Verify state before acting" |
| "Don't implement without reading the spec" | "Read the spec before implementing" |
| "Don't mark done without proof" | "Show evidence before marking done" |

## What Happened to the Other Rules?

The rules you removed from the advisory list are not deleted. They are **demoted from instructions to mechanisms**:

- **Technical constraints** become assertion gates (hooks that block wrong actions)
- **Process rules** become workflow hooks (hooks that enforce sequence)
- **Knowledge rules** become probe output (state injected into context)

The key insight: **a rule that can be mechanically enforced should not be an instruction**. Instructions are for things that require judgment. Mechanical facts are for hooks.

Your previous 11 rules become:
- 3 advisory rules (in CLAUDE.md or equivalent)
- 5-8 assertion gates (in hooks configuration)
- 1 pre-flight probe (injecting state that makes some rules unnecessary)

The total behavioral coverage is the same or better. The cognitive load on the agent is dramatically lower.

## FAQ

### "What if I have a rule that does not fit any of the three categories?"

If a rule does not fit verification, preparation, or completion, it is probably a technical constraint that should be an assertion gate. If it cannot be mechanically enforced and does not fit the three categories, consider whether it is actually necessary. Many rules exist because of a single failure that never recurred.

### "What if three rules are not enough?"

Three rules plus assertion gates should cover everything. If you find yourself needing a fourth rule, first check whether the behavior can be enforced by a gate instead. If it truly requires judgment (not a mechanical check), consider whether it can be folded into one of the existing three rules as a sub-case.

### "What if the agent still ignores the three rules?"

If the agent ignores a rule despite having only three, the rule is not the right defense. Convert it to a mechanical enforcement: a hook that blocks the action, a probe that injects the relevant state, or an assertion gate that checks the precondition. Rules are cognitive anchors. Mechanisms are the actual defense.

### "Should I literally have only 3 lines in my AI config?"

No. Your config file will also have build commands, code style conventions, and compaction directives. But the "rules" section -- the numbered items that tell the agent what to do before taking action -- should contain exactly three items. Everything else is either mechanical enforcement (hooks, gates) or reference information (style guides, command lists).
