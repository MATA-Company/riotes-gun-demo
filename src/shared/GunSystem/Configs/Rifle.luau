--!strict
--[[ Rifle — inherits the Rifle class, owns its animation set + magazine. ]]

return {
	name = "Rifle",
	displayName = "Rifle",
	type = "Rifle",
	animationSet = "Rifle",
	slot = "Primary",

	magazine = 30,
	startingAmmo = 30,
	reloadTime = 2.1,

	camera = {
		aimFov = 52,
		strafeTilt = 1.4,
		-- exact framing tuned in game
		tuning = {
			px = 0.32, py = -1.70, pz = -1.20,
			rx = 0, ry = 0, rz = 0,
			wx = -95, wy = -5, wz = 0,
			gx = -0.05, gy = 0.15, gz = -0.35,
			scale = 1.25,
		},
	},
}
