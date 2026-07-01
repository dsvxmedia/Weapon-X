# Worked example: a budget cap that could be bypassed for free

This is a curated write-up of a bug found in this project by testing it against itself,
kept as a public example because it's a specific, checkable claim rather than a general
one: most agent loops with retry caps have this exact bug, and it's easy to miss because
it only shows up on the second run, not the first.

## The bug

`weaponx`'s original design capped every task at 4 generate-verify cycles before stopping
and reporting `hit-retry-cap` — a circuit breaker meant to stop a stuck task from spinning
forever. The cap was implemented as a per-invocation counter.

That's the bug. A per-invocation counter resets to zero every time you run the command
again. So a task that failed 4 times, hit the cap, and got reported as stuck could simply
be re-run, and the loop would grant it 4 more free cycles, with no memory that this was
already tried and already failed. Run it a third time, get 4 more. The "hard cap" was not
hard. It was a suggestion that reset itself on request.

## How it was found

Not by reading the code again. By building a fixture specifically designed to fail every
single time — two tests asserting contradictory outcomes for the same function call, so
no possible implementation could pass both — and then actually running the loop against
it twice, with the cap deliberately set to 1 cycle to keep the test cheap.

First run: cycle 1, REJECT (correctly, since the task is unsatisfiable by design), cap
hit, `hit-retry-cap` reported. Second run, same task, same cap: this is the actual test.
Before the fix, this would silently reset to a fresh cycle. After the fix, the loop found
the prior trace, carried the cycle count forward, saw it already met the cap, and stopped
immediately with zero new work dispatched, telling the human the cap needed an explicit
raise rather than granting one automatically.

## Why this matters more than it sounds like it should

A budget cap that can be bypassed by re-running the command isn't a rare implementation
slip. It's close to the default outcome of building a retry cap without specifically
asking "what happens if someone just runs this again." Most cap implementations checked
during this project's own research either didn't specify this behavior at all, or
specified it in a way that implicitly assumed one continuous session, not a cap meant to
survive across separate invocations, days apart, possibly by a different person.

The fix: track the cap cumulatively per task, not per invocation. Simple once named. Easy
to never think to name.

## The general lesson

Any hard cap in an agentic system needs an explicit answer to "what happens on retry,"
not an implicit one. If the answer is "it resets," it isn't a cap. This is the kind of
finding that a fixture built to fail reliably can catch cheaply, in a few real tool calls,
instead of being discovered later, in production, by someone with a stuck task and an
unexpectedly large bill.
