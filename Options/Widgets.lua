--------------------------------------------------------------------------------
-- NameplateSCT options: widget toolkit
--------------------------------------------------------------------------------
-- Visual language adapted from PlateSCT's "Ember" settings design: warm near-black
-- surfaces, a single gold accent, Source Sans 3 typography, 32px control rows and
-- 12px row padding. Deliberately self-contained (no AceGUI, no SetBackdrop, no
-- retail-only menu API) so the same code path runs on Era through Midnight.

local NS = _G.NameplateSCT
if not NS then return end

local W = {}
NS.W = W

local MEDIA = "Interface\\AddOns\\NameplateSCT\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Palette: sampled from this addon's own logo (logo.png), not from PlateSCT.
-- The artwork is a cool near-black plate with a white wordmark and a scorching
-- orange -> gold -> red SCT mark, so the surfaces stay neutral/cool and the single
-- accent is the logo orange, with the logo red reserved for danger states.
local C = {
	-- surfaces (cool near-black, sampled #12161D / #101318 / #0D1015)
	window = { 0.078, 0.090, 0.122, 1 },
	sidebar = { 0.063, 0.075, 0.094, 1 },
	drawer = { 0.051, 0.063, 0.082, 1 },
	edge = { 0.180, 0.208, 0.251, 1 },
	line = { 0.129, 0.153, 0.196, 1 },
	field = { 0.102, 0.125, 0.165, 1 },
	fieldHover = { 0.137, 0.169, 0.216, 1 },
	navActive = { 0.137, 0.169, 0.216, 1 },
	hover = { 0.098, 0.122, 0.157, 1 },
	card = { 0.090, 0.110, 0.141, 1 },

	-- brand (logo orange #FF8D0A, gold #FECF03, red #E72A2C)
	accent = { 1.000, 0.553, 0.039, 1 },
	accentHover = { 1.000, 0.655, 0.200, 1 },
	accentDown = { 0.851, 0.455, 0.000, 1 },
	onAccent = { 0.078, 0.063, 0.039, 1 },
	yellow = { 0.996, 0.812, 0.012, 1 },
	red = { 0.906, 0.165, 0.173, 1 },

	-- type (logo white #F4F8FC, neutral greys #D1D5DA / #A0A4A9)
	text = { 0.910, 0.925, 0.949 },
	bright = { 0.973, 0.984, 1.000 },
	navText = { 0.765, 0.792, 0.831 },
	muted = { 0.600, 0.631, 0.678 },
	dim = { 0.478, 0.510, 0.561 },
	disabledText = { 0.341, 0.376, 0.424 },

	-- states
	warning = { 0.165, 0.082, 0.071, 1 },
	warningText = { 1.000, 0.725, 0.659 },
	good = { 0.435, 0.816, 0.545 },
	switchOff = { 0.173, 0.204, 0.247, 1 },
	knobOn = { 0.090, 0.067, 0.039, 1 },
	knobOff = { 0.557, 0.588, 0.631, 1 },
	black = { 0, 0, 0, 1 },
}
W.C = C

local CJK = { koKR = true, zhCN = true, zhTW = true }

local function rgb(c)
	return c[1], c[2], c[3], c[4] or 1
end

function W.FontPath(role)
	local locale = GetLocale and GetLocale()
	if CJK[locale] then
		return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	end
	local files = {
		regular = "SourceSans3-Regular.ttf",
		medium = "SourceSans3-Medium.ttf",
		semibold = "SourceSans3-Semibold.ttf",
	}
	return MEDIA .. "Fonts\\" .. (files[role] or files.regular)
end

-- Touch each bundled font at load: the client streams a font on first use and text
-- laid out before that can stay blank.
do
	local loader = CreateFrame("Frame")
	loader:Hide()
	for _, file in ipairs({ "SourceSans3-Regular.ttf", "SourceSans3-Medium.ttf", "SourceSans3-Semibold.ttf" }) do
		local probe = loader:CreateFontString(nil, "ARTWORK")
		pcall(probe.SetFont, probe, MEDIA .. "Fonts\\" .. file, 13, "")
		probe:SetText("Aa")
	end
end

-- Fonts are always set on a region this addon owns. Never on a shared font object
-- (GameFontNormal, GameFontHighlight, ...) and never by assigning STANDARD_TEXT_FONT: those
-- are used by the whole client, so writing them repaints action bars, chat and tooltips.
-- The harness fails the build if such a write ever appears.
function W.SetFont(region, role, size, flags)
	region:SetFont(W.FontPath(role), size or 13, flags or "")
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

-- Two stacked fills: the larger one in the ring colour reads as a 1px border around
-- the inset fill. A single outlined rect would paint over the panel instead.
function W.Panel(frame, fillColor, ringColor)
	local inset = ringColor and 1 or 0

	if ringColor then
		local ring = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
		ring:SetAllPoints(frame)
		ring:SetTexture(WHITE)
		ring:SetVertexColor(rgb(ringColor))
		frame._ring = ring
	end

	local fill = frame:CreateTexture(nil, "BACKGROUND", nil, ringColor and 1 or 0)
	if inset > 0 then
		fill:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
		fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
	else
		fill:SetAllPoints(frame)
	end
	fill:SetTexture(WHITE)
	fill:SetVertexColor(rgb(fillColor or C.field))
	frame._fill = fill

	return frame
end

function W.Recolor(frame, color)
	if frame and frame._fill then frame._fill:SetVertexColor(rgb(color)) end
end

function W.Divider(parent, y, width)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(rgb(C.line))
	line:SetHeight(1)
	line:SetWidth(width)
	line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	return line
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

function W.Text(parent, text, x, y, width, role, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	W.SetFont(fs, role or "regular", size or 13)
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(rgb(color or C.text))
	fs:SetText(text)
	if width then
		fs:SetWidth(width)
		fs:SetWordWrap(true)
	end
	if x then
		fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	end
	return fs
end

function W.Title(parent, text, x, y)
	local fs = W.Text(parent, text, x, y, nil, "semibold", 18, C.bright)
	return fs
end

function W.Upper(parent, text, x, y, color)
	local fs = W.Text(parent, string.upper(text), x, y, nil, "semibold", 10, color or C.dim)
	return fs
end

-- Small caps section label with a rule beside it.
function W.Section(parent, text, y, width)
	local label = W.Upper(parent, text, 0, y, C.dim)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(rgb(C.line))
	rule:SetHeight(1)
	rule:SetPoint("LEFT", label, "RIGHT", 10, 0)
	rule:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	return label
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

local function PaintButtonState(button, color, textColor)
	W.Recolor(button, color)
	if button.label then button.label:SetTextColor(rgb(textColor or C.text)) end
end

function W.Button(parent, label, width, height, onClick, style)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height or 32)
	W.Panel(button, C.field, C.edge)

	local fs = button:CreateFontString(nil, "OVERLAY")
	W.SetFont(fs, "medium", 13)
	fs:SetPoint("CENTER", 0, 0)
	fs:SetText(label)
	fs:SetTextColor(rgb(C.text))
	button.label = fs

	if style == "accent" then
		PaintButtonState(button, C.accent, C.onAccent)
	elseif style == "quiet" then
		PaintButtonState(button, C.sidebar, C.muted)
		if button._ring then button._ring:SetVertexColor(rgb(C.line)) end
	end

	button:SetScript("OnEnter", function(self)
		PaintButtonState(self, style == "accent" and C.accentHover or C.fieldHover,
			style == "accent" and C.onAccent or C.bright)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		if style == "accent" then
			PaintButtonState(self, C.accent, C.onAccent)
		elseif style == "quiet" then
			PaintButtonState(self, C.sidebar, C.muted)
		else
			PaintButtonState(self, C.field, C.text)
		end
		GameTooltip:Hide()
	end)
	button:SetScript("OnMouseDown", function(self)
		PaintButtonState(self, style == "accent" and C.accentDown or C.line,
			style == "accent" and C.onAccent or C.bright)
	end)
	button:SetScript("OnClick", onClick or function() end)

	return button
end

function W.NavButton(parent, label, width, height, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height or 34)
	W.Panel(button, C.sidebar, nil)

	local bar = button:CreateTexture(nil, "ARTWORK")
	bar:SetColorTexture(rgb(C.accent))
	bar:SetWidth(2)
	bar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	bar:Hide()
	button.bar = bar

	local fs = button:CreateFontString(nil, "OVERLAY")
	W.SetFont(fs, "medium", 13)
	fs:SetPoint("LEFT", 14, 0)
	fs:SetText(label)
	fs:SetTextColor(rgb(C.navText))
	button.label = fs

	button:SetScript("OnEnter", function(self)
		if not self.selected then W.Recolor(self, C.hover); self.label:SetTextColor(rgb(C.bright)) end
	end)
	button:SetScript("OnLeave", function(self)
		if not self.selected then W.Recolor(self, C.sidebar); self.label:SetTextColor(rgb(C.navText)) end
	end)
	button:SetScript("OnClick", onClick or function() end)

	function button:SetSelected(selected)
		self.selected = selected
		W.Recolor(self, selected and C.navActive or C.sidebar)
		self.label:SetTextColor(rgb(selected and C.bright or C.navText))
		if selected then self.bar:Show() else self.bar:Hide() end
	end

	return button
end

function W.CloseButton(parent, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(28, 28)
	W.Panel(button, C.window, nil)
	local fs = button:CreateFontString(nil, "OVERLAY")
	W.SetFont(fs, "medium", 16)
	fs:SetPoint("CENTER", 0, -1)
	fs:SetText("×")
	fs:SetTextColor(rgb(C.muted))
	button:SetScript("OnEnter", function(self) W.Recolor(self, C.field); fs:SetTextColor(rgb(C.bright)) end)
	button:SetScript("OnLeave", function(self) W.Recolor(self, C.window); fs:SetTextColor(rgb(C.muted)) end)
	button:SetScript("OnClick", onClick)
	return button
end

--------------------------------------------------------------------------------
-- Selection menu: exactly one popup for the whole addon
--------------------------------------------------------------------------------
-- Selection rows open this menu instead of cycling one step per click, which is workable
-- for two values and unusable for a font list. One menu object and one click-catcher are
-- created for the whole window, so two menus can never appear: opening another selection
-- re-anchors and reuses the same frame. Picking a value, ESC, a click anywhere else, or
-- hiding the settings window closes it.

local MENU_ROW_HEIGHT = 26
local MENU_MAX_ROWS = 9
local MENU_PAD = 4

local menu, catcher
local menuRows = {}
local menuState = { options = {}, selected = nil, onPick = nil, anchor = nil, offset = 0 }

local function visibleMenuRows()
	return math.min(#menuState.options, MENU_MAX_ROWS)
end

local function hideMenu()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end
W.CloseSelect = hideMenu

local function renderMenu()
	if not menu then return end
	local first = menuState.offset + 1

	for index, row in ipairs(menuRows) do
		local option = menuState.options[first + index - 1]
		if option then
			row.option = option
			row.label:SetText(option.text or tostring(option.value))
			row.label:ClearAllPoints()
			row.label:SetPoint("LEFT", option.swatch and 32 or 12, 0)

			if option.swatch then
				local red, green, blue = NS.hexToRGB(option.swatch)
				row.swatch:SetVertexColor(red, green, blue)
				row.swatch:Show()
			else
				row.swatch:Hide()
			end

			if option.value == menuState.selected then row.mark:Show() else row.mark:Hide() end
			W.Recolor(row, C.window)
			row.label:SetTextColor(rgb(C.text))
			row:Show()
		else
			row.option = nil
			row:Hide()
		end
	end
end

local function ensureMenu()
	if menu then return end

	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", hideMenu)
	catcher:Hide()

	menu = CreateFrame("Frame", "NameplateSCTSelectMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(30)
	menu:SetClampedToScreen(true)
	menu:EnableMouseWheel(true)
	menu:Hide()
	W.Panel(menu, C.window, C.edge)

	-- Exposed for the harness: it asserts there is one menu and one catcher, ever.
	NS.selectMenu = menu
	NS.selectCatcher = catcher

	for index = 1, MENU_MAX_ROWS do
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(MENU_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 1, -MENU_PAD - (index - 1) * MENU_ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -1, -MENU_PAD - (index - 1) * MENU_ROW_HEIGHT)
		W.Panel(row, C.window, nil)

		local swatch = row:CreateTexture(nil, "ARTWORK")
		swatch:SetSize(12, 12)
		swatch:SetPoint("LEFT", 12, 0)
		swatch:SetTexture(WHITE)
		swatch:Hide()
		row.swatch = swatch

		local mark = row:CreateTexture(nil, "ARTWORK")
		mark:SetWidth(2)
		mark:SetPoint("TOPLEFT", 0, 0)
		mark:SetPoint("BOTTOMLEFT", 0, 0)
		mark:SetColorTexture(rgb(C.accent))
		mark:Hide()
		row.mark = mark

		local label = row:CreateFontString(nil, "OVERLAY")
		W.SetFont(label, "regular", 13)
		label:SetPoint("LEFT", 12, 0)
		label:SetPoint("RIGHT", -10, 0)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		label:SetTextColor(rgb(C.text))
		row.label = label

		row:SetScript("OnEnter", function(self)
			W.Recolor(self, C.fieldHover)
			self.label:SetTextColor(rgb(C.bright))
		end)
		row:SetScript("OnLeave", function(self)
			W.Recolor(self, C.window)
			self.label:SetTextColor(rgb(C.text))
		end)
		row:SetScript("OnClick", function(self)
			if not self.option then return end
			local pick = menuState.onPick
			local value = self.option.value
			hideMenu()
			if pick then pick(value) end
		end)
		menuRows[index] = row
	end

	-- Exposed for the harness: it proves a second selection reuses these rows.
	NS.selectMenuRows = menuRows

	menu:SetScript("OnMouseWheel", function(_, delta)
		local maximum = math.max(0, #menuState.options - MENU_MAX_ROWS)
		menuState.offset = math.max(0, math.min(maximum, menuState.offset - delta))
		renderMenu()
	end)
	menu:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
end

---@param anchor Frame
---@param options table
---@param selected any
---@param onPick function
function W.OpenSelect(anchor, options, selected, onPick)
	ensureMenu()
	menuState.options = options or {}
	menuState.selected = selected
	menuState.onPick = onPick
	menuState.anchor = anchor
	menuState.offset = 0

	for index, option in ipairs(menuState.options) do
		if option.value == selected then
			if index > MENU_MAX_ROWS then menuState.offset = index - MENU_MAX_ROWS end
			break
		end
	end

	local width = math.max(180, (anchor and anchor:GetWidth()) or 180)
	menu:SetSize(width, visibleMenuRows() * MENU_ROW_HEIGHT + MENU_PAD * 2)
	menu:ClearAllPoints()
	if anchor then menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4) end

	renderMenu()
	catcher:Show()
	menu:Show()
	if menu.Raise then menu:Raise() end
end

---@return boolean
function W.IsSelectOpen()
	return menu ~= nil and menu:IsShown()
end

--------------------------------------------------------------------------------
-- Row enablement
--------------------------------------------------------------------------------
-- A row whose parent option is off greys out and stops taking clicks, instead of quietly
-- writing a setting nothing reads.

local function refreshEnabledState(control)
	local predicate = control.enabledPredicate
	local enabled = (not predicate) or predicate() and true or false
	control:SetAlpha(enabled and 1 or 0.4)
	if control.Enable and control.Disable then
		if enabled then control:Enable() else control:Disable() end
	end
	control.isDisabled = not enabled
	return enabled
end
W.RefreshEnabled = refreshEnabledState

-- Background highlight for a settings row, so the whole line reads as one control.
local function rowHover(row)
	local fill = row:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(row)
	fill:SetColorTexture(rgb(C.hover))
	fill:SetAlpha(0.55)
	fill:Hide()
	row:EnableMouse(true)
	row:SetScript("OnEnter", function() fill:Show() end)
	row:SetScript("OnLeave", function() fill:Hide() end)

	-- A hairline under every row: on a 1200px surface the eye needs the separation.
	local rule = row:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetColorTexture(rgb(C.line))
	rule:SetAlpha(0.6)
	rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

	return fill
end

--------------------------------------------------------------------------------
-- Switch (toggle)
--------------------------------------------------------------------------------

function W.Switch(parent, get, set, tooltip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(44, 22)
	W.Panel(button, C.switchOff, C.edge)

	local knob = button:CreateTexture(nil, "ARTWORK")
	knob:SetSize(16, 16)
	knob:SetTexture(WHITE)
	knob:SetVertexColor(rgb(C.knobOff))
	button.knob = knob

	function button:Refresh()
		local on = get() and true or false
		self.on = on
		W.Recolor(self, on and C.accent or C.switchOff)
		self.knob:ClearAllPoints()
		self.knob:SetPoint(on and "RIGHT" or "LEFT", self, on and "RIGHT" or "LEFT", on and -3 or 3, 0)
		self.knob:SetVertexColor(rgb(on and C.knobOn or C.knobOff))
		refreshEnabledState(self)
	end

	button:SetScript("OnClick", function(self)
		if self.isDisabled then return end
		set(not (get() and true or false))
		self:Refresh()
	end)
	button:SetScript("OnEnter", function(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button.tooltip = tooltip
	return button
end

-- A labelled row with the switch on the right.
function W.ToggleRow(parent, y, label, get, set, width, tooltip, isEnabled)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, 44)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	rowHover(row)

	local fs = W.Text(row, label, 0, 0, width - 60, "medium", 14, C.text)
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", row, "LEFT", 0, 0)

	local switch = W.Switch(row, get, set, tooltip)
	switch:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	switch.enabledPredicate = isEnabled
	switch:Refresh()

	return row, switch
end

--------------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------------

function W.SliderRow(parent, y, label, minValue, maxValue, step, get, set, width, formatter, isEnabled)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, 52)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	rowHover(row)

	local fs = W.Text(row, label, 0, 0, width - 90, "medium", 14, C.text)
	fs:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 8)

	local valueText = W.Text(row, "", width - 70, 0, nil, "medium", 13, C.muted)
	valueText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, 9)
	valueText:SetJustifyH("RIGHT")

	local slider = CreateFrame("Slider", nil, row)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(width - 8, 12)
	slider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 6)
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	pcall(slider.SetObeyStepOnDrag, slider, true)

	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(slider)
	track:SetTexture(WHITE)
	track:SetVertexColor(rgb(C.field))

	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(10, 18)
	thumb:SetTexture(WHITE)
	thumb:SetVertexColor(rgb(C.accent))
	slider:SetThumbTexture(thumb)

	local function show(value)
		valueText:SetText(formatter and formatter(value) or tostring(value))
	end

	slider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value / step + 0.5) * step
		show(value)
		if slider.updating then return end
		slider.updating = true
		set(value)
		slider.updating = false
	end)

	function slider:Refresh()
		self.updating = true
		self:SetValue(get())
		self.updating = false
		show(get())
		refreshEnabledState(self)
	end

	slider.enabledPredicate = isEnabled
	slider:Refresh()
	return row, slider
end

--------------------------------------------------------------------------------
-- Select row (opens the shared menu above)
--------------------------------------------------------------------------------

function W.SelectRow(parent, y, label, options, get, set, width, isEnabled)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, 44)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	rowHover(row)

	do
		local labelText = W.Text(row, label, 0, 0, math.floor(width * 0.45), "medium", 14, C.text)
		labelText:ClearAllPoints()
		labelText:SetPoint("LEFT", row, "LEFT", 0, 0)
	end

	local button = CreateFrame("Button", nil, row)
	button:SetSize(math.floor(width * 0.52), 30)
	button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	W.Panel(button, C.field, C.edge)

	local valueText = button:CreateFontString(nil, "OVERLAY")
	W.SetFont(valueText, "medium", 13)
	valueText:SetPoint("LEFT", 10, 0)
	valueText:SetPoint("RIGHT", -24, 0)
	valueText:SetJustifyH("LEFT")
	valueText:SetWordWrap(false)
	valueText:SetTextColor(rgb(C.text))
	button.valueText = valueText

	local chevron = button:CreateTexture(nil, "OVERLAY")
	chevron:SetSize(10, 6)
	chevron:SetPoint("RIGHT", -8, 0)
	chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	chevron:SetVertexColor(rgb(C.muted))

	local function currentText()
		local value = get()
		for _, entry in ipairs(options) do
			if entry.value == value then return entry.text or tostring(value) end
		end
		return tostring(value)
	end

	function button:Refresh()
		valueText:SetText(currentText())
		refreshEnabledState(self)
	end

	button.enabledPredicate = isEnabled
	button:Refresh()

	button:SetScript("OnClick", function(self)
		if self.isDisabled then return end
		-- Clicking the row whose menu is already open closes it; anything else reuses the
		-- one menu and re-anchors it instead of opening a second popup.
		if menu and menu:IsShown() and menuState.anchor == self then
			hideMenu()
			return
		end
		W.OpenSelect(self, options, get(), function(value)
			set(value)
			self:Refresh()
		end)
	end)
	button:SetScript("OnEnter", function(self)
		if not self.isDisabled then W.Recolor(self, C.fieldHover) end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click to choose", 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		if not self.isDisabled then W.Recolor(self, C.field) end
		GameTooltip:Hide()
	end)
	return row, button
end

--------------------------------------------------------------------------------
-- Edit box
--------------------------------------------------------------------------------

function W.EditRow(parent, y, label, get, set, width, onCommit, isEnabled)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, 52)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	rowHover(row)

	local fs = W.Text(row, label, 0, 0, width, "medium", 14, C.text)
	fs:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 6)

	local box = CreateFrame("EditBox", nil, row)
	box:SetSize(width - 8, 28)
	box:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
	box:SetAutoFocus(false)
	W.SetFont(box, "regular", 13)
	box:SetTextColor(rgb(C.text))
	box:SetTextInsets(8, 8, 0, 0)
	box:SetMaxLetters(4096)
	W.Panel(box, C.field, C.edge)

	local function commit(value)
		if onCommit and not onCommit(value) then
			-- Invalid input: keep focus, flag the field red, leave the profile untouched.
			if box._ring then box._ring:SetVertexColor(rgb(C.red)) end
			return false
		end
		if box._ring then box._ring:SetVertexColor(rgb(C.edge)) end
		set(value)
		return true
	end

	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		if box._ring then box._ring:SetVertexColor(rgb(C.edge)) end
		self:SetText(get() or "")
	end)
	box:SetScript("OnEnterPressed", function(self)
		if commit(self:GetText() or "") then self:ClearFocus() end
	end)
	box:SetScript("OnEditFocusLost", function(self)
		if self:GetText() ~= (get() or "") then commit(self:GetText() or "") end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		if box._ring then box._ring:SetVertexColor(rgb(C.accent)) end
	end)

	function box:Refresh()
		self:SetText(get() or "")
		if self._ring then self._ring:SetVertexColor(rgb(C.edge)) end
		refreshEnabledState(self)
	end
	box.enabledPredicate = isEnabled
	box:Refresh()

	return row, box
