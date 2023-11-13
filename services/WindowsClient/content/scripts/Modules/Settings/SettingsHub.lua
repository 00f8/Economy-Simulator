--[[
		Filename: SettingsHub.lua
		Written by: jeditkacheff
		Version 1.0
		Description: Controls the settings menu navigation and contains the settings pages
--]]

--[[ CONSTANTS ]]
local SETTINGS_SHIELD_COLOR = Color3.new(41/255,41/255,41/255)
local SETTINGS_SHIELD_TRANSPARENCY = 0.2
local SETTINGS_SHIELD_SIZE = UDim2.new(1, 0, 1, 0)
local SETTINGS_SHIELD_INACTIVE_POSITION = UDim2.new(0,0,-1,-36)
local SETTINGS_SHIELD_ACTIVE_POSITION = UDim2.new(0, 0, 0, 0)
local SETTINGS_BASE_ZINDEX = 2
local DEV_CONSOLE_ACTION_NAME = "Open Dev Console"

--[[ SERVICES ]]
local CoreGui = game:GetService("CoreGui")
local RobloxGui = CoreGui:WaitForChild("RobloxGui")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

--[[ UTILITIES ]]
local utility = require(RobloxGui.Modules.Settings.Utility)

--[[ VARIABLES ]]
local isTouchDevice = UserInputService.TouchEnabled
local isSmallTouchScreen = utility:IsSmallTouchScreen()
RobloxGui:WaitForChild("Modules"):WaitForChild("TenFootInterface")
local isTenFootInterface = require(RobloxGui.Modules.TenFootInterface):IsEnabled()
local platform = UserInputService:GetPlatform()
-- TODO: Change dev console script to parent this to somewhere other than an engine created gui
local ControlFrame = RobloxGui:WaitForChild('ControlFrame')
local ToggleDevConsoleBindableFunc = ControlFrame:WaitForChild('ToggleDevConsole')
local lastInputChangedCon = nil
local chatWasVisible = false
local userlistSuccess, userlistFlagValue = pcall(function() return settings():GetFFlag("UseUserListMenu") end)
local useUserList = (userlistSuccess and userlistFlagValue == true)


local function IsPlayMyPlaceEnabled()
	if UserInputService:GetPlatform() == Enum.Platform.XBoxOne then
		local playMyPlaceSuccess, playMyPlaceFlagValue = pcall(function() return settings():GetFFlag("XboxPlayMyPlace") end)
		return (playMyPlaceSuccess and playMyPlaceFlagValue == true)
	end
	return false
end


--[[ CORE MODULES ]]
local playerList = require(RobloxGui.Modules.PlayerlistModule)
local chat = require(RobloxGui.Modules.Chat)
local backpack = require(RobloxGui.Modules.BackpackScript)

if isSmallTouchScreen or isTenFootInterface then
	SETTINGS_SHIELD_ACTIVE_POSITION = UDim2.new(0,0,0,0)
	SETTINGS_SHIELD_SIZE = UDim2.new(1,0,1,0)
end

