--[[
		Filename: GamepadMenu.lua
		Written by: jeditkacheff
		Version 1.1
		Description: Controls the radial menu that appears when pressing menu button on gamepad
--]]

--[[ SERVICES ]]
local GuiService = game:GetService('GuiService')
local CoreGuiService = game:GetService('CoreGui')
local InputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')
local HttpService = game:GetService('HttpService')
local StarterGui = game:GetService('StarterGui')
local GuiRoot = CoreGuiService:WaitForChild('RobloxGui')
--[[ END OF SERVICES ]]

--[[ MODULES ]]
local tenFootInterface = require(GuiRoot.Modules.TenFootInterface)
local utility = require(GuiRoot.Modules.Settings.Utility)
local recordPage = require(GuiRoot.Modules.Settings.Pages.Record)

--[[ VARIABLES ]]
local gamepadSettingsFrame = nil
local isVisible = false
local smallScreen = utility:IsSmallTouchScreen()
local isTenFootInterface = tenFootInterface:IsEnabled()
local radialButtons = {}
local lastInputChangedCon = nil

local function getButtonForCoreGuiType(coreGuiType)
	if coreGuiType == Enum.CoreGuiType.All then
		return radialButtons
	else
		for button, table in pairs(radialButtons) do
			if table["CoreGuiType"] == coreGuiType then
				return button
			end
		end
	end

	return nil
end

local function getImagesForSlot(slot)
	if slot == 1 then		return "rbxasset://textures/ui/Settings/Radial/Top.png", "rbxasset://textures/ui/Settings/Radial/TopSelected.png",
									"rbxasset://textures/ui/Settings/Radial/Menu.png",
									UDim2.new(0.5,-26,0,18), UDim2.new(0,52,0,41),
									UDim2.new(0,150,0,100), UDim2.new(0.5,-75,0,0)
	elseif slot == 2 then	return "rbxasset://textures/ui/Settings/Radial/TopRight.png", "rbxasset://textures/ui/Settings/Radial/TopRightSelected.png",
									"rbxasset://textures/ui/Settings/Radial/PlayerList.png",
									UDim2.new(1,-90,0,90), UDim2.new(0,52,0,52),
									UDim2.new(0,108,0,150), UDim2.new(1,-110,0,50)
	elseif slot == 3 then	return "rbxasset://textures/ui/Settings/Radial/BottomRight.png", "rbxasset://textures/ui/Settings/Radial/BottomRightSelected.png",
									"rbxasset://textures/ui/Settings/Radial/Alert.png",
									UDim2.new(1,-85,1,-150), UDim2.new(0,42,0,58),
									UDim2.new(0,120,0,150), UDim2.new(1,-120,1,-200)
	elseif slot == 4 then 	return "rbxasset://textures/ui/Settings/Radial/Bottom.png", "rbxasset://textures/ui/Settings/Radial/BottomSelected.png",
									"rbxasset://textures/ui/Settings/Radial/Leave.png",
									UDim2.new(0.5,-20,1,-62), UDim2.new(0,55,0,46),
									UDim2.new(0,150,0,100), UDim2.new(0.5,-75,1,-100)
	elseif slot == 5 then	return "rbxasset://textures/ui/Settings/Radial/BottomLeft.png", "rbxasset://textures/ui/Settings/Radial/BottomLeftSelected.png",
									"rbxasset://textures/ui/Settings/Radial/Backpack.png",
									UDim2.new(0,40,1,-150), UDim2.new(0,44,0,56),
									UDim2.new(0,110,0,150), UDim2.new(0,0,0,205)
	elseif slot == 6 then	return "rbxasset://textures/ui/Settings/Radial/TopLeft.png", "rbxasset://textures/ui/Settings/Radial/TopLeftSelected.png",
									"rbxasset://textures/ui/Settings/Radial/Chat.png",
									UDim2.new(0,35,0,100), UDim2.new(0,56,0,53),
									UDim2.new(0,110,0,150), UDim2.new(0,0,0,50)
	end

	return "", "", UDim2.new(0,0,0,0), UDim2.new(0,0,0,0)
