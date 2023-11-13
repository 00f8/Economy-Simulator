--[[
		Filename: NotificationScript2.lua
		Version 1.1
		Written by: jmargh
		Description: Handles notification gui for the following in game ROBLOX events
			Badge Awarded
			Player Points Awarded
			Friend Request Recieved/New Friend
			Graphics Quality Changed
			Teleports
			CreatePlaceInPlayerInventoryAsync
--]]

--[[ Services ]]--
local BadgeService = game:GetService('BadgeService')
local GuiService = game:GetService('GuiService')
local Players = game:GetService('Players')
local PointsService = game:GetService('PointsService')
local MarketplaceService = game:GetService('MarketplaceService')
local TeleportService = game:GetService('TeleportService')
local HttpService = game:GetService("HttpService")
local ContextActionService = game:GetService("ContextActionService")
local CoreGui = game:GetService("CoreGui")
local RobloxGui = CoreGui:WaitForChild("RobloxGui")
local Settings = UserSettings()
local GameSettings = Settings.GameSettings

--[[ Fast Flags ]]--
local getNotificationDisableSuccess, notificationsDisableActiveValue = pcall(function() return settings():GetFFlag("SetCoreDisableNotifications") end)
local allowDisableNotifications = getNotificationDisableSuccess and notificationsDisableActiveValue

local getSendNotificationSuccess, sendNotificationActiveValue = pcall(function() return settings():GetFFlag("SetCoreSendNotifications") end)
local allowSendNotifications = getSendNotificationSuccess and sendNotificationActiveValue

--[[ Script Variables ]]--
local LocalPlayer = nil
while not Players.LocalPlayer do
	wait()
end
LocalPlayer = Players.LocalPlayer
local RbxGui = script.Parent
local NotificationQueue = {}
local OverflowQueue = {}
local FriendRequestBlacklist = {}
local CurrentGraphicsQualityLevel = GameSettings.SavedQualityLevel.Value
local BindableEvent_SendNotification = Instance.new('BindableFunction')
BindableEvent_SendNotification.Name = "SendNotification"
BindableEvent_SendNotification.Parent = RbxGui
local isPaused = false
RobloxGui:WaitForChild("Modules"):WaitForChild("TenFootInterface")
local isTenFootInterface = require(RobloxGui.Modules.TenFootInterface):IsEnabled()

local pointsNotificationsActive = true
local badgesNotificationsActive = true

--[[ Constants ]]--
local BG_TRANSPARENCY = 0.7
local MAX_NOTIFICATIONS = 3
local NOTIFICATION_Y_OFFSET = 64
local IMAGE_SIZE = 48
local EASE_DIR = Enum.EasingDirection.InOut
local EASE_STYLE = Enum.EasingStyle.Sine
local TWEEN_TIME = 0.35
local DEFAULT_NOTIFICATION_DURATION = 5

--[[ Images ]]--
local PLAYER_POINTS_IMG = 'http://www.roblox.com/asset?id=206410433'
local BADGE_IMG = 'http://www.roblox.com/asset?id=206410289'
local FRIEND_IMAGE = 'http://www.roblox.com/thumbs/avatar.ashx?userId='

--[[ Gui Creation ]]--
local function createFrame(name, size, position, bgt)
	local frame = Instance.new('Frame')
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundTransparency = bgt

	return frame
end

local function createTextButton(name, text, position)
	local button = Instance.new('TextButton')
	button.Name = name
	button.Size = UDim2.new(0.5, -2, 0.5, 0)
	button.Position = position
	button.BackgroundTransparency = BG_TRANSPARENCY
	button.BackgroundColor3 = Color3.new(0, 0, 0)
	button.Font = Enum.Font.SourceSansBold
	button.FontSize = Enum.FontSize.Size18
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text

	return button
end

local NotificationFrame = createFrame("NotificationFrame", UDim2.new(0, 200, 0.42, 0), UDim2.new(1, -204, 0.50, 0), 1)
NotificationFrame.Parent = RbxGui

local DefaultNotifcation = createFrame("Notifcation", UDim2.new(1, 0, 0, NOTIFICATION_Y_OFFSET), UDim2.new(0, 0, 0, 0), BG_TRANSPARENCY)
DefaultNotifcation.BackgroundColor3 = Color3.new(0, 0, 0)
DefaultNotifcation.BorderSizePixel = 0

