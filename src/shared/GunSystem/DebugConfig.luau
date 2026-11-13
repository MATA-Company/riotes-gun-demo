--!strict
--[[
	DebugConfig — live, replicated debug switches for the gun system.

	Server owns the BoolValues (under ReplicatedStorage.GunSystem.Debug);
	clients read them and can flip them through the Debug remote, so a
	toggle in-game is visible to both realms immediately.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"VisualizeCasts",
	"Trajectory",
	"BulletHoles",
	"HitLog",
	"InfiniteAmmo",
}

local DEFAULTS = {
	VisualizeCasts = false,
	Trajectory = false,
	BulletHoles = true,
	HitLog = false,
	InfiniteAmmo = false,
}

local DebugConfig = {}

local function root(): Instance
	local gunSystem = ReplicatedStorage:FindFirstChild("GunSystem")
	if not gunSystem then
		gunSystem = Instance.new("Folder")
		gunSystem.Name = "GunSystem"
		gunSystem.Parent = ReplicatedStorage
	end
	local folder = gunSystem:FindFirstChild("Debug")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Debug"
		folder.Parent = gunSystem
	end
	return folder
end

if RunService:IsServer() then
	local folder = root()
	for _, name in ipairs(NAMES) do
		if not folder:FindFirstChild(name) then
			local value = Instance.new("BoolValue")
			value.Name = name
			value.Value = DEFAULTS[name]
			value.Parent = folder
		end
	end
end

--- Reads one switch; false when the folder has not replicated yet.
function DebugConfig.get(name: string): boolean
	local folder = ReplicatedStorage:FindFirstChild("GunSystem")
	local debug = folder and folder:FindFirstChild("Debug")
	local value = debug and debug:FindFirstChild(name)
	return value ~= nil and (value :: BoolValue).Value == true
end

--- Server-only: sets one switch (used by the Debug remote).
function DebugConfig.set(name: string, value: boolean)
	assert(RunService:IsServer(), "DebugConfig.set is server-only")
	local folder = root()
	local entry = folder:FindFirstChild(name)
	if not entry then
		entry = Instance.new("BoolValue")
		entry.Name = name
		entry.Parent = folder
	end
	(entry :: BoolValue).Value = value
end

--- Server-only: flips every switch together (the F3 master toggle).
function DebugConfig.setAll(value: boolean)
	for _, name in ipairs(NAMES) do
		DebugConfig.set(name, value)
	end
end

DebugConfig.names = table.freeze(NAMES)

return DebugConfig
