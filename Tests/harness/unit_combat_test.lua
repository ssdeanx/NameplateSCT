--------------------------------------------------------------------------------
-- Tests/harness/unit_combat_test.lua
--------------------------------------------------------------------------------
-- Proves the Forever/Midnight combat path end to end without a game client:
-- the addon must subscribe to UNIT_COMBAT (never CLEU alone) when the client reports
-- secret restrictions, and a hit must reach FontString:SetText with the amount intact.
--
-- Run: lua5.1 Tests/harness/unit_combat_test.lua

local checks, failures = 0, 0

local function ok(condition, name, detail)
	checks = checks + 1
	if condition then
		print(("PASS  %s"):format(name))
	else
		failures = failures + 1
		print(("FAIL  %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end

local function eq(actual, expected, name)
	ok(actual == expected, name, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

--------------------------------------------------------------------------------
-- WoW API stubs
--------------------------------------------------------------------------------

local createdFontStrings = {}
local registeredEvents = {}
local createdFrames = {}

local function NewRegion(kind)
	local region = { _kind = kind }
	-- The main number sets NSCTText before writing; the shadow region never does, so this
	-- records the number's own FontString even though the shadow writes after it.
	region.SetText = function(self, value)
		self._text = value
		_G.__lastFontString = self
		if self.NSCTText ~= nil then _G.__lastNumberFontString = self end
	end
	region.GetText = function(self) return self._text end
	region.SetFormattedText = function(self, value) self._text = value end
	region.SetFont = function(self, path, size, flags) self._font = { path = path, size = size, flags = flags } end
	region.GetFont = function(self)
		local font = self._font or {}
		return font.path or "font", font.size or 13, font.flags or ""
	end
	region.SetTextHeight = function(self, height) self._textHeight = height end
	region.SetShadowOffset = function(self, x, y) self._shadowOffset = { x, y } end
	region.SetShadowColor = function() end
	-- tests can force a secret measurement (GetStringHeight is SecretWhenAnchoringSecret)
	region.GetStringHeight = function() return _G.__stringHeight or 12 end
	region.SetPoint = function(self, ...)
		local a = { ... }
		self._point = { a[1], a[4], a[5] }
	end
	region.SetAllPoints = function() end
	region.ClearAllPoints = function() end
	region.SetAlpha = function(self, value) self._alpha = value end
	region.GetAlpha = function() return 1 end
	region.SetDrawLayer = function() end
	region.SetParent = function(self, parent) self._parent = parent; return self end
	region.GetParent = function(self) return self._parent end
	region.Show = function(self) self._shown = true end
	region.Enable = function(self) self._enabled = true end
	region.Disable = function(self) self._enabled = false end
	region.IsEnabled = function(self) return self._enabled ~= false end
	region.RegisterForClicks = function() end
	region.SetShown = function(self, shown) self._shown = shown and true or false end
	region.Hide = function(self) self._shown = false end
	region.IsShown = function(self) return self._shown ~= false end
	region.SetSize = function(self, w, h) self._w, self._h = w, h end
	region.SetScale = function(self, value) self._scale = value end
	region.SetClipsChildren = function(self, value) self._clipsChildren = value end
	region.GetWidth = function(self) return self._w or 0 end
	region.GetHeight = function(self) return self._h or 0 end
	region.SetWidth = function(self, w) self._w = w end
	region.SetHeight = function(self, h) self._h = h end
	region.SetTexture = function(self, texture) self._texture = texture end
	region.SetTexCoord = function() end
	region.SetVertexColor = function(self, r, g, b, a) self._color = { r, g, b, a } end
	region.SetColorTexture = function(self, r, g, b, a) self._color = { r, g, b, a } end
	region.SetJustifyH = function() end
	region.SetJustifyV = function() end
	region.SetWordWrap = function() end
	region.SetTextColor = function(self, r, g, b, a) self._textColor = { r, g, b, a } end
	region.SetNonSpaceWrap = function() end
	region.SetShadow = function() end
	region.SetTextInsets = function() end
	region.SetMaxLetters = function() end
	region.SetMaxLines = function() end
	region.SetMultiLine = function() end
	region.SetAutoFocus = function() end
	region.ClearFocus = function() end
	region.SetFocus = function() end
	region.HasFocus = function() return false end
	region.SetOrientation = function() end
	region.SetMinMaxValues = function(self, min, max) self._min, self._max = min, max end
	region.SetValueStep = function() end
	region.SetObeyStepOnDrag = function() end
	region.SetThumbTexture = function() end
	region.SetValue = function(self, value) self._value = value end
	region.GetValue = function(self) return self._value or 0 end
	region.SetHorizontalScroll = function() end
	region.SetVerticalScroll = function() end
	region.CreateTexture = function() return NewRegion("texture") end
	region.CreateFontString = function(self)
		local fs = NewRegion("fontstring")
		fs._parent = self
		createdFontStrings[#createdFontStrings + 1] = fs
		return fs
	end
	return region
end

CreateFrame = function(frameType, name, parent)
	local frame = NewRegion(frameType)
	frame._name = name
	frame._scripts = {}
	frame._events = {}
	frame.SetScript = function(self, event, handler) self._scripts[event] = handler end
	frame.GetScript = function(self, event) return self._scripts[event] end
	frame.HookScript = function(self, event, handler) self._scripts[event] = handler end
	frame.SetFrameStrata = function() end
	frame.SetFrameLevel = function() end
	frame.RegisterEvent = function(self, event)
		self._events[event] = true
		registeredEvents[#registeredEvents + 1] = event
	end
	frame.RegisterUnitEvent = function(self, event) self._events[event] = true end
	frame.UnregisterAllEvents = function(self) self._events = {} end
	frame.UnregisterEvent = function(self, event) self._events[event] = nil end
	frame.RegisterForDrag = function() end
	frame.EnableMouse = function() end
	frame.SetMovable = function() end
	frame.SetClampedToScreen = function() end
	frame.SetToplevel = function() end
	frame.StartMoving = function() end
	frame.StopMoving = function() end
	frame.Raise = function() end
	frame.SetParent = function() end
	frame.SetID = function() end
	frame.AddLine = function() end
	frame.SetFading = function() end
	frame.EnableMouseWheel = function() end
	frame.SetBackdrop = function() end
	frame.SetBackdropColor = function() end
	frame.SetBackdropBorderColor = function() end
	createdFrames[#createdFrames + 1] = frame
	if name and _G then _G[name] = frame end
	return frame
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
UISpecialFrames = {}

-- Client identity: Forever (Camelot), interface 16001.
WOW_PROJECT_ID = 18
WOW_PROJECT_CAMELOT = 18
WOW_PROJECT_MAINLINE = 1

GetBuildInfo = function() return "1.60.1", "1.60.1.70888", "Nov 13 2026", 16001 end
GetLocale = function() return "enUS" end
GetTime = function() return _G.__now or 0 end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GameFontHighlight = NewRegion("fontobject")
ChatFontNormal = NewRegion("fontobject")

-- Secret predicates: restrictions are ON, so hasSecretRestrictions is true. Values are
-- plain unless a test marks them.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
issecretvalue = function(value) return value == SECRET end
canaccessvalue = function(value) return value ~= SECRET end

C_Secrets = { HasSecretRestrictions = function() return true end }
C_CombatLog = { IsCombatLogRestricted = function() return true end }
local helpfulSpells = { [2061] = true, [774] = true }
C_Spell = {
	GetSpellTexture = function() return nil end,
	IsSpellHelpful = function(id) return helpfulSpells[id] == true end,
}

-- Nameplate anchors: a hit on "nameplate1" resolves to this frame.
local plateFrames = {}
C_NamePlate = {
	-- The client raises on target-of-target tokens; reproducing it here means a call
	-- site that forgets the guard fails the harness, not a player's chat frame.
	GetNamePlateForUnit = function(unit)
		if type(unit) == "string" and unit ~= "target" and string.sub(unit, -6) == "target" then
			error("bad argument #1 to '?' (Target-of-target unit tokens are not allowed for this call. - Usage: local nameplate = C_NamePlate.GetNamePlateForUnit(unitToken [, includeForbidden]))", 2)
		end
		return plateFrames[unit]
	end,
	GetNamePlates = function()
		local list = {}
		for unit in pairs(plateFrames) do list[#list + 1] = { name = unit } end
		return list
	end,
}

Enum = { Damageclass = {
	MaskPhysical = 0x1, MaskHoly = 0x2, MaskFire = 0x4, MaskNature = 0x8,
	MaskFrost = 0x10, MaskShadow = 0x20, MaskArcane = 0x40,
} }

SCHOOL_MASK_PHYSICAL = 0x1
SCHOOL_MASK_HOLY = 0x2
SCHOOL_MASK_FIRE = 0x4
SCHOOL_MASK_NATURE = 0x8
SCHOOL_MASK_FROST = 0x10
SCHOOL_MASK_SHADOW = 0x20
SCHOOL_MASK_ARCANE = 0x40

strsplit = function(separator, text)
	local out = {}
	for piece in string.gmatch(text or "", "([^" .. separator .. "]+)") do out[#out + 1] = piece end
	return unpack(out)
end

GameTooltip = {
	SetOwner = function() end, SetText = function() end,
	Show = function() end, Hide = function() end, AddLine = function() end,
}

function UnitGUID() return "Player-1-0000" end
-- Tests can name one unit that is the player's target; everything else stays off-target.
function UnitIsUnit(a, b)
	if _G.__unitIsTarget and a == _G.__unitIsTarget and b == "target" then return true end
	if _G.__unitIsSelf and a == _G.__unitIsSelf and b == "player" then return true end
	return false
end
function UnitIsDead(unit) return false end
function UnitExists(unit)
	if _G.__existingUnits then return _G.__existingUnits[unit] == true end
	return true
end
function UnitCanAttack(a, b)
	if _G.__hostileUnits and a == "player" then return _G.__hostileUnits[b] == true end
	return false
end
function UnitName(unit)
	if _G.__unitNames then return _G.__unitNames[unit] end
	return nil
end
-- CVars are a table now: the Blizzard combat-text family is steered, restored and checked by
-- name, so a single stubbed answer cannot prove any of it.
local cvarValues = { nameplateShowEnemies = "1" }
function GetCVar(name) return cvarValues[name] end
-- The client's binding takes a cstring and silently ignores anything else, and refuses
-- read-only/secure CVars the same way. Both behaviours are modelled so a numeric write (the
-- 1.63 bug) or an unverified write fails here instead of in game.
function SetCVar(name, value)
	if type(value) ~= "string" then return end
	if _G.__refuseCvar == name then return end
	cvarValues[name] = value
end

-- The client's actual combat-text renderer (Blizzard_CombatText, LoadOnDemand). This is the
-- piece 1.64 was missing: CombatTextTypeInfo gives DAMAGE, DAMAGE_CRIT, SPELL_DAMAGE and the
-- HEAL entries `show = 1` with no cvar, so no per-category CVar is ever consulted for them.
-- The only switch is the event registration driven by `enableFloatingCombatText`:
--
--   CombatText:OnLoad()  -> CombatTextUtil.UpdateEventRegistration(self, GetCVarBool(master))
--   settings callback    -> same call when the master flips
--
-- so the stub models exactly that: a frame that only draws when it is registered.
local combatTextFrame = { events = {} }
function combatTextFrame:RegisterEvent(name) self.events[name] = true end
function combatTextFrame:UnregisterEvent(name) self.events[name] = nil end
function combatTextFrame:UnregisterAllEvents() self.events = {} end
function combatTextFrame:IsEventRegistered(name) return self.events[name] and true or false end
function combatTextFrame:IsVisible() return true end
function combatTextFrame:UpdateDisplayedMessages() self.refreshes = (self.refreshes or 0) + 1 end
function combatTextFrame:OnEvent(event)
	if not self.events[event] then return end
	_G.__blizzardNumbers = (_G.__blizzardNumbers or 0) + 1
end
_G.CombatText = combatTextFrame
CombatTextUtil = {
	UpdateEventRegistration = function(frame, enable)
		if enable then
			frame:RegisterEvent("COMBAT_TEXT_UPDATE")
		else
			frame:UnregisterEvent("COMBAT_TEXT_UPDATE")
		end
	end,
}
function CombatText_UpdateDisplayedMessages() combatTextFrame:UpdateDisplayedMessages() end
-- One tick of the client's own combat text. Counts a number only while the frame is registered.
function _G.__drawBlizzardText() combatTextFrame:OnEvent("COMBAT_TEXT_UPDATE") end

-- Provided by AceGUI-3.0-SharedMediaWidgets at runtime; the AceConfig page table
-- dereferences it while the file loads.
AceGUIWidgetLSMlists = { font = { ["Friz Quadrata TT"] = "Friz Quadrata TT" } }

-- Libraries ----------------------------------------------------------------

local chatCommands = {}
local registeredOptions = {}

-- The client's options entry point. Stubbed so a fall-through to the Blizzard panel is
-- observable instead of silently doing nothing.
Settings = { OpenToCategory = function(name) _G.__openedCategory = name end }

local function deepcopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = deepcopy(item) end
	return copy
end

LibStub = function(name, silent)
	if name == "AceAddon-3.0" then
		return {
			NewAddon = function(_, addonName)
				local addon = { _name = addonName }
				addon._events = {}
				addon.RegisterEvent = function(self, event)
					self._events[event] = true
					registeredEvents[#registeredEvents + 1] = event
				end
				addon.RegisterUnitEvent = function(self, event)
					self._events[event] = true
					registeredEvents[#registeredEvents + 1] = event
				end
				addon.UnregisterAllEvents = function(self) self._events = {} end
				addon.RegisterChatCommand = function(_, command, method)
					chatCommands[command] = method
				end
				addon.Print = function() end
				addon.Enable = function(self) if self.OnEnable then self:OnEnable() end end
				addon.Disable = function(self) if self.OnDisable then self:OnDisable() end end
				-- No global is published here: AceAddon does not publish one, and faking it
				-- would hide a missing _G.NameplateSCT from every check below.
				return addon
			end,
		}
	elseif name == "LibEasing-1.0" then
		-- every curve the addon actually calls; each yields its start value, which is
		-- enough to drive the animation loop without modelling the easing maths
		return {
			InQuad = function(_, start) return start end,
			InExpo = function(_, start) return start end,
			InQuint = function(_, start) return start end,
			OutQuint = function(_, start) return start end,
			OutQuad = function(_, start) return start end,
			InOutQuad = function(_, start) return start end,
		}
	elseif name == "LibSharedMedia-3.0" then
		return {
			Fetch = function(_, _, value)
				if value == "Friz Quadrata TT" or value == "Arial Narrow" then return value end
				return nil
			end,
			-- Two fonts, like a real install: a one-entry list cannot prove a selection.
			List = function() return { "Friz Quadrata TT", "Arial Narrow" } end,
			IsValid = function(_, _, value) return value == "Friz Quadrata TT" or value == "Arial Narrow" end,
		}
	elseif name == "AceLocale-3.0" then
		-- AceLocale returns the translation table itself: L["Missed"] == "Missed".
		return { GetLocale = function()
			return setmetatable({}, { __index = function(_, key) return key end })
		end }
	elseif name == "AceDB-3.0" then
		return {
			New = function(_, _, defaults)
				_G.__defaults = defaults
				return {
					profile = deepcopy(defaults.profile),
					ResetProfile = function() end,
				}
			end,
		}
	elseif name == "AceDBOptions-3.0" then
		return {
			GetOptionsTable = function(_, db)
				ok(db ~= nil, "AceDBOptions is handed a database")
				return { type = "group", name = "Profiles", args = {} }
			end,
		}
	elseif name == "AceConfigRegistry-3.0" then
		return { RegisterOptionsTable = function(_, appName, table) registeredOptions[appName] = table end }
	elseif name == "AceConfigDialog-3.0" then
		return { AddToBlizOptions = function() return "NameplateSCT" end }
	elseif name == "Masque" then
		if silent then return nil end
		return {}
	end
	error("unexpected library: " .. tostring(name))
end

--------------------------------------------------------------------------------
-- Load the addon
--------------------------------------------------------------------------------

local addonPath = (arg and arg[1]) or "NameplateSCT.lua"
local chunk = assert(loadfile(addonPath))
chunk("NameplateSCT")

-- The options modules find the addon as _G.NameplateSCT. AceAddon does not publish it, so
-- this is the addon's own job; if it stops doing it, the dashboard silently never exists.
local NS = _G.NameplateSCT
ok(NS ~= nil, "the addon publishes itself as _G.NameplateSCT")
ok(NS.hasCombatRestrictions == true, "Forever detected as a restricted client")

-- A v1.57-era saved variable: settings under the shared `global` namespace.
_G.NameplateSCTDB = {
	global = {
		enabled = true,
		yOffset = 22,
		font = "Friz Quadrata TT",
		textShadow = true,
		sizing = { smallHits = false },
	},
}

NS:OnInitialize()
NS:OnEnable()

-- Registration happens on initialize, and AceConsole calls NS[method] for the command.
ok(chatCommands["nsct"] == "OpenMenu", "/nsct is registered to the window opener",
	tostring(chatCommands["nsct"]))

--------------------------------------------------------------------------------
-- The regression: which event source got registered?
--------------------------------------------------------------------------------

local subscribed = {}
for _, event in ipairs(registeredEvents) do subscribed[event] = true end

ok(subscribed["UNIT_COMBAT"] == true, "UNIT_COMBAT is registered on a restricted client")
ok(subscribed["COMBAT_LOG_EVENT_UNFILTERED"] == nil, "CLEU is not the registered source on a restricted client")
ok(NS.diagnostics.path == "unit", "diagnostics report the unit-combat path")

-- Register the anchor plate before firing.

-- Dispatch through the registration table, the way the client does: an event that was
-- never registered never reaches its handler.
local function FireEvent(event, ...)
	if not (NS._events and NS._events[event]) then return false end
	local handler = NS[event]
	if handler then handler(NS, event, ...) end
	return true
end

local function FireCastEvent(event, ...)
	local cf = NS.castFrame
	if not (cf and cf._events and cf._events[event] and cf._scripts and cf._scripts.OnEvent) then
		return false
	end
	cf._scripts.OnEvent(cf, event, ...)
	return true
end

plateFrames["nameplate1"] = CreateFrame("Frame", "Plate1")

--------------------------------------------------------------------------------
-- A plain hit must render
--------------------------------------------------------------------------------

_G.__now = 100
createdFontStrings = {}
NS.diagnostics.drawn = 0
NS.diagnostics.events = 0

FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 1234, SCHOOL_MASK_FIRE)

ok(NS.diagnostics.events == 1, "one event counted")
ok(NS.diagnostics.drawn == 1, "one number drawn", NS.diagnostics.drawn)

local rendered
for _, fs in ipairs(createdFontStrings) do
	if fs._text ~= nil and fs._text ~= "" then rendered = fs._text break end
end

ok(rendered ~= nil, "a FontString received text")
ok(type(rendered) == "string" and rendered:find("1%.2k") ~= nil,
	"the amount reached the screen abbreviated by default", tostring(rendered))
ok(rendered and rendered:find("|Cff") == nil,
	"the text stays plain: colour is a FontString property, not an inline code", tostring(rendered))
local coloured
for _, fs in ipairs(createdFontStrings) do
	if fs._text ~= nil and fs._text ~= "" then coloured = fs._textColor break end
end
ok(type(coloured) == "table" and type(coloured[1]) == "number" and type(coloured[2]) == "number"
	and type(coloured[3]) == "number", "the number carries its colour on the FontString",
	coloured and tostring(coloured[1]))

-- Same hit with full-number styling must render the grouped digits.
NS.db.profile.truncateMethod = "NONE"
_G.__now = 150
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 1234, SCHOOL_MASK_FIRE)
local fullText
for _, fs in ipairs(createdFontStrings) do
	if type(fs._text) == "string" and fs._text ~= "" then fullText = fs._text end
end
ok(fullText ~= nil and fullText:find("1,234") ~= nil,
	"full-number style renders grouped digits", tostring(fullText))
NS.db.profile.truncateMethod = "WESTERN"

--------------------------------------------------------------------------------
-- The same hit repeated on another alias must be collapsed
--------------------------------------------------------------------------------

NS.diagnostics.drawn = 0
_G.__now = 100.01
plateFrames.target = plateFrames["nameplate1"]
FireEvent("UNIT_COMBAT", "target", "WOUND", "", 1234, SCHOOL_MASK_FIRE)
eq(NS.diagnostics.drawn, 0, "the same hit on an alias plate is not drawn twice")

-- A genuinely later hit still draws.
_G.__now = 100.5
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 4321, SCHOOL_MASK_FIRE)
eq(NS.diagnostics.drawn, 1, "a later hit draws again")

--------------------------------------------------------------------------------
-- A secret amount is passed through untouched (no arithmetic can survive it)
--------------------------------------------------------------------------------

NS.diagnostics.drawn = 0
_G.__now = 200
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", SECRET, SCHOOL_MASK_SHADOW)

eq(NS.diagnostics.drawn, 1, "a secret amount still draws")
local passedThrough = false
for _, fs in ipairs(createdFontStrings) do
	if fs._text == SECRET then passedThrough = true end
end
ok(passedThrough, "the secret value reaches FontString:SetText by identity, never formatted")

--------------------------------------------------------------------------------
-- Misses render as words
--------------------------------------------------------------------------------

NS.diagnostics.drawn = 0
_G.__now = 300
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "DODGE", "", 0, 0)

local missText
for _, fs in ipairs(createdFontStrings) do
	if type(fs._text) == "string" and fs._text ~= "" then missText = fs._text end
end
ok(missText ~= nil and missText:find("Dodged") ~= nil, "a dodge renders as text", tostring(missText))

--------------------------------------------------------------------------------
-- Healing is drawn only when healed by you, in its own colour, and can be switched off
--------------------------------------------------------------------------------

NS.db.profile.showHealing = true
NS:ClearHealAttribution()
NS.diagnostics.drawn = 0
createdFontStrings = {}
_G.__now = 400
-- Unattributed heals (no heal cast by you) must never render on random players or yourself.
FireEvent("UNIT_COMBAT", "nameplate1", "HEAL", "", 55, 0)
eq(NS.diagnostics.drawn, 0, "random unattributed heal on a nameplate is dropped")
eq(NS.diagnostics.lastDrop, "not your heal", "unattributed heal records why it was dropped")
FireEvent("UNIT_COMBAT", "player", "HEAL", "", 55, 0)
eq(NS.diagnostics.drawn, 0, "random unattributed heal on you is also dropped")

-- Offensive casts (e.g. Aimed Shot 19434) must not open heal attribution.
FireCastEvent("UNIT_SPELLCAST_SENT", "player", "Mob", "cast-dmg-1", 19434)
FireCastEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-dmg-1", 19434)
FireEvent("UNIT_COMBAT", "nameplate1", "HEAL", "", 55, 0)
eq(NS.diagnostics.drawn, 0, "an offensive cast does not authorize random heals")

-- Casting a heal of your own draws it cleanly.
FireCastEvent("UNIT_SPELLCAST_SENT", "player", SECRET, "cast-heal-1", 2061)
FireCastEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-heal-1", 2061)
FireEvent("UNIT_COMBAT", "nameplate1", "HEAL", "", 55, 0)
eq(NS.diagnostics.drawn, 1, "healing is drawn after your heal cast (even with secret targetName)")

local healText, healColor
for _, fs in ipairs(createdFontStrings) do
	if fs._text ~= nil and fs._text ~= "" then healText, healColor = fs._text, fs._textColor break end
end
ok(healText == "+55", "a heal is prefixed with +", tostring(healText))
ok(type(healColor) == "table" and healColor[2] > healColor[1] and healColor[2] > healColor[3],
	"a heal is green by default", healColor and tostring(healColor[2]))

-- Enemy units healing themselves never render, even during your own heal window.
plateFrames["nameplate2"] = CreateFrame("Frame", "Plate2")
_G.__hostileUnits = { nameplate2 = true }
NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "nameplate2", "HEAL", "", 80, 0)
eq(NS.diagnostics.drawn, 0, "an enemy heal is dropped even during your heal window")
_G.__hostileUnits = nil

-- The crit heal colour is a setting of its own.
NS.db.profile.useHealCritColor = true
NS.db.profile.healCritColor = "3366ff"
createdFontStrings = {}
_G.__now = 401
FireCastEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-heal-2", 2061)
FireEvent("UNIT_COMBAT", "nameplate1", "HEAL", "CRITICAL", 90, 0)
local critHealColor
for _, fs in ipairs(createdFontStrings) do
	if fs._text ~= nil and fs._text ~= "" then critHealColor = fs._textColor break end
end
ok(type(critHealColor) == "table" and critHealColor[3] > critHealColor[2],
	"a heal crit uses the heal crit colour", critHealColor and tostring(critHealColor[3]))
NS.db.profile.useHealCritColor = false

-- Channeled AoE heals (e.g. Tranquility 740) authorize heals while channeling and expire afterward.
_G.__now = 410
FireCastEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-chan-1", 740)
_G.__now = 415
NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "nameplate2", "HEAL", "", 40, 0)
eq(NS.diagnostics.drawn, 1, "channeled heal draws during channel even past 2s")
_G.__now = 416
FireCastEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-chan-1", 740)
_G.__now = 419
NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "nameplate2", "HEAL", "", 40, 0)
eq(NS.diagnostics.drawn, 0, "heal window closes after channel stops")

-- Per-recipient HoT tracking: Rejuvenation on target nameplate1 keeps ticking for you at +6s,
-- while an unhealed ally on nameplate2 at +6s is dropped.
NS:ClearHealAttribution()
_G.__now = 430
_G.__unitIsTarget = "nameplate1"
FireCastEvent("UNIT_SPELLCAST_SENT", "player", "Tank", "cast-hot-1", 774)
_G.__unitIsTarget = nil
FireCastEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-hot-1", 774)
_G.__now = 436
NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "nameplate2", "HEAL", "", 30, 0)
eq(NS.diagnostics.drawn, 0, "random heal on another ally after 2s is dropped")
FireEvent("UNIT_COMBAT", "nameplate1", "HEAL", "", 30, 0)
eq(NS.diagnostics.drawn, 1, "your HoT tick on the healed target still draws within 15s")

-- CLEU path: even with personal damage enabled, another healer's heal on you is dropped,
-- while your own heal on yourself still draws.
local personalBefore = NS.db.profile.personal
NS.db.profile.personal = true
NS.diagnostics.drawn = 0
NS:CombatFilter(0, "SPELL_HEAL", false, "Player-2-9999", "OtherHealer", 0, 0,
	UnitGUID("player"), "Me", 0, 0, 2061, "Flash Heal", 2, 120, 0, 0, false)
eq(NS.diagnostics.drawn, 0, "CLEU drops heals on you from other healers even when personal is on")
NS:CombatFilter(0, "SPELL_HEAL", false, UnitGUID("player"), "Me", 0, 0,
	UnitGUID("player"), "Me", 0, 0, 2061, "Flash Heal", 2, 120, 0, 0, false)
eq(NS.diagnostics.drawn, 1, "CLEU draws heals you cast on yourself")
NS.db.profile.personal = personalBefore
plateFrames["nameplate2"] = nil
NS:ClearHealAttribution()

-- And it can be switched off entirely.
NS.db.profile.showHealing = false
NS.diagnostics.drawn = 0
_G.__now = 440
FireEvent("UNIT_COMBAT", "nameplate1", "HEAL", "", 55, 0)
eq(NS.diagnostics.drawn, 0, "healing is off when the switch is off")
eq(NS.diagnostics.lastDrop, "healing is off", "and it says why")
NS.db.profile.showHealing = true

NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "nameplate1", "NONSENSE_ACTION", "", 55, 0)
eq(NS.diagnostics.drawn, 0, "an unknown action is ignored")

--------------------------------------------------------------------------------
-- Every kind of hit has its own switch
--------------------------------------------------------------------------------

local categories = {
	{ action = "WOUND", key = "showMeleeDamage" },
	{ action = "SPELL", key = "showSpellDamage" },
	{ action = "RANGE", key = "showRangedDamage" },
	{ action = "PERIODIC", key = "showPeriodicDamage" },
}

for _, case in ipairs(categories) do
	local saved = NS.db.profile[case.key]
	NS.db.profile[case.key] = false
	NS.diagnostics.drawn = 0
	_G.__now = _G.__now + 1
	FireEvent("UNIT_COMBAT", "nameplate1", case.action, "", 100, SCHOOL_MASK_FIRE)
	eq(NS.diagnostics.drawn, 0, case.action .. " is off when " .. case.key .. " is off")
	eq(NS.diagnostics.lastDrop, "that kind of damage is off", "the drop reason names the category")

	NS.db.profile[case.key] = true
	_G.__now = _G.__now + 1
	FireEvent("UNIT_COMBAT", "nameplate1", case.action, "", 100, SCHOOL_MASK_FIRE)
	eq(NS.diagnostics.drawn, 1, case.action .. " draws again when " .. case.key .. " is on")
	NS.db.profile[case.key] = saved
end

-- Pet damage has no source on this client, but the combat-log path can gate it.
NS.db.profile.showPetDamage = false
local petBefore = NS.diagnostics.dropped["pet damage is off"] or 0
NS:DamageEvent("Creature-0-1-2-3-4", "pet", 100, 0, SCHOOL_MASK_PHYSICAL, false, nil, 0, nil, true)
eq((NS.diagnostics.dropped["pet damage is off"] or 0), petBefore + 1, "pet damage is gated where it can be told apart")
NS.db.profile.showPetDamage = true

-- A combat-log category reaches DamageEvent directly.
NS.db.profile.showRangedDamage = false
local rangedBefore = NS.diagnostics.dropped["that kind of damage is off"] or 0
NS:DamageEvent("Creature-0-1-2-3-4", "Auto Shot", 100, 0, SCHOOL_MASK_PHYSICAL, false, nil, 0, "showRangedDamage")
eq((NS.diagnostics.dropped["that kind of damage is off"] or 0), rangedBefore + 1,
	"a combat-log hit is gated by its category")
NS.db.profile.showRangedDamage = true

--------------------------------------------------------------------------------
-- Crits: UNIT_COMBAT carries the flag Blizzard's own combat feedback reads, so a crit
-- gets its own colour, size and animation on the restricted client too.
--------------------------------------------------------------------------------

-- The crit colour is a plain lookup, so it can be proved without an event.
NS.db.profile.useCritColor = true
NS.db.profile.critColor = "ff00ff"
local cr, cg, cb = NS:GetTextColor(false, SCHOOL_MASK_FIRE, nil, true)
eq(math.floor(cr * 255 + 0.5), 255, "the crit colour wins over the school colour")
eq(math.floor(cg * 255 + 0.5), 0, "the crit colour's green channel is applied")
eq(math.floor(cb * 255 + 0.5), 255, "the crit colour's blue channel is applied")

-- And an event with the CRITICAL flag uses it, plus the crit sizing and animation.
NS.db.profile.animations.crit = "fountain"
NS.db.profile.sizing.crits = true
NS.db.profile.sizing.critsScale = 2
_G.__now = _G.__now + 1
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "SPELL", "CRITICAL", 200, SCHOOL_MASK_FIRE)
local critFontString = _G.__lastNumberFontString
ok(critFontString ~= nil, "a crit draws")
eq(critFontString and critFontString.animation, "fountain", "a crit uses the crit animation")
-- The plate is off-target, so the off-target size is the base the crit scale multiplies.
local critBase = NS.db.profile.useOffTargetAppearance
	and NS.db.profile.offTargetFormatting.size or NS.db.profile.formatting.size
