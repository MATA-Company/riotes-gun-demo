--!strict
--[[
	Weapon (server) — one live gun for one player.

	Owns authority: ammo, reload timing, rate limit and the raycast. The
	client only ever *asks*; it never decides a hit.

	Presentation it drives (replicated to every client):
	  • muzzle particles + light from the tool's `Effects` ObjectValues
	  • SFX from the tool's `SFX` folder, by name
	  • attributes the HUD and animations read
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

local DebugConfig = require(ReplicatedStorage.Shared.GunSystem.DebugConfig)
local Net = require(ReplicatedStorage.Shared.GunSystem.Net)
local FastCast2 = require(ReplicatedStorage.Packages.FastCast2)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Weapon = {}
Weapon.__index = Weapon

local CONTINUOUS_EMITTERS = { Smoke = true, OverHeat = true }

function Weapon.new(definition, tool: Tool, player: Player)
	local self = setmetatable({}, Weapon)

	self.definition = definition
	self.tool = tool
	self.player = player
	self.trove = Trove.new()

	self.equipped = false
	self.reloading = false
	self.aiming = false
	self.ammo = definition.startingAmmo
	self.nextFireAt = 0

	self.signalHit = Signal.new()
	self.trove:Add(self.signalHit)

	self.character = player.Character or player.CharacterAdded:Wait()
	self.trove:Add(player.CharacterAdded:Connect(function(character)
		self.character = character
		if self.equipped then
			self:unequip()
		end
	end))

	self.caster = self:_createCaster()
	self.effects = self:_resolveEffects()
	self:_writeAttributes()

	return self
end

-- // Ballistics ---------------------------------------------------------------

function Weapon:_createCaster()
	local caster = FastCast2.new()

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local behavior = FastCast2.newBehavior()
	behavior.RaycastParams = params
	behavior.MaxDistance = self.definition.range
	behavior.Acceleration = Vector3.zero

	caster.Hit = function(_cast, result)
		self:_onHit(result)
	end

	caster:Init("BulkMoveTo", false)

	self.behavior = behavior
	self.castParams = params
	return caster
end

function Weapon:_onHit(result: RaycastResult)
	local instance = result.Instance
	if not instance then
		return
	end

	if self.lastOrigin then
		self.lastOrigin = nil -- tracer is spawned by fire(), not here
	end
	if DebugConfig.get("BulletHoles") then
		self:_spawnHole(result)
	end
	self:_spawnImpact(result)

	local model = instance:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		if DebugConfig.get("HitLog") then
			print(string.format("[GunSystem] hit %s (%s)", instance.Name, instance.ClassName))
		end
		return
	end
	if model == self.character then
		return
	end

	local isHead = instance.Name == "Head"
	local damage = self.definition.damage * (isHead and self.definition.headshotMultiplier or 1)
	humanoid:TakeDamage(damage)

	if DebugConfig.get("HitLog") then
		print(string.format("[GunSystem] hit %s for %.0f%s", humanoid.Parent and humanoid.Parent.Name or "?", damage, isHead and " (head)" or ""))
	end

	self.signalHit:Fire(isHead)
end

--- Templates live in ServerStorage.GunSystemTemplates (workspace fallback).
local function findTemplate(name: string): Instance?
	local serverStorage = game:GetService("ServerStorage")
	local templates = serverStorage:FindFirstChild("GunSystemTemplates")
	local found = templates and templates:FindFirstChild(name)
	if found then
		return found
	end
	return workspace:FindFirstChild(name)
end

--- The attachment the muzzle effects belong to (nil if the gun has none).
local function muzzleAttachment(tool: Tool): Attachment?
	local effects = tool:FindFirstChild("Effects")
	if effects then
		for _, child in ipairs(effects:GetChildren()) do
			if child:IsA("ObjectValue") and child.Value and child.Value:IsA("Attachment") then
				return child.Value
			end
		end
	end
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("Attachment") then
			local name = string.lower(descendant.Name)
			if name:find("muzzle") or name == "shooteffect" or name == "barrel" then
				return descendant
			end
		end
	end
	return nil
end

local function muzzlePosition(tool: Tool): Vector3?
	local effects = tool:FindFirstChild("Effects")
	if effects then
		for _, child in ipairs(effects:GetChildren()) do
			if child:IsA("ObjectValue") and child.Value then
				local anchor = child.Value
				if anchor:IsA("Attachment") then
					return anchor.WorldPosition
				end
			end
		end
	end

	-- Fall back to the muzzle attachment authored on the model itself.
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("Attachment") then
			local name = string.lower(descendant.Name)
			if name:find("muzzle") or name == "shooteffect" or name == "barrel" then
				return descendant.WorldPosition
			end
		end
	end

	local handle = tool:FindFirstChild("Handle")
	return handle and handle:IsA("BasePart") and handle.Position or nil
end

--- A flat, orientation-corrected hole cloned from the project's hole template.
function Weapon:_spawnHole(result: RaycastResult)
	local folder = workspace:FindFirstChild("BulletHoles")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BulletHoles"
		folder.Parent = workspace
	end

	local template = findTemplate("BulletHole") or workspace:FindFirstChild("Part")
	local hole
	if template and template:IsA("BasePart") then
		hole = template:Clone()
		hole.Size = Vector3.new(0.12, 0.12, 0.02)
	else
		hole = Instance.new("Part")
		hole.Size = Vector3.new(0.1, 0.1, 0.02)
		hole.Material = Enum.Material.Plastic
	end
	hole.Name = "BulletHole"
	hole.Anchored = true
	hole.CanCollide = false
	hole.CanQuery = false
	hole.CanTouch = false
	hole.Color = Color3.fromRGB(14, 14, 14)
	hole.Transparency = 0.1
	hole.Massless = true

	local normal = result.Normal
	local position = result.Position + normal * 0.01
	hole.CFrame = CFrame.lookAt(position, position + normal)
		* CFrame.Angles(0, 0, math.random() * math.pi * 2)
	hole.Parent = folder

	-- keep the place clean: cap the number of live holes
	local children = folder:GetChildren()
	if #children > 120 then
		for index = 1, #children - 120 do
			children[index]:Destroy()
		end
	end

	Debris:AddItem(hole, 20)
end

--- Smooth trail from the muzzle to the impact, cloned from Workspace.BulletTracer.
function Weapon:_spawnTracer(from: Vector3, to: Vector3)
	local template = findTemplate("BulletTracer")
	local distance = (to - from).Magnitude
	if not template or distance < 0.5 then
		return
	end

	local tracer = template:Clone()
	local att0 = tracer:FindFirstChild("Att0")
	local att1 = tracer:FindFirstChild("Att1")
	if not (att0 and att1) or not (att0:IsA("Attachment") and att1:IsA("Attachment")) then
		tracer:Destroy()
		return
	end

	att0.Position = Vector3.zero
	att1.Position = Vector3.new(0, 0, -distance)
	tracer.CFrame = CFrame.lookAt(from, to)
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Parent = workspace

	-- The template carries trails whose width dwarfs a hitscan shot; the beam
	-- below is the visual, so drop them.
	for _, descendant in ipairs(tracer:GetDescendants()) do
		if descendant:IsA("Trail") then
			descendant:Destroy()
		end
	end

	-- A Trail needs movement history; both endpoints are positioned in the same
	-- frame here, so use a Beam as the reliable instant-shot visual.
	local beam = Instance.new("Beam")
	beam.Name = "RuntimeTracerBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.FaceCamera = true
	beam.Width0 = 0.035
	beam.Width1 = 0.012
	beam.LightEmission = 0.65
	beam.Brightness = 2
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170))
	beam.Transparency = NumberSequence.new(0.35)
	beam.Segments = 1
	beam.Enabled = true
	beam.Parent = tracer

	-- Fade out: thin and fade rather than blinking away.
	task.spawn(function()
		local steps = 10
		for step = 1, steps do
			task.wait(0.018)
			if not tracer.Parent then
				break
			end
			local alpha = step / steps
			beam.Width0 = 0.035 * (1 - alpha)
			beam.Width1 = 0.012 * (1 - alpha)
			beam.Transparency = NumberSequence.new(0.35 + 0.6 * alpha)
		end
		if tracer.Parent then
			tracer:Destroy()
		end
	end)

	Debris:AddItem(tracer, 0.4)
