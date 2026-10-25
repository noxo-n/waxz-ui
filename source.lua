--// PinkUI - minimalist pink / black / white gradient UI library (Linoria-inspired)
--// ModuleScript -> put it in ReplicatedStorage and name it "PinkUI"
--//
--// Features: tween drag, corner resize, RShift toggle, blur + snow backdrop, two-column tabs,
--// toggles, sliders, buttons, dropdowns (single / multi), HSV + hex color picker, gradient picker,
--// keybinds, textboxes, labels, notifications, FULL live theming (presets + per-color pickers), unload.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- THEMES
----------------------------------------------------------------
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local DEFAULT_THEME = {
	Accent = rgb(255, 140, 190),        -- gradient start (pink)
	Accent2 = rgb(255, 255, 255),       -- gradient end (white)
	Background = rgb(8, 8, 10),         -- window gradient start
	BackgroundEnd = rgb(78, 30, 56),    -- window gradient end
	Panel = rgb(20, 17, 21),            -- group boxes
	Field = rgb(28, 24, 28),            -- buttons, sliders, textboxes, dropdowns
	Outline = rgb(80, 62, 74),          -- borders
	Text = rgb(228, 222, 226),          -- main text
	Muted = rgb(160, 150, 158),         -- secondary text
	Highlight = rgb(255, 182, 213),     -- slider values, keybind text
}

local function copyTable(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local PRESETS = {
	Pink = copyTable(DEFAULT_THEME),
	Ocean = {
		Accent = rgb(90, 170, 255), Accent2 = rgb(255, 255, 255),
		Background = rgb(6, 8, 12), BackgroundEnd = rgb(20, 40, 78),
		Panel = rgb(15, 19, 26), Field = rgb(22, 27, 36), Outline = rgb(60, 75, 95),
		Text = rgb(225, 230, 238), Muted = rgb(150, 160, 175), Highlight = rgb(170, 210, 255),
	},
	Mint = {
		Accent = rgb(110, 240, 180), Accent2 = rgb(255, 255, 255),
		Background = rgb(6, 10, 8), BackgroundEnd = rgb(20, 70, 50),
		Panel = rgb(15, 22, 19), Field = rgb(22, 31, 27), Outline = rgb(60, 90, 78),
		Text = rgb(225, 238, 230), Muted = rgb(150, 170, 160), Highlight = rgb(180, 255, 220),
	},
	Violet = {
		Accent = rgb(170, 120, 255), Accent2 = rgb(255, 200, 240),
		Background = rgb(9, 7, 12), BackgroundEnd = rgb(50, 25, 90),
		Panel = rgb(20, 16, 26), Field = rgb(28, 23, 36), Outline = rgb(80, 65, 100),
		Text = rgb(232, 225, 240), Muted = rgb(160, 150, 172), Highlight = rgb(210, 190, 255),
	},
	Crimson = {
		Accent = rgb(255, 80, 100), Accent2 = rgb(255, 200, 200),
		Background = rgb(10, 6, 7), BackgroundEnd = rgb(90, 20, 30),
		Panel = rgb(22, 15, 16), Field = rgb(31, 22, 23), Outline = rgb(95, 55, 60),
		Text = rgb(240, 225, 226), Muted = rgb(170, 150, 152), Highlight = rgb(255, 170, 180),
	},
	Mono = {
		Accent = rgb(255, 255, 255), Accent2 = rgb(150, 150, 150),
		Background = rgb(8, 8, 8), BackgroundEnd = rgb(50, 50, 52),
		Panel = rgb(18, 18, 18), Field = rgb(26, 26, 26), Outline = rgb(70, 70, 72),
		Text = rgb(235, 235, 235), Muted = rgb(150, 150, 150), Highlight = rgb(220, 220, 220),
	},
}

local THEME_KEYS = {
	"Accent", "Accent2", "Background", "BackgroundEnd",
	"Panel", "Field", "Outline", "Text", "Muted", "Highlight",
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local Library = {
	Options = {},                 -- Library.Options["Id"].Value
	Theme = copyTable(DEFAULT_THEME),
	Defaults = DEFAULT_THEME,
	Presets = PRESETS,            -- add your own: Library.Presets.MyTheme = { ... }
	Open = false,
	Snow = true,
	Blur = true,
	SpinMult = 1,                 -- speed multiplier of the spinning border gradient
	ToggleKey = Enum.KeyCode.RightShift,
	Window = nil,
	_ui = nil,
	_keybinds = {},
	_listening = nil,
	_unloadCallbacks = {},
}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)
local FONT = Enum.Font.Code
local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function tween(inst, info, props)
	if type(info) == "number" then
		info = TweenInfo.new(info, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

local function round(n, decimals)
	local m = 10 ^ (decimals or 0)
	return math.floor(n * m + 0.5) / m
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function measure(text, width)
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, 13, FONT, Vector2.new(width, 1000))
	end)
	return ok and v or Vector2.new(width, 14)
end

-- bound properties: re-applied whenever the theme changes.
-- getter is either a theme key ("Panel") or a function returning a Color3.
local bound = {}
local function bind(inst, prop, getter)
	if type(getter) == "string" then
		local key = getter
		getter = function() return Library.Theme[key] end
	end
	inst[prop] = getter()
	table.insert(bound, { inst, prop, getter })
	return inst
end

-- themed gradients
local themed = {}
local function kp(t, c) return ColorSequenceKeypoint.new(t, c) end

local function themeSeq(kind)
	local th = Library.Theme
	if kind == "loop" then
		return ColorSequence.new({ kp(0, th.Accent), kp(0.5, th.Accent2), kp(1, th.Accent) })
	elseif kind == "bg" then
		return ColorSequence.new({
			kp(0, th.Background),
			kp(0.6, th.Background:Lerp(th.BackgroundEnd, 0.3)),
			kp(1, th.BackgroundEnd),
		})
	end
	return ColorSequence.new(th.Accent, th.Accent2)
end

local function themedGradient(parent, kind, rotation)
	local g = new("UIGradient", { Color = themeSeq(kind), Rotation = rotation or 0 }, parent)
	table.insert(themed, { g, kind })
	return g
