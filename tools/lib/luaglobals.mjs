// Static analysis of one Lua 5.1 file: which global names it reads and
// writes, which game events it registers, which frame templates it uses,
// which draw sublevels it asks for and how close its functions come to the
// compiler's limits.

import luaparse from 'luaparse';
import { measureLuaLimits } from './lualimits.mjs';

const EVENT_METHODS = new Set(['RegisterEvent', 'RegisterUnitEvent', 'UnregisterEvent', 'IsEventRegistered']);
const CVAR_FUNCTIONS = new Set(['GetCVar', 'SetCVar', 'GetCVarBool', 'GetCVarDefault']);
const TEMPLATE_ARG_INDEX = 3; // CreateFrame(type, name, parent, template)
// Methods that take a draw sublevel, and the position of that argument:
// region:SetDrawLayer(layer, sublevel), frame:CreateTexture(name, layer, template, sublevel).
const SUBLEVEL_ARG_INDEX = new Map([
  ['SetDrawLayer', 1],
  ['CreateTexture', 3],
]);
const GLOBAL_TABLE = '_G';
// hooksecurefunc("Name", handler) hooks a global function by its name. The name is a string, so
// a misspelt or removed function would otherwise pass as text and fail in the client.
const HOOK_FUNCTION = 'hooksecurefunc';
// Every file of the addon shares one table under this local name.
const ADDON_TABLE = 'addon';
// Local names the addon gives its translation tables: L["text"] and LO["text"].
const LOCALE_TABLES = new Set(['L', 'LO']);
// The byte order mark as decoded text and as its three raw bytes (files are read as latin1).
const BYTE_ORDER_MARKS = [String.fromCharCode(0xfeff), String.fromCharCode(0xef, 0xbb, 0xbf)];

export class LuaSyntaxError extends Error {
  constructor(message, line) {
    super(message);
    this.line = line;
  }
}

function stringValue(node) {
  if (!node || node.type !== 'StringLiteral') return null;
  const raw = node.raw;
  if (raw.startsWith('[')) {
    const open = raw.indexOf('[', 1) + 1;
    return raw.slice(open, raw.length - open);
  }
  return raw.slice(1, -1);
}

// Returns the value of a number written out in the source (`7`, `-8`), or null.
function numberValue(node) {
  if (!node) return null;
  if (node.type === 'NumericLiteral') return node.value;
  if (node.type === 'UnaryExpression' && node.operator === '-' && node.argument.type === 'NumericLiteral') {
    return -node.argument.value;
  }
  return null;
}

function record(map, name, line) {
  if (!map.has(name)) map.set(name, []);
  map.get(name).push(line);
}

/**
 * @param {string} source Lua source text
 * @returns {{ reads: Map<string, number[]>, writes: Map<string, number[]>,
 *             fieldReads: Map<string, number[]>, fieldWrites: Map<string, number[]>,
 *             events: {name: string, line: number}[], templates: {name: string, line: number}[],
 *             cvars: {name: string, line: number}[],
 *             hooks: {name: string, line: number}[],
 *             sublevels: {value: number, line: number}[],
 *             limits: {name: string, line: number, locals: number, upvalues: number}[],
 *             localeUses: {table: string, key: string, line: number}[], localeDefs: Set<string> }}
 *   fieldReads and fieldWrites are fields of the shared addon table (addon.Name).
 *   sublevels holds the draw sublevels written as plain numbers; limits is described in lualimits.mjs.
 */
