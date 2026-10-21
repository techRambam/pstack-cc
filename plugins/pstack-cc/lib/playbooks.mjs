import fs from 'node:fs';
import path from 'node:path';
import { REVIEW_STEPS } from './receipts.mjs';

/** Bumped when an export of this file changes shape. receipts.mjs carries its own. The playbook gate in
 *  ~/.claude compares both with the numbers it was written for and, on a mismatch, allows the call and
 *  says the gate is off. */
export const EXPORTS_VERSION = 1;

/**
 * @typedef {'critical' | 'commit' | 'merge'} Tag
 * @typedef {'pending' | 'active' | 'done' | 'skipped'} StepStatus
 * @typedef {{ text: string, status: StepStatus, reason?: string, steps?: readonly PlanStep[] }} PlanStep
 * @typedef {import('./receipts.mjs').ReviewStepId} ReviewStepId
 *
 * @typedef {object} PlaybookStep
 * @property {number} n                    1-based, as written
 * @property {string} head                 shortest matching prefix, normalized, for messages
 * @property {readonly string[]} prefixes  normalized prefixes a plan step may equal, shortest first
 * @property {ReadonlySet<Tag>} tags
 * @property {boolean} opensPr             holds the sentence "Run Opening a PR"
 * @property {string} display              shortest matching prefix as written, tags and markdown kept
 * @property {readonly string[]} substeps  the step's own `- ` bullets, as written
 *
 * @typedef {object} Playbook
 * @property {string} slug     file name without .md
 * @property {string} title    the `### ` heading
 * @property {string} file     absolute path
 * @property {readonly PlaybookStep[]} steps
 * @property {number} commitAt        index of the [commit] step, else pushAt, else the last step
 * @property {number | null} pushAt   index of the step that opens a PR
 * @property {number} mergeAt         index of the [merge] step, else pushAt, else the last step
 * @property {boolean} writes         has a [commit] tag or opens a PR
 *
 * @typedef {(
 *   | { ok: true, playbook: Playbook, rows: readonly PlanStep[], reviewSkips: ReadonlyMap<ReviewStepId, string> }
 *   | { ok: false, why: 'no-plan' }
 *   | { ok: false, why: 'no-playbook', first: string }
 *   | { ok: false, why: 'missing-step', playbook: Playbook, step: PlaybookStep, after: string | null }
 * )} PlanMatch
 */

const TAGS_RE = /^(?:\[(?:critical|commit|merge)\]\s+)+/;
const STEP_RE = /^(\d+)\.\s+(.*)$/;
const BULLET_RE = /^(\s+)[-*]\s+(.*)$/;
const FENCE_RE = /^\s*(```|~~~)/;
const OPENS_PR = 'Run Opening a PR';
const MIN_WORDS = 5;
const SKIP_SUFFIX_RE = /\s*[-–—(\[,;]*\s*\bskip(?:ped)?:\s*(.*?)\s*[)\]]?\s*$/i;

/**
 * Words stay exact. Formatting goes, meaning gate tags, `**`, `__`, backticks, curly quotes and runs
 * of whitespace. Applied to playbook text and plan text alike.
 * @param {string} text
 */
export function normalizeStepText(text) {
  return text.trim().replace(TAGS_RE, '')
    .replace(/\*\*|__|`/g, '')
    .replace(/[‘’]/g, "'").replace(/[“”]/g, '"')
    .replace(/\s+/g, ' ').trim();
}

const wordCount = (s) => (s ? s.split(' ').length : 0);

const SENTENCE_TERMINATOR = /[.!?]/;
const CLOSERS_AFTER_TERMINATOR = /(?:\*\*|__|`|\)|"|'|”|’)*/;
const NEXT_SENTENCE_OPENER = /(?=\s+[A-Z0-9"'(\[`*_“‘])/;
const SENTENCE_BOUNDARY_RE = new RegExp(
  SENTENCE_TERMINATOR.source + CLOSERS_AFTER_TERMINATOR.source + NEXT_SENTENCE_OPENER.source, 'g');

function rawPrefixes(raw) {
  const out = [...raw.matchAll(SENTENCE_BOUNDARY_RE)].map((m) => raw.slice(0, m.index + m[0].length));
  out.push(raw);
  return out;
}

