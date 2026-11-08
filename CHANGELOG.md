# NameplateSCT

## [1.55] (2026-11-08)

- WoW Forever (Camelot 1.60.1, Interface 16001): Added dedicated `NameplateSCT_Forever.toc` with `## AllowLoadGameType: camelot`.
- Added WoW Forever / Camelot compatibility and updated floating combat text CVar to `floatingCombatTextCombatDamage_v2`.
- Added secret-value guards (`issecretvalue`) to prevent Lua errors when restrictions are active:
  - Guarded `NAME_PLATE_UNIT_ADDED` / `NAME_PLATE_UNIT_REMOVED` against indexing tables with secret GUIDs.
  - Guarded `CombatFilter` against secret GUIDs and event clues.
  - Safe pass-through of secret damage values directly to FontString text sinks without arithmetic, comparison, or string formatting failure.
  - Fallback to `C_CombatLog.GetCurrentEventInfo` with safe pcall event registration.
- Fixed duplicate `Spellshadow` school color mask key.
- Fixed global variable leak of `critical` in missed event handlers.
- Configured `.luacheckrc` and `.luarc.json` for linting and LuaLS validation.

## [1.54](https://github.com/Justw8/NameplateSCT/tree/1.54) (2026-07-15)
[Full Changelog](https://github.com/Justw8/NameplateSCT/compare/1.53...1.54) [Previous Releases](https://github.com/Justw8/NameplateSCT/releases)

- TBC: bump toc  
