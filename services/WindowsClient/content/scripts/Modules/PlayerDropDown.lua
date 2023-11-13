--[[
	// FileName: PlayerDropDown.lua
	// Written by: TheGamer101
	// Description: Code for the player drop down in the PlayerList and Chat
]]
local moduleApiTable = {}

--[[ Services ]]--
local CoreGui = game:GetService('CoreGui')
local HttpService = game:GetService('HttpService')
local HttpRbxApiService = game:GetService('HttpRbxApiService')
local PlayersService = game:GetService('Players')

--[[ Script Variables ]]--
local LocalPlayer = PlayersService.LocalPlayer

--[[ Constants ]]--
local POPUP_ENTRY_SIZE_Y = 24
local ENTRY_PAD = 2
local BG_TRANSPARENCY = 0.5
local BG_COLOR = Color3.new(31/255, 31/255, 31/255)
local TEXT_STROKE_TRANSPARENCY = 0.75
local TEXT_COLOR = Color3.new(1, 1, 243/255)
local TEXT_STROKE_COLOR = Color3.new(34/255, 34/255, 34/255)
local MAX_FRIEND_COUNT = 200
local FRIEND_IMAGE = 'http://www.roblox.com/thumbs/avatar.ashx?userId='

--[[ Fast Flags ]]--
local followerSuccess, isFollowersEnabled = pcall(function() return settings():GetFFlag("EnableLuaFollowers") end)
local IsFollowersEnabled = followerSuccess and isFollowersEnabled

local serverFollowersSuccess, serverFollowersEnabled = pcall(function() return settings():GetFFlag("UserServerFollowers") end)
local IsServerFollowers = serverFollowersSuccess and serverFollowersEnabled

--[[ Modules ]]--
local RobloxGui = CoreGui:WaitForChild('RobloxGui')
local settingsHub = nil

spawn(function()
	settingsHub = require(RobloxGui:WaitForChild("Modules"):WaitForChild("Settings"):WaitForChild("SettingsHub"))
end)

--[[ Bindables ]]--
local BinbableFunction_SendNotification = nil
spawn(function()
	BinbableFunction_SendNotification = RobloxGui:WaitForChild("SendNotification")
end)

--[[ Remotes ]]--
local RemoteEvent_NewFollower = nil

spawn(function()
	local RobloxReplicatedStorage = game:GetService('RobloxReplicatedStorage')
	RemoteEvent_NewFollower = RobloxReplicatedStorage:WaitForChild('NewFollower')
end)

--[[ Utility Functions ]]--
local function createSignal()
	local sig = {}

	local mSignaler = Instance.new('BindableEvent')

	local mArgData = nil
	local mArgDataCount = nil

	function sig:fire(...)
		mArgData = {...}
		mArgDataCount = select('#', ...)
		mSignaler:Fire()
	end

	function sig:connect(f)
		if not f then error("connect(nil)", 2) end
		return mSignaler.Event:connect(function()
			f(unpack(mArgData, 1, mArgDataCount))
		end)
	end

	function sig:wait()
		mSignaler.Event:wait()
		assert(mArgData, "Missing arg data, likely due to :TweenSize/Position corrupting threadrefs.")
		return unpack(mArgData, 1, mArgDataCount)
	end

	return sig
end

--[[ Events ]]--
local BlockStatusChanged = createSignal()

--[[ Personal Server Stuff ]]--
local IsPersonalServer = false
local PersonalServerService = nil
if game.Workspace:FindFirstChild('PSVariable') then
	IsPersonalServer = true
	PersonalServerService = game:GetService('PersonalServerService')
end
game.Workspace.ChildAdded:connect(function(child)
	if child.Name == 'PSVariable' and child:IsA('BoolValue') then
		IsPersonalServer = true
		PersonalServerService = game:GetService('PersonalServerService')
	end
end)

local PRIVILEGE_LEVEL = {
	OWNER = 255,
	ADMIN = 240,
	MEMBER = 128,
	VISITOR = 10,
	BANNED = 0,
}

local function onPrivilegeLevelSelect(player, rank)
	while player.PersonalServerRank < rank do
		PersonalServerService:Promote(player)
	end
	while player.PersonalServerRank > rank do
		PersonalServerService:Demote(player)
	end
end

