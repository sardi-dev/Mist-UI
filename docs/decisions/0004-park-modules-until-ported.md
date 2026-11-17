# 0004. Park modules until they are ported, and check names statically

- **Date:** 2026-11-09
- **Status:** Accepted

## Context

The addon can only run inside the game client, so a mistake normally shows up
as an error during a manual test session. Loading all imported modules at
once on 5.4.8 would produce hundreds of errors with no clear order to fix
them in.

## Decision

A module runs only when `MistUI/modules/modules.xml` lists it. Imported files
that are not listed are "parked". Modules are ported and listed one at a time.

`npm run check` resolves the load list and, for loaded files only, reports
every global name, event and frame template that the stock 5.4.8 interface
source does not know. That source is read from a folder outside the
repository. Names verified by hand are recorded with a reason in
`tools/known-globals.txt`. Parked files are only checked for syntax.

Luaparse (MIT) is the one development dependency. No Lua runtime is required.

## Consequences

- Each port has a clear finish line before the in-game test.
- The check proves that a name exists, not that it behaves the same as on
  3.3.5a. Reading the stock 5.4.8 code and testing in game are still needed.
- A name the stock code never uses is reported even if the client has it, and
  needs an allowlist entry.
