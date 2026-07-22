--!strict
-- BuildClient.lua -> Handles the client-sided build logic.
-- Created by Jacksxity (07/20/2026)

--[[ Services ]]--
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--[[ Variables ]]--
local BuildSystemFolder = ReplicatedStorage:WaitForChild('BuildSystem')
local _Keybinds = require(BuildSystemFolder:WaitForChild('_Keybinds'))
local _Constants = require(BuildSystemFolder:WaitForChild('_Constants'))
local _Types = require(BuildSystemFolder:WaitForChild('_Types'))

local Remotes = BuildSystemFolder:WaitForChild("Remotes")
local PlaceRequest = Remotes:WaitForChild("PlaceRequest") :: RemoteFunction
local RemoveRequest = Remotes:WaitForChild("RemoveRequest") :: RemoteFunction
local UndoRequest = Remotes:WaitForChild("UndoRequest") :: RemoteFunction
local RedoRequest = Remotes:WaitForChild("RedoRequest") :: RemoteFunction
local BuildClient = {} BuildClient.__index = BuildClient

--[[ Functions ]]--
function BuildClient.new() : _Types.BuildClient
	--[[ Constructor ]]--
	local self = setmetatable({Player = Players.LocalPlayer, GhostModel = nil, HitboxVisual = nil, IsRemoving = false, CurrentRotation = 0, CurrentScale = 1, _renderConnection = nil, PointA = nil, PlacementMode = "Single", OriginalSize = nil}, BuildClient)
	self:BindInputs()
	return self
end

function BuildClient:Hook(targetObject:Instance, mode:string?)
	--[[ Hook/Equip Function ]]--
	self:Unhook()
	self.PlacementMode = mode or "Single"
	self.PointA = nil
	self.OriginalSize = nil

	if targetObject:IsA("BasePart") then
		local model = Instance.new("Model") model.Name = targetObject.Name local clone = targetObject:Clone() clone.Parent = model model.PrimaryPart = clone self.GhostModel = model
	elseif targetObject:IsA("Model") and targetObject.PrimaryPart then 
		self.GhostModel = targetObject:Clone()
	else 
		warn("Invalid object: Must be a BasePart or a Model with a PrimaryPart.") 
		return 
	end

	if self.GhostModel then
		self.GhostModel.Parent = workspace
		local primary = self.GhostModel.PrimaryPart
		if primary then
			primary.Anchored = true
			primary.CanCollide = false
			self.OriginalSize = primary.Size

			local isSinglePart = true
			for _, p in self.GhostModel:GetDescendants() do if p:IsA("BasePart") and p ~= primary then isSinglePart = false break end end
			primary.Transparency = if isSinglePart then 0.5 else 1

			local box = Instance.new("SelectionBox") box.Adornee = primary box.Color3 = Color3.fromRGB(0, 255, 0) box.LineThickness = 0.05 box.Parent = self.GhostModel self.HitboxVisual = box
		end
		for _, part in self.GhostModel:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				if part ~= primary then
					part.Transparency = 0.5
					local weld = Instance.new("WeldConstraint") weld.Part0 = primary weld.Part1 = part weld.Parent = primary part.Anchored = false
				end
			end
		end
	end
	if self._renderConnection then self._renderConnection:Disconnect() end
	self._renderConnection = RunService.RenderStepped:Connect(function() self:Move() end)
end

