# NameplateSCT

## [1.66] (2026-11-14)

### Fixed: Only show heals cast by you, not random heals on everyone

With `showHealing` enabled on Forever, `UNIT_COMBAT` (`HEAL`) previously drew every heal on any visible unit—other healers, potions/regen, and enemies healing themselves. And on Classic/CLEU, enabling `Show damage you take` (`personal`) also let other players' heals on you leak through.

- **Player heal attribution on restricted clients (`UNIT_COMBAT`):** Track `UNIT_SPELLCAST_SENT`, `UNIT_SPELLCAST_START`, `UNIT_SPELLCAST_CHANNEL_START`, `UNIT_SPELLCAST_CHANNEL_STOP`, and `UNIT_SPELLCAST_SUCCEEDED` for your healing/helpful casts (`C_Spell.IsSpellHelpful` plus ground/AoE/channel healing spells). Unattributed heals and heals on hostile units (`UnitCanAttack`) are dropped (`"not your heal"`).
- **HoT and channel support:** Channeled heals stay authorized until `UNIT_SPELLCAST_CHANNEL_STOP` (capped at 12s), cast/instant/AoE heals open a 2s window, and captured friendly recipients (`target`, `mouseover`, self, pet, or accessible `targetName`) keep a 15s HoT window with the cast's healing spell ID.
- **CLEU incoming-heal guard:** `CombatFilter` now requires `playerGUID == sourceGUID` (or your own pet/guardian) for heals even when `personal` damage taken is on.
- **Settings label:** Renamed `showHealing` in `/nsct` to **"Healing you cast"** with a clear description.

## [1.65] (2026-11-14)

### Fixed: Blizzard's in-world combat numbers stayed on screen on Forever

1.64 turned off `Blizzard_CombatText` and four `_v2` CVars, but WoW Forever still drew in-world floating combat text from other active `floatingCombatText*` CVars (auto-attacks, pet melee/spell damage, healing, absorbs, spell mechanics, auras, and non-`_v2` aliases) and allowed other addons or post-login timing to flip them back without re-applying.

- **Expanded steered CVar list:** Suppress and restore all 24 `floatingCombatText*` boolean CVars in both `_v2` and non-`_v2` forms alongside `enableFloatingCombatText`, and skip recording/restoring CVars that do not exist (`GetCVar == nil`) on the active client.
- **Guarded against late overrides:** Watch all steered CVars case-insensitively in `CVAR_UPDATE`, and schedule deferred `C_Timer.After(0, ...)` re-application on `OnEnable`, `PLAYER_ENTERING_WORLD`, `SETTINGS_LOADED`, and `ADDON_LOADED` (`Blizzard_CombatText`).
- **Accurate dashboard status:** Updated `GetBlizzardFCTStatus()` to verify `GetBlizzardFCTState()` across all world-text CVars even when `Blizzard_CombatText` is already unregistered.
- **Midnight AceConfig fix:** Pass `"1"`/`"0"` strings when toggling `floatingCombatTextCombatDamage_v2` via the legacy Midnight options menu.

## [1.64] (2026-11-14)

### Fixed: turning off Blizzard's numbers did nothing visible

The addon was steering the wrong switch. Reading the client's own combat-text code
(`Blizzard_CombatText`, forever branch) explains the whole report:

- `CombatTextTypeInfo` gives **damage and healing no CVar at all** - `DAMAGE`, `DAMAGE_CRIT`,
  `SPELL_DAMAGE`, `HEAL`, `PERIODIC_HEAL` and friends are declared with `show = 1` and no
  `cvar` field. Only avoidance, block/absorb, auras, gains and combat-state text carry one.
- What actually stops everything is the master switch `enableFloatingCombatText`:
  `CombatText:OnLoad()` calls `CombatTextUtil.UpdateEventRegistration(self, GetCVarBool(master))`
  and the settings callback repeats it when the value flips. With "0" the frame never registers
  for `COMBAT_TEXT_UPDATE`, so `OnEvent` never runs.
