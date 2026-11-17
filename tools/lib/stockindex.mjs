// Builds an index of the names the stock 5.4.8 interface source knows about.
// The stock source lives outside this repository; a name its own code uses
// (a client function, a frame, a constant) is taken to exist in that client.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { analyzeLua, LuaSyntaxError } from './luaglobals.mjs';

const XML_NAME = /\bname\s*=\s*"([^"]+)"/g;
const PARENT_PREFIX = '$parent';
const UPPERCASE_STRING = /["']([A-Z][A-Z0-9_]*)["']/g;
// Console variables the stock code reads, writes or binds to an options control.
const CVAR_USES = [/\b(?:Get|Set)CVar\w*\(\s*["']([^"']+)["']/g, /\bcvar\s*=\s*["']([^"']+)["']/gi];
const LOOSE_IDENTIFIER = /[A-Za-z_][A-Za-z0-9_]*/g;

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

export function collectXmlNames(text, names, parentSuffixes) {
  for (const match of text.matchAll(XML_NAME)) {
    const name = match[1];
    if (name.startsWith(PARENT_PREFIX)) parentSuffixes.add(name.slice(PARENT_PREFIX.length));
    else if (!name.includes('$')) names.add(name);
  }
}

/**
 * @param {string} uiSourceDir checkout of the stock interface source
 */
export function buildStockIndex(uiSourceDir) {
  const identifiers = new Set();
  const xmlNames = new Set();
  const parentSuffixes = new Set();
  const uppercaseStrings = new Set();
  const cvars = new Set(); // lower case: the client ignores case in these names

  for (const file of walk(uiSourceDir)) {
    const lower = file.toLowerCase();
    if (!lower.endsWith('.lua') && !lower.endsWith('.xml')) continue;
    const text = readFileSync(file, 'latin1');
    for (const match of text.matchAll(UPPERCASE_STRING)) uppercaseStrings.add(match[1]);
    for (const pattern of CVAR_USES) {
      for (const match of text.matchAll(pattern)) cvars.add(match[1].toLowerCase());
    }

    if (lower.endsWith('.xml')) {
      collectXmlNames(text, xmlNames, parentSuffixes);
      // Inline handler scripts call functions by name.
      for (const match of text.matchAll(LOOSE_IDENTIFIER)) identifiers.add(match[0]);
      continue;
    }
    try {
      const { reads, writes } = analyzeLua(text);
      for (const name of reads.keys()) identifiers.add(name);
      for (const name of writes.keys()) identifiers.add(name);
    } catch (error) {
      if (!(error instanceof LuaSyntaxError)) throw error;
      for (const match of text.matchAll(LOOSE_IDENTIFIER)) identifiers.add(match[0]);
    }
  }
  return { identifiers, xmlNames, parentSuffixes, uppercaseStrings, cvars };
}

/**
 * Returns a function that classifies a global name as 'known', 'derived'
 * (a known frame name plus a child suffix such as "Icon") or 'unknown'.
 */
export function createNameClassifier(index, extraKnown = new Set()) {
  const memo = new Map();
  const isDirect = (name) => index.identifiers.has(name) || index.xmlNames.has(name) || extraKnown.has(name);

  const classify = (name) => {
    if (memo.has(name)) return memo.get(name);
    let result = 'unknown';
    if (isDirect(name)) {
      result = 'known';
    } else {
      memo.set(name, 'unknown'); // guards the recursion below
      for (let split = name.length - 1; split >= 1; split -= 1) {
        if (index.parentSuffixes.has(name.slice(split)) && classify(name.slice(0, split)) !== 'unknown') {
          result = 'derived';
          break;
        }
      }
    }
    memo.set(name, result);
    return result;
  };
  return classify;
}
