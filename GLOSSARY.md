# pstack-cc

A Claude Code plugin regenerated from two outside skill packs, Lauren Tan's pstack and Matt Pocock's skills, rather than forked from them.

## Language

**Upstream**:
One of the two outside sources the plugin is built from: pstack (the `pstack/` folder of `cursor/plugins`) or Matt Pocock's skills.
_Avoid_: Source repo, parent, fork

**Pinned ref**:
The exact upstream commit the plugin is currently built from, one per upstream.
_Avoid_: Version, tag, current upstream

**Generator**:
The process that rebuilds the plugin from the pinned refs, together with its guards.
_Avoid_: Build script, importer

**Guard**:
A check inside the generator that fails the build when an upstream change would slip through the port silently.
_Avoid_: Test, lint

**Overlay**:
A whole-file replacement this port keeps for an upstream file that substitutions cannot port.
_Avoid_: Patch, override

**Relevant change**:
An upstream commit newer than the pinned ref that touches what the generator reads from that upstream.
_Avoid_: Upstream drift, new commit

**Sync**:
Moving the pinned refs forward and resolving every guard failure that the move causes.
_Avoid_: Update, upgrade, bump

**Trial import**:
A run of the generator against the newest upstream commits instead of the pinned refs, to learn what a sync would have to fix.
_Avoid_: Dry run, test sync

**Upstream watch**:
The scheduled check that looks for relevant changes, runs a trial import, and reports both.
_Avoid_: Drift check, update checker

**Watch issue**:
The single open issue where the upstream watch reports the current state, until a sync closes it.
_Avoid_: Sync ticket, drift issue
