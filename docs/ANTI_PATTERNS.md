# Anti-Patterns to Avoid

These are the common mistakes teams make when trying to prevent AI agent failures. Each anti-pattern is individually rational but collectively counterproductive. Recognizing these patterns is the first step to breaking the cycle.

## 1. Rule Accumulation

### The Pattern

Every time the AI agent makes a mistake, add a new rule to prevent it from happening again.

- Agent creates duplicate database -> Add rule: "Check if database exists"
- Agent asks documented question -> Add rule: "Read docs before asking"
- Agent ignores spec -> Add rule: "Read spec before implementing"
- Agent ignores that rule -> Add rule: "Reread master context at session start"
- Agent ignores master context -> Add meta-rule: "Follow all rules listed above"

### Why It Feels Right

Each rule is correct. Each rule addresses a real failure. Adding a rule feels like progress -- you identified the problem and addressed it.

### Why It Fails

Research on instruction-following capacity (IFScale) shows that AI model compliance degrades as instruction count increases. At 500 instructions, even frontier models achieve only 68% accuracy. The critical finding: models shift from modification errors to complete omission. Past the threshold, the model does not follow rules approximately -- it abandons them entirely.

Each new rule adds cognitive load that degrades compliance with all existing rules. Rule 12 does not just add one more item; it reduces the likelihood that Rules 1-11 are followed.

### What to Do Instead

Add a **mechanism** (assertion gate, hook, probe) instead of a rule. Mechanisms execute regardless of the agent's instruction-following capacity. If the database-exists check is a hook, it does not matter whether the agent remembers the rule -- the hook fires automatically.

---

## 2. Document Sprawl

### The Pattern

Create more documentation to ensure the AI agent has all the context it needs. Master context documents, compass files, registries, trackers, checklists, reference documents.

A typical evolution:
- Start: README.md (50 lines)
- Month 2: README.md + ARCHITECTURE.md + CONTRIBUTING.md
- Month 4: Add COMPASS.md (300 lines) as "master context"
- Month 6: COMPASS.md grows to 759 lines, add SPEC_REGISTRY.md
- Month 8: Add SPEC_COMPLIANCE.md, DOCUMENTATION_GUIDE.md, CLAUDE_REFERENCE.md
- Month 10: 76 research documents, 14 design documents, 6-layer guardrail system

### Why It Feels Right

More documentation means more context. More context means better decisions. If the agent does not know something, the solution must be to document it.

### Why It Fails

Context rot (Chroma Research) shows that accuracy drops from 70-75% to 55-60% with just 20 retrieved documents. The "lost in the middle" effect means that information in the middle of large documents receives minimal attention. Logical coherence paradoxically hurts performance -- the model follows the narrative flow instead of extracting specific actionable items.

A 759-line master context document competes with the user's immediate request, the code being edited, and the conversation history. Important instructions occupy middle positions with diminishing attention weights.

### What to Do Instead

Replace large context documents with **small, factual probe output** that is automatically injected. The probe answers the same questions the document would, but in 100 lines instead of 759, with verified current state instead of potentially stale documentation, and at the top of context (high attention position) instead of buried in the middle.

---

## 3. Trust-Based Verification

### The Pattern

Verify that the agent followed instructions by asking it.

- "Did you read the spec before implementing?" -> "Yes, I reviewed the specification."
- "Did you check if the database exists?" -> "Yes, the database should be set up."
- "Did you follow the coding standards?" -> "Yes, I followed all project conventions."

### Why It Feels Right

The agent is capable of answering questions. Asking it to confirm compliance seems like a reasonable verification step.

### Why It Fails

The agent will almost always answer affirmatively. It is trained to be helpful and to confirm it has followed instructions. "Did you read the spec?" produces "Yes" regardless of whether the spec was actually loaded and processed. The verification provides false confidence.

Research on safety rules (LessWrong) found that "high adherence scores often masked incidental non-violation rather than deliberate compliance." Many agents did not choose to comply; they were just confused into appearing compliant.

### What to Do Instead

Replace verbal confirmation with **verification artifacts**. Instead of "did you read the spec?", check whether a spec file was read in the session log. Instead of "did you check the database?", run a probe and inject the output. Verification should produce timestamped evidence, not verbal claims.

---

## 4. Instruction Density

### The Pattern

