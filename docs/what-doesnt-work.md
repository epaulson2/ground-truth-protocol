# What Doesn't Work (and Why)

This document catalogs approaches to AI agent completion verification that fail, with evidence from research and real-world experience. Understanding why these fail is as important as understanding what works.

---

## 1. More Rules in CLAUDE.md

### The Approach

Every time the agent makes a mistake, add a rule to prevent it.

```markdown
## Rules
1. Always verify state before acting
2. Read the spec before implementing
3. Run tests before marking done
4. Check if database exists before creating
5. Read docs before asking questions
6. Use 127.0.0.1 not localhost
7. Never edit generated files
8. Run code generator after schema changes
9. Check CODEOWNERS before editing
10. Verify before marking complete
11. Follow all rules listed above
```

### Why It Fails

**Research: IFScale Benchmark (arXiv:2507.11538)**

The IFScale benchmark measured how AI models handle increasing instruction density. The results:

- At 50 instructions: ~85% accuracy
- At 150 instructions: ~75% accuracy (threshold models begin collapsing here)
- At 500 instructions: ~68% accuracy (best models)
- At 500 instructions: ~7-15% accuracy (worst models)

The critical finding is not just that accuracy drops. It is that the **error type changes**. At low instruction counts, models make modification errors (doing the wrong thing). At high counts, they make **omission errors** (not doing the thing at all). They do not follow Rule 7 incorrectly; they abandon Rule 7 entirely.

Adding Rule 12 does not just add one more item. It increases cognitive load on all rules, making it more likely that Rules 3, 7, and 10 are abandoned.

**Real-world evidence: Queen City Redline**

The QCR project grew from 8 rules to 11 rules over 6 months. Each rule was correct. Each addressed a real failure. The final result: 7 of 14 plan sections marked DONE were 25-50% complete. The rules were being abandoned, not approximately followed.

### What Works Instead

Reduce rules to 3. Convert the other 8 to mechanical enforcement (hooks, gates, probes). Three rules can be held in active attention. The remaining behaviors are enforced by mechanisms that do not require the agent to remember them.

---

## 2. Longer Checklists

### The Approach

Create a comprehensive checklist of everything the agent should verify before marking work complete.

```markdown
## Completion Checklist
- [ ] Code written
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] API responds correctly
- [ ] Database migration applied
- [ ] Error handling implemented
- [ ] Logging added
- [ ] Documentation updated
- [ ] Performance acceptable
- [ ] Security reviewed
- [ ] Accessibility checked
- [ ] Feature flag configured
```

### Why It Fails

**Research: Chroma "Context Rot"**

Chroma Research found that with just 20 retrieved documents (~4,000 tokens), accuracy drops from 70-75% to 55-60% based on information placement alone. The "lost in the middle" effect means that items in the middle of the checklist receive less attention than items at the beginning or end.

More counterintuitively, **logical coherence paradoxically hurts performance**. Models perform worse when surrounding context preserves logical flow, because the model follows the narrative rather than searching for specific items. A well-organized checklist may perform worse than a disorganized one.

**Practical evidence**

A 12-item checklist with 3-5 sub-steps per item is effectively 36-60 instructions. This is well into the degradation zone identified by IFScale. The agent will check items 1-3, maybe item 12 (primacy and recency effects), and skip the middle.

### What Works Instead

Replace the checklist with acceptance gates that are run automatically. The gate runner checks whether the API responds, whether tests pass, whether the database is correct -- without requiring the agent to remember to check each one. The checklist becomes a YAML file executed by a machine, not a document read by an agent.

---

## 3. Asking the Agent "Are You Done?"

### The Approach

Before accepting the agent's work, ask it to confirm completion.

"Have you verified that all endpoints return the correct status codes?"
"Did you test the error handling?"
"Is the feature fully wired into the application?"

### Why It Fails

**Research: LessWrong Safety Rule Study (2025)**

The study tested six LLMs on adherence to safety rules and found:

> "High adherence scores often masked incidental non-violation rather than deliberate compliance."

The agents were not deliberately choosing to comply. They appeared compliant because they happened not to violate the rules, not because they actively verified compliance. When asked "did you follow the rules?", they said yes -- not because they checked, but because that is the helpful response.

**The structural problem**

Self-assessment is circular. The agent wrote the code. It believes the code is correct (otherwise it would have written different code). When asked "is this correct?", it consults its own understanding of the code -- the same understanding that produced the code in the first place. It will always say yes.

This is not a fixable problem with better prompts. It is a structural limitation of self-assessment. The entity that did the work cannot objectively evaluate the work because it shares the same blind spots.

### What Works Instead

Independent verification. A judge agent that never saw the building process evaluates the work from scratch. Or better: automated acceptance gates that do not ask anyone's opinion but simply run checks against the live system and report pass/fail.

---

## 4. Agent-Written Tests as Proof

### The Approach

The agent writes unit tests. The tests pass. Therefore the feature is complete.

