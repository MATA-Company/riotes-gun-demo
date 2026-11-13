--!strict
--[[
	Animation sets — named bundles of the tracks every gun needs.

	hold / shoot / reload drive the third-person rig.
	aim / aimShoot drive the first-person view model while RMB is held.
]]

local HOLD = "102758597620460"

local AnimationSets = {
	Default = {
		hold = HOLD,
		shoot = "123413871301093",
		reload = "138501597881118",
		aim = HOLD,
		aimShoot = "123413871301093",
	},
	Rifle = {
		hold = HOLD,
		shoot = "73786459340105",
		reload = "126834709021604",
		aim = "111473927447455",
		aimShoot = "77434657571361",
	},
}

for name, set in pairs(AnimationSets) do
	AnimationSets[name] = table.freeze(set)
end

return table.freeze(AnimationSets)
