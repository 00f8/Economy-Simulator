--[[
			// LoadingWidget.lua

			// Created by Kip Turner
			// Copyright Roblox 2015
]]


local CoreGui = Game:GetService("CoreGui")
local GuiRoot = CoreGui:FindFirstChild("RobloxGui")
local Modules = GuiRoot:FindFirstChild("Modules")
local GuiService = game:GetService('GuiService')

local Utility = require(Modules:FindFirstChild('Utility'))


local function CreateLoadingWidget(properties, loadingFunctions)
	properties = properties or {}
	loadingFunctions = loadingFunctions or {}

	local this = {}

	local completedFunctions = {}
	local cancelled = false
	local finishedConn = Utility.Signal()

	local loadIcon = Utility.Create'ImageLabel'
	{
		Name = "LoadIcon";
		BackgroundTransparency = 1;
		Image = 'rbxasset://textures/ui/Shell/Icons/LoadingSpinner@1080.png';
		Size = properties.Size or UDim2.new(0,99,0,100);
		ZIndex = properties.ZIndex or 7;
		Parent = properties.Parent;
	}
	Utility.CalculateAnchor(loadIcon, properties.Position or UDim2.new(0.5,0,0.5,0), Utility.Enum.Anchor.Center)

	if properties.Visible == false then
		loadIcon.Visible = false
	end

	local function isLoadingComplete()
		return #completedFunctions == #loadingFunctions
	end

	function this:AwaitFinished()
		if isLoadingComplete() then
			return true
		end
		finishedConn:wait()
		if cancelled then
			return false
		end
		return true
	end

	function this:Cleanup()
		loadIcon.Parent = nil
		loadIcon:Destroy()
		cancelled = true
	end


	-- Run it!
	for _, loadingFunction in pairs(loadingFunctions) do
		spawn(function()
			loadingFunction()
			table.insert(completedFunctions, loadingFunction)
		end)
	end

	spawn(function()
		local t = tick()
		while not (cancelled or isLoadingComplete()) do
			local now = tick()
			local rotation = (now - t) * 360
			if loadIcon.Parent then
				loadIcon.Rotation = loadIcon.Rotation + rotation
			end
			t = now
			wait()
		end
		finishedConn.fire()
	end)

	return this
end

return CreateLoadingWidget
