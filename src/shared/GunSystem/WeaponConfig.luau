--!strict
--[[
	WeaponConfig — resolves type defaults + per-gun overrides, validates, freezes.

	Resolution order for every field:  gun config  >  weapon type  >  defaults.
	That is what lets a Shotgun be one line of data and still behave correctly.
]]

local Enums = require(script.Parent.Enums)
local AnimationSets = require(script.Parent.AnimationSets)
local WeaponTypes = require(script.Parent.WeaponTypes)

local DEFAULTS = {
	displayName = nil,
	weaponType = "Gun",
	slot = Enums.Slot.Primary,
	fireMode = Enums.FireMode.Semi,
	reloadType = Enums.ReloadType.Mag,
	animationSet = "Default",
	pellets = 1,

	damage = 20,
	headshotMultiplier = 2,
	range = 500,
	bulletVelocity = 2000,
	fireTime = 0.2,
	reloadTime = 1.6,
	magazine = 12,
	startingAmmo = nil,
	spread = 1,
	aimSpread = 0.35,
	flashTime = 0.05,

	camera = {
		kick = 2,
		recovery = 10,
		shake = 0.2,
		hipFov = 70,
		aimFov = 52,
		strafeTilt = 2.5,
		sway = 0.35,
		viewModelHip = Vector3.new(0.7, -1.5, -2.0),
		viewModelAim = Vector3.new(0.05, -1.3, -1.65),
		-- per-weapon view model tuning (position, rotation, wrist, gun, scale)
		tuning = {
			px = 0.32, py = -1.70, pz = -1.20,
			rx = 0, ry = 0, rz = 0,
			wx = -95, wy = -5, wz = 0,
			gx = -0.05, gy = 0.15, gz = -0.35,
			scale = 1.25,
		},
	},
	sounds = { fire = "", reload = "", equip = "", empty = "" },
}

local function pickField(gun, typeDefaults, field: string)
	local value = gun[field]
	if value ~= nil then
		return value
	end
	return typeDefaults[field] ~= nil and typeDefaults[field] or DEFAULTS[field]
end

local function assertNumber(value, field: string, minimum)
	if typeof(value) ~= "number" or value ~= value then
		error(string.format("WeaponConfig: field %q must be a number", field), 3)
	end
	if value < minimum then
		error(string.format("WeaponConfig: field %q must be >= %s", field, tostring(minimum)), 3)
	end
	return value
end

local function assertEnum(value, field: string, allowed: { string }): string
	for _, candidate in ipairs(allowed) do
		if value == candidate then
			return value
		end
	end
	error(string.format("WeaponConfig: field %q must be one of %s", field, table.concat(allowed, ", ")), 3)
end

local WeaponConfig = {}

function WeaponConfig.build(raw: { [string]: any })
	local name = raw.name or error("WeaponConfig: name is required", 2)

	local typeName = raw.type or "Rifle"
	local typeDefaults = WeaponTypes[typeName]
	if not typeDefaults then
		error(string.format("WeaponConfig: unknown weapon type %q", tostring(typeName)), 2)
	end

	local animationSet = pickField(raw, typeDefaults, "animationSet")
	local set = AnimationSets[animationSet]
	if not set then
		error(string.format("WeaponConfig: unknown animationSet %q", tostring(animationSet)), 2)
	end

	local gunCamera = raw.camera or {}
	local typeCamera = typeDefaults.camera or {}
	local gunSounds = raw.sounds or {}

	local magazine = assertNumber(pickField(raw, typeDefaults, "magazine"), "magazine", 1)

	local definition = {
		name = name,
		type = typeName,
		displayName = raw.displayName or name,
		weaponType = pickField(raw, typeDefaults, "weaponType"),
		slot = assertEnum(pickField(raw, typeDefaults, "slot"), "slot", { "Primary", "Secondary" }),
		fireMode = assertEnum(pickField(raw, typeDefaults, "fireMode"), "fireMode", Enums.FireModeValues),
		reloadType = assertEnum(pickField(raw, typeDefaults, "reloadType"), "reloadType", Enums.ReloadTypeValues),
		animationSet = animationSet,
		animations = set,
		pellets = assertNumber(pickField(raw, typeDefaults, "pellets"), "pellets", 1),

		damage = assertNumber(pickField(raw, typeDefaults, "damage"), "damage", 0),
		headshotMultiplier = assertNumber(pickField(raw, typeDefaults, "headshotMultiplier"), "headshotMultiplier", 1),
		range = assertNumber(pickField(raw, typeDefaults, "range"), "range", 1),
		bulletVelocity = assertNumber(pickField(raw, typeDefaults, "bulletVelocity"), "bulletVelocity", 1),
		fireTime = assertNumber(pickField(raw, typeDefaults, "fireTime"), "fireTime", 0.01),
		reloadTime = assertNumber(pickField(raw, typeDefaults, "reloadTime"), "reloadTime", 0.01),
		magazine = magazine,
		startingAmmo = assertNumber(raw.startingAmmo or magazine, "startingAmmo", 0),
		spread = assertNumber(pickField(raw, typeDefaults, "spread"), "spread", 0),
		aimSpread = assertNumber(pickField(raw, typeDefaults, "aimSpread"), "aimSpread", 0),
		flashTime = assertNumber(pickField(raw, typeDefaults, "flashTime"), "flashTime", 0),

		camera = {
			kick = assertNumber(gunCamera.kick or typeCamera.kick or DEFAULTS.camera.kick, "camera.kick", 0),
			recovery = assertNumber(gunCamera.recovery or typeCamera.recovery or DEFAULTS.camera.recovery, "camera.recovery", 1),
			shake = assertNumber(gunCamera.shake or typeCamera.shake or DEFAULTS.camera.shake, "camera.shake", 0),
			hipFov = assertNumber(gunCamera.hipFov or DEFAULTS.camera.hipFov, "camera.hipFov", 1),
			aimFov = assertNumber(gunCamera.aimFov or DEFAULTS.camera.aimFov, "camera.aimFov", 1),
			strafeTilt = assertNumber(gunCamera.strafeTilt or DEFAULTS.camera.strafeTilt, "camera.strafeTilt", 0),
			sway = assertNumber(gunCamera.sway or DEFAULTS.camera.sway, "camera.sway", 0),
			viewModelHip = gunCamera.viewModelHip or typeCamera.viewModelHip or DEFAULTS.camera.viewModelHip,
			viewModelAim = gunCamera.viewModelAim or typeCamera.viewModelAim or DEFAULTS.camera.viewModelAim,
			tuning = gunCamera.tuning or typeCamera.tuning or DEFAULTS.camera.tuning,
		},

		sounds = {
			fire = tostring(gunSounds.fire or ""),
			reload = tostring(gunSounds.reload or ""),
			equip = tostring(gunSounds.equip or ""),
			empty = tostring(gunSounds.empty or ""),
		},
	}

	return table.freeze(definition)
end

return WeaponConfig
