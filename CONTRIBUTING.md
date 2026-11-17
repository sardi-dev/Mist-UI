# Contributing

Thanks for helping with Mist-UI. The first public release is out for testing,
so the most useful contributions are test reports from the 5.4.8 client
(through the bug report form), fixes for what they find, and ports of the
modules that are still parked.

## Ground rules

- **No game files in the repository.** No textures, sounds, models, client
  executables or tables extracted from the game's data files. Artwork is
  fetched separately (see [docs/ARTWORK.md](docs/ARTWORK.md)).
- **Credit your sources.** If code comes from another addon, name it and its
  license in the commit body and add it to `MistUI/THIRD_PARTY_NOTICES.md`.
  Keep original license headers. Do not copy from "All Rights Reserved"
  projects.
- **Target the 5.4.8 (18414) client only**, interface version `50400`, on any
  server. Do not depend on behaviour that only one server has.

## Workflow

1. Create a branch from `main`: `type/short-description`, for example
   `feat/minimap-port` or `fix/castbar-latency`.
2. Make one logical change per commit, with a
   [Conventional Commits](https://www.conventionalcommits.org/) message:
   `type(scope): description`, lowercase, imperative, 72 characters at most.
3. Update `CHANGELOG.md` in the same commit (title, date, summary, why).
4. Run `npm test` and `npm run check`. Both must pass. Run `npm run harness`
   too when its tools are installed (see below).
5. Test in the game client and say in the pull request what you tested, on
   which class, and on which kind of server.

## Porting a module

A module is "parked" until it is listed in `MistUI/modules/modules.xml`.

1. Add its `<Script>` or `<Include>` line to `modules.xml`.
2. Run `npm run check` and fix what it reports: functions, frames, events and
   templates that do not exist in the 5.4.8 client, draw sublevels outside
   -8 to 7, and functions past the Lua limits (200 local variables, 60
   captured variables).
3. Read the stock 5.4.8 code for the frames the module touches. A name that
   still exists can still behave differently.
4. Remove branches that only serve 3.3.5a, and the second ("Forever") art
   style, as you go.
5. Test in game: login, `/reload`, combat, a vehicle, and a profile reset.

If the checker flags a name that does exist in the client, add it to
`tools/known-globals.txt` with a comment saying how you verified it.

## Offline run

`npm run harness` loads both addons with Lua 5.1 into a fake 5.4.8 game and
plays a short session: login, bags and bank, a target, combat with a cast, a
party member, a boss, a vehicle, a pet, stances, the guild bank, every
settings tab, three name plates and the slash commands. It prints every Lua
error with its stack. Add `--saved <file>` to start from a saved settings
file. It finds errors,
not looks or taint: the game test still decides.

It needs Lua 5.1 (`lua5.1.exe`, from the LuaBinaries project; set
`MISTUI_LUA51` or place it in `../tools-lua51/`), the stock interface source
(as for `npm run check`) and, for the names of the client's own functions,
the 5.4.8 client program (`MISTUI_CLIENT_EXE`, read only). Without Lua or the
interface source it skips. An error that comes from the fake rather than the
addon is fixed in `tools/harness/`: the fake answers what it does not model
with nil, and widget methods it lacks fail as "attempt to call method".

## Code style

- Follow the style of the surrounding code.
- Comments explain why, not what.
- No dead code, commented-out code or leftover debug prints.
- Name magic numbers.