end

--------------------------------------------------------------------------------
-- Colour row: the hex field plus a swatch that opens the preset palette
--------------------------------------------------------------------------------
-- The palette is the same single menu the other selectors use, so there is still exactly
-- one popup in the addon; picking a swatch writes the hex value directly.

local COLOUR_PRESETS = {
	{ value = "ffffff", text = "White", swatch = "ffffff" },
	{ value = "c0c0c0", text = "Silver", swatch = "c0c0c0" },
	{ value = "808080", text = "Grey", swatch = "808080" },
	{ value = "404040", text = "Dark grey", swatch = "404040" },
	{ value = "000000", text = "Black", swatch = "000000" },
	{ value = "e74c3c", text = "Crimson", swatch = "e74c3c" },
	{ value = "ff0000", text = "Red", swatch = "ff0000" },
	{ value = "ff8000", text = "Orange", swatch = "ff8000" },
	{ value = "ff8d0a", text = "NameplateSCT orange", swatch = "ff8d0a" },
	{ value = "f1c40f", text = "Gold", swatch = "f1c40f" },
	{ value = "ffff00", text = "Yellow", swatch = "ffff00" },
	{ value = "80ff00", text = "Lime", swatch = "80ff00" },
	{ value = "2ecc71", text = "Emerald", swatch = "2ecc71" },
	{ value = "00ff00", text = "Green", swatch = "00ff00" },
	{ value = "1abc9c", text = "Teal", swatch = "1abc9c" },
	{ value = "00ffff", text = "Cyan", swatch = "00ffff" },
	{ value = "0080ff", text = "Sky", swatch = "0080ff" },
	{ value = "0000ff", text = "Blue", swatch = "0000ff" },
	{ value = "9b59b6", text = "Amethyst", swatch = "9b59b6" },
	{ value = "8000ff", text = "Purple", swatch = "8000ff" },
	{ value = "ff00ff", text = "Magenta", swatch = "ff00ff" },
	{ value = "ff0080", text = "Pink", swatch = "ff0080" },
	{ value = "c69c6d", text = "Tan", swatch = "c69c6d" },
	{ value = "8b4513", text = "Brown", swatch = "8b4513" },
}
W.COLOUR_PRESETS = COLOUR_PRESETS

