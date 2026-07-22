--!strict
-- BuildClient.lua -> Handles the client-sided build logic.
-- Created by Jacksxity (07/20/2026)

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--[[ Variables ]]--
local BuildSystemFolder = ReplicatedStorage:WaitForChild("BuildSystem")
local _Keybinds = require(BuildSystemFolder:WaitForChild("_Keybinds"))
local _Constants = require(BuildSystemFolder:WaitForChild("_Constants"))
local _Types = require(BuildSystemFolder:WaitForChild("_Types"))
local Remotes = BuildSystemFolder:WaitForChild("Remotes")
local PlaceRequest = Remotes:WaitForChild("PlaceRequest") :: RemoteFunction
local RemoveRequest = Remotes:WaitForChild("RemoveRequest") :: RemoteFunction
local UndoRequest = Remotes:WaitForChild("UndoRequest") :: RemoteFunction
local RedoRequest = Remotes:WaitForChild("RedoRequest") :: RemoteFunction
local VALID_COLOR = Color3.fromRGB(0, 255, 0)
local INVALID_COLOR = Color3.fromRGB(255, 0, 0)
local MIN_BOX_AXIS = 0.01
local BuildClient = {} BuildClient.__index = BuildClient

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

local function getBasePart(player:Player) : BasePart?
	local folder = player:FindFirstChild("BuildSystem")
	local baseRef = folder and folder:FindFirstChild("Base")
	if not baseRef or not baseRef:IsA("ObjectValue") then return nil end
	return getPrimaryPart(baseRef.Value)
end

local function getMouseRay(player:Player) : Ray
	local mouse = player:GetMouse()
	local camera = workspace.CurrentCamera
	if not camera then return Ray.new(Vector3.zero, Vector3.zAxis) end
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	return Ray.new(unitRay.Origin, unitRay.Direction)
end

local function makeRaycastParams(excludes:{Instance}) : RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludes
	return params
end

local function makeOverlapParams(excludes:{Instance}) : OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludes
	return params
end

local function getExcludes(self:_Types.BuildClient, includeBase:boolean, basePart:BasePart?) : {Instance}
	local excludes:{Instance} = {}
	if self.GhostModel then table.insert(excludes, self.GhostModel) end
	if self.Player.Character then table.insert(excludes, self.Player.Character) end
	if includeBase and basePart then table.insert(excludes, basePart) end
	return excludes
end

local function getBoundsAtPrimaryCFrame(model:Model, targetPrimaryCF:CFrame) : (CFrame, Vector3)
	local primary = model.PrimaryPart :: BasePart
	local currentBoxCF, boxSize = model:GetBoundingBox()
	local primaryToBox = primary.CFrame:ToObjectSpace(currentBoxCF)
	return targetPrimaryCF * primaryToBox, boxSize
end

local function areKeyModifiersHeld(binding:any) : boolean
	if typeof(binding) ~= "table" then return false end
	local hasModifier = false
	for _, key in binding do
		if key.EnumType == Enum.KeyCode then
			hasModifier = true
			if not UserInputService:IsKeyDown(key) then return false end
		end
	end
	return hasModifier
end

local function getCollisionSize(size:Vector3) : Vector3
	local inset = _Constants.CollisionInset
	return Vector3.new(math.max(size.X - inset, MIN_BOX_AXIS), math.max(size.Y - inset, MIN_BOX_AXIS), math.max(size.Z - inset, MIN_BOX_AXIS))
end

local function isBoxInsideBase(boxCF:CFrame, boxSize:Vector3, basePart:BasePart) : boolean
	local localCF = basePart.CFrame:ToObjectSpace(boxCF)
	local baseSize = basePart.Size
	local sx, sy, sz = boxSize.X / 2, boxSize.Y / 2, boxSize.Z / 2
	local tolerance = _Constants.BoundsTolerance
	local corners = {Vector3.new(sx, sy, sz), Vector3.new(-sx, sy, sz), Vector3.new(sx, -sy, sz), Vector3.new(-sx, -sy, sz), Vector3.new(sx, sy, -sz), Vector3.new(-sx, sy, -sz), Vector3.new(sx, -sy, -sz), Vector3.new(-sx, -sy, -sz)}

	for _, corner in corners do
		local localCorner = localCF * corner
		if math.abs(localCorner.X) > (baseSize.X / 2) + tolerance
			or math.abs(localCorner.Z) > (baseSize.Z / 2) + tolerance
			or localCorner.Y < -tolerance then
			return false
		end
	end

	return true