--[[ Follower Notifications ]]--
local function sendNotification(title, text, image, duration, callback)
	if BinbableFunction_SendNotification then
		BinbableFunction_SendNotification:Invoke(title, text, image, duration, callback)
	end
end

--[[ Friend Functions ]]--
local function getFriendStatus(selectedPlayer)
	if selectedPlayer == LocalPlayer then
		return Enum.FriendStatus.NotFriend
	else
		local success, result = pcall(function()
			-- NOTE: Core script only
			return LocalPlayer:GetFriendStatus(selectedPlayer)
		end)
		if success then
			return result
		else
			return Enum.FriendStatus.NotFriend
		end
	end
end

-- if userId = nil, then it will get count for local player
local function getFriendCountAsync(userId)
	local friendCount = nil
	local wasSuccess, result = pcall(function()
		local str = 'user/get-friendship-count'
		if userId then
			str = str..'?userId='..tostring(userId)
		end
		return HttpRbxApiService:GetAsync(str, true)
	end)
	if not wasSuccess then
		print("getFriendCountAsync() failed because", result)
		return nil
	end
	result = HttpService:JSONDecode(result)

	if result["success"] and result["count"] then
		friendCount = result["count"]
	end

	return friendCount
end

-- checks if we can send a friend request. Right now the only way we
-- can't is if one of the players is at the max friend limit
local function canSendFriendRequestAsync(otherPlayer)
	local theirFriendCount = getFriendCountAsync(otherPlayer.userId)
	local myFriendCount = getFriendCountAsync()

	-- assume max friends if web call fails
	if not myFriendCount or not theirFriendCount then
		return false
	end
	if myFriendCount < MAX_FRIEND_COUNT and theirFriendCount < MAX_FRIEND_COUNT then
		return true
	elseif myFriendCount >= MAX_FRIEND_COUNT then
		sendNotification("Cannot send friend request", "You are at the max friends limit.", "", 5, function() end)
		return false
	elseif theirFriendCount >= MAX_FRIEND_COUNT then
		sendNotification("Cannot send friend request", otherPlayer.Name.." is at the max friends limit.", "", 5, function() end)
		return false
	end
end

--[[ Follower Functions ]]--

-- Returns whether followerUserId is following userId
local function isFollowing(userId, followerUserId)
	local apiPath = "user/following-exists?userId="
	local params = userId.."&followerUserId="..followerUserId
	local success, result = pcall(function()
		return HttpRbxApiService:GetAsync(apiPath..params, true)
	end)
	if not success then
		print("isFollowing() failed because", result)
		return false
	end

	-- can now parse web response
	result = HttpService:JSONDecode(result)
	return result["success"] and result["isFollowing"]
end

--[[ Functions for Blocking users ]]--
local BlockedList = {}
local MutedList = {}

local function GetBlockedPlayersAsync()
	local userId = LocalPlayer.userId
	local apiPath = "userblock/getblockedusers" .. "?" .. "userId=" .. tostring(userId) .. "&" .. "page=" .. "1"
	if userId > 0 then
		local blockList = nil
		local success, msg = pcall(function()
			local request = HttpRbxApiService:GetAsync(apiPath)
			blockList = request and game:GetService('HttpService'):JSONDecode(request)
		end)
		if blockList and blockList['success'] == true and blockList['userList'] then
			return blockList['userList']
		end
	end
	return {}
end

spawn(function()
	BlockedList = GetBlockedPlayersAsync()
end)

local function isBlocked(userId)
	if (BlockedList[userId] ~= nil and BlockedList[userId] == true) then
		return true
	end
	return false
end

local function isMuted(userId)
	if (MutedList[userId] ~= nil and MutedList[userId] == true) then
		return true	
	end
	return false
end

local function BlockPlayerAsync(playerToBlock)
	if playerToBlock and LocalPlayer ~= playerToBlock then
		local blockUserId = playerToBlock.UserId
		if blockUserId > 0 then
			if not isBlocked(blockUserId) then
				BlockedList[blockUserId] = true
				BlockStatusChanged:fire(blockUserId, true)
				pcall(function()
					local success = PlayersService:BlockUser(LocalPlayer.userId, blockUserId)
				end)
			end
		end
	end
end

