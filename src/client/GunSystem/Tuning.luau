--!strict
--[[
	Tuning — live, in-game adjustment panel for the first-person view model.

	Open with F2. Each field has − / + buttons and prints a ready-to-paste
	snippet, so the numbers you settle on can be baked into the config.

	Values are read every frame by the controller (camera-space placement) and
	by the view model (wrist correction), so changes apply instantly.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Configs = require(ReplicatedStorage.Shared.GunSystem.Configs)

local Tuning = {}

local DEFAULT_PROFILE = {
	px = 0.32, py = -1.70, pz = -1.20,
	rx = 0, ry = 0, rz = 0,
	wx = -95, wy = -5, wz = 0,
	gx = -0.05, gy = 0.15, gz = -0.35,
	scale = 1.25,
}

Tuning.values = table.clone(DEFAULT_PROFILE)
Tuning.profiles = {}
Tuning.currentName = "default"

Tuning.enabled = true

local refreshAll: (() -> ())? = nil

--- Switches the panel to a weapon's profile, seeded from its config the first
--- time that weapon is equipped. Everything else (GUI, rig) follows.
function Tuning.useProfile(name: string, defaults: { [string]: number }?)
	local profile = Tuning.profiles[name]
	if not profile then
		profile = table.clone(DEFAULT_PROFILE)
		if defaults then
			for key, value in pairs(defaults) do
				if type(value) == "number" then
					profile[key] = value
				end
			end
		end
		Tuning.profiles[name] = profile
	end
	Tuning.values = profile
	Tuning.currentName = name
	if refreshAll then
		refreshAll()
	end
end

function Tuning.offsetCFrame(): CFrame
	local v = Tuning.values
	return CFrame.new(v.px, v.py, v.pz)
		* CFrame.Angles(math.rad(v.rx), math.rad(v.ry), math.rad(v.rz))
end

function Tuning.wristCFrame(): CFrame
	local v = Tuning.values
	return CFrame.Angles(math.rad(v.wx), math.rad(v.wy), math.rad(v.wz))
end

--- Offset applied inside the hand: moves the gun forward/back and sideways.
function Tuning.gunOffsetCFrame(): CFrame
	local v = Tuning.values
	return CFrame.new(v.gx, v.gy, v.gz)
end

local ROWS = {
	{ key = "px", label = "pos X", step = 0.05 },
	{ key = "py", label = "pos Y", step = 0.05 },
	{ key = "pz", label = "pos Z (fwd)", step = 0.05 },
	{ key = "rx", label = "rot X", step = 5 },
	{ key = "ry", label = "rot Y", step = 5 },
	{ key = "rz", label = "rot Z", step = 5 },
	{ key = "wx", label = "wrist X", step = 5 },
	{ key = "wy", label = "wrist Y", step = 5 },
	{ key = "wz", label = "wrist Z", step = 5 },
	{ key = "gx", label = "gun X", step = 0.05 },
	{ key = "gy", label = "gun Y", step = 0.05 },
	{ key = "gz", label = "gun Z (fwd)", step = 0.05 },
	{ key = "scale", label = "scale", step = 0.05 },
}

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GunTuning"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Position = UDim2.new(0, 24, 0, 120)
	frame.Size = UDim2.fromOffset(250, 40 + #ROWS * 26 + 34)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(160, 210, 255)
	title.Text = "VIEW MODEL — F2 to hide"
	title.Parent = frame

	local valueLabels: { [string]: TextLabel } = {}

	local function makeRow(index: number, row: any)
		local y = 30 + (index - 1) * 26

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(8, y)
		label.Size = UDim2.fromOffset(70, 22)
		label.Font = Enum.Font.Gotham
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(220, 220, 220)
		label.Text = row.label
		label.Parent = frame

		local minus = Instance.new("TextButton")
		minus.Position = UDim2.fromOffset(80, y)
		minus.Size = UDim2.fromOffset(28, 22)
		minus.Text = "-"
		minus.Font = Enum.Font.GothamBold
		minus.TextSize = 14
		minus.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
		minus.TextColor3 = Color3.new(1, 1, 1)
		minus.BorderSizePixel = 0
		minus.Parent = frame

		local value = Instance.new("TextLabel")
		value.Position = UDim2.fromOffset(112, y)
		value.Size = UDim2.fromOffset(66, 22)
		value.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
		value.Font = Enum.Font.Code
		value.TextSize = 12
		value.TextColor3 = Color3.fromRGB(255, 255, 255)
		value.Text = "0"
		value.Parent = frame
		valueLabels[row.key] = value

		local plus = Instance.new("TextButton")
		plus.Position = UDim2.fromOffset(182, y)
		plus.Size = UDim2.fromOffset(28, 22)
		plus.Text = "+"
		plus.Font = Enum.Font.GothamBold
		plus.TextSize = 14
		plus.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
		plus.TextColor3 = Color3.new(1, 1, 1)
		plus.BorderSizePixel = 0
		plus.Parent = frame

		local function refresh()
			value.Text = string.format("%.2f", Tuning.values[row.key])
		end
		minus.MouseButton1Click:Connect(function()
			Tuning.values[row.key] -= row.step
			refresh()
		end)
		plus.MouseButton1Click:Connect(function()
			Tuning.values[row.key] += row.step
			refresh()
		end)
		refresh()
	end

	for index, row in ipairs(ROWS) do
		makeRow(index, row)
	end

	refreshAll = function()
		for _, row in ipairs(ROWS) do
			local label = valueLabels[row.key]
			if label then
				label.Text = string.format("%.2f", Tuning.values[row.key])
			end
		end
		title.Text = "VIEW MODEL — " .. Tuning.currentName .. " — F2"
	end
	refreshAll()

	local function button(text: string, x: number, onClick: () -> ())
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, 30 + #ROWS * 26 + 4)
		b.Size = UDim2.fromOffset(78, 24)
		b.Text = text
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.BorderSizePixel = 0
		b.Parent = frame
		b.MouseButton1Click:Connect(onClick)
		return b
	end

	button("Print values", 8, function()
		local v = Tuning.values
		print(string.format(
			"[Tuning] pos=(%.2f, %.2f, %.2f) rot=(%.0f, %.0f, %.0f) wrist=(%.0f, %.0f, %.0f) gun=(%.2f, %.2f, %.2f) scale=%.2f",
			v.px, v.py, v.pz, v.rx, v.ry, v.rz, v.wx, v.wy, v.wz, v.gx, v.gy, v.gz, v.scale
		))
	end)

	button("Copy config", 90, function()
		local v = Tuning.values
		print(string.format(
			[[
	-- %s view model framing
	tuning = {
		px = %.2f, py = %.2f, pz = %.2f,
		rx = %.0f, ry = %.0f, rz = %.0f,
		wx = %.0f, wy = %.0f, wz = %.0f,
		gx = %.2f, gy = %.2f, gz = %.2f,
		scale = %.2f,
	},]],
			Tuning.currentName,
			v.px, v.py, v.pz, v.rx, v.ry, v.rz, v.wx, v.wy, v.wz, v.gx, v.gy, v.gz, v.scale
		))
	end)

	button("Reset", 172, function()
		for key, value in pairs(DEFAULT_PROFILE) do
			Tuning.values[key] = value
		end
		if refreshAll then
			refreshAll()
		end
	end)

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(8, 30 + #ROWS * 26 + 30)
	hint.Size = UDim2.new(1, -16, 0, 16)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Color3.fromRGB(140, 140, 150)
	hint.Text = "mouse is unlocked while open"
	hint.Parent = frame

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F2 then
			gui.Enabled = not gui.Enabled
		end
	end)

	return gui
end

local gui = buildGui()
gui.Enabled = false -- dev tool: hidden until F2

-- Watch the equipped gun ourselves, so each weapon always has its own profile
-- regardless of how the controller is wired up.
RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then
		return
	end
	local equipped: Tool? = nil
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("GunSystem") then
			equipped = child
			break
		end
	end
	if not equipped or Tuning.currentName == equipped.Name then
		return
	end

	local definition = Configs.get(equipped.Name)
	local defaults = definition and definition.camera and definition.camera.tuning
	Tuning.useProfile(equipped.Name, defaults)
end)

-- First person locks the cursor; release it while the panel is open so the
-- buttons are clickable. Runs after the camera so the lock cannot win.
RunService:BindToRenderStep("GunTuningMouse", Enum.RenderPriority.Camera.Value + 50, function()
	if gui.Enabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end)

return Tuning
