--!strict
-- BuildServer.lua -> Handles the server-sided build logic.
-- Created by Jacksxity (07/20/2026)

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

--[[ Variables ]]--
local BuildSystemFolder = ReplicatedStorage:WaitForChild("BuildSystem")
local _Constants = require(BuildSystemFolder:WaitForChild("_Constants"))
local _Types = require(BuildSystemFolder:WaitForChild("_Types"))
local Remotes = BuildSystemFolder:WaitForChild("Remotes")
local ObjectTemplates = ServerStorage:WaitForChild("BuildSystem"):WaitForChild("Objects")
local MIN_BOX_AXIS = 0.01
local BuildServer = {} BuildServer.__index = BuildServer

--[[ Helper Functions ]]--
local function getPrimaryPart(root:Instance?) : BasePart?
	if not root then return nil end
	if root:IsA("BasePart") then return root end
	if root:IsA("Model") then return root.PrimaryPart end
	return nil
end

local function getBuildRoot(instance:Instance?) : Instance?
	local current = instance
	while current and current ~= workspace do
		if current:GetAttribute("Owner") ~= nil then return current end
		current = current.Parent
	end
	return nil
end

local function isFiniteNumber(value:number) : boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector3(value:Vector3) : boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function isFiniteCFrame(value:CFrame) : boolean
	local components = {value:GetComponents()}
	for _, component in components do
		if not isFiniteNumber(component) then return false end
	end
	return true
end

local function getCollisionSize(size:Vector3) : Vector3
	local inset = _Constants.CollisionInset
	return Vector3.new(math.max(size.X - inset, MIN_BOX_AXIS), math.max(size.Y - inset, MIN_BOX_AXIS), math.max(size.Z - inset, MIN_BOX_AXIS))
end

local function getSegmentNodes(cf:CFrame, size:Vector3, endPadding:number) : (Vector3, Vector3)
	local nodeDistance = math.max((size.Z - endPadding) / 2, 0)
	return (cf * CFrame.new(0, 0, -nodeDistance)).Position, (cf * CFrame.new(0, 0, nodeDistance)).Position
end

local function segmentsConnect(newCF:CFrame, newSize:Vector3, newPadding:number, targetCF:CFrame, targetSize:Vector3, targetPadding:number) : boolean
	local newA, newB = getSegmentNodes(newCF, newSize, newPadding)
	local targetA, targetB = getSegmentNodes(targetCF, targetSize, targetPadding)
	local newNodes = {newA, newB}
	local targetNodes = {targetA, targetB}
	local bestDistance = math.huge
	local bestNewIndex = 1
	local bestTargetIndex = 1
	for newIndex = 1, 2 do
		for targetIndex = 1, 2 do
			local distance = (newNodes[newIndex] - targetNodes[targetIndex]).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				bestNewIndex = newIndex
				bestTargetIndex = targetIndex
			end
		end
	end
	if bestDistance > _Constants.SegmentConnectionTolerance then return false end
	local newAway = newNodes[3 - bestNewIndex] - newNodes[bestNewIndex]
	local targetAway = targetNodes[3 - bestTargetIndex] - targetNodes[bestTargetIndex]
	if newAway.Magnitude > 0.001 and targetAway.Magnitude > 0.001 then if newAway.Unit:Dot(targetAway.Unit) > 0.999 then return false end end
	return true
end

local function isBoxInsideBase(boxCF:CFrame, boxSize:Vector3, basePart:BasePart) : boolean
	local localCF = basePart.CFrame:ToObjectSpace(boxCF)
	local baseSize = basePart.Size
	local sx, sy, sz = boxSize.X / 2, boxSize.Y / 2, boxSize.Z / 2
	local tolerance = _Constants.BoundsTolerance
	local corners = {Vector3.new(sx, sy, sz), Vector3.new(-sx, sy, sz), Vector3.new(sx, -sy, sz), Vector3.new(-sx, -sy, sz), Vector3.new(sx, sy, -sz), Vector3.new(-sx, sy, -sz), Vector3.new(sx, -sy, -sz), Vector3.new(-sx, -sy, -sz)}
	for _, corner in corners do
		local localCorner = localCF * corner
		if math.abs(localCorner.X) > (baseSize.X / 2) + tolerance or math.abs(localCorner.Z) > (baseSize.Z / 2) + tolerance or localCorner.Y < -tolerance then
			return false
		end
	end
	return true
end

local function pivotModelToPrimaryCFrame(model:Model, primaryCF:CFrame)
	local primary = model.PrimaryPart :: BasePart
	local primaryToPivot = primary.CFrame:ToObjectSpace(model:GetPivot())
	model:PivotTo(primaryCF * primaryToPivot)
end

local function getPlayerHistory(self:_Types.BuildServer, player:Player) : _Types.PlayerHistory
	local history = self.PlayerHistory[player]
	if not history then
		local newHistory:_Types.PlayerHistory = {stack = {}, pointer = 0}
		self.PlayerHistory[player] = newHistory
		history = newHistory
	end
	return history