function parsePlaybook(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const slug = path.basename(file, '.md');
  const title = (lines.find((l) => l.startsWith('### ')) ?? `### ${slug}`).slice(4).trim();
  const raw = [];
  let inFence = false;
  let cur = null;
  let ended = false;
  for (const line of lines) {
    if (FENCE_RE.test(line)) { inFence = !inFence; continue; }
    if (inFence) continue;
    const m = STEP_RE.exec(line);
    if (m) {
      const n = Number(m[1]);
      if (ended || n !== raw.length + 1) {
        throw new Error(`${file}: step "${line.slice(0, 40)}" breaks the numbering 1..${raw.length}. `
          + 'A playbook holds one column-0 numbered list.');
      }
      cur = { n, text: m[2], substeps: [], bulletIndent: null };
      raw.push(cur);
      continue;
    }
    if (!cur) continue;
    const b = BULLET_RE.exec(line);
    if (b && (cur.bulletIndent === null || b[1].length === cur.bulletIndent)) {
      cur.bulletIndent = b[1].length;
      cur.substeps.push(b[2].trim());
    } else if (line.trim() && !/^\s/.test(line)) {
      ended = true;
      cur = null;
    }
  }

  const steps = raw.map(({ n, text, substeps }) => {
    const tagText = TAGS_RE.exec(text.trim())?.[0] ?? '';
    const tags = new Set([...tagText.matchAll(/\[(critical|commit|merge)\]/g)].map((t) => t[1]));
    const all = rawPrefixes(text.trim());
    const usable = all.filter((p, i) => i === all.length - 1 || wordCount(normalizeStepText(p)) >= MIN_WORDS);
    const prefixes = [...new Set(usable.map(normalizeStepText))];
    return {
      n, head: prefixes[0], prefixes, tags,
      opensPr: normalizeStepText(text).includes(OPENS_PR),
      display: usable[0], substeps,
    };
  });
  if (!steps.length) return null;
  const idx = (pred) => { const i = steps.findIndex(pred); return i < 0 ? null : i; };
  const pushAt = idx((s) => s.opensPr);
  const commitTag = idx((s) => s.tags.has('commit'));
  const mergeTag = idx((s) => s.tags.has('merge'));
  const last = steps.length - 1;
  return {
    slug, title, file, steps, pushAt,
    commitAt: commitTag ?? pushAt ?? last,
    mergeAt: mergeTag ?? pushAt ?? last,
    writes: commitTag !== null || pushAt !== null,
  };
}

/**
 * Every playbook with numbered steps, sorted by slug. opening-a-pr.md has none and is left out.
 * Throws when a playbook's numbering breaks, since its steps cannot be read reliably.
 * @param {string} pluginRoot the pstack-cc plugin directory (installed_plugins.json installPath)
 * @returns {Playbook[]}
 */
export function loadPlaybooks(pluginRoot) {
  const dir = path.join(pluginRoot, 'skills', 'poteto-mode', 'playbooks');
  return fs.readdirSync(dir).filter((f) => f.endsWith('.md')).sort()
    .map((f) => parsePlaybook(path.join(dir, f))).filter(Boolean);
}

/** @returns {{ text: string, reason: string } | null} the row text without its `skip: <reason>` tail, or null when it has none */
function splitSkipSuffix(text) {
  const m = SKIP_SUFFIX_RE.exec(text);
  return m ? { text: text.slice(0, m.index), reason: m[1] } : null;
}

function readRow(step) {
  const skip = splitSkipSuffix(step.text);
  if (!skip) return step;
  const status = step.status === 'done' ? 'skipped' : step.status;
  return { ...step, text: skip.text, status, reason: step.reason || skip.reason };
}

const namesStep = (text, step) => step.prefixes.includes(normalizeStepText(text));

function reviewIdOf(text) {
  const t = normalizeStepText(text);
  return REVIEW_STEPS.find((r) => t === r.skill || t.startsWith(`${r.skill} `))?.id ?? null;
}

