--!strict
--[[
	WeaponController (client) — presentation only.

	Owns animations, camera feel, first/third person framing, character
	facing, the bottom-right HUD and input. Damage, ammo and hits stay on
	the server.

	Input: LMB fire (hold = automatic) · RMB aim · R reload · V first person
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.GunSystem.Net)
local Configs = require(ReplicatedStorage.Shared.GunSystem.Configs)
local DebugConfig = require(ReplicatedStorage.Shared.GunSystem.DebugConfig)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ViewModel = require(script.Parent.ViewModel)
local Tuning = require(script.Parent.Tuning)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local DEFAULT_FOV = 70
local MAX_RECOIL_DEGREES = 6
local BASE_SPEED = 16
local AIM_SPEED = 7
local FIRE_SPEED = 10 -- shooting while hip-firing
local AIM_FIRE_SPEED = 4 -- shooting while aimed in
local CAMERA_BIND = "GunSystemCamera"
local ROTATE_BIND = "GunSystemFacing"

local WeaponController = {}

local state = {
	tool = nil :: Tool?,
	definition = nil :: any,
	tracks = nil :: any,
	aiming = false,
	sprinting = false,
	firstPerson = false,
	firing = false,
	fireAccumulator = 0,
	recoilPitch = 0,
	recoilYaw = 0,
	recoilRoll = 0,
	shakePos = Vector3.zero,
	cameraApplied = CFrame.identity,
	strafeRoll = 0,
	bobPhase = 0,
	bobAmount = 0,
	bobRoll = 0,
	aimBlend = 0,
	equipTime = 0,
	aimOffset = Vector3.zero,
	lastFireAt = 0,
	glide = Vector3.zero,
	debugOn = false,
	waist = nil :: any,
	waistBase = nil :: CFrame?,
	waistAttachment = nil :: Attachment?,
	gripBase = nil :: CFrame?,
	torsoKick = 0,
	torsoApplied = CFrame.identity,
	bodyShown = false,
	viewModel = nil :: any,
	viewModelCFrame = CFrame.new(0.02, -1.3, -1.45),
	armJoints = nil :: any,
	armBlend = 0,
}

local root: any = nil          -- root Trove (lifetime of the controller)
local equipTrove: any = nil    -- per-equip Trove (destroyed on unequip)
local hud: ScreenGui? = nil
local labels: any = nil
local reloadFill: Frame? = nil

local function currentWalkSpeed(): number
	-- Aiming and shooting both slow you down; together they slow you most.
	if state.aiming then
		return state.firing and AIM_FIRE_SPEED or AIM_SPEED
	end
	if state.firing then
		return FIRE_SPEED
	end
	return state.sprinting and 24 or BASE_SPEED
end

local function applyMovementSpeed()
	local character = state.tool and state.tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = currentWalkSpeed()
	end
end

-- // HUD ----------------------------------------------------------------------

local function buildHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GunHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -28, 1, -28)
	panel.Size = UDim2.fromOffset(190, 92)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local function text(name: string, size: number, y: number, height: number, color: Color3)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.55
		label.TextSize = size
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.AnchorPoint = Vector2.new(1, 0)
		label.Position = UDim2.new(1, 0, 0, y)
		label.Size = UDim2.new(1, 0, 0, height)
		label.Parent = panel
		return label
	end

	labels = {
		ammo = text("Ammo", 26, 0, 28, Color3.fromRGB(255, 255, 255)),
		weapon = text("Weapon", 13, 30, 16, Color3.fromRGB(225, 225, 225)),
		mode = text("Mode", 10, 48, 12, Color3.fromRGB(150, 200, 255)),
		class = text("Class", 10, 62, 12, Color3.fromRGB(120, 140, 160)),
	}

	local bar = Instance.new("Frame")
	bar.Name = "ReloadBar"
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, 0, 0, 80)
	bar.Size = UDim2.new(0, 120, 0, 3)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bar.BackgroundTransparency = 0.35
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = panel

	reloadFill = Instance.new("Frame")
	reloadFill.Name = "Fill"
	reloadFill.Size = UDim2.fromScale(0, 1)
	reloadFill.BackgroundColor3 = Color3.fromRGB(120, 220, 160)
	reloadFill.BorderSizePixel = 0
	reloadFill.Parent = bar

	gui.Enabled = false
	return gui
end