function W.ColourRow(parent, y, label, get, set, width, onCommit, isEnabled)
	local row, box = W.EditRow(parent, y, label, get, set, width, onCommit, isEnabled)

	local swatch = CreateFrame("Button", nil, row)
	swatch:SetSize(22, 22)
	swatch:SetPoint("RIGHT", row, "RIGHT", -2, 9)
	W.Panel(swatch, C.field, C.edge)

	local fill = swatch:CreateTexture(nil, "ARTWORK")
	fill:SetAllPoints(swatch)
	fill:SetTexture(WHITE)

	box:SetWidth(width - 36)

	local function paint()
		local hex = tostring(get() or "ffffff"):gsub("#", "")
		local red, green, blue = NS.hexToRGB(hex)
		fill:SetVertexColor(red, green, blue)
	end

	function swatch:Refresh()
		paint()
		refreshEnabledState(self)
	end

	swatch:SetScript("OnClick", function(self)
		if self.isDisabled then return end
		W.OpenSelect(self, COLOUR_PRESETS, tostring(get() or ""):gsub("#", ""):lower(),
			function(value)
				set(value)
				paint()
				if box.Refresh then box:Refresh() end
			end)
	end)
	swatch:SetScript("OnEnter", function(self)
		W.Recolor(self, C.fieldHover)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Pick a colour, or type a hex value below", 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	swatch:SetScript("OnLeave", function(self)
		W.Recolor(self, C.field)
		GameTooltip:Hide()
	end)

	paint()
	swatch:Refresh()
	return row, box, swatch