end

-- // Presentation -------------------------------------------------------------

--- Materials without a dedicated folder reuse the closest authored one.
local MATERIAL_ALIASES = {
	Rock = "Cobblestone",
	Pebble = "Pebble",
	Limestone = "Concrete",
	Pavement = "Concrete",
	Sandstone = "Sand",
	Ground = "Sand",
	Salt = "Sand",
	Snow = "Sand",
	Mud = "Sand",
	Basalt = "Slate",
	CrackedLava = "Slate",
	Glacier = "Ice",
	LeafyGrass = "Grass",
	Carpet = "Fabric",
	Leather = "Fabric",
	Cardboard = "Wood",
	Plaster = "Concrete",
	CeramicTiles = "Marble",
	ClayRoofTiles = "Brick",
	RoofShingles = "WoodPlanks",
	Asphalt = "Concrete",
	Rubber = "Plastic",
	ForceField = "Neon",
	Water = "Concrete",
	Air = "Custom",
}

local function hitEffectFolder(templates: Instance, materialName: string): Instance?
	local direct = templates:FindFirstChild(materialName)
	if direct then
		return direct
	end
	local alias = MATERIAL_ALIASES[materialName]
	if alias then
		local aliased = templates:FindFirstChild(alias)
		if aliased then
			return aliased
		end
	end
	return templates:FindFirstChild("Custom") or templates:FindFirstChild("Concrete")