local function refreshHud()
	local tool = state.tool
	if not tool or not hud or not labels then
		if hud then
			hud.Enabled = false
		end
		return
	end
	hud.Enabled = true
	labels.class.Text = string.upper(tostring(tool:GetAttribute("WeaponClass") or ""))
	labels.weapon.Text = tostring(tool:GetAttribute("DisplayName") or tool.Name)
	labels.ammo.Text = string.format("%d / %d", tool:GetAttribute("Ammo") or 0, tool:GetAttribute("Magazine") or 0)
	labels.mode.Text = string.upper(tostring(tool:GetAttribute("FireMode") or ""))
end

-- // Camera -------------------------------------------------------------------

local function fovTo(value: number, speed: number)
	TweenService:Create(camera, TweenInfo.new(speed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = value,
	}):Play()
end

local function setAiming(value: boolean)
	if state.aiming == value then
		return
	end
	state.aiming = value
	Net.send("Aim", value)

	local definition = state.definition
	if not definition then
		return
	end
	fovTo(value and definition.camera.aimFov or definition.camera.hipFov, 0.16)

	-- First person never shifts the camera: the eye is already the origin.
	state.aimOffset = (value and not state.firstPerson) and Vector3.new(0.7, 0, 0) or Vector3.zero

	-- Aiming locks the stance: slow walk instead of full sprint speed.
	applyMovementSpeed()

	-- aim pose in, carry pose out
	if state.tracks then
		if value then
			state.tracks.aim:Play(0.12)
			state.tracks.hold:Stop(0.12)
		else
			state.tracks.aim:Stop(0.12)
			state.tracks.hold:Play(0.12)
		end
	end

	if showBody then
		showBody()
	end
end

--- Public hook: flips first ↔ third person (used by the V key and by tests).
local setFirstPerson
function WeaponController.toggleView()
	setFirstPerson(not state.firstPerson)
end

--- Read-only debug view of the controller state.
function WeaponController.getState()
	return {
		firstPerson = state.firstPerson,
		tool = state.tool and state.tool.Name,
		hasViewModel = state.viewModel ~= nil,
		tracks = state.tracks ~= nil,
	}
end

-- Test hook: attribute-driven command channel. Attributes bridge contexts, so
-- tooling can drive the live controller even though synthetic input does not
-- reach Studio's play viewport.
player:GetAttributeChangedSignal("GunDebugCommand"):Connect(function()
	local command = player:GetAttribute("GunDebugCommand")
	if type(command) ~= "string" then
		return
	end
	if command == "toggle" then
		setFirstPerson(not state.firstPerson)
	elseif command == "fire" then
		if state.initialised then
			fireOnce()
		end
	elseif command == "aim" then
		setAiming(not state.aiming)
	elseif command == "reload" then
		Net.send("Reload")
	elseif command == "sound" then
		playSound("Fire")
	end
end)

function setFirstPerson(value: boolean)
	state.firstPerson = value
	player.CameraMode = value and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic

	-- Leaving first person leaves the zoom pinned at minimum, which parks the
	-- camera inside the character. Force a real third-person distance.
	if value then
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = math.max(player.CameraMaxZoomDistance, 32)
	else
		player.CameraMaxZoomDistance = math.max(player.CameraMaxZoomDistance, 32)
		player.CameraMinZoomDistance = 10
	end
	state.aimOffset = (state.aiming and not value) and Vector3.new(0.7, 0, 0) or Vector3.zero

	-- Drop the view model immediately; syncViewModel() rebuilds it in first person.
	if state.viewModel then
		state.viewModel:destroy()
		state.viewModel = nil
	end

	local definition = state.definition
	if definition then
		fovTo(definition.camera.hipFov, 0.15)
	end
end

-- // Animation ----------------------------------------------------------------

local function buildTracks(animator: Animator, definition: any)
	local function track(id: string, priority: Enum.AnimationPriority): AnimationTrack
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://" .. id
		local loaded = animator:LoadAnimation(animation)
		-- Explicit priorities: the carry pose owns the body while moving,
		-- shooting/reloading sit above it, movement animations sit below.
		loaded.Priority = priority
		return loaded
	end
	return {
		hold = track(definition.animations.hold, Enum.AnimationPriority.Action),
		shoot = track(definition.animations.shoot, Enum.AnimationPriority.Action2),
		reload = track(definition.animations.reload, Enum.AnimationPriority.Action3),
		aim = track(definition.animations.aim or definition.animations.hold, Enum.AnimationPriority.Action),
		aimShoot = track(definition.animations.aimShoot or definition.animations.shoot, Enum.AnimationPriority.Action2),
	}