end

local function textLabel(parent, props, colorKey)
	local p = { BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextXAlignment = LEFT }
	for k, v in pairs(props) do p[k] = v end
	local l = new("TextLabel", p, parent)
	if colorKey ~= false then bind(l, "TextColor3", colorKey or "Text") end
	return l
end

local function outline(parent, thickness, transparency)
	local s = new("UIStroke", { Thickness = thickness or 1, Transparency = transparency or 0 }, parent)
	bind(s, "Color", "Outline")
	return s
end

function Library:SetTheme(theme)
	if type(theme) == "string" then theme = self.Presets[theme] end
	if type(theme) ~= "table" then return end
	for k, v in pairs(theme) do
		self.Theme[k] = v
	end
	for i = #bound, 1, -1 do
		local e = bound[i]
		if e[1]:IsDescendantOf(game) then
			e[1][e[2]] = e[3]()
		else
			table.remove(bound, i)
		end
	end
	for i = #themed, 1, -1 do
		local e = themed[i]
		if e[1]:IsDescendantOf(game) then
			e[1].Color = themeSeq(e[2])
		else
			table.remove(themed, i)
		end
	end
end

-- returns a table you can paste into CreateWindow({ Theme = ... })
function Library:ExportTheme()
	local lines = { "Theme = {" }
	for _, key in ipairs(THEME_KEYS) do
		local c = self.Theme[key]
		table.insert(lines, string.format("\t%s = Color3.fromRGB(%d, %d, %d),", key,
			math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)))
	end
	table.insert(lines, "},")
	return table.concat(lines, "\n")
end

function Library:OnUnload(fn)
	table.insert(self._unloadCallbacks, fn)
end

-- every interactive element registers an option here
local optionCounter = 0
local function makeOption(id, typ, value, opts)
	if not id then
		optionCounter += 1
		id = "option" .. optionCounter
	end
	local o = { Id = id, Type = typ, Value = value, _changed = {} }
	function o:OnChanged(fn)
		table.insert(self._changed, fn)
	end
	function o:_fire()
		if opts.Callback then task.spawn(opts.Callback, self.Value) end
		for _, fn in ipairs(self._changed) do
			task.spawn(fn, self.Value)
		end
	end
	Library.Options[id] = o
	return o
end

local function nextOrder(group)
	group._order += 1
	return group._order
end

----------------------------------------------------------------
-- GROUP (element container)
----------------------------------------------------------------
local Group = {}
Group.__index = Group