end

local function setSelectedRadialButton(selectedObject)
	for button, buttonTable in pairs(radialButtons) do
		local isVisible = (button == selectedObject)
		button:FindFirstChild("Selected").Visible = isVisible
		button:FindFirstChild("RadialLabel").Visible = isVisible
	end
end

local function activateSelectedRadialButton()
	for button, buttonTable in pairs(radialButtons) do
		if button:FindFirstChild("Selected").Visible then
			buttonTable["Function"]()
			return true
		end
	end

	return false
end

local function setButtonEnabled(button, enabled)
	if radialButtons[button]["Disabled"] == not enabled then return end
	
	if button:FindFirstChild("Selected").Visible == true then
		setSelectedRadialButton(nil)
	end
	
	if enabled then
		button.Image = string.gsub(button.Image, "rbxasset://textures/ui/Settings/Radial/Empty", "rbxasset://textures/ui/Settings/Radial/")
		button.ImageTransparency = 0
		button.RadialIcon.ImageTransparency = 0
	else
		button.Image = string.gsub(button.Image, "rbxasset://textures/ui/Settings/Radial/", "rbxasset://textures/ui/Settings/Radial/Empty")
		button.ImageTransparency = 0
		button.RadialIcon.ImageTransparency = 1
	end

	radialButtons[button]["Disabled"] = not enabled
end

local emptySelectedImageObject = utility:Create'ImageLabel'
{
	BackgroundTransparency = 1,
	Size = UDim2.new(1,0,1,0),
	Image = ""
};

local function createRadialButton(name, text, slot, disabled, coreGuiType, activateFunc)
	local slotImage, selectedSlotImage, slotIcon,
			slotIconPosition, slotIconSize, mouseFrameSize, mouseFramePos = getImagesForSlot(slot) 

	local radialButton = utility:Create'ImageButton'
	{
		Name = name,
		Position = UDim2.new(0,0,0,0),
		Size = UDim2.new(1,0,1,0),
		BackgroundTransparency = 1,
		Image = slotImage,
		ZIndex = 2,
		SelectionImageObject = emptySelectedImageObject,
		Parent = gamepadSettingsFrame
	};
	if disabled then
		radialButton.Image = string.gsub(radialButton.Image, "rbxasset://textures/ui/Settings/Radial/", "rbxasset://textures/ui/Settings/Radial/Empty")
	end

	local selectedRadial = utility:Create'ImageLabel'
	{
		Name = "Selected",
		Position = UDim2.new(0,0,0,0),
		Size = UDim2.new(1,0,1,0),
		BackgroundTransparency = 1,
		Image = selectedSlotImage,
		ZIndex = 2,
		Visible = false,
		Parent = radialButton
	};

	local radialIcon = utility:Create'ImageLabel'
	{
		Name = "RadialIcon",
		Position = slotIconPosition,
		Size = slotIconSize,
		BackgroundTransparency = 1,
		Image = slotIcon,
		ZIndex = 3,
		ImageTransparency = disabled and 1 or 0,
		Parent = radialButton
	};

	local nameLabel = utility:Create'TextLabel'
	{

		Size = UDim2.new(0,220,0,50),
		Position = UDim2.new(0.5, -110, 0.5, -25),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.SourceSansBold,
		FontSize = Enum.FontSize.Size14,
		TextColor3 = Color3.new(1,1,1),
		Name = "RadialLabel",
		Visible = false,
		ZIndex = 2,
		Parent = radialButton
	};
	if not smallScreen then
		nameLabel.FontSize = Enum.FontSize.Size36
		nameLabel.Size = UDim2.new(nameLabel.Size.X.Scale, nameLabel.Size.X.Offset, nameLabel.Size.Y.Scale, nameLabel.Size.Y.Offset + 4)
	end
	local nameBackgroundImage = utility:Create'ImageLabel'
	{
		Name = text .. "BackgroundImage",
		Size = UDim2.new(1,0,1,0),
		Position = UDim2.new(0,0,0,2),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/Settings/Radial/RadialLabel@2x.png",
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(24,4,130,42),
		ZIndex = 2,
		Parent = nameLabel
	};

	local mouseFrame = utility:Create'ImageButton'
	{
		Name = "MouseFrame",
		Position = mouseFramePos,
		Size = mouseFrameSize,
		ZIndex = 3,
		BackgroundTransparency = 1,
		SelectionImageObject = emptySelectedImageObject,
		Parent = radialButton
	};

	mouseFrame.MouseEnter:connect(function()
		if not radialButtons[radialButton]["Disabled"] then
			setSelectedRadialButton(radialButton)
		end
	end)
	mouseFrame.MouseLeave:connect(function()
		setSelectedRadialButton(nil)
	end)

	mouseFrame.MouseButton1Click:connect(function()
		if selectedRadial.Visible then
			activateFunc()
		end
	end)

	radialButtons[radialButton] = {["Function"] = activateFunc, ["Disabled"] = disabled, ["CoreGuiType"] = coreGuiType}

	return radialButton