end

local function stopTracks(tracks: any)
	if not tracks then
		return
	end
	for _, track in pairs(tracks) do
		if track.IsPlaying then
			track:Stop(0.08)
		end
	end
end

-- // Firing -------------------------------------------------------------------

local function fireDirection(origin: Vector3): Vector3
	local hit = mouse.Hit
	local target = hit and hit.Position or (origin + camera.CFrame.LookVector * 120)
	return target - origin
end

local function muzzlePosition(tool: Tool): Vector3?
	local effects = tool:FindFirstChild("Effects")
	if effects then
		for _, child in ipairs(effects:GetChildren()) do
			if child:IsA("ObjectValue") and child.Value and child.Value:IsA("Attachment") then
				return child.Value.WorldPosition
			end
		end
	end

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

local function playSound(name: string)
	local tool = state.tool
	local sfx = tool and tool:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function fireOnce()
	local tool = state.tool
	local definition = state.definition
	if not (tool and definition) then
		return
	end
	-- Keep the client cadence identical to the server cadence.  The old 0.5x
	-- guard let the client play recoil/audio twice as often as the server could
	-- accept shots, which felt like delayed or dropped firing under load.
	if os.clock() - state.lastFireAt < definition.fireTime then
		return
	end
	state.lastFireAt = os.clock()

	local origin = muzzlePosition(tool)
	if not origin then
		return
	end
	if (tool:GetAttribute("Ammo") or 0) <= 0 then
		playSound("Empty")
		Net.send("Reload")
		return
	end
	if tool:GetAttribute("Reloading") then
		return
	end

	Net.send("Fire", fireDirection(origin))
	playSound("Fire")

	if state.tracks then
		if state.aiming and state.tracks.aimShoot then
			state.tracks.aimShoot:Play(0.03, 1, 1)
		else
			state.tracks.shoot:Play(0.03, 1, 1)
		end
	end

	-- camera kick: smaller in first person, clamped so rapid fire cannot spin
	local scale = state.firstPerson and 0.5 or 1
	state.recoilPitch = math.clamp(
		state.recoilPitch + definition.camera.kick * 0.15 * scale,
		0,
		MAX_RECOIL_DEGREES * scale
	)
	state.recoilYaw += (math.random() - 0.5) * definition.camera.kick * 0.06 * scale
	state.recoilRoll += (math.random() - 0.5) * definition.camera.shake * 0.7 * scale
	state.shakePos += Vector3.new(
		(math.random() - 0.5) * definition.camera.shake * 0.1,
		(math.random() - 0.5) * definition.camera.shake * 0.1,
		definition.camera.shake * 0.06
	) * scale

	-- visible body recoil: the torso absorbs the shot and eases back
	state.torsoKick += 0.05 * scale
end

-- // Character facing ----------------------------------------------------------

local function stepFacing(dt: number)
	local tool = state.tool
	local character = tool and tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local part = humanoid and humanoid.RootPart
	if not (humanoid and part) then
		return
	end

	-- Third person: the body turns to the aim only while shooting (plus a short
	-- follow-through), instead of tracking the mouse every frame.
	local recentlyFired = os.clock() - state.lastFireAt < 0.6
	if not (state.firing or recentlyFired) then
		humanoid.AutoRotate = true
		return
	end
	humanoid.AutoRotate = false

	-- Face the actual aim point (the mouse), not merely the camera direction,
	-- so the body lines up with where the bullet will land.
	local aimPoint = mouse.Hit and mouse.Hit.Position
	local look
	if aimPoint then
		local chest = part.Position + Vector3.new(0, 1.5, 0)
		look = (aimPoint - chest) * Vector3.new(1, 0, 1)
	end
	if not look or look.Magnitude < 0.05 then
		look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	if look.Magnitude < 0.05 then
		return
	end

	local target = CFrame.lookAt(part.Position, part.Position + look.Unit)
	local turnSpeed = state.aiming and 18 or 10
	part.CFrame = part.CFrame:Lerp(target, math.min(dt * turnSpeed, 1))
end

-- // Per-frame camera ---------------------------------------------------------