end

local function truncateRedoHistory(history:_Types.PlayerHistory)
	if history.pointer >= #history.stack then return end
	for index = #history.stack, history.pointer + 1, -1 do
		local obsolete = history.stack[index]
		if obsolete.action == "Place" and obsolete.instance then obsolete.instance:Destroy() end
		table.remove(history.stack, index)
	end
end

local function pushHistory(history:_Types.PlayerHistory, action:"Place" | "Remove", instance:Instance)
	truncateRedoHistory(history)
	table.insert(history.stack, {action = action, instance = instance})
	history.pointer += 1
	while #history.stack > _Constants.MaxUndoSteps do
		local oldest = table.remove(history.stack, 1)
		history.pointer -= 1
		if oldest.action == "Remove" and oldest.instance then oldest.instance:Destroy() end
	end
end

local function getBasePart(player:Player) : BasePart?
	local folder = player:FindFirstChild("BuildSystem")
	local baseRef = folder and folder:FindFirstChild("Base")
	if not baseRef or not baseRef:IsA("ObjectValue") then return nil end
	return getPrimaryPart(baseRef.Value)
end

local function setupPlayer(self:_Types.BuildServer, player:Player, defaultBase:Instance)
	getPlayerHistory(self, player)
	local folder = player:FindFirstChild("BuildSystem")
	if not folder then folder = Instance.new("Folder") folder.Name = "BuildSystem" folder.Parent = player end
	local baseValue = folder:FindFirstChild("Base")
	if not baseValue or not baseValue:IsA("ObjectValue") then if baseValue then baseValue:Destroy() end baseValue = Instance.new("ObjectValue") baseValue.Name = "Base" baseValue.Parent = folder end
	if not baseValue.Value then baseValue.Value = defaultBase end
end

local function validatePlacementRequest( template:Model, cf:any, scaleOrSize:any, requestedMode:any) : (boolean, string?)
	if typeof(cf) ~= "CFrame" or not isFiniteCFrame(cf) then return false, nil end
	local inferredMode = if typeof(scaleOrSize) == "Vector3" then "Segment" else "Single"
	local mode = if requestedMode == nil then inferredMode else requestedMode
	if mode ~= "Single" and mode ~= "Segment" then return false, nil end
	if mode ~= inferredMode then return false, nil end
	local templateMode = template:GetAttribute("BuildMode")
	if typeof(templateMode) == "string" and templateMode ~= "Both" and templateMode ~= mode then return false, nil end
	local primary = template.PrimaryPart :: BasePart
	if mode == "Single" then
		if typeof(scaleOrSize) ~= "number" or not isFiniteNumber(scaleOrSize) then return false, nil end
		if scaleOrSize < _Constants.MinScale or scaleOrSize > _Constants.MaxScale then return false, nil end
	else
		if typeof(scaleOrSize) ~= "Vector3" or not isFiniteVector3(scaleOrSize) then return false, nil end
		if math.abs(scaleOrSize.X - primary.Size.X) > _Constants.BoundsTolerance then return false, nil end
		if math.abs(scaleOrSize.Y - primary.Size.Y) > _Constants.BoundsTolerance then return false, nil end
		if scaleOrSize.Z < primary.Size.Z or scaleOrSize.Z > _Constants.MaxSegmentLength then return false, nil end
	end
	return true, mode
end

--[[ Functions ]]--
function BuildServer.new() : _Types.BuildServer
	local self = setmetatable({PlayerHistory = {}}, BuildServer)
	local defaultBase = workspace:WaitForChild("Plot")
	
	local PlaceRequest = Remotes:WaitForChild("PlaceRequest") :: RemoteFunction
	PlaceRequest.OnServerInvoke = function(player:Player, objectName:any, cf:any, scaleOrSize:any, connectedTargets:any, requestedMode:any) return self:Place(player, objectName, cf, scaleOrSize, connectedTargets, requestedMode) end
	local RemoveRequest = Remotes:WaitForChild("RemoveRequest") :: RemoteFunction
	RemoveRequest.OnServerInvoke = function(player:Player, target:any) return self:Remove(player, target) end
	local UndoRequest = Remotes:WaitForChild("UndoRequest") :: RemoteFunction
	UndoRequest.OnServerInvoke = function(player:Player) return self:Undo(player) end
	local RedoRequest = Remotes:WaitForChild("RedoRequest") :: RemoteFunction
	RedoRequest.OnServerInvoke = function(player:Player) return self:Redo(player) end
	
	Players.PlayerAdded:Connect(function(player) setupPlayer(self, player, defaultBase) end)
	for _, player in Players:GetPlayers() do setupPlayer(self, player, defaultBase) end
	Players.PlayerRemoving:Connect(function(player)
		local history = self.PlayerHistory[player]
		if history then
			for _, record in history.stack do
				if record.instance and record.instance.Parent == nil then record.instance:Destroy() end
			end
		end
		self.PlayerHistory[player] = nil
	end)
	
	return self
