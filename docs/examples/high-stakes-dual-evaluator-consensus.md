# Worked example: dual-evaluator consensus on a high-stakes task

This is a curated write-up of one real `/weaponx` run, kept as a public example because it
demonstrates the thing this project is actually built around — a generator/evaluator split
where the two evaluators genuinely add independent value, not just redundant agreement.
The raw branch this came from (`weaponx/high-stakes-discount-fix`) has been deleted; this
write-up, and the full technical trace it's drawn from, are the permanent record.

## The task

A small, deliberately broken pricing function:

```python
def apply_discount(price, percent_off):
    """Apply a percentage discount to a price."""
    return price - percent_off
```

`apply_discount(80, 25)` should return `60` (25% off $80). It returned `55`, because the
function was subtracting `percent_off` as a flat number instead of a percentage. The task
was flagged **high-stakes** — explicitly, by the human, because it touches pricing logic.

## What happened

**Generation** produced the correct one-line fix — `price - (price * percent_off / 100)` —
and proactively flagged something it didn't fix: the result is now a `float`, which matters
for money, but fixing that wasn't in scope for "make the tests pass." Good behavior:
surfacing a concern instead of silently deciding it either way.

**Verification dispatched two evaluators in parallel**, structurally unable to see each
other's output:

- **Evaluator A** (correctness-framed): ran the tests, confirmed the formula is
  mathematically correct, confirmed the diff was minimal. **PASS**, every claim `verified`.
- **Evaluator B** (risk-framed — "what's the worst way this is wrong even if it passes?"):
  also reached **PASS**, but for a different reason than "the tests pass." It flagged real
  gaps the task itself never asked about: no bounds check on `percent_off > 100` (silently
  produces a negative price), no check on negative `percent_off` (silently produces a
  markup instead of a discount), float arithmetic on money as a latent rounding-drift risk,
  and a test suite too thin (3 cases) for something framed as high-stakes.

Both reached the same verdict. **That agreement is the less interesting result.** The
valuable outcome is that evaluator B produced information evaluator A's framing could not
have produced, even in agreement — which is the actual argument for running two evaluators
with different lenses instead of one, or two evaluators asking the same question twice.

## Cost

Consensus roughly doubled verification cost versus a single evaluator for this run (~32k
tokens across both evaluators vs. ~15k for a comparable single-evaluator PASS elsewhere in
this project's history). That's real and worth knowing before flagging something
high-stakes reflexively — the mechanism isn't free, and it shouldn't be treated as free.

## Why this one, specifically, survived cleanup

Two other pressure-test fixtures from the same testing pass were deleted without a
write-up, because they only demonstrated "the loop finds and fixes a bug" — a
single-evaluator PASS, already shown once. This run demonstrated something structurally
different (independent value under agreement, not just under disagreement), which is
rarer and more worth preserving in a form someone evaluating this project would actually
read.