local NotificationTitle = Instance.new('TextLabel')
NotificationTitle.Name = "NotificationTitle"
NotificationTitle.Size = UDim2.new(0, 0, 0, 0)
NotificationTitle.Position = UDim2.new(0.5, 0, 0.5, -12)
NotificationTitle.BackgroundTransparency = 1
NotificationTitle.Font = Enum.Font.SourceSansBold
NotificationTitle.FontSize = Enum.FontSize.Size18
NotificationTitle.TextColor3 = Color3.new(0.97, 0.97, 0.97)

local NotificationText = Instance.new('TextLabel')
NotificationText.Name = "NotificationText"
NotificationText.Size = UDim2.new(1, -20, 0, 28)
NotificationText.Position = UDim2.new(0, 10, 0.5, 1)
NotificationText.BackgroundTransparency = 1
NotificationText.Font = Enum.Font.SourceSans
NotificationText.FontSize = Enum.FontSize.Size14
NotificationText.TextColor3 = Color3.new(0.92, 0.92, 0.92)
NotificationText.TextWrap = true
NotificationText.TextYAlignment = Enum.TextYAlignment.Top

local NotificationImage = Instance.new('ImageLabel')
NotificationImage.Name = "NotificationImage"
NotificationImage.Size = UDim2.new(0, IMAGE_SIZE, 0, IMAGE_SIZE)
NotificationImage.Position = UDim2.new(0, 8, 0.5, -24)
NotificationImage.BackgroundTransparency = 1
NotificationImage.Image = ""

-- Would really like to get rid of this but some events still require this
local PopupFrame = createFrame("PopupFrame", UDim2.new(0, 360, 0, 160), UDim2.new(0.5, -180, 0.5, -50), 0)
PopupFrame.Style = Enum.FrameStyle.DropShadow
PopupFrame.ZIndex = 4
PopupFrame.Visible = false
PopupFrame.Parent = RbxGui

local PopupAcceptButton = Instance.new('TextButton')
PopupAcceptButton.Name = "PopupAcceptButton"
PopupAcceptButton.Size = UDim2.new(0, 100, 0, 50)
PopupAcceptButton.Position = UDim2.new(0.5, -102, 1, -58)
PopupAcceptButton.Style = Enum.ButtonStyle.RobloxRoundButton
PopupAcceptButton.Font = Enum.Font.SourceSansBold
PopupAcceptButton.FontSize = Enum.FontSize.Size24
PopupAcceptButton.TextColor3 = Color3.new(1, 1, 1)
PopupAcceptButton.Text = "Accept"
PopupAcceptButton.ZIndex = 5
PopupAcceptButton.Parent = PopupFrame

local PopupDeclineButton = PopupAcceptButton:Clone()
PopupDeclineButton.Name = "PopupDeclineButton"
PopupDeclineButton.Position = UDim2.new(0.5, 2, 1, -58)
PopupDeclineButton.Text = "Decline"
PopupDeclineButton.Parent = PopupFrame

local PopupOKButton = PopupAcceptButton:Clone()
PopupOKButton.Name = "PopupOKButton"
PopupOKButton.Position = UDim2.new(0.5, -50, 1, -58)
PopupOKButton.Text = "OK"
PopupOKButton.Visible = false
PopupOKButton.Parent = PopupFrame

local PopupText = Instance.new('TextLabel')
PopupText.Name = "PopupText"
PopupText.Size = UDim2.new(1, -16, 0.8, 0)
PopupText.Position = UDim2.new(0, 8, 0, 8)
PopupText.BackgroundTransparency = 1
PopupText.Font = Enum.Font.SourceSansBold
PopupText.FontSize = Enum.FontSize.Size36
PopupText.TextColor3 = Color3.new(0.97, 0.97, 0.97)
PopupText.TextWrap = true
PopupText.ZIndex = 5
PopupText.TextYAlignment = Enum.TextYAlignment.Top
PopupText.Text = "This is a popup"
PopupText.Parent = PopupFrame

