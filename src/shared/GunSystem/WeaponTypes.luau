--!strict
--[[
	WeaponTypes — the per-class defaults every gun inherits.

	A config sets `type = "Shotgun"` and only overrides what makes that gun
	different. This is what makes a new weapon feel consistent without
	copy-pasting numbers, and it is the single place that defines how each
	class behaves (pellets, cadence, spread shape, camera feel).
]]

local WeaponTypes = {
	Rifle = {
		fireMode = "Auto",
		pellets = 1,
		fireTime = 0.09,
		spread = 1.4,
		aimSpread = 0.4,
		damage = 24,
		range = 600,
		bulletVelocity = 3000,
		reloadType = "Mag",
		camera = { kick = 2.2, recovery = 11, shake = 0.22 },
	},

	Pistol = {
		fireMode = "Semi",
		pellets = 1,
		fireTime = 0.18,
		spread = 1.1,
		aimSpread = 0.25,
		damage = 26,
		range = 300,
		bulletVelocity = 1800,
		reloadType = "Mag",
		camera = { kick = 3.2, recovery = 14, shake = 0.18 },
	},

	Shotgun = {
		fireMode = "Semi",
		pellets = 8,
		fireTime = 0.75,
		spread = 4.5,
		aimSpread = 2.4,
		damage = 9,
		range = 180,
		bulletVelocity = 1400,
		reloadType = "Shell",
		camera = { kick = 6.5, recovery = 8, shake = 0.55 },
	},
}

return table.freeze(WeaponTypes)
