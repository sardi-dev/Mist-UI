// Reads the client's taint.log. Every record starts with a time stamp and two
// spaces, and is followed by stack lines that carry four more spaces:
//
//   11/21 21:35:43.025  Global variable NAME tainted by MistUI - Interface\FrameXML\File.lua:105
//   11/21 21:35:43.025      BuffFrame_Update()
//   11/21 21:35:43.025      Interface\AddOns\MistUI\modules\file.lua:330 SetThing()
//   11/21 21:35:43.025  An action was blocked in combat because of taint from MistUI - Frame:SetPoint()
//   11/21 21:35:43.025  (an empty line ends a record)
//
// The summary keeps the two kinds of record that point at addon code: a blocked
// action and a global that the addon tainted.

const RECORD_LINE = /^(\d+\/\d+ \d+:\d+:\d+(?:\.\d+)?)  (.*)$/;
const STACK_INDENT = '    ';
const BLOCKED = /^An action was blocked in combat because of taint from (\S+)(?: - (.*))?$/;
const TAINTED_GLOBAL = /^Global variable (\S+) tainted by (\S+)(?: - .*)?$/;
const ADDON_FILE = /Interface\\AddOns\\(.+?\.lua:\d+)/i;

export const KIND_BLOCKED = 'blocked action';
export const KIND_TAINTED = 'tainted global';
export const UNKNOWN_LOCATION = '(no addon file in the stack)';

/**
 * @param {string} text contents of taint.log
 * @returns {{ time: string, kind: string, subject: string, addon: string, stack: string[] }[]}
 *   only the blocked-action and tainted-global records, in file order
 */
export function parseTaintLog(text) {
  const entries = [];
  let current = null;
  for (const line of text.split(/\r?\n/)) {
    const match = RECORD_LINE.exec(line);
    if (!match) continue;
    const [, time, rest] = match;
    if (rest.startsWith(STACK_INDENT)) {
      if (current) current.stack.push(rest.trim());
      continue;
    }
    current = null;
    const blocked = BLOCKED.exec(rest);
    const tainted = TAINTED_GLOBAL.exec(rest);
    if (blocked) {
      current = { time, kind: KIND_BLOCKED, subject: blocked[2] ?? '(unnamed action)', addon: blocked[1], stack: [] };
    } else if (tainted) {
      current = { time, kind: KIND_TAINTED, subject: tainted[1], addon: tainted[2], stack: [] };
    }
    if (current) entries.push(current);
  }
  return entries;
}

// The first (innermost) stack line inside one of the addon's own Lua files.
function addonLocation(stack, addonNames) {
  for (const line of stack) {
    const match = ADDON_FILE.exec(line);
    if (match && addonNames.has(match[1].split('\\')[0])) return match[1];
  }
  return null;
}

/**
 * Groups identical entries of the given addons and sorts them, most frequent first.
 * @param {ReturnType<typeof parseTaintLog>} entries
 * @param {string[]} addons names of the addons to report
 * @returns {{ count: number, kind: string, subject: string, addon: string, location: string }[]}
 */
export function summarizeTaint(entries, addons) {
  const addonNames = new Set(addons);
  const groups = new Map();
  for (const entry of entries) {
    if (!addonNames.has(entry.addon)) continue;
    const location = addonLocation(entry.stack, addonNames) ?? UNKNOWN_LOCATION;
    const key = [entry.kind, entry.subject, entry.addon, location].join('\n');
    const group = groups.get(key) ?? { count: 0, kind: entry.kind, subject: entry.subject, addon: entry.addon, location };
    group.count += 1;
    groups.set(key, group);
  }
  return [...groups.values()].sort(
    (a, b) => b.count - a.count || a.subject.localeCompare(b.subject) || a.location.localeCompare(b.location),
  );
}

export function formatTaintReport(groups) {
  if (groups.length === 0) return 'No blocked actions or tainted globals from the addon in this log.';
  const width = String(groups[0].count).length;
  return groups
    .map((group) => `${String(group.count).padStart(width)}x  ${group.kind}  ${group.subject}  [${group.addon}]  ${group.location}`)
    .join('\n');
}
