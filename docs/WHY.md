# Why: The Context Drift Problem

## The Failure Mode Nobody Talks About

AI coding agents are getting better at writing code. They are not getting better at knowing what already exists.

A team has a production database with 38 tables, 50,000 drug records, and a fully configured API. They ask their AI coding agent to "set up the database." The agent responds with `CREATE DATABASE`, `CREATE TABLE` statements, and a migration plan -- for a database that already exists and is populated.

This is not a hallucination. The agent is not making up information. It is applying its training prior (how to set up databases in general) because it has no awareness of the project's actual state. The information about the existing database may be in a project document somewhere, but the agent did not read it -- or read it and forgot it as the context window filled with other tokens.

This failure has a name: **context drift**. It is the progressive degradation of an AI agent's awareness of project state over the course of a session, a task, or a multi-turn conversation.

## The Academic Evidence

Context drift is not anecdotal. It is a quantified, reproduced phenomenon across multiple research studies.

### Agent Drift Is Measurable

Chen et al. (arXiv:2601.04170, January 2026) studied behavioral degradation in multi-agent LLM systems and measured:

- **42% task success rate decline** in drifting vs. stable systems
- **Drift onset at median 73 interactions** -- not thousands, seventy-three
- **3.2x increase in human interventions** (from 0.31 to 0.98 per task)
- **Drift acceleration**: Decline rates double from early to later stages

The study identified three drift categories:
- **Semantic drift**: The agent's understanding of the task deviates from the original intent
- **Coordination drift**: In multi-agent systems, agents lose consensus about goals
- **Behavioral drift**: The agent develops unintended strategies (like skipping verification)

### More Instructions Make Compliance Worse

The IFScale benchmark (arXiv:2507.11538) specifically measured how AI models handle increasing instruction density:

| Pattern | Models | Behavior |
|---------|--------|----------|
| Threshold decay | o3, Gemini 2.5 Pro | Near-perfect until ~150 instructions, then sharp collapse |
| Linear decay | GPT-4.1, Claude 3.7 Sonnet | Steady, predictable accuracy reduction |
| Exponential decay | Claude 3.5 Haiku, LLaMA 4 Scout | Rapid early collapse, stabilizing at 7-15% floor |

The most important finding: as instruction density increases, models shift from **modification errors** (doing the wrong thing) to **complete omission** (not doing the thing at all). At high density, the model does not attempt to follow the rule incorrectly -- it abandons the rule entirely.

This means that adding Rule 12 to prevent the next failure may cause the model to abandon Rules 3, 7, and 10 entirely.

### Context Rot Is Real

Chroma Research ("Context Rot: How Increasing Input Tokens Impacts LLM Performance") demonstrated:

- With just 20 retrieved documents (~4,000 tokens), accuracy drops from **70-75% to 55-60%** based on information placement alone
- The "lost in the middle" effect is confirmed: models attend most to beginning and end positions
- Information buried in middle positions receives minimal attention
- **Logical coherence paradoxically hurts performance**: models perform worse when surrounding context preserves logical flow, because the model follows the narrative rather than extracting specific actionable items

That last finding is particularly concerning. Well-organized, logically coherent project documents may actually perform *worse* than fragmented bullet points, because the model reads along with the narrative instead of searching for the specific rule it needs.

### Multi-Turn Conversations Degrade Systematically

Research on multi-turn interactions (arXiv:2510.07777) found:

- All tested LLMs show **39% lower performance in multi-turn conversations** than single-turn
- LLMs make assumptions in early turns and prematurely commit to solutions
- **Once an LLM takes a wrong turn, it does not recover** -- it commits to the incorrect path
- The agent "overly relies" on its early outputs, creating a compounding feedback loop

When an agent encounters "set up the database" as an early instruction, it immediately activates its training prior for database setup. Once it has mentally committed to `CREATE DATABASE`, it does not backtrack to check whether the database exists. This is systematic, not anomalous.