-- View state is enforced every frame from `state.firstPerson` (single source of
-- truth), so toggling can never leave mismatched camera/body/view-model state.
local showBody
local syncViewModel

local HIP_OFFSET = Vector3.new(0.02, -1.3, -1.45)
local AIM_OFFSET = Vector3.new(0.0, -1.15, -1.2)
-- No manual rotation: the clone mirrors the real pose exactly.
local HIP_ROTATION = CFrame.identity
local AIM_ROTATION = CFrame.identity
--- Drives the first-person view model: visibility, creation and placement.
local function stepViewModel(dt: number)
	-- camera mode follows the flag, not the other way round
	local wantCamera = state.firstPerson and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	if player.CameraMode ~= wantCamera then
		player.CameraMode = wantCamera
	end

	showBody()
	syncViewModel()

	local viewModel = state.viewModel
	if not viewModel then
		return
	end

	local character = state.tool and state.tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local speed = 0
	if humanoid and humanoid.RootPart then
		speed = humanoid.RootPart.AssemblyLinearVelocity.Magnitude
	end
	local bob = math.sin(state.bobPhase) * 0.02 * math.clamp(speed / BASE_SPEED, 0, 1)

	-- // Smooth presentation ---------------------------------------------------
	-- Equip: the rig rises into frame instead of popping in.
	state.equipTime += dt
	local equipAlpha = math.clamp(state.equipTime / 0.32, 0, 1)
	local equipEase = equipAlpha * equipAlpha * (3 - 2 * equipAlpha)

	-- Aim blend: eases the rig towards centre while aiming.
	local aimTarget = state.aiming and 1 or 0
	state.aimBlend += (aimTarget - state.aimBlend) * math.min(dt * 9, 1)

	-- Bob: speed-driven, eased in and out, disabled while aiming.
	local speedFactor = math.clamp(speed / BASE_SPEED, 0, 1)
	local bobTarget = (speed > 3 and not state.aiming) and speedFactor or 0
	state.bobAmount += (bobTarget - state.bobAmount) * math.min(dt * 5, 1)
	state.bobPhase += dt * (5.5 + speed * 0.45) * (0.4 + state.bobAmount)

	local bobY = math.sin(state.bobPhase * 2) * 0.016 * state.bobAmount
	local bobX = math.cos(state.bobPhase) * 0.011 * state.bobAmount
	local bobRoll = math.cos(state.bobPhase) * math.rad(1.2) * state.bobAmount

	-- Live placement from the F2 tuning panel (config values seed it).
	local base = Tuning.offsetCFrame()
	local aimShift = CFrame.new(0, 0.015 * state.aimBlend, 0.05 * state.aimBlend)
	local riseOffset = -0.85 * (1 - equipEase)
	local target = base
		* aimShift
		* CFrame.new(bobX, bobY + riseOffset, 0)
		* CFrame.Angles(math.rad(6 * (1 - equipEase)), 0, bobRoll)

	state.viewModelCFrame = target

	viewModel:update(camera.CFrame, state.viewModelCFrame)
end

--- Pitches the torso with aim (up/down) and absorbs a kick per shot.
-- View model is off: first person uses the real rig's arms, posed by
-- offsetting the shoulder joint attachments (the animator owns Transform,
-- but attachment frames are ours to move).
local USE_VIEW_MODEL = true

local FPS_PARTS = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}

-- First person hides only what the camera would clip through; the torso and
-- legs stay visible so you can look down and see your own body.
local FIRST_PERSON_HIDE_PARTS = {
	Head = true,
	-- the camera sits at neck height, i.e. inside the upper torso; hiding it is
	-- what stops the "giant shirt" filling the screen when you look down
	UpperTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}

