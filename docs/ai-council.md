# Decision Council

The Decision Council is a Codex-specific, repository-local workflow for ambiguous technical and product decisions. It uses several specialized subagents to pressure-test a proposal from different angles, then asks the main Codex agent to synthesize the result as chair.

This is a decision aid, not a truth machine. It does not guarantee correctness, neutrality, objectivity, safety, or consensus. Its value is in forcing dissent, surfacing assumptions, naming missing evidence, and ending with a concrete next step that a human can review.

## When To Use It

Use the Decision Council for decisions where a single quick answer may hide important tradeoffs:

- Architecture decisions.
- Product feature scope and prioritization.
- Rollout plans.
- Monetization, support, and sustainability choices.
- Risky implementation choices.
- Regression investigation planning.
- Privacy, security, App Store, licensing, or operational questions where the team needs explicit assumptions and evidence.

## When Not To Use It

Do not use the council when:

- The task is a straightforward code edit, typo fix, or command output request.
- The decision is already made and only execution remains.
- The cost of running multiple subagents is larger than the risk of a wrong call.
- You need authoritative legal, medical, financial, security, or compliance advice. Use qualified human review.
- The question requires private WhatsApp data. Keep private archives, messages, media paths, screenshots, and generated exports out of prompts and outputs.

## Standard Mode Prompt

```text
Ask the Decision Council about this decision: [question/proposal/context].

Spawn these advisors in parallel:
- council_contrarian
- council_first_principles
- council_expansionist
- council_outsider
- council_executor

Wait for all advisors. Then synthesize as chair.

Chair output must include:
1. Decision summary
2. Strongest argument for
3. Strongest argument against
4. Hidden assumptions
5. Evidence we have
6. Evidence missing
7. Reversibility
8. Risk level
9. Recommended next step
10. Stop condition
11. What would change the recommendation

Do not majority-vote. If disagreement remains, preserve it explicitly.
```

## Deep Mode Prompt

```text
Ask the Decision Council in deep mode about this decision: [question/proposal/context].

First spawn:
- council_contrarian
- council_first_principles
- council_expansionist
- council_outsider
- council_executor

Then spawn council_reviewer agents to review the advisor outputs for unsupported claims, missing evidence, and weak reasoning.

Finally synthesize as chair with explicit dissent and one concrete next step.
```

## Expected Output Schema

The chair synthesis should use this schema:

```text
Decision summary:
Recommendation:
Risk level:
Reversibility:

Strongest argument for:
Strongest argument against:

Hidden assumptions:
Evidence we have:
Evidence missing:
Speculative conclusions:
Unresolved disagreement:

Recommended next step:
Validation plan:
Stop condition:
What would change the recommendation:
```

Use `low`, `medium`, `high`, or `unknown` for risk level. Use `easy`, `moderate`, `hard`, or `one-way` for reversibility. If the evidence is thin, say so directly.

## Chair Synthesis Rules

The chair owns the final judgment. The chair must not average opinions, count votes, or smooth away disagreement.

The chair must:

- Preserve the strongest argument for and against the proposal.
- Identify hidden assumptions.
- Separate available evidence from missing evidence.
- Label speculative conclusions.
- Identify unresolved disagreement explicitly.
- Consider reversibility before recommending scope.
- Prefer a concrete next step over a broad implementation commitment.
- Include a stop condition.
- Explain what new evidence would change the recommendation.

The chair may recommend proceeding, rejecting, narrowing, delaying, or running a reversible probe. A narrow next step is often the best recommendation when the upside is real but evidence is incomplete.

## Advisor Roles

The repo defines these Codex custom agents under `.codex/agents/`:

- `council_contrarian`: strongest case against the proposal.
- `council_first_principles`: reframes the question around the real objective and constraints.
- `council_expansionist`: upside, reuse, optionality, and missed opportunity.
- `council_outsider`: unclear context and outsider comprehension.
- `council_executor`: smallest reversible next step, validation, rollback, owner, docs, and stop conditions.
- `council_reviewer`: peer review of another council response for unsupported claims and weak reasoning.

## Examples

### Architecture Decision

```text
Ask the Decision Council about this decision: Should we add packaged archive import support that unpacks a single transferred archive inside the iOS app, instead of continuing to rely on raw folder transfer?

Context: The app is a local, read-only WhatsApp archive viewer. Large archives may contain tens of GB and more than 100k files. The project must not upload private data and should avoid eager media loading.
```

Expected chair focus: transfer reliability, storage pressure, App Store review risk, file-provider behavior, read-only guarantees, migration path, and a reversible prototype.

### Product Feature Decision

```text
Ask the Decision Council about this decision: Should the viewer add a richer Stories media browser before improving the per-chat media library?

Context: Status/story detection is intentionally conservative. The current product has a lightweight Stories section and a Chat Info media view.
```

Expected chair focus: user value, evidence that Stories data is reliably classified, confusion risk, fixture coverage, simpler sequencing, and what validation would justify priority.

### Open-Source Monetization Or Support Decision

```text
Ask the Decision Council about this decision: Should this open-source project offer paid setup support for non-developer users who want help extracting and opening their own local archives?

Context: The project handles highly private local data. It is pre-release and currently requires an Xcode/developer workflow unless another distribution path is added later.
```

Expected chair focus: privacy boundaries, liability, support burden, documentation gaps, conflict with open-source expectations, clear scope, and a stop condition if support requests require private data access.

### Regression Investigation Planning

```text
Ask the Decision Council about this decision: How should we investigate a suspected regression where duplicate-title archive fragments are reappearing in normal chat search?

Context: Do not print private message contents or raw private identifiers. Use synthetic fixtures or schema-only observations when possible.
```

Expected chair focus: smallest reproducible case, fixture-first investigation, privacy-safe logs, likely files touched, validation commands, rollback plan, and stop conditions for unclear private-data-only evidence.

## Limitations

The Decision Council can improve reasoning discipline, but it cannot guarantee truth, correctness, neutrality, safety, or compliance. It can miss facts, overfit the prompt, amplify bad assumptions, or produce confident but wrong conclusions.

Human review remains required. For high-stakes privacy, security, legal, App Store, licensing, financial, or user-safety decisions, treat council output as preparation for qualified human judgment, not a replacement for it.