eq(critFontString and critFontString.NSCTFontSize, critBase * NS.db.profile.sizing.critsScale,
	"a crit is enlarged by the crit scale")
ok(critFontString and critFontString._textColor and critFontString._textColor[1] > 0.9
	and critFontString._textColor[3] > 0.9, "a crit uses the crit colour",
	critFontString and critFontString._textColor and tostring(critFontString._textColor[1]))

-- A plain hit keeps the normal animation and colour.
NS.db.profile.animations.ability = "rainfall"
_G.__now = _G.__now + 1
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "SPELL", "", 200, SCHOOL_MASK_FIRE)
local plainFontString = _G.__lastNumberFontString
eq(plainFontString and plainFontString.animation, "rainfall", "a normal hit uses the normal animation")
ok(plainFontString and plainFontString._textColor
	and (plainFontString._textColor[1] ~= critFontString._textColor[1]
		or plainFontString._textColor[3] ~= critFontString._textColor[3]),
	"a normal hit is not coloured like a crit")
NS.db.profile.useCritColor = false
NS.db.profile.sizing.critsScale = 1.5

--------------------------------------------------------------------------------
-- Numbers about you mount where the setting says
--------------------------------------------------------------------------------

NS.db.profile.personal = true
NS.db.profile.displayMode = "nameplates"