--- First person renders the real torso/legs plus the cloned arms and weapon.
function showBody()
	local tool = state.tool
	local character = tool and tool.Parent
	if not character then
		return
	end

	local firstPerson = state.firstPerson
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Tool parts are authored: the Handle is the invisible grip block and
			-- the rest is the gun. LocalTransparencyModifier only — writing
			-- Transparency would replicate and hide the gun for everyone else.
			if part:FindFirstAncestorOfClass("Tool") then
				part.LocalTransparencyModifier = firstPerson and 1 or 0
				continue
			end

			-- Accessories (hats, ears) belong to the third-person look only; in
			-- first person they would poke into the camera. Local only.
			if part:FindFirstAncestorOfClass("Accessory") then
				part.LocalTransparencyModifier = firstPerson and 1 or 0
				continue
			end
			-- First person hides only the head, the arms (the view model
			-- supplies them) and the live tool; torso and legs stay so you can
			-- look down and see your own body.
			local visible = not firstPerson
			if firstPerson then
				visible = not FIRST_PERSON_HIDE_PARTS[part.Name]
					and part:FindFirstAncestorOfClass("Tool") == nil
			end

			-- Orphaned gun handles (welded leftovers with no Tool parent) must
			-- never render. Accessory handles are their hat/ears mesh — leave
			-- those alone.
			if part.Name == "Handle"
				and part:FindFirstAncestorOfClass("Tool") == nil
				and part:FindFirstAncestorOfClass("Accessory") == nil
			then
				visible = false
			end

			-- The root part is a 2x2x1 block at the torso centre and the camera
			-- sits inside it: it must never be made visible, in any mode.
			if part.Name == "HumanoidRootPart" then
				visible = false
			end
			local target = visible and 0 or 1
			-- LocalTransparencyModifier is per-client. `Transparency` replicates,
			-- so writing it here would hide your body on everyone else's screen.
			if part.LocalTransparencyModifier ~= target then
				part.LocalTransparencyModifier = target
			end
		end
	end
end

--- Creates the view model once per equipped tool and keeps it alive.
--- (Recreating it per frame was resetting the pose every render step, which
--- is why the arms looked frozen.)
function syncViewModel()
	local tool = state.tool
	local character = tool and tool.Parent
	local wanted = USE_VIEW_MODEL and state.firstPerson and tool ~= nil and character ~= nil

	if not wanted then
		if state.viewModel then
			state.viewModel:destroy()
			state.viewModel = nil
		end
		return
	end

	if state.viewModel and state.viewModel.tool ~= tool then
		state.viewModel:destroy()
		state.viewModel = nil
	end

	if not state.viewModel then
		state.viewModel = ViewModel.new(character, tool)
		state.equipTime = 0 -- play the rise from the bottom on every equip
	end
end

local function stepTorso(dt: number)
	local waist = state.waist	if not waist or not waist.Parent then
		return
	end

	local look = camera.CFrame.LookVector
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local target = math.clamp(-pitch * 0.5, -0.42, 0.42)
	state.torsoKick *= math.exp(-dt * 10)

	-- real vertical travel while running, applied to the spine joint
	local speed = 0
	local character = state.tool and state.tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart then
		speed = humanoid.RootPart.AssemblyLinearVelocity.Magnitude
	end
	local bob = math.sin(state.bobPhase) * 0.05 * math.clamp(speed / BASE_SPEED, 0, 1)

	local pose = CFrame.new(0, bob, 0) * CFrame.Angles(target + state.torsoKick, 0, 0)

	if waist:IsA("Motor6D") and state.waistBase then
		waist.C0 = state.waistBase * pose
	else
		-- AnimationConstraint: the animator writes Transform each frame, so
		-- strip last frame's offset, then re-apply — animations stay intact
		-- and the joint still moves.
		local current = waist.Transform
		local base = current * state.torsoApplied:Inverse()
		waist.Transform = base * pose
		state.torsoApplied = pose
	end

	local tool = state.tool
	if tool and state.gripBase then
		tool.Grip = state.gripBase * CFrame.Angles(math.clamp(target * 0.6, -0.3, 0.3), 0, 0)
	end
end