local function CreateSettingsHub()
	local this = {}
	this.Visible = false
	this.Active = false
	this.Pages = {CurrentPage = nil, PageTable = {}}
	this.MenuStack = {}
	this.TabHeaders = {}
	this.BottomBarButtons = {}
	this.TabConnection = nil
	this.LeaveGamePage = require(RobloxGui.Modules.Settings.Pages.LeaveGame)
	this.ResetCharacterPage = require(RobloxGui.Modules.Settings.Pages.ResetCharacter)
	this.SettingsShowSignal = utility:CreateSignal()
	this.OpenStateChangedCount = 0

	local pageChangeCon = nil

	local PoppedMenuEvent = Instance.new("BindableEvent")
	PoppedMenuEvent.Name = "PoppedMenu"
	this.PoppedMenu = PoppedMenuEvent.Event

	local function setBottomBarBindings()
		for i = 1, #this.BottomBarButtons do
			local buttonTable = this.BottomBarButtons[i]
			local buttonName = buttonTable[1]
			local hotKeyTable = buttonTable[2]
			ContextActionService:BindCoreAction(buttonName, hotKeyTable[1], false, unpack(hotKeyTable[2]))
		end

		if this.BottomButtonFrame then
			this.BottomButtonFrame.Visible = true
		end
	end

	local function removeBottomBarBindings(delayBeforeRemoving)
		for _, hotKeyTable in pairs(this.BottomBarButtons) do
			ContextActionService:UnbindCoreAction(hotKeyTable[1])
		end

		local myOpenStateChangedCount = this.OpenStateChangedCount
		local remove = function()
			if this.OpenStateChangedCount == myOpenStateChangedCount and this.BottomButtonFrame then
				this.BottomButtonFrame.Visible = false
			end
		end

		if delayBeforeRemoving then
			delay(delayBeforeRemoving, remove)
		else
			remove()
		end
	end

	local function addBottomBarButton(name, text, gamepadImage, keyboardImage, position, clickFunc, hotkeys)
		local buttonName = name .. "Button"
		local textName = name .. "Text"

		local size = UDim2.new(0,260,0,70)
		if isTenFootInterface then
			size = UDim2.new(0,320,0,120)
		end

		this[buttonName], this[textName] = utility:MakeStyledButton(name .. "Button", text, size, clickFunc, nil, this)
		this[buttonName].Position = position
		this[buttonName].Parent = this.BottomButtonFrame
		if isTenFootInterface then
			this[buttonName].ImageTransparency = 1
		end

		this[textName].FontSize = Enum.FontSize.Size24
		local hintLabel = nil

		if not isTouchDevice then
			this[textName].Size = UDim2.new(1,0,1,0)
			if isTenFootInterface then
				this[textName].Position = UDim2.new(0,60,0,-4)
			else
				this[textName].Position = UDim2.new(0,10,0,-4)
			end

			local hintNameText = name .. "HintText"
			local hintName = name .. "Hint"
			local image = ""
			if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) or platform == Enum.Platform.XBoxOne then
				image = gamepadImage
			else
				image = keyboardImage
			end

			hintLabel = utility:Create'ImageLabel'
			{
				Name = hintName,
				Size = UDim2.new(0,60,0,60),
				Position = UDim2.new(0,10,0,5),
				ZIndex = this.Shield.ZIndex + 2,
				BackgroundTransparency = 1,
				Image = image,
				Parent = this[buttonName]
			};
			if isTenFootInterface then
				hintLabel.Size = UDim2.new(0,90,0,90)
				hintLabel.Position = UDim2.new(0,10,0.5,-45)
			elseif UserInputService.MouseEnabled then
				hintLabel.Image = keyboardImage
				hintLabel.Size = UDim2.new(0,48,0,48)
				hintLabel.Position = UDim2.new(0,10,0,8)
			end
		end

		if isTenFootInterface then
			this[textName].FontSize = Enum.FontSize.Size36
		end

		UserInputService.InputBegan:connect(function(inputObject)
			if inputObject.UserInputType == Enum.UserInputType.Gamepad1 or inputObject.UserInputType == Enum.UserInputType.Gamepad2 or
				inputObject.UserInputType == Enum.UserInputType.Gamepad3 or inputObject.UserInputType == Enum.UserInputType.Gamepad4 then
					if hintLabel then
						hintLabel.Image = gamepadImage
						if isTenFootInterface then
							hintLabel.Size = UDim2.new(0,90,0,90)
							hintLabel.Position = UDim2.new(0,10,0.5,-45)
						else
							hintLabel.Size = UDim2.new(0,60,0,60)
							hintLabel.Position = UDim2.new(0,10,0,5)
						end
					end
			elseif inputObject.UserInputType == Enum.UserInputType.Keyboard then
				if hintLabel then
					hintLabel.Image = keyboardImage
					hintLabel.Size = UDim2.new(0,48,0,48)
					hintLabel.Position = UDim2.new(0,10,0,8)
				end
			end
		end)

		local hotKeyFunc = function(contextName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				clickFunc()
			end
		end

		local hotKeyTable = {hotKeyFunc, hotkeys}
		this.BottomBarButtons[#this.BottomBarButtons + 1] = {buttonName, hotKeyTable}
	end

	local function createGui()
		local PageViewSizeReducer = 0
		if isSmallTouchScreen then
			PageViewSizeReducer = 5
		end

		local clippingShield = utility:Create'Frame'
		{
			Name = "SettingsShield",
			Size = SETTINGS_SHIELD_SIZE,
			Position = SETTINGS_SHIELD_ACTIVE_POSITION,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			BackgroundTransparency = 1,
			Visible = true,
			ZIndex = SETTINGS_BASE_ZINDEX,
			Parent = RobloxGui
		};

		this.Shield = utility:Create'Frame'
		{
			Name = "SettingsShield",
			Size = UDim2.new(1,0,1,0),
			Position = SETTINGS_SHIELD_INACTIVE_POSITION,
			BackgroundTransparency = SETTINGS_SHIELD_TRANSPARENCY,
			BackgroundColor3 = SETTINGS_SHIELD_COLOR,
			BorderSizePixel = 0,
			Visible = false,
			Active = true,
			ZIndex = SETTINGS_BASE_ZINDEX,
			Parent = clippingShield
		};

		this.Modal = utility:Create'TextButton' -- Force unlocks the mouse, really need a way to do this via UIS
		{
			Name = 'Modal',
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 1, 0),
			Modal = true,
			Text = '',
			Parent = this.Shield
		}

		this.HubBar = utility:Create'ImageLabel'
		{
			Name = "HubBar",
			ZIndex = this.Shield.ZIndex + 1,
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(78/255, 84/255, 96/255),
			BackgroundTransparency = 1,
			Image = "rbxasset://textures/ui/Settings/MenuBarAssets/MenuBackground.png",
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(4,4,6,6),
			Parent = this.Shield
		};

		local barHeight = 60
		if isSmallTouchScreen then
			barHeight = 40
			this.HubBar.Size = UDim2.new(1,-10,0,40)
			this.HubBar.Position = UDim2.new(0,5,0,6)
		elseif isTenFootInterface then
			barHeight = 100
			this.HubBar.Size = UDim2.new(0,1200,0,100)
			this.HubBar.Position = UDim2.new(0.5,-600,0.1,0)
		else
			this.HubBar.Size = UDim2.new(0,800,0,60)
			this.HubBar.Position = UDim2.new(0.5,-400,0.1,0)
		end

		this.PageViewClipper = utility:Create'Frame'
		{
			Name = 'PageViewClipper',
			BackgroundTransparency = 1,
			Size = UDim2.new(this.HubBar.Size.X.Scale,this.HubBar.Size.X.Offset,
				 				1, -this.HubBar.Size.Y.Offset - this.HubBar.Position.Y.Offset - PageViewSizeReducer),
			Position = UDim2.new(this.HubBar.Position.X.Scale, this.HubBar.Position.X.Offset,
												this.HubBar.Position.Y.Scale, this.HubBar.Position.Y.Offset + this.HubBar.Size.Y.Offset + 1),
			ClipsDescendants = true,
			Parent = this.Shield,

			utility:Create'ImageButton'{
				Name = 'InputCapture',
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Image = ''
			}
		}

		this.PageView = utility:Create'ScrollingFrame'
		{
			Name = "PageView",
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = this.Shield.ZIndex,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Selectable = false,
			Parent = this.PageViewClipper,
		};
		if UserInputService.MouseEnabled then
			this.PageViewClipper.Size = UDim2.new(this.HubBar.Size.X.Scale,this.HubBar.Size.X.Offset,
											0.5, -(this.HubBar.Position.Y.Offset - this.HubBar.Size.Y.Offset))
		end

		if isSmallTouchScreen then
			this.PageView.CanvasSize = this.PageViewClipper.Size
		else
			local bottomOffset = 0
			if isTouchDevice and not UserInputService.MouseEnabled then
				bottomOffset = 80
			end
			this.BottomButtonFrame = utility:Create'Frame'
			{
				Name = "BottomButtonFrame",
				Size = this.HubBar.Size,
				Position = UDim2.new(0.5, -this.HubBar.Size.X.Offset/2, 1-this.HubBar.Position.Y.Scale-this.HubBar.Size.Y.Scale, -this.HubBar.Position.Y.Offset-this.HubBar.Size.Y.Offset),
				ZIndex = this.Shield.ZIndex + 1,
				BackgroundTransparency = 1,
				Parent = this.Shield
			};

			local leaveGameFunc = function()
				this:AddToMenuStack(this.Pages.CurrentPage)
				this.HubBar.Visible = false
				removeBottomBarBindings()
				this:SwitchToPage(this.LeaveGamePage, nil, 1, true)
			end

			local resetCharFunc = function()
				this:AddToMenuStack(this.Pages.CurrentPage)
				this.HubBar.Visible = false
				removeBottomBarBindings()
				this:SwitchToPage(this.ResetCharacterPage, nil, 1, true)
			end

			-- Xbox Only
			local inviteToGameFunc = function()
				local platformService = game:GetService('PlatformService')
				if platformService then
					platformService:PopupGameInviteUI()
				end
			end

			local resumeFunc = function()
				setVisibilityInternal(false)
			end

			local buttonImageAppend = ""

			if isTenFootInterface then
				buttonImageAppend = "@2x"
			end

			if UserInputService:GetPlatform() == Enum.Platform.XBoxOne then
				local function createInviteButton()
					addBottomBarButton("InviteToGame", "Send Game Invites", "rbxasset://textures/ui/Settings/Help/XButtonLight" .. buttonImageAppend .. ".png",
						"", UDim2.new(0.5,isTenFootInterface and -160 or -130,0.5,-25),
						inviteToGameFunc, {Enum.KeyCode.ButtonX})
				end

				if IsPlayMyPlaceEnabled() then
					spawn(function()
						local PlatformService = nil
						pcall(function() PlatformService = game:GetService('PlatformService') end)
						local pmpCreatorId = PlatformService and PlatformService:BeginGetPMPCreatorId()
						if pmpCreatorId == 0 then
							createInviteButton()
						end
					end)
				else
					createInviteButton()
				end
			else
				addBottomBarButton("LeaveGame", "Leave Game", "rbxasset://textures/ui/Settings/Help/XButtonLight" .. buttonImageAppend .. ".png",
					"rbxasset://textures/ui/Settings/Help/LeaveIcon.png", UDim2.new(0.5,isTenFootInterface and -160 or -130,0.5,-25),
					leaveGameFunc, {Enum.KeyCode.L, Enum.KeyCode.ButtonX})
			end

			addBottomBarButton("ResetCharacter", "    Reset Character", "rbxasset://textures/ui/Settings/Help/YButtonLight" .. buttonImageAppend .. ".png",
				"rbxasset://textures/ui/Settings/Help/ResetIcon.png", UDim2.new(0.5,isTenFootInterface and -550 or -400,0.5,-25),
				resetCharFunc, {Enum.KeyCode.R, Enum.KeyCode.ButtonY})
			addBottomBarButton("Resume", "Resume Game", "rbxasset://textures/ui/Settings/Help/BButtonLight" .. buttonImageAppend .. ".png",
				"rbxasset://textures/ui/Settings/Help/EscapeIcon.png", UDim2.new(0.5,isTenFootInterface and 200 or 140,0.5,-25),
				resumeFunc, {Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonStart})
		end


		local function onScreenSizeChanged()
			local largestPageSize = 600
			local fullScreenSize = RobloxGui.AbsoluteSize.y
			local bufferSize = (1-0.95) * fullScreenSize
			if isTenFootInterface then
				largestPageSize = 800
				bufferSize = 0.07 * fullScreenSize
			elseif isSmallTouchScreen then
				bufferSize = (1-0.99) * fullScreenSize
			end
			local barSize = this.HubBar.Size.Y.Offset
			local extraSpace = bufferSize*2+barSize*2


			local usableScreenHeight = fullScreenSize - extraSpace
			local minimumPageSize = 150
			local usePageSize = nil

			if largestPageSize < usableScreenHeight then
				usePageSize = largestPageSize
				this.HubBar.Position = UDim2.new(
					this.HubBar.Position.X.Scale,
					this.HubBar.Position.X.Offset,
					0.5,
					-largestPageSize/2 - this.HubBar.Size.Y.Offset
				)
				if this.BottomButtonFrame then
					this.BottomButtonFrame.Position = UDim2.new(
						this.BottomButtonFrame.Position.X.Scale,
						this.BottomButtonFrame.Position.X.Offset,
						0.5,
						largestPageSize/2
					)
				end
			elseif usableScreenHeight < minimumPageSize then
				usePageSize = minimumPageSize
				this.HubBar.Position = UDim2.new(
					this.HubBar.Position.X.Scale,
					this.HubBar.Position.X.Offset,
					0.5,
					-minimumPageSize/2 - this.HubBar.Size.Y.Offset
				)
				if this.BottomButtonFrame then
					this.BottomButtonFrame.Position = UDim2.new(
						this.BottomButtonFrame.Position.X.Scale,
						this.BottomButtonFrame.Position.X.Offset,
						0.5,
						minimumPageSize/2
					)
				end
			else
				usePageSize = usableScreenHeight
				this.HubBar.Position = UDim2.new(
					this.HubBar.Position.X.Scale,
					this.HubBar.Position.X.Offset,
					0,
					bufferSize
				)
				if this.BottomButtonFrame then
					this.BottomButtonFrame.Position = UDim2.new(
						this.BottomButtonFrame.Position.X.Scale,
						this.BottomButtonFrame.Position.X.Offset,
						1,
						-(bufferSize + barSize)
					)
				end
			end

			if useUserList and not isTenFootInterface then
				if isSmallTouchScreen then
					this.PageViewClipper.Size = UDim2.new(
						this.PageViewClipper.Size.X.Scale,
						this.PageViewClipper.Size.X.Offset,
						0,
						usePageSize + 44
					)
				else
					this.PageViewClipper.Size = UDim2.new(
						this.PageViewClipper.Size.X.Scale,
						this.PageViewClipper.Size.X.Offset,
						0,
						usePageSize
					)
				end
			else
				this.PageViewClipper.Size = UDim2.new(
					this.PageViewClipper.Size.X.Scale,
					this.PageViewClipper.Size.X.Offset,
					0,
					usePageSize
				)
			end
			this.PageViewClipper.Position = UDim2.new(
				this.PageViewClipper.Position.X.Scale,
				this.PageViewClipper.Position.X.Offset,
				0.5,
				-usePageSize/2
			)
		end
		-- TODO: disconnect this event?
		RobloxGui.Changed:connect(function(prop)
			if prop == "AbsoluteSize" then
				onScreenSizeChanged()
			end
		end)
		onScreenSizeChanged()
	end

	local function toggleDevConsole(actionName, inputState, inputObject)
		if actionName == DEV_CONSOLE_ACTION_NAME then 	-- ContextActionService->F9
			if inputState and inputState == Enum.UserInputState.Begin and ToggleDevConsoleBindableFunc then
				ToggleDevConsoleBindableFunc:Invoke()
			end
		end
	end

	local lastInputUsedToSelectGui = isTenFootInterface
	UserInputService.InputBegan:connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 or input.UserInputType == Enum.UserInputType.Gamepad2 or input.UserInputType == Enum.UserInputType.Gamepad3 or input.UserInputType == Enum.UserInputType.Gamepad4
			or input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.Tab then
			lastInputUsedToSelectGui = true
		elseif input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			lastInputUsedToSelectGui = false
		end
	end)
	UserInputService.InputChanged:connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2 then
			if input.Position.magnitude >= 0.25 then
				lastInputUsedToSelectGui = true
			end
		elseif input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
			lastInputUsedToSelectGui = false
		end
	end)


	local switchTab = function(direction, cycle)
		local currentTabPosition = GetHeaderPosition(this.Pages.CurrentPage)
		if currentTabPosition < 0 then return end

		local newTabPosition = currentTabPosition + direction
		if cycle then
			if newTabPosition > #this.TabHeaders then
				newTabPosition = 1
			elseif newTabPosition < 1 then
				newTabPosition = #this.TabHeaders
			end
		end
		local newHeader = this.TabHeaders[newTabPosition]

		if newHeader then
			for pager,v in pairs(this.Pages.PageTable) do
				if pager:GetTabHeader() == newHeader then
					this:SwitchToPage(pager, true, direction)
					break
				end
			end
		end
	end

	local switchTabFromBumpers = function(actionName, inputState, inputObject)
		if inputState ~= Enum.UserInputState.Begin then return end

		local direction = 0
		if inputObject.KeyCode == Enum.KeyCode.ButtonR1 then
			direction = 1
		elseif inputObject.KeyCode == Enum.KeyCode.ButtonL1 then
			direction = -1
		end

		switchTab(direction, true, true)
	end

	local switchTabFromKeyboard = function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			local direction = 0
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				direction = -1
			else
				direction = 1
			end

			switchTab(direction, true, true)
		end
	end

	local scrollHotkeyFunc = function(actionName, inputState, inputObject)
		if inputState ~= Enum.UserInputState.Begin then return end

		local direction = 0
		if inputObject.KeyCode == Enum.KeyCode.PageUp then
			direction = -100
		elseif inputObject.KeyCode == Enum.KeyCode.PageDown then
			direction = 100
		end

		this:ScrollPixels(direction)
	end

	-- need some stuff for functions below so init here
	createGui()

	function GetHeaderPosition(page)
		local header = page:GetTabHeader()
		if not header then return -1 end

		for i,v in pairs(this.TabHeaders) do
			if v == header then
				return i
			end
		end

		return -1
	end

	local setZIndex = nil
	setZIndex = function(newZIndex, object)
		if object:IsA("GuiObject") then
			object.ZIndex = newZIndex
			local children = object:GetChildren()
			for i = 1, #children do
				setZIndex(newZIndex, children[i])
			end
		end
	end

	local function AddHeader(newHeader, headerPage)
		if not newHeader then return end

		this.TabHeaders[#this.TabHeaders + 1] = newHeader
		headerPage.TabPosition = #this.TabHeaders

		local sizeOfTab = 1/#this.TabHeaders
		for i = 1, #this.TabHeaders do
			local tabMaxPos = (sizeOfTab * i)
			local tabMinPos = (sizeOfTab * (i - 1))
			local pos = ((tabMaxPos - tabMinPos)/2) + tabMinPos

			local tab = this.TabHeaders[i]
			tab.Position = UDim2.new(pos,-tab.Size.X.Offset/2,0,0)
		end

		setZIndex(SETTINGS_BASE_ZINDEX + 1, newHeader)
		newHeader.Parent = this.HubBar
	end

	local function RemoveHeader(oldHeader)
		local removedPos = nil

		for i = 1, #this.TabHeaders do
			if this.TabHeaders[i] == oldHeader then
				removedPos = i
				table.remove(this.TabHeaders, i)
				break
			end
		end

		if removedPos then
			for i = removedPos, #this.TabHeaders do
				local currentTab = this.TabHeaders[i]
				currentTab.Position = UDim2.new(currentTab.Position.X.Scale, currentTab.Position.X.Offset - oldHeader.AbsoluteSize.X,
				 								currentTab.Position.Y.Scale, currentTab.Position.Y.Offset)
			end
		end

		oldHeader.Parent = nil
	end

	-- Page APIs
	function this:AddPage(pageToAdd)
		this.Pages.PageTable[pageToAdd] = true
		AddHeader(pageToAdd:GetTabHeader(), pageToAdd)
		pageToAdd.Page.Position = UDim2.new(pageToAdd.TabPosition - 1,0,0,0)
	end

	function this:RemovePage(pageToRemove)
		this.Pages.PageTable[pageToRemove] = nil
		RemoveHeader(pageToRemove:GetTabHeader())
	end

	function this:HideBar()
		this.HubBar.Visible = false
		this.PageViewClipper.Visible = false
		if this.BottomButtonFrame then
			removeBottomBarBindings()
		end
	end

	function this:ShowBar()
		this.HubBar.Visible = true
		this.PageViewClipper.Visible = true
		if this.BottomButtonFrame then
			setBottomBarBindings()
		end
	end

	function this:ScrollPixels(pixels)
		-- Only Y
		local oldY = this.PageView.CanvasPosition.Y
		local maxY = this.PageView.CanvasSize.Y.Offset - this.PageViewClipper.AbsoluteSize.y
		local newY = math.max(0, math.min(oldY+pixels, maxY)) -- i.e. clamp
		this.PageView.CanvasPosition = Vector2.new(0, newY)
	end

	function this:ScrollToFrame(frame, forced)
		if lastInputUsedToSelectGui or forced then
			local ay = frame.AbsolutePosition.y - this.Pages.CurrentPage.Page.AbsolutePosition.y
			local by = ay + frame.AbsoluteSize.y

			if ay < this.PageView.CanvasPosition.y then -- Scroll up to fit top
				this.PageView.CanvasPosition = Vector2.new(0, ay)
			elseif by - this.PageView.CanvasPosition.y > this.PageViewClipper.Size.Y.Offset then -- Scroll down to fit bottom
				this.PageView.CanvasPosition = Vector2.new(0, by - this.PageViewClipper.Size.Y.Offset)
			end
		end
	end

	function this:SwitchToPage(pageToSwitchTo, ignoreStack, direction, skipAnimation)
		if this.Pages.PageTable[pageToSwitchTo] == nil then return end

		-- detect direction
		if direction == nil then
			if this.Pages.CurrentPage and this.Pages.CurrentPage.TabHeader and pageToSwitchTo and pageToSwitchTo.TabHeader then
				direction = this.Pages.CurrentPage.TabHeader.AbsolutePosition.x < pageToSwitchTo.TabHeader.AbsolutePosition.x and 1 or -1
			end
		end
		if direction == nil then
			direction = 1
		end

		-- if we have a page we need to let it know to go away
		if this.Pages.CurrentPage then
			pageChangeCon:disconnect()
			this.Pages.CurrentPage.Active = false
		end

		-- make sure all pages are in right position
		local newPagePos = pageToSwitchTo.TabPosition
		for page, _ in pairs(this.Pages.PageTable) do
			if page ~= pageToSwitchTo then
				page:Hide(-direction, newPagePos, skipAnimation)
			end
		end

		if this.BottomButtonFrame then
			this.BottomButtonFrame.Visible = (pageToSwitchTo ~= this.ResetCharacterPage and pageToSwitchTo ~= this.LeaveGamePage)
			this.HubBar.Visible = this.BottomButtonFrame.Visible
		end

		-- make sure page is visible
		this.Pages.CurrentPage = pageToSwitchTo
		this.Pages.CurrentPage:Display(this.PageView, skipAnimation)
		this.Pages.CurrentPage.Active = true

		local pageSize = this.Pages.CurrentPage:GetSize()
		this.PageView.CanvasSize = UDim2.new(0,pageSize.X,0,pageSize.Y)

		pageChangeCon = this.Pages.CurrentPage.Page.Changed:connect(function(prop)
			if prop == "AbsoluteSize" then
				local pageSize = this.Pages.CurrentPage:GetSize()
				this.PageView.CanvasSize = UDim2.new(0,pageSize.X,0,pageSize.Y)
			end
		end)

		if this.MenuStack[#this.MenuStack] ~= this.Pages.CurrentPage and not ignoreStack then
			this.MenuStack[#this.MenuStack + 1] = this.Pages.CurrentPage
		end
	end

	function this:SetActive(active)
		this.Active = active

		if this.Pages.CurrentPage then
			this.Pages.CurrentPage.Active = active
		end
	end

	function clearMenuStack()
		while this.MenuStack and #this.MenuStack > 0 do
			this:PopMenu()
		end
	end

	function setOverrideMouseIconBehavior()
		pcall(function()
			if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
				UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceHide
			else
				UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
			end
		end)
	end

	function setVisibilityInternal(visible, noAnimation, customStartPage)
		this.OpenStateChangedCount = this.OpenStateChangedCount + 1
		local switchedFromGamepadInput = switchedFromGamepadInput or isTenFootInterface
		this.Visible = visible


		this.Modal.Visible = this.Visible

		if this.TabConnection then
			this.TabConnection:disconnect()
			this.TabConnection = nil
		end

		if this.Visible then
			this.SettingsShowSignal:fire(this.Visible)

			pcall(function() GuiService:SetMenuIsOpen(true) end)
			this.Shield.Visible = this.Visible
			if noAnimation then
				this.Shield.Position = SETTINGS_SHIELD_ACTIVE_POSITION
			else
				this.Shield:TweenPosition(SETTINGS_SHIELD_ACTIVE_POSITION, Enum.EasingDirection.InOut, Enum.EasingStyle.Quart, 0.5, true)
			end

			local noOpFunc = function() end
			ContextActionService:BindCoreAction("RbxSettingsHubStopCharacter", noOpFunc, false,
												 Enum.PlayerActions.CharacterForward,
												 Enum.PlayerActions.CharacterBackward,
												 Enum.PlayerActions.CharacterLeft,
												 Enum.PlayerActions.CharacterRight,
												 Enum.PlayerActions.CharacterJump,
												 Enum.KeyCode.LeftShift,
												 Enum.KeyCode.RightShift,
												 Enum.KeyCode.Tab,
												 Enum.UserInputType.Gamepad1, Enum.UserInputType.Gamepad2, Enum.UserInputType.Gamepad3, Enum.UserInputType.Gamepad4)

			ContextActionService:BindCoreAction("RbxSettingsHubSwitchTab", switchTabFromBumpers, false, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL1)
			ContextActionService:BindCoreAction("RbxSettingsScrollHotkey", scrollHotkeyFunc, false, Enum.KeyCode.PageUp, Enum.KeyCode.PageDown)
			setBottomBarBindings()

			this.TabConnection = UserInputService.InputBegan:connect(switchTabFromKeyboard)


			setOverrideMouseIconBehavior()
			pcall(function() lastInputChangedCon = UserInputService.LastInputTypeChanged:connect(setOverrideMouseIconBehavior) end)
			if UserInputService.MouseEnabled then
				pcall(function()
					UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
				end)
			end

			if customStartPage then
				removeBottomBarBindings()
				this:SwitchToPage(customStartPage, nil, 1, true)
			else
				if useUserList and not isTenFootInterface then
					this:SwitchToPage(this.PlayersPage, nil, 1, true)
				else
					if this.HomePage then
						this:SwitchToPage(this.HomePage, nil, 1, true)
					else
						this:SwitchToPage(this.GameSettingsPage, nil, 1, true)
					end
				end
			end

			playerList:HideTemp('SettingsMenu', true)

			if chat:GetVisibility() then
				chatWasVisible = true
				chat:ToggleVisibility()
			end

			if backpack.IsOpen then
				backpack:OpenClose()
			end
		else
			if noAnimation then
				this.Shield.Position = SETTINGS_SHIELD_INACTIVE_POSITION
				this.Shield.Visible = this.Visible
				this.SettingsShowSignal:fire(this.Visible)
				pcall(function() GuiService:SetMenuIsOpen(false) end)
			else
				this.Shield:TweenPosition(SETTINGS_SHIELD_INACTIVE_POSITION, Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.4, true, function()
					this.Shield.Visible = this.Visible
					this.SettingsShowSignal:fire(this.Visible)
					if not this.Visible then pcall(function() GuiService:SetMenuIsOpen(false) end) end
				end)
			end

			if lastInputChangedCon then
				lastInputChangedCon:disconnect()
			end

			playerList:HideTemp('SettingsMenu', false)

			if chatWasVisible then
				chat:ToggleVisibility()
				chatWasVisible = false
			end

			pcall(function() UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None end)

			clearMenuStack()
			ContextActionService:UnbindCoreAction("RbxSettingsHubSwitchTab")
			ContextActionService:UnbindCoreAction("RbxSettingsHubStopCharacter")
			ContextActionService:UnbindCoreAction("RbxSettingsScrollHotkey")
			removeBottomBarBindings(0.4)

			GuiService.SelectedCoreObject = nil
		end
	end

	function this:SetVisibility(visible, noAnimation, customStartPage, switchedFromGamepadInput)
		if this.Visible == visible then return end

		setVisibilityInternal(visible, noAnimation, customStartPage, switchedFromGamepadInput)
	end

	function this:ToggleVisibility(switchedFromGamepadInput)
		setVisibilityInternal(not this.Visible, nil, nil, switchedFromGamepadInput)
	end

	function this:AddToMenuStack(newItem)
		if this.MenuStack[#this.MenuStack] ~= newItem then
			this.MenuStack[#this.MenuStack + 1] = newItem
		end
	end


	function this:PopMenu(switchedFromGamepadInput, skipAnimation)
		if this.MenuStack and #this.MenuStack > 0 then
			local lastStackItem = this.MenuStack[#this.MenuStack]

			if type(lastStackItem) ~= "table" then
				PoppedMenuEvent:Fire(lastStackItem)
			end

			if lastStackItem == this.LeaveGamePage or lastStackItem == this.ResetCharacterPage then
				setBottomBarBindings()
			end

			table.remove(this.MenuStack, #this.MenuStack)
			this:SwitchToPage(this.MenuStack[#this.MenuStack], true, 1, skipAnimation)
			if #this.MenuStack == 0 then
				this:SetVisibility(false)
				this.Pages.CurrentPage:Hide(0, 0)
			end
		else
			this.MenuStack = {}
			PoppedMenuEvent:Fire()
			this:ToggleVisibility()
		end
	end

	function this:ShowShield()
		this.Shield.BackgroundTransparency = SETTINGS_SHIELD_TRANSPARENCY
	end
	function this:HideShield()
		this.Shield.BackgroundTransparency = 1
	end

	local closeMenuFunc = function(name, inputState, input)
		if inputState ~= Enum.UserInputState.Begin then return end
		this:PopMenu(false, true)
	end
	ContextActionService:BindCoreAction("RBXEscapeMainMenu", closeMenuFunc, false, Enum.KeyCode.Escape)

	this.ResetCharacterPage:SetHub(this)
	this.LeaveGamePage:SetHub(this)

	-- full page initialization
	if not useUserList then
		if utility:IsSmallTouchScreen() then
			this.HomePage = require(RobloxGui.Modules.Settings.Pages.Home)
			this.HomePage:SetHub(this)
		end
	end

	this.GameSettingsPage = require(RobloxGui.Modules.Settings.Pages.GameSettings)
	this.GameSettingsPage:SetHub(this)

	if platform ~= Enum.Platform.XBoxOne and platform ~= Enum.Platform.PS4 then
		this.ReportAbusePage = require(RobloxGui.Modules.Settings.Pages.ReportAbuseMenu)
		this.ReportAbusePage:SetHub(this)
	end

	this.HelpPage = require(RobloxGui.Modules.Settings.Pages.Help)
	this.HelpPage:SetHub(this)

	if platform == Enum.Platform.Windows then
		this.RecordPage = require(RobloxGui.Modules.Settings.Pages.Record)
		this.RecordPage:SetHub(this)
	end

	if useUserList and not isTenFootInterface then
		this.PlayersPage = require(RobloxGui.Modules.Settings.Pages.Players)
		this.PlayersPage:SetHub(this)
	end

	-- page registration
	if useUserList and not isTenFootInterface then
		this:AddPage(this.PlayersPage)
	end
	this:AddPage(this.ResetCharacterPage)
	this:AddPage(this.LeaveGamePage)
	if not useUserList then
		if this.HomePage then
			this:AddPage(this.HomePage)
		end
	end
	this:AddPage(this.GameSettingsPage)
	if this.ReportAbusePage then
		this:AddPage(this.ReportAbusePage)
	end
	this:AddPage(this.HelpPage)
	if this.RecordPage then
		this:AddPage(this.RecordPage)
	end

	if useUserList and not isTenFootInterface then
		this:SwitchToPage(this.PlayerPage, true, 1)
	else
		if this.HomePage then
			this:SwitchToPage(this.HomePage, true, 1)
		else
			this:SwitchToPage(this.GameSettingsPage, true, 1)
		end
	end
	-- hook up to necessary signals

	-- connect back button on android
	GuiService.ShowLeaveConfirmation:connect(function()
		if #this.MenuStack == 0 then
			this:SwitchToPage(this.LeaveGamePage, nil, 1)
			this:SetVisibility(true)
		else
			this:SetVisibility(false)
			this:PopMenu()
		end
	end)

	-- Dev Console Connections
	ContextActionService:BindCoreAction(DEV_CONSOLE_ACTION_NAME, toggleDevConsole, false, Enum.KeyCode.F9)

	-- Keyboard control
	UserInputService.InputBegan:connect(function(input)
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
			if this.Visible and this.Active then
				if this.Pages.CurrentPage then
					if GuiService.SelectedCoreObject == nil then
						this.Pages.CurrentPage:SelectARow()
					end
				end
			end
		end
	end)

	return this
end


-- Main Entry Point

local moduleApiTable = {}

	local SettingsHubInstance = CreateSettingsHub()

	function moduleApiTable:SetVisibility(visible, noAnimation, customStartPage, switchedFromGamepadInput)
		SettingsHubInstance:SetVisibility(visible, noAnimation, customStartPage, switchedFromGamepadInput)
	end

	function moduleApiTable:ToggleVisibility(switchedFromGamepadInput)
		SettingsHubInstance:ToggleVisibility(switchedFromGamepadInput)
	end

	function moduleApiTable:SwitchToPage(pageToSwitchTo, ignoreStack)
		SettingsHubInstance:SwitchToPage(pageToSwitchTo, ignoreStack, 1)
	end

	function moduleApiTable:ReportPlayer(player)
		if SettingsHubInstance.ReportAbusePage and player then
			local setReportPlayerConnection = nil
			setReportPlayerConnection = SettingsHubInstance.ReportAbusePage.Displayed.Event:connect(function()
				-- When we change the SelectionIndex of GameOrPlayerMode it waits until the tween is done
				-- before it fires the IndexChanged signal. The WhichPlayerMode dropdown listens to this signal
				-- and resets when it is fired. Therefore we need to listen to this signal and set the player we want
				-- to report the frame after the dropdown is reset
				local indexChangedConnection = nil
				indexChangedConnection = SettingsHubInstance.ReportAbusePage.GameOrPlayerMode.IndexChanged:connect(function()
					if indexChangedConnection then
						indexChangedConnection:disconnect()
						indexChangedConnection = nil
					end
					wait() -- We need to wait a frame to set the value of WhichPlayerMode as it is being updated by another script listening to the IndexChanged signal
					SettingsHubInstance.ReportAbusePage.WhichPlayerMode:SetSelectionByValue(player.Name)
				end)
				SettingsHubInstance.ReportAbusePage.GameOrPlayerMode:SetSelectionIndex(2)

				if setReportPlayerConnection then
					setReportPlayerConnection:disconnect()
					setReportPlayerConnection = nil
				end
			end)
			SettingsHubInstance:SetVisibility(true, false, SettingsHubInstance.ReportAbusePage)
		end
	end

	function moduleApiTable:GetVisibility()
		return SettingsHubInstance.Visible
	end

	function moduleApiTable:ShowShield()
		SettingsHubInstance:ShowShield()
	end

	function moduleApiTable:HideShield()
		SettingsHubInstance:HideShield()
	end

	moduleApiTable.SettingsShowSignal = SettingsHubInstance.SettingsShowSignal

	moduleApiTable.Instance = SettingsHubInstance

return moduleApiTable