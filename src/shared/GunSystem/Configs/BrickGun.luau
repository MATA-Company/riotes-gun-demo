--!strict
--[[ Brick Gun — Shotgun class (pellets + shell reload), Default animations. ]]

return {
	name = "Brick Gun",
	displayName = "Brick Gun",
	type = "Shotgun",
	animationSet = "Default",
	slot = "Secondary",

	magazine = 6,
	startingAmmo = 6,
	reloadTime = 1.1,

	camera = {
		aimFov = 58,
		strafeTilt = 1.6,
		-- its own framing; tune with F2 and paste the printed values here
		tuning = {
			px = 0.32, py = -1.70, pz = -1.20,
			rx = 0, ry = 0, rz = 0,
			wx = -95, wy = -5, wz = 0,
			gx = -0.05, gy = 0.15, gz = -0.35,
			scale = 1.25,
		},
	},
}
