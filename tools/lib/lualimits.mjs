// Measures a parsed Lua 5.1 file against two limits of the Lua compiler the
// game client uses: a function may have 200 local variables in scope at one
// time and may capture 60 variables of the functions around it ("upvalues").
// One more and the client refuses to load the whole file.

export const MAX_LOCALS = 200;
export const MAX_UPVALUES = 60;

// A `for` loop keeps three hidden variables of its own while it runs.
const FOR_HIDDEN_LOCALS = 3;
const HIDDEN = Symbol('hidden');
const MAIN_CHUNK = '(file level)';
const ANONYMOUS = '(anonymous)';

function functionName(identifier) {
  if (!identifier) return ANONYMOUS;
  if (identifier.type === 'Identifier') return identifier.name;
  const base = identifier.base?.type === 'Identifier' ? identifier.base.name : functionName(identifier.base);
  return `${base}${identifier.indexer ?? '.'}${identifier.identifier?.name ?? '?'}`;
}

/**
 * @param {object} ast luaparse tree of one file (parsed with `locations: true`)
 * @returns {{ name: string, line: number, locals: number, upvalues: number }[]}
 *   one entry per function, the file level included; `locals` is the highest
 *   number of local variables in scope at once
 */
export function measureLuaLimits(ast) {
  const results = [];

  // `blocks` is the stack of open scopes of the function being measured; a
  // block maps a variable name to true, or a hidden key to a count.
  const newFunction = (name, line, parent) => ({
    name,
    line,
    parent,
    blocks: [new Map()],
    active: 0,
    maxActive: 0,
    upvalues: new Set(),
  });

  const grow = (fn, count) => {
    fn.active += count;
    if (fn.active > fn.maxActive) fn.maxActive = fn.active;
  };

  const declare = (fn, name) => {
    const block = fn.blocks[fn.blocks.length - 1];
    // Declaring a name twice in one block still takes two slots.
    if (block.has(name)) block.set(HIDDEN, (block.get(HIDDEN) ?? 0) + 1);
    else block.set(name, true);
    grow(fn, 1);
  };

  const reserve = (fn, count) => {
    const block = fn.blocks[fn.blocks.length - 1];
    block.set(HIDDEN, (block.get(HIDDEN) ?? 0) + count);
    grow(fn, count);
  };

  const pushBlock = (fn) => fn.blocks.push(new Map());

  const popBlock = (fn) => {
    for (const value of fn.blocks.pop().values()) fn.active -= value === true ? 1 : value;
  };

  const hasLocal = (fn, name) => fn.blocks.some((block) => block.get(name) === true);

  // A variable of an outer function is an upvalue of every function between
  // its owner and the code that uses it.
  const use = (fn, name) => {
    const between = [];
    let cursor = fn;
    while (cursor && !hasLocal(cursor, name)) {
      between.push(cursor);
      cursor = cursor.parent;
    }
    if (!cursor) return; // a global
    for (const item of between) item.upvalues.add(name);
  };

  const walkBody = (fn, body) => {
    for (const statement of body) walk(fn, statement);
  };

  const walkScoped = (fn, body) => {
    pushBlock(fn);
    walkBody(fn, body);
    popBlock(fn);
  };

  const walkFunction = (outer, node) => {
    const inner = newFunction(functionName(node.identifier), node.loc.start.line, outer);
    if (node.identifier?.type === 'MemberExpression' && node.identifier.indexer === ':') declare(inner, 'self');
    for (const parameter of node.parameters) {
      if (parameter.type === 'Identifier') declare(inner, parameter.name);
    }
    walkBody(inner, node.body);
    results.push({ name: inner.name, line: inner.line, locals: inner.maxActive, upvalues: inner.upvalues.size });
  };

  function walk(fn, node) {
    if (!node || typeof node !== 'object') return;
    switch (node.type) {
      case 'Identifier':
        use(fn, node.name);
        return;
      case 'MemberExpression':
        // node.identifier is a field name, not a variable.
        walk(fn, node.base);
        return;
      case 'TableKeyString':
        walk(fn, node.value);
        return;
      case 'LocalStatement':
        // The values are evaluated before the names exist.
        for (const init of node.init) walk(fn, init);
        for (const variable of node.variables) declare(fn, variable.name);
        return;
      case 'FunctionDeclaration':
        // `local function f` can call itself: the name exists before the body.
        if (node.isLocal && node.identifier) declare(fn, node.identifier.name);
        else if (node.identifier) walk(fn, node.identifier);
        walkFunction(fn, node);
        return;
      case 'DoStatement':
        walkScoped(fn, node.body);
        return;
      case 'WhileStatement':
        walk(fn, node.condition);
        walkScoped(fn, node.body);
        return;
      case 'RepeatStatement':
        // The `until` condition still sees the body's variables.
        pushBlock(fn);
        walkBody(fn, node.body);
        walk(fn, node.condition);
        popBlock(fn);
        return;
      case 'IfStatement':
        for (const clause of node.clauses) {
          if (clause.condition) walk(fn, clause.condition);
          walkScoped(fn, clause.body);
        }
        return;
      case 'ForNumericStatement':
        walk(fn, node.start);
        walk(fn, node.end);
        walk(fn, node.step);
        pushBlock(fn);
        reserve(fn, FOR_HIDDEN_LOCALS);
        declare(fn, node.variable.name);
        walkBody(fn, node.body);
        popBlock(fn);
        return;
      case 'ForGenericStatement':
        for (const iterator of node.iterators) walk(fn, iterator);
        pushBlock(fn);
        reserve(fn, FOR_HIDDEN_LOCALS);
        for (const variable of node.variables) declare(fn, variable.name);
        walkBody(fn, node.body);
        popBlock(fn);
        return;
      default:
        for (const [key, value] of Object.entries(node)) {
          if (key === 'loc' || key === 'range' || key === 'type') continue;
          if (Array.isArray(value)) for (const item of value) walk(fn, item);
          else if (value && typeof value === 'object') walk(fn, value);
        }
    }
  }

  const main = newFunction(MAIN_CHUNK, 1, null);
  walkBody(main, ast.body);
  results.push({ name: main.name, line: main.line, locals: main.maxActive, upvalues: 0 });
  return results;
}
