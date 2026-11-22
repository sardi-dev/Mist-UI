#!/usr/bin/env node
// Usage: node tools/harness.mjs [--saved <MistUI.lua>] [--verbose]
// Loads both addons into a fake 5.4.8 game with Lua 5.1, plays a short session (login, bags,
// bank, combat, slash commands) and prints every Lua error with its stack. It finds errors, not
// looks or taint. It also enforces the combat lockdown: in combat, a change that addon code makes
// to a protected frame (XML protected="true" or a Secure* template, or a frame holding one) is
// blocked and listed as an error with the method, the frame and the addon file and line. Only
// Show, Hide, SetShown, SetPoint, ClearAllPoints, SetAllPoints, SetParent, SetWidth, SetHeight,
// SetSize, SetScale and SetAttribute count, and on a texture or font string only SetParent.
// Calls made by the harness itself or by stock code are not counted. Needs:
//   - lua5.1.exe: the MISTUI_LUA51 variable, else ../tools-lua51/lua5.1.exe
//   - the stock interface source: MISTUI_UI_SOURCE, else ../ui-source-5.4.8
//   - optional, the client program for the names of its own functions: MISTUI_CLIENT_EXE
//     (read only; without it those names are answered with stand-ins)
// --saved loads a saved settings file (for example the game's WTF copy) instead of none.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseToc, resolveLoadList } from './lib/loadlist.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PARENT = resolve(REPO_ROOT, '..');
const ADDONS = ['MistUI', 'MistUI_Options'];

function pick(envName, fallback) {
  const value = process.env[envName] ?? fallback;
  return value && existsSync(value) ? resolve(value) : null;
}

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

const FRAME_TAGS = new Set([
  'Frame', 'Button', 'CheckButton', 'StatusBar', 'Slider', 'EditBox', 'ScrollFrame', 'Cooldown', 'GameTooltip',
  'MessageFrame', 'ScrollingMessageFrame', 'Model', 'PlayerModel', 'Minimap', 'ColorSelect', 'SimpleHTML',
  'DressUpModel', 'TabardModel', 'Texture', 'FontString', 'MovieFrame', 'Font',
  'QuestPOIFrame', 'ArchaeologyDigSiteFrame', 'ScenarioPOIFrame',
]);

// Button and bar parts declared with their own tags: the region type and the slot they fill.
const PART_TAGS = {
  NormalTexture: ['Texture', '__normal'], PushedTexture: ['Texture', '__pushed'],
  HighlightTexture: ['Texture', '__highlight'], CheckedTexture: ['Texture', '__checked'],
  DisabledTexture: ['Texture', '__disabled'], DisabledCheckedTexture: ['Texture', '__disabledChecked'],
  ThumbTexture: ['Texture', '__thumb'], BarTexture: ['Texture', '__barTexture'],
  ButtonText: ['FontString', '__fontString'],
};
for (const tag of Object.keys(PART_TAGS)) FRAME_TAGS.add(tag);