function Group:AddLabel(text, opts)
	opts = opts or {}
	local lbl = textLabel(self.Container, {
		Size = UDim2.new(1, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = nextOrder(self),
	}, opts.Color and false or "Muted")
	if opts.Color then lbl.TextColor3 = opts.Color end

	local o = { Instance = lbl }
	function o:SetText(t) lbl.Text = t end
	return o
end

function Group:AddDivider()
	local line = new("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	themedGradient(line, "loop")
end

function Group:AddToggle(id, opts)
	opts = opts or {}
	local o = makeOption(id, "Toggle", opts.Default == true, opts)

	local row = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	local box = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BorderSizePixel = 0,
	}, row)
	bind(box, "BackgroundColor3", "Field")
	outline(box)
	local fill = new("Frame", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = o.Value and 0 or 1,
		BorderSizePixel = 0,
	}, box)
	themedGradient(fill, "pair", 45)
	local label = textLabel(row, {
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -22, 1, 0),
		Text = opts.Text or "Toggle",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	function o:Set(v, silent)
		v = v and true or false
		if self.Value == v then return end
		self.Value = v
		tween(fill, 0.15, { BackgroundTransparency = v and 0 or 1 })
		if not silent then self:_fire() end
	end
	function o:SetText(t) label.Text = t end

	row.MouseButton1Click:Connect(function()
		o:Set(not o.Value)
	end)
	return o
end

function Group:AddSlider(id, opts)
	opts = opts or {}
	local min, max = opts.Min or 0, opts.Max or 100
	local decimals = opts.Decimals or 0
	local suffix = opts.Suffix or ""
	local o = makeOption(id, "Slider", math.clamp(opts.Default or min, min, max), opts)

	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	textLabel(holder, {
		Size = UDim2.new(1, -50, 0, 14),
		Text = opts.Text or "Slider",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local valueLabel = textLabel(holder, {
		Size = UDim2.new(1, 0, 0, 14),
		Text = tostring(o.Value) .. suffix,
		TextXAlignment = RIGHT,
	}, "Highlight")
	local bar = new("TextButton", {
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 0, 10),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, holder)
	bind(bar, "BackgroundColor3", "Field")
	outline(bar)
	local fill = new("Frame", {
		Size = UDim2.fromScale((o.Value - min) / (max - min), 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, bar)
	themedGradient(fill, "pair")

	function o:Set(v, silent)
		v = math.clamp(round(v, decimals), min, max)
		self.Value = v
		valueLabel.Text = tostring(v) .. suffix
		tween(fill, 0.08, { Size = UDim2.fromScale((v - min) / (max - min), 1) })
		if not silent then self:_fire() end
	end

	local sliding = false
	local function fromInput(input)
		local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		o:Set(min + (max - min) * alpha)
	end
	bar.InputBegan:Connect(function(input)
		if isPress(input) then
			sliding = true
			fromInput(input)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if isPress(input) then sliding = false end
	end)
	return o
end

function Group:AddButton(opts)
	opts = opts or {}
	local hovered = false
	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 22),
		BorderSizePixel = 0,
		Text = opts.Text or "Button",
		Font = FONT,
		TextSize = 13,
		AutoButtonColor = false,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	bind(btn, "BackgroundColor3", "Field")
	bind(btn, "TextColor3", "Text")
	local stroke = new("UIStroke", { Thickness = 1 }, btn)
	bind(stroke, "Color", function()
		return hovered and Library.Theme.Accent or Library.Theme.Outline
	end)
	local flash = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, btn)
	themedGradient(flash, "pair", 45)

	btn.MouseEnter:Connect(function()
		hovered = true
		tween(stroke, 0.15, { Color = Library.Theme.Accent })
	end)
	btn.MouseLeave:Connect(function()
		hovered = false
		tween(stroke, 0.15, { Color = Library.Theme.Outline })
	end)
	btn.MouseButton1Click:Connect(function()
		flash.BackgroundTransparency = 0.55
		tween(flash, 0.35, { BackgroundTransparency = 1 })
		if opts.Callback then task.spawn(opts.Callback) end
	end)

	local o = { Instance = btn }
	function o:SetText(t) btn.Text = t end
	return o
end

function Group:AddDropdown(id, opts)
	opts = opts or {}
	local multi = opts.Multi == true
	local values = opts.Values or {}

	local initial
	if multi then
		initial = {}
		if type(opts.Default) == "table" then
			for _, name in ipairs(opts.Default) do initial[name] = true end
		end
	else
		initial = opts.Default
		if type(initial) == "number" then initial = values[initial] end
	end
	local o = makeOption(id, "Dropdown", initial, opts)

	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, holder)

	if opts.Text then
		textLabel(holder, {
			Size = UDim2.new(1, 0, 0, 14),
			Text = opts.Text,
			LayoutOrder = 1,
		})
	end

	local header = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 20),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 2,
	}, holder)
	bind(header, "BackgroundColor3", "Field")
	outline(header)
	local headerText = textLabel(header, {
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local arrow = textLabel(header, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.fromOffset(10, 20),
		Text = "v",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, "Muted")

	local list = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = 3,
	}, holder)
	bind(list, "BackgroundColor3", "Field")
	outline(list)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local items = {}

	local function isSelected(name)
		if multi then return o.Value[name] == true end
		return o.Value == name
	end

	local function displayText()
		if multi then
			local names = {}
			for _, v in ipairs(values) do
				if o.Value[v] then table.insert(names, v) end
			end
			return #names > 0 and table.concat(names, ", ") or "None"
		end
		return o.Value ~= nil and tostring(o.Value) or "None"
	end

	local function itemColor(name)
		return isSelected(name) and Library.Theme.Text or Library.Theme.Muted
	end

	local function refresh()
		headerText.Text = displayText()
		for name, item in pairs(items) do
			item.marker.Visible = isSelected(name)
			item.label.TextColor3 = itemColor(name)
		end
	end

	local function setListOpen(state)
		list.Visible = state
		arrow.Text = state and "^" or "v"
	end

	local function rebuild()
		for _, item in pairs(items) do item.button:Destroy() end
		table.clear(items)
		for i, name in ipairs(values) do
			local button = new("TextButton", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = i,
			}, list)
			local marker = new("Frame", {
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(0, 2, 1, -4),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Visible = false,
			}, button)
			themedGradient(marker, "pair", 90)
			local label = textLabel(button, {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -10, 1, 0),
				Text = tostring(name),
			}, false)
			bind(label, "TextColor3", function() return itemColor(name) end)
			items[name] = { button = button, marker = marker, label = label }

			button.MouseButton1Click:Connect(function()
				if multi then
					if o.Value[name] then o.Value[name] = nil else o.Value[name] = true end
				else
					o.Value = name
					setListOpen(false)
				end
				refresh()
				o:_fire()
			end)
		end
	end

	header.MouseButton1Click:Connect(function()
		setListOpen(not list.Visible)
	end)

	function o:Set(v, silent)
		if multi then
			local set = {}
			if type(v) == "table" then
				if v[1] ~= nil then
					for _, name in ipairs(v) do set[name] = true end
				else
					for name, on in pairs(v) do if on then set[name] = true end end
				end
			end
			self.Value = set
		else
			self.Value = v
		end
		refresh()
		if not silent then self:_fire() end
	end

	function o:SetValues(newValues)
		values = newValues
		if multi then
			for name in pairs(self.Value) do
				if not table.find(values, name) then self.Value[name] = nil end
			end
		elseif not table.find(values, self.Value) then
			self.Value = values[1]
		end
		rebuild()
		refresh()
	end

	rebuild()
	refresh()
	return o
end

function Group:AddColorPicker(id, opts)
	opts = opts or {}
	local o = makeOption(id, "ColorPicker", opts.Default or WHITE, opts)

	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	textLabel(row, {
		Size = UDim2.new(1, -40, 1, 0),
		Text = opts.Text or "Color",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local swatch = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(30, 14),
		BackgroundColor3 = o.Value,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, row)
	outline(swatch)

	function o:Set(c, silent)
		self.Value = c
		swatch.BackgroundColor3 = c
		if not silent then self:_fire() end
	end

	local window = self.Window
	swatch.MouseButton1Click:Connect(function()
		window._openPicker(opts.Text or "color", o.Value, function(c) o:Set(c) end)
	end)
	return o
end

function Group:AddGradientPicker(id, opts)
	opts = opts or {}
	local d = opts.Default or {}
	local a = d[1] or Library.Theme.Accent
	local b = d[2] or Library.Theme.Accent2
	local o = makeOption(id, "GradientPicker", { A = a, B = b }, {})

	-- gradient callbacks receive (colorA, colorB)
	function o:_fire()
		if opts.Callback then task.spawn(opts.Callback, self.Value.A, self.Value.B) end
		for _, fn in ipairs(self._changed) do
			task.spawn(fn, self.Value.A, self.Value.B)
		end
	end

	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	textLabel(row, {
		Size = UDim2.new(1, -100, 1, 0),
		Text = opts.Text or "Gradient",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local function makeSwatch(x, color)
		local sw = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, x, 0.5, 0),
			Size = UDim2.fromOffset(22, 14),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
		}, row)
		outline(sw)
		return sw
	end
	local swA = makeSwatch(-74, a)
	local strip = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -26, 0.5, 0),
		Size = UDim2.fromOffset(44, 14),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, row)
	outline(strip)
	local stripGrad = new("UIGradient", { Color = ColorSequence.new(a, b) }, strip)
	local swB = makeSwatch(0, b)

	function o:Set(ca, cb, silent)
		self.Value.A, self.Value.B = ca, cb
		swA.BackgroundColor3 = ca
		swB.BackgroundColor3 = cb
		stripGrad.Color = ColorSequence.new(ca, cb)
		if not silent then self:_fire() end
	end

	local window = self.Window
	local text = opts.Text or "gradient"
	swA.MouseButton1Click:Connect(function()
		window._openPicker(text .. " (start)", o.Value.A, function(c) o:Set(c, o.Value.B) end)
	end)
	swB.MouseButton1Click:Connect(function()
		window._openPicker(text .. " (end)", o.Value.B, function(c) o:Set(o.Value.A, c) end)
	end)
	return o
