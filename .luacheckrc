std = "lua51"
max_line_length = false
exclude_files = { "Libs" }

globals = {
    -- WoW Globals
    "AceGUIWidgetLSMlists",
    "C_CombatLog",
    "C_AddOns",
    "C_NamePlate",
    "C_Secrets",
    "C_Spell",
    "CombatLogGetCurrentEventInfo",
    "CreateFrame",
    "GetAddOnMetadata",
    "GetLocale",
    "GameTooltip",
    "GameFontHighlight",
    "ChatFontNormal",
    "Enum",
    "GetBuildInfo",
    "GetCVar",
    "GetSpellTexture",
    "GetTime",
    "InterfaceOptionsFrame_OpenToCategory",
    "LibStub",
    "SetCVar",
    "Settings",
    "UIParent",
    "UnitGUID",
    "UnitIsDead",
    "UnitIsUnit",
    "UISpecialFrames",
    "STANDARD_TEXT_FONT",
    "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_MAINLINE",
    "WOW_PROJECT_ID",
    "bit",
    "canaccessvalue",
    "issecretvalue",
    "strsplit",

    -- Combat Log Constants
    "COMBATLOG_OBJECT_AFFILIATION_MINE",
    "COMBATLOG_OBJECT_TYPE_GUARDIAN",
    "COMBATLOG_OBJECT_TYPE_PET",

    -- Spell School Masks
    "SCHOOL_MASK_PHYSICAL",
    "SCHOOL_MASK_HOLY",
    "SCHOOL_MASK_FIRE",
    "SCHOOL_MASK_NATURE",
    "SCHOOL_MASK_FROST",
    "SCHOOL_MASK_SHADOW",
    "SCHOOL_MASK_ARCANE",
}

ignore = {
    "212", -- unused argument
    "213", -- unused loop variable
}

-- The harness deliberately defines the client environment it tests against, so its
-- global assignments are the point, not a leak.
files["Tests/harness/*.lua"] = {
    allow_defined_top = true,
    -- the harness defines the whole client environment; the addon reads those globals
    -- through _G, so luacheck cannot see the read from inside this file
    ignore = { "111", "112", "131" }, -- the harness defines the client environment on purpose
    globals = { "UnitExists", "GameTooltip", "CanAlert" },
}
files["Tests/**"] = { allow_defined_top = true }