// Frames, templates and their children from interface XML. A template's children are stored
// with names relative to "$parent" (the frame made from the template) and a path that says
// which child they hang from.
function readXml(text, frames, templates) {
  // Inline script code can contain "<" and ">": keep each handler's tag, drop its code.
  text = text.replace(/<!--[\s\S]*?-->/g, '').replace(/<(On\w+)([^>]*?)(?<!\/)>[\s\S]*?<\/\1>/g, '<$1$2/>');
  const stack = [];
  let counter = 0;
  for (const m of text.matchAll(/<(\/?)([A-Za-z]+)\b([^>]*?)(\/?)>/g)) {
    const [, closing, xmlTag, attrs, selfClosing] = m;
    if (closing) {
      for (let i = stack.length - 1; i >= 0; i--) {
        if (stack[i].xmlTag === xmlTag) { stack.length = i; break; }
      }
      continue;
    }
    if (/^On[A-Z]/.test(xmlTag)) {
      // A script handler: recorded on the frame or template child it belongs to.
      const owner = [...stack].reverse().find((s) => s.isFrame);
      if (owner && owner.scripts) owner.scripts.push(xmlTag);
      continue;
    }
    const part = PART_TAGS[xmlTag];
    const tag = part ? part[0] : xmlTag;
    const slot = part ? part[1] : undefined;
    const attr = (name) => (attrs.match(new RegExp(`\\b${name}\\s*=\\s*"([^"]*)"`)) || [])[1];
    const isFrame = FRAME_TAGS.has(tag);
    const enclosing = [...stack].reverse().find((s) => s.isFrame);
    let entry = { tag, isFrame };
    if (isFrame) {
      const rawName = attr('name');
      const inherits = attr('inherits');
      const parentKey = attr('parentKey');
      const hidden = attr('hidden') === 'true';
      // Only protected frames are locked in combat; the Secure* templates inherit this flag.
      const isProtected = attr('protected') === 'true';
      const root = enclosing ? enclosing.root : null;
      if (tag === 'Font' && !enclosing && rawName) {
        // Font objects are global objects even when the XML marks them virtual.
        frames[rawName] = { type: 'Font', inherits, keys: [], scripts: [] };
      }
      if (!enclosing && attr('virtual') === 'true') {
        // A template root: its own name is the template name.
        const tmpl = { type: tag, inherits, children: [], scripts: [], protected: isProtected };
        templates[rawName] = tmpl;
        entry = { tag, isFrame, root: { tmpl }, name: '$parent', path: '', scripts: tmpl.scripts };
      } else if (root && root.tmpl) {
        // A child inside a template.
        const name = rawName ? rawName.replace(/\$parent/g, enclosing.name ?? '$parent') : null;
        const path = `${enclosing.path}/${counter++}`;
        const child = { type: tag, slot, name, inherits, parentKey, hidden, path, parentPath: enclosing.path, scripts: [], protected: isProtected };
        root.tmpl.children.push(child);
        entry = { tag, isFrame, root, name: name ?? enclosing.name, path, scripts: child.scripts };
      } else {
        // A concrete frame or one of its children.
        let name = rawName;
        if (name && enclosing && enclosing.name) name = name.replace(/\$parent/g, enclosing.name);
        if (name && name.includes('$parent')) name = null;
        const parentName = attr('parent') || (enclosing ? enclosing.name : null);
        const scripts = [];
        if (name) {
          frames[name] = { type: tag, parent: parentName, hidden, inherits, keys: [], scripts, protected: isProtected };
        }
        // Every child of a named frame is recorded on it, so its regions and parentKey fields exist.
        if (enclosing && enclosing.name && frames[enclosing.name]) {
          frames[enclosing.name].keys.push({ key: parentKey, slot, type: tag, name, inherits, hidden, scripts, protected: isProtected });
        }
        entry = { tag, isFrame, root: { concrete: true }, name, path: '', scripts };
      }
    }
    entry.xmlTag = xmlTag;
    if (!selfClosing) stack.push(entry);
  }
}
const CONSTANT = /^([A-Z][A-Za-z0-9_]+)\s*=\s*(-?\d+(?:\.\d+)?|"(?:[^"\\]|\\.)*"|true|false|\{\s*\})\s*;?\s*(?:--.*)?$/;
const FUNCTION = /^function\s+([A-Za-z_][\w]*)\s*\(|^([A-Za-z_][\w]*)\s*=\s*function\b/;

// Names, types and parents of the stock frames, the stock Lua functions and literal constants.
// Stock addons the client loads at login: those not marked load on demand, and those the
// addon's TOC names as dependencies. The others (the guild bank window, for one) do not exist yet.
function loadedStockAddons(uiSource, addonDir) {
  const meta = parseToc(readFileSync(join(addonDir, `${ADDONS[0]}.toc`), 'utf8')).meta;
  const deps = `${meta.Dependencies ?? ''},${meta.OptionalDeps ?? ''},${meta.RequiredDeps ?? ''}`
    .split(',').map((s) => s.trim()).filter(Boolean);
  const loaded = new Set(deps);
  const addonsDir = join(uiSource, 'AddOns');
  for (const name of existsSync(addonsDir) ? readdirSync(addonsDir) : []) {
    const toc = join(addonsDir, name, `${name}.toc`);
    if (existsSync(toc) && parseToc(readFileSync(toc, 'utf8')).meta.LoadOnDemand !== '1') loaded.add(name);
  }
  return loaded;
}

function readStock(uiSource, addonDirs) {
  const frames = {};
  const templates = {};
  const functions = new Set();
  const constants = {};
  const loadedAddons = loadedStockAddons(uiSource, addonDirs[0]);
  const addonsDir = join(uiSource, 'AddOns');
  for (const file of walk(uiSource)) {
    if (file.startsWith(addonsDir)) {
      const addonName = file.slice(addonsDir.length + 1).split(/[\\/]/)[0];
      if (!loadedAddons.has(addonName)) continue;
    }
    if (file.endsWith('.lua')) {
      for (const line of readFileSync(file, 'utf8').split(/\r?\n/)) {
        const fn = line.match(FUNCTION);
        if (fn) functions.add(fn[1] || fn[2]);
        const c = line.match(CONSTANT);
        if (c && !(c[1] in constants)) constants[c[1]] = c[2];
      }
    } else if (file.endsWith('.xml')) {
      readXml(readFileSync(file, 'utf8'), frames, templates);
    }
  }
  // The addon's own XML templates, so its CreateFrame calls get their children too.
  const addonFrames = {};
  for (const dir of addonDirs) {
    for (const file of walk(dir)) {
      if (file.endsWith('.xml')) readXml(readFileSync(file, 'utf8'), addonFrames, templates);
    }
  }
  return { frames, templates, functions, constants };
}

const luaValue = (v) => {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'boolean' || typeof v === 'number') return String(v);
  if (typeof v === 'string') return luaString(v);
  if (Array.isArray(v)) return `{${v.map(luaValue).join(',')}}`;
  return `{${Object.entries(v).map(([k, x]) => `[${luaString(k)}]=${luaValue(x)}`).join(',')}}`;
};