end

function Group:AddKeybind(id, opts)
	opts = opts or {}
	local mode = opts.Mode or "Press" -- "Press" | "Hold" | "Toggle"
	local o = makeOption(id, "Keybind", opts.Default, {})
	o.State = false

	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	textLabel(row, {
		Size = UDim2.new(1, -70, 1, 0),
		Text = opts.Text or "Keybind",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		Text = "",
		Font = FONT,
		TextSize = 12,
		AutoButtonColor = false,
	}, row)
	bind(btn, "BackgroundColor3", "Field")
	bind(btn, "TextColor3", "Highlight")
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, btn)
	outline(btn)

	local function keyName()
		return o.Value and o.Value.Name or "None"
	end
	btn.Text = keyName()

	function o:_cancel() btn.Text = keyName() end

	function o:Set(key, silent)
		self.Value = key
		btn.Text = keyName()
		if not silent then
			self:_fire()
			if opts.ChangedCallback then task.spawn(opts.ChangedCallback, key) end
		end
	end

	function o:_press()
		if mode == "Toggle" then
			self.State = not self.State
			if opts.Callback then task.spawn(opts.Callback, self.State) end
		elseif mode == "Hold" then
			self.State = true
			if opts.Callback then task.spawn(opts.Callback, true) end
		elseif opts.Callback then
			task.spawn(opts.Callback, true)
		end
	end

	function o:_release()
		if mode == "Hold" then
			self.State = false
			if opts.Callback then task.spawn(opts.Callback, false) end
		end
	end

	btn.MouseButton1Click:Connect(function()
		if Library._listening and Library._listening ~= o then
			Library._listening:_cancel()
		end
		Library._listening = o
		btn.Text = "..."
	end)

	table.insert(Library._keybinds, o)
	return o
end

function Group:AddTextbox(id, opts)
	opts = opts or {}
	local o = makeOption(id, "Textbox", opts.Default or "", opts)

	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	}, self.Container)
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	if opts.Text then
		textLabel(holder, {
			Size = UDim2.new(1, 0, 0, 14),
			Text = opts.Text,
			LayoutOrder = 1,
		})
	end
	local focused = false
	local box = new("TextBox", {
		Size = UDim2.new(1, 0, 0, 20),
		BorderSizePixel = 0,
		Text = tostring(o.Value),
		PlaceholderText = opts.Placeholder or "",
		Font = FONT,
		TextSize = 13,
		TextXAlignment = LEFT,
		ClearTextOnFocus = false,
		LayoutOrder = 2,
	}, holder)
	bind(box, "BackgroundColor3", "Field")
	bind(box, "TextColor3", "Text")
	bind(box, "PlaceholderColor3", "Muted")
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, box)
	local stroke = new("UIStroke", { Thickness = 1 }, box)
	bind(stroke, "Color", function()
		return focused and Library.Theme.Accent or Library.Theme.Outline
	end)

	box.Focused:Connect(function()
		focused = true
		tween(stroke, 0.15, { Color = Library.Theme.Accent })
	end)
	box.FocusLost:Connect(function()
		focused = false
		tween(stroke, 0.15, { Color = Library.Theme.Outline })
		if opts.Numeric then
			local n = tonumber(box.Text)
			if n then
				o.Value = n
			else
				box.Text = tostring(o.Value)
				return
			end
		else
			o.Value = box.Text
		end
		o:_fire()
	end)

	function o:Set(v, silent)
		self.Value = v
		box.Text = tostring(v)
		if not silent then self:_fire() end
	end
	return o
end

----------------------------------------------------------------
-- TAB
----------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

function Tab:AddGroup(name, side)
	if side ~= "Left" and side ~= "Right" then
		side = (self._count.Left <= self._count.Right) and "Left" or "Right"
	end
	self._count[side] += 1

	local frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = self._count[side],
	}, self.Columns[side])
	bind(frame, "BackgroundColor3", "Panel")
	outline(frame, 1, 0.3)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, frame)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	local label = textLabel(frame, {
		Size = UDim2.new(1, 0, 0, 14),
		Text = name,
		TextColor3 = WHITE,
		LayoutOrder = -1,
	}, false)
	themedGradient(label, "pair")

	return setmetatable({
		Container = frame,
		Window = self.Window,
		Tab = self,
		_order = 0,
	}, Group)
end

function Tab:AddLeftGroup(name) return self:AddGroup(name, "Left") end
function Tab:AddRightGroup(name) return self:AddGroup(name, "Right") end

----------------------------------------------------------------
-- NOTIFICATIONS
----------------------------------------------------------------
function Library:Notify(text, duration)
	local ui = self._ui
	if not ui then return end
	duration = duration or 4

	local textSize = measure(text, 212)
	local height = math.max(28, textSize.Y + 18)

	local wrapper = new("Frame", {
		Size = UDim2.fromOffset(240, height),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, ui.notifyList)
	local inner = new("Frame", {
		Position = UDim2.new(1, 1, 0, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, wrapper)
	bind(inner, "BackgroundColor3", "Panel")
	local stroke = new("UIStroke", { Color = WHITE, Thickness = 1 }, inner)
	themedGradient(stroke, "loop")
	local bar = new("Frame", {
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, inner)
	themedGradient(bar, "pair", 90)
	textLabel(inner, {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -16, 1, -3),
		Text = text,
		TextWrapped = true,
	})
	local progress = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, inner)
	themedGradient(progress, "pair")

	tween(inner, 0.25, { Position = UDim2.new(0, 1, 0, 1) })
	TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.new(0, 0, 0, 2),
	}):Play()

	task.delay(duration, function()
		if not wrapper.Parent then return end
		local out = tween(inner, 0.25, { Position = UDim2.new(1, 1, 0, 1) })
		out.Completed:Connect(function()
			if not wrapper.Parent then return end
			local collapse = tween(wrapper, 0.15, { Size = UDim2.fromOffset(240, 0) })
			collapse.Completed:Connect(function()
				if wrapper.Parent then wrapper:Destroy() end
			end)
		end)
	end)