end

--------------------------------------------------------------------------------
-- Image
--------------------------------------------------------------------------------

function W.Image(parent, path, width, height, x, y)
	local texture = parent:CreateTexture(nil, "ARTWORK")
	texture:SetSize(width, height)
	if x then texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
	texture:SetTexture(path)
	texture:SetTexCoord(0, 1, 0, 1)
	return texture
end

--------------------------------------------------------------------------------
-- Scrolling page
--------------------------------------------------------------------------------
-- The settings surface outgrew one screen, so every page scrolls. The wheel drives it
-- and a slim gold thumb reports the position; no Blizzard scroll template, so the page
-- looks the same on every client.

function W.ScrollPage(parent, width, height)
	local viewport = CreateFrame("Frame", nil, parent)
	viewport:SetSize(width, height)
	viewport:SetClampedToScreen(false)
	-- Children draw outside their parent unless the frame clips them, so a scrolled page
	-- would spill rows past the bottom of the window. Clipping is what makes the viewport a
	-- viewport.
	if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end

	local content = CreateFrame("Frame", nil, viewport)
	content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
	content:SetSize(width - 12, 1)

	local state = { offset = 0, contentHeight = 0 }

	local track = viewport:CreateTexture(nil, "BACKGROUND")
	track:SetWidth(4)
	track:SetColorTexture(rgb(C.field))
	track:SetAlpha(0.9)
	track:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, 0)
	track:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", 0, 0)

	local thumb = viewport:CreateTexture(nil, "ARTWORK")
	thumb:SetWidth(4)
	thumb:SetColorTexture(rgb(C.accent))
	thumb:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, 0)
	thumb:Hide()

	local function clamp()
		local maximum = math.max(0, state.contentHeight - height)
		if state.offset < 0 then state.offset = 0 end
		if state.offset > maximum then state.offset = maximum end
		return maximum
	end

	local function apply()
		local maximum = clamp()
		content:ClearAllPoints()
		content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, state.offset)

		if maximum <= 0 or state.contentHeight <= 0 then
			thumb:Hide()
			return
		end

		local thumbHeight = math.max(32, height * (height / state.contentHeight))
		local travel = height - thumbHeight
		local startY = -travel * (state.offset / maximum)

		thumb:Show()
		thumb:SetHeight(thumbHeight)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, startY)
	end

	viewport:EnableMouseWheel(true)
	viewport:SetScript("OnMouseWheel", function(_, delta)
		-- Positive delta is a wheel-up notch, which scrolls toward the top of the page.
		state.offset = state.offset - (delta or 0) * 60
		apply()
	end)

	function viewport:SetContentHeight(total)
		state.contentHeight = math.max(0, total)
		apply()
	end

	function viewport:ResetScroll()
		state.offset = 0
		apply()
	end

	viewport.content = content
	return viewport
end