end

local function isAllowedCollision(part:BasePart, allowedConnections:{Instance}) : boolean
	for _, target in allowedConnections do
		if part == target or part:IsDescendantOf(target) then return true end
	end
	return false
end

local function resetSegmentState(self:_Types.BuildClient)
	self.PointA = nil
	self.CurrentPoint = nil
	self.CurrentSnapTarget = nil
	self.PointASnapTarget = nil
	if self.OriginalSize and self.GhostModel and self.GhostModel.PrimaryPart then self.GhostModel.PrimaryPart.Size = self.OriginalSize end
end

--[[ Functions ]]--
function BuildClient.new() : _Types.BuildClient
	local self = setmetatable({
		Player = Players.LocalPlayer,
		GhostModel = nil,
		HitboxVisual = nil,
		IsRemoving = false,
		CanPlace = false,
		CurrentRotation = 0,
		CurrentScale = 1,
		_renderConnection = nil,
		PointA = nil,
		CurrentPoint = nil,
		CurrentSnapTarget = nil,
		PointASnapTarget = nil,
		PlacementMode = "Single",
		OriginalSize = nil,
	}, BuildClient)

	self:BindInputs()
	
	return self
end

function BuildClient:Hook(targetObject:Instance, mode:string?)
	self:Unhook()
	self.IsRemoving = false
	self.PlacementMode = mode or "Single"
	self.CurrentScale = 1
	self.CanPlace = false
	resetSegmentState(self)
	self.OriginalSize = nil

	if targetObject:IsA("BasePart") then
		local model = Instance.new("Model")
		local clone = targetObject:Clone()
		model.Name = targetObject.Name
		clone.Parent = model
		model.PrimaryPart = clone
		self.GhostModel = model
	elseif targetObject:IsA("Model") and targetObject.PrimaryPart then
		self.GhostModel = targetObject:Clone()
	else
		warn("Invalid object: Must be a BasePart or a Model with a PrimaryPart.")
		return
	end

	local ghostModel = self.GhostModel :: Model
	ghostModel.Parent = workspace
	local primary = ghostModel.PrimaryPart :: BasePart
	primary.Anchored = true
	primary.CanCollide = false
	self.OriginalSize = primary.Size

	local isSinglePart = true
	for _, descendant in ghostModel:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= primary then
			isSinglePart = false
			break
		end
	end
	primary.Transparency = if isSinglePart then 0.5 else 1

	local box = Instance.new("SelectionBox")
	box.Adornee = primary
	box.Color3 = VALID_COLOR
	box.LineThickness = 0.05
	box.Parent = ghostModel
	self.HitboxVisual = box

	for _, descendant in ghostModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			if descendant ~= primary then
				descendant.Transparency = 0.5
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = descendant
				weld.Parent = primary
				descendant.Anchored = false
			end
		end
	end

	if self._renderConnection then self._renderConnection:Disconnect() end
	self._renderConnection = RunService.RenderStepped:Connect(function() self:Move() end)
end

