# AGENTS.md

Orientation for any agent or automation session working in this repository.

NameplateSCT — a World of Warcraft addon that draws scrolling combat text on nameplates or a
screen area. Version 1.58. Read `CHANGELOG.md` first: its newest entry is the current state.

## 1. Offline verification (no game client needed)

| Command | Proves | Expected |
| :--- | :--- | :--- |
| `wowlua_ls check .` | full diagnostic pass | `No errors or warnings` (12 files, 47 library files skipped) |
| `luacheck NameplateSCT.lua Options/ Tests/` | style/unused analysis | `0 warnings / 0 errors` |
| `bash Tests/run.sh` | runtime behaviour | `77 checks, 0 failed` |
| `luac5.1 -p <file>` | syntax per file | silent |

Run all four before claiming a change works. A red gate is never "done".

## 2. Using wowlua_ls standalone

Binary: `/home/sam/wowlua-ls/target/release/wowlua_ls` (built from the v0.36.0 source checkout;
that checkout's `.git` is read-only, so `git fetch` fails — it cannot self-update).

Authoritative model for the rules below: `https://tradeskillmaster.github.io/wowlua-ls/` —
`guide/secrets.html`, `guide/nil-safety.html`, `guide/diagnostics.html`,
`reference/annotations.html`, `reference/configuration.html`, `reference/diagnostics.html`.
Read `guide/secrets.html` before touching any combat/aura/health code.

```bash
wowlua_ls check .                 # diagnostics for the whole addon
wowlua_ls profile .               # parse/analysis timings
wowlua_ls test-query ...          # hover / definition / completion at a position
wowlua_ls evaluate <file>         # tree, types and diagnostics for one file
wowlua_ls -h                      # all subcommands
```

`.wowluarc.json` semantics (verified against the server source):

- `library` — scanned for **types**, diagnostics **suppressed**. `["Libs/"]` covers every
  vendored library, including ones added later.
- `ignore` — skipped entirely. Currently `Tests/` (a lua5.1 harness, not game code),
  `Media/`, `.vscode/`, `.dsh-progress/`, `.git/`.
- `flavors` — `retail`, `classic`, `classic_era`, `forever` are the only valid names (they map
  to the WoW install folders). This addon targets all four.
- `globals.write` — limited to the `SCHOOL_MASK_*` compatibility shim, the only globals the
  addon writes.
- **Do not set `addonRoot`.** A `"."` value silently breaks resolution of the relative
  `library`/`ignore` patterns, so everything including Ace3 gets linted.

## 3. Non-negotiable rules for this addon

1. **Never disable a diagnostic with a comment.** No `---@diagnostic disable`. If the analyzer
   cannot prove a thing, change the code or the contract until it can. Suppressing a
   `secret-*` finding would ship a runtime error.
2. **Combat source is chosen by client family.** Forever (Camelot, interface 16001) and
   Midnight are restricted: `UNIT_COMBAT` is the only permitted number source and
   `COMBAT_LOG_EVENT_UNFILTERED` must never drive damage there. Era/TBC/Wrath/MoP use CLEU.
3. **Secret contract.** The `UNIT_COMBAT` amount is `SecretValue = true`: pass it to
   `FontString:SetText` by identity. No arithmetic, comparison, concatenation or
   `string.format`. `type(x) == "string"` is not a secrecy test. An amount is never cached —
   only the plain, post-guard answer may be.
4. **Client API shapes are fixed** (verified in `/home/sam/wow-ui-source`, `origin/forever`):
   `issecretvalue(value) -> bool`, `canaccessvalue(value) -> bool`, `UnitIsUnit(u1,u2) -> bool`,
   `UnitIsDead(unit) -> bool`, `UnitGUID(unit) -> WOWGUID (nilable)`. Do not invent extra
   returns on the client APIs; extra returns belong to this addon's own helpers and must be
   annotated.
5. **Classic clients ship the secret predicates too** (`origin/classic`, `classic_era`,
   `classic_anniversary` all document them). They are pass-through: they answer "accessible"
   and "not secret" without caring about taint. Do not write "absent on classic" fallbacks —
   they hide the guard from the analyzer and stop it proving the taint contract.
6. **Make helpers recognized guards instead of suppressing findings.** A helper that tests a
   secret value gets `@secret-guard <param> is-secret` (or `accessible` / `any-secret`) so the
   analyzer narrows through it; a context guard uses `@secret-clears` / `@secret-restriction-guard`
   / `@secret-satisfies`. That is how `isSecretValue` is annotated. Never a `@diagnostic` comment.
7. **Widget secret aspects.** Passing a secret to a widget setter is legal, but the widget's
   aspect becomes secret and its getters then return secrets — the analyzer does *not* flag
   them. `FontString:GetStringHeight` is `SecretWhenAnchoringSecret`, so after writing a secret
   amount the measured height is secret. Read geometry only under `canaccessvalue` and store a
   plain fallback; never feed a measured value into arithmetic (`powSizing`).
8. **The `defaults` table is the settings schema.** Every leaf must be reachable in
   `Options/Settings.lua`, and every key the render path reads must be declared. The harness
   fails if either direction breaks.
9. **Settings live in `db.profile`.** Never reintroduce `db.global`; profiles and
   `AceDBOptions` only work in the profile namespace.
10. **Hot paths never call restricted APIs per frame per number.** Cache the plain answer with
   a short TTL (see `fontStringTargetState` / `fontStringDeadState`).
11. **Versioning:** bump all seven `NameplateSCT*.toc` files and add a `CHANGELOG.md` entry.

## 4. File map

| Path | Responsibility |
| :--- | :--- |
| `NameplateSCT.lua` | DB defaults + migration, both combat paths, display, animation loop, filters, legacy AceConfig menu |
| `Options/Widgets.lua` | brand palette `W.C`, painting, text, switch, slider, cycle row, edit box, scroll page |
| `Options/Settings.lua` | the `/nsct` window: dashboard + seven pages, all writing `db.profile` |
| `Tests/harness/unit_combat_test.lua` | stubs the client and drives real events through the registration table |
| `Media/` | `logo.tga` (must stay 32-bit type-2 TGA) and the bundled Source Sans 3 fonts (OFL) |
| `Libs/` | vendored Ace3 + LibSharedMedia + LibEasing; declared as a `library` root |

Data flow: event → normalise per source → threshold/filter → text (secret pass-through where
applicable) → `DisplayText` (resolve plate or screen-area anchor) → `Animate` → `OnUpdate`
(cached target/death state, strata only on change).

## 5. Pitfalls that cost real time here

- `Frame:StopMoving` does **not** exist — it is `StopMovingOrSizing`.
- `AceEvent` has no `RegisterUnitEvent`; register unit-filtered events on a plain frame.
- `UnitIsDead` is `AllowedWhenUntainted` and `UnitIsUnit` is `SecretWhenUnitComparisonRestricted`:
  both can raise, and both were called bare inside `OnUpdate`. `UnitIsUnit` also has a
  precondition (`CanCompareUnitTokens`) and returns nothing when it fails — check
  `C_Secrets.CanCompareUnitTokens` first.
- `GetStringHeight` is `SecretWhenAnchoringSecret`: after `SetText(secret)` the height is
  secret, and comparing or dividing it raises. This is the subtlest Forever crash in the addon.
- A JSON `addonRoot` breaks `.wowluarc.json` relative patterns (see §2).
- The game copy at `.../Interface/AddOns/NameplateSCT` is a **separate copy**, not a link, and
  writing there is outside the workspace sandbox. The addon has also been observed *disabled*
  in `AddOns.txt`, which alone produces the "nothing shows up" symptom.
- `LoadAddOn`/`Settings` APIs do not exist on every client: guard with `pcall` rather than
  assuming the retail `Settings` table.

## 6. Deployment

```bash
rsync -a --exclude .git --exclude Tests --exclude .vscode \
  /home/sam/NameplateSCT/ \
  "/home/sam/Games/batttlenet2/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/NameplateSCT/"
```

Then `/reload`, and confirm the addon is enabled. The in-game dashboard (`/nsct`) reports the
active combat source, events received and numbers drawn — use it before theorising.

## 7. Durable memory

Mnemon memory space **NameplateSCT** holds the project documents (architecture reference, the
version update record covering 1.56 → 1.58, the Forever restoration write-up) and the durable
facts, including the wowlua-ls secret model and .wowluarc.json semantics. Recall it
before re-deriving the client-family rules or the settings contract.
