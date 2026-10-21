import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/** @typedef {'unslop' | 'no-comments' | 'interrogate'} ReviewStepId */
/** @typedef {{ id: ReviewStepId, skill: string, planText: string, critical: boolean }} ReviewStep */

/** @type {readonly ReviewStep[]} */
export const REVIEW_STEPS = Object.freeze([
  { id: 'unslop', skill: '/pstack-cc:unslop', planText: '/pstack-cc:unslop over the diff', critical: false },
  { id: 'no-comments', skill: '/no-comments', planText: '/no-comments', critical: false },
  { id: 'interrogate', skill: 'interrogate', planText: 'interrogate on the PR diff', critical: true },
]);
const REVIEW_IDS = new Set(REVIEW_STEPS.map((s) => s.id));
export const VERDICTS = Object.freeze(['PASS', 'PASS+NOTES', 'FAIL']);

/**
 * @typedef {string} Tree  a 40-hex git tree id
 * @typedef {{ model: string, delivered: true } | { model: string, delivered: false, reason: string }} Seat
 * @typedef {(
 *   | { step: 'unslop' }
 *   | { step: 'no-comments', summary: string, deletions: number | null }
 *   | { step: 'interrogate', seats: readonly Seat[], actOn: readonly string[] }
 * )} Evidence
 * @typedef {{ v: 1, branch: string, at: string, worktree: string, head: string }} Common
 * @typedef {Common & { kind: 'review', step: ReviewStepId, input: Tree, output: Tree, fixPaths: string[],
 *   evidence: { files: string[] } | { summary: string, deletions: number | null } | { seats: Seat[], actOn: string[] } }} ReviewReceipt
 * @typedef {Common & { kind: 'verdict', verdict: 'PASS' | 'PASS+NOTES' | 'FAIL', pr: number, by: string,
 *   ran: string, base: string, patchId: string }} VerdictReceipt
 * @typedef {ReviewReceipt | VerdictReceipt} Receipt
 *
 * @typedef {(
 *   | { kind: 'no-branch' }
 *   | { kind: 'missing', step: ReviewStepId }
 *   | { kind: 'out-of-order', earlier: ReviewStepId, later: ReviewStepId }
 *   | { kind: 'gap', from: ReviewStepId, to: ReviewStepId, paths: string[] }
 *   | { kind: 'tail', after: ReviewStepId, paths: string[], allowed: string[] }
 * )} ChainProblem
 * @typedef {{ ok: true } | { ok: false, problem: ChainProblem, rerun: ReviewStepId[] }} ChainState
 * @typedef {(
 *   | { ok: true, receipt: VerdictReceipt }
 *   | { ok: false, why: 'none' | 'no-base' }
 *   | { ok: false, why: 'stale', receipt: VerdictReceipt, patch: string }
 *   | { ok: false, why: 'fail', receipt: VerdictReceipt }
 * )} VerdictState
 * @typedef {{ tree: Tree, head: string, base: string | null, branch: string | null, receipts: Receipt[],
 *   chain: ChainState, verdict: VerdictState }} ReceiptState
 */

/** A refusal whose message is the fix. The CLI prints it and exits 2. */
export class ReceiptRefused extends Error {}
const refuse = (msg) => { throw new ReceiptRefused(msg); };


