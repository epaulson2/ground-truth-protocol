# Research Summary

Hold Point is grounded in research from six domains that have already solved the completion verification problem. This document summarizes the key findings from each domain and explains how they inform the Hold Point design.

For full citations and links, see [RESEARCH.md](RESEARCH.md).

---

## Aerospace: DO-178C and NASA RVM

### What They Built

**DO-178C** is the international standard for airborne software. It defines five Development Assurance Levels (DAL A through E), where DAL A (catastrophic failure) requires the most rigorous verification. Key requirements:

- **Pre-defined objectives**: Every verification activity has objectives defined before development starts, not after.
- **Independence**: Verification must be performed by a person or team independent of the development team. At DAL A, even test cases must be reviewed by someone who did not write them.
- **Traceability**: Every requirement must trace to a verification activity. Every verification activity must trace to evidence. Gaps are not permitted.
- **Structural coverage**: Code must be exercised at the MC/DC (Modified Condition/Decision Coverage) level for DAL A -- the most rigorous form of test coverage.

**NASA Requirements Verification Matrix (RVM)** extends this with a matrix that maps every requirement to a verification method (test, analysis, inspection, or demonstration) and tracks status. No requirement can be "assumed verified." Each must have specific evidence.

### What Hold Point Learned

1. **Criteria must be defined before work starts.** DO-178C requires verification objectives before development, not after. Hold Point requires YAML gate definitions before code is evaluated.
2. **Verification must be independent.** DO-178C prohibits self-verification at high assurance levels. Hold Point uses a judge agent independent of the builder.
3. **Evidence must be traceable.** DO-178C requires traceability from requirement to evidence. Hold Point produces timestamped gate results, judge reports, and approval records.

---

## Nuclear: ITAAC

### What They Built

**ITAAC** (Inspections, Tests, Analyses, and Acceptance Criteria) is the NRC's system for verifying nuclear reactor construction. Before a reactor can operate, every ITAAC must be completed with documented evidence.

Key properties of ITAAC:

- **Acceptance criteria are defined in the construction permit**, before construction begins. They cannot be retroactively modified to match what was built.
- **Each ITAAC specifies the inspection, test, or analysis** that will verify the criterion. The method is pre-defined, not chosen after the fact.
- **Evidence is physical**: radiographic examination results, pressure test records, material certifications. Not assertions, not self-assessments.
- **The reactor cannot operate until ALL ITAAC are verified.** There is no "90% is good enough." There is no schedule-based override. The hold point is absolute.

### What Hold Point Learned

1. **Criteria cannot be retroactively adjusted.** ITAAC are defined in the permit and cannot be weakened. Hold Point requires G1 (human approval) of criteria before they are used, and modifying approved criteria requires re-approval.
2. **Verification produces physical evidence.** ITAAC do not accept verbal claims. Hold Point produces JSON result files with specific evidence (HTTP response codes, SQL query results, command outputs).
3. **The hold point is absolute.** A reactor does not operate until every ITAAC passes. A Hold Point feature is not DONE until every gate passes, the judge approves, and the human signs off.

---

## Manufacturing: Toyota Jidoka and Poka-Yoke

### What They Built

**Jidoka** (autonomation) is Toyota's principle that machines should detect defects and stop automatically. When a defect is detected, the production line stops. The line does not restart until the root cause is addressed. No human decision is required to stop the line -- the machine detects the defect and stops itself.

The Andon cord extends this to human workers: any worker can pull the cord to stop the entire production line when they see a quality issue. The culture supports this -- stopping the line is valued, not punished.

**Poka-yoke** (mistake-proofing) is the complementary principle of making errors impossible by design. A USB connector can only be inserted one way. A car cannot shift out of park without pressing the brake. The system is designed so that the wrong action physically cannot be performed.

### What Hold Point Learned

1. **Automatic stop on defect detection.** Jidoka stops the line when quality fails. Hold Point blocks pipeline advancement when gates fail. No human decision needed -- the mechanism enforces the stop.
2. **Make errors impossible, not inadvisable.** Poka-yoke designs out the error. Hold Point guards make bypass impossible through hooks, not through rules that say "do not bypass."
3. **Culture supports stopping.** In Toyota's system, stopping the line is the right thing to do. In Hold Point, a failing gate is informative, not punitive. The system tells the agent what needs to be fixed, not just "BLOCKED."

---

## Big Tech: Google Canary, Netflix Chaos, Spotify Honk

### What They Built

**Google Canary Deployments**: New code is deployed to a small percentage of traffic first. Automated systems compare error rates, latency, and business metrics between canary and baseline. If the canary degrades any metric beyond a threshold, the deployment is automatically rolled back. No human approval needed for rollback -- the system decides.

**Netflix Chaos Engineering**: Netflix deliberately injects failures (Chaos Monkey, Chaos Kong) into production systems to verify that resilience mechanisms work. The key insight: you verify against the LIVE system under REAL conditions, not in a test environment. If a service claims to handle a database failure gracefully, Chaos Engineering kills the database and sees what happens.