local function stepCamera(dt: number)
	if state.cameraApplied ~= CFrame.identity then
		camera.CFrame = camera.CFrame * state.cameraApplied:Inverse()
		state.cameraApplied = CFrame.identity
	end

	local definition = state.definition
	if not definition then
		return
	end

	local tool = state.tool
	local character = tool and tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local speed = 0
	local strafe = 0
	if humanoid and humanoid.RootPart then
		speed = humanoid.RootPart.AssemblyLinearVelocity.Magnitude
		if humanoid.MoveDirection.Magnitude > 0.05 then
			strafe = -humanoid.MoveDirection:Dot(camera.CFrame.RightVector)
		end

		-- Smooth slowdown: keep a decaying slide for a few frames after the
		-- keys are released instead of stopping dead. Disabled while aiming
		-- because aiming is a deliberate locked stance.
		if humanoid.MoveDirection.Magnitude > 0.08 and not state.aiming then
			state.glide = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
		elseif state.glide.Magnitude > 0.01 and speed > 1 then
			state.glide *= math.max(0, 1 - dt * 9)
			humanoid:Move(state.glide * 0.45, false)
		else
			state.glide = Vector3.zero
		end
	end

	-- strafe tilt is third-person only: rolling the eye in first person reads as drift.
	-- Scaled down so the scene stays readable while strafing.
	local targetRoll = state.firstPerson and 0 or strafe * math.rad(definition.camera.strafeTilt) * 0.55
	state.strafeRoll += (targetRoll - state.strafeRoll) * math.min(dt * 7, 1)

	if humanoid then
		-- Running bob: two-axis sine plus a matching roll, eased by speed and
		-- disabled while aiming so the sight picture stays steady.
		local bobAmount = state.bobAmount
		local bobY = math.sin(state.bobPhase * 2) * 0.04 * bobAmount
		local bobX = math.cos(state.bobPhase) * 0.025 * bobAmount
		local rollBob = math.cos(state.bobPhase) * math.rad(0.5) * bobAmount
		humanoid.CameraOffset = state.aimOffset + Vector3.new(bobX, bobY, 0)
		state.bobRoll = rollBob
	end

	-- smooth recovery of the kick
	local decay = math.exp(-definition.camera.recovery * dt)
	state.recoilPitch *= decay
	state.recoilYaw *= decay
	state.recoilRoll *= decay
	state.shakePos *= math.exp(-dt * 14)

	local pitch = math.rad(state.recoilPitch)
	local yaw = math.rad(state.recoilYaw)
	local roll = state.strafeRoll + math.rad(state.recoilRoll) + (state.bobRoll or 0)

	-- Camera kick belongs to first person only: writing the CFrame in third
	-- person fights the default camera and pins it inside the character.
	if state.firstPerson then
		state.cameraApplied = CFrame.Angles(pitch, yaw, roll) * CFrame.new(state.shakePos)
		camera.CFrame = camera.CFrame * state.cameraApplied
	else
		state.cameraApplied = CFrame.identity
	end
end

--- Raises the real arms into view by rotating the shoulder joints on top of
--- whatever the animator is playing. Attachment frames are not animation-owned,
--- so this offset survives every frame.
local function stepArms(dt: number)
	if USE_VIEW_MODEL then
		return -- the view model owns the arms in this mode
	end
	local tool = state.tool
	local character = tool and tool.Parent
	if not character then
		return
	end

	if not state.armJoints then
		state.armJoints = {}
		for _, name in ipairs({ "RightShoulder", "LeftShoulder" }) do
			local joint = character:FindFirstChild(name, true)
			local attachment = joint and (joint :: any).Attachment1
			if joint and attachment and attachment:IsA("Attachment") then
				table.insert(state.armJoints, {
					attachment = attachment,
					base = attachment.CFrame,
					yaw = 0,
				})
			end
		end
	end

	if #state.armJoints == 0 then
		return
	end

	state.armBlend += ((state.aiming and 1.15 or 0.95) - state.armBlend) * math.min(dt * 8, 1)
	local kick = math.rad(state.recoilPitch) * 0.35

	for _, entry in ipairs(state.armJoints) do
		if entry.attachment.Parent then
			entry.attachment.CFrame = entry.base * CFrame.Angles(-state.armBlend + kick, entry.yaw, 0)
		end
	end
end

local function stepFiring(dt: number)
	local tool = state.tool
	local definition = state.definition
	if not (tool and definition and state.firing) then
		state.fireAccumulator = 0
		return
	end
	if tool:GetAttribute("FireMode") ~= "Auto" then
		return
	end
	state.fireAccumulator += dt
	-- Preserve fractional time so a slow frame does not permanently shift the
	-- automatic-fire rhythm.  Cap catch-up to one shot per frame; the server is
	-- still authoritative and rejects anything faster than fireTime.
	if state.fireAccumulator >= definition.fireTime then
		state.fireAccumulator -= definition.fireTime
		fireOnce()
	end
end

-- // Equip / unequip -----------------------------------------------------------