function BuildClient:BindInputs()
	ContextActionService:BindAction("Build_Place", function(_, state, input)
		if state == Enum.UserInputState.Begin then self:Place(input) end
		return Enum.ContextActionResult.Pass
	end, true, _Keybinds.Place)

	ContextActionService:BindAction("Build_RotateCW", function(_, state)
		if state == Enum.UserInputState.Begin then self:Rotate(1) end
		return Enum.ContextActionResult.Pass
	end, true, _Keybinds.RotateCW)

	ContextActionService:BindAction("Build_RotateCCW", function(_, state)
		if state == Enum.UserInputState.Begin then self:Rotate(-1) end
		return Enum.ContextActionResult.Pass
	end, true, _Keybinds.RotateCCW)

	ContextActionService:BindAction("Build_ScaleIncrease", function(_, state)
		if state == Enum.UserInputState.Begin then self:Scale(1) end
		return Enum.ContextActionResult.Pass
	end, true, _Keybinds.ScaleIncrease)

	ContextActionService:BindAction("Build_ScaleDecrease", function(_, state)
		if state == Enum.UserInputState.Begin then self:Scale(-1) end
		return Enum.ContextActionResult.Pass
	end, true, _Keybinds.ScaleDecrease)

	ContextActionService:BindAction("Build_Sledgehammer", function(_, state)
		if state == Enum.UserInputState.Begin then self:Remove() end
		return Enum.ContextActionResult.Pass
	end, true, _Keybinds.Sledgehammer)

	ContextActionService:BindAction("Build_Cancel", function(_, state)
		if state == Enum.UserInputState.Begin then
			self.IsRemoving = false
			self:Unhook()
		end
		return Enum.ContextActionResult.Pass
	end, false, _Keybinds.Cancel)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		local function checkCombo(keys:any) : boolean
			if typeof(keys) == "table" then
				local matched = false
				for _, key in keys do
					if key == input.KeyCode or key == input.UserInputType then
						matched = true
					elseif key.EnumType == Enum.KeyCode and not UserInputService:IsKeyDown(key) then
						return false
					end
				end
				return matched
			end
			return input.KeyCode == keys or input.UserInputType == keys
		end

		if checkCombo(_Keybinds.Undo) then
			self:Undo()
		elseif checkCombo(_Keybinds.Redo) then
			self:Redo()
		end
	end)
end

function BuildClient:Place(_input:InputObject)
	if self.IsRemoving then self:TryRemove() return end
	if not self.GhostModel or not self.CanPlace then return end
	if self.PlacementMode == "Segment" and not self.PointA then if not self.CurrentPoint then return end self.PointA = self.CurrentPoint self.PointASnapTarget = self.CurrentSnapTarget return end

	local primary = self.GhostModel.PrimaryPart :: BasePart
	local scaleOrSize = if self.PlacementMode == "Segment" then primary.Size else self.CurrentScale
	local placementCF = primary.CFrame
	local connectedTargets:{Instance} = {}

	if self.PlacementMode == "Segment" then
		if self.PointASnapTarget then table.insert(connectedTargets, self.PointASnapTarget) end
		if self.CurrentSnapTarget and self.CurrentSnapTarget ~= self.PointASnapTarget then
			table.insert(connectedTargets, self.CurrentSnapTarget)
		end
	end

	local success = PlaceRequest:InvokeServer(self.GhostModel.Name, placementCF, scaleOrSize, connectedTargets, self.PlacementMode)
	if success then
		if self.PlacementMode == "Segment" then
			local basePart = getBasePart(self.Player)
			local rotationCF = if basePart then basePart.CFrame:ToObjectSpace(placementCF) else placementCF
			local yaw, _, _ = rotationCF:ToEulerAnglesYXZ()
			self.CurrentRotation = math.deg(yaw)
			resetSegmentState(self)
		end

		if not areKeyModifiersHeld(_Keybinds.PlaceMultiple) then self:Unhook() end
	else
		warn("Server rejected placement!")
		if self.PlacementMode == "Segment" then resetSegmentState(self) end
	end
end

