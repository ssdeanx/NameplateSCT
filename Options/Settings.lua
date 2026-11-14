--------------------------------------------------------------------------------
-- NameplateSCT options: settings window
--------------------------------------------------------------------------------
-- One self-contained settings window in this addon's own brand palette (sampled from
-- logo.png): cool near-black surfaces, one logo-orange accent, logo red for danger.
-- Every key in the saved-variable schema is reachable here, and the dashboard reports
-- the live combat-event path, because the usual "nothing shows up" failure is a silent
-- event-source problem rather than a styling one.

local NS = _G.NameplateSCT
if not NS then return end

local W = NS.W
if not W then return end
local C = W.C

local WINDOW_WIDTH, WINDOW_HEIGHT = 1200, 800
local SIDEBAR_WIDTH, HEADER_HEIGHT = 232, 76
-- Chrome: a page header above the scroll area and a status bar under it, so the window
-- reads as an application rather than one long list.
local CONTENT_TOP = HEADER_HEIGHT + 66
local FOOTER_HEIGHT = 32
local VIEWPORT_HEIGHT = WINDOW_HEIGHT - CONTENT_TOP - FOOTER_HEIGHT - 10
local PAD_LEFT, PAD_RIGHT = 32, 24
local CONTENT_WIDTH = WINDOW_WIDTH - SIDEBAR_WIDTH - PAD_LEFT - PAD_RIGHT - 14
local ROW = 44
local SLIDER_ROW = 54
local SECTION_GAP = 26

local LOGO = "Interface\\AddOns\\NameplateSCT\\logo"

local frame
local ensurePage
local selectedPageId
local refreshables = {}
local pageRefreshHooks = {}

-- Every control records the profile path it owns and the setter the widget drives. The test
-- harness uses this to prove, in both directions, that each saved key has a control and
-- each control writes exactly that key - a text match cannot show either.
local controls = {}
local buildingPage
NS.settingsControls = controls

-- Settings only the combat log can honour. Forever and Midnight hide the combat log, so
-- these rows are shown disabled with the reason in the label instead of quietly saving a
-- value nothing reads. NS.cleuOnlySettings is the contract the harness checks.
local CLEU_ONLY = {
	personalOnly = true,
	showAbsorbDamage = true,
	shouldDisplayOverkill = true,
	useCritColor = true,
	critColor = true,
	["sizing.crits"] = true,
	["sizing.critsScale"] = true,
	["sizing.autoattackcritsizing"] = true,
	["sizing.smallHits"] = true,
	["sizing.smallHitsHide"] = true,
	["sizing.smallHitsScale"] = true,
	["animations.crit"] = true,
	["animations.autoattack"] = true,
	["animations.autoattackcrit"] = true,
	["animationsPersonal.crit"] = true,
}
NS.cleuOnlySettings = CLEU_ONLY