--[[ Helper Functions ]]--
local insertNotifcation = nil
local removeNotification = nil
--
local function createNotification(title, text, image)
	local notificationFrame = DefaultNotifcation:Clone()
	notificationFrame.Position = UDim2.new(1, 4, 1, -NOTIFICATION_Y_OFFSET - 4)
	--
	local notificationTitle = NotificationTitle:Clone()
	notificationTitle.Text = title
	notificationTitle.Parent = notificationFrame

	local notificationText = NotificationText:Clone()
	notificationText.Text = text
	notificationText.Parent = notificationFrame

	if image and image ~= "" then
		local notificationImage = NotificationImage:Clone()
		notificationImage.Image = image
		notificationImage.Parent = notificationFrame
		--
		notificationTitle.Position = UDim2.new(0, NotificationImage.Size.X.Offset + 16, 0.5, -12)
		notificationTitle.TextXAlignment = Enum.TextXAlignment.Left
		--
		notificationText.Size = UDim2.new(1, -IMAGE_SIZE - 16, 0, 28)
		notificationText.Position = UDim2.new(0, IMAGE_SIZE + 16, 0.5, 1)
		notificationText.TextXAlignment = Enum.TextXAlignment.Left
	end

	GuiService:AddSelectionParent(HttpService:GenerateGUID(false), notificationFrame)

	return notificationFrame
end

local function findNotification(notification)
	local index = nil
	for i = 1, #NotificationQueue do
		if NotificationQueue[i] == notification then
			return i
		end
	end
end

local function updateNotifications()
	local pos = 1
	local yOffset = 0
	for i = #NotificationQueue, 1, -1 do
		local currentNotification = NotificationQueue[i]
		if currentNotification then
			local frame = currentNotification.Frame
			if frame and frame.Parent then
				local thisOffset = currentNotification.IsFriend and (NOTIFICATION_Y_OFFSET + 2) * 1.5 or NOTIFICATION_Y_OFFSET
				yOffset = yOffset + thisOffset
				frame:TweenPosition(UDim2.new(0, 0, 1, -yOffset - (pos * 4)), EASE_DIR, EASE_STYLE, TWEEN_TIME, true)
				pos = pos + 1
			end
		end
	end
end