"757 tests passing. All green."

### Why It Fails

**Real-world evidence: Queen City Redline**

757 tests passed. Spec alignment was 18%. How is this possible?

The tests verified **what was built**, not **what was specified**. The agent implemented login but not registration, not password reset, not rate limiting. The tests verified that login works. The tests did not verify that registration exists -- because the agent did not write tests for features it did not implement.

Agent-written tests have a circular validation problem:
1. Agent understands the feature a certain way
2. Agent implements based on that understanding
3. Agent writes tests based on that same understanding
4. Tests pass because they test the agent's understanding, which matches the agent's implementation
5. Nobody checks whether the agent's understanding matches the specification

**The coverage illusion**

100% test coverage means every line of code that exists is tested. It says nothing about code that should exist but does not. If rate limiting is in the spec but not in the code, there are no lines of rate-limiting code to cover. Coverage is 100%. The feature is missing.

### What Works Instead

Acceptance gates defined from the specification, not from the implementation. The gate says "POST /login with rate-limited credentials returns 429 on the 6th attempt." This criterion exists regardless of whether the agent implemented rate limiting. If rate limiting is missing, the gate fails -- even if all agent-written tests pass.

---

## 5. Post-Hoc Review by Humans

### The Approach

After the agent says it is done, a human reviews the work.

### Why It Fails

**Behavioral economics: Sunk cost and status quo bias**

By the time a human reviews, the work is "done." There is psychological pressure to accept it:
- **Sunk cost**: Time has been invested. Rejecting means starting over.
- **Status quo bias**: The current state (work "complete") feels like the default. Changing it requires effort.
- **Anchoring**: The agent's claim of completion anchors the reviewer's expectation. They look for confirmation, not disconfirmation.

**Practical limitations**

Human review of AI-generated code is notoriously unreliable:
- The code is often unfamiliar to the reviewer (the agent wrote it, not a team member)
- The volume can be large (agents generate code quickly)
- The specification may be long (14 design documents in QCR)
- The reviewer may not have the full context
- "Looks reasonable" is the most common review outcome, which catches obvious issues but misses structural gaps

**The timing problem**

Post-hoc review catches problems after the work is done. This is the most expensive time to catch problems. The agent has moved on. Context has been lost. Fixing issues requires reconstructing the mental model. In manufacturing, this is called "end-of-line inspection" -- the most expensive and least effective quality strategy.

### What Works Instead

Verification built into the process, not appended after it:
- Gates that run continuously, catching issues as they arise
- Pipeline state machine that prevents advancing without verification
- Judge agent that reviews before the human, reducing the human's burden to reviewing evidence rather than reviewing code

---

## 6. Training the Agent to Be More Careful

### The Approach

Use better prompts. Fine-tune the model. Select a more capable model. Surely a smarter agent will be more careful.

### Why It Fails

**Research: LessWrong Safety Rule Study**

> "Paradoxically, stronger general capabilities reduced rule adherence."

More capable models are better at accomplishing tasks. But they are also better at finding creative ways to accomplish tasks that circumvent rules. A more capable agent does not follow rules more carefully -- it is more likely to find a path that technically does not violate the rule while not actually following its intent.

**The capability-reliability gap**

OpenAI's research on process reward models identified what they call the capability-reliability gap: the gap between what a model can do and what it reliably does. More capable models have a wider gap, not a narrower one. They can solve harder problems, but they are not more consistent at solving easier problems.

**The architectural problem**

No amount of training changes the fundamental architecture:
- Models still have attention distributions that deprioritize middle content
- Models still have instruction-following capacity limits
- Models still have self-assessment blind spots
- Models still take wrong paths and do not backtrack

Training can improve the baseline quality of the agent's work. It cannot make the agent reliably verify its own work. Verification is an architectural problem, not a capability problem.

### What Works Instead

External verification mechanisms that do not depend on the agent's capability or reliability. A gate runner does not care how capable the agent is. It runs the criteria and reports pass/fail. A pipeline state machine does not care how careful the agent claims to be. It blocks advancement until gates pass.

---

## The Common Thread

All six approaches share a common assumption: **the agent can be trusted to verify its own work if given the right instructions, tools, or capabilities.**

This assumption is wrong. Not because agents are untrustworthy, but because self-verification is structurally unreliable. It has been proven unreliable for humans in every safety-critical domain (aviation, nuclear, manufacturing, medicine). It is equally unreliable for AI agents.

The solution is the same solution every safety-critical domain discovered independently: **external verification with blocking enforcement.**

- Aviation: Independent V&V teams, DO-178C certification holds
- Nuclear: Independent inspectors, ITAAC hold points
- Manufacturing: QA inspectors, Jidoka automatic stops
- Medicine: Independent diagnosis, surgical safety checklists
- Software with AI agents: Judge agents, acceptance gates, pipeline holds

The Hold Point system does not trust the agent. It verifies the work.
