### Deciding what to build

**The human owns this phase. You own the facts.** Every product or preference call goes to the user with your recommended answer attached. Every question the codebase or a quick run can answer is yours, and you answer it before asking.

This is the one playbook that asks instead of proceeding. It ends at agreed tickets, and building them is the Feature or Bug fix playbook's job.

1. If the repo has no `docs/agents/issue-tracker.md`, run the **setup-matt-pocock-skills** skill first, so the spec and tickets land in the tracker. Take the tracker it proposes for this repo's remote (GitHub issues for a GitHub remote, GitLab for GitLab, local markdown with none) unless the user names another.
2. Work bigger than one session goes to the **wayfinder** skill instead. Return to step 3 for each part of its map that resolves into something buildable.
3. Run the **grill-with-docs** skill. It grills over the design tree, one round at a time, and records resolved terms and hard-to-reverse decisions with the **domain-modeling** skill in `GLOSSARY.md` and ADRs. Grilling's confirmation is the gate to step 4.
4. Run the **to-spec** skill. Agree the seams under test in its step 2, and keep them in the spec's Testing Decisions.
5. Run the **to-tickets** skill. Each ticket carries its seams under test and its acceptance criteria, and the user approves the breakdown.
6. Stop. Build only when the user asks. Each ticket is then built by the Feature or Bug fix playbook in blocking order, autonomously.

**Reply:** the spec and ticket links, the seams agreed, the terms and ADRs recorded, and anything the user left open.