- So the old code wrote `floatingCombatTextCombatDamage_v2`, read it back as "0", and the client
  never looked at it - a green check over numbers that were still drawing. That is why the
  dashboard reported success while the numbers stayed.

The addon now turns off `enableFloatingCombatText`, and then drives the same registration call
itself so the change lands in the current session instead of after the next reload. Turning the
setting off hands the player's own values back and re-registers the client's renderer. The
per-category CVars are still steered as a second line of defence for the classic families, whose
`FloatingCombatText` reads them directly.

- **The write itself never landed either.** `SetCVar` takes a cstring value, and a rejected call
  does not raise - so passing the number `0` changed nothing while the toggle still looked on.
  The value is written as a string, read back to prove it stuck, and retried through
  `C_CVar.SetCVar` when the legacy global refuses. A client that still refuses is reported on the
  dashboard ("this client refused the CVar change") instead of looking like a broken toggle.
- A CVar this client does not expose is now skipped rather than counted as a failure, so the
  failure count means "the client refused", not "this family has fewer switches".
- The setting is re-applied on `PLAYER_ENTERING_WORLD`, because a loading screen can reset it.
- It was silently skipped in Screen mode, so the toggle did nothing at all for screen-mode
  players. The setting is honoured in both modes now, because it is the player's explicit
  choice rather than something the addon should decide from the display mode.
- **The dashboard check asks the client, not the CVar.** It reads
  `CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE")`, so it is green only when the renderer
  actually stopped, and the failure hint names the reason ("the client is still drawing its own
  text", "enableFloatingCombatText still reads 1"). `Copy details` reports `fct=off` or
  `fct=on: <reason>`.
- **Turning the addon itself off hands the text back.** Muting the client while drawing nothing
  of our own would leave the player with no numbers at all, so suppression requires both
  *Addon enabled* and *Hide Blizzard's own numbers*.
- **The restore value can never be "0".** The record of what the switches held is per session;
  after a reload there is nothing to hand back, so a switch that already reads "0" is recorded
  at the client's own default instead. Un-ticking the setting gives the text back in every
  order of events, and a client setting the player made themselves is still left alone.
- **The setting stays authoritative.** If the game's own options (or another addon) turn
  Blizzard's text back on while the toggle is on, a `CVAR_UPDATE` handler puts it back. The
  echo of the addon's own write is recognised and skipped, so this is not a write loop.
- **A new dashboard check names another addon drawing numbers.** With *PlateSCT*, *ClassicFCT*
  or a similar addon loaded, "I turned Blizzard's off and they still show" is reported by name
  instead of looking like this toggle failing.

### Added: one switch per kind of hit

Every category the client reports now has a control instead of an implicit yes: **melee**,
**spell**, **ranged**, **damage over time**, **healing** and **pet damage**. A switched-off
category drops with its own recorded reason ("that kind of damage is off") so the dashboard
still answers why a number did not appear. Pet damage is marked *combat log only*: `UNIT_COMBAT`
reports the victim and the action but never the source, so no addon can tell a pet's hit from
yours on Forever.

### Added: healing

`HEAL` was dropped outright; it is drawn now, on the unit that received it, prefixed with `+` and
coloured with its own settings - a heal colour, an optional heal crit colour, and a heal / heal
crit animation pair. Heals on you follow the "show damage you take" placement but not its switch:
a heal is not damage, so it shows even with that setting off. On the combat-log clients the same
path covers `SPELL_HEAL` and `SPELL_PERIODIC_HEAL`.

### Fixed: colours now reach the screen on Forever

Colour was applied by wrapping the number in `|Cff...|r`. A secret amount may not be
concatenated, so on the restricted clients every colour setting was silently doing nothing - the
numbers were plain white. Colour is applied with `FontString:SetTextColor` now, from plain
numbers worked out before the text is written, so school colours, the normal-hit colour, the crit
colour, the miss colours and the heal colours all work on every client, and the shadow keeps its
own colour.

### Added: crits on the reduced clients

`UNIT_COMBAT` carries the same flag Blizzard's own combat feedback reads (`CRITICAL`, `CRUSHING`,
`GLANCING`), so crit colour, crit sizing and the crit animation are no longer combat-log-only.
They were previously disabled on Forever because the old code never looked at that flag.