_G.PlayerFrame = { IsShown = function() return true end }
NS.db.profile.personalAnchor = "unitframe"
_G.__now = _G.__now + 1
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "player", "WOUND", "", 100, SCHOOL_MASK_FIRE)
local unitFrameNumber = _G.__lastNumberFontString
ok(unitFrameNumber ~= nil, "damage on you draws")
ok(unitFrameNumber and unitFrameNumber.anchorFrame == _G.PlayerFrame,
	"damage on you is mounted to your unit frame")

NS.db.profile.personalAnchor = "screen"
_G.__now = _G.__now + 1
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "player", "WOUND", "", 100, SCHOOL_MASK_FIRE)
local screenNumber = _G.__lastNumberFontString
ok(screenNumber and screenNumber.anchorFrame == UIParent,
	"and to the screen when that is the choice")

-- A unit frame the client is not showing falls back to the screen instead of dropping it.
_G.PlayerFrame = { IsShown = function() return false end }
NS.db.profile.personalAnchor = "unitframe"
_G.__now = _G.__now + 1
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "player", "WOUND", "", 100, SCHOOL_MASK_FIRE)
local fallbackNumber = _G.__lastNumberFontString
ok(fallbackNumber and fallbackNumber.anchorFrame == UIParent,
	"a hidden unit frame falls back to the screen")
_G.PlayerFrame = nil
NS.db.profile.personalAnchor = "screen"
NS.db.profile.personal = false

--------------------------------------------------------------------------------
-- A plate-less unit token is ignored rather than raising
--------------------------------------------------------------------------------

_G.__now = 500
NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "exists-but-no-plate", "WOUND", "", 10, 0)
eq(NS.diagnostics.drawn, 0, "a token with no nameplate is ignored")

--------------------------------------------------------------------------------
-- Target-of-target tokens: the reported crash
--------------------------------------------------------------------------------
-- UNIT_COMBAT reports "targettarget" on Forever, and C_NamePlate.GetNamePlateForUnit raises
-- on it. The stub above reproduces that error, so these checks fail if any display path
-- hands a derived token to the client again.