function BuildClient:BindInputs()
	--[[ Binding User Inputs ]]--
	ContextActionService:BindAction("Build_Place", function(_, state, input) if state == Enum.UserInputState.Begin then self:Place(input) end return Enum.ContextActionResult.Pass end, true, _Keybinds.Place)
	ContextActionService:BindAction("Build_RotateCW", function(_, state) if state == Enum.UserInputState.Begin then self:Rotate(1) end return Enum.ContextActionResult.Pass end, true, _Keybinds.RotateCW)
	ContextActionService:BindAction("Build_RotateCCW", function(_, state) if state == Enum.UserInputState.Begin then self:Rotate(-1) end return Enum.ContextActionResult.Pass end, true, _Keybinds.RotateCCW)
	ContextActionService:BindAction("Build_ScaleIncrease", function(_, state) if state == Enum.UserInputState.Begin then self:Scale(1) end return Enum.ContextActionResult.Pass end, true, _Keybinds.ScaleIncrease)
	ContextActionService:BindAction("Build_ScaleDecrease", function(_, state) if state == Enum.UserInputState.Begin then self:Scale(-1) end return Enum.ContextActionResult.Pass end, true, _Keybinds.ScaleDecrease)
	ContextActionService:BindAction("Build_Sledgehammer", function(_, state) if state == Enum.UserInputState.Begin then self:Remove() end return Enum.ContextActionResult.Pass end, true, _Keybinds.Sledgehammer)
	ContextActionService:BindAction("Build_Cancel", function(_, state) if state == Enum.UserInputState.Begin then self:Unhook() end return Enum.ContextActionResult.Pass end, false, _Keybinds.Cancel)

	UserInputService.InputBegan:Connect(function(input, gpe)
		local function checkCombo(keys)
			if typeof(keys) == "table" then
				local matched = false
				for _, k in keys do 
					if k == input.KeyCode or k == input.UserInputType then 
						matched = true 
					elseif not UserInputService:IsKeyDown(k) then 
						return false 
					end 
				end
				return matched
			end
			return input.KeyCode == keys or input.UserInputType == keys
		end

		if checkCombo(_Keybinds.Undo) then 
			self:Undo() 
			return
		elseif checkCombo(_Keybinds.Redo) then 
			self:Redo() 
			return
		elseif checkCombo(_Keybinds.NoSnap) then
			self.CurrentRotation = 0
		end

		if gpe then return end
	end)
end

function BuildClient:Place(input:InputObject)
	--[[ Client Placement Function ]]--
	if self.IsRemoving or not self.GhostModel then return end
	if self.HitboxVisual and self.HitboxVisual.Color3 == Color3.fromRGB(255, 0, 0) then return end
	if self.PlacementMode == "Segment" and not self.PointA then self.PointA = self.GhostModel:GetPivot().Position return end

	local scaleOrSize = if self.PlacementMode == "Segment" then (self.GhostModel.PrimaryPart :: BasePart).Size else self.CurrentScale
	local success = PlaceRequest:InvokeServer(self.GhostModel.Name, self.GhostModel:GetPivot(), scaleOrSize)
	if success then 
		if self.PlacementMode == "Segment" then 
			local _, y, _ = self.GhostModel:GetPivot():ToEulerAnglesYXZ()
			self.CurrentRotation = math.deg(y)

			self.PointA = nil 
			if self.OriginalSize and self.GhostModel.PrimaryPart then
				(self.GhostModel.PrimaryPart :: BasePart).Size = self.OriginalSize
			end
		end
		if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then self:Unhook() end 
	else 
		warn("Server rejected placement!") 
		if self.PlacementMode == "Segment" then 
			self.PointA = nil 
			if self.OriginalSize and self.GhostModel.PrimaryPart then
				(self.GhostModel.PrimaryPart :: BasePart).Size = self.OriginalSize
			end
		end
	end
end

