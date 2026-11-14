---------------
-- LIBRARIES --
---------------
---@class NameplateSCT_LibEasing
---@field InQuad fun(t: number, b: number, c: number, d: number): number
---@field OutQuint fun(t: number, b: number, c: number, d: number): number
---@field InQuint fun(t: number, b: number, c: number, d: number): number
---@field InExpo fun(t: number, b: number, c: number, d: number): number

local AceAddon = assert(LibStub("AceAddon-3.0"), "NameplateSCT requires AceAddon-3.0")
---@type NameplateSCT_LibEasing
local LibEasing = assert(LibStub("LibEasing-1.0"), "NameplateSCT requires LibEasing-1.0")
local SharedMedia = assert(LibStub("LibSharedMedia-3.0"), "NameplateSCT requires LibSharedMedia-3.0")
local AceLocale = assert(LibStub("AceLocale-3.0"), "NameplateSCT requires AceLocale-3.0")
local L = AceLocale:GetLocale("NameplateSCT")
local MSQ = LibStub("Masque", true)

---@class NameplateSCT : AceAddon-3.0, AceConsole-3.0, AceEvent-3.0
---@field db any
---@field frame Frame
---@field W any palette and widget helpers, installed by Options/Widgets.lua
---@field OpenDashboard (fun(self: NameplateSCT))? installed by Options/Settings.lua
local NameplateSCT = AceAddon:NewAddon("NameplateSCT", "AceConsole-3.0", "AceEvent-3.0")
-- AceAddon keeps the addon table in its own registry; it does NOT publish it under the
-- addon's name. Options/Widgets.lua and Options/Settings.lua look the object up as
-- _G.NameplateSCT, so without this line both modules return at their first statement: no
-- palette, no dashboard, and /nsct silently falls through to the Blizzard AddOns panel.
_G.NameplateSCT = NameplateSCT
NameplateSCT.frame = CreateFrame("Frame", nil, UIParent)

-------------------
-- COMPATIBILITY --
-------------------

local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local _, _, _, build = GetBuildInfo()
local numericBuild = tonumber(build) or 0
local WOW_PROJECT_CAMELOT = _G.WOW_PROJECT_CAMELOT or 18
local isForever = (WOW_PROJECT_ID == WOW_PROJECT_CAMELOT) or (numericBuild >= 16000 and numericBuild < 17000)
local isMidnight = (numericBuild >= 120000)
local isModernCvar = isMidnight or isForever
local blizzardCvar = isModernCvar and "floatingCombatTextCombatDamage_v2" or "floatingCombatTextCombatDamage"
NameplateSCT.blizzardCVar = blizzardCvar

-- Blizzard has two separate floating combat-text renderers:
--
--   1. Blizzard_CombatText (Scrolling Combat Text on the player): gated by the master
--      `enableFloatingCombatText` CVar via `CombatTextUtil.UpdateEventRegistration`.
--   2. In-world 3D combat text (damage/healing/pet/mechanics over targets): rendered by the
--      engine directly and gated by the per-category `floatingCombatText*` CVars
--      (`_v2` on modern/Forever clients, plain names on Classic clients).
--
-- Turning off only `enableFloatingCombatText` + 4 `_v2` CVars left auto-attacks
-- (`floatingCombatTextCombatDamageAllAutos_v2`), pet melee/spell damage, target healing,
-- spell mechanics, and non-`_v2` CVars active on Forever, so Blizzard's world numbers kept
-- drawing alongside NameplateSCT.
local BLIZZARD_FCT_MASTER_CVAR = "enableFloatingCombatText"
NameplateSCT.blizzardFCTMasterCVar = BLIZZARD_FCT_MASTER_CVAR

-- Every boolean `floatingCombatText*` toggle exposed across supported WoW clients.
-- Any CVar the running client does not expose returns nil from GetCVar and is skipped.
local BLIZZARD_TEXT_BASENAMES = {
	"floatingCombatTextCombatDamage",
	"floatingCombatTextCombatDamageAllAutos",
	"floatingCombatTextCombatHealing",
	"floatingCombatTextCombatHealingAbsorbSelf",
	"floatingCombatTextCombatHealingAbsorbTarget",
	"floatingCombatTextCombatLogPeriodicSpells",
	"floatingCombatTextPetMeleeDamage",
	"floatingCombatTextPetSpellDamage",
	"floatingCombatTextDodgeParryMiss",
	"floatingCombatTextDamageReduction",
	"floatingCombatTextSpellMechanics",
	"floatingCombatTextSpellMechanicsOther",
	"floatingCombatTextAllSpellMechanics",
	"floatingCombatTextAuras",
	"floatingCombatTextAuraFade",
	"floatingCombatTextHonorGains",
	"floatingCombatTextEnergyGains",
	"floatingCombatTextPeriodicEnergyGains",
	"floatingCombatTextReactives",
	"floatingCombatTextFriendlyHealers",
	"floatingCombatTextComboPoints",
	"floatingCombatTextLowManaHealth",
	"floatingCombatTextRepChanges",
	"floatingCombatTextCombatState",
}