function BuildClient:Move()
	local ghostModel = self.GhostModel
	if not ghostModel or not ghostModel.PrimaryPart then return end
	local primary = ghostModel.PrimaryPart
	local basePart = getBasePart(self.Player)
	local excludes = getExcludes(self, false, basePart)
	local mouseRay = getMouseRay(self.Player)
	local rayResult = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 500, makeRaycastParams(excludes))
	local hitPos = if rayResult then rayResult.Position else mouseRay.Origin + (mouseRay.Direction * 50)
	local isSegment = self.PlacementMode == "Segment"
	local isValid = true
	local buildUp = if basePart then basePart.CFrame.UpVector else Vector3.yAxis

	if isSegment and _Constants.UseBase and basePart then
		local planePoint = basePart.Position + (buildUp * (basePart.Size.Y / 2))
		local denominator = mouseRay.Direction:Dot(buildUp)
		if math.abs(denominator) > 0.0001 then
			local t = (planePoint - mouseRay.Origin):Dot(buildUp) / denominator
			if t > 0 then hitPos = mouseRay.Origin + (mouseRay.Direction * t) end
		end
	end

	local snappingEnabled = not UserInputService:IsKeyDown(_Keybinds.NoSnap)
	local gridSnap = if snappingEnabled then _Constants.GridSnap else 0
	local originalSize = self.OriginalSize or primary.Size
	local forcedX, forcedY, forcedZ = originalSize.X, originalSize.Y, originalSize.Z
	local currentPoint = if isSegment then hitPos + (buildUp * (forcedY / 2)) else hitPos
	local snappedToNode = false
	local closestTarget:Instance? = nil

	if snappingEnabled and isSegment then
		local snapExcludes = getExcludes(self, true, basePart)
		local nearbyParts = workspace:GetPartBoundsInRadius(currentPoint, _Constants.SegmentSnapDistance, makeOverlapParams(snapExcludes))
		local seenRoots:{[Instance]:boolean} = {}
		local closestDistance = _Constants.SegmentSnapDistance
		local closestPoint:Vector3? = nil

		for _, nearbyPart in nearbyParts do
			local root = getBuildRoot(nearbyPart)
			if not root or seenRoots[root] or root == ghostModel then continue end
			seenRoots[root] = true
			if root:GetAttribute("Owner") ~= self.Player.UserId then continue end

			local part = getPrimaryPart(root)
			local buildMode = root:GetAttribute("BuildMode")
			local canBeSegment = buildMode == "Segment" or root.Name == ghostModel.Name
			if not part or not canBeSegment then continue end

			local savedPadding = root:GetAttribute("SegmentEndPadding")
			local endPadding = if typeof(savedPadding) == "number" then savedPadding else forcedZ
			local nodeDistance = math.max((part.Size.Z - endPadding) / 2, 0)
			local pointA = (part.CFrame * CFrame.new(0, 0, -nodeDistance)).Position
			local pointB = (part.CFrame * CFrame.new(0, 0, nodeDistance)).Position
			local distanceA = (currentPoint - pointA).Magnitude
			local distanceB = (currentPoint - pointB).Magnitude

			if distanceA < closestDistance then
				closestDistance = distanceA
				closestPoint = pointA
				closestTarget = root
			end
			if distanceB < closestDistance then
				closestDistance = distanceB
				closestPoint = pointB
				closestTarget = root
			end
		end

		if closestPoint then
			currentPoint = closestPoint
			snappedToNode = true
		end
	end

	if gridSnap > 0 and not snappedToNode and not (isSegment and self.PointA) then
		if _Constants.UseBase and basePart then
			local localPosition = basePart.CFrame:PointToObjectSpace(currentPoint)
			localPosition = Vector3.new(math.round(localPosition.X / gridSnap) * gridSnap, localPosition.Y, math.round(localPosition.Z / gridSnap) * gridSnap)
			currentPoint = basePart.CFrame:PointToWorldSpace(localPosition)
		else
			currentPoint = Vector3.new(math.round(currentPoint.X / gridSnap) * gridSnap, currentPoint.Y, math.round(currentPoint.Z / gridSnap) * gridSnap)
		end
	end

	self.CurrentSnapTarget = closestTarget
	local baseRotation = if _Constants.UseBase and basePart then basePart.CFrame.Rotation else CFrame.identity
	local targetCF = CFrame.new(currentPoint) * baseRotation * CFrame.Angles(0, math.rad(self.CurrentRotation), 0)
	if isSegment and self.PointA then
		local rawOffset = currentPoint - self.PointA
		local localOffset = if basePart then basePart.CFrame:VectorToObjectSpace(rawOffset) else rawOffset
		localOffset = Vector3.new(localOffset.X, 0, localOffset.Z)

		if not snappedToNode and snappingEnabled and localOffset.Magnitude > 0.001 then
			local distance = localOffset.Magnitude
			if _Constants.SegmentAngleSnap > 0 then
				local rawAngle = math.atan2(localOffset.Z, localOffset.X)
				local snapRadians = math.rad(_Constants.SegmentAngleSnap)
				local snappedAngle = math.round(rawAngle / snapRadians) * snapRadians
				local direction = Vector3.new(math.cos(snappedAngle), 0, math.sin(snappedAngle))
				distance = math.max(localOffset:Dot(direction), _Constants.MinSegmentLength)
				if gridSnap > 0 then distance = math.round(distance / gridSnap) * gridSnap end
				localOffset = direction * math.max(distance, _Constants.MinSegmentLength)
			elseif gridSnap > 0 then
				distance = math.round(distance / gridSnap) * gridSnap
				localOffset = localOffset.Unit * math.max(distance, _Constants.MinSegmentLength)
			end
		end

		local offset = if basePart then basePart.CFrame:VectorToWorldSpace(localOffset) else localOffset
		if offset.Magnitude < 0.001 then local fallback = if basePart then basePart.CFrame.LookVector else Vector3.zAxis offset = fallback * _Constants.MinSegmentLength end
		local maxOffset = math.max(_Constants.MaxSegmentLength - forcedZ, _Constants.MinSegmentLength)
		if offset.Magnitude > maxOffset then offset = offset.Unit * maxOffset self.CurrentSnapTarget = nil end

		local endpoint = self.PointA + offset
		local center = self.PointA + (offset / 2)
		targetCF = CFrame.lookAt(center, center + offset, buildUp)
		primary.Size = Vector3.new(forcedX, forcedY, offset.Magnitude + forcedZ)
		self.CurrentPoint = endpoint
	else
		self.CurrentPoint = if isSegment then currentPoint else nil
	end

	local boxCF, boxSize = getBoundsAtPrimaryCFrame(ghostModel, targetCF)
	if _Constants.UseBase then isValid = basePart ~= nil and isBoxInsideBase(boxCF, boxSize, basePart :: BasePart) end
	if _Constants.DoCollisions and isValid then
		local collisionExcludes = getExcludes(self, true, basePart)
		local allowedConnections:{Instance} = {}
		if isSegment then
			if self.PointASnapTarget then table.insert(allowedConnections, self.PointASnapTarget) end
			if self.CurrentSnapTarget and self.CurrentSnapTarget ~= self.PointASnapTarget then
				table.insert(allowedConnections, self.CurrentSnapTarget)
			end
		end

		local parts = workspace:GetPartBoundsInBox(boxCF, getCollisionSize(boxSize), makeOverlapParams(collisionExcludes))
		for _, part in parts do
			if not isAllowedCollision(part, allowedConnections) then
				isValid = false
				break
			end
		end
	end

	self.CanPlace = isValid
	if self.HitboxVisual then self.HitboxVisual.Color3 = if isValid then VALID_COLOR else INVALID_COLOR end
	primary.CFrame = targetCF
