local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/noxo-n/waxz-ui/refs/heads/main/source.lua"))()

local Window = Library:CreateWindow({
	Title = "pink ui  /  demo",
	Size = Vector2.new(520, 380),         -- starting size
	MinSize = Vector2.new(380, 260),      -- smallest the corner grip can shrink to
	MaxSize = Vector2.new(1100, 800),     -- largest the corner grip can expand to
	ToggleKey = Enum.KeyCode.RightShift,
	Snow = true,
	Blur = true,
})

-- TAB 1: basic elements
local Main = Window:AddTab("Main")

local Left = Main:AddGroup("Toggles & buttons", "Left")
Left:AddToggle("ExampleToggle", {
	Text = "Example toggle",
	Default = false,
	Callback = function(value) print("toggle:", value) end,
})
Left:AddButton({
	Text = "Send notification",
	Callback = function() Library:Notify("hello from pink ui", 3) end,
})
Left:AddDivider()
Left:AddKeybind("ExampleKey", {
	Text = "Notify keybind",
	Default = Enum.KeyCode.X,
	Mode = "Press", -- "Press" | "Hold" | "Toggle"
	Callback = function() Library:Notify("keybind pressed", 2) end,
})
Left:AddTextbox("ExampleName", {
	Text = "Textbox",
	Default = "",
	Placeholder = "type something...",
	Callback = function(text) print("textbox:", text) end,
})
Left:AddLabel("Tip: drag the title bar to move, drag the bottom-right corner to resize.")

local Right = Main:AddGroup("Sliders & dropdowns", "Right")
Right:AddSlider("ExampleSlider", {
	Text = "Example slider",
	Min = 0, Max = 100, Default = 40, Decimals = 0, Suffix = "%",
	Callback = function(value) print("slider:", value) end,
})
Right:AddSlider("ExampleDecimal", {
	Text = "Decimal slider",
	Min = 0, Max = 1, Default = 0.25, Decimals = 2,
})
Right:AddDropdown("ExampleDropdown", {
	Text = "Mode",
	Values = { "Alpha", "Beta", "Gamma" },
	Default = "Alpha",
	Callback = function(value) print("dropdown:", value) end,
})
Right:AddDropdown("ExampleMulti", {
	Text = "Multi select",
	Values = { "One", "Two", "Three", "Four" },
	Multi = true,
	Default = { "One" },
	Callback = function(set)
		for name in pairs(set) do print("selected:", name) end
	end,
})

-- TAB 2: colors
local Colors = Window:AddTab("Colors")
local Pickers = Colors:AddGroup("Pickers", "Left")
Pickers:AddColorPicker("ExampleColor", {
	Text = "Single color",
	Default = Color3.fromRGB(255, 140, 190),
	Callback = function(color) print("color:", color) end,
})
Pickers:AddGradientPicker("ExampleGradient", {
	Text = "Gradient",
	Default = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 182, 213) },
	Callback = function(a, b) print("gradient:", a, b) end,
})

-- TAB 3: built-in settings (menu key, snow, blur, accent theme, unload)
Window:AddSettingsTab()

-- Reading values anywhere else in your code
Library.Options.ExampleToggle:OnChanged(function(value)
	print("changed via OnChanged:", value)
end)

-- print(Library.Options.ExampleSlider.Value)
-- Library.Options.ExampleToggle:Set(true)
-- Library:Unload()  -- removes everything