local blizzardTextCvars = {}
local blizzardFCTSet = {}
do
	blizzardFCTSet[string.lower(BLIZZARD_FCT_MASTER_CVAR)] = BLIZZARD_FCT_MASTER_CVAR
	local primarySuffix = isModernCvar and "_v2" or ""
	local secondarySuffix = isModernCvar and "" or "_v2"
	for _, base in ipairs(BLIZZARD_TEXT_BASENAMES) do
		local primary = base .. primarySuffix
		blizzardTextCvars[#blizzardTextCvars + 1] = primary
		blizzardFCTSet[string.lower(primary)] = primary
	end
	for _, base in ipairs(BLIZZARD_TEXT_BASENAMES) do
		local secondary = base .. secondarySuffix
		blizzardTextCvars[#blizzardTextCvars + 1] = secondary
		blizzardFCTSet[string.lower(secondary)] = secondary
	end
end
NameplateSCT.blizzardTextCVars = blizzardTextCvars

-- issecretvalue / canaccessvalue are documented on every supported client (live, classic,
-- classic_era, classic_anniversary and forever). Classic clients pass them through: they
-- answer "not secret" and "accessible" without caring about taint at all, so the same code
-- path is correct on both families. Both take one value and return one bool.
---@secret-guard value is-secret
---@param value any
---@return boolean
local function isSecretValue(value)
	local ok, secret = pcall(issecretvalue, value)
	-- a refused issecretvalue means "we are not allowed to know": treat it as secret
	return (not ok) or secret == true
end

-- UnitIsUnit returns a single bool and is SecretWhenUnitComparisonRestricted; a refusal
-- reads as "not the same unit". The second return is this helper's own contract and tells
-- the caller whether the client answered at all.
---@param unit1 string?
---@param unit2 string?
---@return boolean isTarget
---@return boolean answered
local function safeUnitIsUnit(unit1, unit2)
	if not unit1 or not unit2 then return false, false end

	-- UnitIsUnit returns nothing when the tokens cannot be compared
	-- (precondition CanCompareUnitTokens), so ask that first.
	local canCompare = C_Secrets and C_Secrets.CanCompareUnitTokens
	if canCompare then
		local compared, allowed = pcall(canCompare, unit1, unit2)
		if not compared or allowed ~= true then
			NameplateSCT.diagnostics.refused = NameplateSCT.diagnostics.refused + 1
			return false, false
		end
	end

	local ok, same = pcall(UnitIsUnit, unit1, unit2)
	if not ok or not canaccessvalue(same) then
		NameplateSCT.diagnostics.refused = NameplateSCT.diagnostics.refused + 1
		return false, false
	end
	if isSecretValue(same) then return false, false end

	return same == true, true
end

-- C_NamePlate.GetNamePlateForUnit only accepts tokens that can own a nameplate and raises
-- ("Target-of-target unit tokens are not allowed for this call") on a token that names a
-- unit's target. UNIT_COMBAT does report those aliases ("targettarget", "pettarget", ...),
-- so they are recognised here and never reach the client.
---@param unit string?
---@return boolean
local function isTargetOfTargetToken(unit)
	if type(unit) ~= "string" or unit == "target" then return false end
	return string.sub(unit, -6) == "target"
end

-- Resolve a unit token to its nameplate frame, or nil when the client must not be asked.
-- A target-of-target has no plate to resolve, so a nameplate-anchored draw is skipped for
-- it while screen mode (which needs no plate) still draws it.
-- The character unit frame, used when numbers about you are mounted there instead of a screen
-- area. PlayerFrame is the client's own frame (retail, classic and Forever all name it that);
-- returning nil keeps the number on screen instead of dropping it.
---@return Frame?
local function getPlayerUnitFrameAnchor()
	local frame = _G.PlayerFrame
	if type(frame) == "table" and type(frame.IsShown) == "function" then
		local ok, shown = pcall(frame.IsShown, frame)
		if ok and shown then return frame end
	end
	return nil
end

---@param unit string?
---@return Frame?
local function getNamePlateForUnit(unit)
	if not unit or isSecretValue(unit) or isTargetOfTargetToken(unit) then return nil end
	local namePlates = C_NamePlate
	if not namePlates or not namePlates.GetNamePlateForUnit then return nil end
	return namePlates.GetNamePlateForUnit(unit)
end

-- Does this build restrict combat events for addons? Forever and Midnight always do;
-- other clients answer through the predicates and are unrestricted.
local function clientHasCombatRestrictions()
	if isForever then
		return true
	end

	local ok, restricted = pcall(function()
		return (C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions())
			or (C_CombatLog and C_CombatLog.IsCombatLogRestricted and C_CombatLog.IsCombatLogRestricted())
	end)

	return ok and restricted == true
end

local hasCombatRestrictions = clientHasCombatRestrictions()

NameplateSCT.hasCombatRestrictions = hasCombatRestrictions
-- Exported for the settings window, which labels the client and picks the right CVar name
-- from these. They are file locals, and a missing export is invisible until the UI shows
-- "Classic" on a Forever client.
NameplateSCT.isForever = isForever
NameplateSCT.isMidnight = isMidnight

-- Live counters read by the options dashboard, so "no numbers" can be diagnosed instead of
-- guessed: a counter that never moves points at the event source, not at the styling.
NameplateSCT.diagnostics = {
	path = hasCombatRestrictions and "unit" or "cleu",
	event = hasCombatRestrictions and "UNIT_COMBAT" or "COMBAT_LOG_EVENT_UNFILTERED",
	events = 0,
	drawn = 0,
	misses = 0,
	secret = 0,
	duplicates = 0,
	refused = 0,
	lastEvent = 0,
	lastDraw = 0,
	lastDropAt = 0,
	lastDrop = nil,
	dropped = {},
	startedAt = 0,
}

-- Drop accounting: every early return in the combat paths records why, so "events arrive but
-- nothing is drawn" can be answered with a reason instead of a guess.
---@param reason string
local function countDrop(reason)
	local d = NameplateSCT.diagnostics
	if not d then return end
	d.dropped[reason] = (d.dropped[reason] or 0) + 1
	d.lastDrop = reason
	d.lastDropAt = GetTime()
end
NameplateSCT.countDrop = countDrop

------------
-- LOCALS --
------------

local _
local optionsMenuName
local animating = {}
local randomX = {}
local randomY = {}

local playerGUID
local unitToGuid = {}
local guidToUnit = {}

local animationValues = {
	-- ["shake"] = L["Shake"],
	["verticalUp"] = L["Vertical Up"],
	["verticalDown"] = L["Vertical Down"],
	["fountain"] = L["Fountain"],
	["rainfall"] = L["Rainfall"],
	["fireworks"] = L["Fireworks"],
	["disabled"] = L["Disabled"]
}

local inversePositions = {
	["BOTTOM"]      = "TOP",
	["LEFT"]        = "RIGHT",
	["TOP"]         = "BOTTOM",
	["RIGHT"]       = "LEFT",
	["TOPLEFT"]     = "BOTTOMRIGHT",
	["TOPRIGHT"]    = "BOTTOMLEFT",
	["BOTTOMLEFT"]  = "TOPRIGHT",
	["BOTTOMRIGHT"] = "TOPLEFT",
	["CENTER"]      = "CENTER"
}

--------
-- DB --
--------
if MSQ then
	---@type any
	NameplateSCT.frame.MSQGroup = MSQ:Group("NameplateSCT")
end

local defaultFont = "Friz Quadrata TT"
if (SharedMedia:IsValid("font", "Bazooka")) then
	defaultFont = "Bazooka"
end

-- Settings live in the AceDB *profile* namespace, so AceDB profiles (and AceDBOptions)
-- actually do something. `global` would be a single shared table across every profile.
local defaults = {
	profile = {
		enabled = true,
		shouldDisplayOverkill = false,
		showAbsorbDamage = true,
		xOffset = 0,
		yOffset = 0,
		-- Show numbers on your own nameplate for damage you take. Off keeps the same
		-- behaviour the combat-log path has always had with an unset value.
		personal = false,
		personalOnly = false,
		xOffsetPersonal = 0,
		yOffsetPersonal = -100,

		modOffTargetStrata = false,
		strata = {
			target = "HIGH",
			offTarget = "MEDIUM",
		},

		font = defaultFont,
		fontFlag = "OUTLINE",
		textShadow = false,
		-- A drop shadow drawn as a second FontString under the number. The client's own
		-- SetShadowOffset is a fixed 1px copy: no size, distance, angle or colour. The
		-- defaults here reproduce exactly that old 1px black shadow.
		shadow = {
			size = 1,
			distance = 1.5,
			angle = 315,
			color = "000000",
			alpha = 1,
		},
		damageColor = true,
		defaultColor = "ffffff",
		useCritColor = false,
		critColor = "ffff00",
		useMissColor = false,
		missColor = "ffffff",

		-- One switch per kind of hit the addon can draw, so every category the client reports
		-- has a control instead of a yes for some and a silent no for others.
		showMeleeDamage = true,
		showSpellDamage = true,
		showRangedDamage = true,
		showPeriodicDamage = true,
		showHealing = true,
		-- Pet damage is only distinguishable in the combat log; UNIT_COMBAT carries no source.
		showPetDamage = true,

		healColor = "00ff00",
		useHealCritColor = false,
		healCritColor = "33ff66",

		showIcon = false,
		showIconOnly = false,
		removeBorder = false,
		enableMSQ = true,
		iconScale = 1,
		iconPosition = "RIGHT",
		xOffsetIcon = 0,
		yOffsetIcon = 0,
		xVariance = 0,
		yVariance = 0,

		damageColorPersonal = false,
		defaultColorPersonal = "ff0000",
		useMissColorPersonal = false,
		missColorPersonal = "ffffff",

		truncateMethod = 'WESTERN',
		truncateLetter = true,
		commaSeperate = true,

		sizing = {
			crits = true,
			critsScale = 1.5,

			miss = false,
			missScale = 1.5,

			smallHits = true,
			smallHitsScale = 0.66,
			smallHitsHide = false,
			autoattackcritsizing = true,
			hideSmallHitsThreshold = 0,
		},

		animations = {
			ability = "fountain",
			crit = "verticalUp",
			miss = "verticalUp",
			heal = "verticalUp",
			healCrit = "verticalUp",
			autoattack = "fountain",
			autoattackcrit = "verticalUp",
			animationspeed = 1,
			fireworksRadius = 100,
			fireworksDuration = 1,
		},

		animationsPersonal = {
			normal = "rainfall",
			crit = "verticalUp",
			miss = "verticalUp",
		},

		formatting = {
			size = 20,
			alpha = 1,
		},

		-- Where numbers are drawn. "nameplates" anchors each number to its plate,
		-- "screen" anchors it to a fixed area on screen (the mode PlateSCT offers).
		displayMode = "nameplates",
		-- Where numbers about you (damage you take, heals on you) are mounted: a screen area,
		-- or your character unit frame.
		personalAnchor = "screen",
		screen = {
			outgoingX = 0,
			outgoingY = -140,
			incomingX = 0,
			incomingY = 110,
		},

		-- Suppress hits below this value outright (independent of the relative
		-- small-hit scaling below).
		minDamage = 0,
		showMisses = true,
		-- Blizzard also draws nameplate damage numbers; leave both on and they double up.
		hideBlizzardFCT = true,

		useOffTargetAppearance = true,
		displayOffTargetText = true,
		offTargetFormatting = {
			size = 15,
			alpha = 0.5,
		},
		filterEnabled = false,
		inverseSpellFilter = false,
		inverseNPCFilter = false,
		filter = "",
		npcFilter = "",
	},
}

-- The settings window resets one page at a time from this schema.
NameplateSCT.defaults = defaults

local filtersTable = {}

function NameplateSCT:updateFilterTable(filterData)
	NameplateSCT.db.profile.filter = filterData
	local splitData = { strsplit("\n", filterData) }
	filtersTable = {}
	for _, spellInfo in ipairs(splitData) do
		filtersTable[spellInfo] = true
	end
end

local npcFiltersTable = {}

function NameplateSCT:updateNPCFilterTable(npcFilterData)
	NameplateSCT.db.profile.npcFilter = npcFilterData
	local splitData = { strsplit("\n", npcFilterData) }
	npcFiltersTable = {}
	for _, npcId in ipairs(splitData) do
		npcFiltersTable[npcId] = true
	end
end

---------------------
-- LOCAL CONSTANTS --
---------------------

local SMALL_HIT_EXPIRY_WINDOW = 30
local SMALL_HIT_MULTIPIER = 0.5

local ANIMATION_VERTICAL_DISTANCE = 75

local ANIMATION_ARC_X_MIN = 50
local ANIMATION_ARC_X_MAX = 150
local ANIMATION_ARC_Y_TOP_MIN = 10
local ANIMATION_ARC_Y_TOP_MAX = 50
local ANIMATION_ARC_Y_BOTTOM_MIN = 10
local ANIMATION_ARC_Y_BOTTOM_MAX = 50

-- local ANIMATION_SHAKE_DEFLECTION = 15
-- local ANIMATION_SHAKE_NUM_SHAKES = 4

local ANIMATION_RAINFALL_X_MAX = 75
local ANIMATION_RAINFALL_Y_MIN = 50
local ANIMATION_RAINFALL_Y_MAX = 100
local ANIMATION_RAINFALL_Y_START_MIN = 5
local ANIMATION_RAINFALL_Y_START_MAX = 15

if not SCHOOL_MASK_PHYSICAL then -- XXX 9.1 PTR Support
	SCHOOL_MASK_PHYSICAL = Enum.Damageclass.MaskPhysical
	SCHOOL_MASK_HOLY = Enum.Damageclass.MaskHoly
	SCHOOL_MASK_FIRE = Enum.Damageclass.MaskFire
	SCHOOL_MASK_NATURE = Enum.Damageclass.MaskNature
	SCHOOL_MASK_FROST = Enum.Damageclass.MaskFrost
	SCHOOL_MASK_SHADOW = Enum.Damageclass.MaskShadow
	SCHOOL_MASK_ARCANE = Enum.Damageclass.MaskArcane
end


local DAMAGE_TYPE_COLORS = {
	[SCHOOL_MASK_PHYSICAL] = "FFFF00",
	[SCHOOL_MASK_HOLY] = "FFE680",
	[SCHOOL_MASK_FIRE] = "FF8000",
	[SCHOOL_MASK_NATURE] = "4DFF4D",
	[SCHOOL_MASK_FROST] = "80FFFF",
	[SCHOOL_MASK_SHADOW] = "8080FF",
	[SCHOOL_MASK_ARCANE] = "FF80FF",
	[SCHOOL_MASK_HOLY + SCHOOL_MASK_PHYSICAL] = "FFF240",                                                          -- Holystrike
	[SCHOOL_MASK_FIRE + SCHOOL_MASK_PHYSICAL] = "FFB900",                                                          -- Flamestrike
	[SCHOOL_MASK_FIRE + SCHOOL_MASK_HOLY] = "FFD266",                                                              -- Radiant
	[SCHOOL_MASK_NATURE + SCHOOL_MASK_PHYSICAL] = "AFFF23",                                                        -- Stormstrike
	[SCHOOL_MASK_HOLY + SCHOOL_MASK_NATURE] = "C1EF6E",                                                            -- Holystorm
	[SCHOOL_MASK_NATURE + SCHOOL_MASK_FIRE] = "AFB923",                                                            -- Volcanic
	[SCHOOL_MASK_FROST + SCHOOL_MASK_PHYSICAL] = "B3FF99",                                                         -- Froststrike
	[SCHOOL_MASK_HOLY + SCHOOL_MASK_FROST] = "CCF0B3",                                                             -- Holyfrost
	[SCHOOL_MASK_FROST + SCHOOL_MASK_FIRE] = "C0C080",                                                             -- Frostfire
	[SCHOOL_MASK_FROST + SCHOOL_MASK_NATURE] = "69FFAF",                                                           -- Froststorm
	[SCHOOL_MASK_SHADOW + SCHOOL_MASK_PHYSICAL] = "C6C673",                                                        -- Shadowstrike
	[SCHOOL_MASK_HOLY + SCHOOL_MASK_SHADOW] = "D3C2AC",                                                            -- Twilight
	[SCHOOL_MASK_SHADOW + SCHOOL_MASK_FIRE] = "B38099",                                                            -- Shadowflame
	[SCHOOL_MASK_SHADOW + SCHOOL_MASK_NATURE] = "6CB3B8",                                                          -- Plague
	[SCHOOL_MASK_SHADOW + SCHOOL_MASK_FROST] = "80C6FF",                                                           -- Shadowfrost
	[SCHOOL_MASK_ARCANE + SCHOOL_MASK_PHYSICAL] = "FFCC66",                                                        -- Spellstrike
	[SCHOOL_MASK_ARCANE + SCHOOL_MASK_HOLY] = "FFCC66",                                                            -- Divine
	[SCHOOL_MASK_ARCANE + SCHOOL_MASK_FIRE] = "FF808C",                                                            -- Spellfire
	[SCHOOL_MASK_ARCANE + SCHOOL_MASK_NATURE] = "AFB9AF",                                                          -- Astral
	[SCHOOL_MASK_ARCANE + SCHOOL_MASK_FROST] = "C0C0FF",                                                           -- Spellfrost
	[SCHOOL_MASK_ARCANE + SCHOOL_MASK_SHADOW] = "B980FF",                                                          -- Spellshadow
	[SCHOOL_MASK_FIRE + SCHOOL_MASK_FROST + SCHOOL_MASK_NATURE] = "0070DE",                                        -- Elemental
	[SCHOOL_MASK_FIRE + SCHOOL_MASK_FROST + SCHOOL_MASK_ARCANE + SCHOOL_MASK_NATURE + SCHOOL_MASK_SHADOW] = "C0C0C0", -- Chromatic
	[SCHOOL_MASK_FIRE + SCHOOL_MASK_FROST + SCHOOL_MASK_ARCANE + SCHOOL_MASK_NATURE + SCHOOL_MASK_SHADOW + SCHOOL_MASK_HOLY] =
	"1111FF",                                                                                                      -- Magic
	[SCHOOL_MASK_PHYSICAL + SCHOOL_MASK_FIRE + SCHOOL_MASK_FROST + SCHOOL_MASK_ARCANE + SCHOOL_MASK_NATURE + SCHOOL_MASK_SHADOW + SCHOOL_MASK_HOLY] =
	"FF1111",                                                                                                      -- Chaos
	["melee"] = "FFFFFF",
	["pet"] = "CC8400"
}

local MISS_EVENT_STRINGS = {
	["ABSORB"] = L["Absorbed"],
	["BLOCK"] = L["Blocked"],
	["DEFLECT"] = L["Deflected"],
	["DODGE"] = L["Dodged"],
	["EVADE"] = L["Evaded"],
	["IMMUNE"] = L["Immune"],
	["MISS"] = L["Missed"],
	["PARRY"] = L["Parried"],
	["REFLECT"] = L["Reflected"],
	["RESIST"] = L["Resisted"],
}


-- UnitIsDead is "AllowedWhenUntainted" on restricted clients and this is called from the
-- animation OnUpdate: a raise here would error every frame and stop all drawing, so an
-- unanswerable query is treated as "alive" and the number keeps animating.
local function safeUnitIsDead(unit)
	if not unit then return false end
	local ok, dead = pcall(UnitIsDead, unit)
	if not ok or isSecretValue(dead) then
		return false
	end
	return dead == true
end

local STRATAS = {
	"BACKGROUND",
	"LOW",
	"MEDIUM",
	"HIGH",
	"DIALOG",
	"TOOLTIP"
}

-- Exported for Options/Widgets.lua and Options/Settings.lua (loaded after this file).
NameplateSCT.animationValues = animationValues
NameplateSCT.strataNames = STRATAS

----------------
-- FONTSTRING --
----------------
local fontPathCache = {}

---@param fontName string?
---@return string
local function getFontPath(fontName)
	-- nil is a legal setting value, so it must never become a table key
	local key = fontName or ""
	local cached = fontPathCache[key]
	if cached then return cached end

	local fontPath = SharedMedia:Fetch("font", key)
	if (fontPath == nil) then
		-- The client's own default font, which is also correct on CJK and Cyrillic locales
		-- where FRIZQT has no glyphs. "Friz Quadrata TT" resolves through SharedMedia first.
		fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	end

	fontPathCache[key] = fontPath
	return fontPath
end

-- A changed font must resolve again (the empty key covers a nil setting).
function NameplateSCT:ResetFontPathCache()
	fontPathCache = {}
end

---@param hex string
---@return number, number, number
local function hexToRGB(hex)
	-- Defensive: a profile edited by hand can hold a number where a colour used to be.
	if type(hex) ~= "string" or #hex < 6 then return 0, 0, 0 end
	return (tonumber(hex:sub(1, 2), 16) or 0) / 255,
		(tonumber(hex:sub(3, 4), 16) or 0) / 255,
		(tonumber(hex:sub(5, 6), 16) or 0) / 255
end

-- Colour travels beside the text as plain numbers and is applied with FontString:SetTextColor.
-- Inline |Cff codes cannot work on the restricted clients: the amount is a secret value that
-- may not be concatenated or formatted, so wrapping it would either raise or hand the client a
-- white number. Keeping the text plain also lets one string change colour between draws.
-- Every hit category switch is named here, literally, so a category cannot be added to the
-- client mapping without also being readable and auditable in one place.
---@param key string
---@return boolean
function NameplateSCT:IsHitCategoryEnabled(key)
	local profile = self.db.profile
	if key == "showMeleeDamage" then return profile.showMeleeDamage ~= false end
	if key == "showSpellDamage" then return profile.showSpellDamage ~= false end
	if key == "showRangedDamage" then return profile.showRangedDamage ~= false end
	if key == "showPeriodicDamage" then return profile.showPeriodicDamage ~= false end
	if key == "showPetDamage" then return profile.showPetDamage ~= false end
	if key == "showHealing" then return profile.showHealing ~= false end
	return true
end

---@param isPersonal boolean
---@param school number|string|nil
---@param spellName string|nil
---@param crit boolean|nil
---@return number, number, number
function NameplateSCT:GetTextColor(isPersonal, school, spellName, crit)
	local profile = self.db.profile
	if crit and profile.useCritColor then
		return hexToRGB(profile.critColor)
	end
	if isPersonal then
		if profile.damageColorPersonal and school and DAMAGE_TYPE_COLORS[school] then
			return hexToRGB(DAMAGE_TYPE_COLORS[school])
		end
		if profile.damageColorPersonal and spellName == "melee" and DAMAGE_TYPE_COLORS.melee then
			return hexToRGB(DAMAGE_TYPE_COLORS.melee)
		end
		return hexToRGB(profile.defaultColorPersonal)
	end
	if profile.damageColor and school and DAMAGE_TYPE_COLORS[school] then
		return hexToRGB(DAMAGE_TYPE_COLORS[school])
	end
	if profile.damageColor and spellName == "melee" and DAMAGE_TYPE_COLORS.melee then
		return hexToRGB(DAMAGE_TYPE_COLORS.melee)
	end
	return hexToRGB(profile.defaultColor)
end

---@param crit boolean|nil
---@return number, number, number
function NameplateSCT:GetHealColor(crit)
	local profile = self.db.profile
	if crit and profile.useHealCritColor then
		return hexToRGB(profile.healCritColor)
	end
	return hexToRGB(profile.healColor)
end

-- The shadow is a second FontString under the number. It carries the same string - a secret
-- amount is passed to both sinks by identity and never formatted - and takes its own size,
-- distance, angle, colour and opacity. Exactly one shadow is ever drawn: while the custom
-- one is on, the client's own offset copy is switched off.
---@param fontString FontString
---@param size number?
local function applyShadow(fontString, size)
	local shadow = fontString.shadow
	if not shadow then return end

	local profile = NameplateSCT.db.profile
	if not profile.textShadow then
		fontString:SetShadowOffset(0, 0)
		shadow:SetAlpha(0)
		return
	end

	fontString:SetShadowOffset(0, 0)

	local textSize = (size or fontString.NSCTFontSize or 15) * (profile.shadow.size or 1)
	local distance = profile.shadow.distance or 0
	local angle = math.rad(profile.shadow.angle or 315)

	shadow:SetFont(getFontPath(profile.font), textSize, profile.fontFlag)
	shadow:SetText(fontString.NSCTText or "")
	local red, green, blue = hexToRGB(profile.shadow.color or "000000")
	shadow:SetTextColor(red, green, blue)
	shadow:SetAlpha((fontString:GetAlpha() or 1) * (profile.shadow.alpha or 1))
	shadow:ClearAllPoints()
	shadow:SetPoint("CENTER", fontString, "CENTER",
		distance * math.cos(angle), distance * math.sin(angle))
	shadow:Show()
end

-- Exported for the settings window, which renders its own preview with the same rules.
NameplateSCT.GetFontPath = getFontPath
NameplateSCT.hexToRGB = hexToRGB
NameplateSCT.applyShadow = applyShadow

local fontStringCache = {}
local frameCounter = 0
local function getFontString()
	local fontString
	local fontStringFrame
	if (next(fontStringCache)) then
		fontString = table.remove(fontStringCache)
	else
		frameCounter = frameCounter + 1
		fontStringFrame = CreateFrame("Frame", nil, UIParent)
		fontStringFrame:SetFrameStrata(NameplateSCT:GetStrata(NameplateSCT.db.profile.strata.target))
		fontStringFrame:SetFrameLevel(frameCounter)
		fontString = fontStringFrame:CreateFontString()
		fontString:SetParent(fontStringFrame)
	end

	fontString:SetFont(getFontPath(NameplateSCT.db.profile.font), 15, NameplateSCT.db.profile.fontFlag)
	fontString:SetAlpha(1)
	fontString:SetDrawLayer("OVERLAY")
	fontString:SetText("")

	-- One shadow region per number, one layer under the text.
	if not fontString.shadow then
		fontString.shadow = fontString:GetParent():CreateFontString(nil, "ARTWORK")
	end
	applyShadow(fontString)

	fontString:Show()

	if NameplateSCT.db.profile.showIcon then
		local frame = fontString:GetParent()
		if not fontString.icon then
			fontString.icon = frame:CreateTexture(nil, "OVERLAY")
		end
		fontString.icon:SetAlpha(1)
		fontString.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		if NameplateSCT.db.profile.removeBorder then fontString.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		fontString.icon:Hide()

		if MSQ and NameplateSCT.db.profile.enableMSQ then
			if not fontString.icon.button then
				local button = CreateFrame("Button", nil, fontStringFrame)
				button:EnableMouse(false)
				button:Disable()
				button:Hide()
				fontString.icon.button = button
			end
			local buttonData = {
				Icon = fontString.icon
			}
			NameplateSCT.frame.MSQGroup:AddButton(fontString.icon.button, buttonData)
		end
		if fontString.icon.button then
			fontString.icon.button:Show()
		end
	end
	return fontString
end

local function recycleFontString(fontString)
	fontString:SetAlpha(0)
	fontString:Hide()

	animating[fontString] = nil
	randomX[fontString] = nil
	randomY[fontString] = nil

	fontString.distance = nil
	fontString.arcTop = nil
	fontString.arcBottom = nil
	fontString.arcXDist = nil
	fontString.deflection = nil
	fontString.numShakes = nil
	fontString.animation = nil
	fontString.animatingDuration = nil
	fontString.animatingStartTime = nil
	fontString.anchorFrame = nil

	fontString.unit = nil
	fontString.guid = nil
	fontString.NSCTText = nil

	fontString.pow = nil
	fontString.startHeight = nil
	fontString.NSCTFontSize = nil
	fontString.strata = nil
	fontString.screenMode = nil
	fontString.targetCheckedAt = nil
	fontString.targetValue = nil
	fontString.deadCheckedAt = nil
	fontString.deadValue = nil

	if fontString.icon then
		fontString.icon:ClearAllPoints()
		fontString.icon:SetAlpha(0)
		fontString.icon:Hide()
		if fontString.icon.button then
			NameplateSCT.frame.MSQGroup:RemoveButton(fontString.icon.button)
			fontString.icon.button:Hide()
			fontString.icon.button:ClearAllPoints()
		end

		fontString.icon.anchorFrame = nil
		fontString.icon.unit = nil
		fontString.icon.guid = nil
	end

	fontString:SetFont(getFontPath(NameplateSCT.db.profile.font), 15, NameplateSCT.db.profile.fontFlag)
	fontString:SetShadowOffset(0, 0)
	if fontString.shadow then
		fontString.shadow:SetAlpha(0)
		fontString.shadow:Hide()
	end
	fontString:ClearAllPoints()

	table.insert(fontStringCache, fontString)
end

-- Diagnostics read this to show pool pressure without reaching into the locals above.
---@return number pooled, number active
function NameplateSCT:GetPoolStats()
	local active = 0
	for _ in pairs(animating) do active = active + 1 end
	return #fontStringCache, active
end

--------------------------------------------------------------------------------
-- DISPLAY MODE: nameplates vs a fixed screen area
--------------------------------------------------------------------------------
-- Screen mode anchors every number to one of two invisible frames instead of a plate,
-- which is the behaviour PlateSCT exposes as its "screen" layout. The frames are 1x1
-- children of UIParent so the existing animation code needs no special case beyond
-- skipping the per-target offsets.

function NameplateSCT:GetScreenAnchor(incoming)
	local global = self.db.profile
	local key = incoming and "incoming" or "outgoing"
	self.screenAnchors = self.screenAnchors or {}

	local anchor = self.screenAnchors[key]
	if not anchor then
		anchor = CreateFrame("Frame", nil, UIParent)
		anchor:SetSize(1, 1)
		self.screenAnchors[key] = anchor
	end

	local area = global.screen or {}
	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", UIParent, "CENTER", area[key .. "X"] or 0, area[key .. "Y"] or 0)
	return anchor
end

function NameplateSCT:RefreshScreenAnchors()
	if not self.screenAnchors then return end
	for key, anchor in pairs(self.screenAnchors) do
		local area = self.db.profile.screen or {}
		anchor:ClearAllPoints()
		anchor:SetPoint("CENTER", UIParent, "CENTER", area[key .. "X"] or 0, area[key .. "Y"] or 0)
	end
end

function NameplateSCT:IsScreenMode()
	return self.db and self.db.profile and self.db.profile.displayMode == "screen"
end

---@param name string
---@return string|nil
local function readBlizzardCvar(name)
	local modern = _G.C_CVar and _G.C_CVar.GetCVar
	if type(modern) == "function" then
		local ok, value = pcall(modern, name)
		if ok and value ~= nil then return value end
	end
	if type(_G.GetCVar) == "function" then
		local ok, value = pcall(_G.GetCVar, name)
		if ok then return value end
	end
	return nil
end

---@param writer function|nil
---@param name string
---@param text string
---@return boolean
local function tryWriteCvar(writer, name, text)
	if type(writer) ~= "function" then return false end
	local ok = pcall(writer, name, text)
	return ok and readBlizzardCvar(name) == text
end

-- The CVar API takes a cstring value and rejects read-only or secure CVars *without raising*
-- (CVarDocumentation: value is cstring, RequiresValidAndPublicCVar / RequiresNonReadOnlyCVar /
-- RequiresNonSecureCVar). Write the string form, then read it back to prove it landed.
---@param name string
---@param value string
---@return boolean written
local function writeBlizzardCvar(name, value)
	-- A CVar this client does not expose is not a failure, it is simply not part of that
	-- client's model. GetCVar answers nil for unknown names on every supported family.
	if readBlizzardCvar(name) == nil then return true end
	local text = tostring(value)
	local modern = _G.C_CVar and _G.C_CVar.SetCVar
	if tryWriteCvar(modern, name, text) then return true end
	if tryWriteCvar(_G.SetCVar, name, text) then return true end
	return false
end

---@return table|nil frame the client's combat-text renderer, if it is loaded
local function getCombatTextFrame()
	local frame = _G.CombatText
	if type(frame) == "table" and type(frame.IsEventRegistered) == "function" then
		return frame
	end
	return nil
end

--- Whether the client's renderer is currently receiving combat-text events.
--- This - not our own CVar write - is what decides whether numbers appear.
---@return boolean|nil registered nil when the renderer is not loaded
local function isCombatTextRegistered()
	local frame = getCombatTextFrame()
	if not frame then return nil end
	local ok, registered = pcall(frame.IsEventRegistered, frame, "COMBAT_TEXT_UPDATE")
	if not ok then return nil end
	return registered and true or false
end

--- Drive the client's own registration path, so the change lands now instead of next reload.
--- Blizzard does exactly this through CombatTextUtil.UpdateEventRegistration.
---@param enable boolean
---@return boolean applied
local function setCombatTextRegistered(enable)
	local frame = getCombatTextFrame()
	if not frame then return false end
	local util = _G.CombatTextUtil
	if util and type(util.UpdateEventRegistration) == "function" then
		local ok = pcall(util.UpdateEventRegistration, frame, enable)
		if ok then return true end
	end
	if not enable and type(frame.UnregisterAllEvents) == "function" then
		local ok = pcall(frame.UnregisterAllEvents, frame)
		if ok then return true end
	end
	return false
end

--- The value a switch should be handed back to when the addon has no record of it.
--- `GetCVarDefault` is the client's own default answer, so a lost record can never
--- leave Blizzard's text muted for good.
---@param name string
---@return string
local function blizzardCvarFallback(name)
	local modern = _G.C_CVar and _G.C_CVar.GetCVarDefault
	if type(modern) == "function" then
		local ok, value = pcall(modern, name)
		if ok and type(value) == "string" then return value end
	end
	local getter = _G.GetCVarDefault
	if type(getter) == "function" then
		local ok, value = pcall(getter, name)
		if ok and type(value) == "string" then return value end
	end
	return "1"
end

-- What the switches held before the addon muted them. Memory-only on purpose: the record is
-- per session, and `rememberBlizzardCvar` refuses to record "0", so a record lost to a reload
-- still hands the text back instead of leaving the client muted for good.
local savedBlizzardCvars

---@param saved table<string, string>
---@param name string
local function rememberBlizzardCvar(saved, name)
	if saved[name] ~= nil then return end
	local previous = readBlizzardCvar(name)
	if previous == nil then return end
	if previous ~= "0" then
		saved[name] = previous
	else
		saved[name] = blizzardCvarFallback(name)
	end
end

-- Set while ApplyBlizzardFCT is writing, so the CVAR_UPDATE it triggers cannot re-enter it.
local applyingBlizzardFCT = false

function NameplateSCT:ApplyBlizzardFCT()
	if applyingBlizzardFCT then return end
	if not self.db then return end
	local profile = self.db.profile
	if not profile then return end
	applyingBlizzardFCT = true

	-- The addon being switched off must give Blizzard's text back: muting the client while
	-- drawing nothing of our own would leave the player with no numbers at all.
	local suppress = profile.hideBlizzardFCT == true and profile.enabled == true

	if not suppress then
		if savedBlizzardCvars then
			for name, value in pairs(savedBlizzardCvars) do
				writeBlizzardCvar(name, value)
			end
			savedBlizzardCvars = nil
		end
		-- Put the client's renderer back the way the restored value says it should be. A value
		-- the client cannot read means "not muted by us", so hand the text back.
		local master = readBlizzardCvar(BLIZZARD_FCT_MASTER_CVAR)
		setCombatTextRegistered(master ~= "0")
		if type(_G.CombatText_UpdateDisplayedMessages) == "function" then
			pcall(_G.CombatText_UpdateDisplayedMessages)
		end
		-- Nothing is being suppressed, so nothing can be failing.
		if self.diagnostics then self.diagnostics.fctFailed = 0 end
		applyingBlizzardFCT = false
		return
	end

	-- Honoured in screen mode too: the setting is the player's explicit choice, and silently
	-- skipping it because of the display mode is how "I turned it on and nothing happened"
	-- happens.
	savedBlizzardCvars = savedBlizzardCvars or {}
	local saved = savedBlizzardCvars
	local failed = 0

	-- The master switch stops Blizzard_CombatText (self SCT).
	rememberBlizzardCvar(saved, BLIZZARD_FCT_MASTER_CVAR)
	if not writeBlizzardCvar(BLIZZARD_FCT_MASTER_CVAR, "0") then failed = failed + 1 end

	-- Then every per-category floatingCombatText CVar that drives in-world target/pet/heal text.
	for _, name in ipairs(blizzardTextCvars) do
		rememberBlizzardCvar(saved, name)
		if not writeBlizzardCvar(name, "0") then failed = failed + 1 end
	end

	-- The CVar is what survives a reload; the registration is what stops the numbers now.
	setCombatTextRegistered(false)
	if type(_G.CombatText_UpdateDisplayedMessages) == "function" then
		pcall(_G.CombatText_UpdateDisplayedMessages)
	end

	-- Reported by the dashboard: a client that refuses the write must not look like a bug in
	-- the toggle.
	local diagnostics = self.diagnostics
	if diagnostics then diagnostics.fctFailed = failed end
	applyingBlizzardFCT = false
end

-- Defer one frame so startup/loading-screen CVar syncs and other addons finish first.
---@param addon NameplateSCT
local function scheduleBlizzardFCT(addon)
	local timer = _G.C_Timer
	if type(timer) == "table" and type(timer.After) == "function" then
		pcall(timer.After, 0, function()
			if addon.db and addon.db.profile then addon:ApplyBlizzardFCT() end
		end)
	end
end

-- Keep the setting authoritative: the game's own options (or another addon) can turn Blizzard's
-- text back on while the toggle is on, and the player would see numbers return and think this
-- setting broke again. Watch every steered CVar, not only the master switch.
function NameplateSCT:CVAR_UPDATE(_, cvar)
	if type(cvar) ~= "string" then return end
	local canonical = blizzardFCTSet[string.lower(cvar)]
	if not canonical then return end
	if applyingBlizzardFCT then return end
	if not self.db or not self.db.profile then return end
	if not self.db.profile.hideBlizzardFCT or not self.db.profile.enabled then return end
	-- This event is also the echo of our own write, which can arrive after the write returned.
	-- Nothing to do when that CVar already reads off and (for the master) the renderer stopped.
	local value = readBlizzardCvar(canonical)
	local masterOpen = (canonical == BLIZZARD_FCT_MASTER_CVAR and isCombatTextRegistered() == true)
	if value == "0" and not masterOpen then return end
	self:ApplyBlizzardFCT()
end

-- The client can reset these while logging in or on a loading screen, so the setting is
-- re-applied once the world is there and again after the settings bootstrap finishes.
function NameplateSCT:PLAYER_ENTERING_WORLD()
	if self.db and self.db.profile then
		self:ApplyBlizzardFCT()
		scheduleBlizzardFCT(self)
	end
end

function NameplateSCT:SETTINGS_LOADED()
	if self.db and self.db.profile then
		self:ApplyBlizzardFCT()
	end
end

function NameplateSCT:ADDON_LOADED(_, addonName)
	if addonName == "Blizzard_CombatText" and self.db and self.db.profile then
		self:ApplyBlizzardFCT()
	end
end

--- How many combat-text CVars this client has, and how many still read "on".
---@return number steered, number stillOn
function NameplateSCT:GetBlizzardFCTState()
	local steered, stillOn = 0, 0
	local master = readBlizzardCvar(BLIZZARD_FCT_MASTER_CVAR)
	if master ~= nil then
		steered = steered + 1
		if master ~= "0" then stillOn = stillOn + 1 end
	end
	for _, name in ipairs(blizzardTextCvars) do
		local value = readBlizzardCvar(name)
		if value ~= nil then
			steered = steered + 1
			if value ~= "0" then stillOn = stillOn + 1 end
		end
	end
	return steered, stillOn
end

--- Whether the client can still draw its own numbers, read from the client rather than from
--- our own write. A dashboard that trusts the write is how 1.64 reported green while Blizzard
--- kept drawing: the CVar read "0" and nothing consulted it.
---@return boolean stopped, string reason
function NameplateSCT:GetBlizzardFCTStatus()
	local registered = isCombatTextRegistered()
	if registered == true then
		return false, "the client is still drawing its own text"
	end
	local master = readBlizzardCvar(BLIZZARD_FCT_MASTER_CVAR)
	if master ~= nil and master ~= "0" then
		return false, BLIZZARD_FCT_MASTER_CVAR .. " still reads " .. tostring(master)
	end
	local steered, stillOn = self:GetBlizzardFCTState()
	if stillOn > 0 then
		return false, stillOn .. " of " .. steered .. " text switches are still on"
	end
	if registered == nil and master == nil and steered == 0 then
		return true, "this client has no combat-text switch"
	end
	return true, "Blizzard's combat text is off"
end

-- Addons that draw their own numbers in the same place. If one of these is loaded, "I turned
-- Blizzard's numbers off and they still show" has a name, instead of another round of guesswork.
local RIVAL_FCT_ADDONS = { "PlateSCT", "ClassicFCT" }

--- Which other number-drawing addons are loaded right now.
---@return string[] names
function NameplateSCT:GetNumberRivals()
	local rivals = {}
	local isLoaded
	local addons = _G.C_AddOns
	if type(addons) == "table" and type(addons.IsAddOnLoaded) == "function" then
		isLoaded = addons.IsAddOnLoaded
	elseif type(_G.IsAddOnLoaded) == "function" then
		isLoaded = _G.IsAddOnLoaded
	end
	if not isLoaded then return rivals end
	for _, name in ipairs(RIVAL_FCT_ADDONS) do
		local ok, loadedOrLoading = pcall(isLoaded, name)
		if ok and loadedOrLoading then rivals[#rivals + 1] = name end
	end
	return rivals
end

----------------
-- NAMEPLATES --
----------------

---@param strataNumber any
---@return string
function NameplateSCT:GetStrata(strataNumber)
	if type(strataNumber) == "number" and STRATAS[strataNumber] then
		return STRATAS[strataNumber]
	end
	return "MEDIUM"
end

----------
-- CORE --
----------

-- AceDB used to keep every setting in the shared `global` namespace, which made profiles
-- (and therefore AceDBOptions) meaningless. Settings now live in `profile`. Copy the old
-- values across exactly once, on the raw saved variable, and keep the legacy table as a
-- recovery copy rather than deleting the player's settings.
local function copyValue(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = copyValue(item) end
	return copy
end

-- Copy a legacy value into the live profile. A nested table is merged key by key: assigning
-- it whole would replace the default subtree, so every key the old saved data did not
-- mention (added by a later version) would be nil afterwards - the settings window then
-- shows blanks and the render path reads nil.
local function mergeInto(target, key, value)
	local existing = target[key]
	if type(value) == "table" and type(existing) == "table" then
		for nestedKey, nestedValue in pairs(value) do
			mergeInto(existing, nestedKey, nestedValue)
		end
	else
		target[key] = copyValue(value)
	end
end

local function migrateSettingsToProfile(db, savedVariableName)
	local saved = rawget(_G, savedVariableName)
	if type(saved) ~= "table" or saved.settingsNamespace == "profile" then
		return false
	end

	local legacy = saved.global
	if type(legacy) == "table" then
		for key, value in pairs(legacy) do
			mergeInto(db.profile, key, value)
		end
	end

	-- Runs once per account: written onto the saved variable, so it survives the profile
	-- being switched, copied or reset later.
	saved.settingsNamespace = "profile"
	return type(legacy) == "table"
end

NameplateSCT.migrateSettingsToProfile = migrateSettingsToProfile

-- Defaults that changed after a build shipped. A profile saved by an older version keeps the
-- old default in its saved variables, so a new default alone would never reach an existing
-- player. Each change is recorded on the saved variable, so it runs once per account and never
-- overrides a player who turns the setting back on afterwards.
---@param db table
---@param savedVariableName string
---@return boolean changed
local function applyDefaultChanges(db, savedVariableName)
	local saved = rawget(_G, savedVariableName)
	if type(saved) ~= "table" then return false end
	local changed = false

	-- Spell icons used to default to on; they are off by default now.
	if saved.iconDefaultOff ~= true then
		if db.profile.showIcon == true then
			db.profile.showIcon = false
			changed = true
		end
		saved.iconDefaultOff = true
	end

	return changed
end

NameplateSCT.applyDefaultChanges = applyDefaultChanges

function NameplateSCT:ConvertDB()
	if type(NameplateSCT.db.profile.strata.offTarget) == "string" then
		for k, v in ipairs(STRATAS) do
			if (v == NameplateSCT.db.profile.strata.offTarget) then
				NameplateSCT.db.profile.strata.offTarget = k
			end
		end
	end
	if type(NameplateSCT.db.profile.strata.target) == "string" then
		for k, v in ipairs(STRATAS) do
			if (v == NameplateSCT.db.profile.strata.target) then
				NameplateSCT.db.profile.strata.target = k
			end
		end
	end
end

function NameplateSCT:OnInitialize()
	-- setup db
	self.db = LibStub("AceDB-3.0"):New("NameplateSCTDB", defaults, true)
	self.migratedSettings = migrateSettingsToProfile(self.db, "NameplateSCTDB")
	self.defaultsUpdated = applyDefaultChanges(self.db, "NameplateSCTDB")

	-- Adjust anything that was edited in the db to be correct
	self:ConvertDB()

	-- setup chat commands
	self:RegisterChatCommand("nsct", "OpenMenu")

	-- setup menu
	self:RegisterMenu()

	-- Update Filters
	self:updateFilterTable(self.db.profile.filter)
	self:updateNPCFilterTable(self.db.profile.npcFilter)

	-- if the addon is turned off in db, turn it off
	if (self.db.profile.enabled == false) then
		self:Disable()
	end
end

-- AceEvent provides RegisterEvent and RegisterMessage but no unit-filtered variant, so
-- that registration needs a plain frame. The previous attempt went through the addon
-- object inside a pcall, failed silently, and never registered anything.
function NameplateSCT:RegisterCastAttribution()
	if not self.castFrame then
		self.castFrame = CreateFrame("Frame")
		self.castFrame:SetScript("OnEvent", function(_, event, ...)
			if event == "UNIT_SPELLCAST_SENT" then
				NameplateSCT:UNIT_SPELLCAST_SENT(event, ...)
			elseif event == "UNIT_SPELLCAST_START" then
				NameplateSCT:UNIT_SPELLCAST_START(event, ...)
			elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
				NameplateSCT:UNIT_SPELLCAST_CHANNEL_START(event, ...)
			elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
				NameplateSCT:UNIT_SPELLCAST_CHANNEL_STOP(event, ...)
			else
				NameplateSCT:UNIT_SPELLCAST_SUCCEEDED(event, ...)
			end
		end)
	end

	local castFrame = self.castFrame
	local unitEvents = {
		"UNIT_SPELLCAST_SENT",
		"UNIT_SPELLCAST_START",
		"UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_STOP",
		"UNIT_SPELLCAST_SUCCEEDED",
	}
	for _, ev in ipairs(unitEvents) do
		local ok = pcall(castFrame.RegisterUnitEvent, castFrame, ev, "player", "pet")
		if not ok then
			pcall(castFrame.RegisterEvent, castFrame, ev)
		end
	end
end

function NameplateSCT:OnEnable()
	playerGUID = UnitGUID("player")

	self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

	if hasCombatRestrictions then
		-- Restricted client (Forever / Midnight): UNIT_COMBAT is the only permitted
		-- damage source. Spell attribution comes from the player's own casts.
		self:RegisterEvent("UNIT_COMBAT")
		self:RegisterCastAttribution()
	else
		pcall(self.RegisterEvent, self, "COMBAT_LOG_EVENT_UNFILTERED")
	end

	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	pcall(self.RegisterEvent, self, "SETTINGS_LOADED")
	self:RegisterEvent("ADDON_LOADED")
	-- Re-assert the Blizzard-text setting when the game's own options or another addon try to turn it back on.
	self:RegisterEvent("CVAR_UPDATE")

	self.db.profile.enabled = true

	-- The dashboard reports whether the event source is actually subscribed, which is the
	-- difference between "no damage yet" and "nothing is listening".
	local diagnostics = self.diagnostics
	if diagnostics then
		diagnostics.registered = true
		diagnostics.startedAt = GetTime()
		diagnostics.event = hasCombatRestrictions and "UNIT_COMBAT" or "COMBAT_LOG_EVENT_UNFILTERED"
	end

	self:ApplyBlizzardFCT()
	scheduleBlizzardFCT(self)
end

function NameplateSCT:OnDisable()
	self:UnregisterAllEvents()
	if self.diagnostics then self.diagnostics.registered = false end

	if self.castFrame then
		self.castFrame:UnregisterAllEvents()
	end
	if self.ClearHealAttribution then
		self:ClearHealAttribution()
	end

	for fontString, _ in pairs(animating) do
		recycleFontString(fontString)
	end

	self.db.profile.enabled = false

	-- Hand Blizzard's own text back: with the addon off, a muted client would leave the player
	-- with no numbers at all.
	self:ApplyBlizzardFCT()
end

---------------
-- ANIMATION --
---------------
local function verticalPath(elapsed, duration, distance)
	return 0, LibEasing.InQuad(elapsed, 0, distance, duration)
end

local function arcPath(elapsed, duration, xDist, yStart, yTop, yBottom)
	local x, y
	local progress = elapsed / duration

	x = progress * xDist

	-- progress 0 to 1
	-- at progress 0, y = yStart
	-- at progress 0.5 y = yTop
	-- at progress 1 y = yBottom

	-- -0.25a + .5b + yStart = yTop
	-- -a + b + yStart = yBottom

	-- -0.25a + .5b + yStart = yTop
	-- .5b + yStart - yTop = 0.25a
	-- 2b + 4yStart - 4yTop = a

	-- -(2b + 4yStart - 4yTop) + b + yStart = yBottom
	-- -2b - 4yStart + 4yTop + b + yStart = yBottom
	-- -b - 3yStart + 4yTop = yBottom

	-- -3yStart + 4yTop - yBottom = b

	-- 2(-3yStart + 4yTop - yBottom) + 4yStart - 4yTop = a
	-- -6yStart + 8yTop - 2yBottom + 4yStart - 4yTop = a
	-- -2yStart + 4yTop - 2yBottom = a

	-- -3yStart + 4yTop - yBottom = b
	-- -2yStart + 4yTop - 2yBottom = a

	local a = -2 * yStart + 4 * yTop - 2 * yBottom
	local b = -3 * yStart + 4 * yTop - yBottom

	y = -a * math.pow(progress, 2) + b * progress + yStart

	return x, y
end

local function powSizing(elapsed, duration, start, middle, finish)
	local size = finish
	if (elapsed < duration) then
		if (elapsed / duration < 0.5) then
			size = LibEasing.OutQuint(elapsed, start, middle - start, duration / 2)
		else
			size = LibEasing.InQuint(elapsed - elapsed / 2, middle, finish - middle, duration / 2)
		end
	end
	return size
end

-- CSS linear() points
local linearPoints = {
	{ 0,     0 },
	{ 0.036, 0.21 },
	{ 0.074, 0.402 },
	{ 0.113, 0.568 },
	{ 0.153, 0.711 },
	{ 0.173, 0.772 },
	{ 0.194, 0.83 },
	{ 0.215, 0.882 },
	{ 0.237, 0.929 },
	{ 0.259, 0.97 },
	{ 0.282, 1.008 },
	{ 0.306, 1.04 },
	{ 0.33,  1.067 },
	{ 0.349, 1.084 },
	{ 0.369, 1.099 },
	{ 0.389, 1.111 },
	{ 0.41,  1.12 },
	{ 0.432, 1.127 },
	{ 0.454, 1.13 },
	{ 0.477, 1.132 },
	{ 0.501, 1.13 },
	{ 0.54,  1.124 },
	{ 0.585, 1.111 },
	{ 0.629, 1.095 },
	{ 0.755, 1.044 },
	{ 0.795, 1.03 },
	{ 0.832, 1.019 },
	{ 0.873, 1.01 },
	{ 0.913, 1.004 },
	{ 0.954, 1.001 },
	{ 1,     1 }
}

local function GetLinearEasing(p)
	if p <= 0 then return linearPoints[1][2] end
	if p >= 1 then return linearPoints[#linearPoints][2] end

	for i = 1, #linearPoints - 1 do
		local p1 = linearPoints[i]
		local p2 = linearPoints[i + 1]
		if p >= p1[1] and p < p2[1] then
			local percent = (p - p1[1]) / (p2[1] - p1[1])
			return p1[2] + (p2[2] - p1[2]) * percent
		end
	end
	return linearPoints[#linearPoints][2]
end

-- Caching rule for restricted clients: only the *plain answer* is ever cached. A secret
-- or refused value is converted to a safe boolean by safeUnitIsUnit / safeUnitIsDead and
-- that boolean is what gets stored, so no secret is held, compared, concatenated or
-- formatted later. The short TTL means a cached answer cannot outlive a restriction change.
local TARGET_CACHE_SECONDS = 0.2
local DEAD_CACHE_SECONDS = 0.25

local function fontStringTargetState(fontString, now)
	if fontString.targetCheckedAt and (now - fontString.targetCheckedAt) < TARGET_CACHE_SECONDS then
		return fontString.targetValue
	end
	-- safeUnitIsUnit yields a plain boolean: a secret answer never reaches this cache.
	local isTarget = safeUnitIsUnit(fontString.unit, "target")
	fontString.targetCheckedAt = now
	fontString.targetValue = isTarget
	return isTarget
end

local function fontStringDeadState(fontString, now)
	if fontString.deadCheckedAt and (now - fontString.deadCheckedAt) < DEAD_CACHE_SECONDS then
		return fontString.deadValue
	end
	-- same contract: the refused/secrets case collapses to false before it is stored
	local isDead = safeUnitIsDead(fontString.unit)
	fontString.deadCheckedAt = now
	fontString.deadValue = isDead
	return isDead
end

local function AnimationOnUpdate()
	if (next(animating)) then
		for fontString, _ in pairs(animating) do
			local now = GetTime()
			local duration = fontString.animatingDuration
			local elapsed = now - fontString.animatingStartTime
			if (not duration) or duration <= 0 or elapsed > duration then
				-- the animation is over (a zero duration would divide by zero below)
				recycleFontString(fontString)
			else
				if not fontString.unit then
					fontString.unit = "player"
				end

				-- Both queries are restricted on Forever and raise there, so they are cached:
				-- asking UnitIsUnit/UnitIsDead for every number on every frame was the hottest
				-- path in the addon.
				local isTarget = fontStringTargetState(fontString, now)

				-- frame level: only when it actually changes
				local frame = fontString:GetParent()
				local strataRequired
				if isTarget then
					strataRequired = NameplateSCT:GetStrata(NameplateSCT.db.profile.strata.target)
				else
					local offTargetStrata = NameplateSCT.db.profile.strata.offTarget
					if NameplateSCT.db.profile.modOffTargetStrata then
						-- Keep off-target text one layer under the target's, whatever the
						-- explicit off-target setting says.
						local targetStrata = tonumber(NameplateSCT.db.profile.strata.target) or 1
						offTargetStrata = math.max(1, targetStrata - 1)
					end
					strataRequired = NameplateSCT:GetStrata(offTargetStrata)
				end
				if fontString.strata ~= strataRequired then
					frame:SetFrameStrata(strataRequired)
					fontString.strata = strataRequired
				end

				-- alpha
				local startAlpha = NameplateSCT.db.profile.formatting.alpha
				if (NameplateSCT.db.profile.useOffTargetAppearance and not isTarget and fontString.unit ~= "player") then
					startAlpha = NameplateSCT.db.profile.offTargetFormatting.alpha
				end

				local alpha = LibEasing.InExpo(elapsed, startAlpha, -startAlpha, fontString.animatingDuration)
				if alpha > 1 then alpha = 1 elseif alpha < 0 then alpha = 0 end -- avoid rare occurences of eg: 1.0003 from the Lib being used to set Alpha
				fontString:SetAlpha(alpha)
				if fontString.shadow then
					-- The shadow fades with the text, never on its own.
					if NameplateSCT.db.profile.textShadow then
						fontString.shadow:SetAlpha(alpha * (NameplateSCT.db.profile.shadow.alpha or 1))
					else
						fontString.shadow:SetAlpha(0)
					end
				end

				-- sizing
				if (fontString.pow) then
					local iconScale = NameplateSCT.db.profile.iconScale
					local height = fontString.startHeight
					if (elapsed < fontString.animatingDuration / 6) then
						fontString:SetText(fontString.NSCTText)
						local size = powSizing(elapsed, fontString.animatingDuration / 6, height / 2, height * 2, height)
						fontString:SetTextHeight(size)
						if fontString.icon then
							if MSQ and NameplateSCT.db.profile.enableMSQ then
								fontString.icon.button:SetSize(size * iconScale, size * iconScale)
							else
								fontString.icon:SetSize(size * iconScale, size * iconScale)
							end
						end
					else
						fontString.pow = nil
						fontString:SetTextHeight(height)
						fontString:SetFont(getFontPath(NameplateSCT.db.profile.font), fontString.NSCTFontSize,
							NameplateSCT.db.profile.fontFlag)
						applyShadow(fontString)
						fontString:SetText(fontString.NSCTText)
						if fontString.icon then
							if MSQ and NameplateSCT.db.profile.enableMSQ then
								fontString.icon.button:SetSize(height * iconScale, height * iconScale)
							else
								fontString.icon:SetSize(height * iconScale, height * iconScale)
							end
						end
					end
				end

				-- position
				local xOffset, yOffset = 0, 0
				if (fontString.animation == "verticalUp") then
					xOffset, yOffset = verticalPath(elapsed, fontString.animatingDuration, fontString.distance)
				elseif (fontString.animation == "verticalDown") then
					xOffset, yOffset = verticalPath(elapsed, fontString.animatingDuration, -fontString.distance)
				elseif (fontString.animation == "fountain") then
					xOffset, yOffset = arcPath(elapsed, fontString.animatingDuration, fontString.arcXDist, 0,
						fontString.arcTop, fontString.arcBottom)
				elseif (fontString.animation == "rainfall") then
					_, yOffset = verticalPath(elapsed, fontString.animatingDuration, -fontString.distance)
					xOffset = fontString.rainfallX
					yOffset = yOffset + fontString.rainfallStartY
				elseif (fontString.animation == "fireworks") then
					-- Fireworks effect: radiates outward from the configured starting radius circle
					local angle = fontString.fireworksAngle or (math.random() * 2 * math.pi)
					local progress = elapsed / fontString.animatingDuration
					-- Use custom linear() easing function
					local easedProgress = GetLinearEasing(progress)
					local distance = (fontString.fireworksDistance or 100) * easedProgress

					-- Get the configured starting radius
					local startRadius = NameplateSCT.db.profile.animations.fireworksRadius
					xOffset = (startRadius + distance) * math.cos(angle)
					yOffset = (startRadius + distance) * math.sin(angle)
					-- elseif (fontString.animation == "shake") then
					-- TODO
				end

				if ((not fontStringDeadState(fontString, now) or fontString.unit == "player") and fontString.anchorFrame and fontString.anchorFrame:IsShown()) then
					if fontString.animation == "fireworks" then
						-- -- Fireworks effect ignores global offset and random jitter, always relative to center
						fontString:SetPoint("CENTER", fontString.anchorFrame, "CENTER", xOffset, yOffset)
					elseif fontString.screenMode then
						-- Screen mode: the anchor is already the configured area, so only the
						-- jitter applies.
						fontString:SetPoint("CENTER", fontString.anchorFrame, "CENTER", xOffset + randomX[fontString],
							yOffset + randomY[fontString])
					else
						if fontString.unit == "player" then -- player frame
							fontString:SetPoint("CENTER", fontString.anchorFrame, "CENTER",
								NameplateSCT.db.profile.xOffsetPersonal + xOffset + randomX[fontString],
								NameplateSCT.db.profile.yOffsetPersonal + yOffset + randomY[fontString]) -- Only allows for adjusting vertical offset
						else                                                     -- nameplate frames
							fontString:SetPoint("CENTER", fontString.anchorFrame, "CENTER",
								NameplateSCT.db.profile.xOffset + xOffset + randomX[fontString],
								NameplateSCT.db.profile.yOffset + yOffset + randomY[fontString])
						end
					end
				else
					recycleFontString(fontString)
				end
			end
		end
		if MSQ and NameplateSCT.db.profile.enableMSQ then
			NameplateSCT.frame.MSQGroup:ReSkin()
		end
	else
		-- nothing in the animation list, so just kill the onupdate
		NameplateSCT.frame:SetScript("OnUpdate", nil)
	end
end

local arcDirection = 1
function NameplateSCT:Animate(fontString, anchorFrame, duration, animation)
	animation = animation or "verticalUp"

	fontString.animation = animation
	fontString.animatingDuration = duration
	fontString.animatingStartTime = GetTime()
	fontString.anchorFrame = anchorFrame == "player" and UIParent or anchorFrame

	if (animation == "verticalUp") then
		fontString.distance = ANIMATION_VERTICAL_DISTANCE
	elseif (animation == "verticalDown") then
		fontString.distance = ANIMATION_VERTICAL_DISTANCE
	elseif (animation == "fountain") then
		fontString.arcTop = math.random(ANIMATION_ARC_Y_TOP_MIN, ANIMATION_ARC_Y_TOP_MAX)
		fontString.arcBottom = -math.random(ANIMATION_ARC_Y_BOTTOM_MIN, ANIMATION_ARC_Y_BOTTOM_MAX)
		fontString.arcXDist = arcDirection * math.random(ANIMATION_ARC_X_MIN, ANIMATION_ARC_X_MAX)

		arcDirection = arcDirection * -1
	elseif (animation == "rainfall") then
		fontString.distance = math.random(ANIMATION_RAINFALL_Y_MIN, ANIMATION_RAINFALL_Y_MAX)
		fontString.rainfallX = math.random(-ANIMATION_RAINFALL_X_MAX, ANIMATION_RAINFALL_X_MAX)
		fontString.rainfallStartY = -math.random(ANIMATION_RAINFALL_Y_START_MIN, ANIMATION_RAINFALL_Y_START_MAX)
	elseif (animation == "fireworks") then
		fontString.fireworksAngle = math.random() * 2 * math.pi
		fontString.fireworksDistance = math.random(80, 150)
		-- elseif (animation == "shake") then
		--	 fontString.deflection = ANIMATION_SHAKE_DEFLECTION
		--	 fontString.numShakes = ANIMATION_SHAKE_NUM_SHAKES
	end

	animating[fontString] = true
	randomX[fontString] = NameplateSCT.db.profile.xVariance > 0 and
		math.random(-NameplateSCT.db.profile.xVariance, NameplateSCT.db.profile.xVariance) or 0
	randomY[fontString] = NameplateSCT.db.profile.yVariance > 0 and
		math.random(-NameplateSCT.db.profile.yVariance, NameplateSCT.db.profile.yVariance) or 0

	-- start onupdate if it's not already running
	if (NameplateSCT.frame:GetScript("OnUpdate") == nil) then
		NameplateSCT.frame:SetScript("OnUpdate", AnimationOnUpdate)
	end
end

------------
-- EVENTS --
------------

function NameplateSCT:NAME_PLATE_UNIT_ADDED(event, unitID)
	if event ~= "NAME_PLATE_UNIT_ADDED" or not unitID then return end

	local guid = UnitGUID(unitID)
	if not guid or isSecretValue(guid) then return end

	unitToGuid[unitID] = guid
	if canaccessvalue(guid) then
		guidToUnit[guid] = unitID
	end
end

function NameplateSCT:NAME_PLATE_UNIT_REMOVED(event, unitID)
	if event ~= "NAME_PLATE_UNIT_REMOVED" or not unitID then return end

	local guid = unitToGuid[unitID]

	unitToGuid[unitID] = nil
	if guid and not isSecretValue(guid) then
		guidToUnit[guid] = nil
	end

	-- recycle any fontStrings attached to this unit
	for fontString, _ in pairs(animating) do
		if fontString.unit == unitID then
			recycleFontString(fontString)
		end
	end
end

-- Which switch governs a combat-log hit. The event name carries the kind, so the same table
-- serves both damage paths.
---@param clue string
---@return string
local function cleuCategory(clue)
	if string.find(clue, "SWING", 1, true) then return "showMeleeDamage" end
	if string.find(clue, "RANGE", 1, true) then return "showRangedDamage" end
	if string.find(clue, "PERIODIC", 1, true) then return "showPeriodicDamage" end
	return "showSpellDamage"
end

function NameplateSCT:CombatFilter(_, clue, _, sourceGUID, _, sourceFlags, _, destGUID, _, _, _, ...)
	local d = NameplateSCT.diagnostics
	if d then
		d.events = d.events + 1; d.lastEvent = GetTime()
	end
	if not clue or not destGUID or isSecretValue(clue) or isSecretValue(sourceGUID) or isSecretValue(destGUID) then
		return countDrop("secret values blocked")
	end
	playerGUID = playerGUID or UnitGUID("player")
	local isHeal = string.find(clue, "_HEAL", 1, true) ~= nil
	if NameplateSCT.db.profile.personalOnly and NameplateSCT.db.profile.personal and playerGUID ~= destGUID then
		return countDrop("personal only")                   -- Cancel out any non player targetted abilities if you have personalSCT only enabled
	end
	if NameplateSCT.db.profile.filterEnabled and destGUID then -- Filter out mobId's if needed
		local _, _, _, _, _, destUnitId = strsplit("-", destGUID)
		destUnitId = tostring(destUnitId) or "1"
		if (NameplateSCT.db.profile.inverseNPCFilter and not npcFiltersTable[destUnitId]) -- Inverse filter
			or
			(not NameplateSCT.db.profile.inverseNPCFilter and npcFiltersTable[destUnitId]) -- Normal Filter
		then
			return countDrop("npc filter")
		end
	end
	if playerGUID == sourceGUID or (NameplateSCT.db.profile.personal and playerGUID == destGUID) then -- Player events
		local destUnit = guidToUnit[destGUID]
		if (destUnit) or (destGUID == playerGUID and (NameplateSCT.db.profile.personal or isHeal)) then
			if isHeal then
				if playerGUID ~= sourceGUID then
					return countDrop("not your heal")
				end
				-- SPELL_HEAL / SPELL_PERIODIC_HEAL carry the same shape: spell, then the amount.
				local spellId, spellName, _, healAmount, _, _, healCrit = ...
				if spellId and spellId == 0 then spellId = nil end
				if NameplateSCT.db.profile.filterEnabled then
					local spellInFilter = filtersTable[tostring(spellId)] or filtersTable[spellName]
					if (NameplateSCT.db.profile.inverseSpellFilter and not spellInFilter) or (not NameplateSCT.db.profile.inverseSpellFilter and spellInFilter) then
						return
					end
				end
				return self:HealEvent(destGUID, spellName, healAmount, healCrit, spellId)
			elseif string.find(clue, "_MISSED") then
				local spellName, missType, spellId, amount, school, critical

				if (string.find(clue, "SWING")) then
					missType, _, amount, critical = ...
				else
					spellId, spellName, school, missType, _, amount, critical = ...
				end
				if spellId and spellId == 0 then
					spellId = nil -- Don't pass spellId 0
				end
				if NameplateSCT.db.profile.filterEnabled then
					local spellInFilter = filtersTable[tostring(spellId)] or filtersTable[spellName] or
						filtersTable["missed"]
					if (NameplateSCT.db.profile.inverseSpellFilter and not spellInFilter) or (not NameplateSCT.db.profile.inverseSpellFilter and spellInFilter) then
						return
					end
				end
				if missType == "ABSORB" then --Show absorbed as damage
					self:DamageEvent(destGUID, spellName, 0, -1, school, critical, spellId, amount)
				else
					self:MissEvent(destGUID, spellName, missType, spellId)
				end
			elseif string.find(clue, "_DAMAGE") or string.find(clue, "DAMAGE_SHIELD") then -- After _MISSED to not catch SPELL_DAMAGE_SHIELD_MISSED
				local spellName, amount, overkill, school, critical, spellId, absorbed
				if (string.find(clue, "SWING")) then
					spellName, amount, overkill, _, _, _, absorbed, critical = "melee", ...
				elseif (string.find(clue, "ENVIRONMENTAL")) then
					spellName, amount, overkill, school, _, _, absorbed, critical = ...
				else
					spellId, spellName, _, amount, overkill, school, _, _, absorbed, critical = ...
				end
				if spellId and spellId == 0 then
					spellId = nil -- Don't pass spellId 0
				end
				if NameplateSCT.db.profile.filterEnabled then
					local spellInFilter = filtersTable[tostring(spellId)] or filtersTable[spellName]
					if (NameplateSCT.db.profile.inverseSpellFilter and not spellInFilter) or (not NameplateSCT.db.profile.inverseSpellFilter and spellInFilter) then
						return
					end
				end
				self:DamageEvent(destGUID, spellName, amount, overkill, school, critical, spellId, absorbed,
					cleuCategory(clue))
			end
		end
	elseif sourceFlags and (bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_GUARDIAN) > 0 or bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) > 0) and bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0 then -- Pet/Guardian events
		local destUnit = guidToUnit[destGUID]
		if (destUnit) or (destGUID == playerGUID and (NameplateSCT.db.profile.personal or isHeal)) then
			if isHeal then
				local spellId, spellName, _, healAmount, _, _, healCrit = ...
				if spellId and spellId == 0 then spellId = nil end
				return self:HealEvent(destGUID, spellName, healAmount, healCrit, spellId)
			elseif string.find(clue, "_MISSED") then
				local spellName, missType, spellId, amount, critical

				if (string.find(clue, "SWING")) then
					missType, _, amount, critical = ...
				else
					spellId, spellName, _, missType, _, amount, critical = ...
				end
				if spellId and spellId == 0 then
					spellId = nil -- Don't pass spellId 0
				end
				if NameplateSCT.db.profile.filterEnabled then
					local spellInFilter = filtersTable[tostring(spellId)] or filtersTable[spellName] or
						filtersTable["missed"]
					if (NameplateSCT.db.profile.inverseSpellFilter and not spellInFilter) or (not NameplateSCT.db.profile.inverseSpellFilter and spellInFilter) then
						return
					end
				end
				if missType == "ABSORB" then
					self:DamageEvent(destGUID, spellName, 0, -1, "pet", critical, spellId, amount)
				end
			elseif string.find(clue, "_DAMAGE") or string.find(clue, "DAMAGE_SHIELD") then -- After _MISSED to not catch SPELL_DAMAGE_SHIELD_MISSED
				local spellName, amount, overkill, critical, spellId, absorbed
				if (string.find(clue, "SWING")) then
					spellName, amount, overkill, _, _, _, absorbed, critical, _, _, _ = "pet", ...
				elseif (string.find(clue, "ENVIRONMENTAL")) then
					spellName, amount, overkill, _, _, _, absorbed, critical = ...
				else
					spellId, spellName, _, amount, overkill, _, _, _, absorbed, critical = ...
				end
				if spellId and spellId == 0 then
					spellId = nil -- Don't pass spellId 0
				end
				if NameplateSCT.db.profile.filterEnabled then
					local spellInFilter = filtersTable[tostring(spellId)] or filtersTable[spellName]
					if (NameplateSCT.db.profile.inverseSpellFilter and not spellInFilter) or (not NameplateSCT.db.profile.inverseSpellFilter and spellInFilter) then
						return
					end
				end
				self:DamageEvent(destGUID, spellName, amount, overkill, "pet", critical, spellId, absorbed,
					cleuCategory(clue), true)
			end
		end
	end
end

function NameplateSCT:COMBAT_LOG_EVENT_UNFILTERED()
	local getEventInfo = C_CombatLog and C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
	if getEventInfo then
		return NameplateSCT:CombatFilter(getEventInfo())
	end
end

----------------------------------------------------------------------------------
-- RESTRICTED CLIENT PATH (Forever / Midnight): UNIT_COMBAT + secret values
----------------------------------------------------------------------------------
-- The combat log is not usable there, UnitGUID is secret for nameplates and UnitIsUnit
-- is unreliable, so a hit is anchored by resolving the unit token to its nameplate
-- frame instead of banking a GUID -> unit table. UNIT_COMBAT reports one hit once per
-- alias of the same unit ("nameplate3", "target", ...): duplicates are collapsed on the
-- resolved plate frame, and the (secret) amount is passed to the FontString untouched.

local MISS_ACTIONS = {
	ABSORB = true,
	BLOCK = true,
	DEFLECT = true,
	DODGE = true,
	EVADE = true,
	IMMUNE = true,
	MISS = true,
	PARRY = true,
	REFLECT = true,
	RESIST = true,
}

local HIT_ACTIONS = {
	WOUND = true, SPELL = true, DAMAGE = true, RANGE = true, SWING = true, PERIODIC = true,
}

local MODERN_DUPLICATE_WINDOW = 0.05
local ATTRIBUTION_WINDOW = 1.2
local HEAL_CAST_WINDOW = 2.0
local HEAL_CHANNEL_MAX = 12.0
local HEAL_HOT_WINDOW = 15.0
local CAST_META_TTL = 15.0
local MAX_TRACKED_HEAL_RECIPIENTS = 16

-- Ground, self-centered, totem and dual-use healing spells whose IsSpellHelpful query may
-- return false on some clients because they do not take a friendly unit target directly.
local HEAL_CAPABLE_SPELLS = {
	[136] = true,    -- Mend Pet
	[596] = true,    -- Prayer of Healing
	[633] = true,    -- Lay on Hands
	[724] = true,    -- Lightwell
	[740] = true,    -- Tranquility
	[1064] = true,   -- Chain Heal
	[5394] = true,   -- Healing Stream Totem
	[15237] = true,  -- Holy Nova
	[19236] = true,  -- Desperate Prayer
	[22842] = true,  -- Frenzied Regeneration
	[28880] = true,  -- Gift of the Naaru
	[32546] = true,  -- Binding Heal
	[34861] = true,  -- Circle of Healing / Holy Word: Sanctify
	[48438] = true,  -- Wild Growth
	[59542] = true,  -- Gift of the Naaru
	[59543] = true,  -- Gift of the Naaru
	[59544] = true,  -- Gift of the Naaru
	[59545] = true,  -- Gift of the Naaru
	[59547] = true,  -- Gift of the Naaru
	[59548] = true,  -- Gift of the Naaru
	[64843] = true,  -- Divine Hymn
	[73920] = true,  -- Healing Rain
	[85222] = true,  -- Light of Dawn
	[85673] = true,  -- Word of Glory
	[88685] = true,  -- Holy Word: Sanctify
	[90361] = true,  -- Spirit Mend
	[98008] = true,  -- Spirit Link Totem
	[108280] = true, -- Healing Tide Totem
	[109304] = true, -- Exhilaration
	[110744] = true, -- Divine Star
	[114165] = true, -- Holy Prism
	[115310] = true, -- Revival
	[120517] = true, -- Halo
	[121093] = true, -- Gift of the Naaru
	[123986] = true, -- Chi Burst
	[145205] = true, -- Efflorescence
	[157153] = true, -- Cloudburst Totem
	[185311] = true, -- Crimson Vial
	[191837] = true, -- Essence Font
	[194509] = true, -- Power Word: Radiance
	[196725] = true, -- Refreshing Jade Wind
	[197721] = true, -- Flourish
	[197995] = true, -- Wellspring
	[207778] = true, -- Downpour
	[323764] = true, -- Convoke the Spirits
	[355913] = true, -- Emerald Blossom
	[355936] = true, -- Dream Breath
	[363534] = true, -- Rewind
	[367226] = true, -- Spiritbloom
	[391528] = true, -- Convoke the Spirits
}

local modernLastHit = {}
local attributedSpellID, attributedSpellTime
local pendingCastMeta = {}
local lastSentCast
local activeHealChannel
local lastHealCastTime, lastHealSpellID, lastHealPetOnly
local recentHealRecipients = {}

local function clearHealAttributionState()
	attributedSpellID, attributedSpellTime = nil, nil
	pendingCastMeta = {}
	lastSentCast = nil
	activeHealChannel = nil
	lastHealCastTime, lastHealSpellID, lastHealPetOnly = nil, nil, nil
	recentHealRecipients = {}
end

function NameplateSCT:ClearHealAttribution()
	clearHealAttributionState()
end

---@param unit string?
---@return boolean
local function safeUnitCanAttack(unit)
	if not unit or unit == "player" or unit == "pet" then return false end
	local canAttackFn = _G.UnitCanAttack
	if type(canAttackFn) ~= "function" then return false end
	local ok, result = pcall(canAttackFn, "player", unit)
	if not ok or not canaccessvalue(result) or isSecretValue(result) then return false end
	return result == true
end

---@param unit string?
---@return string?
local function safeUnitName(unit)
	if not unit or type(_G.UnitName) ~= "function" then return nil end
	local ok, name = pcall(_G.UnitName, unit)
	if not ok or not canaccessvalue(name) or isSecretValue(name) then return nil end
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

---@param left string?
---@param right string?
---@return boolean
local function namesMatch(left, right)
	if not left or not right then return false end
	if left == right then return true end
	local shortLeft = strsplit("-", left)
	local shortRight = strsplit("-", right)
	return shortLeft ~= nil and shortLeft ~= "" and shortLeft == shortRight
end

---@param spellID any
---@return boolean
local function isHealCapableSpell(spellID)
	if not spellID or isSecretValue(spellID) or type(spellID) ~= "number" then return false end
	if HEAL_CAPABLE_SPELLS[spellID] then return true end
	local helpfulFn = (C_Spell and C_Spell.IsSpellHelpful) or _G.IsHelpfulSpell
	if type(helpfulFn) ~= "function" then return false end
	local ok, helpful = pcall(helpfulFn, spellID)
	if not ok or not canaccessvalue(helpful) or isSecretValue(helpful) then return false end
	return helpful == true
end

local function inspectCastTarget(token)
	if not token or type(_G.UnitExists) ~= "function" then return nil end
	local okExists, exists = pcall(_G.UnitExists, token)
	if not okExists or not canaccessvalue(exists) or isSecretValue(exists) or exists ~= true then
		return nil
	end
	if safeUnitCanAttack(token) then return nil end
	local plate = getNamePlateForUnit(token)
	local isSelf, selfKnown = safeUnitIsUnit(token, "player")
	local isPet, petKnown = safeUnitIsUnit(token, "pet")
	local name = (not plate) and safeUnitName(token) or nil
	if not plate and not (selfKnown and isSelf) and not (petKnown and isPet) and not name then
		return nil
	end
	return {
		plate = plate,
		isPlayer = (selfKnown and isSelf) or false,
		isPet = (petKnown and isPet) or false,
		name = name,
	}
end

local function captureFriendlyCastMeta(targetName)
	local meta = inspectCastTarget("mouseover") or inspectCastTarget("target") or {}
	if type(targetName) == "string" and canaccessvalue(targetName) and not isSecretValue(targetName) and targetName ~= "" then
		meta.name = targetName
		local playerName = safeUnitName("player")
		if playerName and namesMatch(targetName, playerName) then
			meta.isPlayer = true
		end
	end
	meta.time = GetTime()
	return meta
end

local function pruneExpiredHeals(now)
	for guid, entry in pairs(pendingCastMeta) do
		local age = now - (entry.time or 0)
		if age < 0 or age > CAST_META_TTL then
			pendingCastMeta[guid] = nil
		end
	end
	local write = 1
	for read = 1, #recentHealRecipients do
		local entry = recentHealRecipients[read]
		local age = now - (entry.time or 0)
		if age >= 0 and age <= HEAL_HOT_WINDOW then
			if write ~= read then recentHealRecipients[write] = entry end
			write = write + 1
		end
	end
	for i = write, #recentHealRecipients do
		recentHealRecipients[i] = nil
	end
end

local function recordHealRecipient(spellID, meta, castUnit, now)
	local isPetCast = (spellID == 136 or castUnit == "pet")
	if not meta and not isPetCast then return end
	local plate = meta and meta.plate or nil
	local name = meta and meta.name or nil
	local isPlayer = meta and meta.isPlayer or false
	local isPet = (meta and meta.isPet) or isPetCast
	if not plate and not name and not isPlayer and not isPet then return end

	for i = 1, #recentHealRecipients do
		local entry = recentHealRecipients[i]
		if (plate and entry.plate == plate)
			or (isPlayer and entry.isPlayer)
			or (isPet and entry.isPet)
			or (name and entry.name and namesMatch(entry.name, name))
		then
			entry.spellID = spellID
			entry.time = now
			entry.plate = plate or entry.plate
			entry.name = name or entry.name
			return
		end
	end

	if #recentHealRecipients >= MAX_TRACKED_HEAL_RECIPIENTS then
		table.remove(recentHealRecipients, 1)
	end
	recentHealRecipients[#recentHealRecipients + 1] = {
		plate = plate,
		name = name,
		isPlayer = isPlayer,
		isPet = isPet,
		spellID = spellID,
		time = now,
	}
end

local function takeCastMeta(castGUID, spellID, now)
	local meta = castGUID and pendingCastMeta[castGUID] or nil
	if castGUID then pendingCastMeta[castGUID] = nil end
	if not meta and lastSentCast then
		local age = now - (lastSentCast.time or 0)
		if lastSentCast.spellID == spellID and age >= 0 and age <= CAST_META_TTL then
			meta = lastSentCast.meta
		end
	end
	return meta
end

function NameplateSCT:UNIT_SPELLCAST_SENT(event, unit, targetName, castGUID, spellID)
	if unit ~= "player" and unit ~= "pet" then return end
	if not spellID or isSecretValue(spellID) then return end
	if not isHealCapableSpell(spellID) then return end
	local now = GetTime()
	pruneExpiredHeals(now)
	local meta = captureFriendlyCastMeta(targetName)
	if castGUID then pendingCastMeta[castGUID] = meta end
	lastSentCast = { spellID = spellID, time = now, meta = meta }
end

function NameplateSCT:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
	if unit ~= "player" and unit ~= "pet" then return end
	if not spellID or isSecretValue(spellID) then return end
	if not isHealCapableSpell(spellID) then return end
	if castGUID and not pendingCastMeta[castGUID] then
		pendingCastMeta[castGUID] = captureFriendlyCastMeta(nil)
	end
end

function NameplateSCT:UNIT_SPELLCAST_CHANNEL_START(event, unit, castGUID, spellID)
	if unit ~= "player" and unit ~= "pet" then return end
	if not spellID or isSecretValue(spellID) then return end
	if not isHealCapableSpell(spellID) then return end
	local now = GetTime()
	pruneExpiredHeals(now)
	local meta = takeCastMeta(castGUID, spellID, now) or captureFriendlyCastMeta(nil)
	activeHealChannel = { spellID = spellID, startedAt = now }
	lastHealCastTime, lastHealSpellID, lastHealPetOnly = now, spellID, (spellID == 136 or unit == "pet")
	recordHealRecipient(spellID, meta, unit, now)
end

function NameplateSCT:UNIT_SPELLCAST_CHANNEL_STOP(event, unit, castGUID, spellID)
	if unit ~= "player" and unit ~= "pet" then return end
	if activeHealChannel then
		lastHealCastTime = GetTime()
		activeHealChannel = nil
	end
end

function NameplateSCT:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
	if unit ~= "player" and unit ~= "pet" then return end
	if not spellID or isSecretValue(spellID) then return end
	local now = GetTime()
	attributedSpellID, attributedSpellTime = spellID, now
	if not isHealCapableSpell(spellID) then return end

	pruneExpiredHeals(now)
	local meta = takeCastMeta(castGUID, spellID, now)
	lastHealCastTime, lastHealSpellID, lastHealPetOnly = now, spellID, (spellID == 136 or unit == "pet")
	recordHealRecipient(spellID, meta, unit, now)
end

local function isYourRecentHeal(unit, plate, isPlayer)
	if not isPlayer and safeUnitCanAttack(unit) then
		return false, nil
	end

	local now = GetTime()
	if activeHealChannel then
		local age = now - activeHealChannel.startedAt
		if age >= 0 and age <= HEAL_CHANNEL_MAX then
			return true, activeHealChannel.spellID
		end
		activeHealChannel = nil
	end

	if lastHealCastTime then
		local age = now - lastHealCastTime
		if age >= 0 and age <= HEAL_CAST_WINDOW then
			if not lastHealPetOnly or unit == "pet" or safeUnitIsUnit(unit, "pet") then
				return true, lastHealSpellID
			end
		end
	end

	local unitName = (not isPlayer) and safeUnitName(unit) or nil
	local isPetUnit = (unit == "pet") or safeUnitIsUnit(unit, "pet")
	for i = #recentHealRecipients, 1, -1 do
		local entry = recentHealRecipients[i]
		local age = now - (entry.time or 0)
		if age >= 0 and age <= HEAL_HOT_WINDOW then
			if (entry.isPlayer and isPlayer)
				or (entry.plate and plate and entry.plate == plate)
				or (entry.isPet and isPetUnit)
				or (entry.name and unitName and namesMatch(entry.name, unitName))
			then
				return true, entry.spellID
			end
		end
	end

	return false, nil
end

local function recentAttributedSpell()
	if not attributedSpellID or not attributedSpellTime then
		return nil
	end
	local age = GetTime() - attributedSpellTime
	if age < 0 or age > ATTRIBUTION_WINDOW then
		return nil
	end
	return attributedSpellID
end

-- Which switch governs a UNIT_COMBAT hit, per action. The client reports one action per kind
-- of hit, so the same table also tells the animation pair apart.
local DAMAGE_CATEGORY = {
	SWING = "showMeleeDamage",
	WOUND = "showMeleeDamage",
	SPELL = "showSpellDamage",
	DAMAGE = "showSpellDamage",
	RANGE = "showRangedDamage",
	PERIODIC = "showPeriodicDamage",
}

-- SWING and WOUND are the auto-attack events, so they get the auto-attack animation pair.
local AUTO_ATTACK_ACTIONS = { SWING = true, WOUND = true }

--- Draw one heal on the unit that received it. Shared by both combat paths: the text, size,
--- colour and animation of a heal do not depend on where the event came from.
---@param unit string?
---@param amount any secret value on the restricted clients, never formatted there
---@param crit boolean
---@param spellId any
---@param guid string?
function NameplateSCT:DrawHeal(unit, amount, crit, spellId, guid)
	local profile = self.db.profile
	if not profile.showHealing then return countDrop("healing is off") end

	local text
	local isSecretAmount = isSecretValue(amount)
	if isSecretAmount then
		-- The client hands the amount over as a secret value: it goes to SetText by identity,
		-- so not even a leading "+" may be added to it.
		text = amount
	elseif type(amount) == "number" then
		text = "+" .. self:truncateText(amount)
	else
		text = tostring(amount)
	end

	local animation = crit and profile.animations.healCrit or profile.animations.heal
	if animation == "disabled" then return countDrop("heal animation is disabled") end

	local size = profile.formatting.size
	if crit and profile.sizing.crits then
		size = size * profile.sizing.critsScale
	end
	if not size or size < 5 then size = 5 end

	local red, green, blue = self:GetHealColor(crit)
	self:DisplayText(guid, text, size, animation, spellId, crit and true or false, nil, unit, red, green, blue)
end

--- Combat-log heals: the destination GUID names the unit that was healed.
---@param guid string
---@param spellName string?
---@param amount any
---@param crit boolean
---@param spellId any
function NameplateSCT:HealEvent(guid, spellName, amount, crit, spellId)
	if not self.db.profile.showHealing then return countDrop("healing is off") end
	local onPlayer = guid == playerGUID
	local unit = onPlayer and "player" or guidToUnit[guid]
	if not unit then return countDrop("no nameplate for unit") end
	return self:DrawHeal(unit, amount, crit and true or false, spellId, onPlayer and nil or guid)
end

function NameplateSCT:UNIT_COMBAT(event, unit, action, flagText, amount, schoolMask)
	if event ~= "UNIT_COMBAT" then return end
	local d = self.diagnostics
	if d then
		d.events = d.events + 1; d.lastEvent = GetTime()
	end
	if not unit or not action then return end
	if isSecretValue(unit) or isSecretValue(action) then return end
	local profile = self.db.profile
	if not profile.enabled then return countDrop("addon disabled") end

	local isHeal = (action == "HEAL")
	if action == "ENERGIZE" then return countDrop("resource gains are not drawn") end
	local isMiss = MISS_ACTIONS[action] == true
	if not isHeal and not isMiss and not HIT_ACTIONS[action] then return countDrop("unknown action") end
	if isHeal and not profile.showHealing then return countDrop("healing is off") end
	if isMiss and not profile.showMisses then return countDrop("misses off") end

	local category = (not isHeal and not isMiss) and DAMAGE_CATEGORY[action] or nil
	if category and not self:IsHitCategoryEnabled(category) then return countDrop("that kind of damage is off") end

	-- The client says whether the hit was a crit. Forever does not expose a combat log, but
	-- UNIT_COMBAT carries the same flags Blizzard's own combat feedback reads.
	local crit = (flagText == "CRITICAL" or flagText == "CRUSHING")

	-- Resolve the anchor first: nameplate mode needs a plate, screen mode does not.
	local isPlayer = (unit == "player")
	if not isPlayer then
		-- Damage you take can arrive under an alias that points at you: while a mob is
		-- hitting you, your target's target is you. Promote it to the player token so the
		-- "Show damage you take" setting governs it, screen mode puts it on the incoming
		-- side, and the duplicate collapse uses one bucket.
		local isSelf, answered = safeUnitIsUnit(unit, "player")
		if answered and isSelf then
			isPlayer = true
			unit = "player"
		end
	end
	-- "Damage you take" gates damage; a heal on you is its own category.
	if isPlayer and not isHeal and not profile.personal then return countDrop("damage you take is off") end

	local screenMode = self:IsScreenMode()
	local plate = (not isPlayer) and getNamePlateForUnit(unit) or nil
	if not isPlayer and not screenMode and not plate then
		return countDrop(isTargetOfTargetToken(unit) and "target-of-target has no plate" or "no nameplate for unit")
	end

	local matchedHealSpellId
	if isHeal then
		local okHeal
		okHeal, matchedHealSpellId = isYourRecentHeal(unit, plate, isPlayer)
		if not okHeal then
			return countDrop("not your heal")
		end
	end

	-- Collapse the per-alias repeat of a single hit.
	local key = plate or (screenMode and ("screen-" .. tostring(unit)) or "player")
	local now = GetTime()
	local last = modernLastHit[key]
	if last and last.action == action and (now - last.time) <= MODERN_DUPLICATE_WINDOW then
		last.time = now
		if d then d.duplicates = d.duplicates + 1 end
		return
	end
	modernLastHit[key] = { action = action, time = now }

	-- Target state is best effort: when UnitIsUnit cannot answer we show the text
	-- anyway rather than hiding every number.
	local onTarget, targetKnown = false, false
	if not isPlayer then
		onTarget, targetKnown = safeUnitIsUnit(unit, "target")
	end

	-- displayOffTargetText is honoured on both paths: an off-target unit known not to be
	-- the target is dropped when the setting is off. An answer the client refused keeps the
	-- number, because hiding everything would be worse than an extra number.
	if not isPlayer and targetKnown and not onTarget and not profile.displayOffTargetText then
		return countDrop("off-target text is off")
	end

	if isHeal then
		return self:DrawHeal(unit, amount, crit, matchedHealSpellId or recentAttributedSpell())
	end

	if isMiss then
		local animation = isPlayer and profile.animationsPersonal.miss or profile.animations.miss
		if animation == "disabled" then return countDrop("miss animation is disabled") end

		local color
		if isPlayer then
			color = profile.useMissColorPersonal and profile.missColorPersonal
		else
			color = profile.useMissColor and profile.missColor
		end
		color = color or (isPlayer and defaults.profile.missColorPersonal or defaults.profile.missColor)

		local size = profile.formatting.size
		if (not isPlayer) and targetKnown and not onTarget and profile.useOffTargetAppearance then
			size = profile.offTargetFormatting.size
		end
		if (not isPlayer) and profile.sizing.miss then
			size = size * profile.sizing.missScale
		end
		if size < 5 then size = 5 end

		if d then d.misses = d.misses + 1 end
		local red, green, blue = hexToRGB(color)
		self:DisplayText(nil, MISS_EVENT_STRINGS[action] or L["Missed"], size, animation,
			recentAttributedSpell(), true, nil, unit, red, green, blue)
		return
	end

	-- A hit. Threshold filtering and the small-hit modifiers are numeric comparisons that a
	-- secret amount cannot survive, so with a secret amount the raw value goes straight to
	-- the FontString and the numeric modifiers are skipped.
	local isSecretAmount = isSecretValue(amount)
	if isSecretAmount and d then d.secret = d.secret + 1 end

	if not isSecretAmount and type(amount) == "number" then
		local floor = math.max(profile.sizing.hideSmallHitsThreshold or 0, profile.minDamage or 0)
		if floor > amount then
			return countDrop("under the damage threshold")
		end
	end

	local autoattack = AUTO_ATTACK_ACTIONS[action] == true
	local animation
	if isPlayer then
		animation = (crit and profile.animationsPersonal.crit) or profile.animationsPersonal.normal
	elseif autoattack then
		animation = (crit and profile.animations.autoattackcrit) or profile.animations.autoattack
	else
		animation = (crit and profile.animations.crit) or profile.animations.ability
	end
	if animation == "disabled" then return countDrop("animation is disabled") end

	local size = profile.formatting.size
	if (not isPlayer) and targetKnown and not onTarget and profile.useOffTargetAppearance then
		size = profile.offTargetFormatting.size
	end
	if crit and not isPlayer and profile.sizing.crits and (not autoattack or profile.sizing.autoattackcritsizing) then
		size = size * profile.sizing.critsScale
	end
	if not size or size < 5 then size = 5 end

	local text
	if isSecretAmount then
		text = amount
	elseif type(amount) == "number" then
		text = self:truncateText(amount)
		if isPlayer then text = "-" .. text end
	else
		text = tostring(amount)
	end

	local red, green, blue = self:GetTextColor(isPlayer, schoolMask, nil, crit)
	self:DisplayText(nil, text, size, animation, recentAttributedSpell(), crit, nil, unit, red, green, blue)
end

-------------
-- DISPLAY --
-------------

local function commaSeperate(number)
	-- https://stackoverflow.com/questions/10989788/lua-format-integer
	local _, _, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')
	if not int then
		return tostring(number)
	end
	int = int:reverse():gsub("(%d%d%d)", "%1,")
	return minus .. int:reverse():gsub("^,", "") .. fraction
end

function NameplateSCT:truncateText(amount)
	if isSecretValue(amount) then
		return amount
	end
	if type(amount) ~= "number" then
		return tostring(amount)
	end
	local text
	if self.db.profile.truncateMethod == 'NONE' then
		if (self.db.profile.commaSeperate) then
			text = commaSeperate(amount)
		else
			text = tostring(amount)
		end
	elseif self.db.profile.truncateMethod == 'WESTERN' then
		local unitLetter = ''
		if self.db.profile.truncateLetter then
			unitLetter = 'k'
		end

		if amount >= 1000000 and self.db.profile.truncateLetter then
			text = string.format("%.1fM", amount / 1000000)
		elseif amount >= 10000 then
			text = string.format("%.0f%s", amount / 1000, unitLetter)
		elseif amount >= 1000 then
			text = string.format("%.1f%s", amount / 1000, unitLetter)
		else
			text = tostring(amount)
		end
	elseif self.db.profile.truncateMethod == 'EASTASIA' then
		local unitLetter = ''
		if self.db.profile.truncateLetter then
			unitLetter = L["Truncate Letter East Asia"]
			if unitLetter == 'Truncate Letter East Asia' then
				-- miss locale, Use its pronunciation instead
				-- 'w' means 'wan', 1wan = 10000
				unitLetter = 'w'
			end
		end

		if amount >= 100000 then
			text = string.format("%.0f%s", amount / 10000, unitLetter)
		elseif amount >= 10000 then
			text = string.format("%.1f%s", amount / 10000, unitLetter)
		else
			text = tostring(amount)
		end
	else
		-- Never reach
		text = tostring(amount)
	end

	return text
end

local numDamageEvents = 0
local lastDamageEventTime
local runningAverageDamageEvents = 0
function NameplateSCT:DamageEvent(guid, spellName, amount, overkill, school, crit, spellId, absorbed, category, isPet)
	if isPet and not self:IsHitCategoryEnabled("showPetDamage") then return countDrop("pet damage is off") end
	if category and not self:IsHitCategoryEnabled(category) then return countDrop("that kind of damage is off") end
	local isSecretAmount = isSecretValue(amount)
	if isSecretAmount and NameplateSCT.diagnostics then
		NameplateSCT.diagnostics.secret = NameplateSCT.diagnostics.secret + 1
	end
	local isSecretAbsorbed = isSecretValue(absorbed)
	local isSecretCrit = isSecretValue(crit)

	amount = amount or 0
	absorbed = absorbed or 0
	local onPlayer = guid == playerGUID

	-- Hide small hits: the relative threshold and the absolute minimum both apply
	if not isSecretAmount and not isSecretAbsorbed then
		local floor = math.max(self.db.profile.sizing.hideSmallHitsThreshold or 0, self.db.profile.minDamage or 0)
		if floor > (amount + absorbed) then
			return countDrop("under the damage threshold")
		end
	end

	local text, animation, pow, size
	local red, green, blue = 1, 1, 1
	local autoattack = spellName == "melee" or spellName == "pet"
	local critFlag = (not isSecretCrit) and (crit == true or crit == 1)

	-- select an animation
	if (autoattack and critFlag) then
		animation = not onPlayer and self.db.profile.animations.autoattackcrit or self.db.profile.animationsPersonal
			.crit
		pow = true
	elseif (autoattack) then
		animation = not onPlayer and self.db.profile.animations.autoattack or self.db.profile.animationsPersonal.normal
		pow = false
	elseif (critFlag) then
		animation = not onPlayer and self.db.profile.animations.crit or self.db.profile.animationsPersonal.crit
		pow = true
	elseif (not autoattack and not critFlag) then
		animation = not onPlayer and self.db.profile.animations.ability or self.db.profile.animationsPersonal.normal
		pow = false
	end

	-- skip if this damage event is disabled
	if (animation == "disabled") then
		return countDrop("animation is disabled")
	end

	local unit = guidToUnit[guid]
	local isTarget = safeUnitIsUnit(unit, "target")

	if (not isTarget and not self.db.profile.displayOffTargetText) then
		return countDrop("off-target text is off")
	end

	if (self.db.profile.useOffTargetAppearance and not isTarget and not onPlayer) then
		size = self.db.profile.offTargetFormatting.size
	else
		size = self.db.profile.formatting.size
	end

	if not NameplateSCT.db.profile.showIconOnly then
		if isSecretAmount then
			text = amount
		else
			-- truncate
			text = self:truncateText(amount)

			-- if damage was done to the player, negate the amount.
			if onPlayer then
				text = ("-%s"):format(text)
			end

			if NameplateSCT.db.profile.showAbsorbDamage and not isSecretAbsorbed and absorbed > 0 then
				local absorbedText = self:truncateText(absorbed)
				text = L["%s (A: %s)"]:format(text, absorbedText)
			end
		end
		-- Colour is applied to the FontString, not woven into the text.
		red, green, blue = self:GetTextColor(onPlayer, school, spellName, critFlag)
	end

	-- shrink small hits
	if not isSecretAmount and (self.db.profile.sizing.smallHits or self.db.profile.sizing.smallHitsHide) and not onPlayer then
		if (not lastDamageEventTime or (lastDamageEventTime + SMALL_HIT_EXPIRY_WINDOW < GetTime())) then
			numDamageEvents = 0
			runningAverageDamageEvents = 0
		end

		runningAverageDamageEvents = ((runningAverageDamageEvents * numDamageEvents) + amount) / (numDamageEvents + 1)
		numDamageEvents = numDamageEvents + 1
		lastDamageEventTime = GetTime()

		if ((not critFlag and amount < SMALL_HIT_MULTIPIER * runningAverageDamageEvents)
				or (critFlag and amount / 2 < SMALL_HIT_MULTIPIER * runningAverageDamageEvents)) then
			if self.db.profile.sizing.smallHitsHide then
				-- skip this damage event, it's too small
				return
			else
				size = size * self.db.profile.sizing.smallHitsScale
			end
		end
	end

	-- embiggen crit's size
	if (self.db.profile.sizing.crits and critFlag) and not onPlayer then
		if (autoattack and not self.db.profile.sizing.autoattackcritsizing) then
			-- don't embiggen autoattacks
			pow = false
		else
			size = size * self.db.profile.sizing.critsScale
		end
	end

	-- make sure that size is larger than 5
	if (size < 5) then
		size = 5
	end

	if NameplateSCT.db.profile.showIconOnly then
		self:DisplayIconWithoutText(guid, size, animation, spellId, pow, spellName)
	elseif (not isSecretAmount and type(overkill) == "number" and overkill > 0 and (self.db.profile.shouldDisplayOverkill or onPlayer)) then
		text = L["%s (O: %s)"]:format(text, self:truncateText(overkill))
		self:DisplayTextOverkill(guid, text, size, animation, spellId, pow, spellName, red, green, blue)
	else
		self:DisplayText(guid, text, size, animation, spellId, pow, spellName, nil, red, green, blue)
	end
end

function NameplateSCT:MissEvent(guid, spellName, missType, spellId)
	if not self.db.profile.showMisses then return end

	local text, animation, pow, size, color
	local unit = guidToUnit[guid]
	local isTarget = safeUnitIsUnit(unit, "target")

	if playerGUID ~= guid then
		animation = self.db.profile.animations.miss
		color = self.db.profile.useMissColor and self.db.profile.missColor or defaults.profile.missColor
	else
		animation = self.db.profile.animationsPersonal.miss
		color = self.db.profile.useMissColorPersonal and self.db.profile.missColorPersonal or
			defaults.profile.missColorPersonal
	end

	-- No animation set, cancel out
	if (animation == "disabled") then return countDrop("miss animation is disabled") end

	if (self.db.profile.useOffTargetAppearance and not isTarget and playerGUID ~= guid) then
		size = self.db.profile.offTargetFormatting.size
	else
		size = self.db.profile.formatting.size
	end

	-- embiggen miss size
	if self.db.profile.sizing.miss and playerGUID ~= guid then
		size = size * self.db.profile.sizing.missScale
	end

	pow = true

	if isSecretValue(missType) then
		text = missType
	else
		text = MISS_EVENT_STRINGS[missType] or L["Missed"]
	end
	local red, green, blue = hexToRGB(color)

	self:DisplayText(guid, text, size, animation, spellId, pow, spellName, nil, red, green, blue)
end

function NameplateSCT:DisplayText(guid, text, size, animation, spellId, pow, spellName, unitOverride, red, green, blue)
	local fontString
	local icon
	local unit = unitOverride
	if not unit and guid and not isSecretValue(guid) then
		unit = guidToUnit[guid]
	end
	local nameplate
	local screenMode = self:IsScreenMode()
	local isPersonal = (unit == "player")
		or (guid ~= nil and playerGUID ~= nil and not isSecretValue(guid) and guid == playerGUID)

	-- Where numbers about you are mounted: the configured screen area, or your character unit
	-- frame (the way PlateSCT's Incoming area can be placed over the frame, but built in).
	local unitFrame
	if isPersonal and self.db.profile.personalAnchor == "unitframe" then
		unitFrame = getPlayerUnitFrameAnchor()
	end

	if unitFrame then
		nameplate = unitFrame
	elseif screenMode then
		nameplate = self:GetScreenAnchor(isPersonal)
	else
		nameplate = getNamePlateForUnit(unit)

		-- if there isn't an anchor frame, make sure that there is a guidNameplatePosition cache entry
		if isPersonal and not nameplate then
			nameplate = "player"
		elseif (not nameplate) then
			return countDrop("no anchor for this number")
		end
	end

	fontString = getFontString()

	local d = self.diagnostics
	if d then
		d.drawn = d.drawn + 1
		d.lastDraw = GetTime()
	end

	fontString.NSCTText = text
	fontString:SetText(fontString.NSCTText)
	fontString:SetTextColor(red or 1, green or 1, blue or 1)

	fontString.NSCTFontSize = size
	fontString:SetFont(getFontPath(NameplateSCT.db.profile.font), fontString.NSCTFontSize,
		NameplateSCT.db.profile.fontFlag)
	applyShadow(fontString, size)
	-- GetStringHeight is SecretWhenAnchoringSecret: once this FontString holds a secret
	-- amount its height is secret too, and startHeight feeds arithmetic in powSizing. Keep
	-- it plain by measuring only when the client allows the read.
	local measured = fontString:GetStringHeight()
	if canaccessvalue(measured) and type(measured) == "number" and measured > 0 then
		fontString.startHeight = measured
	else
		fontString.startHeight = fontString.NSCTFontSize or 5
	end
	fontString.pow = pow

	fontString.unit = unit
	fontString.guid = guid
	fontString.screenMode = screenMode

	local texture = GetSpellTexture(spellId or spellName or "")
	if NameplateSCT.db.profile.showIcon and texture then
		icon = fontString.icon
		icon:Show()
		icon:SetTexture(texture)
		if MSQ and NameplateSCT.db.profile.enableMSQ then
			icon.button:SetSize(size * NameplateSCT.db.profile.iconScale, size * NameplateSCT.db.profile.iconScale)
			icon.button:SetPoint(
				inversePositions[NameplateSCT.db.profile.iconPosition],
				fontString,
				NameplateSCT.db.profile.iconPosition,
				NameplateSCT.db.profile.xOffsetIcon,
				NameplateSCT.db.profile.yOffsetIcon
			)
			icon.button:Show()
		else
			icon:SetSize(size * NameplateSCT.db.profile.iconScale, size * NameplateSCT.db.profile.iconScale)
			icon:SetPoint(
				inversePositions[NameplateSCT.db.profile.iconPosition],
				fontString,
				NameplateSCT.db.profile.iconPosition,
				NameplateSCT.db.profile.xOffsetIcon,
				NameplateSCT.db.profile.yOffsetIcon
			)
		end
		fontString.icon = icon
	else
		if fontString.icon then
			fontString.icon:Hide()
			if MSQ and NameplateSCT.db.profile.enableMSQ then
				fontString.icon.button:Hide()
			end
		end
	end
	local duration = NameplateSCT.db.profile.animations.animationspeed
	if animation == "fireworks" then
		duration = NameplateSCT.db.profile.animations.fireworksDuration
	end
	self:Animate(fontString, nameplate, duration, animation)
end

function NameplateSCT:DisplayIconWithoutText(guid, size, animation, spellId, pow, spellName, unitOverride)
	local fontString
	local icon
	local unit = unitOverride
	if not unit and guid and not isSecretValue(guid) then
		unit = guidToUnit[guid]
	end
	local nameplate
	local screenMode = self:IsScreenMode()

	if screenMode then
		local incoming = (unit == "player")
			or (guid and playerGUID and not isSecretValue(guid) and guid == playerGUID)
		nameplate = self:GetScreenAnchor(incoming)
	else
		nameplate = getNamePlateForUnit(unit)

		if unit == "player" and not nameplate then
			nameplate = "player"
		elseif guid and playerGUID == guid and not unit then
			nameplate = "player"
		elseif (not nameplate) then
			return countDrop("no anchor for this number")
		end
	end

	fontString = getFontString()
	fontString.NSCTText = ""
	fontString:SetText(fontString.NSCTText)
	applyShadow(fontString)
	fontString.NSCTFontSize = size
	fontString.startHeight = fontString.NSCTFontSize
	fontString.pow = pow

	if (fontString.startHeight <= 0) then
		fontString.startHeight = 5
	end

	fontString.unit = unit
	fontString.guid = guid
	fontString.screenMode = screenMode

	local texture = GetSpellTexture(spellId or spellName or "")
	if NameplateSCT.db.profile.showIcon and texture then
		icon = fontString.icon
		icon:Show()
		icon:SetTexture(texture)
		if MSQ and NameplateSCT.db.profile.enableMSQ then
			icon.button:SetSize(size * NameplateSCT.db.profile.iconScale, size * NameplateSCT.db.profile.iconScale)
			icon.button:SetPoint(
				inversePositions[NameplateSCT.db.profile.iconPosition],
				fontString,
				NameplateSCT.db.profile.iconPosition,
				NameplateSCT.db.profile.xOffsetIcon,
				NameplateSCT.db.profile.yOffsetIcon
			)
			icon.button:Show()
		else
			icon:SetSize(size * NameplateSCT.db.profile.iconScale, size * NameplateSCT.db.profile.iconScale)
			icon:SetPoint(
				inversePositions[NameplateSCT.db.profile.iconPosition],
				fontString,
				NameplateSCT.db.profile.iconPosition,
				NameplateSCT.db.profile.xOffsetIcon,
				NameplateSCT.db.profile.yOffsetIcon
			)
		end
		fontString.icon = icon
	else
		if fontString.icon then
			fontString.icon:Hide()
			if MSQ and NameplateSCT.db.profile.enableMSQ then
				fontString.icon.button:Hide()
			end
		end
	end
	local duration = NameplateSCT.db.profile.animations.animationspeed
	if animation == "fireworks" then
		duration = NameplateSCT.db.profile.animations.fireworksDuration
	end
	self:Animate(fontString, nameplate, duration, animation)
end

function NameplateSCT:DisplayTextOverkill(guid, text, size, animation, spellId, pow, spellName, red, green, blue)
	local fontString
	local icon
	local nameplate = "player"

	fontString = getFontString()

	fontString.NSCTText = text
	fontString:SetText(fontString.NSCTText)
	fontString:SetTextColor(red or 1, green or 1, blue or 1)

	fontString.NSCTFontSize = size
	fontString:SetFont(getFontPath(NameplateSCT.db.profile.font), fontString.NSCTFontSize,
		NameplateSCT.db.profile.fontFlag)
	applyShadow(fontString, size)
	-- GetStringHeight is SecretWhenAnchoringSecret: once this FontString holds a secret
	-- amount its height is secret too, and startHeight feeds arithmetic in powSizing. Keep
	-- it plain by measuring only when the client allows the read.
	local measured = fontString:GetStringHeight()
	if canaccessvalue(measured) and type(measured) == "number" and measured > 0 then
		fontString.startHeight = measured
	else
		fontString.startHeight = fontString.NSCTFontSize or 5
	end
	fontString.pow = pow

	fontString.unit = "player"
	fontString.guid = guid
	local texture = GetSpellTexture(spellId or spellName or "")
	if NameplateSCT.db.profile.showIcon and texture then
		icon = fontString.icon
		icon:Show()
		icon:SetTexture(texture)
		if MSQ and NameplateSCT.db.profile.enableMSQ then
			icon.button:SetSize(size * NameplateSCT.db.profile.iconScale, size * NameplateSCT.db.profile.iconScale)
			icon.button:SetPoint(
				inversePositions[NameplateSCT.db.profile.iconPosition],
				fontString,
				NameplateSCT.db.profile.iconPosition,
				NameplateSCT.db.profile.xOffsetIcon,
				NameplateSCT.db.profile.yOffsetIcon
			)
			icon.button:Show()
		else
			icon:SetSize(size * NameplateSCT.db.profile.iconScale, size * NameplateSCT.db.profile.iconScale)
			icon:SetPoint(
				inversePositions[NameplateSCT.db.profile.iconPosition],
				fontString,
				NameplateSCT.db.profile.iconPosition,
				NameplateSCT.db.profile.xOffsetIcon,
				NameplateSCT.db.profile.yOffsetIcon
			)
		end
		fontString.icon = icon
	else
		if fontString.icon then
			fontString.icon:Hide()
			if MSQ and NameplateSCT.db.profile.enableMSQ then
				fontString.icon.button:Hide()
			end
		end
	end
	local duration = NameplateSCT.db.profile.animations.animationspeed
	if animation == "fireworks" then
		duration = NameplateSCT.db.profile.animations.fireworksDuration
	end
	self:Animate(fontString, nameplate, duration, animation)
end

function NameplateSCT:ColorText(startingText, guid, pGUID, school, spellName, crit)
	if isSecretValue(startingText) then
		return startingText
	end
	local finalText
	if guid ~= (pGUID or playerGUID) then
		if crit and self.db.profile.useCritColor then
			finalText = "|Cff" .. self.db.profile.critColor .. startingText .. "|r"
		elseif self.db.profile.damageColor and school and DAMAGE_TYPE_COLORS[school] then
			finalText = "|Cff" .. DAMAGE_TYPE_COLORS[school] .. startingText .. "|r"
		elseif self.db.profile.damageColor and spellName == "melee" and DAMAGE_TYPE_COLORS[spellName] then
			finalText = "|Cff" .. DAMAGE_TYPE_COLORS[spellName] .. startingText .. "|r"
		else
			finalText = "|Cff" .. self.db.profile.defaultColor .. startingText .. "|r"
		end
	else
		if self.db.profile.damageColorPersonal and school and DAMAGE_TYPE_COLORS[school] then
			finalText = "|Cff" .. DAMAGE_TYPE_COLORS[school] .. startingText .. "|r"
		elseif self.db.profile.damageColorPersonal and spellName == "melee" and DAMAGE_TYPE_COLORS[spellName] then
			finalText = "|Cff" .. DAMAGE_TYPE_COLORS[spellName] .. startingText .. "|r"
		else
			finalText = "|Cff" .. self.db.profile.defaultColorPersonal .. startingText .. "|r"
		end
	end

	return finalText
end

-------------
-- OPTIONS --
-------------

-- The Blizzard AddOns panel is a launcher, not a settings tree.
-- It used to mirror every saved setting in one very tall AceConfig page. That page cannot
-- scroll inside the client's options canvas, so the section ran off the bottom of the
-- window and nothing in it was reachable. The dashboard owns the settings now, so this
-- panel only says where they live and carries the one button that opens it.
local menu = {
	name = "NameplateSCT",
	handler = NameplateSCT,
	type = 'group',
	args = {
		nameplatesEnabled = {
			type = 'description',
			name = "|cFFFF0000" .. L["YOUR ENEMY NAMEPLATES ARE DISABLED, NAMEPLATESCT WILL NOT WORK!!"] .. "|r",
			hidden = function() return GetCVar("nameplateShowEnemies") == "1" end,
			order = 1,
			width = "full",
		},
		openDashboard = {
			type = 'execute',
			name = "Open NameplateSCT dashboard",
			desc = "Opens the settings window. /nsct opens the same window.",
			func = function() NameplateSCT:OpenMenu() end,
			order = 2,
			width = "full",
		},
		whereSettingsLive = {
			type = 'description',
			name = "Every setting, the profiles and the live combat-source counters are in that window.",
			order = 3,
			width = "full",
		},
	},
}

if isMidnight then
	menu.args = {
		disabledInMidnight = {
			type = 'description',
			name = "|cFFFF0000" ..
				L
				["Unfortunately Blizzard has not added a SCT API in Midnight, until they do this addon will not have any functionality."] ..
				"|r",
			order = 1,
			width = "full",
			fontSize = "large",
		},
		header = {
			type = 'header',
			name = "",
			order = 2,
		},
		blizzardToggleDesc = {
			type = 'description',
			name = L["If you want to enable or disable the blizzard SCT you can do so here"],
			order = 3,
			width = "full",
		},
		disableBlizzardFCT = {
			type = 'toggle',
			name = L["BlizzardSCT"],
			get = function() return readBlizzardCvar(blizzardCvar) == "1" end,
			set = function(_, newValue)
				writeBlizzardCvar(blizzardCvar, newValue and "1" or "0")
			end,
			order = 4,
			width = "full",
		},
		header2 = {
			type = 'header',
			name = "",
			order = 5,
		},
		thankYou = {
			type = 'description',
			name = "|cFFFFFF00" ..
				L
				["Thank you for the years of support, and hopefully we'll be able to bring NameplateSCT back in the future! - Justwait"] ..
				"|r",
			order = 6,
			width = "full",
		},
		openDashboard = {
			type = 'execute',
			name = "Open NameplateSCT dashboard",
			desc = "Opens the settings window. /nsct opens the same window.",
			func = function() NameplateSCT:OpenMenu() end,
			order = 7,
			width = "full",
		},
	}
end

-- The legacy AceConfig panel is where the AceDB profiles group lives (AceDBOptions builds
-- an AceConfig table, which the custom window cannot render).
function NameplateSCT:OpenLegacyOptions()
	if not optionsMenuName then return end
	if not Settings or not Settings.OpenToCategory then return end
	pcall(Settings.OpenToCategory, optionsMenuName)
end

function NameplateSCT:OpenMenu()
	-- Options/Settings.lua owns the dashboard window. The AddOns panel is only a launcher
	-- for it now, so a dashboard that is missing or throws is reported instead of falling
	-- through to that panel - silently opening the wrong window is what made /nsct look
	-- broken while the addon had in fact never built its own settings UI.
	local openDashboard = self.OpenDashboard
	if not openDashboard then
		if self.Print then
			self:Print("the settings window did not load; the NameplateSCT section in the AddOns options opens it.")
		end
		self:OpenLegacyOptions()
		return
	end

	local opened, err = pcall(openDashboard, self)
	if not opened and self.Print then
		self:Print("could not open the settings window: " .. tostring(err))
	end
end

function NameplateSCT:RegisterMenu()
	-- AceDBOptions can only do anything now that settings live in the profile namespace.
	local dbOptions = LibStub("AceDBOptions-3.0", true)
	if dbOptions and menu.args then
		local profiles = dbOptions:GetOptionsTable(self.db)
		if profiles then
			profiles.order = 900
			menu.args.profiles = profiles
		end
	end

	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("NameplateSCT", menu)
	_, optionsMenuName = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("NameplateSCT", "NameplateSCT")
end
