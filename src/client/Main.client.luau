--!strict
--[[ Client entry point. Wiring only: resolve the sibling folder, then start. ]]

local GunSystem = script.Parent:WaitForChild("GunSystem")
local WeaponController = require(GunSystem:WaitForChild("WeaponController"))

WeaponController.start()