local function UnblockPlayerAsync(playerToUnblock)
	if playerToUnblock then
		local unblockUserId = playerToUnblock.userId

		if isBlocked(unblockUserId) then
			BlockedList[unblockUserId] = nil
			BlockStatusChanged:fire(unblockUserId, false)
			pcall(function()
				local success = PlayersService:UnblockUser(LocalPlayer.userId, unblockUserId)
			end)
		end
	end
end

local function MutePlayer(playerToMute)
	if playerToMute and LocalPlayer ~= playerToMute then
		local muteUserId = playerToMute.UserId
		if muteUserId > 0 then
			if not isMuted(muteUserId) then
				MutedList[muteUserId] = true
			end
		end
	end
end

local function UnmutePlayer(playerToUnmute)
	if playerToUnmute then
		local unmuteUserId = playerToUnmute.UserId
		MutedList[unmuteUserId] = nil
	end
end

--[[ Function to create DropDown class ]]--
function createPlayerDropDown()
	local playerDropDown = {}
	playerDropDown.Player = nil
	playerDropDown.PopupFrame = nil
	playerDropDown.HidePopupImmediately = false
	playerDropDown.PopupFrameOffScreenPosition = nil -- if this is set the popup frame tweens to a different offscreen position than the default
	
	playerDropDown.HiddenSignal = createSignal()
	
	--[[ Functions for when options in the dropdown are pressed ]]--
	local function onFriendButtonPressed()
		if playerDropDown.Player then
			local status = getFriendStatus(playerDropDown.Player)
			if status == Enum.FriendStatus.Friend then
				LocalPlayer:RevokeFriendship(playerDropDown.Player)
			elseif status == Enum.FriendStatus.Unknown or status == Enum.FriendStatus.NotFriend then
				-- cache and spawn
				local cachedLastSelectedPlayer = playerDropDown.Player
				spawn(function()
					-- check for max friends before letting them send the request
					if canSendFriendRequestAsync(cachedLastSelectedPlayer) then 	-- Yields
						if cachedLastSelectedPlayer and cachedLastSelectedPlayer.Parent == PlayersService then
							LocalPlayer:RequestFriendship(cachedLastSelectedPlayer)
						end
					end
				end)
			elseif status == Enum.FriendStatus.FriendRequestSent then
				LocalPlayer:RevokeFriendship(playerDropDown.Player)
			elseif status == Enum.FriendStatus.FriendRequestReceived then
				LocalPlayer:RequestFriendship(playerDropDown.Player)
			end

			playerDropDown:Hide()
		end
	end
	
	local function onDeclineFriendButonPressed()
		if playerDropDown.Player then
			LocalPlayer:RevokeFriendship(playerDropDown.Player)
			playerDropDown:Hide()
		end
	end
	
	-- Client unfollows followedUserId
	local function onUnfollowButtonPressed()
		if not playerDropDown.Player then return end
		--
		local apiPath = "user/unfollow"
		local params = "followedUserId="..tostring(playerDropDown.Player.userId)
		local success, result = pcall(function()
			return HttpRbxApiService:PostAsync(apiPath, params, true, Enum.ThrottlingPriority.Default, Enum.HttpContentType.ApplicationUrlEncoded)
		end)
		if not success then
			print("unfollowPlayer() failed because", result)
			playerDropDown:Hide()
			return
		end

		result = HttpService:JSONDecode(result)
		if result["success"] then
			if RemoteEvent_NewFollower then
				RemoteEvent_NewFollower:FireServer(playerDropDown.Player, false)
			end
			moduleApiTable.FollowerStatusChanged:fire()
		end

		playerDropDown:Hide()
		-- no need to send notification when someone unfollows
	end

	local function onBlockButtonPressed()
		if playerDropDown.Player then
			local cachedPlayer = playerDropDown.Player
			spawn(function()
				BlockPlayerAsync(cachedPlayer)
			end)
			playerDropDown:Hide()
		end
	end

	local function onUnblockButtonPressed()
		if playerDropDown.Player then
			local cachedPlayer = playerDropDown.Player
			spawn(function()
				UnblockPlayerAsync(cachedPlayer)
			end)
			playerDropDown:Hide()
		end
	end
	
	local function onReportButtonPressed()
		if playerDropDown.Player then
			settingsHub:ReportPlayer(playerDropDown.Player)
			playerDropDown:Hide()
		end
	end
	
	-- Client follows followedUserId
	local function onFollowButtonPressed()
		if not playerDropDown.Player then return end
		--
		local followedUserId = tostring(playerDropDown.Player.userId)
		local apiPath = "user/follow"
		local params = "followedUserId="..followedUserId
		local success, result = pcall(function()
			return HttpRbxApiService:PostAsync(apiPath, params, true, Enum.ThrottlingPriority.Default, Enum.HttpContentType.ApplicationUrlEncoded)
		end)
		if not success then
			print("followPlayer() failed because", result)
			playerDropDown:Hide()
			return
		end

		result = HttpService:JSONDecode(result)
		if result["success"] then
			sendNotification("You are", "now following "..playerDropDown.Player.Name, FRIEND_IMAGE..followedUserId.."&x=48&y=48", 5, function() end)
			if RemoteEvent_NewFollower then
				RemoteEvent_NewFollower:FireServer(playerDropDown.Player, true)
			end
			moduleApiTable.FollowerStatusChanged:fire()
		end

		playerDropDown:Hide()
	end
	
	--[[ GUI Creation Functions ]]--
	local function createPersonalServerDialog(buttons, selectedPlayer)
		local showPersonalServerRanks = IsPersonalServer and LocalPlayer.PersonalServerRank >= PRIVILEGE_LEVEL.ADMIN and LocalPlayer.PersonalServerRank > selectedPlayer.PersonalServerRank
		if showPersonalServerRanks then
			table.insert(buttons, {
				Name = "BanButton",
				Text = "Ban",
				OnPress = function()
					playerDropDown:Hide()
					onPrivilegeLevelSelect(selectedPlayer, PRIVILEGE_LEVEL.BANNED)
				end,
				})
			table.insert(buttons, {
				Name = "VistorButton",
				Text = "Visitor",
				OnPress = function()
					onPrivilegeLevelSelect(selectedPlayer, PRIVILEGE_LEVEL.VISITOR)
				end,
				})
			table.insert(buttons, {
				Name = "MemberButton",
				Text = "Member",
				OnPress = function()
					onPrivilegeLevelSelect(selectedPlayer, PRIVILEGE_LEVEL.MEMBER)
				end,
				})
			table.insert(buttons, {
				Name = "AdminButton",
				Text = "Admin",
				OnPress = function()
					onPrivilegeLevelSelect(selectedPlayer, PRIVILEGE_LEVEL.ADMIN)
				end,
				})
		end
	end
	
	local function createPopupFrame(buttons)
		local frame = Instance.new('Frame')
		frame.Name = "PopupFrame"
		frame.Size = UDim2.new(1, 0, 0, (POPUP_ENTRY_SIZE_Y * #buttons) + (#buttons - ENTRY_PAD))
		frame.Position = UDim2.new(1, 1, 0, 0)
		frame.BackgroundTransparency = 1

		for i,button in ipairs(buttons) do
			local btn = Instance.new('TextButton')
			btn.Name = button.Name
			btn.Size = UDim2.new(1, 0, 0, POPUP_ENTRY_SIZE_Y)
			btn.Position = UDim2.new(0, 0, 0, POPUP_ENTRY_SIZE_Y * (i - 1) + ((i - 1) * ENTRY_PAD))
			btn.BackgroundTransparency = BG_TRANSPARENCY
			btn.BackgroundColor3 = BG_COLOR
			btn.BorderSizePixel = 0
			btn.Text = button.Text
			btn.Font = Enum.Font.SourceSans
			btn.FontSize = Enum.FontSize.Size14
			btn.TextColor3 = TEXT_COLOR
			btn.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
			btn.TextStrokeColor3 = TEXT_STROKE_COLOR
			btn.AutoButtonColor = true
			btn.Parent = frame

			btn.MouseButton1Click:connect(button.OnPress)
		end

		return frame
	end
	
	--[[ PlayerDropDown Functions ]]--
	function playerDropDown:Hide()
		if playerDropDown.PopupFrame then
			local offscreenPosition = (playerDropDown.PopupFrameOffScreenPosition ~= nil and playerDropDown.PopupFrameOffScreenPosition or UDim2.new(1, 1, 0, playerDropDown.PopupFrame.Position.Y.Offset))
			if not playerDropDown.HidePopupImmediately then
				playerDropDown.PopupFrame:TweenPosition(offscreenPosition, Enum.EasingDirection.InOut,
					Enum.EasingStyle.Quad, TWEEN_TIME, true, function()
						if playerDropDown.PopupFrame then
							playerDropDown.PopupFrame:Destroy()
							playerDropDown.PopupFrame = nil
						end
					end)
			else
				playerDropDown.PopupFrame:Destroy()
				playerDropDown.PopupFrame = nil
			end
		end
		if playerDropDown.Player then
			playerDropDown.Player = nil
		end
		playerDropDown.HiddenSignal:fire()
	end
	
	function playerDropDown:CreatePopup(Player)
		playerDropDown.Player = Player
		
		local buttons = {}

		local status = getFriendStatus(playerDropDown.Player)
		local friendText = ""
		local canDeclineFriend = false
		if status == Enum.FriendStatus.Friend then
			friendText = "Unfriend Player"
		elseif status == Enum.FriendStatus.Unknown or status == Enum.FriendStatus.NotFriend then
			friendText = "Send Friend Request"
		elseif status == Enum.FriendStatus.FriendRequestSent then
			friendText = "Revoke Friend Request"
		elseif status == Enum.FriendStatus.FriendRequestReceived then
			friendText = "Accept Friend Request"
			canDeclineFriend = true
		end

		local blocked = isBlocked(playerDropDown.Player.userId)

		if not blocked then
			table.insert(buttons, {
				Name = "FriendButton",
				Text = friendText,
				OnPress = onFriendButtonPressed,
				})
		end

		if canDeclineFriend and not blocked then
			table.insert(buttons, {
				Name = "DeclineFriend",
				Text = "Decline Friend Request",
				OnPress = onDeclineFriendButonPressed,
				})
		end
		-- following status
		if IsServerFollowers or IsFollowersEnabled then
			local following = isFollowing(playerDropDown.Player.userId, LocalPlayer.userId)
			local followerText = following and "Unfollow Player" or "Follow Player"
			
			if not blocked then
				table.insert(buttons, {
					Name = "FollowerButton",
					Text = followerText,
					OnPress = following and onUnfollowButtonPressed or onFollowButtonPressed,
					})
			end
		end

		local blockedText = blocked and "Unblock Player" or "Block Player"
		table.insert(buttons, {
			Name = "BlockButton",
			Text = blockedText,
			OnPress = blocked and onUnblockButtonPressed or onBlockButtonPressed,
			})
		table.insert(buttons, {
			Name = "ReportButton",
			Text = "Report Abuse",
			OnPress = onReportButtonPressed,
			})

		createPersonalServerDialog(buttons, playerDropDown.Player)
		if playerDropDown.PopupFrame then
			playerDropDown.PopupFrame:Destroy()
		end
		playerDropDown.PopupFrame = createPopupFrame(buttons)
		return playerDropDown.PopupFrame
	end
	
	--[[ PlayerRemoving Connection ]]--
	PlayersService.PlayerRemoving:connect(function(leavingPlayer) 
		if playerDropDown.Player == leavingPlayer then
			playerDropDown:Hide()
		end
	end)
	
	return playerDropDown
end


do
	moduleApiTable.FollowerStatusChanged = createSignal()

	function moduleApiTable:CreatePlayerDropDown()
		return createPlayerDropDown()
	end

	function moduleApiTable:CreateBlockingUtility()
		local blockingUtility = {}
		
		function blockingUtility:BlockPlayerAsync(player)
			return BlockPlayerAsync(player)
		end
		
		function blockingUtility:UnblockPlayerAsync(player)
			return UnblockPlayerAsync(player)
		end
		
		function blockingUtility:MutePlayer(player)
			return MutePlayer(player)
		end
		
		function blockingUtility:UnmutePlayer(player)
			return UnmutePlayer(player)
		end
		
		function blockingUtility:IsPlayerBlockedByUserId(userId)
			return isBlocked(userId)
		end

		function blockingUtility:GetBlockedStatusChangedEvent()
			return BlockStatusChanged
		end
		
		function blockingUtility:IsPlayerMutedByUserId(userId)
			return isMuted(userId)
		end
		
		return blockingUtility
	end
end

return moduleApiTable