_G.__now = 550
NS.diagnostics.drawn = 0
local tofOk, tofErr = pcall(FireEvent, "UNIT_COMBAT", "targettarget", "WOUND", "", 900, SCHOOL_MASK_FIRE)
ok(tofOk, "a target-of-target hit does not raise", tofErr)
eq(NS.diagnostics.drawn, 0, "a target-of-target hit with no plate is skipped in nameplate mode")

NS.db.profile.displayMode = "screen"
_G.__now = 551
NS.diagnostics.drawn = 0
createdFontStrings = {}
local screenOk, screenErr = pcall(FireEvent, "UNIT_COMBAT", "targettarget", "WOUND", "", 901, SCHOOL_MASK_FIRE)
ok(screenOk, "a target-of-target hit does not raise in screen mode", screenErr)
eq(NS.diagnostics.drawn, 1, "screen mode still draws a target-of-target hit")
NS.db.profile.displayMode = "nameplates"

-- A plain "target" token is valid and must keep resolving.
_G.__now = 552
NS.diagnostics.drawn = 0
plateFrames.target = plateFrames["nameplate1"]
local targetOk, targetErr = pcall(FireEvent, "UNIT_COMBAT", "target", "WOUND", "", 902, SCHOOL_MASK_FIRE)
ok(targetOk, "a plain target token is still accepted by the plate lookup", targetErr)


--------------------------------------------------------------------------------
-- Options window: it must load and build without a runtime error, because a failure
-- here is what a player sees when they type /nsct.
--------------------------------------------------------------------------------

local addonDir = addonPath:gsub("NameplateSCT%.lua$", "")

local widgetsOk, widgetsErr = pcall(function()
	assert(loadfile(addonDir .. "Options/Widgets.lua"))("NameplateSCT")
end)
ok(widgetsOk, "Options/Widgets.lua loads", widgetsErr)

local settingsOk, settingsErr = pcall(function()
	assert(loadfile(addonDir .. "Options/Settings.lua"))("NameplateSCT")
end)
ok(settingsOk, "Options/Settings.lua loads", settingsErr)

if settingsOk then
	local openOk, openErr = pcall(function() NS:OpenDashboard() end)
	ok(openOk, "the dashboard opens without error", openErr)
	ok(_G.NameplateSCTSettingsFrame ~= nil, "the settings frame was created")

	local openAgainOk, openAgainErr = pcall(function() NS:OpenDashboard() end)
	ok(openAgainOk, "reopening the dashboard is safe", openAgainErr)

	local pagesBuilt = 0
	if _G.NameplateSCTSettingsFrame and _G.NameplateSCTSettingsFrame.pages then
		for _, content in pairs(_G.NameplateSCTSettingsFrame.pages) do
			if content.built then pagesBuilt = pagesBuilt + 1 end
		end
	end
	ok(pagesBuilt >= 1, "the dashboard page was built", pagesBuilt)

	-- Every page must build: a single throwing builder would break navigation.
	local navOk, navErr = true, nil
	-- Every page, including the two that used to be skipped here: a page that never builds
	-- in the harness is a page nobody tests.
	for _, page in ipairs({ "dashboard", "general", "numbers", "appearance", "animations", "position", "filters", "about" }) do
		local pageOk, pageErr = pcall(function() NS:OpenDashboard(); _G.NameplateSCTSettingsFrame:SelectPage(page) end)
		if not pageOk then navOk, navErr = false, page .. ": " .. tostring(pageErr) end
	end
	ok(navOk, "every settings page builds", navErr)

	local refreshOk, refreshErr = pcall(function() NS:RefreshSettings() end)
	ok(refreshOk, "the refresh pass runs", refreshErr)

	-- /nsct must open the dashboard, never the Blizzard AddOns panel.
	_G.__openedCategory = nil
	_G.NameplateSCTSettingsFrame:Hide()
	local nsct = chatCommands["nsct"]
	local slashOk, slashErr = pcall(NS[nsct], NS, "")
	ok(slashOk, "/nsct opens without error", slashErr)
	ok(_G.NameplateSCTSettingsFrame:IsShown(), "/nsct opens the dashboard window")
	eq(_G.__openedCategory, nil, "/nsct does not fall through to the Blizzard options panel")

	-- The AddOns section is a launcher: a button, not a settings tree that overflows the
	-- client's options canvas.
	local panel = registeredOptions["NameplateSCT"]
	ok(panel ~= nil, "the AddOns panel is registered")
	local launcher, argCount = nil, 0
	if panel and panel.args then
		for _, entry in pairs(panel.args) do
			argCount = argCount + 1
			if entry.type == "execute" then launcher = entry end
		end
	end
	ok(launcher ~= nil, "the AddOns panel has a button that opens the dashboard")
	ok(argCount > 0 and argCount <= 6, "the AddOns panel stays a launcher, not a settings tree", argCount)

	if launcher then
		_G.__openedCategory = nil
		_G.NameplateSCTSettingsFrame:Hide()
		local buttonOk, buttonErr = pcall(launcher.func)
		ok(buttonOk, "the AddOns button runs without error", buttonErr)
		ok(_G.NameplateSCTSettingsFrame:IsShown(), "the AddOns button opens the dashboard")
		eq(_G.__openedCategory, nil, "the AddOns button opens the addon's own window")
	end
end




--------------------------------------------------------------------------------
-- Display modes, thresholds and the miss toggle
--------------------------------------------------------------------------------

local function lastDrawn()
	local text
	for _, fs in ipairs(createdFontStrings) do
		if fs._text ~= nil and fs._text ~= "" then text = fs._text end
	end
	return text
end

-- Screen mode must draw even when the unit has no nameplate at all.
NS.db.profile.displayMode = "screen"
NS.db.profile.showMisses = true
NS.diagnostics.drawn = 0
_G.__now = 600
createdFontStrings = {}
local screenDrawn = FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 777, SCHOOL_MASK_FIRE)
ok(screenDrawn, "unit-combat event dispatched")
eq(NS.diagnostics.drawn, 1, "screen mode draws without a nameplate frame")
ok(lastDrawn() ~= nil, "screen mode produced text")
ok(NS:GetScreenAnchor(false) ~= nil, "the outgoing screen anchor exists")

NS.db.profile.displayMode = "nameplates"

-- The absolute minimum damage floor.
NS.db.profile.minDamage = 1000
NS.diagnostics.drawn = 0
_G.__now = 700
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 500, SCHOOL_MASK_FIRE)
eq(NS.diagnostics.drawn, 0, "a hit under the minimum damage floor is dropped")

_G.__now = 700.5
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 1500, SCHOOL_MASK_FIRE)
eq(NS.diagnostics.drawn, 1, "a hit above the floor draws")
NS.db.profile.minDamage = 0

-- The miss toggle.
NS.db.profile.showMisses = false
NS.diagnostics.drawn = 0
_G.__now = 800
FireEvent("UNIT_COMBAT", "nameplate1", "DODGE", "", 0, 0)
eq(NS.diagnostics.drawn, 0, "misses are suppressed when the toggle is off")
NS.db.profile.showMisses = true

_G.__now = 801
FireEvent("UNIT_COMBAT", "nameplate1", "DODGE", "", 0, 0)
eq(NS.diagnostics.drawn, 1, "misses draw again when the toggle is on")

--------------------------------------------------------------------------------
-- Brand assets: the palette is the logo's, and the TGA is loadable by the client
--------------------------------------------------------------------------------

local Palette = NS.W and NS.W.C
ok(Palette ~= nil, "the widget palette is exposed")
ok(Palette and math.abs(Palette.accent[1] - 1.0) < 0.01 and math.abs(Palette.accent[2] - 0.553) < 0.01,
	"the accent is the logo orange", Palette and tostring(Palette.accent[2]))
ok(Palette and Palette.yellow ~= nil and Palette.red ~= nil, "the palette carries the logo gold and red")

local tga = io.open(addonDir .. "logo.tga", "rb")
if tga then
	local header = tga:read(18)
	tga:close()
	local idLength = header:byte(1)
	local imageType = header:byte(3)
	local width = header:byte(13) + header:byte(14) * 256
	local bpp = header:byte(17)

	eq(imageType, 2, "logo.tga is uncompressed true-colour (WoW cannot read palettized TGA)")
	eq(bpp, 32, "logo.tga is 32-bit")
	local power = width
	while power > 1 and power % 2 == 0 do power = power / 2 end
	ok(width > 0 and power == 1, "logo.tga width is a power of two", width)
	ok(idLength == 0, "logo.tga has no palette/ID block")
else
	ok(false, "logo.tga exists")
end

--------------------------------------------------------------------------------
-- Settings coverage: every key in the saved-variable schema must be reachable
--------------------------------------------------------------------------------