end

function BuildClient:Rotate(direction:number)
	self.CurrentRotation = (self.CurrentRotation + (_Constants.RotationSnap * direction)) % 360
end

function BuildClient:Scale(direction:number)
	if self.PlacementMode == "Segment" then return end
	self.CurrentScale = math.clamp(self.CurrentScale + (0.1 * direction), _Constants.MinScale, _Constants.MaxScale)
	if self.GhostModel then self.GhostModel:ScaleTo(self.CurrentScale) end
end

function BuildClient:TryRemove()
	local mouseRay = getMouseRay(self.Player)
	local excludes:{Instance} = {}
	if self.Player.Character then table.insert(excludes, self.Player.Character) end
	local result = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 500, makeRaycastParams(excludes))
	if not result then return end

	local target = getBuildRoot(result.Instance)
	if not target or target:GetAttribute("Owner") ~= self.Player.UserId then return end
	RemoveRequest:InvokeServer(target)
end

function BuildClient:Unhook()
	if self._renderConnection then
		self._renderConnection:Disconnect()
		self._renderConnection = nil
	end
	if self.GhostModel then
		self.GhostModel:Destroy()
		self.GhostModel = nil
	end
	self.HitboxVisual = nil
	self.CanPlace = false
	resetSegmentState(self)
	self.OriginalSize = nil
	self.PlacementMode = "Single"
end

function BuildClient:Undo()
	UndoRequest:InvokeServer()
end

function BuildClient:Redo()
	RedoRequest:InvokeServer()
end

function BuildClient:Remove()
	self.IsRemoving = not self.IsRemoving
	self:Unhook()
end

return BuildClient