Pack as many instructions as possible into the system prompt or configuration file. Cover every edge case. Anticipate every failure.

```markdown
## Rules
1. Always do X before Y
2. Never do A without B
3. When doing C, first check D, then E, then F
4. If G happens, follow steps H-I-J-K
5. Before any L, verify M, N, O, and P
...
11. Remember to follow rules 1-10 at all times
```

### Why It Feels Right

Thoroughness is a virtue. Covering every case means fewer surprises. Detailed instructions leave no room for ambiguity.

### Why It Fails

The IFScale research documents a **primacy effect**: models show strongest bias toward earlier instructions at 150-200 instructions, then show uniform failure at extreme densities. Rule 1 gets more attention than Rule 11 purely due to position. At high density, all instructions become equally ignored.

Multi-step rules (e.g., "check registry, read doc, cite sections, use template, update alignment, run verification") are the most likely to be completely abandoned because each step has an implicit speed vs. thoroughness conflict.

### What to Do Instead

Reduce instructions to **the smallest set that requires genuine judgment**. Everything that can be mechanically checked should be a hook or gate, not an instruction. The remaining instructions (ideally 3) should each be a single positive action: "Verify state. Read spec. Show evidence."

---

## 5. Post-Hoc Rules

### The Pattern

After a failure, create a rule that addresses the specific failure scenario rather than the root cause.

- Database was recreated -> Rule: "Do not create databases that already exist"
- API keys were requested -> Rule: "Do not ask about API keys"
- Wrong table was modified -> Rule: "Always check table ownership first"

### Why It Feels Right

The rule directly addresses the failure. If followed, the specific failure would not recur.

### Why It Fails

Post-hoc rules address symptoms, not root causes. The root cause of "database was recreated" is not "the agent did not know not to create databases." The root cause is "the agent had no awareness of existing database state." A rule about databases does not help when the next failure is about files, services, or credentials -- same root cause, different symptom.

Post-hoc rules also accumulate rapidly. Each failure produces a new rule. The rule list grows with every failure, increasing cognitive load, which increases the likelihood of the next failure, which produces another rule.

### What to Do Instead

Address the **root cause**. The root cause of most drift failures is "the agent did not know what exists." The fix is a probe that injects state, not a rule about a specific resource type. One probe prevents database recreation, credential requests, and duplicate file creation -- all from the same mechanism.

---

## 6. Context Pollution

### The Pattern

Load as much context as possible to ensure the agent has everything it might need. Include all documentation, all configuration, all history.

- Load the full project architecture document
- Load all design specs at session start
- Include the complete conversation history
- Add research documents for reference
- Include the change log for context on recent changes

### Why It Feels Right

More context means the agent has more information to make decisions. You cannot have too much relevant information.

### Why It Fails

Anthropic's own research team identifies context engineering -- curating the **smallest** set of high-signal tokens -- as the critical discipline. The emphasis is on smallest, not largest. Loading everything is the opposite of context engineering.

Context pollution creates two problems:
1. **Signal dilution**: Important information (like "database exists") competes with less important information (like the architecture document's section on deployment strategy) for attention weight
2. **Distractor effects**: Chroma Research showed that plausible but irrelevant information (distractors) degrade performance more than random noise. Loading architecture documents when the task is a bug fix introduces high-quality distractors.

### What to Do Instead

Apply the **smallest effective context** principle. At session start, inject only the probe output (~100 lines of verified state). Load additional context on demand -- when the agent needs a spec, it loads that specific spec, not all specs. When it needs architecture context, it loads the relevant section, not the full document.

The probe provides just-in-time state. Assertion gates provide just-in-time constraints. Specs are loaded just-in-time before implementation. Nothing is pre-loaded "just in case."

---

## The Meta-Anti-Pattern

All six anti-patterns share a common root: **treating the AI agent as a human who needs more information, better instructions, and clearer rules.**

AI agents are not humans. They do not improve with more instructions. They do not get better at following rules when you add more rules. They do not become more reliable when you load more context.

AI agents improve when you:
- **Inject verified state** instead of hoping they will discover it
- **Mechanically enforce constraints** instead of hoping they will follow them
- **Reduce cognitive load** instead of increasing it
- **Make wrong actions impossible** instead of making them inadvisable

The Ground Truth Protocol is built on this understanding. It does not tell the agent to do the right thing. It makes it difficult to do the wrong thing.