### Added: where numbers about you are mounted

*Numbers about you* (damage you take, heals on you) can be mounted to the **screen area** or to
**your unit frame**, so they rise from your player frame the way PlateSCT's Incoming area does
when it is dragged over it. The *On you* offsets apply in both cases, and a unit frame the client
is not showing falls back to the screen instead of dropping the number.

### Scope: what the switch really turns off

`enableFloatingCombatText` is the whole renderer, so the answer is *everything* Blizzard draws:

- damage of every kind - melee, spell, ranged, periodic, and **pet damage** (a pet's hit is an
  ordinary damage event on the mob's unit)
- **healing**, absorbs, blocks and resists
- misses, dodges, parries, evades, immunes, deflects
- mana/energy/rage gains, honour and reputation changes, auras, reactives, combo points,
  entering and leaving combat, low-health and low-mana warnings

The consequence has to be said plainly: the addon draws **damage only** - `HEAL` and `ENERGIZE`
have always been dropped - so with the switch on there are no heal numbers anywhere, yours or
anyone else's. That is the client's design, not a gap in the toggle: on Forever a message
category with no CVar cannot be silenced on its own, and the only switch below "everything" is
"everything". Untick *Hide Blizzard's own numbers*, or disable the addon, and Blizzard's text
comes back as it was.

On the classic families it is finer-grained: those clients read
`floatingCombatTextCombatHealing` and friends directly, so the same toggle steers the categories
this addon replaces (damage, DoTs, avoidance, block/absorb) and leaves healing, gains, auras and
loot text alone.

### Changed: spell icons are off by default

Spell icons made a first install noisier than the numbers themselves. **Show spell icons** now
starts off, and an existing profile is moved over **once**, recorded on the saved variable, so a
player who turns them back on afterwards keeps them.

### Fixed: damage to you could still draw

Damage you take can reach `UNIT_COMBAT` under an alias that points at you rather than the
`player` token: while a mob is hitting you, your target's target *is* you. That token was not
treated as personal, so in screen mode it was drawn on the outgoing side even with **Show damage
you take** off. Any token the client compares equal to the player is promoted to the player
now, which puts it under the same setting, on the incoming side, and in the same duplicate
bucket. Damage to you stays off by default.

### Clarified: what "off-target" means

It is literal: *not the unit you currently have targeted*, not "my target's target". A hit on
any other mob's plate is drawn with the off-target size, opacity and stratum; your current
target keeps the normal look. `UnitIsUnit(unit, "target")` answers the question, and when the
restricted client refuses to compare, the number is kept rather than hidden.

### Tests

273 checks (was 189): the master switch goes off and the client's own renderer is unregistered,
a combat-text tick draws nothing while the setting is on, a CVar that reads "0" while the
renderer is still registered is reported as **not** stopped (the 1.64 green-check bug, pinned),
re-applying re-asserts the registration without relying on the client's settings callback,
turning the setting off restores the player's values and the renderer, a record lost to a reload
still hands the text back, a client setting the player made themselves is left alone, turning the
addon off hands the text back and turning it on mutes it again, a CVar the client does not expose
is not counted, unrelated CVars are left alone, a refused write is counted while the other
switches still change and the renderer still stops, the failure count clears on a clean pass, the
status helper answers from the client rather than from the addon's write, another loaded
number-drawing addon is named, each kind of hit is proved to obey its own switch, a heal draws
with a + and the heal colour, a heal crit uses the heal crit colour, healing off records its
reason, a `CRITICAL` flag drives the crit colour, size and animation on the reduced client, and
numbers about you mount to the unit frame or the screen as the setting says. Damage to you is
still dropped by default even when it arrives under a self-pointing alias. The test doubles for `SetCVar` and for `CombatText` model the real client:
non-string values are rejected, a named CVar can be refused, and the frame only counts a number
while it is registered.

## [1.63] (2026-11-14)

### Fixed: the page scrolled the wrong way

A wheel-up notch moved the page down and a wheel-down notch moved it up. The offset sign was
inverted; wheel-up now scrolls toward the top of the page.

### Fixed: page content ran past the bottom of the window

The page viewport is shorter than a page, and a plain frame does not clip its children, so rows
drew straight over the window edge and into the game world. Every page viewport now clips its
content (`SetClipsChildren`), so a row that does not fit is cut at the viewport edge instead of
escaping the window.

### Fixed: the window called a Forever client "Classic"

`isForever` and `isMidnight` were file locals and were never published on the addon table, so
`clientLabel()` fell through to "Classic" and any UI-side client decision was made with nil. Both
are exported now. The combat path and the CVar branch were unaffected - they use the locals - but
the header, the footer and the dashboard tiles were wrong on the client this addon exists for.

### Scrollbar

The gutter was 3px of near-invisible line on a dark surface. It is 4px with a visible track, a
32px minimum thumb and the same clamped travel.

### Visual

Toggle and select labels are centred on the same line as their control, instead of hugging the
top of the row while the switch or value button sits 12px lower.

### Guard: no shared font objects

The window and the render path set fonts per region only, never on a Blizzard font object
(`GameFontNormal:SetFont`) and never by assigning `STANDARD_TEXT_FONT`. Writing either repaints
every frame in the client that shares it - action bars, chat, tooltips. A static pin now fails
the build if such a write appears in any source file, red-proved by adding a dead branch that
does it.

### Tests

189 checks (was 182): the client identity is exported and the window labels it "Forever", every
page viewport clips, a wheel-down notch moves the content down while wheel-up returns it, and
no source line writes a shared font object.

## [1.62] (2026-11-14)

### Settings window: 1200x800, scaled to fit

- The window is designed at 1200x800 and scales itself down (never below 60%) on a smaller
  screen, so it cannot run off the edge of a laptop display.
- Every row carries a hairline and a hover fill, so wide rows stay scannable.

### New: settings search

The title bar has a search box. Typing switches to a Search page and shows every matching
setting as the real control - one live row per setting, created the first time it matches and
only moved and shown afterwards, so typing cannot leak frames. A query that matches nothing says
so; Escape clears the box and returns to the page the search started from.

### New: colour picker

Colour settings keep the hex box and gain a swatch that opens a 24-colour palette in the same
single menu every other selector uses - still exactly one popup in the addon.

### New: backup

A Backup page exports the profile as a plain `path=value` text block (select it, Ctrl+C) and
imports one back. The format is text and is never executed: import only writes keys that exist
in the schema, coerces each to the type the setting actually holds, and reports how many lines
were applied and refused. Multiline filter lists survive the round trip.

### Diagnostics: more sensitive, and in the window

- Every early return in both combat paths records why a hit was dropped: under the threshold,
  off-target text off, no nameplate, target-of-target, animation disabled, healing, filters,
  misses off, addon disabled, secret values, personal only.
- New counters: misses drawn, duplicates collapsed, secret amounts, client refusals, active and
  pooled FontStrings, last draw time, and whether the event source is subscribed.
- The dashboard runs six automatic checks (enabled, source subscribed, nameplates visible,
  events in the last 15 seconds, numbers in the last 15 seconds, Blizzard text not doubling),
  lists the counters, and names the last drop reason with its count.
- The shadow controls are also on the dashboard, beside the quick settings.

### Performance

- A slider drag used to refresh all eighty controls every frame. Slider changes are throttled to
  one refresh per 100 ms; toggles still refresh immediately.

### Tests

182 checks (was 145): drop reasons and counters, the dashboard status line, search (match, row
reuse, no match, Escape), the palette writing the picked hex, window size and fit scale, and
export/import including unknown keys, multiline values and numeric settings whose default is a
string.

## [1.61] (2026-11-14)

### New: configurable text shadow

`Text shadow` used to switch on the client's own `SetShadowOffset`, a fixed 1px copy with no
size, distance, angle or colour. Every number now carries its own shadow FontString:

- **size** - 50% to 200% of the number's own size
- **distance** - 0 to 12 px
- **angle** - 0 to 360 degrees, 315 being the down-right direction the old shadow used
- **opacity** and **colour** (hex)

Exactly one shadow is drawn: while the custom one is on, the client's offset copy is switched
off. Defaults (off, 100%, 1.5 px, 315, black) reproduce the previous 1px black shadow exactly,
so enabling it changes nothing until a slider moves. A secret amount is passed to both
FontStrings by identity and never formatted, and the shadow fades with the text because the
animation drives both alphas.

### New: live preview

The Appearance page draws the number in the current font, outline, size and colour - twice:
the target style and the smaller, faded off-target style - with the shadow applied. It updates
as you change a setting, so the shadow can be tuned by looking at it.

### Default font

An unknown or missing font falls back to the client's own default (`STANDARD_TEXT_FONT`)
instead of a hardcoded FRIZQT path, which has no glyphs on CJK and Cyrillic clients.

### Off-target numbers: verified

A hit on a mob that is not your target uses the off-target size and opacity and one stratum
lower, exactly as before; turning *Show text that is not on your target* off drops it entirely.
Both are now pinned by tests on the real event path, including the animation opacity.

### README

Rewritten as a download page: what the addon does, compatibility table, install steps, first
run, the eight settings pages, the shadow table, filters, off-target behaviour, FAQ, and the
quality bar. Badges and the addon logo sit at the top.

### Tests

145 checks (was 124): shadow size, offset from distance and angle, colour, opacity, the fade
with the animation, secret pass-through to both sinks, off-target size and opacity,
off-target suppression, the live preview, and the default-font fallback.

## [1.60] (2026-11-13)

### Settings: every option audited, and the window fixed to match

Every control now declares the profile path it owns, and the harness proves three things
instead of matching key names in the source text: each saved key has a control, each control
writes exactly its own key and nothing else, and each key is read by the addon. That audit
found four real defects:

- `personal` was read by the combat-log path and saved by the window, but was never declared
  in `defaults`, so it was always nil. It is declared, and the restricted path now honours it
  together with `displayOffTargetText`, which it had been ignoring.
- `modOffTargetStrata` was declared, saved and documented, and read nowhere. Off-target
  numbers now render one stratum under the target's while it is on; the explicit off-target
  stratum row greys out then, because it no longer applies.
- The 1.58 migration assigned a legacy nested table over the default subtree, so every key
  the old saved data did not mention became nil - the Numbers page then formatted a nil and
  threw. Nested tables are merged key by key now.
- A control whose parent option is off (`Off-target size` without a separate off-target
  look, icon options without icons, screen areas outside screen mode) is disabled instead of
  quietly saving a value nothing reads.

### Settings the restricted client cannot honour

Crit colour, overkill, absorbed amounts, personal-only, small-hit scaling and the crit /
auto-attack animations come from the combat log, which Forever and Midnight do not expose.
Those rows stay on their page but are disabled and say "combat log only", rather than
looking functional and doing nothing.

### One selection menu

Selection rows cycled one value per click, which is workable for two values and unusable for
a font list. They open a menu now. One menu object and one click-catcher exist for the whole
addon, so a second menu can never appear: opening another selection re-anchors the same
frame, and picking, clicking outside, switching page or hiding the window closes it. This is
a structural guarantee, and the harness counts the menu objects.

### Settings window

- Page header (title and one-line purpose) and a footer status line; a rejected value is
  explained there and the field itself turns red instead of a chat message.
- Dashboard is a status surface: four KPI tiles, a one-line health strip with a coloured
  state dot, an action bar (test number, test on you, reset counters, copy details), then the
  quick settings.
- Sidebar is grouped (Overview / Display / Data / About) with the addon version at the bottom.
- `Reset page` restores one page to its defaults; the profile reset on About needs a second
  click, because it is destructive and immediate.

### Tests

124 checks (was 99): the control audit in both directions, the write-isolation check, the
single-menu invariant (including "clicking the open row closes it"), per-page reset, hex
validation, and the disabled client-only rows.

## [1.59] (2026-11-13)

### Fixed: `/nsct` opened the Blizzard panel instead of the dashboard

`AceAddon:NewAddon` keeps the addon table in its own registry and never publishes it under the
addon's name. `Options/Widgets.lua` and `Options/Settings.lua` both look the object up as
`_G.NameplateSCT`, so both returned at their first statement: no palette, no window, and
`/nsct` fell through to the AceConfig panel. The addon now publishes itself, and the opener
reports a missing or throwing window instead of silently opening the wrong one.

The harness had been hiding this. Its AceAddon stub published the global itself, so the options
modules loaded in tests while they could never load in game. The stub no longer does that, and a
check now asserts the addon publishes itself.

### Fixed: `C_NamePlate.GetNamePlateForUnit` error on target-of-target

`UNIT_COMBAT` on Forever reports tokens such as `targettarget`, and the client raises
`Target-of-target unit tokens are not allowed for this call`. The token reached the plate lookup
on all three display paths. Derived tokens are now recognised before the call: a
nameplate-anchored draw is skipped for them (a target-of-target has no plate the client will
resolve) while screen mode still draws them, and a plain `target` token keeps working. The
harness stub raises the same error, so a regression fails the suite instead of a player's chat.

### Changed: the Blizzard AddOns section is a launcher

The legacy AceConfig tree duplicated every setting in one very tall page. The client's options
canvas does not scroll it, so the section ran off the bottom of the window and nothing in it
could be reached. It now holds the "enemy nameplates are disabled" warning, one **Open
NameplateSCT dashboard** button and a line pointing at the window. The duplicated **Filters**
subcategory is gone (the dashboard owns those two lists), and the colour, strata, position and
truncation maps that only the old tree used were deleted. AceDBOptions' Profiles page is still
registered there.

### Tests

92 checks (was 77): target-of-target tokens raise in the client stub and must not reach it in
either display mode, `/nsct` must open the dashboard and not the Blizzard panel, the AddOns
panel must expose a button that opens the dashboard and stay a launcher, and the addon must
publish itself as `_G.NameplateSCT`.

## [1.58] (2026-11-13)

### AceDB: settings now live in the profile, so profiles work

Settings were stored in AceDB's `global` namespace - one table shared by every profile and
character, which made AceDB profiles meaningless. They now live in `profile`, and a one-time
migration copies the old values across:

- Runs once, marked on the saved variable (`settingsNamespace = "profile"`), so switching or
  resetting a profile cannot resurrect old values.
- Copies nested tables by value, so the profile never shares a table with the legacy data.
- Keeps the old `global` table on disk as a recovery copy; it is simply no longer read.

`AceDBOptions-3.0` is now embedded and its Profiles page is registered in the legacy options
panel (About -> "Manage profiles"), giving new/copy/delete/reset without new code.

### Performance

- The animation loop asked the client for `UnitIsUnit` and `UnitIsDead` for **every** number
  on **every** frame. Both are restricted on Forever, so they were also a throw risk. Both are
  now cached per number with a 0.2 s / 0.25 s TTL: roughly 9 client calls per second per
  number instead of ~180.
- Cached values are plain booleans produced *after* the secrecy gate. A secret or refused
  answer collapses to `false` before it is stored, so no secret is ever held, compared or
  formatted later. The harness asserts the cached values are untainted.
- `SetFrameStrata` is only called when the stratum actually changes, instead of every frame
  for every number.
- Font paths are memoised (was a LibSharedMedia lookup per number, per event) and the cache is
  cleared when the font setting changes.
- Settings rows resolve their dotted path once instead of splitting it on every refresh.
- The dashboard refresh ticker is only attached while the window is shown; it used to run an
  `OnUpdate` forever.

### Reliability

- `canaccessvalue` / `issecretvalue` are called directly again. They are documented on every
  supported client (live, classic, classic_era, classic_anniversary and forever) and classic
  clients pass them through - answering "accessible" / "not secret" without caring about
  taint. Wrapping them hid the guard from the type checker and stopped it proving the taint
  contract.
- Helper return shapes now match the client contracts exactly: `UnitIsUnit` and `UnitIsDead`
  return a single bool, `UnitGUID` stays nilable, and a refused `issecretvalue` is read as
  "secret" rather than "not secret".
- **`GetStringHeight` is `SecretWhenAnchoringSecret`.** Once a FontString holds a secret amount
  its measured height is secret, and that height fed arithmetic in `powSizing` - the old
  `startHeight <= 0` comparison would have raised on every Forever number. The height is now
  read only under `canaccessvalue`, falling back to the requested font size.
- `UnitIsUnit` has a documented precondition (`CanCompareUnitTokens`) and returns nothing when
  it fails; that precondition is checked first, which also removes the nil return.
- `isSecretValue` carries `@secret-guard value is-secret`, so callers that guard with it narrow
  correctly instead of the helper hiding the guard from the analyzer.
- A zero animation duration is recycled instead of dividing by zero.
- `C_NamePlate` is never indexed unguarded.
- The window's `OnDragStop` uses `StopMovingOrSizing` (see 1.57).

### Tests

- Harness grew to 71 checks: the settings migration (values, false values, nested tables,
  copy-not-share, one-time marker, no second run), the untainted cache contract under a
  secret-returning `UnitIsUnit`/`UnitIsDead`, and the animation tick itself.

## [1.57] (2026-11-13)

### Settings window: brand palette and logo

- The dashboard palette is now sampled from the addon's own logo instead of borrowed from a
  reference addon: cool near-black surfaces, the logo orange as the single accent, logo gold
  for counters, logo red for danger.
- `logo.tga` was an 8-bit palettized TGA, which the client cannot decode, so the addon icon
  was blank. It is now a 512x512 32-bit uncompressed TGA (verified by a harness pin), and it
  is used in the window header and the About page.

### Screen mode

- New `Display mode`: Nameplates or Screen. Screen mode anchors every number to one of two
  configurable areas (outgoing / incoming) instead of a nameplate, so numbers can be read
  without nameplates enabled - the layout PlateSCT offers.
- Screen mode draws from `UNIT_COMBAT` even when a unit has no nameplate frame.

### Settings: complete and wired

- Every one of the 74 saved keys is reachable in the window; a harness pin now fails the build
  if a new default is added without exposing it.
- Pages scroll, so each page can hold the full set: Dashboard, General, Numbers, Appearance,
  Animations, Position, Filters, About.
- Added the settings that were previously only in the AceConfig panel or missing entirely:
  hit filtering and size modifiers, crit/miss colours and hex fields, icon options, strata,
  offsets/variance, screen areas, fireworks tuning, and text opacity.
- Two keys the render path already read (`removeBorder`, `showIconOnly`) were missing from the
  schema; both are now declared and exposed, as are the new `minDamage`, `showMisses`,
  `hideBlizzardFCT` and `screen` keys.

### Features taken from the reference addon

- `Ignore hits below` absolute damage floor, applied on both combat paths.
- `Show misses and avoidance` toggle, honoured by both combat paths.
- `Hide Blizzard's own numbers`: steers only the one combat-text CVar this addon owns, and
  only while nameplate mode is active, so the two cannot double up.

### Fixed (found by wowlua_ls)

- `Frame:StopMoving` does not exist in the client API (it is `StopMovingOrSizing`), so the
  settings window threw on every drag release. Now uses the real method.
- Spell attribution never registered: the code called `self:RegisterUnitEvent(...)` inside a
  `pcall`, but AceEvent exposes only `RegisterEvent`/`RegisterMessage`, so the call always
  failed silently. It now registers on a dedicated frame, and is unregistered on disable.
- Colour parsing no longer does arithmetic on a nil `tonumber` result, `GetStrata` can no
  longer hand nil to `SetFrameStrata`, a nil `destGUID` can no longer be used as a table key,
  and the thousands separator survives a value the pattern cannot match.

### Dependencies

- Bundled Ace3 updated to the current release set (47 library files across 13 directories).
  The `embeds.xml` load chain was re-verified end to end: 55 live Script/Include targets all
  resolve. `AceConfigDropdown-3.0` and `AceDBOptions-3.0` are referenced only in comments, so
  nothing is missing; `AceDBOptions-3.0` ships but is not embedded and never loads.

### Editor support

- `.wowluarc.json` is now correct for this project: `Libs/` is declared as a library root, so
  every vendored library is scanned for types with diagnostics suppressed (47 files), `Tests/`
  and `Media/` are ignored, and `globals.write` lists the `SCHOOL_MASK_*` shim instead of a
  leftover from another addon.
- `wowlua_ls check .` reports zero errors and zero warnings.

### Tests

- Harness grew to 53 checks: screen mode without a nameplate, the damage floor, the miss
  toggle, palette values, TGA header validity (type 2, 32-bit, power-of-two width) and full
  settings coverage.

## [1.56] (2026-11-13)

### Fixed: no numbers ever appeared on WoW Forever

The addon subscribed to `COMBAT_LOG_EVENT_UNFILTERED` and, when the client reported secret
value restrictions, it silently skipped that registration and registered nothing else. Forever
always reports restrictions on, so the addon loaded, saved its settings and drew nothing - with
no Lua error to explain it.

- Forever/Midnight now use `UNIT_COMBAT`, the only damage source a restricted client permits,
  while unrestricted clients keep the combat log path.
- Hits are anchored by resolving the unit token to its nameplate frame, so no secret `UnitGUID`
  key is ever used; duplicate reports of one hit on another alias of the same plate are collapsed.
- Secret damage amounts are passed to the FontString by identity, skipping every numeric
  comparison and formatting step; misses still render as words and school colours still apply.
- Spell attribution comes from the player's and pet's own `UNIT_SPELLCAST_SUCCEEDED` events.
- Added live diagnostics counters (`events`, `drawn`, path) that the dashboard reads.
- Hardened the animation loop: `UnitIsDead` is `AllowedWhenUntainted` on Forever and was
  called bare inside `OnUpdate`, where a raise would error every frame and stop all drawing;
  an unanswerable query now reads as "alive" and the number keeps animating.

### Added: new settings window

- New dashboard window opened by `/nsct`, adapted from PlateSCT's "Ember" settings design:
  warm near-black surfaces, one gold accent, Source Sans 3 typography (OFL, bundled), left
  navigation and quiet content pane.
- Dashboard reports client, combat source, events received and numbers drawn, and explains the
  likely cause when a counter stays at zero; also offers test numbers and a diagnostics copy.
- Pages: General, Appearance, Animations, Filters, About - all writing straight to the AceDB
  profile. The existing AceConfig/Blizzard panel is left in place as a fallback.

### Changed

- Base `NameplateSCT.toc` now declares interface `16001` as well; the client selects a TOC by
  interface value, and every other addon in this install lists it on the base TOC.
- Fixed the `fontShadow` default being written while the render path read `textShadow`, which
  made the text-shadow toggle a no-op.
- Fixed one Blizzard combat-text CVar read/write still using the pre-Midnight name.

### Tests

- Added `Tests/harness/unit_combat_test.lua` (`bash Tests/run.sh`): stubs the client API and
  proves the event source, the render path, alias de-duplication, secret pass-through, miss
  text, static hazard pins, and that every settings page builds. Restoring the old
  registration logic fails 11 of its checks, including "a FontString received text".

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