local function defaultKeys()
	local handle = io.open(addonDir .. "NameplateSCT.lua", "r")
	if not handle then return {} end
	local text = handle:read("*a")
	handle:close()

	local block = text:match("local defaults = (%b{})")
	if not block then return {} end

	-- A line may hold several pairs ("outgoingX = 0, outgoingY = -140,") and may open and
	-- close tables, so this walks the tokens rather than assuming one pair per line.
	local keys, stack = {}, {}
	for line in block:gmatch("[^\n]+") do
		line = line:gsub("%-%-.*$", "")
		local closes = 0
		for _ in line:gmatch("}") do closes = closes + 1 end

		for key, value in line:gmatch("([%w_]+)%s*=%s*([^{},]+)") do
			if #stack > 0 and value:match("%S") then
				keys[#keys + 1] = table.concat(stack, ".") .. "." .. key
			end
		end
		for key in line:gmatch("([%w_]+)%s*=%s*{") do
			stack[#stack + 1] = key
		end
		for _ = 1, closes do
			if #stack > 0 then stack[#stack] = nil end
		end
	end
	return keys
end

local settingsSource = io.open(addonDir .. "Options/Settings.lua", "r")
local settingsText = settingsSource and settingsSource:read("*a")
if settingsSource then settingsSource:close() end

local keys = defaultKeys()
ok(#keys > 40, "the defaults schema was parsed", #keys)

-- The window declares, per control, the profile path it owns, so coverage is checked
-- structurally instead of by searching the file for the key name: a control for a key that
-- does not exist, or a key with no control, both fail here.
local controls = NS.settingsControls or {}
ok(#controls > 40, "the settings window declares its controls", #controls)

local defaultsSet = {}
for _, key in ipairs(keys) do
	defaultsSet[key:gsub("^profile%.", ""):gsub("^global%.", "")] = true
end

local controlPaths = {}
for _, control in ipairs(controls) do controlPaths[control.path] = true end

local unexposed, orphans = {}, {}
for path in pairs(defaultsSet) do
	if not controlPaths[path] then unexposed[#unexposed + 1] = path end
end
for path in pairs(controlPaths) do
	if not defaultsSet[path] then orphans[#orphans + 1] = path end
end
table.sort(unexposed)
table.sort(orphans)

ok(#unexposed == 0, "every saved setting has a control",
	#unexposed > 0 and table.concat(unexposed, ", ") or nil)
ok(#orphans == 0, "every control writes a setting that exists",
	#orphans > 0 and table.concat(orphans, ", ") or nil)

--------------------------------------------------------------------------------
-- Restricted-client hazards in the render loop: UnitIsDead is AllowedWhenUntainted
-- and runs inside the animation OnUpdate, so it must never be called bare.
--------------------------------------------------------------------------------

local handle = io.open(addonDir .. "NameplateSCT.lua", "r")
local source = handle and handle:read("*a")
if handle then handle:close() end

ok(source ~= nil, "addon source readable for the static pins")

-- Fonts are set per region, never on a shared Blizzard font object. Writing
-- GameFontNormal/GameFontHighlight (or STANDARD_TEXT_FONT) would repaint every frame in the
-- client that shares it - action bars, chat, tooltips - which is the "the addon changed my
-- UI font" class of bug. The bundled Source Sans files are only ever passed to
-- CreateFontString/SetFont on regions this addon owns.
local widgetsHandle = io.open(addonDir .. "Options/Widgets.lua", "r")
local widgetsText = widgetsHandle and widgetsHandle:read("*a")
if widgetsHandle then widgetsHandle:close() end

local function globalFontWrites(text)
	local found = {}
	for line in (text or ""):gmatch("[^\n]+") do
		local code = line:gsub("%-%-.*$", "")
		if code:find("GameFont[%w_]*%s*:SetFont") or code:find("GameFont[%w_]*%.font%s*=")
			or code:find("STANDARD_TEXT_FONT%s*=") or code:find("ChatFont[%w_]*%s*:SetFont") then
			found[#found + 1] = line
		end
	end
	return found
end

local fontViolations = {}
for _, text in ipairs({ source, settingsText, widgetsText }) do
	for _, line in ipairs(globalFontWrites(text)) do
		fontViolations[#fontViolations + 1] = line
	end
end
ok(#fontViolations == 0, "nothing writes a shared Blizzard font object",
	#fontViolations > 0 and table.concat(fontViolations, " | ") or nil)
ok(source and source:find("safeUnitIsDead") ~= nil, "the death check goes through a throw-aware helper")
ok(source and source:find("(not UnitIsDead%(") == nil, "no bare UnitIsDead call remains in the render loop")
ok(source and source:find("UnitHealth") == nil, "no UnitHealth read (health is a secret number)")




--------------------------------------------------------------------------------
-- Settings namespace migration: `global` (shared) -> `profile` (AceDB profiles)
--------------------------------------------------------------------------------

ok(NS.db.profile ~= nil, "settings live in the AceDB profile namespace")
ok(NS.db.global == nil, "the shared global namespace is no longer used")

eq(NS.db.profile.yOffset, 22, "a legacy value is carried into the profile")
eq(NS.db.profile.textShadow, true, "a legacy true is carried over, not dropped")
eq(NS.db.profile.sizing.smallHits, false, "nested legacy tables are carried over")
ok(type(NS.db.profile.sizing) == "table" and NS.db.profile.sizing ~= _G.NameplateSCTDB.global.sizing,
	"migrated tables are copied, not shared with the legacy table")
-- The legacy fixture only mentions sizing.smallHits. Merging must keep the rest of the
-- default subtree; assigning the table whole used to drop every other sizing key.
eq(NS.db.profile.sizing.critsScale, 1.5, "a nested legacy table keeps defaults it does not mention")
eq(NS.db.profile.sizing.hideSmallHitsThreshold, 0, "a nested legacy table does not erase later keys")
ok(NS.db.profile.formatting ~= nil and NS.db.profile.formatting.size ~= nil,
	"a legacy table does not erase sibling default tables")
eq(_G.NameplateSCTDB.settingsNamespace, "profile", "the migration is marked on the saved variable")
ok(_G.NameplateSCTDB.global ~= nil, "the legacy settings are kept as a recovery copy")

-- Running again must not migrate a second time (it would resurrect old values).
NS.db.profile.yOffset = 99
local reran = NS.migrateSettingsToProfile(NS.db, "NameplateSCTDB")
eq(reran, false, "the migration reports that it did not run")
eq(NS.db.profile.yOffset, 99, "a second run leaves the current profile untouched")


--------------------------------------------------------------------------------
-- Caching must never hold a secret. A restricted answer is converted to a plain
-- boolean first, so what lands in the cache is untainted and safe to compare later.
--------------------------------------------------------------------------------

local previousUnitIsUnit, previousUnitIsDead = UnitIsUnit, UnitIsDead
UnitIsUnit = function() return SECRET end
UnitIsDead = function() return SECRET end

NS.db.profile.displayMode = "nameplates"
NS.diagnostics.drawn = 0
_G.__now = 900
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 500, SCHOOL_MASK_FIRE)

local cachedFontString
for _, fs in ipairs(createdFontStrings) do
	if fs._text ~= nil and fs._text ~= "" then cachedFontString = fs end
end
ok(cachedFontString ~= nil, "a number exists for the cache test")

local updateScript = NS.frame and NS.frame._scripts and NS.frame._scripts["OnUpdate"]
ok(updateScript ~= nil, "the animation tick is installed")

if updateScript then
	local ticked, tickError = pcall(updateScript, NS.frame)
	ok(ticked, "the animation tick survives secret UnitIsUnit and UnitIsDead results", tickError)
end

if cachedFontString then
	ok(cachedFontString.targetValue ~= SECRET, "a secret target answer is not cached as-is")
	ok(not issecretvalue(cachedFontString.targetValue), "the cached target value is untainted")
	ok(cachedFontString.deadValue ~= SECRET, "a secret death answer is not cached as-is")
	ok(not issecretvalue(cachedFontString.deadValue), "the cached death value is untainted")
end

UnitIsUnit = previousUnitIsUnit
UnitIsDead = previousUnitIsDead


--------------------------------------------------------------------------------
-- A FontString holding a secret amount reports a secret GetStringHeight
-- (SecretWhenAnchoringSecret). startHeight feeds arithmetic in powSizing, so it must be
-- replaced by a plain value rather than propagated.
--------------------------------------------------------------------------------

_G.__stringHeight = SECRET
_G.__lastFontString = nil
_G.__lastNumberFontString = nil
_G.__now = 1000
NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 640, SCHOOL_MASK_FIRE)

-- Font strings are pooled, so look at the one that was actually written to. The shadow is a
-- FontString too and writes after the number, so the stub records the number's region.
local secretSized = _G.__lastNumberFontString

ok(secretSized ~= nil, "a number was drawn for the secret-height test")
eq(NS.diagnostics.drawn, 1, "the secret-height hit drew once")
if secretSized then
	ok(not issecretvalue(secretSized.startHeight), "a secret measured height is not stored")
	ok(type(secretSized.startHeight) == "number" and secretSized.startHeight > 0,
		"the height falls back to a plain, usable number", tostring(secretSized.startHeight))
	eq(secretSized.startHeight, secretSized.NSCTFontSize, "the fallback is the requested font size")
end

local tickScript = NS.frame and NS.frame._scripts and NS.frame._scripts["OnUpdate"]
if tickScript then
	local ticked, tickError = pcall(tickScript, NS.frame)
	ok(ticked, "the animation tick survives a secret measured height", tickError)
end

_G.__stringHeight = nil




-- Damage to you must stay off by default, even when the client reports it under an alias that
-- points at you ("targettarget" while a mob is hitting you) instead of the "player" token.
NS.db.profile.displayMode = "screen"
NS.db.profile.personal = false
_G.__unitIsSelf = "targettarget"
_G.__now = 1450
NS.diagnostics.drawn = 0
createdFontStrings = {}
local selfDropsBefore = NS.diagnostics.dropped["damage you take is off"] or 0

FireEvent("UNIT_COMBAT", "targettarget", "WOUND", "", 42, SCHOOL_MASK_FIRE)
eq(NS.diagnostics.drawn, 0, "damage to you is not drawn by default, even under an alias")
ok((NS.diagnostics.dropped["damage you take is off"] or 0) == selfDropsBefore + 1,
	"the alias is recorded as damage you take")

-- With the setting on it is drawn once, on the personal side.
NS.db.profile.personal = true
NS.db.profile.displayMode = "nameplates"
_G.__now = 1452
NS.diagnostics.drawn = 0
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "targettarget", "WOUND", "", 43, SCHOOL_MASK_FIRE)
eq(NS.diagnostics.drawn, 1, "with the setting on, damage to you is drawn")
local selfNumber = _G.__lastNumberFontString
ok(selfNumber and selfNumber.unit == "player",
	"an alias that points at you is treated as the player", selfNumber and selfNumber.unit)

NS.db.profile.personal = false
_G.__unitIsSelf = nil
NS.db.profile.displayMode = "nameplates"

--------------------------------------------------------------------------------
-- Blizzard combat text: the master switch gates the renderer, the family CVars are the
-- classic-family defence. Reading back our own CVar is not proof - the client is.
--------------------------------------------------------------------------------

local family = NS.blizzardTextCVars or {}
local master = NS.blizzardFCTMasterCVar
eq(type(master), "string", "the master combat-text switch has a name")
ok(#family >= 40, "the addon steers the full combat-text CVar family (both _v2 and plain)")

-- Start from the state the user reported: Blizzard's numbers are drawing.
-- Stub a realistic Forever subset: the _v2 CVars plus plain ones if exposed, leaving
-- absent CVars as nil so we also verify absent CVars are skipped cleanly.
local activeFamily = {
	"floatingCombatTextCombatDamage_v2",
	"floatingCombatTextCombatDamageAllAutos_v2",
	"floatingCombatTextCombatHealing_v2",
	"floatingCombatTextCombatLogPeriodicSpells_v2",
	"floatingCombatTextPetMeleeDamage_v2",
	"floatingCombatTextPetSpellDamage_v2",
	"floatingCombatTextDodgeParryMiss_v2",
	"floatingCombatTextDamageReduction_v2",
	"floatingCombatTextCombatDamage",
}
_G.CombatText.events = { COMBAT_TEXT_UPDATE = true }
for _, name in ipairs(activeFamily) do cvarValues[name] = "1" end
cvarValues[master] = "1"

NS.db.profile.hideBlizzardFCT = true
NS:ApplyBlizzardFCT()

eq(cvarValues[master], "0", "the master switch this client actually reads is turned off")
eq(cvarValues.floatingCombatTextCombatDamageAllAutos_v2, "0", "auto-attack world numbers are turned off")
eq(cvarValues.floatingCombatTextPetMeleeDamage_v2, "0", "pet melee world numbers are turned off")
eq(cvarValues.floatingCombatTextPetSpellDamage_v2, "0", "pet spell world numbers are turned off")
eq(cvarValues.floatingCombatTextCombatHealing_v2, "0", "healing world numbers are turned off")
eq(cvarValues.floatingCombatTextCombatDamage, "0", "plain combat-damage CVar is also turned off if present")
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false,
	"the client's renderer is unregistered, which is what stops self damage and healing text")

_G.__blizzardNumbers = 0
_G.__drawBlizzardText()
eq(_G.__blizzardNumbers, 0, "a combat-text tick draws nothing once the setting is on")
eq((NS:GetBlizzardFCTStatus()), true, "the dashboard status reads the client, not our write")

-- Even with enableFloatingCombatText = "0" and CombatText unregistered, an active world
-- combat-text CVar still counts as on, so the dashboard must not report green.
cvarValues.floatingCombatTextCombatDamageAllAutos_v2 = "1"
eq((NS:GetBlizzardFCTStatus()), false, "an active world-text CVar fails the status check even when master is 0")
cvarValues.floatingCombatTextCombatDamageAllAutos_v2 = "0"

-- The 1.64 bug, exactly: every CVar reads "0" and the client keeps drawing. A check that trusts
-- the CVar goes green here; one that asks the client does not.
for _, name in ipairs(activeFamily) do cvarValues[name] = "0" end
_G.CombatText.events = { COMBAT_TEXT_UPDATE = true }
eq((NS:GetBlizzardFCTStatus()), false, "a green CVar does not mean the client stopped")
_G.__blizzardNumbers = 0
_G.__drawBlizzardText()
eq(_G.__blizzardNumbers, 1, "and the numbers really do still come through")

-- The addon's own pass re-asserts the registration, so the fix does not depend on the client's
-- settings callback having fired.
NS:ApplyBlizzardFCT()
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false, "re-applying unregisters the renderer")
_G.__blizzardNumbers = 0
_G.__drawBlizzardText()
eq(_G.__blizzardNumbers, 0, "numbers stop again")

local steered, on = NS:GetBlizzardFCTState()
eq(steered, 1 + #activeFamily, "the state helper sees the master plus every exposed CVar")
eq(on, 0, "the state helper reports nothing still drawing")

-- Toggling the setting back off restores what the player had, and gives the text back.
NS.db.profile.hideBlizzardFCT = false
NS:ApplyBlizzardFCT()
eq(cvarValues[master], "1", "the master switch is handed back to the player")
local restored = 0
for _, name in ipairs(activeFamily) do
	if cvarValues[name] == "1" then restored = restored + 1 end
end
eq(restored, #activeFamily, "turning the setting off restores every steered CVar")
eq(cvarValues.floatingCombatTextAuras_v2, nil, "absent CVars are never written on restore")
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), true, "the client's renderer is registered again")
_G.__blizzardNumbers = 0
_G.__drawBlizzardText()
eq(_G.__blizzardNumbers, 1, "Blizzard's numbers come back when the setting is off")

-- A CVar this client does not have is skipped, not treated as a refused write.
NS.db.profile.hideBlizzardFCT = true
NS:ApplyBlizzardFCT()
local droppedVar = activeFamily[#activeFamily]
cvarValues[droppedVar] = nil
local steeredWithout = select(1, NS:GetBlizzardFCTState())
eq(steeredWithout, 1 + #activeFamily - 1, "a CVar the client does not expose is not counted")
eq(NS.diagnostics.fctFailed, 0, "an absent CVar is not a failure")
cvarValues[droppedVar] = "1"

-- And nothing outside the switch is touched.
eq(cvarValues.nameplateShowEnemies, "1", "unrelated CVars are left alone")

-- A CVar the client refuses to change is reported, not silently assumed to have worked.
for _, name in ipairs(activeFamily) do cvarValues[name] = "1" end
NS.db.profile.hideBlizzardFCT = false
NS:ApplyBlizzardFCT()
_G.__refuseCvar = activeFamily[1]
NS.db.profile.hideBlizzardFCT = true
NS:ApplyBlizzardFCT()
eq(cvarValues[activeFamily[1]], "1", "a refused CVar keeps its value")
eq(cvarValues[activeFamily[2]], "0", "the other CVars are still written")
eq(NS.diagnostics.fctFailed, 1, "the refused write is counted")
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false,
	"even a refused CVar leaves the renderer unregistered this session")
_G.__refuseCvar = nil

NS.db.profile.hideBlizzardFCT = false
NS:ApplyBlizzardFCT()
eq(NS.diagnostics.fctFailed, 0, "a successful pass clears the failure count")

-- The record that makes "show" possible is per session. A reload between "hide" and "show"
-- leaves the switch reading "0" with nothing to hand back, so the addon must never record "0"
-- as the value to restore: it records the client's default instead and the text always returns.
cvarValues[master] = "0"
NS.db.profile.hideBlizzardFCT = true
NS:ApplyBlizzardFCT()
NS.db.profile.hideBlizzardFCT = false
NS:ApplyBlizzardFCT()
eq(cvarValues[master], "1", "a record lost to a reload still hands Blizzard's text back")
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), true, "and the renderer comes back")

-- With the setting off and nothing recorded, the player's own choice is left alone: a player
-- who turned the client's combat text off in the game's options must stay off.
cvarValues[master] = "0"
_G.CombatText.events = {}
NS.db.profile.hideBlizzardFCT = false
NS:ApplyBlizzardFCT()
eq(cvarValues[master], "0", "an untouched client setting is not turned on behind the player")
_G.CombatText.events = { COMBAT_TEXT_UPDATE = true }

-- Turning the addon itself off hands Blizzard's text back: drawing nothing while muting the
-- client would leave the player with no numbers at all.
NS.db.profile.hideBlizzardFCT = true
NS.db.profile.enabled = true
NS:ApplyBlizzardFCT()
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false, "hidden while the addon is on")
NS.db.profile.enabled = false
NS:ApplyBlizzardFCT()
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), true, "the renderer returns with the addon off")
eq(cvarValues[master], "1", "the master switch is handed back with the addon off")
NS.db.profile.enabled = true
NS:ApplyBlizzardFCT()
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false, "and is muted again when the addon is back on")
NS.db.profile.hideBlizzardFCT = false
NS:ApplyBlizzardFCT()

-- The setting stays authoritative: if the game's own options or another addon turn Blizzard's
-- text back on while the toggle is on, the addon puts it back instead of letting numbers return.
NS.db.profile.hideBlizzardFCT = true
NS.db.profile.enabled = true
NS:ApplyBlizzardFCT()
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false, "hidden to start")
cvarValues[master] = "1"
_G.CombatText.events = { COMBAT_TEXT_UPDATE = true }
FireEvent("CVAR_UPDATE", master)
eq(cvarValues[master], "0", "the master switch is put back")
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false, "and the renderer is unregistered again")

