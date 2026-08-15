---
axis: opportunity-solution-tree-branching
rule_count_floor: 10
---

# Opportunity-solution-tree branching and pruning

Research trail: Teresa Torres's continuous-discovery Opportunity Solution Tree (OST) method, fetched this session via Product School, ProductPlan glossary, Chameleon's interview with Torres, and Shortform's summary of *Continuous Discovery Habits*; the four-layer structure (outcome, opportunity, solutions, assumption tests) and Torres's explicit pruning/prioritization guidance.

## Rules

1. When placing a current-state finding on the tree, classify it into exactly one of the four named layers — outcome, opportunity, solution, or assumption test — and state that layer explicitly in the record, rather than describing it in free prose; the tree's structure is defined by "a desired outcome at the top, opportunities... in the middle, solutions... below those, and experiments (assumption tests) at the bottom," so an entry with no named layer cannot be placed or later pruned correctly. source: https://www.productplan.com/glossary/opportunity-solution-tree

2. When a new customer need or pain point surfaces, add it as an opportunity node under the relevant outcome, not directly as a solution — Torres's structure requires opportunities to sit between outcome and solution so that multiple solutions can later be generated for the same validated need, instead of a single feature idea silently standing in for the underlying need. source: https://www.chameleon.io/blog/opportunity-solution-tree

3. When comparing candidate solutions for build priority, do not prioritize solutions directly — first assess and prioritize the opportunity space, then generate solutions only for the target opportunity; Torres explicitly does not recommend prioritizing solutions because "teams end up comparing apples to oranges" across unrelated opportunities. source: https://www.chameleon.io/blog/opportunity-solution-tree

4. When generating candidate solutions for a chosen opportunity, generate as many ideas as reasonably possible for that one opportunity before selecting, rather than stopping at the first plausible idea — Torres's method is to "start with generating as many ideas as you can for that target opportunity" precisely because a narrow solution set biased toward the first idea under-explores the opportunity. source: https://www.chameleon.io/blog/opportunity-solution-tree

5. When a solution node carries residual uncertainty about whether it will actually work, attach an assumption-test (experiment) node beneath it before committing engineering effort, rather than treating the solution as validated on its own; the fourth layer of the tree exists specifically to test the riskiest assumptions a solution depends on before build. source: https://www.productplan.com/glossary/opportunity-solution-tree

6. When the tree accumulates more than roughly 3-4 active opportunities or 8-10 total candidate solutions under the current outcome, prune inactive or lower-value branches rather than retaining an exhaustive taxonomy — Torres's own sizing guidance is that "a tree with 3-4 opportunities and 8-10 total solutions is more useful than an exhaustive taxonomy," so a tree that has grown past this without pruning has stopped functioning as a focus tool. source: https://getperspective.ai/blog/opportunity-solution-tree-2026-practical-guide-continuous-discovery

7. When an assumption test invalidates a solution, prune that solution branch from the active tree (mark it pruned, keep it in history) rather than deleting the opportunity above it — a failed solution test says the solution didn't work, not that the opportunity is invalid; killing the opportunity along with the solution discards a possibly-still-valid customer need. source: https://roadmap.one/blog/posts/blog9-9-opportunity-solution-tree/

8. When an opportunity has had every generated solution tested and invalidated with no new candidate solutions surfacing, prune the opportunity branch itself and record why — an opportunity that keeps failing every proposed solution is a signal the opportunity was mis-scoped or is not actually reachable under current constraints, and keeping it live without resolution silently stalls the tree. source: https://www.ideaplan.io/guides/opportunity-solution-tree-guide

9. **REMOVAL**: When a tree entry names a specific opportunity but its parent outcome is unnamed or ambiguous, remove the opportunity from the active tree until an outcome is assigned — the top layer sets scope for everything below it, so an unanchored opportunity cannot be legitimately prioritized against opportunities that do have a named outcome. source: https://www.productplan.com/glossary/opportunity-solution-tree

10. **REMOVAL**: When a solution branch has sat with no assumption test run and no build activity for a full discovery cycle, prune it from the active tree rather than letting it persist as a stale placeholder — the tree is meant to "represent your current focus, not every possible path," so idle solution branches with no test in flight should be cut, not carried forward indefinitely. source: https://getperspective.ai/blog/opportunity-solution-tree-2026-practical-guide-continuous-discovery

11. When more than one candidate solution sits under the same opportunity and only one assumption test can run next, pick the test by learning value per unit of experiment cost — which test would most cheaply invalidate or confirm the riskiest shared assumption across the sibling solutions — rather than by which solution looks biggest or most polished; ranking solutions by apparent size instead of by what the next experiment would actually teach collapses back into exactly the "comparing apples to oranges" mistake rule 3 already rules out for whole opportunities, one layer down at the solution/test pair.
