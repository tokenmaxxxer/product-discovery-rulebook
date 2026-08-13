---
axis: guardrail-metric-status
rule_count_floor: 10
---

# Guardrail metric naming and status reporting

Research trail: guardrail-metric practice fetched this session via Statsig's guardrail explainer, Optibase's guardrail glossary, PrepVector's secondary-vs-guardrail explainer, and abtestresult.com's guardrail article; scoped narrowly to the naming/status-reporting decisions distinct from the threshold-fixing rules already covered in hypothesis-preregistration.md.

## Rules

1. When naming guardrail metrics for a hypothesis, choose metrics the team explicitly does NOT want to see harmed (e.g. refund rate, support ticket volume, page-load latency), never the metric the experiment is trying to improve — guardrail metrics are "not the metric you are trying to improve — they are the ones you do not want to break," so listing the primary metric itself as its own guardrail is a category error that adds no protection. source: https://www.optibase.io/glossary/guardrail-metric

2. When a change plausibly affects revenue, trust, or system health in a way the primary metric would not detect (e.g. a UI change that could raise engagement while quietly increasing complaint volume), name that risk explicitly as a guardrail metric rather than leaving it unmonitored — guardrails exist to catch exactly this class of hidden harm that a single primary metric's improvement would otherwise mask. source: https://www.statsig.com/blog/what-are-guardrail-metrics-in-ab-tests

3. When distinguishing a secondary metric from a guardrail metric, keep the two lists separate and label each explicitly — a secondary metric is something the team is curious about or hopes moves favorably, while a guardrail metric is a metric that must not move adversarially; collapsing both into one undifferentiated "other metrics" list erases the guardrail's veto power over the verdict. source: https://prepvector.substack.com/p/explain-like-i-am-5-day-16-what-are

4. When a record reports the outcome of a measured hypothesis, state the guardrail-metric status explicitly and adjacent to the primary metric result — never implied by omission — "a test is only a real win when the primary metric improves and every guardrail stays inside its safe range," so a record that reports only the primary metric's result is incomplete regardless of how favorable that result looks. source: https://abtestresult.com/articles/guardrail-metrics

5. When a guardrail metric's measured value is inside its registered threshold but close to the boundary, report the actual measured value next to the threshold (not just "guardrail OK") — a boundary-adjacent pass is a materially different signal from a comfortable pass, and collapsing both into a binary OK/not-OK label discards information a reviewer needs to judge trust in the result. source: https://www.optibase.io/glossary/guardrail-metric

6. When a guardrail trips (breaches its threshold) while the primary metric wins, record the result as reduced-trust or kill per the pre-registered rule, not as a win with a caveat appended — "the simplest rule: a guardrail trips if it gets statistically worse, even if the primary metric is winning," so softening a tripped guardrail into a footnoted caveat on an otherwise-declared win contradicts the rule's own mechanical intent. source: https://www.optibase.io/glossary/guardrail-metric

7. When a new experiment or hypothesis reuses a product surface that a prior experiment already flagged a guardrail risk on, carry that guardrail forward into the new registration by default rather than re-deriving the guardrail list from scratch — dropping a previously-relevant guardrail without a stated reason risks silently losing protection the earlier experiment established was necessary.

8. When guardrail status must be evaluated but the guardrail's measurement pipeline was not actually running during the test window, report the guardrail as unmeasured (not as "passed") and treat the overall result as inconclusive on that axis — a guardrail that was never observed cannot be said to have stayed inside its safe range, and defaulting an unmeasured guardrail to "pass" silently converts an instrumentation gap into a false trust signal.

9. **REMOVAL**: When a hypothesis package lists a guardrail metric with no numeric degradation threshold attached, strip it from the guardrail list and route it back to registration rather than counting it as satisfying the "guardrails named and non-empty" requirement — a bare metric name with no bound cannot mechanically trip, so it provides the appearance of a guardrail without the enforceable content of one (mirrors hypothesis-preregistration.md rule 5, scoped here to the naming step itself).

10. **REMOVAL**: When a guardrail metric has shown zero adversarial movement across several consecutive completed experiments on the same surface and the team can state a specific reason it is no longer at risk, remove it from the default guardrail list for future experiments on that surface (recording the removal and its reason) rather than carrying an inert guardrail forward indefinitely — an unexamined, never-tripping guardrail that nobody can justify still being tracked adds review overhead without adding protection, and the removal decision itself must be recorded, not silently dropped.