-- Another addon flipping a world-text CVar (while master stays "0") is also caught and reverted.
cvarValues.floatingCombatTextCombatDamage_v2 = "1"
cvarValues.floatingCombatTextCombatDamageAllAutos_v2 = "1"
FireEvent("CVAR_UPDATE", "floatingCombatTextCombatDamage_v2")
eq(cvarValues.floatingCombatTextCombatDamage_v2, "0", "a reverted damage CVar is put back to 0")
eq(cvarValues.floatingCombatTextCombatDamageAllAutos_v2, "0", "and sibling world-text CVars are also put back")

-- Late-loading Blizzard_CombatText or SETTINGS_LOADED re-asserts suppression.
_G.CombatText.events = { COMBAT_TEXT_UPDATE = true }
FireEvent("ADDON_LOADED", "Blizzard_CombatText")
eq(_G.CombatText:IsEventRegistered("COMBAT_TEXT_UPDATE"), false, "late-loaded Blizzard_CombatText is unregistered")
cvarValues.floatingCombatTextPetMeleeDamage_v2 = "1"
FireEvent("SETTINGS_LOADED")
eq(cvarValues.floatingCombatTextPetMeleeDamage_v2, "0", "SETTINGS_LOADED re-asserts Blizzard FCT suppression")

-- The echo of our own write does not cause a second pass.
_G.CombatText.events = {}
FireEvent("CVAR_UPDATE", master)
eq(cvarValues[master], "0", "our own write's event is left alone")

-- An unrelated CVar does not trigger a re-apply.
cvarValues[master] = "1"
_G.CombatText.events = { COMBAT_TEXT_UPDATE = true }
FireEvent("CVAR_UPDATE", "nameplateShowEnemies")
eq(cvarValues[master], "1", "an unrelated CVar change is ignored")

NS.db.profile.hideBlizzardFCT = false
NS:ApplyBlizzardFCT()

