--!strict
-- BuildServer.lua -> Handles the server-sided build logic.
-- Created by Jacksxity (07/20/2026)

--[[ Services ]]--
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

--[[ Variables ]]--
local BuildSystemFolder = ReplicatedStorage:WaitForChild('BuildSystem')
local _Constants = require(BuildSystemFolder:WaitForChild('_Constants'))
local _Types = require(BuildSystemFolder:WaitForChild('_Types'))
local Remotes = BuildSystemFolder:WaitForChild("Remotes")
local BuildServer = {} BuildServer.__index = BuildServer

--[[ Functions ]]--
function BuildServer.new() : _Types.BuildServer
	--[[ Constructor ]]--
	local self = setmetatable({PlayerHistory = {}}, BuildServer)
	
	local PlaceRequest = Remotes:WaitForChild("PlaceRequest") :: RemoteFunction PlaceRequest.OnServerInvoke = function(player:Player, objectName:string, cf:CFrame, scaleOrSize:any) return self:Place(player, objectName, cf, scaleOrSize) end
	local RemoveRequest = Remotes:WaitForChild("RemoveRequest") :: RemoteFunction RemoveRequest.OnServerInvoke = function(player:Player, target:Instance) return self:Remove(player, target) end
	local UndoRequest = Remotes:WaitForChild("UndoRequest") :: RemoteFunction UndoRequest.OnServerInvoke = function(player:Player) return self:Undo(player) end 
	local RedoRequest = Remotes:WaitForChild("RedoRequest") :: RemoteFunction RedoRequest.OnServerInvoke = function(player:Player) return self:Redo(player) end 

	Players.PlayerAdded:Connect(function(player)
		self.PlayerHistory[player] = { stack = {}, pointer = 0 }
		local folder = Instance.new("Folder") folder.Name = "BuildSystem" folder.Parent = player
		local baseValue = Instance.new("ObjectValue") baseValue.Name = "Base" baseValue.Parent = folder baseValue.Value = workspace:WaitForChild("Plot")
	end)
	Players.PlayerRemoving:Connect(function(player) self.PlayerHistory[player] = nil end)

	return self
end

function BuildServer:Place(player:Player, objectName:string, cf:CFrame, scaleOrSize:any) : boolean
	--[[ Server Placement Function ]]--
	local template = ServerStorage:WaitForChild('BuildSystem'):WaitForChild('Objects'):FindFirstChild(objectName) if not template then return false end
	local folder = player:FindFirstChild("BuildSystem")
	local baseRef = folder and folder:FindFirstChild("Base") :: ObjectValue
	local basePart = if baseRef and baseRef.Value then (if baseRef.Value:IsA("BasePart") then baseRef.Value elseif baseRef.Value:IsA("Model") then baseRef.Value.PrimaryPart else nil) else nil
	local isSegment = typeof(scaleOrSize) == "Vector3"
	local boxSize = if isSegment then scaleOrSize else (template.PrimaryPart :: BasePart).Size * (scaleOrSize :: number)

	if _Constants.UseBase then
		if not basePart then warn("Player has no valid base assigned!") return false end
		local localCf = basePart.CFrame:ToObjectSpace(cf)
		local size = basePart.Size
		local sx, sy, sz = boxSize.X / 2, boxSize.Y / 2, boxSize.Z / 2
		local corners = {Vector3.new(sx,sy,sz), Vector3.new(-sx,sy,sz), Vector3.new(sx,-sy,sz), Vector3.new(-sx,-sy,sz), Vector3.new(sx,sy,-sz), Vector3.new(-sx,sy,-sz), Vector3.new(sx,-sy,-sz), Vector3.new(-sx,-sy,-sz)}

		for _, corner in corners do
			local cb = localCf * corner
			if math.abs(cb.X) > (size.X / 2) + 0.01 or math.abs(cb.Z) > (size.Z / 2) + 0.01 or cb.Y < -0.01 then return false end
		end
	end

	if _Constants.DoCollisions then
		local overlap = OverlapParams.new() overlap.FilterType = Enum.RaycastFilterType.Exclude 
		local excludes = {} if basePart then table.insert(excludes, basePart) end if player.Character then table.insert(excludes, player.Character) end
		overlap.FilterDescendantsInstances = excludes
		local collisionBox = boxSize - Vector3.new(0.02, 0.02, 0.02)
		local parts = workspace:GetPartBoundsInBox(cf, collisionBox, overlap)
		if #parts > 0 then return false end
	end

	local clone = template:Clone() 
	if clone:IsA("Model") then 
		if isSegment then clone.PrimaryPart.Size = boxSize else clone:ScaleTo(scaleOrSize :: number) end
		clone:PivotTo(cf) 
	end
	clone:SetAttribute("Owner", player.UserId) clone.Parent = workspace

	local history = self.PlayerHistory[player]
	if history.pointer < #history.stack then
		for i = #history.stack, history.pointer + 1, -1 do
			local obsolete = history.stack[i] if obsolete.action == "Place" and obsolete.instance then obsolete.instance:Destroy() end table.remove(history.stack, i)
		end
	end

	table.insert(history.stack, {action = "Place", instance = clone}) history.pointer += 1

	while #history.stack > _Constants.MaxUndoSteps do
		local oldest = table.remove(history.stack, 1) history.pointer -= 1
		if oldest.action == "Remove" and oldest.instance then oldest.instance:Destroy() end
	end

	return true
end

function BuildServer:Remove(player:Player, target:Instance) : boolean
	--[[ Server Sledgehammer/Remove Function ]]--
	if not target or target:GetAttribute("Owner") ~= player.UserId then return false end
	target.Parent = nil 
	local history = self.PlayerHistory[player]
	if history.pointer < #history.stack then
		for i = #history.stack, history.pointer + 1, -1 do
			local obsolete = history.stack[i] if obsolete.action == "Place" and obsolete.instance then obsolete.instance:Destroy() end table.remove(history.stack, i)
		end
	end

	table.insert(history.stack, {action = "Remove", instance = target}) history.pointer += 1

	while #history.stack > _Constants.MaxUndoSteps do
		local oldest = table.remove(history.stack, 1) history.pointer -= 1
		if oldest.action == "Remove" and oldest.instance then oldest.instance:Destroy() end
	end

	return true
end

function BuildServer:Undo(player:Player) : boolean
	--[[ Server Undo Function ]]--
	local history = self.PlayerHistory[player]
	if history.pointer > 0 then
		local record = history.stack[history.pointer]
		if record.action == "Place" and record.instance then record.instance.Parent = nil elseif record.action == "Remove" and record.instance then record.instance.Parent = workspace end
		history.pointer -= 1 return true
	end
	return false
end

function BuildServer:Redo(player:Player) : boolean
	--[[ Server Redo Function ]]--
	local history = self.PlayerHistory[player]
	if history.pointer < #history.stack then
		history.pointer += 1
		local record = history.stack[history.pointer]
		if record.action == "Place" and record.instance then record.instance.Parent = workspace elseif record.action == "Remove" and record.instance then record.instance.Parent = nil end
		return true
	end
	return false
end

return BuildServer