local function teardown()
	if state.viewModel then
		state.viewModel:destroy()
		state.viewModel = nil
	end

	-- restore the real arm joints
	if state.armJoints then
		for _, entry in ipairs(state.armJoints) do
			if entry.attachment and entry.attachment.Parent then
				entry.attachment.CFrame = entry.base
			end
		end
		state.armJoints = nil
	end
	state.armBlend = 0

	state.firing = false
	state.sprinting = false
	state.aiming = false
	-- Never leak a sprint/aim speed into the next character or weapon.
	local character = state.tool and state.tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_SPEED
	end
	state.recoilPitch = 0
	state.recoilYaw = 0
	state.recoilRoll = 0
	state.shakePos = Vector3.zero
	state.strafeRoll = 0
	state.aimOffset = Vector3.zero
	state.glide = Vector3.zero

	stopTracks(state.tracks)
	state.tracks = nil

	-- release the spine joint so the idle/animation poses take over again
	if state.waist and state.waist.Parent then
		if state.waist:IsA("Motor6D") and state.waistBase then
			state.waist.C0 = state.waistBase
		elseif state.waist:IsA("AnimationConstraint") then
			state.waist.Transform = CFrame.identity
		end
	end
	state.waist = nil
	state.waistAttachment = nil
	state.waistBase = nil
	state.torsoKick = 0

	if state.tool and state.gripBase then
		state.tool.Grip = state.gripBase
	end
	state.gripBase = nil
	state.torsoApplied = CFrame.identity

	state.tool = nil
	state.definition = nil

	if equipTrove then
		equipTrove:Destroy()
		equipTrove = nil
	end

	if hud then
		hud.Enabled = false
	end
	if reloadFill and reloadFill.Parent then
		reloadFill.Parent.Visible = false
	end

	fovTo(DEFAULT_FOV, 0.18)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
		humanoid.WalkSpeed = BASE_SPEED
	end
end

local function setup(tool: Tool, definition: any)
	teardown()

	local character = tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (humanoid and animator) then
		return
	end

	-- R15 spine joint: lets the torso pitch with aim and absorb recoil.
	-- Modern rigs expose Waist as an AnimationConstraint (Transform-based);
	-- older ones use a Motor6D (C0-based), so support both.
	local upperTorso = character:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	state.waist = nil
	state.waistBase = nil
	state.waistAttachment = nil
	if waist then
		if waist:IsA("Motor6D") then
			state.waist = waist
			state.waistBase = waist.C0
		elseif waist:IsA("AnimationConstraint") then
			-- The animator owns Transform, so the offset rides on the joint's
			-- attachment instead: that survives every animation frame.
			local attachment = waist.Attachment1
			if attachment and attachment:IsA("Attachment") then
				state.waist = waist
				state.waistAttachment = attachment
				state.waistBase = attachment.CFrame
			end
		end
	end

	state.tool = tool
	state.definition = definition
	state.gripBase = tool.Grip
	state.equipTime = 0
	state.bobAmount = 0
	state.aimBlend = 0

	-- Each weapon owns its view-model framing; seeded from its config once.
	Tuning.useProfile(tool.Name, definition.camera.tuning)
	playSound("Equip")
	state.tracks = buildTracks(animator, definition)
	state.tracks.hold:Play(0.15)
	tool:SetAttribute("LocalEquipped", true)

	refreshHud()
	fovTo(definition.camera.hipFov, 0.2)

	equipTrove = root:Extend()

	equipTrove:Add(tool:GetAttributeChangedSignal("Ammo"):Connect(function()
		refreshHud()
		if (tool:GetAttribute("Ammo") or 0) <= 0 and not tool:GetAttribute("Reloading") then
			Net.send("Reload")
		end
	end))
	equipTrove:Add(tool:GetAttributeChangedSignal("Magazine"):Connect(refreshHud))
	equipTrove:Add(tool:GetAttributeChangedSignal("DisplayName"):Connect(refreshHud))
	equipTrove:Add(tool:GetAttributeChangedSignal("FireMode"):Connect(refreshHud))
	equipTrove:Add(tool:GetAttributeChangedSignal("WeaponClass"):Connect(refreshHud))
	equipTrove:Add(tool:GetAttributeChangedSignal("Reloading"):Connect(function()
		local reloading = tool:GetAttribute("Reloading")
		if state.tracks then
			if reloading then
				playSound("Reload")
				state.tracks.reload:Play(0.1)
			else
				state.tracks.reload:Stop(0.12)
			end
		end
		if reloadFill and reloadFill.Parent then
			local bar = reloadFill.Parent :: Frame
			bar.Visible = reloading
			if reloading then
				reloadFill.Size = UDim2.fromScale(0, 1)
				TweenService:Create(reloadFill, TweenInfo.new(definition.reloadTime, Enum.EasingStyle.Linear), {
					Size = UDim2.fromScale(1, 1),
				}):Play()
			end
		end
	end))

	-- landing dip: weight without touching gameplay
	equipTrove:Add(humanoid.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Landed then
			state.shakePos -= Vector3.new(0, 0.14, 0)
			state.recoilPitch = math.max(state.recoilPitch - 1.1, 0)
		end
	end))

	-- the tool leaving the character is the one true unequip signal
	equipTrove:Add(tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(character) then
			teardown()
		end
	end))
	equipTrove:Add(tool.Unequipped:Connect(function()
		teardown()
	end))

	equipTrove:Add(function()
		stopTracks(state.tracks)
	end)
