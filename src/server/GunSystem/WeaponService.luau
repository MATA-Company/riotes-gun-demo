--!strict
--[[
	WeaponService (server) — binds Tools to Weapon instances and owns the
	remote surface. One equipped gun per player; everything else is derived.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.GunSystem.Net)
local DebugConfig = require(ReplicatedStorage.Shared.GunSystem.DebugConfig)
local Configs = require(ReplicatedStorage.Shared.GunSystem.Configs)
local Weapon = require(script.Parent.Weapon)

local WeaponService = {}

local equipped: { [Player]: any } = {}

local SOUND_NAMES = { fire = "Fire", reload = "Reload", equip = "Equip", empty = "Empty" }

--- Creates the SFX folder and one named Sound per slot; fills ids from config.
local function ensureSfx(tool: Tool, definition: any)
	local folder = tool:FindFirstChild("SFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SFX"
		folder.Parent = tool
	end
	for key, soundName in pairs(SOUND_NAMES) do
		local sound = folder:FindFirstChild(soundName)
		if not sound then
			sound = Instance.new("Sound")
			sound.Name = soundName
			sound.Parent = folder
		end
		local id = definition.sounds[key]
		if id ~= "" and sound.SoundId ~= ("rbxassetid://" .. id) then
			sound.SoundId = "rbxassetid://" .. id
		end
	end
end

-- Weapon geometry is visual only. If any mesh remains massive or touchable,
-- equipping can add a physical assembly to the character and shove the rig.
local function configureToolPhysics(tool: Tool)
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function setupTool(tool: Instance)
	if not tool:IsA("Tool") then
		return
	end
	local definition = Configs.get(tool.Name)
	if not definition then
		return
	end
	-- Idempotent: re-apply every join so a clone that inherited stale
	-- attributes still ends up consistent with the current config.
	tool:SetAttribute("GunSystem", true)
	tool:SetAttribute("WeaponType", definition.weaponType)
	tool:SetAttribute("DisplayName", definition.displayName)
	tool:SetAttribute("Slot", definition.slot)
	tool:SetAttribute("FireMode", definition.fireMode)
	tool:SetAttribute("Ammo", definition.startingAmmo)
	tool:SetAttribute("Magazine", definition.magazine)
	tool:SetAttribute("Reloading", false)
	tool:SetAttribute("Equipped", false)
	tool:SetAttribute("Owner", "")
	configureToolPhysics(tool)
	ensureSfx(tool, definition)
end

local function equipTool(player: Player, tool: Instance)
	if not tool:IsA("Tool") then
		return
	end
	local definition = Configs.get(tool.Name)
	if not definition then
		return
	end

	local current = equipped[player]
	if current then
		current:destroy()
		equipped[player] = nil
	end

	local weapon = Weapon.new(definition, tool, player)
	equipped[player] = weapon
	weapon:equip()

	weapon.signalHit:Connect(function(isHead: boolean)
		Net.remote("Hit"):FireClient(player, isHead)
	end)
end

local function releaseTool(player: Player, tool: Instance)
	local current = equipped[player]
	if current and current.tool == tool then
		current:destroy()
		equipped[player] = nil
	end
end

local function bindCharacter(player: Player, character: Model)
	for _, child in ipairs(character:GetChildren()) do
		setupTool(child)
		equipTool(player, child)
	end

	character.ChildAdded:Connect(function(child)
		setupTool(child)
		equipTool(player, child)
	end)

	character.ChildRemoved:Connect(function(child)
		releaseTool(player, child)
	end)
end

function WeaponService.start()
	if _G.GunSystemStarted then
		return -- one bind per server VM, even when Rojo hot-reloads this script
	end
	_G.GunSystemStarted = true

	-- Publish the per-material impact sounds so clients can play them locally
	-- at the hit point (server playback arrives a beat too late).
	do
		-- These two assets were archived by Roblox; they fail to load and were
		-- the source of the delayed/silent impact audio.
		local ARCHIVED = {
			["rbxassetid://4668967717"] = true,
			["rbxassetid://4668967993"] = true,
		}

		local hitEffects = ServerStorage:FindFirstChild("HitEffects")
		local replicated = ReplicatedStorage:FindFirstChild("HitSounds")
		if hitEffects and not replicated then
			local root = Instance.new("Folder")
			root.Name = "HitSounds"
			root.Parent = ReplicatedStorage

			for _, materialFolder in ipairs(hitEffects:GetChildren()) do
				local sounds = materialFolder:FindFirstChild("MaterialSounds")
				if sounds then
					local copy = Instance.new("Folder")
					copy.Name = materialFolder.Name
					for _, sound in ipairs(sounds:GetChildren()) do
						if sound:IsA("Sound")
							and sound.SoundId ~= ""
							and not ARCHIVED[sound.SoundId]
						then
							sound:Clone().Parent = copy
						end
					end
					if #copy:GetChildren() > 0 then
						copy.Parent = root
					end
				end
			end

			-- Any material left with nothing reuses the concrete pool.
			local fallback = root:FindFirstChild("Concrete")
			if fallback then
				for _, materialFolder in ipairs(hitEffects:GetChildren()) do
					if not root:FindFirstChild(materialFolder.Name) then
						local copy = fallback:Clone()
						copy.Name = materialFolder.Name
						copy.Parent = root
					end
				end
			end
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		WeaponService.trackPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		WeaponService.trackPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local current = equipped[player]
		if current then
			current:destroy()
			equipped[player] = nil
		end
	end)

	Net.onServer("Fire", function(player: Player, direction: any)
		local weapon = equipped[player]
		if not weapon or typeof(direction) ~= "Vector3" then
			return
		end
		if direction.Magnitude > 1 then
			direction = direction.Unit
		end
		weapon:fire(direction)
	end)

	Net.onServer("Reload", function(player: Player)
		local weapon = equipped[player]
		if weapon then
			weapon:reload()
		end
	end)

	Net.onServer("Aim", function(player: Player, aiming: any)
		local weapon = equipped[player]
		if weapon and typeof(aiming) == "boolean" then
			weapon:setAiming(aiming)
		end
	end)

	Net.onServer("Debug", function(_player: Player, all: any)
		if typeof(all) == "boolean" then
			DebugConfig.setAll(all)
		end
	end)
end

function WeaponService.trackPlayer(player: Player)
	local function onCharacter(character: Model)
		bindCharacter(player, character)
	end

	local character = player.Character
	if character then
		onCharacter(character)
	end
	player.CharacterAdded:Connect(onCharacter)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			setupTool(tool)
		end
		backpack.ChildAdded:Connect(setupTool)
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			child.ChildAdded:Connect(setupTool)
			for _, tool in ipairs(child:GetChildren()) do
				setupTool(tool)
			end
		end
	end)
end

return WeaponService