## The Paradox of More Guardrails

Every team that encounters context drift follows the same pattern:

1. Agent creates a duplicate database. Team adds a rule: "Check if the database exists before creating one."
2. Agent asks for API keys that are documented. Team adds a rule: "Read the docs before asking questions."
3. Agent builds features without reading specs. Team adds a rule: "Read the spec before implementing."
4. Agent ignores all three rules. Team adds a master context document with all project state.
5. Agent ignores the master context document. Team adds more rules about reading the master context document.

Each guardrail is individually rational. Collectively, they are self-defeating. This is **extraneous load accumulation** (Sweller, 1988) -- each well-intentioned instruction adds to the total load that degrades performance on all instructions.

The paradox: **the more guardrails you add in response to failures, the more likely future failures become**, because the growing instruction set dilutes attention on any individual rule.

## Why Documents Fail as Guardrails

A document that says "read X before doing Y" has three failure modes:

### 1. It Requires Voluntary Compliance

The document is an instruction, not a mechanism. The agent can comply or not comply. There is no physical barrier between the agent and the wrong action. The aviation industry calls this the difference between a **procedure** (written in a manual) and a **checklist** (physically executed before takeoff). Procedures are advisory. Checklists are mechanical.

### 2. It Competes for Attention

Every token in the context window competes for attention weight. A rule buried on line 47 of a configuration file competes with the user's immediate request, the code the agent is looking at, the conversation history, and every other instruction. Research shows that models attend most to tokens at the beginning and end of context, with middle positions receiving minimal attention. Your carefully written Rule 10 may be in the dead zone.

### 3. It Becomes Stale

Documents describe intended state at the time they were written. The project evolves. New tables are added. Services are reconfigured. API keys change. Unless the document is updated every time the project changes (it is not), it describes a historical state, not the current state. When the agent reads the document and acts on it, it may be acting on information that was true last week but is false today.

## Why Mechanisms Succeed

A mechanism does not require compliance. It executes.

Consider two approaches to preventing duplicate database creation:

**Document approach:**
```markdown
Rule 10: Before creating any database, check if it already exists by running
`psql -c "SELECT 1" mydb`. If it succeeds, do not create a new database.
```

**Mechanism approach:**
```bash
# PreToolUse hook — runs automatically before any Bash command matching CREATE DATABASE
DB_EXISTS=$(psql -c "SELECT 1" mydb 2>/dev/null && echo "yes" || echo "no")
if [ "$DB_EXISTS" = "yes" ]; then
  echo "BLOCKED: Database 'mydb' already exists with $(psql -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" mydb) tables."
  exit 1
fi
```

The document requires the agent to:
1. Remember the rule exists
2. Decide to follow it
3. Correctly execute the check
4. Correctly interpret the result
5. Decide not to proceed

The mechanism requires the agent to do nothing. The hook fires automatically. If the database exists, the action is blocked. The agent receives the block message and adjusts. There is no compliance decision because there is no option to not comply.

This is the fundamental insight of the Ground Truth Protocol: **replace instructions that require voluntary compliance with mechanisms that inject verified state involuntarily.**

The agent does not need to be told "the database exists with 38 tables." The probe output already says so. The agent does not need to be told "do not create a database." The assertion gate already blocks it. The rules are not the defense. The mechanisms are the defense. The rules exist only as cognitive anchors that help the agent understand why the mechanisms are running.

## The Path Forward

The solution is not better documents. It is not more rules. It is not longer context files. It is **context engineering**: curating the smallest set of high-signal tokens that maximize desired outcomes.

Anthropic's own research team identifies context engineering -- not prompt engineering -- as the critical discipline for AI agent development. The fix is not more documents to read but better mechanisms for injecting verified state.

The Ground Truth Protocol provides five such mechanisms. See [FRAMEWORK.md](FRAMEWORK.md) for the complete framework.