function BuildClient:Move()
	--[[ Client Movement Function ]]--
	if not self.GhostModel then return end
	local mouse = self.Player:GetMouse()
	local params = RaycastParams.new() params.FilterType = Enum.RaycastFilterType.Exclude
	local filters = {self.GhostModel} if self.Player.Character then table.insert(filters, self.Player.Character) end params.FilterDescendantsInstances = filters
	local unitRay = workspace.CurrentCamera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, params)
	local hitPos = result and result.Position or (unitRay.Origin + unitRay.Direction * 50)
	local folder = self.Player:FindFirstChild("BuildSystem")
	local baseRef = folder and folder:FindFirstChild("Base") :: ObjectValue
	local basePart = if baseRef and baseRef.Value then (if baseRef.Value:IsA("BasePart") then baseRef.Value elseif baseRef.Value:IsA("Model") then baseRef.Value.PrimaryPart else nil) else nil
	local isValid = true

	if self.PlacementMode == "Segment" and _Constants.UseBase and basePart then
		local planeNormal = basePart.CFrame.UpVector
		local planePoint = basePart.Position + (planeNormal * (basePart.Size.Y / 2))
		local denominator = unitRay.Direction:Dot(planeNormal)
		if math.abs(denominator) > 0.0001 then
			local t = (planePoint - unitRay.Origin):Dot(planeNormal) / denominator
			if t > 0 then hitPos = unitRay.Origin + (unitRay.Direction * t) end
		end
	end

	local isSnappingEnabled = not UserInputService:IsKeyDown(_Keybinds.NoSnap)
	local currentSnap = if isSnappingEnabled then _Constants.GridSnap else 0
	local primary = self.GhostModel.PrimaryPart :: BasePart
	local snappedToNode = false
	local forcedX = if self.OriginalSize then self.OriginalSize.X else primary.Size.X
	local forcedY = if self.OriginalSize then self.OriginalSize.Y else primary.Size.Y
	local forcedZ = if self.OriginalSize then self.OriginalSize.Z else primary.Size.Z

	if isSnappingEnabled and self.PlacementMode == "Segment" then
		local closestDist = 2
		local closestPoint = nil
		for _, obj in workspace:GetChildren() do
			if obj:GetAttribute("Owner") and obj ~= self.GhostModel then
				local part = if obj:IsA("Model") then obj.PrimaryPart else (if obj:IsA("BasePart") then obj else nil)
				if part then
					local pCF, pSize = part.CFrame, part.Size local nodeDist = math.max((pSize.Z - forcedZ) / 2, 0)
					local p1 = (pCF * CFrame.new(0, 0, -nodeDist)).Position local p2 = (pCF * CFrame.new(0, 0, nodeDist)).Position
					local d1, d2 = (hitPos - p1).Magnitude, (hitPos - p2).Magnitude

					if d1 < closestDist then closestDist = d1; closestPoint = p1 end
					if d2 < closestDist then closestDist = d2; closestPoint = p2 end
				end
			end
		end

		if closestPoint then hitPos = closestPoint snappedToNode = true end
	end

	if currentSnap > 0 and not snappedToNode then
		if _Constants.UseBase and basePart then
			local localPos = basePart.CFrame:PointToObjectSpace(hitPos)
			localPos = Vector3.new(math.round(localPos.X / currentSnap) * currentSnap, localPos.Y, math.round(localPos.Z / currentSnap) * currentSnap)
			hitPos = basePart.CFrame:PointToWorldSpace(localPos)
		else
			hitPos = Vector3.new(math.round(hitPos.X / currentSnap) * currentSnap, hitPos.Y, math.round(hitPos.Z / currentSnap) * currentSnap)
		end
	end

	local yOffset = if self.PlacementMode == "Segment" then primary.Size.Y / 2 else 0
	local targetCF = CFrame.new(hitPos + Vector3.new(0, yOffset, 0)) * CFrame.Angles(0, math.rad(self.CurrentRotation), 0)
	if self.PlacementMode == "Segment" and self.PointA then
		local flatHit = Vector3.new(hitPos.X, self.PointA.Y, hitPos.Z)
		local offset = flatHit - self.PointA
		if isSnappingEnabled and _Constants.SegmentAngleSnap > 0 and offset.Magnitude > 0.001 then
			local rawAngle = math.atan2(offset.Z, offset.X)
			local snapRad = math.rad(_Constants.SegmentAngleSnap)
			local snappedAngle = math.round(rawAngle / snapRad) * snapRad
			local dir = Vector3.new(math.cos(snappedAngle), 0, math.sin(snappedAngle))
			offset = dir * math.max(offset:Dot(dir), 0.1)
		end

		local length = math.max(offset.Magnitude, 0.1) + forcedZ
		local center = self.PointA + (offset / 2)
		if offset.Magnitude > 0.001 then
			targetCF = CFrame.lookAt(center, center + offset)
		else
			targetCF = CFrame.new(center) * CFrame.Angles(0, math.rad(self.CurrentRotation), 0)
		end
		primary.Size = Vector3.new(forcedX, forcedY, length)
	end

	if _Constants.UseBase then
		if basePart then
			local localCf = basePart.CFrame:ToObjectSpace(targetCF)
			local size = basePart.Size
			local objSize = if self.PlacementMode == "Segment" then primary.Size else primary.Size * self.CurrentScale
			local sx, sy, sz = objSize.X / 2, objSize.Y / 2, objSize.Z / 2
			local corners = {Vector3.new(sx,sy,sz), Vector3.new(-sx,sy,sz), Vector3.new(sx,-sy,sz), Vector3.new(-sx,-sy,sz), Vector3.new(sx,sy,-sz), Vector3.new(-sx,sy,-sz), Vector3.new(sx,-sy,-sz), Vector3.new(-sx,-sy,-sz)}
			for _, corner in corners do
				local cb = localCf * corner
				if math.abs(cb.X) > (size.X / 2) + 0.01 or math.abs(cb.Z) > (size.Z / 2) + 0.01 or cb.Y < -0.01 then isValid = false break end
			end
		else isValid = false end
	end

	if _Constants.DoCollisions and isValid then
		local overlap = OverlapParams.new() overlap.FilterType = Enum.RaycastFilterType.Exclude
		local excludes = {self.GhostModel} 
		if basePart then table.insert(excludes, basePart) end 
		if self.Player.Character then table.insert(excludes, self.Player.Character) end
		overlap.FilterDescendantsInstances = excludes

		local objSize = if self.PlacementMode == "Segment" then primary.Size else primary.Size * self.CurrentScale
		local collisionBox = objSize - Vector3.new(0.02, 0.02, 0.02)
		local parts = workspace:GetPartBoundsInBox(targetCF, collisionBox, overlap)
		if #parts > 0 then isValid = false end
	end

	if self.HitboxVisual then self.HitboxVisual.Color3 = isValid and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0) end
	if self.PlacementMode == "Segment" and self.PointA then
		primary.CFrame = targetCF
	else
		local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		TweenService:Create(primary, tweenInfo, {CFrame = targetCF}):Play()
	end