end

--- Material-aware impact burst: particles + audio from ServerStorage.HitEffects.
function Weapon:_spawnImpact(result: RaycastResult)
	local templates = ServerStorage:FindFirstChild("HitEffects")
	if not templates then
		return
	end

	local materialName = (result.Material and result.Material.Name) or "Plastic"
	local folder = hitEffectFolder(templates, materialName)
	if not folder then
		return
	end

	local surface = result.Instance
	local surfaceColor = (surface and surface:IsA("BasePart")) and surface.Color or nil

	local anchor = Instance.new("Part")
	anchor.Name = "Impact"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.lookAt(
		result.Position + result.Normal * 0.05,
		result.Position + result.Normal * 2
	)
	anchor.Parent = workspace

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			local emitter = child:Clone()

			local countValue = child:FindFirstChild("EmitCount")
			local count = (countValue and countValue:IsA("IntValue") and countValue.Value) or 8

			local colorValue = child:FindFirstChild("PartColor")
			if colorValue and colorValue:IsA("BoolValue") and colorValue.Value and surfaceColor then
				emitter.Color = ColorSequence.new(surfaceColor)
			end

			emitter.Parent = anchor
			emitter:Emit(count)
		end
	end

	-- Audio is played by each client at the exact impact point, so there is no
	-- replication delay between the hit and the sound.
	pcall(function()
		Net.remote("Impact"):FireAllClients(result.Position, folder.Name)
	end)

	Debris:AddItem(anchor, 2)
end

--- Muzzle smoke parented to the gun's own muzzle attachment, so it always
--- leaves the barrel tip regardless of how the gun is held.
function Weapon:_muzzleSmoke(anchor: Attachment?)
	if not anchor then
		return
	end

	local template = ServerStorage:FindFirstChild("MuzzleSmokeTemplate")
	if not template then
		return
	end

	local source = template:FindFirstChildOfClass("Smoke")
		or template:FindFirstChildOfClass("ParticleEmitter")
	if not source then
		return
	end

	local effect = source:Clone()
	effect.Parent = anchor
	if effect:IsA("ParticleEmitter") then
		effect:Emit(8)
	end
	Debris:AddItem(effect, 0.6)
end

--- Every ObjectValue in `Effects` names one anchor (e.g. ShootEffect).
function Weapon:_resolveEffects(): { Instance }
	local out = {}
	local folder = self.tool:FindFirstChild("Effects")
	if not folder then
		return out
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ObjectValue") and child.Value then
			table.insert(out, child.Value)
		end
	end
	return out
end

--- Audio is owned by the client controller (so it is always audible locally
--- and never doubled by replication); this stays as a no-op hook.
function Weapon:_playSound(_name: string)
	return
end

function Weapon:_muzzleFlash()
	local flashTime = self.definition.flashTime
	local lights = {}

	for _, anchor in ipairs(self.effects) do
		if anchor:IsA("Attachment") then
			for _, child in ipairs(anchor:GetDescendants()) do
				if child:IsA("ParticleEmitter") and not CONTINUOUS_EMITTERS[child.Name] then
					child:Emit(1)
				elseif child:IsA("Light") then
					child.Enabled = true
					table.insert(lights, child)
				end
			end
		end
	end

	if #lights > 0 then
		task.delay(flashTime, function()
			for _, light in ipairs(lights) do
				if light.Parent then
					light.Enabled = false
				end
			end
		end)
	end
end

-- // State --------------------------------------------------------------------