local lastTimeInserted = 0
insertNotifcation = function(notification)
	spawn(function() 
		while isPaused do wait() end
		notification.IsActive = true
		local size = #NotificationQueue
		if size == MAX_NOTIFICATIONS then
			OverflowQueue[#OverflowQueue + 1] = notification
			return
		end
		--
		NotificationQueue[size + 1] = notification
		notification.Frame.Parent = NotificationFrame
		delay(notification.Duration, function()
			removeNotification(notification)
		end)
		while tick() - lastTimeInserted < TWEEN_TIME do
			wait()
		end
		lastTimeInserted = tick()
		--
		updateNotifications()
	end)
end

removeNotification = function(notification)
	if not notification then return end
	--
	local index = findNotification(notification)
	table.remove(NotificationQueue, index)
	local frame = notification.Frame
	if frame and frame.Parent then
		notification.IsActive = false
		spawn(function() 
			while isPaused do wait() end

			frame:TweenPosition(UDim2.new(1, 0, 1, frame.Position.Y.Offset), EASE_DIR, EASE_STYLE, TWEEN_TIME, true,
				function()
					frame:Destroy()
					notification = nil
				end)
		end)
	end
	if #OverflowQueue > 0 then
		local nextNofication = OverflowQueue[1]
		table.remove(OverflowQueue, 1)
		insertNotifcation(nextNofication)
	else
		updateNotifications()
	end
end

local function sendNotifcation(title, text, image, duration, callback, button1Text, button2Text)
	local notification = {}
	local notificationFrame = createNotification(title, text, image)
	--
	
	local button1 = nil
	if button1Text and button1Text ~= "" then
		notification.IsFriend = true -- Prevents other notifications overlapping the buttons
		button1 = createTextButton("Button1", button1Text, UDim2.new(0, 0, 1, 2))
		button1.Parent = notificationFrame
		local button1ClickedConnection = nil
		button1ClickedConnection = button1.MouseButton1Click:connect(function()
			if button1ClickedConnection then
				button1ClickedConnection:disconnect()
				button1ClickedConnection = nil
				removeNotification(notification)
				if callback and type(callback) ~= "function" then -- callback should be a bindable
					pcall(function() callback:Invoke(button1Text) end)
				elseif type(callback) == "function" then
					callback(button1Text)
				end
			end
		end)
	end
	
	if button2Text and button2Text ~= "" then
		notification.IsFriend = true 
		local button2 = createTextButton("Button1", button2Text, UDim2.new(0.5, 2, 1, 2))
		button2.Parent = notificationFrame
		local button2ClickedConnection = nil
		button2ClickedConnection = button2.MouseButton1Click:connect(function()
			if button2ClickedConnection then
				button2ClickedConnection:disconnect()
				button2ClickedConnection = nil
				removeNotification(notification)
				if callback and type(callback) ~= "function" then -- callback should be a bindable
					pcall(function() callback:Invoke(button2Text) end)
				elseif type(callback) == "function" then
					callback(button2Text)
				end
			end
		end)
	else
		-- Resize button1 to take up all the space under the notification if button2 doesn't exist
		if button1 then
			button1.Size = UDim2.new(1, -2, .5, 0)
		end
	end
	
	notification.Frame = notificationFrame
	notification.Duration = duration
	insertNotifcation(notification)
end
BindableEvent_SendNotification.OnInvoke = function(title, text, image, duration, callback)
	sendNotifcation(title, text, image, duration, callback)
end

-- New follower notification
spawn(function()
	local RobloxReplicatedStorage = game:GetService('RobloxReplicatedStorage')
	local RemoteEvent_NewFollower = RobloxReplicatedStorage:WaitForChild('NewFollower')
	--
	RemoteEvent_NewFollower.OnClientEvent:connect(function(followerRbxPlayer)
		sendNotifcation("New Follower", followerRbxPlayer.Name.." is now following you!",
			FRIEND_IMAGE..followerRbxPlayer.userId.."&x=48&y=48", 5, function() end)
	end)
end)

local function sendFriendNotification(fromPlayer)
	local notification = {}
	local notificationFrame = createNotification(fromPlayer.Name, "Sent you a friend request!",
		FRIEND_IMAGE..tostring(fromPlayer.userId).."&x=48&y=48")
	notificationFrame.Position = UDim2.new(1, 4, 1, -(NOTIFICATION_Y_OFFSET + 2) * 1.5 - 4)
	--
	local acceptButton = createTextButton("AcceptButton", "Accept", UDim2.new(0, 0, 1, 2))
	acceptButton.Parent = notificationFrame

	local declineButton = createTextButton("DeclineButton", "Decline", UDim2.new(0.5, 2, 1, 2))
	declineButton.Parent = notificationFrame

	acceptButton.MouseButton1Click:connect(function()
		if not notification.IsActive then return end
		if notification then
			removeNotification(notification)
		end
		LocalPlayer:RequestFriendship(fromPlayer)
	end)

	declineButton.MouseButton1Click:connect(function()
		if not notification.IsActive then return end
		if notification then
			removeNotification(notification)
		end
		LocalPlayer:RevokeFriendship(fromPlayer)
		FriendRequestBlacklist[fromPlayer] = true
	end)

	notification.Frame = notificationFrame
	notification.Duration = 8
	notification.IsFriend = true
	insertNotifcation(notification)
end

--[[ Friend Notifications ]]--
local function onFriendRequestEvent(fromPlayer, toPlayer, event)
	if fromPlayer ~= LocalPlayer and toPlayer ~= LocalPlayer then return end
	--
	if fromPlayer == LocalPlayer then
		if event == Enum.FriendRequestEvent.Accept then
			sendNotifcation("New Friend", "You are now friends with "..toPlayer.Name.."!",
				FRIEND_IMAGE..tostring(toPlayer.userId).."&x=48&y=48", DEFAULT_NOTIFICATION_DURATION, nil)
		end
	elseif toPlayer == LocalPlayer then
		if event == Enum.FriendRequestEvent.Issue then
			if FriendRequestBlacklist[fromPlayer] then return end
			sendFriendNotification(fromPlayer)
		elseif event == Enum.FriendRequestEvent.Accept then
			sendNotifcation("New Friend", "You are now friends with "..fromPlayer.Name.."!", 
				FRIEND_IMAGE..tostring(fromPlayer.userId).."&x=48&y=48", DEFAULT_NOTIFICATION_DURATION, nil)
		end
	end
end

--[[ Player Points Notifications ]]--
local function onPointsAwarded(userId, pointsAwarded, userBalanceInGame, userTotalBalance)
	if pointsNotificationsActive and userId == LocalPlayer.userId then
		if pointsAwarded == 1 then
			sendNotifcation("Point Awarded", "You received "..tostring(pointsAwarded).." point!", PLAYER_POINTS_IMG, DEFAULT_NOTIFICATION_DURATION, nil)
		elseif pointsAwarded > 0 then
			sendNotifcation("Points Awarded", "You received "..tostring(pointsAwarded).." points!", PLAYER_POINTS_IMG, DEFAULT_NOTIFICATION_DURATION, nil)
		elseif pointsAwarded < 0 then
			sendNotifcation("Points Lost", "You lost "..tostring(-pointsAwarded).." points!", PLAYER_POINTS_IMG, DEFAULT_NOTIFICATION_DURATION, nil)
		end
	end
end

--[[ Badge Notification ]]--
local function onBadgeAwarded(message, userId, badgeId)
	if badgesNotificationsActive and userId == LocalPlayer.userId then
		sendNotifcation("Badge Awarded", message, BADGE_IMG, DEFAULT_NOTIFICATION_DURATION, nil)
	end
end

--[[ Graphics Changes Notification ]]--
function onGameSettingsChanged(property, amount)
	if property == "SavedQualityLevel" then
		local level = GameSettings.SavedQualityLevel.Value + amount
		if level > 10 then
			level = 10
		elseif level < 1 then
			level = 1
		end
		-- value of 0 is automatic, we do not want to send a notification in that case
		if level > 0 and level ~= CurrentGraphicsQualityLevel then
			if level > CurrentGraphicsQualityLevel then
				sendNotifcation("Graphics Quality", "Increased to ("..tostring(level)..")", "", 2, nil)
			else
				sendNotifcation("Graphics Quality", "Decreased to ("..tostring(level)..")", "", 2, nil)
			end
			CurrentGraphicsQualityLevel = level
		end
	end
end

--[[ Connections ]]--
if not isTenFootInterface then
	Players.FriendRequestEvent:connect(onFriendRequestEvent)
	PointsService.PointsAwarded:connect(onPointsAwarded)
	BadgeService.BadgeAwarded:connect(onBadgeAwarded)
	--GameSettings.Changed:connect(onGameSettingsChanged)
	game.GraphicsQualityChangeRequest:connect(function(graphicsIncrease) --graphicsIncrease is a boolean
		onGameSettingsChanged("SavedQualityLevel", graphicsIncrease == true and 1 or -1)
	end)
end

GuiService.SendCoreUiNotification = function(title, text)
	local notification = createNotification(title, text, "")
	notification.BackgroundTransparency = .5
	notification.Size = UDim2.new(.5, 0, .1, 0)
	notification.Position = UDim2.new(.25, 0, -0.1, 0)
	notification.NotificationTitle.FontSize = Enum.FontSize.Size36
	notification.NotificationText.FontSize = Enum.FontSize.Size24
	notification.Parent = RbxGui
	notification:TweenPosition(UDim2.new(.25, 0, 0, 0), EASE_DIR, EASE_STYLE, TWEEN_TIME, true)
	wait(5)
	if notification then
		notification:Destroy()
	end
end

--[[ Market Place Events ]]--
-- This is used for when a player calls CreatePlaceInPlayerInventoryAsync
local function onClientLuaDialogRequested(msg, accept, decline)
	PopupText.Text = msg
	--
	local acceptCn, declineCn = nil, nil
	local function disconnectCns()
		if acceptCn then acceptCn:disconnect() end
		if declineCn then declineCn:disconnect() end
		--
		GuiService:RemoveCenterDialog(PopupFrame)
		PopupFrame.Visible = false
	end

	acceptCn = PopupAcceptButton.MouseButton1Click:connect(function()
		disconnectCns()
		MarketplaceService:SignalServerLuaDialogClosed(true)
	end)
	declineCn = PopupDeclineButton.MouseButton1Click:connect(function()
		disconnectCns()
		MarketplaceService:SignalServerLuaDialogClosed(false)
	end)

	local centerDialogSuccess = pcall(
		function()
			GuiService:AddCenterDialog(PopupFrame, Enum.CenterDialogType.QuitDialog,
				function()
					PopupOKButton.Visible = false
					PopupAcceptButton.Visible = true
					PopupDeclineButton.Visible = true
					PopupAcceptButton.Text = accept
					PopupDeclineButton.Text = decline
					PopupFrame.Visible = true
				end,
				function()
					PopupFrame.Visible = false
				end)
		end)

	if not centerDialogSuccess then
		PopupFrame.Visible = true
		PopupAcceptButton.Text = accept
		PopupDeclineButton.Text = decline
	end

	return true
end
MarketplaceService.ClientLuaDialogRequested:connect(onClientLuaDialogRequested)

--[[ Developer customization API ]]--
local function createDeveloperNotification(notificationTable) 
	if type(notificationTable) == "table" then 
		if type(notificationTable.Title) == "string" and type(notificationTable.Text) == "string" then
			local iconImage = (type(notificationTable.Icon) == "string" and notificationTable.Icon or "")
			local duration = (type(notificationTable.Duration) == "number" and notificationTable.Duration or DEFAULT_NOTIFICATION_DURATION)
			local success, bindable = pcall(function() return (notificationTable.Callback:IsA("BindableFunction") and notificationTable.Callback or nil) end)
			local button1Text = (type(notificationTable.Button1) == "string" and notificationTable.Button1 or "")
			local button2Text = (type(notificationTable.Button2) == "string" and notificationTable.Button2 or "")
			sendNotifcation(notificationTable.Title, notificationTable.Text, iconImage, duration, bindable, button1Text, button2Text)
		end
	end 
end

if allowDisableNotifications then
	game:WaitForChild("StarterGui"):RegisterSetCore("PointsNotificationsActive", function(value) if type(value) == "boolean" then pointsNotificationsActive = value end end)
	game:WaitForChild("StarterGui"):RegisterSetCore("BadgesNotificationsActive", function(value) if type(value) == "boolean" then badgesNotificationsActive = value end end)
else
	game:WaitForChild("StarterGui"):RegisterSetCore("PointsNotificationsActive", function() end)
	game:WaitForChild("StarterGui"):RegisterSetCore("BadgesNotificationsActive", function() end)
end

game:WaitForChild("StarterGui"):RegisterGetCore("PointsNotificationsActive", function() return pointsNotificationsActive end)
game:WaitForChild("StarterGui"):RegisterGetCore("BadgesNotificationsActive", function() return badgesNotificationsActive end)

if allowSendNotifications then
	game:WaitForChild("StarterGui"):RegisterSetCore("SendNotification", createDeveloperNotification)
else
	game:WaitForChild("StarterGui"):RegisterSetCore("SendNotification", function() end)
end

if not isTenFootInterface then
	local gamepadMenu = RobloxGui:WaitForChild("CoreScripts/GamepadMenu")
	local gamepadNotifications = gamepadMenu:FindFirstChild("GamepadNotifications")
	while not gamepadNotifications do
		wait()
		gamepadNotifications = gamepadMenu:FindFirstChild("GamepadNotifications")
	end

	local leaveNotificationFunc = function(name, state, inputObject)
		if state ~= Enum.UserInputState.Begin then return end

		if GuiService.SelectedCoreObject:IsDescendantOf(NotificationFrame) then
			GuiService.SelectedCoreObject = nil
		end

		ContextActionService:UnbindCoreAction("LeaveNotificationSelection")
	end

	gamepadNotifications.Event:connect(function(isSelected)
		if not isSelected then return end

		isPaused = true
		local notifications = NotificationFrame:GetChildren()
		for i = 1, #notifications do
			local noteComponents = notifications[i]:GetChildren()
			for j = 1, #noteComponents do
				if noteComponents[j]:IsA("GuiButton") and noteComponents[j].Visible then
					GuiService.SelectedCoreObject = noteComponents[j]
					break
				end
			end
		end

		if GuiService.SelectedCoreObject then
			ContextActionService:BindCoreAction("LeaveNotificationSelection", leaveNotificationFunc, false, Enum.KeyCode.ButtonB)
		else
			isPaused = false
			local utility = require(RobloxGui.Modules.Settings.Utility)
			local okPressedFunc = function() end
			utility:ShowAlert("You have no notifications", "Ok", settingsHub, okPressedFunc, true)
		end
	end)

	GuiService.Changed:connect(function(prop)
		if prop == "SelectedCoreObject" then
			if not GuiService.SelectedCoreObject or not GuiService.SelectedCoreObject:IsDescendantOf(NotificationFrame) then
				isPaused = false
			end
		end
	end)
end

local UserInputService = game:GetService('UserInputService')
local Platform = UserInputService:GetPlatform()
local Modules = RobloxGui:FindFirstChild('Modules')
if Platform == Enum.Platform.XBoxOne then
	-- Platform hook for controller connection events
	-- Displays overlay to user on controller connection lost
	local PlatformService = nil
	pcall(function() PlatformService = game:GetService('PlatformService') end)
	if PlatformService and Modules then
		local controllerStateManager = require(Modules:FindFirstChild('ControllerStateManager'))
		if controllerStateManager then
			controllerStateManager:Initialize()

			-- retro check in case of controller disconnect while loading
			-- for now, gamepad1 is always mapped to the active user
			controllerStateManager:CheckUserConnected()
		end
	end
end