export function analyzeLua(source) {
  const mark = BYTE_ORDER_MARKS.find((candidate) => source.startsWith(candidate));
  const text = mark ? source.slice(mark.length) : source;
  let ast;
  try {
    ast = luaparse.parse(text, { luaVersion: '5.1', scope: true, locations: true, comments: false });
  } catch (error) {
    throw new LuaSyntaxError(error.message, error.line);
  }

  const reads = new Map();
  const writes = new Map();
  const fieldReads = new Map();
  const fieldWrites = new Map();
  const events = [];
  const templates = [];
  const cvars = [];
  const hooks = [];
  const sublevels = [];
  const localeUses = [];
  const localeDefs = new Set();

  const lineOf = (node) => node.loc.start.line;

  const readIdentifier = (node) => {
    if (node.type === 'Identifier' && node.isLocal === false) record(reads, node.name, lineOf(node));
  };

  // Libraries often cache it first (`local _G = _G`), so a local of that name counts too.
  const isGlobalTable = (node) => node.type === 'Identifier' && node.name === GLOBAL_TABLE;

  // Returns the global name written by `_G.Name = v` or `_G["Name"] = v`.
  const globalTableField = (node) => {
    if (node.type === 'MemberExpression' && isGlobalTable(node.base)) return node.identifier.name;
    if (node.type === 'IndexExpression' && isGlobalTable(node.base)) return stringValue(node.index);
    return null;
  };

  const isAddonField = (node) =>
    node.type === 'MemberExpression' && node.base.type === 'Identifier' && node.base.name === ADDON_TABLE;

  // Returns the text key of `L["text"]`, or null for anything else.
  const localeKey = (node) =>
    node.type === 'IndexExpression' && node.base.type === 'Identifier' && LOCALE_TABLES.has(node.base.name)
      ? stringValue(node.index)
      : null;

  const writeTarget = (node) => {
    const viaGlobalTable = globalTableField(node);
    if (viaGlobalTable) {
      record(writes, viaGlobalTable, lineOf(node));
    } else if (localeKey(node) !== null) {
      localeDefs.add(localeKey(node));
    } else if (isAddonField(node)) {
      record(fieldWrites, node.identifier.name, lineOf(node));
    } else if (node.type === 'Identifier') {
      if (node.isLocal === false) record(writes, node.name, lineOf(node));
    } else {
      visit(node);
    }
  };

  const visitCall = (node) => {
    const base = node.base;
    // f(a, b) has an array; f{...} and f"..." each carry one node.
    const args = [node.arguments ?? node.argument ?? []].flat();
    if (base.type === 'MemberExpression' && EVENT_METHODS.has(base.identifier.name)) {
      const name = stringValue(args[0]);
      if (name) events.push({ name, line: lineOf(node) });
    }
    if (base.type === 'MemberExpression' && SUBLEVEL_ARG_INDEX.has(base.identifier.name)) {
      const value = numberValue(args[SUBLEVEL_ARG_INDEX.get(base.identifier.name)]);
      if (value !== null) sublevels.push({ value, line: lineOf(node) });
    }
    if (base.type === 'Identifier' && base.name === HOOK_FUNCTION) {
      // With a table first (hooksecurefunc(frame, "Method", handler)) the name is a method, not a global.
      const name = stringValue(args[0]);
      if (name) hooks.push({ name, line: lineOf(node) });
    }
    if (base.type === 'Identifier' && CVAR_FUNCTIONS.has(base.name)) {
      const name = stringValue(args[0]);
      if (name) cvars.push({ name, line: lineOf(node) });
    }
    if (base.type === 'Identifier' && base.name === 'CreateFrame') {
      const templateList = stringValue(args[TEMPLATE_ARG_INDEX]);
      if (templateList) {
        for (const name of templateList.split(',')) {
          if (name.trim()) templates.push({ name: name.trim(), line: lineOf(node) });
        }
      }
    }
    visit(base);
    args.forEach(visit);
  };

  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) {
      node.forEach(visit);
      return;
    }
    switch (node.type) {
      case 'Identifier':
        readIdentifier(node);
        return;
      case 'MemberExpression':
        // node.identifier is a field name, not a variable.
        if (isAddonField(node)) record(fieldReads, node.identifier.name, lineOf(node));
        visit(node.base);
        return;
      case 'IndexExpression':
        if (localeKey(node) !== null) {
          localeUses.push({ table: node.base.name, key: localeKey(node), line: lineOf(node) });
        }
        visit(node.base);
        visit(node.index);
        return;
      case 'TableKeyString':
        // node.key is a field name, not a variable.
        visit(node.value);
        return;
      case 'AssignmentStatement':
        node.variables.forEach(writeTarget);
        node.init.forEach(visit);
        return;
      case 'LocalStatement':
        node.init.forEach(visit);
        return;
      case 'FunctionDeclaration':
        // `function a.b()` and `function a:b()` assign a field; `local function f` declares a local.
        if (node.identifier && !node.isLocal) writeTarget(node.identifier);
        visit(node.body);
        return;
      case 'ForNumericStatement':
        visit(node.start);
        visit(node.end);
        visit(node.step);
        visit(node.body);
        return;
      case 'ForGenericStatement':
        node.iterators.forEach(visit);
        visit(node.body);
        return;
      case 'CallExpression':
      case 'StringCallExpression':
      case 'TableCallExpression':
        visitCall(node);
        return;
      default:
        for (const [key, value] of Object.entries(node)) {
          if (key === 'loc' || key === 'range' || key === 'type') continue;
          if (value && typeof value === 'object') visit(value);
        }
    }
  }

  visit(ast.body);
  return {
    reads,
    writes,
    fieldReads,
    fieldWrites,
    events,
    templates,
    cvars,
    hooks,
    sublevels,
    limits: measureLuaLimits(ast),
    localeUses,
    localeDefs,
  };
}