function Weapon:_writeAttributes()
	local tool = self.tool
	local definition = self.definition
	tool:SetAttribute("GunSystem", true)
	tool:SetAttribute("WeaponClass", definition.type)
	tool:SetAttribute("WeaponType", definition.weaponType)
	tool:SetAttribute("DisplayName", definition.displayName)
	tool:SetAttribute("Slot", definition.slot)
	tool:SetAttribute("FireMode", definition.fireMode)
	tool:SetAttribute("Ammo", self.ammo)
	tool:SetAttribute("Magazine", definition.magazine)
	tool:SetAttribute("Reloading", false)
	tool:SetAttribute("Equipped", false)
	tool:SetAttribute("Owner", "")
end

function Weapon:_setAmmo(value: number)
	self.ammo = math.clamp(value, 0, self.definition.magazine)
	self.tool:SetAttribute("Ammo", self.ammo)
end

function Weapon:_setReloading(value: boolean)
	self.reloading = value
	self.tool:SetAttribute("Reloading", value)
end

-- // Lifecycle ----------------------------------------------------------------

function Weapon:equip()
	if self.equipped then
		return
	end
	self.equipped = true

	local character = self.character
	if character then
		self.castParams.FilterDescendantsInstances = { character }
	end

	self.tool:SetAttribute("Equipped", true)
	self.tool:SetAttribute("Owner", self.player.Name)
	self:_playSound("equip")
end

function Weapon:unequip()
	if not self.equipped then
		return
	end
	self.equipped = false
	self:_setReloading(false)
	self.tool:SetAttribute("Equipped", false)

	for _, anchor in ipairs(self.effects) do
		for _, light in ipairs(anchor:GetDescendants()) do
			if light:IsA("Light") then
				light.Enabled = false
			end
		end
	end
end

function Weapon:destroy()
	self:unequip()
	self.trove:Destroy()
end

-- // Actions ------------------------------------------------------------------

function Weapon:canFire(): boolean
	return self.equipped and not self.reloading and self.ammo > 0 and os.clock() >= self.nextFireAt
end

function Weapon:fire(direction: Vector3)
	if not self.equipped or self.reloading then
		return
	end
	if self.ammo <= 0 then
		self:_playSound("empty")
		return
	end
	if os.clock() < self.nextFireAt then
		return
	end
	if direction.Magnitude < 0.001 then
		return
	end

	local origin = muzzlePosition(self.tool)
	if not origin then
		return
	end

	self.nextFireAt = os.clock() + self.definition.fireTime
	if not DebugConfig.get("InfiniteAmmo") then
		self:_setAmmo(self.ammo - 1)
	end
	self:_muzzleFlash()
	self:_muzzleSmoke(muzzleAttachment(self.tool))
	self:_playSound("fire")

	if self.behavior then
		self.behavior.VisualizeCasts = DebugConfig.get("VisualizeCasts")
	end

	local spread = math.rad(self.aiming and self.definition.aimSpread or self.definition.spread)
	self.lastOrigin = origin
	for _ = 1, self.definition.pellets do
		local scatter = Vector3.new(
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread,
			(math.random() - 0.5) * spread
		)
		local shotDirection = (direction + scatter).Unit
		self.caster:RaycastFire(origin, shotDirection, self.definition.bulletVelocity, self.behavior)

		-- Tracer is drawn from our own ray, so a shot into thin air still
		-- trails off to max range instead of vanishing.
		local maxRange = self.definition.range
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { self.character, self.tool }
		params.IgnoreWater = true
		local hit = workspace:Raycast(origin, shotDirection * maxRange, params)
		local endpoint = (hit and hit.Position) or (origin + shotDirection * maxRange)
		self:_spawnTracer(origin, endpoint)
	end
end

function Weapon:setAiming(aiming: boolean)
	self.aiming = aiming and self.equipped
end

function Weapon:reload()
	if self.reloading or self.ammo >= self.definition.magazine or not self.equipped then
		return
	end

	self:_setReloading(true)
	local definition = self.definition
	local shell = definition.reloadType == "Shell"

	task.spawn(function()
		repeat
			task.wait(definition.reloadTime)
			if not self.reloading or not self.equipped then
				break
			end
			self:_playSound("reload")
			self:_setAmmo(self.ammo + (shell and 1 or definition.magazine))
		until not shell or self.ammo >= definition.magazine

		self:_setReloading(false)
	end)
end

return Weapon
