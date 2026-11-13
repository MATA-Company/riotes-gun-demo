--!strict
--[[
	ViewModel — true first-person arms rig at original scale.

	Build: clone the whole character (1:1, no scaling), remove accessories and
	scripts, keep only the two arms visible, anchor the root to the camera.

	Pose: nothing is hand-authored. The clone mirrors the live joint values of
	the real character every frame, so the arms move exactly like the world rig
	(hold / shoot / reload), which is why the motion stays fluid instead of
	feeling scaled or detached.

	The real character's arms are hidden in first person, so you never see two
	pairs of arms.

	API
		ViewModel.new(character, tool)
		viewModel:update(cameraCFrame, offsetCFrame)
		viewModel:destroy()
]]

local ARM_PARTS = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}

--- Joint chain that carries the arm pose.
local MIRROR_JOINTS = {
	"Waist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
}

local CLEANUP_CLASSES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	Accessory = true,
	Sound = true,
	ParticleEmitter = true,
	Trail = true,
	Highlight = true,
}

local ViewModel = {}
ViewModel.__index = ViewModel

local Tuning = require(script.Parent.Tuning)

local function findJoint(model: Model, name: string): Instance?
	return model:FindFirstChild(name, true)
end

function ViewModel.new(character: Model, tool: Tool?)
	local self = setmetatable({}, ViewModel)
	self.alive = true
	self.tool = tool
	self.joints = {}

	if not character.Archivable then
		character.Archivable = true
	end
	local clone = character:Clone()
	if not clone then
		self.alive = false
		return self
	end
	clone.Name = "GunViewModel"
	self.model = clone

	for _, descendant in ipairs(clone:GetDescendants()) do
		if CLEANUP_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = false
		end
	end

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Keep the Humanoid: Shirt/Pants only render through one. It cannot
		-- move anything because the root is anchored below.
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		clone:Destroy()
		self.alive = false
		return self
	end
	self.root = root
	root.Anchored = true
	clone.PrimaryPart = root
	clone.Parent = workspace

	-- Cache the joint pairs we mirror; no scaling, no manual pose.
	for _, name in ipairs(MIRROR_JOINTS) do
		local source = findJoint(character, name)
		local target = findJoint(clone, name)
		if source and target then
			table.insert(self.joints, { name = name, source = source, target = target })
		end
	end

	-- The rig equips its own copy of the gun, so the grip weld is native to
	-- the view-model character instead of being copied from the world rig.
	local toolModel = clone:FindFirstChildOfClass("Tool")
	if toolModel then
		toolModel:Destroy()
	end
	self:_equipNative(tool)

	self:_applyVisibility()

	return self
end

--- Gives the view-model rig its own Tool, welded with the rig's own RightGrip.
--- (Humanoid:EquipTool silently fails on a detached clone, so the weld is
--- created explicitly — same C0/C1 the engine uses.)
function ViewModel:_equipNative(sourceTool: Tool?)
	local hand = self.model:FindFirstChild("RightHand", true)
	if not (hand and hand:IsA("BasePart") and sourceTool) then
		return
	end

	local toolClone = sourceTool:Clone()
	for _, descendant in ipairs(toolClone:GetDescendants()) do
		if CLEANUP_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		end
	end
	toolClone.Parent = self.model

	local handle = toolClone:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	handle.CFrame = hand.CFrame * toolClone.Grip
	local weld = Instance.new("Weld")
	weld.Name = "RightGrip"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = toolClone.Grip
	weld.C1 = CFrame.new()
	weld.Parent = hand

	self.toolModel = toolClone
	self.handle = handle
	self.weld = weld
	self.grip = toolClone.Grip
	self.appliedScale = 1
end

--- Only the arms and the gun render; everything else on the clone is hidden.
--- Also collects the parts so collision can be re-asserted every frame: the
--- kept Humanoid re-enables CanCollide on its limbs, which would otherwise
--- make the player collide with their own view model.
function ViewModel:_applyVisibility()
	self.parts = {}
	for _, part in ipairs(self.model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			table.insert(self.parts, part)

			local isToolPart = part:FindFirstAncestorOfClass("Tool") ~= nil
			local visible = ARM_PARTS[part.Name] == true or isToolPart

			-- Tool parts: the Handle is the invisible grip block, the rest is the
			-- gun body. Forcing 0 on everything made the red handle render.
			local transparency
			if isToolPart then
				transparency = (part.Name == "Handle") and 1 or 0
			else
				transparency = visible and 0 or 1
			end

			part.LocalTransparencyModifier = visible and 0 or 1
			part.Transparency = transparency
			-- LocalTransparencyModifier can be overridden by clothing/accessory
			-- rendering on cloned rigs. Hard-hide every non-arm body part too so
			-- the first-person viewport never shows the torso, head, or legs.
			if not visible then
				part.Transparency = 1
			end
		end
	end
end

--- Places the clone at the camera and mirrors the live arm pose.
function ViewModel:update(cameraCFrame: CFrame, offsetCFrame: CFrame)
	if not self.alive or not self.root or not self.root.Parent then
		return
	end

	self.root.CFrame = cameraCFrame * offsetCFrame

	-- Re-assert no-collision: the rig's Humanoid re-enables it on its limbs.
	local parts = self.parts
	if parts then
		for index = 1, #parts do
			local part = parts[index]
			if part.Parent and part.CanCollide then
				part.CanCollide = false
			end
		end
	end

	-- Gun-local offset (forward/back, sideways, up/down) applied to the weld.
	if self.weld and self.weld.Parent and self.grip then
		self.weld.C0 = self.grip * Tuning.gunOffsetCFrame()
	end

	-- Live rig scale.
	local wantedScale = Tuning.values.scale
	if self.model.ScaleTo and math.abs(wantedScale - self.appliedScale) > 0.001 then
		pcall(function()
			self.model:ScaleTo(wantedScale)
		end)
		self.appliedScale = wantedScale
	end

	for _, pair in ipairs(self.joints) do
		local source = pair.source
		local target = pair.target
		local offset = pair.name == "RightWrist" and Tuning.wristCFrame() or CFrame.identity
		if source:IsA("AnimationConstraint") and target:IsA("AnimationConstraint") then
			target.Transform = source.Transform * offset
		elseif source:IsA("Motor6D") and target:IsA("Motor6D") then
			target.C0 = source.C0
			target.C1 = source.C1
		end
	end
end

function ViewModel:destroy()
	self.alive = false
	if self.model then
		self.model:Destroy()
	end
	self.joints = {}
end

return ViewModel