end

function BuildServer:Place(player:Player, objectName:any, cf:any, scaleOrSize:any, connectedTargets:any, requestedMode:any) : boolean
	if typeof(objectName) ~= "string" or #objectName > 100 then return false end
	local template = ObjectTemplates:FindFirstChild(objectName)
	if not template or not template:IsA("Model") or not template.PrimaryPart then return false end
	local validRequest, mode = validatePlacementRequest(template, cf, scaleOrSize, requestedMode)
	if not validRequest or not mode then return false end
	local isSegment = mode == "Segment"
	local placementCF = cf :: CFrame
	local basePart = getBasePart(player)
	if _Constants.UseBase and not basePart then return false end

	local clone = template:Clone()
	local clonePrimary = clone.PrimaryPart :: BasePart
	local templatePrimary = template.PrimaryPart :: BasePart
	local segmentEndPadding = templatePrimary.Size.Z
	if isSegment then
		clonePrimary.Size = scaleOrSize :: Vector3
	else
		clone:ScaleTo(scaleOrSize :: number)
	end
	pivotModelToPrimaryCFrame(clone, placementCF)

	local boxCF, boxSize = clone:GetBoundingBox()
	if _Constants.UseBase and not isBoxInsideBase(boxCF, boxSize, basePart :: BasePart) then clone:Destroy() return false end
	local allowedConnections:{Instance} = {}
	local seenConnections:{[Instance]:boolean} = {}
	if isSegment and typeof(connectedTargets) == "table" then
		local connectionCount = math.min(#connectedTargets, 2)
		for index = 1, connectionCount do
			local candidate = connectedTargets[index]
			if typeof(candidate) ~= "Instance" then continue end
			
			local target = getBuildRoot(candidate :: Instance)
			if not target or seenConnections[target] then continue end
			if not target:IsDescendantOf(workspace) or target:GetAttribute("Owner") ~= player.UserId then continue end
			local targetPart = getPrimaryPart(target)
			local targetMode = target:GetAttribute("BuildMode")
			if not targetPart or (targetMode ~= "Segment" and target.Name ~= objectName) then continue end
			
			local savedPadding = target:GetAttribute("SegmentEndPadding")
			local targetPadding = if typeof(savedPadding) == "number" then savedPadding else segmentEndPadding
			if segmentsConnect(placementCF, clonePrimary.Size, segmentEndPadding, targetPart.CFrame, targetPart.Size, targetPadding) then
				seenConnections[target] = true
				table.insert(allowedConnections, target)
			end
		end
	end

	if _Constants.DoCollisions then
		local excludes:{Instance} = {}
		if basePart then table.insert(excludes, basePart) end
		if player.Character then table.insert(excludes, player.Character) end
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = excludes

		local parts = workspace:GetPartBoundsInBox(boxCF, getCollisionSize(boxSize), overlap)
		for _, part in parts do
			local allowed = false
			for _, target in allowedConnections do
				if part == target or part:IsDescendantOf(target) then
					allowed = true
					break
				end
			end
			if not allowed then
				clone:Destroy()
				return false
			end
		end
	end

	clone:SetAttribute("Owner", player.UserId)
	clone:SetAttribute("BuildMode", mode)
	if isSegment then clone:SetAttribute("SegmentEndPadding", segmentEndPadding) end
	clone.Parent = workspace

	pushHistory(getPlayerHistory(self, player), "Place", clone)
	return true
end

function BuildServer:Remove(player:Player, target:any) : boolean
	if typeof(target) ~= "Instance" then return false end
	local root = getBuildRoot(target :: Instance)
	if not root or not root:IsDescendantOf(workspace) then return false end
	if root:GetAttribute("Owner") ~= player.UserId then return false end

	root.Parent = nil
	pushHistory(getPlayerHistory(self, player), "Remove", root)
	return true
end

function BuildServer:Undo(player:Player) : boolean
	local history = getPlayerHistory(self, player)
	if history.pointer <= 0 then return false end

	local record = history.stack[history.pointer]
	if record.action == "Place" and record.instance then
		record.instance.Parent = nil
	elseif record.action == "Remove" and record.instance then
		record.instance.Parent = workspace
	end
	history.pointer -= 1
	return true
end

function BuildServer:Redo(player:Player) : boolean
	local history = getPlayerHistory(self, player)
	if history.pointer >= #history.stack then return false end

	history.pointer += 1
	local record = history.stack[history.pointer]
	if record.action == "Place" and record.instance then
		record.instance.Parent = workspace
	elseif record.action == "Remove" and record.instance then
		record.instance.Parent = nil
	end
	return true
end

return BuildServer
