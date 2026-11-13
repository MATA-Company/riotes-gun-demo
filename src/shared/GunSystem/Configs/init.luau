--!strict
--[[
	Config registry — tool name -> validated definition.
	Adding a gun means dropping a data file and one line here.
]]

local WeaponConfig = require(script.Parent.WeaponConfig)

local Registry = {}

local RAW = {
	Rifle = require(script.Rifle),
	["Brick Gun"] = require(script.BrickGun),
}

local build = WeaponConfig.build
local definitions: { [string]: any } = {}

for toolName, raw in pairs(RAW) do
	definitions[toolName] = build(raw)
end

--- Definition for a tool name, or nil when the tool is not a gun.
function Registry.get(toolName: string)
	return definitions[toolName]
end

--- Every registered tool name.
function Registry.names(): { string }
	local out = {}
	for name in pairs(definitions) do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

return table.freeze(Registry)
