// Finds interface texts that reach a translation table (L["text"]) without
// being written at the lookup itself. Three patterns exist in the addon:
//
//  1. A helper whose body looks a parameter up in the table
//     (`local function T(key) return L[key] end`), called as T("text").
//  2. A key table whose values are looked up, directly (`L[KEYS[name]]`) or
//     through a local (`local k = KEYS[name]; return L[k]`).
//  3. A field name used as the key (`LO[group.label]`, or a helper called with
//     `opts.labelKey`): the texts are the string values of that field in the
//     table rows (tables nested in another table) of the same file.
//
// Everything is matched by name inside one file, so a shadowed variable, a
// helper defined in another file or a text built at run time is not followed.

import { localeTableName, stringValue, walk } from './luaast.mjs';

const lineOf = (node) => node.loc.start.line;

// `local function T`, `function T` and `local T = function` all name a helper.
function namedFunctions(node) {
  if (node.type === 'FunctionDeclaration') {
    return node.identifier?.type === 'Identifier' ? [[node.identifier.name, node]] : [];
  }
  if (node.type !== 'LocalStatement' && node.type !== 'AssignmentStatement') return [];
  const pairs = [];
  node.variables.forEach((target, index) => {
    const value = node.init?.[index];
    if (target.type === 'Identifier' && value?.type === 'FunctionDeclaration') pairs.push([target.name, value]);
  });
  return pairs;
}

// Parameters of the function that its body looks up in a translation table.
function lookedUpParameters(fn) {
  const found = [];
  const names = fn.parameters.map((parameter) => parameter.name);
  walk(fn.body, (node) => {
    if (node.type !== 'IndexExpression' || node.index.type !== 'Identifier') return;
    const table = localeTableName(node.base);
    const position = names.indexOf(node.index.name);
    if (table && position >= 0) found.push({ table, position });
  });
  return found;
}

function stringFields(constructor, fieldName) {
  const values = [];
  for (const field of constructor.fields) {
    const named =
      (field.type === 'TableKeyString' && field.key.name === fieldName) ||
      (field.type === 'TableKey' && stringValue(field.key) === fieldName);
    const key = named ? stringValue(field.value) : null;
    if (key !== null) values.push({ key, line: lineOf(field.value) });
  }
  return values;
}

function allStrings(constructor) {
  return constructor.fields.flatMap((field) => {
    const key = stringValue(field.value);
    return key === null ? [] : [{ key, line: lineOf(field.value) }];
  });
}

/**
 * @param {object} ast luaparse chunk
 * @returns {{ table: string, key: string, line: number }[]}
 */
export function findIndirectLocaleUses(ast) {
  const helpers = new Map(); // function name -> [{ table, position }]
  const calls = [];
  const lookups = [];
  const tableConstructors = new Map(); // local name -> constructor it was set to
  const readFrom = new Map(); // variable name -> name of the table it was read from
  const rows = [];

  walk(ast.body, (node) => {
    for (const [name, fn] of namedFunctions(node)) {
      const parameters = lookedUpParameters(fn);
      if (parameters.length > 0) helpers.set(name, parameters);
    }

    if (node.type === 'CallExpression' && node.base.type === 'Identifier') {
      calls.push({ name: node.base.name, args: node.arguments, line: lineOf(node) });
    }
    if (node.type === 'IndexExpression') {
      const table = localeTableName(node.base);
      if (table) lookups.push({ table, index: node.index });
    }
    if (node.type === 'LocalStatement' || node.type === 'AssignmentStatement') {
      node.variables.forEach((target, index) => {
        const value = node.init?.[index];
        if (target.type !== 'Identifier' || !value) return;
        if (node.type === 'LocalStatement' && value.type === 'TableConstructorExpression') {
          tableConstructors.set(target.name, value);
        }
        if (value.type === 'IndexExpression' && value.base.type === 'Identifier') {
          readFrom.set(target.name, value.base.name);
        }
      });
    }
    if (node.type === 'TableConstructorExpression') {
      for (const field of node.fields) {
        if (field.type === 'TableValue' && field.value.type === 'TableConstructorExpression') rows.push(field.value);
      }
    }
  });

  const keyTables = new Map(); // local name -> locale tables its values are looked up in
  const keyFields = new Map(); // field name -> locale tables its values are looked up in
  const addTo = (map, name, table) => map.set(name, (map.get(name) ?? new Set()).add(table));
  const uses = [];

  for (const { table, index } of lookups) {
    if (index.type === 'IndexExpression' && index.base.type === 'Identifier') {
      addTo(keyTables, index.base.name, table);
    } else if (index.type === 'Identifier' && readFrom.has(index.name)) {
      addTo(keyTables, readFrom.get(index.name), table);
    } else if (index.type === 'MemberExpression') {
      addTo(keyFields, index.identifier.name, table);
    }
  }

  for (const call of calls) {
    for (const { table, position } of helpers.get(call.name) ?? []) {
      const argument = call.args[position];
      const key = stringValue(argument);
      if (key !== null) uses.push({ table, key, line: call.line });
      else if (argument?.type === 'MemberExpression') addTo(keyFields, argument.identifier.name, table);
    }
  }

  for (const [name, tables] of keyTables) {
    const constructor = tableConstructors.get(name);
    if (!constructor) continue;
    for (const table of tables) uses.push(...allStrings(constructor).map((text) => ({ table, ...text })));
  }
  for (const [fieldName, tables] of keyFields) {
    for (const row of rows) {
      for (const table of tables) uses.push(...stringFields(row, fieldName).map((text) => ({ table, ...text })));
    }
  }
  return uses;
}