end

----------------------------------------------------------------
-- OPEN / CLOSE / BACKDROP
----------------------------------------------------------------
function Library:RefreshBackdrop()
	local ui = self._ui
	if not ui then return end
	tween(ui.blur, 0.25, { Size = (self.Open and self.Blur) and 22 or 0 })
	tween(ui.dim, 0.25, { BackgroundTransparency = self.Open and 0.75 or 1 })

	local snowOn = self.Open and self.Snow
	if snowOn then ui.snowGroup.Visible = true end
	local tw = tween(ui.snowGroup, 0.25, { GroupTransparency = snowOn and 0 or 1 })
	tw.Completed:Connect(function()
		if ui.snowGroup.Parent and not (Library.Open and Library.Snow) then
			ui.snowGroup.Visible = false
		end
	end)
end

function Library:SetOpen(state)
	local ui = self._ui
	if not ui then return end
	self.Open = state

	if state then
		ui.root.Visible = true
		tween(ui.window, 0.25, { GroupTransparency = 0 })
		tween(ui.scale, 0.25, { Scale = 1 })
	else
		ui.closePicker()
		ui.stopInteractions()
		if self._listening then
			self._listening:_cancel()
			self._listening = nil
		end
		local tw = tween(ui.window, 0.25, { GroupTransparency = 1 })
		tw.Completed:Connect(function()
			if ui.root.Parent and not Library.Open then
				ui.root.Visible = false
			end
		end)
		tween(ui.scale, 0.25, { Scale = 0.94 })
	end
	self:RefreshBackdrop()
end

function Library:Toggle()
	self:SetOpen(not self.Open)
end

function Library:Unload()
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	pcall(function() RunService:UnbindFromRenderStep("PinkUIMouse") end)

	local ui = self._ui
	if ui then
		for _, inst in ipairs({ ui.main, ui.backdrop, ui.notify, ui.blur }) do
			inst:Destroy()
		end
	end

	local callbacks = self._unloadCallbacks
	self._unloadCallbacks = {}
	for _, fn in ipairs(callbacks) do task.spawn(fn) end

	self._ui = nil
	self.Window = nil
	self.Options = {}
	self.Open = false
	self._keybinds = {}
	self._listening = nil
	table.clear(themed)
	table.clear(bound)
end

