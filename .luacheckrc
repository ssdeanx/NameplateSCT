std = "lua51"
max_line_length = false
exclude_files = { "Libs" }

globals = {
    -- WoW Globals
    "AceGUIWidgetLSMlists",
    "C_CombatLog",
    "C_NamePlate",
    "C_Secrets",
    "C_Spell",
    "CombatLogGetCurrentEventInfo",
    "CreateFrame",
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
    "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_ID",
    "bit",
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