**Spotify Honk**: Spotify's system for surfacing "unhealthy" services. Services are continuously monitored against health criteria. When a service fails its health checks, it is flagged and the responsible team is notified. The system does not wait for someone to check -- it continuously verifies.

### What Hold Point Learned

1. **Verify against the live system.** Netflix does not test resilience in staging. Hold Point does not test features with mocks. The live system is ground truth.
2. **Automate the rollback decision.** Google's canary system does not ask a human "should we roll back?" It measures metrics and decides. Hold Point's gate runner does not ask the agent "did this pass?" It runs the check and reports the result.
3. **Continuous verification, not one-time.** Spotify's health checks run continuously. Hold Point's continuous verification invalidates gate results when code changes.

---

## AI Research: Process Reward Models

### What They Built

**Process Reward Models (PRMs)** are a technique from OpenAI's research on mathematical reasoning. Instead of only checking whether the final answer is correct (outcome verification), PRMs verify each step in the reasoning process (process verification).

Key finding from "Let's Verify Step by Step" (OpenAI, 2023):
> Process verification -- checking each reasoning step -- outperforms outcome verification -- checking only the final answer. The improvement is substantial: process reward models achieve significantly higher accuracy than outcome reward models on the MATH benchmark.

**Why process verification wins:**
- If you only check the final answer, a wrong step that happens to produce a right answer is rewarded.
- If you check each step, wrong steps are caught early, before they compound.
- Process verification provides more granular feedback: not just "wrong answer" but "step 3 was wrong."

### What Hold Point Learned

1. **Verify each step, not just the final result.** PRMs verify each reasoning step. Hold Point verifies at each pipeline stage, not just at the end.
2. **Gate results are step-level verification.** Each criterion in a gate is a step verification. "Login works" is one step. "Password hashing correct" is another. "Token grants access" is another. Verifying all three is more informative than verifying only the final result.
3. **Early detection reduces wasted work.** A PRM that catches a wrong step at step 3 saves the computation of steps 4-10. A gate that catches a missing database table early saves the agent from building an entire feature on a broken foundation.

---

## Software Engineering: DoD, ATDD, Fitness Functions

### What They Built

**Definition of Done (DoD)**: Agile teams define explicit criteria for what "done" means. Code is not done when it is written. It is done when it is written, tested, reviewed, documented, and deployed (or whatever the team's DoD specifies). The DoD is agreed upon before work starts.

**Acceptance Test-Driven Development (ATDD)**: Tests are written before implementation, based on the specification. The tests define the behavior that the implementation must produce. Implementation is complete when the acceptance tests pass. The tests are the specification, operationalized.

**Fitness Functions** (from "Building Evolutionary Architectures"): Automated checks that verify architectural properties continuously. A fitness function might verify that no module has more than N dependencies, or that response times stay under a threshold, or that security headers are present on all endpoints. Fitness functions run continuously, not once.

### What Hold Point Learned

1. **Define "done" before starting.** The DoD is defined before work begins. Hold Point's YAML gates are defined before (or at the start of) implementation.
2. **Tests as executable specification.** ATDD writes tests from the spec before writing code. Hold Point's gate criteria are an executable specification -- they define what the feature must do in terms that can be automatically verified.
3. **Continuous verification of properties.** Fitness functions run on every build. Hold Point's continuous verification invalidates gate results when code changes, ensuring that properties verified yesterday still hold today.

---

## What Does Not Work

The research also documents approaches that do not work. These are covered in detail in [what-doesnt-work.md](what-doesnt-work.md), but summarized here:

| Approach | Why It Fails | Research |
|----------|-------------|----------|
| More rules | Compliance degrades with instruction count; shift from errors to omission | IFScale (arXiv:2507.11538) |
| Longer checklists | Lost-in-the-middle effect; logical coherence paradoxically hurts | Chroma Context Rot |
| Self-verification | High adherence masks incidental non-violation, not deliberate compliance | LessWrong safety rules study |
| Agent-written tests | Tests verify what was built, not what was specified; circular validation | QCR case study (18% alignment) |
| Post-hoc review | Damage is already done; sunk cost makes rejection unlikely | Behavioral economics |
| More training | Stronger capabilities paradoxically reduce rule adherence | LessWrong safety rules study |

---

## The Five Properties

The research converges on five properties required for reliable completion verification. Every domain that solved this problem implements all five. Every approach that fails is missing at least one.

| Property | Aerospace | Nuclear | Manufacturing | Big Tech | AI Research |
|----------|-----------|---------|---------------|----------|-------------|
| Pre-defined criteria | DO-178C objectives | ITAAC in permit | Design specifications | SLOs/SLIs | PRM step definitions |
| Independent verification | Independent V&V team | Independent inspectors | QA inspectors | Automated metrics | Separate reward model |
| Live system verification | Flight testing | Physical evidence | Production line testing | Canary traffic | Live model evaluation |
| Blocking enforcement | DAL certification hold | Reactor operation hold | Jidoka line stop | Automatic rollback | Step-level rejection |
| Bypass prevention | Regulatory audit | NRC oversight | Poka-yoke | Continuous monitoring | Process-level checking |

Hold Point implements all five.