----------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------
function Library:CreateWindow(opts)
	if self.Window then self:Unload() end
	opts = opts or {}

	local size = opts.Size or Vector2.new(480, 360)
	local minSize = opts.MinSize or Vector2.new(380, 260)
	local maxSize = opts.MaxSize or Vector2.new(1100, 800)
	if opts.Snow ~= nil then self.Snow = opts.Snow end
	if opts.Blur ~= nil then self.Blur = opts.Blur end
	if opts.ToggleKey then self.ToggleKey = opts.ToggleKey end

	-- theme can be a preset name ("Ocean"), a table of colors, or the old Accent/Accent2 options
	if opts.Theme then
		local th = opts.Theme
		if type(th) == "string" then th = self.Presets[th] end
		if type(th) == "table" then
			for k, v in pairs(th) do self.Theme[k] = v end
		end
	end
	if opts.Accent then self.Theme.Accent = opts.Accent end
	if opts.Accent2 then self.Theme.Accent2 = opts.Accent2 end

	for _, name in ipairs({ "PinkUI_Main", "PinkUI_Backdrop", "PinkUI_Notify" }) do
		local old = playerGui:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local oldBlur = Lighting:FindFirstChild("PinkUI_Blur")
	if oldBlur then oldBlur:Destroy() end

	local Window = { _tabs = {}, _footerText = opts.Footer }

	------------------------------------------------------------
	-- backdrop: blur + dim + snow
	------------------------------------------------------------
	local blur = new("BlurEffect", { Name = "PinkUI_Blur", Size = 0 }, Lighting)
	local backdropGui = new("ScreenGui", {
		Name = "PinkUI_Backdrop", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 9,
	}, playerGui)
	local dim = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, backdropGui)
	local snowGroup = new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
	}, backdropGui)

	local rng = Random.new()
	local flakeKinds = { "white", "accent", "accent2", "black", "black" }
	local flakes = {}
	for i = 1, 80 do
		local fsize = rng:NextInteger(3, 7)
		local kind = flakeKinds[rng:NextInteger(1, #flakeKinds)]
		local frame = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(fsize, fsize),
			BackgroundTransparency = rng:NextNumber(0.05, 0.35),
			BorderSizePixel = 0,
		}, snowGroup)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
		if kind == "white" then
			frame.BackgroundColor3 = WHITE
		elseif kind == "black" then
			frame.BackgroundColor3 = BLACK
			new("UIStroke", { Color = WHITE, Thickness = 1, Transparency = 0.65 }, frame)
		elseif kind == "accent" then
			bind(frame, "BackgroundColor3", "Accent")
		else
			bind(frame, "BackgroundColor3", "Accent2")
		end
		flakes[i] = {
			frame = frame,
			x = rng:NextNumber(),
			y = rng:NextNumber(),
			speed = rng:NextNumber(0.05, 0.14) * (fsize / 5),
			sway = rng:NextNumber(0.004, 0.018),
			freq = rng:NextNumber(0.5, 1.5),
			phase = rng:NextNumber(0, math.pi * 2),
		}
	end

	------------------------------------------------------------
	-- notifications
	------------------------------------------------------------
	local notifyGui = new("ScreenGui", {
		Name = "PinkUI_Notify", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 11,
	}, playerGui)
	local notifyList = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 240, 1, -24),
		BackgroundTransparency = 1,
	}, notifyGui)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}, notifyList)

	------------------------------------------------------------
	-- main window (root = position/size, window = visuals)
	------------------------------------------------------------
	local mainGui = new("ScreenGui", {
		Name = "PinkUI_Main", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 10,
	}, playerGui)

	local viewport = workspace.CurrentCamera.ViewportSize
	local root = new("Frame", {
		Name = "Root",
		Position = UDim2.fromOffset(math.floor((viewport.X - size.X) / 2), math.floor((viewport.Y - size.Y) / 2)),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Visible = false,
	}, mainGui)

	local window = new("CanvasGroup", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
	}, root)
	local scale = new("UIScale", { Scale = 0.94 }, window)

	local bg = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, window)
	themedGradient(bg, "bg", 55)

	-- title bar
	local titleBar = new("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Active = true,
	}, window)
	local title = textLabel(titleBar, {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Text = opts.Title or "pink ui",
		TextSize = 15,
		TextColor3 = WHITE,
	}, false)
	themedGradient(title, "pair")

	local accent = new("Frame", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, window)
	themedGradient(accent, "loop")

	-- tab bar + content + footer
	local tabBar = new("Frame", {
		Position = UDim2.fromOffset(0, 31),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, window)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4) }, tabBar)

	local content = new("Frame", {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -84),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, window)

	local footer = textLabel(window, {
		Position = UDim2.new(0, 0, 1, -22),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, "Muted")

	function Window:SetFooter(text)
		self._footerText = text
		footer.Text = text or (Library.ToggleKey.Name .. ": menu   |   drag corner to resize")
	end
	function Window:SetTitle(text) title.Text = text end
	function Window:Toggle() Library:Toggle() end
	Window:SetFooter(opts.Footer)

	-- resize grip (bottom-right corner)
	local gripHot = false
	local grip = new("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -2),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, window)
	local gripDots = {}
	local function gripColor()
		return gripHot and Library.Theme.Accent or Library.Theme.Muted
	end
	for _, p in ipairs({ { 13, 13 }, { 9, 13 }, { 13, 9 }, { 5, 13 }, { 9, 9 }, { 13, 5 } }) do
		local dot = new("Frame", {
			Position = UDim2.fromOffset(p[1], p[2]),
			Size = UDim2.fromOffset(2, 2),
			BorderSizePixel = 0,
		}, grip)
		bind(dot, "BackgroundColor3", gripColor)
		table.insert(gripDots, dot)
	end
	local function setGripHot(state)
		gripHot = state
		for _, d in ipairs(gripDots) do
			tween(d, 0.15, { BackgroundColor3 = gripColor() })
		end
	end

	------------------------------------------------------------
	-- color picker popup (shared by all pickers)
	------------------------------------------------------------
	local pickerCatcher = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
	}, window)
	local pickerFrame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(204, 184),
		BorderSizePixel = 0,
		Visible = false,
	}, window)
	bind(pickerFrame, "BackgroundColor3", "Panel")
	outline(pickerFrame)

	local pickerTitle = textLabel(pickerFrame, {
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -34, 0, 18),
		Text = "color",
		TextColor3 = WHITE,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, false)
	themedGradient(pickerTitle, "pair")
	local pickerClose = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Text = "x",
		Font = FONT,
		TextSize = 14,
	}, pickerFrame)
	bind(pickerClose, "TextColor3", "Muted")

	local svBox = new("Frame", {
		Position = UDim2.fromOffset(8, 26),
		Size = UDim2.fromOffset(160, 118),
		BackgroundColor3 = Color3.fromHSV(0, 1, 1),
		BorderSizePixel = 0,
	}, pickerFrame)
	outline(svBox)
	local satLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, svBox)
	new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, satLayer)
	local valLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0 }, svBox)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, valLayer)
	local svCursor = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, svBox)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, svCursor)
	new("UIStroke", { Color = WHITE, Thickness = 1.5 }, svCursor)
	local svBtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, svBox)

	local hueBar = new("Frame", {
		Position = UDim2.fromOffset(176, 26),
		Size = UDim2.fromOffset(18, 118),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, pickerFrame)
	outline(hueBar)
	do
		local keys = {}
		for i = 0, 6 do
			keys[#keys + 1] = kp(i / 6, Color3.fromHSV(math.min(i / 6, 1), 1, 1))
		end
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(keys) }, hueBar)
	end
	local hueCursor = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 4, 0, 4),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, hueBar)
	new("UIStroke", { Color = BLACK, Thickness = 1 }, hueCursor)
	local hueBtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, hueBar)

	local pickerPreview = new("Frame", {
		Position = UDim2.fromOffset(8, 152),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, pickerFrame)
	outline(pickerPreview)
	-- hex box: type a color like #FF8CBE and press enter
	local pickerHex = new("TextBox", {
		Position = UDim2.fromOffset(38, 152),
		Size = UDim2.new(1, -46, 0, 22),
		BorderSizePixel = 0,
		Text = "#FFFFFF",
		Font = FONT,
		TextSize = 13,
		TextXAlignment = LEFT,
		ClearTextOnFocus = false,
	}, pickerFrame)
	bind(pickerHex, "BackgroundColor3", "Field")
	bind(pickerHex, "TextColor3", "Text")
	new("UIPadding", { PaddingLeft = UDim.new(0, 6) }, pickerHex)
	outline(pickerHex)

	local pickerOnChange = nil
	local ph, ps, pv = 0, 1, 1
	local svDrag, hueDrag = false, false

	local function pickerVisuals()
		local color = Color3.fromHSV(ph, ps, pv)
		svBox.BackgroundColor3 = Color3.fromHSV(ph, 1, 1)
		svCursor.Position = UDim2.fromScale(ps, 1 - pv)
		hueCursor.Position = UDim2.fromScale(0.5, ph)
		pickerPreview.BackgroundColor3 = color
		pickerHex.Text = string.format("#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
		return color
	end

	local function pickerCommit()
		local color = pickerVisuals()
		if pickerOnChange then pickerOnChange(color) end
	end

	local function closePicker()
		pickerOnChange = nil
		svDrag, hueDrag = false, false
		pickerFrame.Visible = false
		pickerCatcher.Visible = false
	end

	function Window._openPicker(label, color, onChange)
		pickerOnChange = nil
		ph, ps, pv = color:ToHSV()
		pickerTitle.Text = label
		pickerVisuals()
		pickerOnChange = onChange
		pickerCatcher.Visible = true
		pickerFrame.Visible = true
	end

	pickerHex.FocusLost:Connect(function()
		local hex = (pickerHex.Text:gsub("[^%x]", ""))
		local n = (#hex == 6) and tonumber(hex, 16) or nil
		if n and pickerOnChange then
			local color = Color3.fromRGB(bit32.rshift(n, 16), bit32.band(bit32.rshift(n, 8), 255), bit32.band(n, 255))
			ph, ps, pv = color:ToHSV()
			pickerCommit()
		else
			pickerVisuals()
		end
	end)

	pickerCatcher.MouseButton1Click:Connect(closePicker)
	pickerClose.MouseButton1Click:Connect(closePicker)

	local function updateSV()
		local m = UserInputService:GetMouseLocation()
		ps = math.clamp((m.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
		pv = 1 - math.clamp((m.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
		pickerCommit()
	end
	local function updateHue()
		local m = UserInputService:GetMouseLocation()
		ph = math.clamp((m.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 0.999)
		pickerCommit()
	end
	svBtn.InputBegan:Connect(function(input)
		if isPress(input) then svDrag = true; updateSV() end
	end)
	hueBtn.InputBegan:Connect(function(input)
		if isPress(input) then hueDrag = true; updateHue() end
	end)

	-- border (drawn last so it sits on top)
	local border = new("Frame", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, window)
	local borderStroke = new("UIStroke", { Color = WHITE, Thickness = 1 }, border)
	local borderGrad = themedGradient(borderStroke, "loop")

	------------------------------------------------------------
	-- tween drag + corner resize
	------------------------------------------------------------
	local dragging, dragStart, dragOrigin = false, nil, nil
	local resizing, resizeStart, resizeBase = false, nil, nil

	connect(titleBar.InputBegan, function(input)
		if isPress(input) then
			dragging = true
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			dragOrigin = root.AbsolutePosition
		end
	end)

	connect(grip.InputBegan, function(input)
		if isPress(input) then
			resizing = true
			resizeStart = Vector2.new(input.Position.X, input.Position.Y)
			resizeBase = root.AbsoluteSize
			setGripHot(true)
		end
	end)
	connect(grip.MouseEnter, function() setGripHot(true) end)
	connect(grip.MouseLeave, function()
		if not resizing then setGripHot(false) end
	end)

	connect(UserInputService.InputChanged, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)

		if dragging then
			local vp = workspace.CurrentCamera.ViewportSize
			local target = dragOrigin + (pos - dragStart)
			local x = math.clamp(target.X, -(root.AbsoluteSize.X - 80), vp.X - 80)
			local y = math.clamp(target.Y, 0, vp.Y - 30)
			tween(root, 0.12, { Position = UDim2.fromOffset(x, y) })
		elseif resizing then
			local vp = workspace.CurrentCamera.ViewportSize
			local abs = root.AbsolutePosition
			local d = pos - resizeStart
			local w = math.clamp(resizeBase.X + d.X, minSize.X, math.max(minSize.X, math.min(maxSize.X, vp.X - abs.X)))
			local h = math.clamp(resizeBase.Y + d.Y, minSize.Y, math.max(minSize.Y, math.min(maxSize.Y, vp.Y - abs.Y)))
			tween(root, 0.08, { Size = UDim2.fromOffset(w, h) })
		elseif svDrag then
			updateSV()
		elseif hueDrag then
			updateHue()
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if isPress(input) then
			dragging, svDrag, hueDrag = false, false, false
			if resizing then
				resizing = false
				setGripHot(false)
			end
		end
	end)

	------------------------------------------------------------
	-- tabs
	------------------------------------------------------------
	local function tabColor(tab)
		return tab.Selected and Library.Theme.Text or Library.Theme.Muted
	end

	local function selectTab(tab)
		for _, tb in ipairs(Window._tabs) do
			tb.Selected = (tb == tab)
			tb.Page.Visible = tb.Selected
			tb.Underline.Visible = tb.Selected
			tween(tb.Button, 0.15, { TextColor3 = tabColor(tb) })
		end
	end

	function Window:AddTab(name)
		local btn = new("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = name,
			Font = FONT,
			TextSize = 13,
			AutoButtonColor = false,
			LayoutOrder = #self._tabs + 1,
		}, tabBar)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, btn)
		local underline = new("Frame", {
			Position = UDim2.new(0, -10, 1, -2),
			Size = UDim2.new(1, 20, 0, 2),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Visible = false,
		}, btn)
		themedGradient(underline, "pair")

		local page = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
		}, content)

		local columns = {}
		for _, side in ipairs({ "Left", "Right" }) do
			local isLeft = side == "Left"
			local col = new("ScrollingFrame", {
				Position = isLeft and UDim2.new(0, 0, 0, 0) or UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 2,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
			}, page)
			bind(col, "ScrollBarImageColor3", "Accent")
			new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, col)
			new("UIPadding", {
				PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, isLeft and 8 or 4),
				PaddingRight = UDim.new(0, isLeft and 4 or 8),
			}, col)
			columns[side] = col
		end

		local tab = setmetatable({
			Window = self,
			Button = btn,
			Underline = underline,
			Page = page,
			Columns = columns,
			Selected = false,
			_count = { Left = 0, Right = 0 },
		}, Tab)
		bind(btn, "TextColor3", function() return tabColor(tab) end)
		table.insert(self._tabs, tab)

		btn.MouseButton1Click:Connect(function() selectTab(tab) end)
		if #self._tabs == 1 then selectTab(tab) end
		return tab
	end

	-- ready-made settings tab: menu options + full theme editor + unload
	function Window:AddSettingsTab(name)
		local tab = self:AddTab(name or "Settings")

		-- left column: menu
		local menu = tab:AddGroup("Menu", "Left")
		menu:AddToggle("PinkUI_Snow", {
			Text = "Snow", Default = Library.Snow,
			Callback = function(v) Library.Snow = v; Library:RefreshBackdrop() end,
		})
		menu:AddToggle("PinkUI_Blur", {
			Text = "Blur background", Default = Library.Blur,
			Callback = function(v) Library.Blur = v; Library:RefreshBackdrop() end,
		})
		menu:AddSlider("PinkUI_Spin", {
			Text = "Border spin (x)", Min = 0, Max = 10, Default = Library.SpinMult, Decimals = 1,
			Callback = function(v) Library.SpinMult = v end,
		})
		menu:AddKeybind("PinkUI_MenuKey", {
			Text = "Menu key", Default = Library.ToggleKey,
			ChangedCallback = function(key)
				if key then
					Library.ToggleKey = key
					if not Window._footerText then Window:SetFooter(nil) end
				end
			end,
		})
		menu:AddButton({ Text = "Unload UI", Callback = function() Library:Unload() end })

		-- right column: theme editor
		local themeOpts = {}
		local singleKeys = {
			{ "Panel", "Panels" },
			{ "Field", "Fields / buttons" },
			{ "Outline", "Outlines" },
			{ "Text", "Text" },
			{ "Muted", "Muted text" },
			{ "Highlight", "Values / keys" },
		}

		local function syncThemeOptions()
			local th = Library.Theme
			themeOpts.Accent:Set(th.Accent, th.Accent2, true)
			themeOpts.Background:Set(th.Background, th.BackgroundEnd, true)
			for _, entry in ipairs(singleKeys) do
				themeOpts[entry[1]]:Set(th[entry[1]], true)
			end
		end

		local themeGroup = tab:AddGroup("Theme", "Right")
		local presetNames = {}
		for presetName in pairs(Library.Presets) do table.insert(presetNames, presetName) end
		table.sort(presetNames)
		themeGroup:AddDropdown("PinkUI_Preset", {
			Text = "Preset",
			Values = presetNames,
			Callback = function(presetName)
				if Library.Presets[presetName] then
					Library:SetTheme(Library.Presets[presetName])
					syncThemeOptions()
				end
			end,
		})
		themeOpts.Accent = themeGroup:AddGradientPicker("PinkUI_Accent", {
			Text = "Accent gradient",
			Default = { Library.Theme.Accent, Library.Theme.Accent2 },
			Callback = function(a, b) Library:SetTheme({ Accent = a, Accent2 = b }) end,
		})
		themeOpts.Background = themeGroup:AddGradientPicker("PinkUI_Background", {
			Text = "Window gradient",
			Default = { Library.Theme.Background, Library.Theme.BackgroundEnd },
			Callback = function(a, b) Library:SetTheme({ Background = a, BackgroundEnd = b }) end,
		})

		local colors = tab:AddGroup("Colors", "Right")
		for _, entry in ipairs(singleKeys) do
			local key = entry[1]
			themeOpts[key] = colors:AddColorPicker("PinkUI_" .. key, {
				Text = entry[2],
				Default = Library.Theme[key],
				Callback = function(c) Library:SetTheme({ [key] = c }) end,
			})
		end
		colors:AddButton({
			Text = "Reset theme",
			Callback = function()
				Library:SetTheme(Library.Defaults)
				syncThemeOptions()
			end,
		})
		colors:AddButton({
			Text = "Print theme to output",
			Callback = function()
				print(Library:ExportTheme())
				Library:Notify("Theme printed to the output window", 3)
			end,
		})
		return tab
	end

	------------------------------------------------------------
	-- input: menu key, keybinds
	------------------------------------------------------------
	connect(UserInputService.InputBegan, function(input, gameProcessed)
		-- rebinding a keybind
		local listening = Library._listening
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				Library._listening = nil
				if input.KeyCode == Enum.KeyCode.Escape then
					listening:Set(nil)
				else
					listening:Set(input.KeyCode)
				end
			end
			return
		end

		if input.KeyCode == Library.ToggleKey and not UserInputService:GetFocusedTextBox() then
			Library:Toggle()
			return
		end

		if not gameProcessed and input.UserInputType == Enum.UserInputType.Keyboard then
			for _, kb in ipairs(Library._keybinds) do
				if kb.Value and kb.Value == input.KeyCode then
					kb:_press()
				end
			end
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			for _, kb in ipairs(Library._keybinds) do
				if kb.Value and kb.Value == input.KeyCode then
					kb:_release()
				end
			end
		end
	end)

	-- free the mouse while the menu is open (first-person / shiftlock games)
	pcall(function() RunService:UnbindFromRenderStep("PinkUIMouse") end)
	RunService:BindToRenderStep("PinkUIMouse", Enum.RenderPriority.Last.Value, function()
		if Library.Open then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	-- border spin + snow
	local t = 0
	connect(RunService.RenderStepped, function(dt)
		t += dt
		if Library.Open then
			borderGrad.Rotation = (borderGrad.Rotation + 40 * Library.SpinMult * dt) % 360
		end
		if snowGroup.Visible then
			for _, f in ipairs(flakes) do
				f.y += f.speed * dt
				if f.y > 1.05 then
					f.y = -0.05
					f.x = rng:NextNumber()
				end
				f.frame.Position = UDim2.fromScale(f.x + math.sin(t * f.freq + f.phase) * f.sway, f.y)
			end
		end
	end)

	------------------------------------------------------------
	-- finish
	------------------------------------------------------------
	self._ui = {
		main = mainGui, backdrop = backdropGui, notify = notifyGui, blur = blur,
		root = root, window = window, scale = scale,
		dim = dim, snowGroup = snowGroup, notifyList = notifyList,
		closePicker = closePicker,
		stopInteractions = function()
			dragging, resizing, svDrag, hueDrag = false, false, false, false
			setGripHot(false)
		end,
	}
	self.Window = Window

	if opts.StartOpen ~= false then
		self:SetOpen(true)
	end
	return Window
end

return Library
