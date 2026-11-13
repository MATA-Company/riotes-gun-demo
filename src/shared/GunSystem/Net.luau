--!strict
--[[
	Net — one place that owns the wire contract.

	Server creates the folder + remotes; client waits for them. Nothing else
	in the codebase touches Instance.new("RemoteEvent").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Signal = require(ReplicatedStorage.Packages.Signal)

local Net = {}

local FOLDER_NAME = "Remotes"
local REMOTE_NAMES = { "Fire", "Reload", "Hit", "Aim", "Debug", "Impact" }

local isServer = RunService:IsServer()
local remotes: { [string]: RemoteEvent } = {}

local function ensureFolder(): Folder
	local root = ReplicatedStorage:FindFirstChild("GunSystem")
	if not root then
		root = Instance.new("Folder")
		root.Name = "GunSystem"
		root.Parent = ReplicatedStorage
	end
	local folder = root:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = root
	end
	return folder :: Folder
end

if isServer then
	local folder = ensureFolder()
	for _, name in ipairs(REMOTE_NAMES) do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote :: RemoteEvent
	end
else
	local folder = ReplicatedStorage:WaitForChild("GunSystem"):WaitForChild(FOLDER_NAME)
	for _, name in ipairs(REMOTE_NAMES) do
		remotes[name] = folder:WaitForChild(name) :: RemoteEvent
	end
end

--- RemoteEvent by name (server: created, client: awaited).
function Net.remote(name: string): RemoteEvent
	local remote = remotes[name]
	assert(remote, string.format("Net: unknown remote %q", name))
	return remote
end

--- Client-only: fires the server with a plain payload.
function Net.send(name: string, ...: any)
	assert(not isServer, "Net.send is client-only")
	Net.remote(name):FireServer(...)
end

--- Server-only: forwards a remote event to a handler with a Trove cleanup.
function Net.onServer(name: string, handler: (Player, ...any) -> ()): RBXScriptConnection
	assert(isServer, "Net.onServer is server-only")
	return Net.remote(name).OnServerEvent:Connect(handler)
end

return table.freeze(Net)