-- Another addon drawing numbers in the same place is named, so "I turned Blizzard's off and it
-- still shows" has a cause instead of another guessing round.
_G.C_AddOns = { IsAddOnLoaded = function(name) return name == "PlateSCT" end }
local rivals = NS:GetNumberRivals()
eq(#rivals, 1, "a loaded number addon is reported")
eq(rivals[1], "PlateSCT", "and it is named")
rivals[#rivals + 1] = "leaked"
eq(#NS:GetNumberRivals(), 1, "each call returns a fresh list")
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
eq(#NS:GetNumberRivals(), 0, "nothing is reported when no rival is loaded")
_G.C_AddOns = nil
eq(#NS:GetNumberRivals(), 0, "a client without the addon API reports nothing")

--------------------------------------------------------------------------------
-- Spell icons are off by default, including for a profile saved by an older build
--------------------------------------------------------------------------------

eq(NS.defaults.profile.showIcon, false, "spell icons are off by default")

-- A profile saved before the change still carries showIcon = true, so the new default only
-- reaches it through a one-time correction recorded on the saved variable.
_G.NameplateSCTDB.iconDefaultOff = nil
NS.db.profile.showIcon = true
local defaultsChanged = NS.applyDefaultChanges(NS.db, "NameplateSCTDB")
eq(defaultsChanged, true, "an existing profile is moved to the new default once")
eq(NS.db.profile.showIcon, false, "spell icons are off after the correction")
eq(_G.NameplateSCTDB.iconDefaultOff, true, "the correction is recorded on the saved variable")

-- Turning them back on is the player's choice and must survive a reload.
NS.db.profile.showIcon = true
eq(NS.applyDefaultChanges(NS.db, "NameplateSCTDB"), false, "the correction does not run twice")
eq(NS.db.profile.showIcon, true, "a player who turns icons back on keeps them")
NS.db.profile.showIcon = false
NS:RefreshSettings()

--------------------------------------------------------------------------------
-- Configurable shadow: a second FontString, because the client's own shadow is a fixed
-- 1px copy with no size, distance, angle or colour.
--------------------------------------------------------------------------------

NS.db.profile.useOffTargetAppearance = false
NS.db.profile.textShadow = true
NS.db.profile.shadow.size = 1.5
NS.db.profile.shadow.distance = 4
NS.db.profile.shadow.angle = 0
NS.db.profile.shadow.color = "ff0000"
NS.db.profile.shadow.alpha = 0.5
NS.db.profile.formatting.size = 20

_G.__now = 1300
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 800, SCHOOL_MASK_FIRE)
local shadowMain = _G.__lastNumberFontString
local shadowRegion = shadowMain and shadowMain.shadow
ok(shadowRegion ~= nil, "a shadow region is attached to every number")

if shadowRegion then
	eq(shadowMain._shadowOffset[1], 0, "the client's fixed shadow is off while the custom one is used")
	eq(shadowRegion._text, shadowMain._text, "the shadow carries the same text")
	ok(shadowRegion._font and shadowRegion._font.size == 30,
		"the shadow is scaled from the number's size", shadowRegion._font and shadowRegion._font.size)
	ok(shadowRegion._point and shadowRegion._point[2] == 4,
		"shadow distance drives the offset", shadowRegion._point and shadowRegion._point[2])
	ok(shadowRegion._textColor and shadowRegion._textColor[1] > 0.99 and shadowRegion._textColor[2] < 0.01,
		"the shadow colour is applied")
	ok(shadowRegion._alpha and math.abs(shadowRegion._alpha - 0.5) < 0.01,
		"the shadow opacity is applied", shadowRegion._alpha)
end

-- A secret amount reaches both sinks by identity, never formatted.
_G.__now = 1301
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", SECRET, SCHOOL_MASK_SHADOW)
local secretMain = _G.__lastNumberFontString
ok(secretMain and secretMain.shadow and secretMain.shadow._text == SECRET,
	"a secret amount reaches the shadow by identity too")

-- Off means off: the custom shadow disappears and the native one stays off.
NS.db.profile.textShadow = false
_G.__now = 1302
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 810, SCHOOL_MASK_FIRE)
local unshadowed = _G.__lastNumberFontString
ok(unshadowed and unshadowed.shadow and unshadowed.shadow._alpha == 0,
	"the custom shadow is invisible when the setting is off")
eq(unshadowed._shadowOffset[1], 0, "the native shadow stays off when the custom one is off")

-- The shadow fades with the text rather than on its own.
NS.db.profile.textShadow = true
_G.__now = 1310
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 820, SCHOOL_MASK_FIRE)
local fading = _G.__lastNumberFontString
_G.__now = 1310.5
local fadeTick = NS.frame and NS.frame._scripts and NS.frame._scripts["OnUpdate"]
if fading and fadeTick then pcall(fadeTick, NS.frame) end
ok(fading and fading.shadow and fading.shadow._alpha and fading.shadow._alpha > 0,
	"the shadow follows the animation alpha")

--------------------------------------------------------------------------------
-- Off-target numbers: a hit on another mob's plate uses the off-target size and opacity
--------------------------------------------------------------------------------

NS.db.profile.displayMode = "nameplates"
NS.db.profile.useOffTargetAppearance = true
NS.db.profile.displayOffTargetText = true
NS.db.profile.textShadow = false
NS.db.profile.formatting.size = 22
NS.db.profile.formatting.alpha = 1
NS.db.profile.offTargetFormatting.size = 11
NS.db.profile.offTargetFormatting.alpha = 0.3

plateFrames["nameplate2"] = CreateFrame("Frame", "Plate2")
_G.__unitIsTarget = "nameplate1"

_G.__now = 1400
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 900, SCHOOL_MASK_FIRE)
local onTargetNumber = _G.__lastNumberFontString
eq(onTargetNumber.NSCTFontSize, 22, "a hit on your target uses the normal size")

_G.__now = 1401
createdFontStrings = {}
FireEvent("UNIT_COMBAT", "nameplate2", "WOUND", "", 901, SCHOOL_MASK_FIRE)
local offTargetNumber = _G.__lastNumberFontString
eq(offTargetNumber.NSCTFontSize, 11, "a hit on another mob's plate uses the off-target size")

_G.__now = 1401.4
local offtick = NS.frame and NS.frame._scripts and NS.frame._scripts["OnUpdate"]
if offtick then pcall(offtick, NS.frame) end
ok(offTargetNumber._alpha and math.abs(offTargetNumber._alpha - 0.3) < 0.05,
	"the off-target opacity is applied while it animates", offTargetNumber._alpha)

-- With off-target text off, the same hit is not drawn at all.
NS.db.profile.displayOffTargetText = false
_G.__now = 1402
createdFontStrings = {}
NS.diagnostics.drawn = 0
FireEvent("UNIT_COMBAT", "nameplate2", "WOUND", "", 902, SCHOOL_MASK_FIRE)
eq(NS.diagnostics.drawn, 0, "off-target text can be switched off completely")
NS.db.profile.displayOffTargetText = true
_G.__unitIsTarget = nil

-- An unknown font falls back to the client's own default, which is right on every locale.
eq(NS.GetFontPath("definitely-not-a-font"), STANDARD_TEXT_FONT,
	"an unknown font resolves to the client default font")

--------------------------------------------------------------------------------
-- Two defects found by wowlua_ls, pinned so they cannot come back
--------------------------------------------------------------------------------

-- AceEvent exposes RegisterEvent/RegisterMessage only; RegisterUnitEvent lives on Frame.
-- The old pcall(self.RegisterUnitEvent, ...) failed silently, so spell attribution was
-- never registered at all.
ok(source and source:find("pcall%(self%.RegisterUnitEvent") == nil,
	"RegisterUnitEvent is never routed through AceEvent")
ok(NS.castFrame ~= nil, "the cast-attribution frame is created on a restricted client")
ok(NS.castFrame and NS.castFrame._events and NS.castFrame._events["UNIT_SPELLCAST_SUCCEEDED"],
	"cast attribution actually registers UNIT_SPELLCAST_SUCCEEDED")

-- Frame:StopMoving does not exist in the client API (it is StopMovingOrSizing), so the
-- window's OnDragStop handler used to throw on every drag release.
ok(settingsText and settingsText:find("StopMovingOrSizing") ~= nil,
	"the drag handler uses the real frame API")
ok(settingsText and settingsText:find("created%.StopMoving%)") == nil,
	"the window never calls the nonexistent Frame:StopMoving")





--------------------------------------------------------------------------------
-- Diagnostics: every drop has a reason, and the window reports it
--------------------------------------------------------------------------------

local d = NS.diagnostics
ok(type(d.dropped) == "table", "the diagnostics carry a drop table")
ok(d.registered == true, "the event source is recorded as subscribed")
ok(type(d.lastDraw) == "number", "the last draw time is recorded")
ok(type(d.secret) == "number", "secret amounts are counted")

NS.db.profile.displayMode = "nameplates"
NS.db.profile.showMisses = true
NS.db.profile.minDamage = 1000000
_G.__now = 1500
local dropsBefore = d.dropped["under the damage threshold"] or 0
FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", 5, SCHOOL_MASK_FIRE)
eq((d.dropped["under the damage threshold"] or 0), dropsBefore + 1, "a hit under the floor records why it was dropped")
eq(d.lastDrop, "under the damage threshold", "the last drop reason is remembered")
NS.db.profile.minDamage = 0

local healBefore = d.dropped["healing is off"] or 0
NS.db.profile.showHealing = false
_G.__now = 1501
FireEvent("UNIT_COMBAT", "nameplate1", "HEAL", "", 10, 0)
ok((d.dropped["healing is off"] or 0) > healBefore, "a heal is counted as dropped when healing is off")
NS.db.profile.showHealing = true

local pooled, active = NS:GetPoolStats()
ok(type(pooled) == "number" and type(active) == "number", "pool statistics are readable")

-- The dashboard's status line reacts to the counters.
local dashboard = NS.settingsDashboard
ok(dashboard ~= nil and dashboard.status ~= nil, "the dashboard exposes its status line")
if dashboard then
	local previous = d.registered
	d.registered = false
	NS:RefreshSettings()
	ok((dashboard.status._text or ""):find("No event source") ~= nil,
		"the status line reports a missing event source", dashboard.status._text)
	d.registered = previous
	NS:RefreshSettings()
end

--------------------------------------------------------------------------------
-- Search: one live row per match, reused between queries
--------------------------------------------------------------------------------

local uiFrame = _G.NameplateSCTSettingsFrame
local searchBox = uiFrame and uiFrame.searchBox
ok(searchBox ~= nil, "the title bar has a search box")

searchBox:SetText("shadow")
searchBox._scripts.OnTextChanged(searchBox)
local searchMatches = NS:SearchSettings("shadow")
ok(searchMatches > 0, "searching finds the shadow settings", searchMatches)
ok(searchBox._text == "shadow", "the search box keeps the query")

local firstRows = {}
for path, entry in pairs(NS.settingsSearchRows or {}) do firstRows[path] = entry end
ok(next(firstRows) ~= nil, "search results create live rows")

NS:SearchSettings("distance")
local kept = 0
for path, entry in pairs(NS.settingsSearchRows or {}) do
	if firstRows[path] == entry then kept = kept + 1 end
end
ok(kept > 0, "rows are reused between queries instead of being recreated")

eq(NS:SearchSettings("zzzz-no-such-setting"), 0, "a query with no match returns nothing")

-- Clearing with ESC returns to the page the search started from.
searchBox._scripts.OnEscapePressed(searchBox)
ok(searchBox._text == "", "ESC clears the search box")



--------------------------------------------------------------------------------
-- Colour picker, window size and backup
--------------------------------------------------------------------------------

local function controlFor(path)
	for _, control in ipairs(NS.settingsControls or {}) do
		if control.path == path and control.control then return control end
	end
end

local function openMenus()
	local count = 0
	for _, frame in ipairs(createdFrames) do
		if frame._name == "NameplateSCTSelectMenu" and frame:IsShown() then count = count + 1 end
	end
	return count
end

ok(NS.isForever == true, "the client identity is exported for the window to label")
ok(uiFrame.subtitle and tostring(uiFrame.subtitle._text):find("Forever", 1, true) ~= nil,
	"the window labels this client as Forever, not Classic", uiFrame.subtitle and uiFrame.subtitle._text)

eq(uiFrame:GetWidth(), 1200, "the window is 1200 wide")
eq(uiFrame:GetHeight(), 800, "the window is 800 tall")
ok(uiFrame.fitScale and uiFrame.fitScale > 0 and uiFrame.fitScale <= 1,
	"the window scales to fit the screen", uiFrame.fitScale)

local dashboardShadow = false
for _, control in ipairs(NS.settingsControls or {}) do
	if control.page == "dashboard" and control.path == "shadow.size" then dashboardShadow = true end
end
ok(dashboardShadow, "the dashboard carries the shadow controls")

-- Colour picker: the swatch opens the one shared menu and writes the hex value.
NS.db.profile.useMissColor = true
NS:RefreshSettings()
local missColour = controlFor("missColor")
ok(missColour ~= nil and missColour.swatch ~= nil, "colour fields have a swatch")
if missColour and missColour.swatch then
	local swatch = missColour.swatch
	pcall(swatch._scripts.OnClick, swatch)
	eq(openMenus(), 1, "the palette uses the one shared menu")

	local preset
	for _, row in ipairs(NS.selectMenuRows or {}) do
		if row.option and row.option.swatch and row.option.swatch ~= NS.db.profile.missColor then
			preset = row
			break
		end
	end
	ok(preset ~= nil, "the palette lists colour presets")
	if preset then
		preset._scripts.OnClick(preset)
		eq(openMenus(), 0, "picking a colour closes the palette")
		eq(NS.db.profile.missColor, preset.option.swatch, "picking a swatch writes its hex value")
	end
end
NS.db.profile.useMissColor = false

-- Backup: export, change, import back.
local exported = NS:ExportSettings()
ok(type(exported) == "string" and exported:sub(1, #"NameplateSCT settings v1") == "NameplateSCT settings v1",
	"the exported block starts with its header")
ok(exported:find("formatting.size=", 1, true) ~= nil, "the export contains the settings")

local originalSize = NS.db.profile.formatting.size
NS.db.profile.formatting.size = 55
local applied, refused = NS:ImportSettings(exported)
ok(applied > 40 and refused == 0, "a full settings block imports",
	("%d applied, %d refused"):format(applied or -1, refused or -1))
eq(NS.db.profile.formatting.size, originalSize, "importing restores a changed value")

-- Multiline lists survive the line-based format.
NS.db.profile.filter = "spell one\nspell two"
local roundTrip = NS:ExportSettings()
NS.db.profile.filter = ""
NS:ImportSettings(roundTrip)
eq(NS.db.profile.filter, "spell one\nspell two", "a multiline value survives export and import")

-- Unknown keys are refused, not written.
local badApplied, badRefused = NS:ImportSettings(
	"NameplateSCT settings v1\nnot.a.real.key=1\nformatting.size=33")
eq(badApplied, 1, "a known line in a mixed block is applied")
eq(badRefused, 1, "an unknown key is refused")
ok(NS.db.profile["not"] == nil, "an unknown key is not created in the profile")
NS.db.profile.filter = ""

-- A key whose runtime type differs from its default representation still imports correctly.
NS:ImportSettings("NameplateSCT settings v1\nstrata.target=5")
eq(NS.db.profile.strata.target, 5, "a numeric stratum imports as a number, not a string")

-- Nothing is applied without the header, and nothing is ever executed.
local garbageApplied, garbageRefused = NS:ImportSettings("return os.exit(1)")
ok(garbageApplied == 0 and garbageRefused < 0, "a block without the header is refused")
ok(_G.__executed == nil, "pasted text is parsed, never executed")
NS:RefreshSettings()

--------------------------------------------------------------------------------
-- Wiring audit: a control must write exactly the setting it declares, and every saved
-- setting must actually be read by the addon. Both are proved, not assumed.
--------------------------------------------------------------------------------

local function profileGet(path)
	local node = NS.db.profile
	for part in path:gmatch("[^.]+") do
		if type(node) ~= "table" then return nil end
		node = node[part]
	end
	return node
end

local function leafSnapshot()
	local snapshot = {}
	local function walk(node, prefix)
		for key, value in pairs(node) do
			local path = prefix == "" and key or (prefix .. "." .. key)
			if type(value) == "table" then walk(value, path) else snapshot[path] = value end
		end
	end
	walk(NS.db.profile, "")
	return snapshot
end

local function changedPaths(before, after)
	local changed = {}
	for path, value in pairs(after) do
		if before[path] ~= value then changed[#changed + 1] = path end
	end
	for path in pairs(before) do
		if after[path] == nil then changed[#changed + 1] = path end
	end
	table.sort(changed)
	return changed
end

local function writeSample(control)
	local current = profileGet(control.path)
	if control.kind == "toggle" then
		return not (current and true)
	elseif control.kind == "slider" then
		local minimum, maximum = control.min or 0, control.max or 100
		return current == minimum and maximum or minimum
	elseif control.kind == "select" then
		for _, option in ipairs(control.options or {}) do
			if option.value ~= current then return option.value end
		end
		return nil
	elseif control.kind == "hex" then
		return "a1b2c3"
	end
	return "sample line one"
end

local writeProblems = {}
for _, control in ipairs(controls) do
	local sample = writeSample(control)
	if sample == nil then
		writeProblems[#writeProblems + 1] = control.path .. " (no distinct value)"
	else
		local before = leafSnapshot()
		control.set(sample)
		local changed = changedPaths(before, leafSnapshot())
		local stored = profileGet(control.path)
		local expected = sample
		if control.kind == "hex" then expected = "a1b2c3" end

		if #changed ~= 1 or changed[1] ~= control.path then
			writeProblems[#writeProblems + 1] = control.path .. " wrote " .. table.concat(changed, "+")
		elseif stored ~= expected then
			writeProblems[#writeProblems + 1] = control.path .. " stored " .. tostring(stored)
		end

		-- Put the original value back so later checks see the profile they expected.
		control.set(profileGet(control.path) == before[control.path] and before[control.path] or before[control.path])
	end
end
ok(#writeProblems == 0, "every control writes exactly its own setting, nothing else",
	#writeProblems > 0 and table.concat(writeProblems, "; ") or nil)

-- Each setting must be consumed by the addon, not merely saved. Paths are matched with the
-- known aliases of db.profile (the code renames it to `global` twice).
local addonHandle = io.open(addonDir .. "NameplateSCT.lua", "r")
local addonText = addonHandle and addonHandle:read("*a")
if addonHandle then addonHandle:close() end
-- Bracket indexing is normalised to dot form first, so `profile["font"]` counts as a read.
local flat = (addonText or ""):gsub("%s+", "")
	:gsub('%[%s*"(.-)"%s*%]', ".%1")
	:gsub("%[%s*'(.-)'%s*%]", ".%1")

local aliases = { profile = true }
for name in flat:gmatch("local([%w_]+)=[%w_%.]-db%.profile") do aliases[name] = true end

-- Screen areas are read through one dynamic index (`area[key .. "X"]`), which no textual
-- scan can resolve, so they are accepted here with the reason recorded.
local readThroughDynamicIndex = {
	screen = "GetScreenAnchor / RefreshScreenAnchors index screen[key .. 'X']",
}

local unread = {}
for path in pairs(defaultsSet) do
	if readThroughDynamicIndex[path:match("^([%w_]+)%.")] then
		unread = unread
	else
	local escaped = path:gsub("%p", "%%%0")
	local found = false
	for alias in pairs(aliases) do
		if flat:find(alias .. "%." .. escaped) then found = true break end
	end
	if not found and path:find("%.") then
		-- nested tables may be held in a local of their own
		found = flat:find("%." .. escaped) ~= nil
	end
		if not found then unread[#unread + 1] = path end
	end
end
table.sort(unread)
ok(#unread == 0, "every saved setting is read by the addon",
	#unread > 0 and table.concat(unread, ", ") or nil)


--------------------------------------------------------------------------------
-- Window chrome, the shared selection menu and input validation
--------------------------------------------------------------------------------

local settingsFrame = _G.NameplateSCTSettingsFrame
ok(settingsFrame ~= nil, "the settings window exists")

local byPath = {}
for _, control in ipairs(NS.settingsControls or {}) do byPath[control.path] = control end

-- The page header follows the selection, so the window always says where you are.
settingsFrame:SelectPage("numbers")
eq(settingsFrame.pageTitle._text, "Numbers", "the page header names the page")
ok(tostring(settingsFrame.pageDescription._text or ""):find("Formatting") ~= nil,
	"the page header explains what the page is for")

-- Exactly one selection menu exists for the whole window, and a second selection reuses
-- it: the "two dropdowns at once" failure is structural, not a timing race.
local function shownMenus()
	local count = 0
	for _, frame in ipairs(createdFrames) do
		if frame._name == "NameplateSCTSelectMenu" and frame:IsShown() then count = count + 1 end
	end
	return count
end

local function menuObjects()
	local count = 0
	for _, frame in ipairs(createdFrames) do
		if frame._name == "NameplateSCTSelectMenu" then count = count + 1 end
	end
	return count
end

local modeButton = byPath.displayMode and byPath.displayMode.control
local fontButton = byPath.font and byPath.font.control
ok(modeButton ~= nil and fontButton ~= nil, "selection rows expose their control")

local openOk, openErr = pcall(modeButton._scripts.OnClick, modeButton)
ok(openOk, "opening a selection does not raise", openErr)
eq(shownMenus(), 1, "opening a selection shows exactly one menu")
ok(menuObjects() == 1, "the addon owns a single menu object", menuObjects())

local menuIdentity = NS.selectMenu
pcall(fontButton._scripts.OnClick, fontButton)
ok(NS.selectMenu == menuIdentity, "a second selection reuses the same menu")
eq(shownMenus(), 1, "two menus are never on screen at once")
ok(menuObjects() == 1, "opening a second selection cannot create a second menu", menuObjects())

-- Picking a value closes the menu and writes it. The mode row owns the menu again, so the
-- value that lands must be displayMode.
pcall(modeButton._scripts.OnClick, modeButton)
local originalMode = NS.db.profile.displayMode
local pick
for _, row in ipairs(NS.selectMenuRows or {}) do
	if row.option and row.option.value ~= originalMode then pick = row break end
end
ok(pick ~= nil, "the menu lists the alternatives")

local pickOk, pickErr = pcall(pick._scripts.OnClick, pick)
ok(pickOk, "picking a value does not raise", pickErr)
eq(shownMenus(), 0, "picking closes the menu")
ok(NS.db.profile.displayMode ~= originalMode, "picking writes the chosen value")
NS.db.profile.displayMode = originalMode

-- Clicking the row that is already open closes it instead of stacking another.
pcall(modeButton._scripts.OnClick, modeButton)
eq(shownMenus(), 1, "reopening shows the menu")
pcall(modeButton._scripts.OnClick, modeButton)
eq(shownMenus(), 0, "clicking the open row again closes its menu")

-- A colour field rejects bad input without writing it, and flags the field.
NS.db.profile.useMissColor = true
NS:RefreshSettings()
local hexBox = byPath.missColor and byPath.missColor.control
ok(hexBox ~= nil, "the miss colour field exists")
local originalHex = NS.db.profile.missColor
if hexBox then
	hexBox:SetText("not-a-colour")
	hexBox._scripts.OnEnterPressed(hexBox)
	eq(NS.db.profile.missColor, originalHex, "an invalid hex value is not saved")
	ok(hexBox._ring and hexBox._ring._color and hexBox._ring._color[1] > 0.8,
		"an invalid hex value flags the field red")

	hexBox:SetText("abc123")
	hexBox._scripts.OnEnterPressed(hexBox)
	eq(NS.db.profile.missColor, "abc123", "a valid hex value is saved")
end
NS.db.profile.useMissColor = false

-- The footer reports state, which is where a rejected value is explained.
NS:SetStatus("check the field", "warning")
eq(settingsFrame.statusText._text, "check the field", "the footer reports a message")

-- Pages are taller than their viewport: without clipping the rows would draw over the
-- bottom edge of the window, which is exactly what the first in-game screenshot showed.
local unclipped = {}
for pageId, viewport in pairs(uiFrame.pages or {}) do
	if viewport._clipsChildren ~= true then unclipped[#unclipped + 1] = pageId end
end
ok(#unclipped == 0, "every page clips its content to the viewport",
	#unclipped > 0 and table.concat(unclipped, ", ") or nil)

-- Wheel direction: a wheel-down notch scrolls down (content moves up), wheel-up returns.
local generalPage = uiFrame.pages and uiFrame.pages.general
ok(generalPage ~= nil and generalPage._scripts and generalPage._scripts.OnMouseWheel ~= nil,
	"the page viewport handles the wheel")
if generalPage and generalPage._scripts and generalPage._scripts.OnMouseWheel then
	generalPage:SetContentHeight(2000)
	generalPage._scripts.OnMouseWheel(generalPage, -1)
	ok(generalPage.content._point and generalPage.content._point[3] == 60,
		"a wheel-down notch scrolls down", generalPage.content._point and generalPage.content._point[3])

	generalPage._scripts.OnMouseWheel(generalPage, 1)
	ok(generalPage.content._point and generalPage.content._point[3] == 0,
		"a wheel-up notch scrolls back toward the top", generalPage.content._point and generalPage.content._point[3])
	generalPage:ResetScroll()
	generalPage:SetContentHeight(0)
end

-- The Appearance page previews the number with the live styling, so the shadow can be
-- tuned by looking at it instead of guessing.
local preview = NS.settingsPreview
ok(preview ~= nil and preview[1] and preview[1].text ~= nil, "the appearance page has a preview")
if preview then
	NS.db.profile.textShadow = true
	NS.db.profile.shadow.size = 2
	NS:RefreshSettings()
	eq(preview[1].text._text, "1,234", "the preview shows a sample number")
	ok(preview[1].shadow and preview[1].shadow:IsShown(), "the preview shows the shadow while it is on")
	ok(preview[1].shadow._font and preview[1].text._font
		and preview[1].shadow._font.size > preview[1].text._font.size,
		"the preview shadow tracks the size setting")

	NS.db.profile.textShadow = false
	NS:RefreshSettings()
	ok(preview[1].shadow and not preview[1].shadow:IsShown(),
		"the preview hides the shadow while it is off")
	NS.db.profile.textShadow = true
end

-- Resetting one page restores that page only.
NS.db.profile.formatting.size = 44
NS.db.profile.showMisses = false
NS:ResetPage("numbers")
eq(NS.db.profile.formatting.size, 20, "reset page restores a default")
eq(NS.db.profile.showMisses, false, "reset page leaves other pages alone")
NS.db.profile.showMisses = true

-- Settings the restricted client cannot honour are shown disabled and say why; the ones it
-- can honour stay usable.
local gateProblems = {}
for path in pairs(NS.cleuOnlySettings or {}) do
	local control = byPath[path]
	if not control or not control.control then
		gateProblems[#gateProblems + 1] = path .. " (no control)"
	else
		control.control:Refresh()
		if not control.control.isDisabled then gateProblems[#gateProblems + 1] = path .. " (enabled)" end
		if not tostring(control.label or ""):find("combat log only", 1, true) then
			gateProblems[#gateProblems + 1] = path .. " (label)"
		end
	end
end
ok(#gateProblems == 0, "settings this client cannot honour are disabled, with the reason",
	#gateProblems > 0 and table.concat(gateProblems, "; ") or nil)

local wronglyDisabled = {}
for _, control in ipairs(NS.settingsControls or {}) do
	if not control.gated and control.control then
		control.control:Refresh()
		if control.control.isDisabled then wronglyDisabled[#wronglyDisabled + 1] = control.path end
	end
end
ok(#wronglyDisabled == 0, "settings that do apply on this client stay enabled",
	#wronglyDisabled > 0 and table.concat(wronglyDisabled, ", ") or nil)

--------------------------------------------------------------------------------

print(("\n%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
