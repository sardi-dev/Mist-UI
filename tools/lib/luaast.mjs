// Small helpers shared by the Lua analysis modules.

// Every file of the addon shares one table under this local name.
export const ADDON_TABLE = 'addon';
// Local names the addon gives its translation tables: L["text"] and LO["text"].
export const LOCALE_TABLES = new Set(['L', 'LO']);

export function stringValue(node) {
  if (!node || node.type !== 'StringLiteral') return null;
  const raw = node.raw;
  if (raw.startsWith('[')) {
    const open = raw.indexOf('[', 1) + 1;
    return raw.slice(open, raw.length - open);
  }
  return raw.slice(1, -1);
}

// Returns "L" or "LO" when the node is a translation table, written either as the
// local `L` or as the shared table's field `addon.L`; null for anything else.
export function localeTableName(node) {
  if (node.type === 'Identifier' && LOCALE_TABLES.has(node.name)) return node.name;
  if (
    node.type === 'MemberExpression' &&
    node.base.type === 'Identifier' &&
    node.base.name === ADDON_TABLE &&
    LOCALE_TABLES.has(node.identifier.name)
  ) {
    return node.identifier.name;
  }
  return null;
}

// Calls visit(node) for the node and every node below it.
export function walk(node, visit) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) {
    for (const child of node) walk(child, visit);
    return;
  }
  if (node.type) visit(node);
  for (const [key, value] of Object.entries(node)) {
    if (key === 'loc' || key === 'range' || key === 'type') continue;
    if (value && typeof value === 'object') walk(value, visit);
  }
}