function git(cwd, args, { input, env } = {}) {
  return execFileSync('git', args, {
    cwd, input, encoding: 'utf8', maxBuffer: 1 << 30,
    env: env ? { ...process.env, ...env } : process.env,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}
const gitLine = (cwd, args) => git(cwd, args).trim();
function gitMaybe(cwd, args) {
  try { return gitLine(cwd, args); } catch { return null; }
}

function repoAt(cwd) {
  const top = gitMaybe(cwd, ['rev-parse', '--show-toplevel']);
  if (!top) refuse(`${cwd} is not inside a git work tree. Run this from the worktree under review.`);
  return {
    top,
    common: gitLine(top, ['rev-parse', '--path-format=absolute', '--git-common-dir']),
    branch: gitMaybe(top, ['symbolic-ref', '--quiet', '--short', 'HEAD']),
  };
}

function worktreeTree(repo) {
  const tmp = path.join(os.tmpdir(), `pstack-index-${process.pid}-${crypto.randomBytes(6).toString('hex')}`);
  try {
    const real = gitLine(repo.top, ['rev-parse', '--path-format=absolute', '--git-path', 'index']);
    if (fs.existsSync(real)) fs.copyFileSync(real, tmp);
    const env = { GIT_INDEX_FILE: tmp };
    git(repo.top, ['add', '-A'], { env });
    return git(repo.top, ['write-tree'], { env }).trim();
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

const treeOfRev = (repo, rev) => gitLine(repo.top, ['rev-parse', '--verify', `${rev}^{tree}`]);

function changedPaths(repo, a, b) {
  if (a === b) return [];
  return git(repo.top, ['diff-tree', '-r', '-z', '--name-only', '--no-renames', a, b])
    .split('\0').filter(Boolean);
}

function resolveBase(repo, branch, explicit) {
  const name = explicit
    ?? (branch && gitMaybe(repo.top, ['config', '--get', `branch.${branch}.pstackBase`]))
    ?? gitMaybe(repo.top, ['symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD'])
    ?? 'main';
  for (const ref of [`refs/remotes/origin/${name}`, name]) {
    if (gitMaybe(repo.top, ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`])) return { name, ref };
  }
  return null;
}

/** `git patch-id --stable` ignores whitespace-only changes. */
function patchIdOf(repo, baseRef, rev) {
  const mb = gitLine(repo.top, ['merge-base', baseRef, rev]);
  const diff = git(repo.top, ['diff', '--binary', mb, rev]);
  if (!diff) return 'empty';
  const out = git(repo.top, ['patch-id', '--verbatim'], { input: diff }).trim();
  return out ? out.split(/\s+/)[0] : 'empty';
}


const encodeBranch = (b) => b.replace(/%/g, '%25').replace(/\//g, '%2F');
const branchDir = (repo, branch) => path.join(repo.common, 'pstack-receipts', encodeBranch(branch));
const sha1 = (s) => crypto.createHash('sha1').update(s).digest('hex');
const openFile = (repo, branch, step) =>
  path.join(branchDir(repo, branch), 'open', `${step}.${sha1(repo.top).slice(0, 12)}.json`);

function writeAtomic(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = path.join(path.dirname(file), `.tmp-${process.pid}-${crypto.randomBytes(6).toString('hex')}`);
  fs.writeFileSync(tmp, content);
  fs.renameSync(tmp, file);
}

/** A repeated review collapses into one file. A repeated verdict does not, because the newest
 *  verdict decides, so PASS, FAIL, PASS must leave three files. */
function writeReceipt(repo, r) {
  const { at, ...rest } = r;
  const name = r.kind === 'verdict'
    ? `verdict.${sha1(JSON.stringify(r)).slice(0, 12)}.json`
    : `${r.step}.${sha1(JSON.stringify(rest)).slice(0, 12)}.json`;
  const file = path.join(branchDir(repo, r.branch), name);
  if (!fs.existsSync(file)) writeAtomic(file, `${JSON.stringify(r, null, 1)}\n`);
  return file;
}

const isReceipt = (r) => r && r.v === 1 && typeof r.at === 'string'
  && ((r.kind === 'review' && REVIEW_IDS.has(r.step) && typeof r.input === 'string' && typeof r.output === 'string'
    && Array.isArray(r.fixPaths))
    || (r.kind === 'verdict' && VERDICTS.includes(r.verdict) && typeof r.patchId === 'string'));

/** @returns {Receipt | null} null for a file that is unreadable, not JSON, or not a receipt */
function parseReceiptFile(file) {
  try {
    const r = JSON.parse(fs.readFileSync(file, 'utf8'));
    return isReceipt(r) ? r : null;
  } catch {
    return null;
  }
}

/** @returns {Receipt[]} */
function readLedger(repo, branch) {
  const dir = branchDir(repo, branch);
  let names;
  try { names = fs.readdirSync(dir); } catch { return []; }
  const out = names.filter((n) => n.endsWith('.json')).sort()
    .map((name) => parseReceiptFile(path.join(dir, name))).filter((r) => r !== null);
  return out.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0));
}

const latest = (rs) => rs.reduce((a, b) => (a && a.at > b.at ? a : b), null);

function relPath(repo, p) {
  const abs = path.resolve(repo.top, p);
  const rel = path.relative(repo.top, abs).split(path.sep).join('/');
  if (!rel || rel.startsWith('..')) refuse(`--act-on ${p} is outside the worktree ${repo.top}. Name files inside it.`);
  return rel;
}

function requireBranch(repo) {
  if (!repo.branch) refuse('HEAD is detached. Check out the branch under review, then run this again.');
  return repo.branch;
}

function requireStep(step) {
  if (!REVIEW_IDS.has(step)) refuse(`unknown review step "${step}". Use one of: ${[...REVIEW_IDS].join(', ')}.`);
}


/**
 * Records the tree a review starts from, per worktree. Running it again replaces the record.
 * @param {ReviewStepId} step
 * @param {{ cwd: string, base?: string }} o
 * @returns {{ step: ReviewStepId, branch: string, input: Tree }}
 */
export function begin(step, { cwd, base }) {
  requireStep(step);
  const repo = repoAt(cwd);
  const branch = requireBranch(repo);
  if (base) {
    if (!resolveBase(repo, branch, base)) refuse(`--base ${base} names no commit here. Fetch it or name an existing branch.`);
    git(repo.top, ['config', `branch.${branch}.pstackBase`, base]);
  }
  const input = worktreeTree(repo);
  const head = gitMaybe(repo.top, ['rev-parse', 'HEAD']) ?? '';
  writeAtomic(openFile(repo, branch, step),
    `${JSON.stringify({ v: 1, step, input, at: new Date().toISOString(), worktree: repo.top, head })}\n`);
  return { step, branch, input };
}

/**
 * Records a finished review. Refuses a finish with no begin, an interrogate run during which the
 * tree moved, and an interrogate run in which no seat delivered.
 * @param {Evidence} evidence
 * @param {{ cwd: string }} o
 * @returns {ReviewReceipt}
 */
export function finish(evidence, { cwd }) {
  const { step } = evidence;
  requireStep(step);
  const repo = repoAt(cwd);
  const branch = requireBranch(repo);
  const file = openFile(repo, branch, step);
  let open;
  try { open = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {
    refuse(`no begin for ${step} in this worktree on ${branch}, so the review window is unknown. `
      + `Run \`pstack-receipt begin ${step}\`, run the review again, then finish.`);
  }
  const output = worktreeTree(repo);
  let fixPaths = [];
  let recorded;
  if (evidence.step === 'interrogate') {
    if (output !== open.input) {
      refuse(`the tree changed during the interrogate run (${changedPaths(repo, open.input, output).join(', ')}), `
        + 'so the reviewers saw another diff. Run `pstack-receipt begin interrogate` and review again, '
        + 'and fix findings only after `finish`.');
    }
    if (!evidence.seats.some((s) => s.delivered)) {
      refuse('no seat delivered, and a run in which no reviewer delivered is not a review. Rerun the panel.');
    }
    fixPaths = [...new Set(evidence.actOn.map((p) => relPath(repo, p)))].sort();
    recorded = { seats: [...evidence.seats], actOn: fixPaths };
  } else if (evidence.step === 'no-comments') {
    recorded = { summary: evidence.summary, deletions: evidence.deletions };
  } else {
    recorded = { files: changedPaths(repo, open.input, output) };
  }
  /** @type {ReviewReceipt} */
  const r = {
    v: 1, kind: 'review', step, branch, at: new Date().toISOString(), worktree: repo.top,
    head: gitMaybe(repo.top, ['rev-parse', 'HEAD']) ?? '', input: open.input, output, fixPaths, evidence: recorded,
  };
  writeReceipt(repo, r);
  fs.rmSync(file, { force: true });
  return r;
}

function ghPrView(pr, cwd) {
  let raw;
  try {
    raw = execFileSync('gh', ['pr', 'view', String(pr), '--json', 'number,headRefName,headRefOid,baseRefName'],
      { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    refuse(`\`gh pr view ${pr}\` failed (${String(e.stderr || e.message).trim()}). Check the PR number and gh auth.`);
  }
  const v = JSON.parse(raw);
  if (!v.headRefName || !v.headRefOid || !v.baseRefName) refuse(`gh returned no head or base for PR #${pr}.`);
  return v;
}

/**
 * Records a Shipping verdict for the PR head this worktree stands on. Refuses on the PR's own
 * branch and off the PR's head. Independence beyond that is the `by` attestation.
 * @param {{ verdict: string, pr: number, by: string, ran: string }} v
 * @param {{ cwd: string }} o
 * @returns {VerdictReceipt}
 */
export function recordVerdict({ verdict, pr, by, ran }, { cwd }) {
  if (!VERDICTS.includes(verdict)) refuse(`verdict must be one of ${VERDICTS.join(', ')}, not "${verdict}".`);
  const repo = repoAt(cwd);
  const info = ghPrView(pr, repo.top);
  if (repo.branch === info.headRefName) {
    refuse(`this checkout is on ${info.headRefName}, the PR's own branch. A verifier runs from its own worktree: `
      + `\`git worktree add --detach <dir> ${info.headRefOid}\`, verify there, and record the verdict there.`);
  }
  const head = gitLine(repo.top, ['rev-parse', 'HEAD']);
  if (head !== info.headRefOid) {
    refuse(`HEAD is ${head.slice(0, 12)} but PR #${pr}'s head is ${info.headRefOid.slice(0, 12)}. `
      + `Fetch and check out ${info.headRefOid} detached, verify that code, then record the verdict.`);
  }
  const base = resolveBase(repo, info.headRefName, info.baseRefName);
  if (!base) refuse(`the PR's base ${info.baseRefName} names no commit here. Fetch it first.`);
  /** @type {VerdictReceipt} */
  const r = {
    v: 1, kind: 'verdict', branch: info.headRefName, at: new Date().toISOString(), worktree: repo.top, head,
    verdict, pr: Number(info.number ?? pr), by, ran, base: info.baseRefName, patchId: patchIdOf(repo, base.ref, head),
  };
  writeReceipt(repo, r);
  return r;
}


/** @returns {ChainState} */
function judgeChain(repo, receipts, tree, skipped) {
  const order = REVIEW_STEPS.filter((s) => s.critical || !skipped.has(s.id)).map((s) => s.id);
  const reviews = receipts.filter((r) => r.kind === 'review');
  const latestOf = new Map(order.map((id) => [id, latest(reviews.filter((r) => r.step === id))]));
  const tailOf = (r) => changedPaths(repo, r.output, tree).filter((p) => !r.fixPaths.includes(p));

  /** @type {ChainProblem | null} */
  let problem = null;
  let linked = 0;
  for (const id of order) {
    const r = latestOf.get(id);
    const prev = linked ? latestOf.get(order[linked - 1]) : null;
    if (!r) { problem = { kind: 'missing', step: id }; break; }
    if (prev && r.at < prev.at) { problem = { kind: 'out-of-order', earlier: prev.step, later: id }; break; }
    if (prev && r.input !== prev.output) {
      problem = { kind: 'gap', from: prev.step, to: id, paths: changedPaths(repo, prev.output, r.input) };
      break;
    }
    linked++;
  }
  if (!problem) {
    const last = latestOf.get(order[order.length - 1]);
    const paths = tailOf(last);
    if (!paths.length) return { ok: true };
    problem = { kind: 'tail', after: last.step, paths, allowed: last.fixPaths };
  }
  const hasTail = (id) => tailOf(latestOf.get(id)).length > 0;
  return { ok: false, problem, rerun: order.slice(rerunFrom(order, linked, hasTail)) };
}

/**
 * Index in `order` where a rerun starts. A review before the break whose output still matches the
 * tree stays valid, so the rerun starts right after the nearest such review, else at the first.
 * @param {readonly ReviewStepId[]} order
 * @param {number} linked  how many reviews from the start link cleanly
 * @param {(id: ReviewStepId) => boolean} hasTail  true when edits follow that review's output
 */
function rerunFrom(order, linked, hasTail) {
  for (let p = Math.min(linked, order.length - 1); p > 0; p--) {
    if (!hasTail(order[p - 1])) return p;
  }
  return 0;
}

/** @returns {VerdictState} */
function judgeVerdict(repo, receipts, head, base) {
  const verdicts = receipts.filter((r) => r.kind === 'verdict');
  if (!verdicts.length) return { ok: false, why: 'none' };
  if (!base) return { ok: false, why: 'no-base' };
  const patch = patchIdOf(repo, base.ref, head);
  const current = latest(verdicts.filter((v) => v.patchId === patch));
  if (!current) return { ok: false, why: 'stale', receipt: latest(verdicts), patch };
  if (current.verdict === 'FAIL') return { ok: false, why: 'fail', receipt: current };
  return { ok: true, receipt: current };
}

/**
 * The one reader. `rev` judges a commit's tree (a push, a PR head) instead of the work tree.
 * `branch` defaults to the checked-out branch. `skipped` holds the reviews the plan skipped;
 * interrogate in it is ignored, because interrogate cannot be skipped.
 * @param {{ cwd: string, rev?: string, base?: string | null, branch?: string,
 *   skipped?: ReadonlySet<ReviewStepId> | Iterable<ReviewStepId> }} q
 * @returns {ReceiptState}
 */
export function receiptState({ cwd, rev, base, branch, skipped = [] }) {
  const repo = repoAt(cwd);
  const br = branch ?? repo.branch;
  const head = gitLine(repo.top, ['rev-parse', '--verify', `${rev ?? 'HEAD'}^{commit}`]);
  const tree = rev ? treeOfRev(repo, rev) : worktreeTree(repo);
  const baseInfo = resolveBase(repo, br, base ?? undefined);
  const receipts = br ? readLedger(repo, br) : [];
  const chain = br
    ? judgeChain(repo, receipts, tree, new Set(skipped))
    : { ok: false, problem: { kind: 'no-branch' }, rerun: REVIEW_STEPS.map((s) => s.id) };
  return {
    tree, head, base: baseInfo?.name ?? null, branch: br, receipts, chain,
    verdict: br ? judgeVerdict(repo, receipts, head, baseInfo) : { ok: false, why: 'none' },
  };
}

/** @param {ChainProblem} p */
export function describeProblem(p) {
  switch (p.kind) {
    case 'no-branch': return 'HEAD is detached, so there is no branch to read receipts for.';
    case 'missing': return `there is no ${p.step} receipt for this branch.`;
    case 'out-of-order': return `${p.later} ran before ${p.earlier}.`;
    case 'gap': return `edits between ${p.from} and ${p.to} touch ${p.paths.join(', ')}, which ${p.from} never saw.`;
    case 'tail': return `edits after ${p.after} touch ${p.paths.join(', ')}, but its Act on findings cite `
      + `${p.allowed.length ? p.allowed.join(', ') : 'no files'}.`;
  }
}
