local player = game:GetService('Players').LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local bindables = player:WaitForChild('PlayerScripts'):WaitForChild('Bindables')
local BuildClient = require(game:GetService('ReplicatedStorage').BuildSystem.BuildClient)
local newBuild = BuildClient.new()
bindables.InitiateBuild.Event:Connect(function(obj, type)
	newBuild:Hook(obj, type)
end)