end

local function createGamepadMenuGui()
	gamepadSettingsFrame = utility:Create'Frame'
	{
		Name = "GamepadSettingsFrame",
		Position = UDim2.new(0.5,-51,0.5,-51),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0,102,0,102),
		Visible = false,
		Parent = GuiRoot
	};

	---------------------------------
	-------- Settings Menu ----------
	local settingsFunc = function()
		toggleCoreGuiRadial(true)
		local MenuModule = require(GuiRoot.Modules.Settings.SettingsHub)
		MenuModule:SetVisibility(true, nil, nil, true)
	end
	local settingsRadial = createRadialButton("Settings", "Settings", 1, false, nil, settingsFunc)
	settingsRadial.Parent = gamepadSettingsFrame

	---------------------------------
	-------- Player List ------------
	local playerListFunc = function() 
		toggleCoreGuiRadial(true)
		local PlayerListModule = require(GuiRoot.Modules.PlayerlistModule)
		if not PlayerListModule:IsOpen() then
			PlayerListModule:ToggleVisibility()
		end
	end
	local playerListRadial = createRadialButton("PlayerList", "Player List", 2, not StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList), Enum.CoreGuiType.PlayerList, playerListFunc)
	playerListRadial.Parent = gamepadSettingsFrame

	---------------------------------
	-------- Notifications ----------
	local gamepadNotifications = Instance.new("BindableEvent")
	gamepadNotifications.Name = "GamepadNotifications"
	gamepadNotifications.Parent = script
	local notificationsFunc = function()
		toggleCoreGuiRadial()
		gamepadNotifications:Fire(true)
	end
	local notificationsRadial = createRadialButton("Notifications", "Notifications", 3, false, nil, notificationsFunc)
	if isTenFootInterface then
		setButtonEnabled(notificationsRadial, false)
	end
	notificationsRadial.Parent = gamepadSettingsFrame

	---------------------------------
	---------- Leave Game -----------
	local leaveGameFunc = function()
		toggleCoreGuiRadial(true)
		local MenuModule = require(GuiRoot.Modules.Settings.SettingsHub)
		MenuModule:SetVisibility(true, false, require(GuiRoot.Modules.Settings.Pages.LeaveGame), true)
	end
	local leaveGameRadial = createRadialButton("LeaveGame", "Leave Game", 4, false, nil, leaveGameFunc)
	leaveGameRadial.Parent = gamepadSettingsFrame

	---------------------------------
	---------- Backpack -------------
	local backpackFunc = function()
		toggleCoreGuiRadial(true)
		local BackpackModule = require(GuiRoot.Modules.BackpackScript)
		BackpackModule:OpenClose() 
	end
	local backpackRadial = createRadialButton("Backpack", "Backpack", 5, not StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack), Enum.CoreGuiType.Backpack, backpackFunc)
	backpackRadial.Parent = gamepadSettingsFrame

	---------------------------------
	------------ Chat ---------------
	local chatFunc = function() 
		toggleCoreGuiRadial()
		local ChatModule = require(GuiRoot.Modules.Chat)
		ChatModule:ToggleVisibility()
	end
	local chatRadial = createRadialButton("Chat", "Chat", 6, not StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat), Enum.CoreGuiType.Chat, chatFunc)
	if isTenFootInterface then
		setButtonEnabled(chatRadial, false)
	end
	chatRadial.Parent = gamepadSettingsFrame


	---------------------------------
	--------- Close Button ----------
	local closeHintImage = utility:Create'ImageLabel'
	{
		Name = "CloseHint",
		Position = UDim2.new(1,10,1,10),
		Size = UDim2.new(0,60,0,60),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/Settings/Help/BButtonDark.png",
		Parent = gamepadSettingsFrame
	}
	if isTenFootInterface then
		closeHintImage.Image = "rbxasset://textures/ui/Settings/Help/BButtonDark@2x.png"
		closeHintImage.Size =  UDim2.new(0,90,0,90)
	end

	local closeHintText = utility:Create'TextLabel'
	{
		Name = "closeHintText",
		Position = UDim2.new(1,10,0.5,-12),
		Size = UDim2.new(0,43,0,24),
		Font = Enum.Font.SourceSansBold,
		FontSize = Enum.FontSize.Size24,
		BackgroundTransparency = 1,
		Text = "Back",
		TextColor3 = Color3.new(1,1,1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = closeHintImage
	}
	if isTenFootInterface then
		closeHintText.FontSize = Enum.FontSize.Size36
	end

	------------------------------------------
	--------- Stop Recording Button ----------
	--todo: enable this when recording is not a verb
	--[[local stopRecordingImage = utility:Create'ImageLabel'
	{
		Name = "StopRecordingHint",
		Position = UDim2.new(0,-100,1,10),
		Size = UDim2.new(0,61,0,61),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/Settings/Help/YButtonDark.png",
		Visible = recordPage:IsRecording(),
		Parent = gamepadSettingsFrame
	}
	local stopRecordingText = utility:Create'TextLabel'
	{
		Name = "stopRecordingHintText",
		Position = UDim2.new(1,10,0.5,-12),
		Size = UDim2.new(0,43,0,24),
		Font = Enum.Font.SourceSansBold,
		FontSize = Enum.FontSize.Size24,
		BackgroundTransparency = 1,
		Text = "Stop Recording",
		TextColor3 = Color3.new(1,1,1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = stopRecordingImage
	}

	recordPage.RecordingChanged:connect(function(isRecording)
		stopRecordingImage.Visible = isRecording
	end)]]

	GuiService:AddSelectionParent(HttpService:GenerateGUID(false), gamepadSettingsFrame)

	gamepadSettingsFrame.Changed:connect(function(prop)
		if prop == "Visible" then
			if not gamepadSettingsFrame.Visible then
				unbindAllRadialActions()
			end
		end
	end)
end

local function isCoreGuiDisabled()
	for _, enumItem in pairs(Enum.CoreGuiType:GetEnumItems()) do
		if StarterGui:GetCoreGuiEnabled(enumItem) then
			return false
		end
	end

	return true
end

local function setupGamepadControls()
	local freezeControllerActionName = "doNothingAction"
	local radialSelectActionName = "RadialSelectAction"
	local thumbstick2RadialActionName = "Thumbstick2RadialAction"
	local radialCancelActionName = "RadialSelectCancel"
	local radialAcceptActionName = "RadialSelectAccept"
	local toggleMenuActionName = "RBXToggleMenuAction"

	local noOpFunc = function() end
	local doGamepadMenuButton = nil

	function unbindAllRadialActions()
		local success = pcall(function() GuiService.CoreGuiNavigationEnabled = true end)
		if not success then
			GuiService.GuiNavigationEnabled = true
		end

		ContextActionService:UnbindCoreAction(radialSelectActionName)
		ContextActionService:UnbindCoreAction(radialCancelActionName)
		ContextActionService:UnbindCoreAction(radialAcceptActionName)
		ContextActionService:UnbindCoreAction(freezeControllerActionName)
		ContextActionService:UnbindCoreAction(thumbstick2RadialActionName)
	end
	
	local radialButtonLayout = {	PlayerList = 	{
														Range = {	Begin = 36,
																	End = 96
																}
													},
									Notifications = {	
														Range = {	Begin = 96,
																	End = 156
																}
													},
									LeaveGame = 	{	
														Range = {	Begin = 156,
																	End = 216
																}
													},	
									Backpack = 		{	
														Range = {	Begin = 216,
																	End = 276
																}
													},			
									Chat = 			{	
														Range = {	Begin = 276,
																	End = 336
																}
													},			
									Settings = 		{	
														Range = {	Begin = 336,
																	End = 36
																}
													},															
								}
	
	
	local function getSelectedObjectFromAngle(angle, depth)
		local closest = nil
		local closestDistance = 30 -- threshold of 30 for selecting the closest radial button
		for radialKey, buttonLayout in pairs(radialButtonLayout) do
			if radialButtons[gamepadSettingsFrame[radialKey]]["Disabled"] == false then
				--Check for exact match
				if buttonLayout.Range.Begin < buttonLayout.Range.End then
					if angle > buttonLayout.Range.Begin and angle <= buttonLayout.Range.End then
						return gamepadSettingsFrame[radialKey]
					end
				else 
					if angle > buttonLayout.Range.Begin or angle <= buttonLayout.Range.End then
						return gamepadSettingsFrame[radialKey]
					end
				end
				--Check if this is the closest button so far
				local distanceBegin = math.min(math.abs((buttonLayout.Range.Begin + 360) - angle), math.abs(buttonLayout.Range.Begin - angle))
				local distanceEnd = math.min(math.abs((buttonLayout.Range.End + 360) - angle), math.abs(buttonLayout.Range.End - angle))
				local distance = math.min(distanceBegin, distanceEnd)
				if distance < closestDistance then
					closestDistance = distance
					closest = gamepadSettingsFrame[radialKey]
				end
			end
		end
		return closest
	end

	local radialSelect = function(name, state, input)
		local inputVector = Vector2.new(0,0)

		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			inputVector = Vector2.new(input.Position.x, input.Position.y)
		end

		local selectedObject = nil

		if inputVector.magnitude > 0.8 then
			
			local angle =  math.atan2(inputVector.X, inputVector.Y) * 180 / math.pi
			if angle < 0 then
				angle = angle + 360
			end

			selectedObject = getSelectedObjectFromAngle(angle)

			setSelectedRadialButton(selectedObject)
		end
	end

	local radialSelectAccept = function(name, state, input)
		if gamepadSettingsFrame.Visible and state == Enum.UserInputState.Begin then
			activateSelectedRadialButton()
		end
	end

	local radialSelectCancel = function(name, state, input)
		if gamepadSettingsFrame.Visible and state == Enum.UserInputState.Begin then
			toggleCoreGuiRadial()
		end
	end

	function setVisibility()
		local children = gamepadSettingsFrame:GetChildren()
		for i = 1, #children do
			if children[i]:FindFirstChild("RadialIcon") then
				children[i].RadialIcon.Visible = isVisible
			end
			if children[i]:FindFirstChild("RadialLabel") and not isVisible then
				children[i].RadialLabel.Visible = isVisible
			end
		end
	end

	function setOverrideMouseIconBehavior()
		pcall(function()
			if InputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
				InputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceHide
			else
				InputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
			end
		end)
	end

	function toggleCoreGuiRadial(goingToSettings)
		isVisible = not gamepadSettingsFrame.Visible
		
		setVisibility()

		if isVisible then
			setOverrideMouseIconBehavior()
			pcall(function() lastInputChangedCon = InputService.LastInputTypeChanged:connect(setOverrideMouseIconBehavior) end)

			gamepadSettingsFrame.Visible = isVisible

			local settingsChildren = gamepadSettingsFrame:GetChildren()
			for i = 1, #settingsChildren do
				if settingsChildren[i]:IsA("GuiButton") then
					utility:TweenProperty(settingsChildren[i], "ImageTransparency", 1, 0, 0.1, utility:GetEaseOutQuad(), nil)
				end
			end
			gamepadSettingsFrame:TweenSizeAndPosition(UDim2.new(0,408,0,408), UDim2.new(0.5,-204,0.5,-204),
														Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.18, true,
				function()
					setVisibility()
			end)
		else
			if lastInputChangedCon ~= nil then
				lastInputChangedCon:disconnect()
				lastInputChangedCon = nil
			end
			pcall(function() InputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None end)

			local settingsChildren = gamepadSettingsFrame:GetChildren()
			for i = 1, #settingsChildren do
				if settingsChildren[i]:IsA("GuiButton") then
					utility:TweenProperty(settingsChildren[i], "ImageTransparency", 0, 1, 0.1, utility:GetEaseOutQuad(), nil)
				end
			end
			gamepadSettingsFrame:TweenSizeAndPosition(UDim2.new(0,102,0,102), UDim2.new(0.5,-51,0.5,-51),
														Enum.EasingDirection.Out, Enum.EasingStyle.Sine, 0.1, true, 
				function()
					if not goingToSettings and not isVisible then GuiService:SetMenuIsOpen(false) end
					gamepadSettingsFrame.Visible = isVisible
			end)
		end

		if isVisible then
			setSelectedRadialButton(nil)

			local success = pcall(function() GuiService.CoreGuiNavigationEnabled = false end)
			if not success then
				GuiService.GuiNavigationEnabled = false
			end

			GuiService:SetMenuIsOpen(true)

			ContextActionService:BindCoreAction(freezeControllerActionName, noOpFunc, false, Enum.UserInputType.Gamepad1)
			ContextActionService:BindCoreAction(radialAcceptActionName, radialSelectAccept, false, Enum.KeyCode.ButtonA)
			ContextActionService:BindCoreAction(radialCancelActionName, radialSelectCancel, false, Enum.KeyCode.ButtonB)
			ContextActionService:BindCoreAction(radialSelectActionName, radialSelect, false, Enum.KeyCode.Thumbstick1)
			ContextActionService:BindCoreAction(thumbstick2RadialActionName, noOpFunc, false, Enum.KeyCode.Thumbstick2)
			ContextActionService:BindCoreAction(toggleMenuActionName, doGamepadMenuButton, false, Enum.KeyCode.ButtonStart)
		else
			unbindAllRadialActions()
		end

		return gamepadSettingsFrame.Visible
	end

	doGamepadMenuButton = function(name, state, input)
		if state ~= Enum.UserInputState.Begin then return end

		if not toggleCoreGuiRadial() then
			unbindAllRadialActions()
		end
	end

	if InputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		createGamepadMenuGui()
	else
		InputService.GamepadConnected:connect(function(gamepadEnum) 
			if gamepadEnum == Enum.UserInputType.Gamepad1 then
				createGamepadMenuGui()
			end
		end)
	end

	local function setRadialButtonEnabled(coreGuiType, enabled)
		local returnValue = getButtonForCoreGuiType(coreGuiType)
		if not returnValue then return end

		local buttonsToDisable = {}
		if type(returnValue) == "table" then
			for button, buttonTable in pairs(returnValue) do
				if buttonTable["CoreGuiType"] then
					if isTenFootInterface and buttonTable["CoreGuiType"] == Enum.CoreGuiType.Chat then
					else
						buttonsToDisable[#buttonsToDisable + 1] = button
					end
				end
			end
		else
			if isTenFootInterface and returnValue.Name == "Chat" then
			else
				buttonsToDisable[1] = returnValue
			end
		end

		for i = 1, #buttonsToDisable do
			local button = buttonsToDisable[i]
			setButtonEnabled(button, enabled)
		end
	end
	StarterGui.CoreGuiChangedSignal:connect(setRadialButtonEnabled)

	ContextActionService:BindCoreAction(toggleMenuActionName, doGamepadMenuButton, false, Enum.KeyCode.ButtonStart)
end

-- hook up gamepad stuff
setupGamepadControls()
