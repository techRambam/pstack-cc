---
name: tdd
description: "Test-driven development for new behavior and for bug fixes. Use when the user asks for TDD, test-first, red-green, a failing test or a regression test; when a ticket or spec names the seams to test; or when a bug has an obvious cheap local test target. Skip when the test path is unclear, expensive or not requested."
---

# Test-Driven Development

TDD is the red to green loop. This skill covers two jobs that share one loop. Building new behavior test-first, one vertical slice at a time. Locking down a bug with a regression test that fails before the fix and passes after it.

When exploring the codebase, read `GLOSSARY.md` (if it exists) so test names and interface vocabulary match the project's domain language, and respect ADRs in the area you're touching.

## What a good test is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely and the tests shouldn't. A good test reads like a specification. "user can checkout with valid cart" says exactly what capability exists, and it survives refactors because it doesn't care about internal structure.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines. The **test-behavior-not-implementation** principle skill is the stricter check: a test that would still pass when every imported function returns `undefined` gets rewritten or deleted.

## Seams: where tests go

A **seam** is the public boundary you test at, the interface where you observe behavior without reaching inside. Tests live at seams, never against internals. You can't test everything, so choosing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

Where the seams come from depends on the phase.

- **Deciding what to build.** Agree the seams with the user while grilling, and record them in the spec or ticket (the **to-spec** and **to-tickets** skills).
- **Building from a spec or ticket.** Take the seams it names. If it names none, choose them yourself, write them down before the first test, and report them with the result. Do not stop to ask.

When the shape of the interface is itself in question (how deep the module is, where the seam belongs, what the interface should expose), call the Skill tool with "codebase-design" for the vocabulary. It is a reference to consult, not a session to run.

## Anti-patterns

- **Implementation-coupled.** Mocks internal collaborators, tests private methods, or verifies through a side channel (querying the database instead of using the interface). The tell is a test that breaks on a refactor while behavior hasn't changed.
- **Tautological.** The assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a snapshot derived by hand the same way, a constant asserted equal to itself), so it passes by construction. Expected values come from an independent source of truth, a known-good literal, a worked example, or the spec.
- **Horizontal slicing.** Writing all tests first, then all implementation. Bulk tests verify imagined behavior and commit to test structure before you understand the implementation. Work in **vertical slices** instead. One test, one implementation, repeat, each test a **tracer bullet** that responds to what the last cycle taught you.

## Building new behavior

- **Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the loop.** It belongs to review and to the Refactoring playbook of the **poteto-mode** skill, not to the red to green cycle.

## Fixing a bug

1. **Understand the bug.** Identify the intended behavior, current behavior, affected path, and smallest observable reproduction. For a hard bug, build the feedback loop first with the **diagnosing-bugs** skill.
2. **Choose the narrowest executable check.** Prefer the closest unit, component, integration or regression test already used for that codepath. If no practical test path is obvious, do not create one from scratch just to satisfy the workflow.
3. **Write the failing test first.** Add the smallest focused test that would have caught the bug. It encodes intended behavior, not the current implementation.
4. **Run it before fixing.** Confirm it fails for the intended reason. If it passes or fails for an unrelated reason, correct the test or reproduction before editing the implementation.
5. **Fix the bug.** Make the smallest production change that satisfies the intended behavior while preserving nearby contracts.
6. **Rerun the regression test.** Confirm it now passes.

## When a test is impractical

Do not force a test when the available one would need broad harness setup, brittle mocks, slow end-to-end infrastructure, production-only state, vague reproduction steps, or large unrelated fixture churn. Use the closest executable check instead: a targeted script, a reproduction command, browser automation, a snapshot comparison, a log assertion, or a focused integration check.

Prefer no new test over a bad test. A bad test mostly tests mocks, encodes implementation details, depends on timing or unrelated global state, needs expensive infrastructure for a small change, or would be deleted right after proving the change.

## Guardrails

- Do not change tests merely to match a wrong implementation.
- Do not weaken existing assertions unless the expected behavior has genuinely changed and the reason is clear.
- Keep a regression test focused on its bug. Avoid broad fixture churn or unrelated coverage expansion.
- If the bug is flaky, make the test deterministic where possible and say which signal it locks down.
- If the bug exposes a broader class of failures, land the focused regression path first, then consider sibling coverage.

## Final response

Report the evidence, not just the outcome.

- The seams you tested, and where they came from (the spec, the ticket, or your own choice).
- The failing-before test or executable check, and the failure it produced.
- The passing-after run and any nearby validation.
- If failing-before evidence could not be shown, why, and the closest check used instead.