local function declareControl(kind, path, setter, extra)
	local record = { kind = kind, path = path, set = setter, page = buildingPage }
	if extra then
		for key, value in pairs(extra) do record[key] = value end
	end
	controls[#controls + 1] = record
end

-- A control change can enable or disable other rows (a dependent option), so the window is
-- refreshed once per change instead of on a timer. Guarded: refreshing a slider writes its
-- value back through OnValueChanged.
local refreshing = false
local lastRefreshAt = 0

-- The window is refreshed on change so dependent rows can enable or disable themselves.
-- Sliders are dragged, so they pass a minimum interval: a hundred refreshes per second of
-- eighty controls is real frame cost, and the value itself is already displayed by the
-- slider while it moves.
local function refreshSoon(minInterval)
	if refreshing or not frame or not frame:IsShown() then return end
	if minInterval then
		local now = GetTime()
		if (now - lastRefreshAt) < minInterval then return end
		lastRefreshAt = now
	end
	refreshing = true
	if NS.RefreshSettings then NS:RefreshSettings() end
	refreshing = false
end

local function db()
	return NS.db and NS.db.profile
end

local pathCache = {}

local function parsePath(path)
	local parts = pathCache[path]
	if not parts then
		parts = {}
		for part in string.gmatch(path, "[^.]+") do parts[#parts + 1] = part end
		pathCache[path] = parts
	end
	return parts
end

local function GetPath(path)
	local node = db()
	for _, part in ipairs(parsePath(path)) do
		if node == nil then return nil end
		node = node[part]
	end
	return node
end

local function SetPath(path, value)
	local node = db()
	if not node then return end
	local parts = parsePath(path)
	for index = 1, #parts - 1 do
		node = node[parts[index]]
		if node == nil then return end
	end
	node[parts[#parts]] = value
end

local function hasCombatLog()
	return not NS.hasCombatRestrictions
end

--- Is this row usable on the running client?
local function usable(path)
	return function() return hasCombatLog() end
end

--- Does the setting this row depends on currently apply?
local function when(path)
	return function() return GetPath(path) and true or false end
end

--- Screen areas only exist in screen mode.
local function screenMode()
	return function() return GetPath("displayMode") == "screen" end
end

-- A gated row says in its own label why it is not available.
local function presentLabel(label, path)
	if CLEU_ONLY[path] and not hasCombatLog() then
		return label .. "  ·  combat log only"
	end
	return label
end

-- The default for one dotted path, straight from the schema. Used by the page reset and by
-- the backup import, which validates every line against it.
local function defaultValue(path)
	local node = NS.defaults and NS.defaults.profile
	for part in path:gmatch("[^.]+") do
		if type(node) ~= "table" then return nil end
		node = node[part]
	end
	return node
end

local function track(control)
	if control and control.Refresh then refreshables[#refreshables + 1] = control end
	return control
end

local function addonVersion()
	local meta = _G.GetAddOnMetadata or (C_AddOns and C_AddOns.GetAddOnMetadata)
	if not meta then return "" end
	local ok, version = pcall(meta, "NameplateSCT", "Version")
	if ok and version then return version end
	return ""
end

local function rgbOf(color)
	return color[1], color[2], color[3]
end

local function clientLabel()
	if NS.isForever then return "Forever (Camelot)" end
	if NS.isMidnight then return "Retail" end
	return "Classic"
end

local function sourceLabel()
	if NS.hasCombatRestrictions then return "UNIT_COMBAT" end
	return "Combat log (CLEU)"
end

--------------------------------------------------------------------------------
-- Row helpers: each returns the next y so a builder reads as a list
--------------------------------------------------------------------------------

-- Rows follow ROW_WIDTH so a page can lay two columns out side by side; every builder runs
-- once, single-threaded, so a temporarily narrower width is safe.
local ROW_WIDTH = CONTENT_WIDTH

local function section(content, y, title)
	if y < 0 then y = y - SECTION_GAP end
	W.Section(content, title, y, ROW_WIDTH)
	return y - 26
end

local function toggle(content, y, label, path, tip, onChange, enabledWhen)
	local function apply(value)
		SetPath(path, value)
		if onChange then onChange(value) end
		refreshSoon()
	end
	label = presentLabel(label, path)
	declareControl("toggle", path, apply, { label = label, enabled = enabledWhen, gated = enabledWhen ~= nil })
	local _, control = W.ToggleRow(content, y, label,
		function() return GetPath(path) end, apply, ROW_WIDTH, tip, enabledWhen)
	controls[#controls].control = control
	track(control)
	return y - ROW
end

local function slider(content, y, label, path, minimum, maximum, step, formatter, enabledWhen)
	local function apply(value)
		SetPath(path, value)
		refreshSoon(0.1)
	end
	label = presentLabel(label, path)
	declareControl("slider", path, apply, {
		label = label, min = minimum, max = maximum, step = step,
		formatter = formatter, enabled = enabledWhen, gated = enabledWhen ~= nil,
	})
	local _, control = W.SliderRow(content, y, label, minimum, maximum, step,
		function() return GetPath(path) end, apply, ROW_WIDTH, formatter, enabledWhen)
	controls[#controls].control = control
	track(control)
	return y - SLIDER_ROW
end

-- One value from a list. The widget opens the shared selection menu; see W.SelectRow.
local function select(content, y, label, path, options, onChange, enabledWhen)
	local function apply(value)
		SetPath(path, value)
		if onChange then onChange(value) end
		refreshSoon()
	end
	label = presentLabel(label, path)
	declareControl("select", path, apply, {
		label = label, options = options, enabled = enabledWhen, gated = enabledWhen ~= nil,
	})
	local _, control = W.SelectRow(content, y, label, options,
		function() return GetPath(path) end, apply, ROW_WIDTH, enabledWhen)
	controls[#controls].control = control
	track(control)
	return y - ROW
end

-- A hex colour field. The widget validates before it commits and keeps the box focused
-- with an inline error while the value is wrong, so a typo never lands in the profile.
local function normalizeHex(value)
	value = tostring(value or ""):gsub("#", ""):lower():gsub("%s", "")
	if #value == 6 and value:match("^%x+$") then return value end
	return nil
end

local function hexField(content, y, label, path, enabledWhen)
	local function apply(value)
		local normalized = normalizeHex(value)
		if normalized then
			SetPath(path, normalized)
			refreshSoon()
		end
	end
	label = presentLabel(label, path)
	declareControl("hex", path, apply, {
		label = label, normalize = normalizeHex, enabled = enabledWhen, gated = enabledWhen ~= nil,
	})
	local _, box, swatch = W.ColourRow(content, y, label,
		function() return GetPath(path) end, apply, ROW_WIDTH, normalizeHex, enabledWhen)
	controls[#controls].control = box
	controls[#controls].swatch = swatch
	track(box)
	track(swatch)
	return y - SLIDER_ROW
end

--------------------------------------------------------------------------------
-- Option lists
--------------------------------------------------------------------------------

local ANIMATION_ORDER = { "verticalUp", "verticalDown", "fountain", "rainfall", "fireworks", "disabled" }

local ANIMATION_FALLBACK = {
	verticalUp = "Vertical Up",
	verticalDown = "Vertical Down",
	fountain = "Fountain",
	rainfall = "Rainfall",
	fireworks = "Fireworks",
	disabled = "Disabled",
}

local function animationOptions()
	local labels = NS.animationValues or {}
	local options = {}
	for _, key in ipairs(ANIMATION_ORDER) do
		options[#options + 1] = { value = key, text = labels[key] or ANIMATION_FALLBACK[key] or key }
	end
	return options
end

local function fontOptions()
	local SharedMedia = LibStub and LibStub("LibSharedMedia-3.0", true)
	local names = SharedMedia and SharedMedia:List("font") or {}
	local options = {}
	for _, name in ipairs(names) do
		options[#options + 1] = { value = name, text = name }
	end
	if #options == 0 then
		options[1] = { value = "Friz Quadrata TT", text = "Friz Quadrata TT" }
	end
	return options
end

local function strataOptions()
	local names = NS.strataNames or {}
	local options = {}
	for index, name in ipairs(names) do
		options[#options + 1] = { value = index, text = name }
	end
	return options
end

local DISPLAY_MODE_OPTIONS = {
	{ value = "nameplates", text = "Nameplates" },
	{ value = "screen", text = "Screen" },
}

local TRUNCATE_OPTIONS = {
	{ value = "NONE", text = "Full number" },
	{ value = "WESTERN", text = "k / M" },
	{ value = "EASTASIA", text = "East Asian (w)" },
}

local FLAG_OPTIONS = {
	{ value = "OUTLINE", text = "Outline" },
	{ value = "THICKOUTLINE", text = "Thick outline" },
	{ value = "", text = "Plain" },
}

local ICON_POSITION_OPTIONS = {
	{ value = "LEFT", text = "Left" },
	{ value = "RIGHT", text = "Right" },
	{ value = "TOP", text = "Top" },
	{ value = "BOTTOM", text = "Bottom" },
}

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local pages = {}
local buildSearch
local searchHint

local function newPage(id, title, description, group, hidden)
	pages[#pages + 1] = {
		id = id, title = title, description = description or "",
		group = group or "", hidden = hidden == true,
	}
	return pages[#pages]
end

--------------------------------------------------------------------------------
-- Dashboard
--------------------------------------------------------------------------------

local function formatUptime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds >= 3600 then
		return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	elseif seconds >= 60 then
		return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
	end
	return ("%ds"):format(seconds)
end

local function buildDashboard(content)
	local y = 0

	local sourceShort = NS.hasCombatRestrictions and "UNIT_COMBAT" or "CLEU"

	local function diagnostics()
		return NS.diagnostics or {}
	end

	local function droppedTotal()
		local total = 0
		for _, count in pairs(diagnostics().dropped or {}) do total = total + count end
		return total
	end

	-- KPI tiles -------------------------------------------------------------
	local tileGap = 10
	local tileWidth = math.floor((CONTENT_WIDTH - tileGap * 3) / 4)
	local tiles = {
		{
			label = "EVENTS",
			hint = "received",
			color = C.yellow,
			getter = function() return tostring(diagnostics().events or 0) end,
		},
		{
			label = "NUMBERS",
			hint = "drawn",
			color = C.good,
			getter = function() return tostring(diagnostics().drawn or 0) end,
		},
		{
			label = "DROPPED",
			hint = "not drawn",
			color = C.muted,
			getter = function() return tostring(droppedTotal()) end,
		},
		{ label = "SOURCE", hint = "damage feed", color = C.text, getter = function() return sourceShort end },
	}

	local statTexts = {}
	for index, tile in ipairs(tiles) do
		local card = CreateFrame("Frame", nil, content)
		card:SetSize(tileWidth, 80)
		card:SetPoint("TOPLEFT", content, "TOPLEFT", (index - 1) * (tileWidth + tileGap), y)
		W.Panel(card, C.card, C.line)

		W.Upper(card, tile.label, 14, -12, C.dim)
		local value = W.Text(card, "", 14, -28, tileWidth - 28, "semibold", 20, tile.color)
		W.Text(card, tile.hint, 14, -56, tileWidth - 28, "regular", 11, C.dim)

		statTexts[#statTexts + 1] = { region = value, getter = tile.getter }
	end
	y = y - 80 - 12

	-- Status strip ----------------------------------------------------------
	local strip = CreateFrame("Frame", nil, content)
	strip:SetSize(CONTENT_WIDTH, 46)
	strip:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	W.Panel(strip, C.card, C.line)

	local dot = strip:CreateTexture(nil, "ARTWORK")
	dot:SetSize(8, 8)
	dot:SetPoint("LEFT", 16, 0)
	dot:SetColorTexture(C.good[1], C.good[2], C.good[3])

	local statusText = W.Text(strip, "", nil, 0, CONTENT_WIDTH - 44, "medium", 13, C.text)
	statusText:SetPoint("LEFT", strip, "LEFT", 32, 0)
	statusText:SetJustifyV("MIDDLE")
	y = y - 46 - 12

	-- Actions ---------------------------------------------------------------
	local function sampleUnit()
		if C_NamePlate and C_NamePlate.GetNamePlates then
			local plates = C_NamePlate.GetNamePlates()
			if plates and plates[1] and plates[1].name then return plates[1].name end
		end
		return (UnitExists and UnitExists("target")) and "target" or "player"
	end

	local actions = {
		{
			label = "Test number",
			style = "accent",
			tooltip = "Draw one number on a nameplate to test the layout",
			onClick = function()
				NS:DisplayText(nil, "1,234", GetPath("formatting.size") or 20,
					GetPath("animations.ability") or "verticalUp", nil, false, nil, sampleUnit())
				NS:SetStatus("Drew one test number.", "good")
			end,
		},
		{
			label = "Test on you",
			tooltip = "Draw one number where damage you take appears",
			onClick = function()
				NS:DisplayText(nil, "987", GetPath("formatting.size") or 20,
					GetPath("animationsPersonal.normal") or "verticalUp", nil, false, nil, "player")
				NS:SetStatus("Drew one test number on you.", "good")
			end,
		},
		{
			label = "Reset counters",
			tooltip = "Set every diagnostic counter back to zero",
			onClick = function()
				local d = NS.diagnostics
				if not d then return end
				d.events, d.drawn, d.misses, d.secret = 0, 0, 0, 0
				d.duplicates, d.refused = 0, 0
				d.dropped = {}
				d.lastDrop = nil
				NS:SetStatus("Counters reset.", "good")
			end,
		},
		{
			label = "Copy details",
			tooltip = "Print a one-line diagnostic report to chat",
			onClick = function()
				local d = diagnostics()
				local pools, active = 0, 0
				if NS.GetPoolStats then pools, active = NS:GetPoolStats() end
				local message = ("NameplateSCT %s | %s | mode=%s | source=%s | events=%d drawn=%d dropped=%d | secret=%d refused=%d | pool=%d/%d")
					:format(addonVersion(), clientLabel(), tostring(GetPath("displayMode")),
						tostring(d.path or "?"), d.events or 0, d.drawn or 0, droppedTotal(),
						d.secret or 0, d.refused or 0, active, pools)
				if NS.Print then NS:Print(message) end
				if db() then db().lastDiagnostics = message end
				NS:SetStatus("Diagnostic line printed to chat.", "good")
			end,
		},
	}

	for index, action in ipairs(actions) do
		local button = W.Button(content, action.label, 148, 30, action.onClick, action.style)
		button:SetPoint("TOPLEFT", content, "TOPLEFT", (index - 1) * 156, y)
		button.tooltip = action.tooltip
	end
	y = y - 30 - 22

	-- Diagnostics: checks on the left, counters on the right -----------------
	y = section(content, y, "DIAGNOSTICS")

	local cardHeight = 180
	local checksWidth = 524

	local checksCard = CreateFrame("Frame", nil, content)
	checksCard:SetSize(checksWidth, cardHeight)
	checksCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	W.Panel(checksCard, C.card, C.line)

	W.Upper(checksCard, "WHAT THE ADDON CHECKS", 14, -10, C.dim)

	local checks = {
		{
			label = "Addon enabled",
			hint = "turn it on below",
			pass = function()
				local profile = db()
				return profile ~= nil and profile.enabled == true
			end,
		},
		{
			label = "Event source subscribed",
			hint = "reload the UI",
			pass = function() return diagnostics().registered == true end,
		},
		{
			label = "Enemy nameplates visible",
			hint = "enable enemy nameplates",
			pass = function()
				if GetPath("displayMode") == "screen" then return true end
				local value = GetCVar and GetCVar("nameplateShowEnemies")
				if value == nil then return true end
				return value == "1"
			end,
		},
		{
			label = "Combat events arriving",
			hint = "hit something",
			pass = function()
				local d = diagnostics()
				return (d.lastEvent or 0) > 0 and (GetTime() - d.lastEvent) < 15
			end,
		},
		{
			label = "Numbers reaching the screen",
			hint = "read the last drop reason",
			pass = function()
				local d = diagnostics()
				return (d.lastDraw or 0) > 0 and (GetTime() - d.lastDraw) < 15
			end,
		},
		{
			label = "Blizzard text not doubling up",
			hint = "turn on Hide Blizzard's own numbers",
			pass = function()
				local cvar = NS.blizzardCVar
				local profile = db()
				if not cvar or not profile then return true end
				if not profile.hideBlizzardFCT then return true end
				local value = GetCVar and GetCVar(cvar)
				if value == nil then return true end
				return value == "0"
			end,
		},
	}

	local checkRows = {}
	for index, check in ipairs(checks) do
		local rowY = -34 - (index - 1) * 23
		local stateDot = checksCard:CreateTexture(nil, "ARTWORK")
		stateDot:SetSize(7, 7)
		stateDot:SetPoint("TOPLEFT", 16, rowY - 3)
		W.Text(checksCard, check.label, 30, rowY, 300, "regular", 12, C.text)
		local state = W.Text(checksCard, "", 0, rowY, checksWidth - 40, "medium", 11, C.dim)
		state:SetPoint("TOPRIGHT", checksCard, "TOPRIGHT", -14, rowY)
		state:SetJustifyH("RIGHT")
		checkRows[#checkRows + 1] = { dot = stateDot, label = check.label, state = state, check = check }
	end

	local countersCard = CreateFrame("Frame", nil, content)
	countersCard:SetSize(CONTENT_WIDTH - checksWidth - 16, cardHeight)
	countersCard:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
	W.Panel(countersCard, C.card, C.line)

	local uptimeLabel = W.Upper(countersCard, "COUNTERS", 14, -10, C.dim)

	local counters = {
		{ "Events received", function() return tostring(diagnostics().events or 0) end },
		{ "Numbers drawn", function() return tostring(diagnostics().drawn or 0) end },
		{ "Misses drawn", function() return tostring(diagnostics().misses or 0) end },
		{ "Duplicates collapsed", function() return tostring(diagnostics().duplicates or 0) end },
		{ "Secret amounts", function() return tostring(diagnostics().secret or 0) end },
		{ "Client refusals", function() return tostring(diagnostics().refused or 0) end },
		{
			"Active / pooled",
			function()
				if not NS.GetPoolStats then return "-" end
				local pooled, active = NS:GetPoolStats()
				return ("%d / %d"):format(active, pooled)
			end,
		},
	}

	local counterRows = {}
	for index, entry in ipairs(counters) do
		local rowY = -34 - (index - 1) * 19
		W.Text(countersCard, entry[1], 14, rowY, 150, "regular", 11, C.dim)
		local value = W.Text(countersCard, "", 0, rowY, 100, "medium", 11, C.text)
		value:SetPoint("TOPRIGHT", countersCard, "TOPRIGHT", -14, rowY)
		value:SetJustifyH("RIGHT")
		counterRows[#counterRows + 1] = { region = value, getter = entry[2] }
	end

	local lastDropText = W.Text(countersCard, "", 14, -34 - 7 * 19 - 4, countersCard:GetWidth() - 28,
		"regular", 11, C.muted)

	y = y - cardHeight - 22

	-- Shadow and quick settings, in two columns ------------------------------
	local columnTop = y
	local columnWidth = math.floor((CONTENT_WIDTH - 16) / 2)
	ROW_WIDTH = columnWidth

	local leftY = section(content, columnTop, "TEXT SHADOW")
	leftY = toggle(content, leftY, "Text shadow", "textShadow",
		"Draws a shadow behind every number")
	leftY = slider(content, leftY, "Size", "shadow.size", 0.5, 2, 0.05,
		function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end, when("textShadow"))
	leftY = slider(content, leftY, "Distance", "shadow.distance", 0, 12, 0.5,
		function(value) return ("%.1f px"):format(value) end, when("textShadow"))
	leftY = slider(content, leftY, "Angle", "shadow.angle", 0, 360, 15,
		function(value) return ("%d deg"):format(value) end, when("textShadow"))

	local rightColumn = CreateFrame("Frame", nil, content)
	rightColumn:SetPoint("TOPLEFT", content, "TOPLEFT", columnWidth + 16, columnTop)
	rightColumn:SetSize(columnWidth, 200)

	local rightY = section(rightColumn, 0, "QUICK SETTINGS")
	rightY = toggle(rightColumn, rightY, "Addon enabled", "enabled", "Turns all numbers on or off",
		function(value)
			if value then NS:Enable() else NS:Disable() end
		end)
	rightY = select(rightColumn, rightY, "Display mode", "displayMode", DISPLAY_MODE_OPTIONS, function()
		NS:RefreshScreenAnchors()
		NS:ApplyBlizzardFCT()
	end)
	rightY = toggle(rightColumn, rightY, "Hide Blizzard's own numbers", "hideBlizzardFCT",
		"Turns off Blizzard's nameplate damage text so it cannot double up with ours",
		function() NS:ApplyBlizzardFCT() end)

	ROW_WIDTH = CONTENT_WIDTH

	y = math.min(leftY, columnTop + rightY - 22)

	-- Exposed for the harness: it checks the status line and the check rows react.
	NS.settingsDashboard = { status = statusText, checks = checkRows, tiles = statTexts }

	-- Refresh ---------------------------------------------------------------
	pageRefreshHooks[#pageRefreshHooks + 1] = function()
		for _, entry in ipairs(statTexts) do
			entry.region:SetText(tostring(entry.getter() or ""))
		end
		for _, entry in ipairs(counterRows) do
			entry.region:SetText(tostring(entry.getter() or "0"))
		end
		uptimeLabel:SetText("COUNTERS  ·  UP " .. formatUptime(GetTime() - ((diagnostics()).startedAt or GetTime())))

		local d = diagnostics()
		for _, row in ipairs(checkRows) do
			local passed = row.check.pass() and true or false
			local color = passed and C.good or C.warningText
			row.dot:SetColorTexture(color[1], color[2], color[3])
			row.state:SetText(passed and "OK" or row.check.hint)
			row.state:SetTextColor(color[1], color[2], color[3])
		end

		local failed = 0
		for _, row in ipairs(checkRows) do
			if not row.check.pass() then failed = failed + 1 end
		end

		local profile = db()
		local events = d.events or 0
		local drawn = d.drawn or 0

		local tone, message
		if not profile or not profile.enabled then
			tone, message = C.red, "The addon is disabled. Turn it on below."
		elseif d.registered ~= true then
			tone, message = C.red, "No event source is subscribed. Reload the UI; if that fails, post the error log."
		elseif events == 0 then
			tone = C.yellow
			message = "No combat events yet. Hit something; if this stays at zero, the event source is the problem."
		elseif drawn == 0 then
			tone = C.yellow
			message = ("Events arrive but nothing is drawn. Last drop: %s."):format(tostring(d.lastDrop or "unknown"))
		elseif failed > 0 then
			tone = C.yellow
			message = ("Working (%d events, %d numbers), but %d check(s) need attention."):format(events, drawn, failed)
		else
			tone = C.good
			message = ("Working: %d events received, %d numbers drawn, %d dropped."):format(events, drawn, droppedTotal())
		end

		dot:SetColorTexture(tone[1], tone[2], tone[3])
		statusText:SetText(message)
		statusText:SetTextColor(rgbOf(tone))

		if d.lastDrop then
			local count = (d.dropped or {})[d.lastDrop] or 0
			lastDropText:SetText(("Last drop: %s (%d)"):format(d.lastDrop, count))
		else
			lastDropText:SetText("Nothing dropped.")
		end
	end

	return y
end

--------------------------------------------------------------------------------
-- General
--------------------------------------------------------------------------------

local function buildGeneral(content)
	local y = 0
	y = section(content, y, "WHERE NUMBERS APPEAR")

	y = select(content, y, "Display mode", "displayMode", DISPLAY_MODE_OPTIONS, function()
		NS:RefreshScreenAnchors()
		NS:ApplyBlizzardFCT()
	end)

	y = toggle(content, y, "Show text that is not on your target", "displayOffTargetText")
	y = toggle(content, y, "Use a separate off-target look", "useOffTargetAppearance")
	y = toggle(content, y, "Hide Blizzard's own numbers", "hideBlizzardFCT",
		"Turns off Blizzard's nameplate damage text so it cannot double up with ours",
		function() NS:ApplyBlizzardFCT() end)

	y = section(content, y, "WHAT COUNTS")

	y = toggle(content, y, "Show damage you take", "personal")
	y = toggle(content, y, "Only damage you deal or take", "personalOnly",
		"Ignores damage other players do to your target", nil, usable("personalOnly"))
	y = toggle(content, y, "Show misses and avoidance", "showMisses")
	y = toggle(content, y, "Include absorbed amount", "showAbsorbDamage", nil, nil,
		usable("showAbsorbDamage"))
	y = toggle(content, y, "Show overkill amount", "shouldDisplayOverkill", nil, nil,
		usable("shouldDisplayOverkill"))

	y = slider(content, y, "Ignore hits below", "minDamage", 0, 5000, 10,
		function(value) return ("%d"):format(value) end)

	return y
end

--------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------

local function buildNumbers(content)
	local y = 0
	y = section(content, y, "FORMATTING")

	y = select(content, y, "Number style", "truncateMethod", TRUNCATE_OPTIONS)
	y = toggle(content, y, "Thousands separator", "commaSeperate")
	y = toggle(content, y, "Abbreviation letter (k / M)", "truncateLetter")

	y = section(content, y, "SIZE")

	y = slider(content, y, "Font size", "formatting.size", 5, 72, 1,
		function(value) return ("%d px"):format(value) end)
	y = slider(content, y, "Off-target size", "offTargetFormatting.size", 5, 72, 1,
		function(value) return ("%d px"):format(value) end, when("useOffTargetAppearance"))
	y = slider(content, y, "Text opacity", "formatting.alpha", 0.1, 1, 0.05,
		function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end)
	y = slider(content, y, "Off-target opacity", "offTargetFormatting.alpha", 0.1, 1, 0.05,
		function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end,
		when("useOffTargetAppearance"))

	y = section(content, y, "HIT FILTERING")

	y = slider(content, y, "Ignore hits below (static)", "sizing.hideSmallHitsThreshold", 0, 5000, 10,
		function(value) return ("%d"):format(value) end)
	y = toggle(content, y, "Scale down small hits", "sizing.smallHits",
		"Shrinks hits below your recent average damage", nil, usable("sizing.smallHits"))
	y = toggle(content, y, "Hide small hits entirely", "sizing.smallHitsHide", nil, nil,
		usable("sizing.smallHitsHide"))
	y = slider(content, y, "Small hit scale", "sizing.smallHitsScale", 0.1, 1, 0.05,
		function(value) return ("%.2fx"):format(value) end, usable("sizing.smallHitsScale"))

	y = section(content, y, "SIZE MODIFIERS")

	y = toggle(content, y, "Embiggen crits", "sizing.crits", nil, nil, usable("sizing.crits"))
	y = slider(content, y, "Crit scale", "sizing.critsScale", 1, 3, 0.05,
		function(value) return ("%.2fx"):format(value) end, usable("sizing.critsScale"))
	y = toggle(content, y, "Crit sizing for auto attacks", "sizing.autoattackcritsizing", nil, nil,
		usable("sizing.autoattackcritsizing"))
	y = toggle(content, y, "Embiggen misses", "sizing.miss")
	y = slider(content, y, "Miss scale", "sizing.missScale", 1, 3, 0.05,
		function(value) return ("%.2fx"):format(value) end, when("sizing.miss"))

	return y
end

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------

-- Live preview: the same font, outline, size, colour and shadow the render path uses, so a
-- shadow can be tuned by looking at it instead of guessing. Both styles are shown because
-- off-target numbers use their own size and opacity.
local function buildPreview(content, y)
	local box = CreateFrame("Frame", nil, content)
	box:SetSize(CONTENT_WIDTH, 104)
	box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	W.Panel(box, C.field, C.line)

	local function sample(x, title, sizePath, alphaPath)
		local panel = CreateFrame("Frame", nil, box)
		panel:SetSize(280, 74)
		panel:SetPoint("TOPLEFT", box, "TOPLEFT", 14 + x, -8)
		W.Upper(panel, title, 0, 0, C.dim)

		local shadow = panel:CreateFontString(nil, "ARTWORK")
		local text = panel:CreateFontString(nil, "OVERLAY")
		text:SetPoint("CENTER", panel, "CENTER", 0, -10)
		shadow:SetPoint("CENTER", text, "CENTER", 0, 0)

		return { text = text, shadow = shadow, sizePath = sizePath, alphaPath = alphaPath }
	end

	local samples = {
		sample(0, "ON YOUR TARGET", "formatting.size", "formatting.alpha"),
		sample(292, "OFF-TARGET", "offTargetFormatting.size", "offTargetFormatting.alpha"),
	}

	W.Text(box, "Preview only. Numbers on screen use the same font, outline, colour and shadow.", nil, 0, CONTENT_WIDTH - 28, "regular", 11, C.dim)
		:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 14, 8)

	local function refreshSample(entry)
		local path = NS.GetFontPath and NS.GetFontPath(GetPath("font")) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
		local flags = GetPath("fontFlag") or ""
		-- Clamped so a 72px setting still fits the box; the real size is what draws.
		local size = math.min(tonumber(GetPath(entry.sizePath)) or 20, 32)
		local red, green, blue = NS.hexToRGB(GetPath("defaultColor") or "ffff00")

		entry.text:SetFont(path, size, flags)
		entry.text:SetText("1,234")
		entry.text:SetTextColor(red, green, blue)
		entry.text:SetAlpha(tonumber(GetPath(entry.alphaPath)) or 1)

		local shadow = entry.shadow
		if GetPath("textShadow") then
			local scale = tonumber(GetPath("shadow.size")) or 1
			local distance = tonumber(GetPath("shadow.distance")) or 0
			local angle = math.rad(tonumber(GetPath("shadow.angle")) or 315)
			local sr, sg, sb = NS.hexToRGB(GetPath("shadow.color") or "000000")

			shadow:SetFont(path, size * scale, flags)
			shadow:SetText("1,234")
			shadow:SetTextColor(sr, sg, sb)
			shadow:SetAlpha((tonumber(GetPath("shadow.alpha")) or 1) * (tonumber(GetPath(entry.alphaPath)) or 1))
			shadow:ClearAllPoints()
			shadow:SetPoint("CENTER", entry.text, "CENTER", distance * math.cos(angle), distance * math.sin(angle))
			shadow:Show()
		else
			shadow:SetAlpha(0)
			shadow:Hide()
		end
	end

	NS.settingsPreview = samples
	pageRefreshHooks[#pageRefreshHooks + 1] = function()
		for _, entry in ipairs(samples) do refreshSample(entry) end
	end
	for _, entry in ipairs(samples) do refreshSample(entry) end

	return y - 104 - 16
end

local function buildAppearance(content)
	local y = buildPreview(content, 0)
	y = section(content, y, "TYPE")

	y = select(content, y, "Font", "font", fontOptions(), function() NS:ResetFontPathCache() end)
	y = select(content, y, "Outline", "fontFlag", FLAG_OPTIONS)
	y = toggle(content, y, "Text shadow", "textShadow",
		"Draws a shadow behind every number, sized and placed below")

	y = section(content, y, "TEXT SHADOW")

	y = slider(content, y, "Shadow size", "shadow.size", 0.5, 2, 0.05,
		function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end, when("textShadow"))
	y = slider(content, y, "Shadow distance", "shadow.distance", 0, 12, 0.5,
		function(value) return ("%.1f px"):format(value) end, when("textShadow"))
	y = slider(content, y, "Shadow angle", "shadow.angle", 0, 360, 15,
		function(value) return ("%d°"):format(value) end, when("textShadow"))
	y = slider(content, y, "Shadow opacity", "shadow.alpha", 0, 1, 0.05,
		function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end, when("textShadow"))
	y = hexField(content, y, "Shadow colour (hex)", "shadow.color", when("textShadow"))

	y = section(content, y, "SPELL ICONS")

	y = toggle(content, y, "Show spell icons", "showIcon")
	y = toggle(content, y, "Icons only, no numbers", "showIconOnly", nil, nil, when("showIcon"))
	y = toggle(content, y, "Remove icon border", "removeBorder", nil, nil, when("showIcon"))
	y = slider(content, y, "Icon scale", "iconScale", 0.5, 2, 0.05,
		function(value) return ("%.2fx"):format(value) end, when("showIcon"))
	y = select(content, y, "Icon position", "iconPosition", ICON_POSITION_OPTIONS, nil, when("showIcon"))

	-- Always shown: without Masque it stays on the page, disabled, instead of vanishing and
	-- leaving the player hunting for a setting that is not there.
	local masque = LibStub and LibStub("Masque", true)
	y = toggle(content, y, "Let Masque style the icons", "enableMSQ",
		masque and "Masque styles the spell icons" or "Requires the Masque addon",
		nil, function() return masque ~= nil and GetPath("showIcon") and true or false end)

	y = section(content, y, "COLOURS")

	y = toggle(content, y, "Colour damage by school", "damageColor")
	y = hexField(content, y, "Default colour (hex)", "defaultColor",
		function() return not GetPath("damageColor") end)
	y = toggle(content, y, "Colour damage you take", "damageColorPersonal")
	y = hexField(content, y, "Your damage taken (hex)", "defaultColorPersonal",
		function() return not GetPath("damageColorPersonal") end)

	y = section(content, y, "CRIT AND MISS COLOURS")

	y = toggle(content, y, "Use a crit colour", "useCritColor", nil, nil, usable("useCritColor"))
	y = hexField(content, y, "Crit colour (hex)", "critColor", usable("critColor"))
	y = toggle(content, y, "Use a miss colour", "useMissColor")
	y = hexField(content, y, "Miss colour (hex)", "missColor", when("useMissColor"))
	y = toggle(content, y, "Use a miss colour on you", "useMissColorPersonal")
	y = hexField(content, y, "Miss colour on you (hex)", "missColorPersonal",
		when("useMissColorPersonal"))

	return y
end

--------------------------------------------------------------------------------
-- Animations
--------------------------------------------------------------------------------

local function buildAnimations(content)
	local options = animationOptions()
	local y = 0

	y = section(content, y, "OUTGOING")

	y = select(content, y, "Ability hits", "animations.ability", options)
	y = select(content, y, "Critical hits", "animations.crit", options, nil, usable("animations.crit"))
	y = select(content, y, "Auto attacks", "animations.autoattack", options, nil,
		usable("animations.autoattack"))
	y = select(content, y, "Auto attack crits", "animations.autoattackcrit", options, nil,
		usable("animations.autoattackcrit"))
	y = select(content, y, "Miss / dodge / parry", "animations.miss", options)

	y = section(content, y, "ON YOU")

	y = select(content, y, "Damage you take", "animationsPersonal.normal", options)
	y = select(content, y, "Critical hits on you", "animationsPersonal.crit", options, nil,
		usable("animationsPersonal.crit"))
	y = select(content, y, "Misses on you", "animationsPersonal.miss", options)

	y = section(content, y, "TIMING")

	y = slider(content, y, "Animation speed", "animations.animationspeed", 0.2, 5, 0.1,
		function(value) return ("%.1fs"):format(value) end)
	y = slider(content, y, "Fireworks radius", "animations.fireworksRadius", 20, 300, 5,
		function(value) return ("%d"):format(value) end)
	y = slider(content, y, "Fireworks duration", "animations.fireworksDuration", 0.2, 5, 0.1,
		function(value) return ("%.1fs"):format(value) end)

	return y
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

local function buildPosition(content)
	local y = 0
	y = section(content, y, "NAMEPLATE OFFSET")

	y = slider(content, y, "Horizontal", "xOffset", -300, 300, 1, function(value) return ("%d"):format(value) end)
	y = slider(content, y, "Vertical", "yOffset", -300, 300, 1, function(value) return ("%d"):format(value) end)

	y = section(content, y, "OFFSET ON YOU")

	y = slider(content, y, "Horizontal", "xOffsetPersonal", -600, 600, 1, function(value) return ("%d"):format(value) end)
	y = slider(content, y, "Vertical", "yOffsetPersonal", -600, 600, 1, function(value) return ("%d"):format(value) end)

	y = section(content, y, "SCATTER")

	y = slider(content, y, "Horizontal variance", "xVariance", 0, 120, 1, function(value) return ("%d"):format(value) end)
	y = slider(content, y, "Vertical variance", "yVariance", 0, 120, 1, function(value) return ("%d"):format(value) end)

	y = section(content, y, "SCREEN AREAS")
	W.Text(content, "Used when the display mode is Screen.", 0, y, CONTENT_WIDTH, "regular", 12, C.muted)
	y = y - 22

	y = slider(content, y, "Outgoing horizontal", "screen.outgoingX", -900, 900, 5,
		function(value) return ("%d"):format(value) end, screenMode())
	y = slider(content, y, "Outgoing vertical", "screen.outgoingY", -600, 600, 5,
		function(value) return ("%d"):format(value) end, screenMode())
	y = slider(content, y, "Incoming horizontal", "screen.incomingX", -900, 900, 5,
		function(value) return ("%d"):format(value) end, screenMode())
	y = slider(content, y, "Incoming vertical", "screen.incomingY", -600, 600, 5,
		function(value) return ("%d"):format(value) end, screenMode())

	y = section(content, y, "ICON OFFSET")

	y = slider(content, y, "Icon horizontal", "xOffsetIcon", -100, 100, 1, function(value) return ("%d"):format(value) end)
	y = slider(content, y, "Icon vertical", "yOffsetIcon", -100, 100, 1, function(value) return ("%d"):format(value) end)

	y = section(content, y, "LAYERING")

	y = select(content, y, "Target numbers", "strata.target", strataOptions())
	y = select(content, y, "Off-target numbers", "strata.offTarget", strataOptions(), nil,
		function() return not GetPath("modOffTargetStrata") end)
	y = toggle(content, y, "Keep off-target one layer below", "modOffTargetStrata",
		"Off-target numbers are drawn one stratum under the target's")

	return y
end

--------------------------------------------------------------------------------
-- Filters
--------------------------------------------------------------------------------

local function buildFilters(content)
	local y = 0
	y = section(content, y, "SPELL FILTER")

	y = toggle(content, y, "Enable the spell filter", "filterEnabled")
	y = toggle(content, y, "Hide listed spells instead of allowing them", "inverseSpellFilter")

	W.Text(content, "One spell name or ID per line.", 0, y, CONTENT_WIDTH, "regular", 12, C.muted)
	y = y - 22

	local box = CreateFrame("EditBox", nil, content)
	box:SetSize(CONTENT_WIDTH - 8, 110)
	box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(65535)
	W.SetFont(box, "regular", 13)
	box:SetTextInsets(8, 8, 6, 6)
	box:SetTextColor(C.text[1], C.text[2], C.text[3])
	W.Panel(box, C.field, C.edge)
	box:SetText(GetPath("filter") or "")
	box:SetScript("OnEditFocusLost", function(self)
		NS:updateFilterTable(self:GetText() or "")
	end)
	do
		local function apply(value)
			NS:updateFilterTable(tostring(value or ""))
		end
		declareControl("text", "filter", apply)
	end
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	track(box)
	y = y - 122

	y = section(content, y, "NPC FILTER")

	y = toggle(content, y, "Hide listed NPCs instead of allowing them", "inverseNPCFilter")

	local npcBox = CreateFrame("EditBox", nil, content)
	npcBox:SetSize(CONTENT_WIDTH - 8, 80)
	npcBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	npcBox:SetMultiLine(true)
	npcBox:SetAutoFocus(false)
	npcBox:SetMaxLetters(65535)
	W.SetFont(npcBox, "regular", 13)
	npcBox:SetTextInsets(8, 8, 6, 6)
	npcBox:SetTextColor(C.text[1], C.text[2], C.text[3])
	W.Panel(npcBox, C.field, C.edge)
	npcBox:SetText(GetPath("npcFilter") or "")
	npcBox:SetScript("OnEditFocusLost", function(self)
		NS:updateNPCFilterTable(self:GetText() or "")
	end)
	do
		local function apply(value)
			NS:updateNPCFilterTable(tostring(value or ""))
		end
		declareControl("text", "npcFilter", apply)
	end
	npcBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	track(npcBox)
	y = y - 92

	return y
end

--------------------------------------------------------------------------------
-- About
--------------------------------------------------------------------------------

local function buildAbout(content)
	W.Image(content, LOGO, 132, 132, 0, -6)

	local x = 152
	W.Text(content, "NameplateSCT", x, -14, CONTENT_WIDTH - x, "semibold", 20, C.bright)
	W.Text(content, ("Version %s"):format(addonVersion()), x, -42, CONTENT_WIDTH - x, "regular", 13, C.muted)
	W.Text(content, "Scrolling combat text driven from nameplates.", x, -62, CONTENT_WIDTH - x, "regular", 13, C.dim)

	local y = -94
	local rows = {
		{ "Client", clientLabel() },
		{ "Combat source", sourceLabel() },
		{ "Display mode", tostring(GetPath("displayMode") or "nameplates") },
		{ "Settings", "/nsct" },
		{ "Profiles", "AceDB profiles, managed below" },
	}

	for _, entry in ipairs(rows) do
		W.Text(content, entry[1], x, y, 120, "medium", 13, C.dim)
		W.Text(content, entry[2], x + 126, y, CONTENT_WIDTH - x - 126, "medium", 13, C.text)
		y = y - 24
	end

	y = -268
	y = section(content, y, "PROFILE")

	local resetArmed = false
	local resetButton
	resetButton = W.Button(content, "Reset this profile to defaults", 250, 32, function()
		-- Destructive and immediate: the first click asks, the second one acts.
		if not resetArmed then
			resetArmed = true
			resetButton.label:SetText("Click again to confirm")
			if NS.SetStatus then NS:SetStatus("This erases every setting in the current profile.", "warning") end
			return
		end
		resetArmed = false
		resetButton.label:SetText("Reset this profile to defaults")
		if not (NS.db and NS.db.ResetProfile) then return end
		NS.db:ResetProfile()
		if NS.Print then NS:Print("NameplateSCT: profile reset to defaults.") end
		NS:RefreshScreenAnchors()
		NS:ApplyBlizzardFCT()
		NS:RefreshSettings()
		if NS.SetStatus then NS:SetStatus("Profile reset to defaults.", "good") end
	end)
	resetButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

	local profilesButton = W.Button(content, "Manage profiles (AceDB)", 250, 32, function()
		if NS.OpenLegacyOptions then NS:OpenLegacyOptions() end
	end, "quiet")
	profilesButton:SetPoint("TOPLEFT", content, "TOPLEFT", 262, y)

	y = y - 48
	W.Text(content, "Default colours are also used when school colouring is off.", 0, y, CONTENT_WIDTH, "regular", 12, C.dim)
	y = y - 20

	return y - 40
end


--------------------------------------------------------------------------------
-- Backup: export and import
--------------------------------------------------------------------------------
-- A plain `path=value` block, one setting per line. Import only ever writes keys that exist
-- in the schema and whose stored type matches the default, so a pasted block cannot inject a
-- key or a type - and nothing is ever executed the way loadstring would.

local BACKUP_HEADER = "NameplateSCT settings v1"

local function collectPaths(node, prefix, out)
	for key, value in pairs(node) do
		local path = prefix == "" and key or (prefix .. "." .. key)
		if type(value) == "table" then
			collectPaths(value, path, out)
		else
			out[#out + 1] = path
		end
	end
	return out
end

local function escapeValue(value)
	local text = tostring(value)
	text = text:gsub("\\", "\\\\"):gsub("\r", ""):gsub("\n", "\\n")
	return text
end

local function unescapeValue(text)
	text = text:gsub("\\n", "\n")
	text = text:gsub("\\\\", "\\")
	return text
end

--- Serialise the current profile, one setting per line.
---@return string
function NS:ExportSettings()
	local defaultsProfile = NS.defaults and NS.defaults.profile
	if not defaultsProfile then return BACKUP_HEADER end

	local paths = collectPaths(defaultsProfile, "", {})
	table.sort(paths)

	local lines = { BACKUP_HEADER }
	for _, path in ipairs(paths) do
		local value = GetPath(path)
		if value ~= nil then
			lines[#lines + 1] = path .. "=" .. escapeValue(value)
		end
	end
	return table.concat(lines, "\n")
end

--- Apply a settings block. Returns how many were applied and how many were refused.
---@param text string?
---@return number applied, number refused
function NS:ImportSettings(text)
	local defaultsProfile = NS.defaults and NS.defaults.profile
	if not defaultsProfile or type(text) ~= "string" then return 0, 0 end

	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = (line:gsub("\r", ""))
	end

	if (lines[1] or "") ~= BACKUP_HEADER then return 0, -1 end

	local applied, refused = 0, 0
	for index = 2, #lines do
		local path, raw = lines[index]:match("^([%w_%.]+)=(.*)$")
		local fallback = path and defaultValue(path)
		-- `false` and `0` are real defaults, so only nil means "not a setting of ours".
		if fallback == nil then
			refused = refused + 1
		else
			-- Some keys change representation at runtime (the strata settings hold an index
			-- number while their default is the name), so the live value's type wins.
			local current = GetPath(path)
			local expect = current ~= nil and type(current) or type(fallback)

			local value
			if expect == "boolean" then
				if raw == "true" or raw == "false" then value = raw == "true" end
			elseif expect == "number" then
				value = tonumber(raw)
			else
				value = unescapeValue(raw)
			end

			if value == nil then
				refused = refused + 1
			else
				SetPath(path, value)
				applied = applied + 1
			end
		end
	end

	return applied, refused
end

local function buildBackup(content)
	local y = 0
	y = section(content, y, "EXPORT")

	W.Text(content, "Keep a copy of your look, or share it. Select the block and press Ctrl+C to copy it.",
		0, y, ROW_WIDTH, "regular", 12, C.muted)
	y = y - 22

	local exportBox = CreateFrame("EditBox", nil, content)
	exportBox:SetSize(ROW_WIDTH - 8, 150)
	exportBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	exportBox:SetMultiLine(true)
	exportBox:SetAutoFocus(false)
	exportBox:SetMaxLetters(65535)
	W.SetFont(exportBox, "regular", 12)
	exportBox:SetTextInsets(8, 8, 6, 6)
	exportBox:SetTextColor(C.text[1], C.text[2], C.text[3])
	W.Panel(exportBox, C.field, C.edge)
	exportBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	y = y - 158

	local generate = W.Button(content, "Generate", 140, 28, function()
		exportBox:SetText(NS:ExportSettings())
		exportBox:SetFocus()
		exportBox:HighlightText()
		NS:SetStatus("Settings block generated and selected; press Ctrl+C.", "good")
	end, "accent")
	generate:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

	local copy = W.Button(content, "Select all", 140, 28, function()
		exportBox:SetFocus()
		exportBox:HighlightText()
	end, "quiet")
	copy:SetPoint("TOPLEFT", content, "TOPLEFT", 148, y)

	y = y - 28 - 22
	y = section(content, y, "IMPORT")

	W.Text(content, "Paste a block above into this box and press Import. Only settings this addon knows are applied.",
		0, y, ROW_WIDTH, "regular", 12, C.muted)
	y = y - 22

	local importBox = CreateFrame("EditBox", nil, content)
	importBox:SetSize(ROW_WIDTH - 8, 150)
	importBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	importBox:SetMultiLine(true)
	importBox:SetAutoFocus(false)
	importBox:SetMaxLetters(65535)
	W.SetFont(importBox, "regular", 12)
	importBox:SetTextInsets(8, 8, 6, 6)
	importBox:SetTextColor(C.text[1], C.text[2], C.text[3])
	W.Panel(importBox, C.field, C.edge)
	importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	y = y - 158

	local armed = false
	local importButton
	importButton = W.Button(content, "Import", 140, 28, function()
		if not armed then
			armed = true
			importButton.label:SetText("Click again")
			NS:SetStatus("Importing overwrites the current profile.", "warning")
			return
		end
		armed = false
		importButton.label:SetText("Import")

		local applied, refused = NS:ImportSettings(importBox:GetText() or "")
		if refused < 0 then
			NS:SetStatus("That does not look like a NameplateSCT settings block.", "warning")
			return
		end

		NS:updateFilterTable(GetPath("filter") or "")
		NS:updateNPCFilterTable(GetPath("npcFilter") or "")
		NS:ResetFontPathCache()
		NS:RefreshScreenAnchors()
		NS:ApplyBlizzardFCT()
		NS:RefreshSettings()
		NS:SetStatus(("Imported %d settings, ignored %d."):format(applied, refused),
			refused > 0 and "warning" or "good")
	end)
	importButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

	y = y - 28 - 18

	return y
end

-- The search page is only a container; its rows are the live controls, added by
-- NS:SearchSettings as the query changes.
buildSearch = function(content)
	searchHint = W.Text(content, "Type to search every setting.", 0, -4, CONTENT_WIDTH, "regular", 13, C.dim)
	return 0
end

newPage("dashboard", "Dashboard", "Live counters, the usual causes when nothing draws, and the settings you change most.", "OVERVIEW").build = buildDashboard
newPage("general", "General", "Where numbers appear and which hits are counted.", "DISPLAY").build = buildGeneral
newPage("numbers", "Numbers", "Formatting, size and the filters that drop small hits.", "DISPLAY").build = buildNumbers
newPage("appearance", "Appearance", "Type, spell icons and colours.", "DISPLAY").build = buildAppearance
newPage("animations", "Animations", "Which animation each kind of hit uses.", "DISPLAY").build = buildAnimations
newPage("position", "Position", "Offsets, scatter and the two screen areas.", "DISPLAY").build = buildPosition
newPage("filters", "Filters", "Spell and NPC lists the addon should ignore.", "DATA").build = buildFilters
newPage("about", "About", "Version, client details and profile management.", "ABOUT").build = buildAbout
newPage("backup", "Backup", "Copy your settings, or paste a block back in.", "DATA").build = buildBackup
newPage("search", "Search", "Every setting that matches what you type in the box above.", "", true).build = buildSearch

local pageById = {}
for _, page in ipairs(pages) do pageById[page.id] = page end

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------
-- One live row per setting, created the first time it matches and then only moved and shown
-- or hidden. Typing cannot leak frames, and every result is the real control, not a copy.

local searchRows = {}
local pageBeforeSearch = "dashboard"

NS.settingsSearchRows = searchRows

local function searchRowFor(content, control)
	local height = ROW
	local row, widget

	if control.kind == "slider" then
		height = SLIDER_ROW
		row, widget = W.SliderRow(content, 0, control.label, control.min or 0, control.max or 100,
			control.step or 1, function() return GetPath(control.path) end, control.set,
			CONTENT_WIDTH, control.formatter, control.enabled)
	elseif control.kind == "select" then
		row, widget = W.SelectRow(content, 0, control.label, control.options or {},
			function() return GetPath(control.path) end, control.set, CONTENT_WIDTH, control.enabled)
	elseif control.kind == "hex" then
		height = SLIDER_ROW
		row, widget = W.ColourRow(content, 0, control.label,
			function() return GetPath(control.path) end, control.set, CONTENT_WIDTH,
			control.normalize, control.enabled)
	elseif control.kind == "text" then
		height = SLIDER_ROW
		row, widget = W.EditRow(content, 0, control.label,
			function() return GetPath(control.path) end, control.set, CONTENT_WIDTH, nil, control.enabled)
	else
		row, widget = W.ToggleRow(content, 0, control.label,
			function() return GetPath(control.path) end, control.set, CONTENT_WIDTH, nil, control.enabled)
	end

	track(widget)
	return { row = row, widget = widget, height = height }
end

local function matchesQuery(control, tokens)
	local text = (tostring(control.label or "") .. " " .. tostring(control.path or "")):lower()
	for _, token in ipairs(tokens) do
		if not text:find(token, 1, true) then return false end
	end
	return true
end

--- Show every setting matching a query. Returns the number of matches.
---@param query string?
---@return number
function NS:SearchSettings(query)
	if not frame or not frame.pages or not frame.pages.search then return 0 end

	local viewport = ensurePage("search")
	if not viewport or not viewport.content then return 0 end

	local content = viewport.content
	local tokens = {}
	for token in tostring(query or ""):lower():gmatch("%S+") do tokens[#tokens + 1] = token end

	for _, entry in pairs(searchRows) do entry.row:Hide() end

	local found, y = 0, 0
	if #tokens > 0 then
		for _, control in ipairs(NS.settingsControls or {}) do
			if matchesQuery(control, tokens) then
				local entry = searchRows[control.path]
				if not entry then
					entry = searchRowFor(content, control)
					searchRows[control.path] = entry
				end

				entry.row:ClearAllPoints()
				entry.row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
				entry.row:Show()
				if entry.widget.Refresh then entry.widget:Refresh() end
				y = y - entry.height
				found = found + 1
			end
		end
	end

	if searchHint then
		if found > 0 then
			searchHint:Hide()
		else
			searchHint:Show()
			searchHint:SetText(#tokens == 0 and "Type to search every setting."
				or "No setting matches that.")
		end
	end

	viewport:SetContentHeight(-y + 24)
	if viewport.ResetScroll then viewport:ResetScroll() end
	return found
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function createFrame()
	local created = CreateFrame("Frame", "NameplateSCTSettingsFrame", UIParent)
	created:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	created:SetPoint("CENTER")
	created:SetFrameStrata("DIALOG")
	created:SetToplevel(true)
	created:SetClampedToScreen(true)
	created:SetMovable(true)
	created:EnableMouse(true)

	-- The layout is designed at 1200x800. On a smaller screen the whole window scales down
	-- rather than running off the edge; on a larger one it stays at design size.
	local screenWidth = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0
	local screenHeight = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0
	local fit = 1
	if screenWidth > 0 and screenHeight > 0 then
		fit = math.min(1, (screenWidth - 60) / WINDOW_WIDTH, (screenHeight - 80) / WINDOW_HEIGHT)
		if fit < 0.6 then fit = 0.6 end
	end
	created:SetScale(fit)
	created.fitScale = fit
	created:RegisterForDrag("LeftButton")
	created:SetScript("OnDragStart", created.StartMoving)
	created:SetScript("OnDragStop", created.StopMovingOrSizing)
	created:Hide()
	created:SetScript("OnShow", function() NS:SetDashboardTicker(true) end)
	created:SetScript("OnHide", function()
		NS:SetDashboardTicker(false)
		if W.CloseSelect then W.CloseSelect() end
	end)
	W.Panel(created, C.window, C.edge)

	-- Title bar -------------------------------------------------------------
	local titleBar = CreateFrame("Frame", nil, created)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(HEADER_HEIGHT)
	W.Panel(titleBar, C.sidebar, nil)

	W.Image(titleBar, LOGO, 36, 36, 18, -16)

	local version = addonVersion()
	local subtitleText = clientLabel() .. "  ·  " .. sourceLabel() .. (version ~= "" and ("  ·  v" .. version) or "")
	W.Text(titleBar, "NameplateSCT", 66, -12, nil, "semibold", 19, C.bright)
	W.Text(titleBar, subtitleText, 66, -38, 500, "regular", 12, C.dim)

	local close = W.CloseButton(titleBar, function() created:Hide() end)
	close:SetPoint("RIGHT", titleBar, "RIGHT", -14, 0)

	-- Search lives in the title bar, where an application puts it.
	local searchBox = CreateFrame("EditBox", nil, titleBar)
	searchBox:SetSize(300, 26)
	searchBox:SetPoint("RIGHT", close, "LEFT", -16, 0)
	searchBox:SetAutoFocus(false)
	W.SetFont(searchBox, "regular", 13)
	searchBox:SetTextColor(C.text[1], C.text[2], C.text[3])
	searchBox:SetTextInsets(10, 10, 0, 0)
	searchBox:SetMaxLetters(64)
	W.Panel(searchBox, C.field, C.edge)
	created.searchBox = searchBox

	local searchPlaceholder = W.Text(titleBar, "Search settings...", nil, 0, 260, "regular", 13, C.dim)
	searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 11, 0)
	searchPlaceholder:SetJustifyV("MIDDLE")
	created.searchPlaceholder = searchPlaceholder

	local function updatePlaceholder()
		if (searchBox:GetText() or "") == "" then
			searchPlaceholder:Show()
		else
			searchPlaceholder:Hide()
		end
	end

	searchBox:SetScript("OnTextChanged", function(self)
		updatePlaceholder()
		local text = self:GetText() or ""
		if text ~= "" and selectedPageId ~= "search" then
			pageBeforeSearch = selectedPageId or "dashboard"
			created:SelectPage("search")
		end
		NS:SearchSettings(text)
	end)
	searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		updatePlaceholder()
		NS:SearchSettings("")
		if selectedPageId == "search" then
			created:SelectPage(pageBeforeSearch or "dashboard")
		end
	end)
	searchBox:SetScript("OnEditFocusGained", function() if searchBox._ring then searchBox._ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3]) end end)
	searchBox:SetScript("OnEditFocusLost", function() if searchBox._ring then searchBox._ring:SetVertexColor(C.edge[1], C.edge[2], C.edge[3]) end end)
	updatePlaceholder()

	local rule = titleBar:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(C.accent[1], C.accent[2], C.accent[3])
	rule:SetHeight(1)
	rule:SetAlpha(0.5)
	rule:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)

	-- Sidebar ---------------------------------------------------------------
	local sidebar = CreateFrame("Frame", nil, created)
	sidebar:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT)
	sidebar:SetPoint("BOTTOMLEFT", 1, 1)
	sidebar:SetWidth(SIDEBAR_WIDTH)
	W.Panel(sidebar, C.sidebar, nil)

	local sideRule = sidebar:CreateTexture(nil, "ARTWORK")
	sideRule:SetColorTexture(C.line[1], C.line[2], C.line[3])
	sideRule:SetWidth(1)
	sideRule:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
	sideRule:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)

	created.navButtons = {}
	local navY = -14
	local lastGroup
	for _, page in ipairs(pages) do
		if not page.hidden and page.group ~= "" and page.group ~= lastGroup then
			lastGroup = page.group
			W.Upper(sidebar, page.group, 14, navY, C.dim)
			navY = navY - 20
		end
		if not page.hidden then
			local button = W.NavButton(sidebar, page.title, SIDEBAR_WIDTH - 20, 32, function()
				created:SelectPage(page.id)
			end)
			button:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, navY)
			created.navButtons[page.id] = button
			navY = navY - 34
		end
	end

	local hint = W.Text(sidebar, "/nsct  ·  ESC to close", 14, 0, SIDEBAR_WIDTH - 28, "regular", 11, C.dim)
	hint:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 14, 28)

	if version ~= "" then
		local build = W.Text(sidebar, "v" .. version, 14, 0, SIDEBAR_WIDTH - 28, "regular", 11, C.disabledText)
		build:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 14, 12)
	end

	-- Page header: every page states what it is for.
	local contentHeader = CreateFrame("Frame", nil, created)
	contentHeader:SetPoint("TOPLEFT", created, "TOPLEFT", SIDEBAR_WIDTH + PAD_LEFT, -HEADER_HEIGHT - 12)
	contentHeader:SetPoint("TOPRIGHT", created, "TOPRIGHT", -PAD_RIGHT - 18, -HEADER_HEIGHT - 12)
	contentHeader:SetHeight(46)

	created.pageTitle = W.Text(contentHeader, "", 0, 0, CONTENT_WIDTH - 120, "semibold", 18, C.bright)
	created.pageDescription = W.Text(contentHeader, "", 0, -24, CONTENT_WIDTH - 110, "regular", 12, C.muted)

	local resetPage = W.Button(contentHeader, "Reset page", 96, 24, function()
		if NS.ResetPage then NS:ResetPage(selectedPageId) end
	end, "quiet")
	resetPage:SetPoint("TOPRIGHT", contentHeader, "TOPRIGHT", 0, 2)
	resetPage.tooltip = "Set every option on this page back to its default"
	created.resetPageButton = resetPage

	-- Footer: a status line. A control that rejects a value has to say so somewhere the
	-- player is already looking.
	local footer = CreateFrame("Frame", nil, created)
	footer:SetPoint("BOTTOMLEFT", created, "BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", created, "BOTTOMRIGHT", -1, 1)
	footer:SetHeight(FOOTER_HEIGHT)
	W.Panel(footer, C.sidebar, nil)

	local footerRule = footer:CreateTexture(nil, "ARTWORK")
	footerRule:SetColorTexture(C.line[1], C.line[2], C.line[3])
	footerRule:SetHeight(1)
	footerRule:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
	footerRule:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)

	created.statusText = W.Text(footer, "Changes apply immediately.", nil, 0, CONTENT_WIDTH, "regular", 12, C.muted)
	created.statusText:SetPoint("LEFT", footer, "LEFT", SIDEBAR_WIDTH + PAD_LEFT - 1, 0)
	created.statusText:SetJustifyV("MIDDLE")

	local footerInfo = W.Text(footer, clientLabel() .. "  ·  " .. sourceLabel(), nil, 0, 220, "regular", 12, C.dim)
	footerInfo:SetPoint("RIGHT", footer, "RIGHT", -PAD_RIGHT - 18, 0)
	footerInfo:SetJustifyH("RIGHT")

	-- Content ---------------------------------------------------------------
	created.pages = {}
	for _, page in ipairs(pages) do
		local viewport = W.ScrollPage(created, CONTENT_WIDTH + 12, VIEWPORT_HEIGHT)
		viewport:SetPoint("TOPLEFT", created, "TOPLEFT", SIDEBAR_WIDTH + PAD_LEFT, -CONTENT_TOP)
		viewport:Hide()
		created.pages[page.id] = viewport
	end

	created.SelectPage = function(self, id)
		ensurePage(id)
		for pageId, viewport in pairs(self.pages) do
			if pageId == id then viewport:Show() else viewport:Hide() end
		end
		for pageId, button in pairs(self.navButtons) do
			button:SetSelected(pageId == id)
		end

		local page = pageById[id]
		if page then
			self.pageTitle:SetText(page.title)
			self.pageDescription:SetText(page.description)
		end
		self.resetPageButton:Show()

		selectedPageId = id
		if self.pages[id] and self.pages[id].ResetScroll then self.pages[id]:ResetScroll() end
		if W.CloseSelect then W.CloseSelect() end
		NS:RefreshSettings()
	end

	return created
end

--------------------------------------------------------------------------------
-- Page construction, lazily and once
--------------------------------------------------------------------------------

function ensurePage(id)
	if not frame then return end
	local viewport = frame.pages[id]
	local page = pageById[id]
	if not viewport or not page or viewport.built then return viewport end

	buildingPage = id
	local used = page.build(viewport.content)
	buildingPage = nil
	viewport:SetContentHeight(-used + 24)
	viewport.built = true
	return viewport
end

--- One line of feedback in the footer. Every path that validates input reports here.
function NS:SetStatus(text, tone)
	if not frame or not frame.statusText then return end
	frame.statusText:SetText(text)
	local color = tone == "warning" and C.warningText or (tone == "good" and C.good) or C.muted
	frame.statusText:SetTextColor(color[1], color[2], color[3])
end

--- Put every setting owned by one page back to its default. The page a control belongs to
-- is recorded while that page is built, so this cannot drift from what is on screen.
function NS:ResetPage(id)
	if not id or not NS.defaults then return end

	local reset = 0
	refreshing = true
	for _, control in ipairs(NS.settingsControls) do
		if control.page == id then
			local value = defaultValue(control.path)
			if value ~= nil then
				control.set(value)
				reset = reset + 1
			end
		end
	end
	refreshing = false

	NS:RefreshSettings()
	NS:SetStatus(reset > 0 and ("Reset %d setting(s) on this page."):format(reset)
		or "This page has nothing to reset.", reset > 0 and "good" or nil)
end

function NS:RefreshSettings()
	for _, control in ipairs(refreshables) do
		control:Refresh()
	end
	for _, hook in ipairs(pageRefreshHooks) do
		hook()
	end
end

function NS:OpenDashboard()
	if not NS.db then return end

	if not frame then
		frame = createFrame()
		_G.NameplateSCTSettingsFrame = frame
		if UISpecialFrames then
			local listed = false
			for _, name in ipairs(UISpecialFrames) do
				if name == "NameplateSCTSettingsFrame" then listed = true end
			end
			if not listed then table.insert(UISpecialFrames, "NameplateSCTSettingsFrame") end
		end
	end

	if NS.db.profile and NS.db.profile.displayMode then
		NS:RefreshScreenAnchors()
	end

	frame:Show()
	if frame.Raise then frame:Raise() end
	frame:SelectPage(selectedPageId or "dashboard")
end

-- The dashboard reads live counters, so refresh it on a slow tick. The ticker is only
-- attached while the window is actually shown: a permanently running OnUpdate is pure
-- frame cost for a window that is almost always closed.
local ticker = CreateFrame("Frame")
local elapsed = 0

local function tick(_, delta)
	elapsed = elapsed + delta
	if elapsed < 0.25 then return end
	elapsed = 0
	if frame and selectedPageId == "dashboard" then
		NS:RefreshSettings()
	end
end

function NS:SetDashboardTicker(enabled)
	ticker:SetScript("OnUpdate", enabled and tick or nil)
end