end

function BuildClient:Rotate(direction:number)
	--[[ Client Rotation Function ]]--
	self.CurrentRotation += (_Constants.RotationSnap * direction) 
end

function BuildClient:Scale(direction:number) 
	--[[ Client Scaling Function ]]--
	self.CurrentScale = math.clamp(self.CurrentScale + (0.1 * direction), _Constants.MinScale, _Constants.MaxScale) 
	if self.GhostModel then self.GhostModel:ScaleTo(self.CurrentScale) end 
end

function BuildClient:Unhook()
	--[[ Unhook/Unequip Function ]]--
	if self._renderConnection then self._renderConnection:Disconnect() end 
	if self.GhostModel then self.GhostModel:Destroy() self.GhostModel = nil self.HitboxVisual = nil end
	self.PointA = nil
	self.OriginalSize = nil
	self.PlacementMode = "Single"
end

function BuildClient:Undo()
	--[[ Undo Function ]]--
	UndoRequest:InvokeServer() 
end

function BuildClient:Redo()
	--[[ Redo Function ]]--
	RedoRequest:InvokeServer() 
end

function BuildClient:Remove()
	--[[ Client Sledgehammer/Remove Function ]]--
	self.IsRemoving = not self.IsRemoving 
	self:Unhook() 
end

return BuildClient