end

-- // Input --------------------------------------------------------------------

local function bindInput()
	root:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if state.tool == nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			state.firing = true
			applyMovementSpeed()
			fireOnce()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			setAiming(true)
		elseif input.KeyCode == Enum.KeyCode.R then
			Net.send("Reload")
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			state.sprinting = true
			applyMovementSpeed()
		elseif input.KeyCode == Enum.KeyCode.V then
			WeaponController.toggleView()
		end
	end))

	root:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.firing = false
			applyMovementSpeed()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			setAiming(false)
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			state.sprinting = false
			applyMovementSpeed()
		end
	end))
end

-- // Bootstrap ----------------------------------------------------------------

function WeaponController.start()
	hud = buildHud()
	root = Trove.new()

	root:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
		stepFiring(dt)
		stepCamera(dt)
		stepViewModel(dt)
		stepTorso(dt)
		stepArms(dt)
	end)
	root:BindToRenderStep(ROTATE_BIND, Enum.RenderPriority.Character.Value, function(dt)
		stepFacing(dt)
	end)

	bindInput()

	-- Players start in first person; V switches to third at any time.
	setFirstPerson(true)

	local function watchCharacter(character: Model)
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("GunSystem") then
				local definition = Configs.get(child.Name)
				if definition then
					setup(child, definition)
				end
			end
		end
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child:GetAttribute("GunSystem") then
				local definition = Configs.get(child.Name)
				if definition then
					setup(child, definition)
				end
			end
		end)
	end

	local character = player.Character or player.CharacterAdded:Wait()
	watchCharacter(character)
	player.CharacterAdded:Connect(watchCharacter)

	-- Impact audio is played here, at the hit point, the moment the hit arrives:
	-- no server round-trip, so no perceptible delay.
	Net.remote("Impact").OnClientEvent:Connect(function(position: any, materialName: any)
		if typeof(position) ~= "Vector3" then
			return
		end

		local soundsRoot = ReplicatedStorage:FindFirstChild("HitSounds")
		local folder = soundsRoot and (soundsRoot:FindFirstChild(tostring(materialName)) or soundsRoot:FindFirstChild("Custom"))
		if not folder then
			return
		end

		local pool = {}
		for _, sound in ipairs(folder:GetChildren()) do
			if sound:IsA("Sound") and sound.SoundId ~= "" then
				table.insert(pool, sound)
			end
		end
		if #pool == 0 then
			return
		end

		local part = Instance.new("Part")
		part.Name = "ImpactSound"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.CFrame = CFrame.new(position)
		part.Parent = workspace

		local sound = pool[math.random(#pool)]:Clone()
		sound.RollOffMaxDistance = 70
		sound.Parent = part
		sound:Play()

		game:GetService("Debris"):AddItem(part, 2)
	end)

	Net.remote("Hit").OnClientEvent:Connect(function(isHead: boolean)
		refreshHud()
		if labels and isHead then
			labels.ammo.TextColor3 = Color3.fromRGB(255, 130, 130)
			task.delay(0.12, function()
				if labels then
					labels.ammo.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end)
		end
	end)
end

-- Tooling entry points onto the live instance.
WeaponController.setAiming = setAiming
WeaponController.setFiring = function(value: boolean)
	state.firing = value
	applyMovementSpeed()
end
WeaponController.fire = fireOnce
WeaponController.reload = function()
	Net.send("Reload")
end

return WeaponController
