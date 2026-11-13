--!strict
--[[ Server entry point. Wiring only: resolve the sibling folder, then start. ]]

local GunSystem = script.Parent:WaitForChild("GunSystem")
local WeaponService = require(GunSystem:WaitForChild("WeaponService"))

WeaponService.start()

print("[GunSystem] server ready v2")