/**
 * Maps a plan onto the playbook it follows. The first top-level plan step names step 1 of a
 * playbook. Each later playbook step is named by a later top-level plan step, in order. Plan steps
 * that name nothing are the task's own and may sit between them, since TodoWrite cannot nest.
 *
 * reviewSkips holds every skipped review row (its text starts with a REVIEW_STEPS skill) nested
 * under the Opening a PR row, or following it at top level before the next playbook row. It maps
 * the review to its reason, '' when none. An interrogate entry is a skipped critical step.
 * @param {readonly PlanStep[]} steps top-level plan steps
 * @param {readonly Playbook[]} playbooks
 * @returns {PlanMatch}
 */
export function matchPlan(steps, playbooks) {
  if (!steps.length) return { ok: false, why: 'no-plan' };
  const plan = steps.map(readRow);
  const candidates = playbooks.filter((p) => namesStep(plan[0].text, p.steps[0]));
  if (!candidates.length) return { ok: false, why: 'no-playbook', first: plan[0].text };

  let best = null;
  for (const pb of candidates) {
    const at = [0];
    for (let i = 1, j = 1; i < pb.steps.length; i++) {
      while (j < plan.length && !namesStep(plan[j].text, pb.steps[i])) j++;
      if (j === plan.length) break;
      at.push(j++);
    }
    if (at.length === pb.steps.length) {
      return { ok: true, playbook: pb, rows: at.map((j) => plan[j]), reviewSkips: reviewSkipsOf(pb, plan, at) };
    }
    if (!best || at.length > best.at.length) best = { pb, at };
  }
  const k = best.at.length;
  return { ok: false, why: 'missing-step', playbook: best.pb, step: best.pb.steps[k], after: plan[best.at[k - 1]].text };
}

function reviewSkipsOf(pb, plan, at) {
  /** @type {Map<ReviewStepId, string>} */
  const skips = new Map();
  if (pb.pushAt === null) return skips;
  const j = at[pb.pushAt];
  const end = pb.pushAt + 1 < at.length ? at[pb.pushAt + 1] : plan.length;
  for (const row of [...(plan[j].steps ?? []).map(readRow), ...plan.slice(j + 1, end)]) {
    const id = reviewIdOf(row.text);
    if (id && row.status === 'skipped') skips.set(id, (row.reason ?? '').trim());
  }
  return skips;
}

/** Why a skip reason does not count, or null when it does. A reason counts when it is three words
 *  or more and not a stock phrase. The playbook gate reminds once about a skipped plan row whose reason fails it. */
export function reasonProblem(reason) {
  const r = (reason ?? '').trim();
  if (!r) return 'a skipped step needs a reason';
  if (/^(?:n\/a|na|none|skip(?:ped)?|not (?:needed|necessary|applicable|relevant)|unnecessary|irrelevant)\.?$/i.test(r)) {
    return `"${r}" is a stock phrase, not a reason`;
  }
  if (r.split(/\s+/).length < 3) return `"${r}" is under three words`;
  return null;
}

/**
 * A playbook's steps as a plan to send to the plan tool, or with `todowrite` as TodoWrite input.
 * Each step reads as its shortest matching prefix. A step's bullets nest under it. The step that
 * opens a PR also gets the three review sub-steps, the plan's one place to record a review skip.
 * TodoWrite cannot nest, so there sub-steps follow their step as rows of their own.
 * @param {Playbook} pb
 * @param {{ todowrite?: boolean }} [o]
 */
export function planFor(pb, { todowrite = false } = {}) {
  const steps = pb.steps.map((s, i) => {
    const subs = [...s.substeps, ...(i === pb.pushAt ? REVIEW_STEPS.map((r) => r.planText) : [])];
    return {
      text: s.display,
      status: i === 0 ? 'active' : 'pending',
      ...(subs.length ? { steps: subs.map((text) => ({ text, status: 'pending' })) } : {}),
    };
  });
  if (!todowrite) return { title: pb.title, steps };
  const todos = steps.flatMap((s) => [s, ...(s.steps ?? [])]).map((s) => ({
    content: s.text, status: s.status === 'active' ? 'in_progress' : 'pending', activeForm: s.text,
  }));
  return { todos };
}

/** TodoWrite input read back as top-level plan steps. */
export function planStepsFromTodos(todos) {
  const status = { pending: 'pending', in_progress: 'active', completed: 'done' };
  return todos.map((t) => ({ text: t.content, status: status[t.status] ?? 'pending' }));
}