// Identifiers stored in the client program: the names of the functions it gives to Lua.
function readClientNames(exe) {
  const names = new Set();
  if (!exe) return names;
  const buf = readFileSync(exe);
  let start = -1;
  for (let i = 0; i < buf.length; i++) {
    const c = buf[i];
    const ident = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95;
    if (ident) {
      if (start < 0) start = i;
    } else {
      if (start >= 0 && c === 0 && i - start >= 3 && i - start <= 60 && buf[start - 1] === 0) {
        const first = buf[start];
        if (first >= 65 && first <= 90) names.add(buf.toString('latin1', start, i));
      }
      start = -1;
    }
  }
  return names;
}

const luaString = (s) => JSON.stringify(s).replace(/\\u([0-9a-f]{4})/gi, (_, h) => `\\${parseInt(h, 16)}`);
const luaPath = (p) => luaString(p.replace(/\\/g, '/'));

function main(argv) {
  const lua = pick('MISTUI_LUA51', join(PARENT, 'tools-lua51', 'lua5.1.exe'));
  const uiSource = pick('MISTUI_UI_SOURCE', join(PARENT, 'ui-source-5.4.8'));
  const exe = pick('MISTUI_CLIENT_EXE', null);
  if (!lua || !uiSource) {
    console.log('Harness SKIPPED: needs lua5.1.exe and the stock interface source (see the top of this file).');
    return 0;
  }
  const savedFlag = argv.indexOf('--saved');
  const saved = savedFlag >= 0 ? resolve(argv[savedFlag + 1]) : null;


  const stock = readStock(uiSource, ADDONS.map((name) => join(REPO_ROOT, name)));
  const clientNames = readClientNames(exe);
  const out = [];
  out.push('return {');
  out.push(`verbose = ${argv.includes('--verbose')},`);
  out.push('stockLuaFiles = {');
  for (const f of ['FrameXML/GlobalStrings.lua', 'FrameXML/Constants.lua']) {
    const full = join(uiSource, f);
    if (existsSync(full)) out.push(`${luaPath(full)},`);
  }
  out.push('},');
  out.push('stock = { frames = {');
  for (const [name, info] of Object.entries(stock.frames)) out.push(`[${luaString(name)}] = ${luaValue(info)},`);
  out.push('}, templates = {');
  for (const [name, info] of Object.entries(stock.templates)) out.push(`[${luaString(name)}] = ${luaValue(info)},`);
  out.push('}, functions = {');
  for (const name of stock.functions) out.push(`[${luaString(name)}] = true,`);
  out.push('}, constants = {');
  for (const [name, value] of Object.entries(stock.constants)) out.push(`[${luaString(name)}] = ${value},`);
  out.push('} },');
  out.push('clientNames = {');
  for (const name of clientNames) out.push(`[${luaString(name)}] = true,`);
  out.push('},');
  out.push('addons = {');
  for (const name of ADDONS) {
    const dir = join(REPO_ROOT, name);
    const { toc, lua: files } = resolveLoadList(dir);
    const lod = toc.meta.LoadOnDemand === '1';
    out.push(`{ name = ${luaString(name)}, loadOnDemand = ${lod}, saved = ${name === 'MistUI' && saved ? luaPath(saved) : 'nil'}, files = {`);
    for (const f of files) out.push(`${luaPath(f)},`);
    out.push('} },');
  }
  out.push('},');
  out.push('}');

  const work = mkdtempSync(join(tmpdir(), 'mistui-harness-'));
  const manifest = join(work, 'manifest.lua');
  writeFileSync(manifest, out.join('\n'));
  const result = spawnSync(lua, [join(REPO_ROOT, 'tools', 'harness', 'run.lua'), manifest], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  process.stdout.write(result.stdout || '');
  process.stderr.write(result.stderr || '');
  return result.status ?? 1;
}

process.exitCode = main(process.argv.slice(2));
