--!strict
--[[
	Enums — the fixed vocabulary the whole gun system speaks.
	Kept as frozen tables (not Enum) so configs stay data-only and
	can be validated cheaply on both realms.
]]

local Enums = {}

Enums.FireMode = table.freeze({
	Semi = "Semi",
	Auto = "Auto",
	Burst = "Burst",
})

Enums.ReloadType = table.freeze({
	Mag = "Mag", -- one animation, refills the whole magazine
	Shell = "Shell", -- one shell per cycle until full
})

Enums.Slot = table.freeze({
	Primary = "Primary",
	Secondary = "Secondary",
})

local function values(set: { [string]: string }): { string }
	local out = {}
	for _, value in pairs(set) do
		table.insert(out, value)
	end
	table.sort(out)
	return out
end

Enums.FireModeValues = table.freeze(values(Enums.FireMode))
Enums.ReloadTypeValues = table.freeze(values(Enums.ReloadType))

return table.freeze(Enums)
