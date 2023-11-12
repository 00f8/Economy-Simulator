--[[
		// FileName: PlayerlistModule.lua
		// Version 1.3
		// Written by: jmargh
		// Description: Implementation of in game player list and leaderboard
]]

local CoreGui = game:GetService('CoreGui')
local GuiService = game:GetService('GuiService')	-- NOTE: Can only use in core scripts
local UserInputService = game:GetService('UserInputService')
local HttpService = game:GetService('HttpService')
local HttpRbxApiService = game:GetService('HttpRbxApiService')
local Players = game:GetService('Players')
local TeamsService = game:FindService('Teams')
local ContextActionService = game:GetService('ContextActionService')
local StarterGui = game:GetService('StarterGui')

local RbxGuiLibrary = nil
if LoadLibrary then
	RbxGuiLibrary = LoadLibrary("RbxGui")
end

while not Players.LocalPlayer do
	wait()
end
local Player = Players.LocalPlayer
local RobloxGui = CoreGui:WaitForChild('RobloxGui')

RobloxGui:WaitForChild("Modules"):WaitForChild("TenFootInterface")
local TenFootInterface = require(RobloxGui.Modules.TenFootInterface)
local isTenFootInterface = TenFootInterface:IsEnabled()

local playerDropDownModule = require(RobloxGui.Modules:WaitForChild("PlayerDropDown"))
local blockingUtility = playerDropDownModule:CreateBlockingUtility()
local playerDropDown = playerDropDownModule:CreatePlayerDropDown()

--[[ Fast Flags ]]--
local followerSuccess, isFollowersEnabled = pcall(function() return settings():GetFFlag("EnableLuaFollowers") end)
local IsFollowersEnabled = followerSuccess and isFollowersEnabled

local serverFollowersSuccess, serverFollowersEnabled = pcall(function() return settings():GetFFlag("UserServerFollowers") end)
local IsServerFollowers = serverFollowersSuccess and serverFollowersEnabled

--[[ Remotes ]]--
local RemoveEvent_OnFollowRelationshipChanged = nil
local RemoteFunc_GetFollowRelationships = nil

--[[ Start Module ]]--
local Playerlist = {}

--[[ Public Event API ]]--
-- Parameters: Sorted Array - see GameStats below
Playerlist.OnLeaderstatsChanged = Instance.new('BindableEvent')
-- Parameters: nameOfStat(string), formatedStringOfStat(string)
Playerlist.OnStatChanged = Instance.new('BindableEvent')

--[[ Client Stat Table ]]--
-- Sorted Array of tables
local GameStats = {}
-- Fields
	-- Name: String the developer has given the stat
	-- Text: Formated string of the stat value
	-- AddId: Child add order id
	-- IsPrimary: Is this the primary stat
	-- Priority: Sorting priority
-- NOTE: IsPrimary and Priority are unofficially supported. They are left over legacy from the old player list.
-- They can be un-supported at anytime. You should prefer using child add order to order your stats in the leader board.

--[[ Script Variables ]]--
local topbarEnabled = true
local playerlistCoreGuiEnabled = true
local MyPlayerEntryTopFrame = nil
local PlayerEntries = {}
local StatAddId = 0
local TeamEntries = {}
local TeamAddId = 0
local NeutralTeam = nil
local IsShowingNeutralFrame = false
local LastSelectedFrame = nil
local LastSelectedPlayer = nil
local MinContainerSize = UDim2.new(0, 165, 0.5, 0)
if isTenFootInterface then
	MinContainerSize = UDim2.new(0, 1000, 0, 720)
end
local TempHideKeys = {}

local PlayerEntrySizeY = 24
if isTenFootInterface then
	PlayerEntrySizeY = 80
end

local TeamEntrySizeY = 18

if isTenFootInterface then
	TeamEntrySizeY = 32
end

local NameEntrySizeX = 170
if isTenFootInterface then
	NameEntrySizeX = 350
end

local StatEntrySizeX = 75
if isTenFootInterface then
	StatEntrySizeX = 250
end

local IsSmallScreenDevice = UserInputService.TouchEnabled and GuiService:GetScreenResolution().Y <= 500

local BaseUrl = game:GetService('ContentProvider').BaseUrl:lower()
BaseUrl = string.gsub(BaseUrl, "/m.", "/www.")
AssetGameUrl = string.gsub(BaseUrl, 'www', 'assetgame')

--[[ Constants ]]--
local ENTRY_PAD = 2
local BG_TRANSPARENCY = 0.5
local BG_COLOR = Color3.new(31/255, 31/255, 31/255)
local BG_COLOR_TOP = Color3.new(106/255, 106/255, 106/255)
local TEXT_STROKE_TRANSPARENCY = 0.75
local TEXT_COLOR = Color3.new(1, 1, 243/255)
local TEXT_STROKE_COLOR = Color3.new(34/255, 34/255, 34/255)
local TWEEN_TIME = 0.15
local MAX_LEADERSTATS = 4
local MAX_STR_LEN = 12
local TILE_SPACING = 2
if isTenFootInterface then
	BG_COLOR_TOP = Color3.new(25/255, 25/255, 25/255)
	BG_COLOR = Color3.new(60/255, 60/255, 60/255)
	BG_TRANSPARENCY = 0.25
	TEXT_STROKE_TRANSPARENCY = 1
	TILE_SPACING = 5
end
local SHADOW_IMAGE = 'rbxasset://textures/ui/PlayerList/TileShadowMissingTop.png'--'http://www.roblox.com/asset?id=286965900'
local SHADOW_SLICE_SIZE = 5
local SHADOW_SLICE_RECT = Rect.new(SHADOW_SLICE_SIZE+1, SHADOW_SLICE_SIZE+1, SHADOW_SLICE_SIZE*2-1, SHADOW_SLICE_SIZE*2-1)

local ADMINS = {	-- Admins with special icons
    ['7210880'] = 'http://www.roblox.com/asset/?id=134032333', -- Jeditkacheff
    ['13268404'] = 'http://www.roblox.com/asset/?id=113059239', -- Sorcus
    ['261'] = 'http://www.roblox.com/asset/?id=105897927', -- shedlestky
    ['20396599'] = 'http://www.roblox.com/asset/?id=161078086', -- Robloxsai
}

local ABUSES = {
	"Swearing",
	"Bullying",
	"Scamming",
	"Dating",
	"Cheating/Exploiting",
	"Personal Questions",
	"Offsite Links",
	"Bad Username",
}

local FOLLOWER_STATUS = {
	FOLLOWER = 0,
	FOLLOWING = 1,
	MUTUAL = 2,
}

--[[ Images ]]--
local CHAT_ICON = 'rbxasset://textures/ui/chat_teamButton.png'
local ADMIN_ICON = 'rbxasset://textures/ui/icon_admin-16.png'
local PLACE_OWNER_ICON = 'rbxasset://textures/ui/icon_placeowner.png'
local BC_ICON = 'rbxasset://textures/ui/icon_BC-16.png'
local TBC_ICON = 'rbxasset://textures/ui/icon_TBC-16.png'
local OBC_ICON = 'rbxasset://textures/ui/icon_OBC-16.png'
local BLOCKED_ICON = 'rbxasset://textures/ui/PlayerList/BlockedIcon.png'
local FRIEND_ICON = 'rbxasset://textures/ui/icon_friends_16.png'
local FRIEND_REQUEST_ICON = 'rbxasset://textures/ui/icon_friendrequestsent_16.png'
local FRIEND_RECEIVED_ICON = 'rbxasset://textures/ui/icon_friendrequestrecieved-16.png'

local FOLLOWER_ICON = 'rbxasset://textures/ui/icon_follower-16.png'
local FOLLOWING_ICON = 'rbxasset://textures/ui/icon_following-16.png'
local MUTUAL_FOLLOWING_ICON = 'rbxasset://textures/ui/icon_mutualfollowing-16.png'

local CHARACTER_BACKGROUND_IMAGE = 'rbxasset://textures/ui/PlayerList/CharacterBackgroundImage.png'

--[[ Helper Functions ]]--
local function clamp(value, min, max)
	if value < min then
		value = min
	elseif value > max then
		value = max
	end

	return value
end

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

-- TODO: Once server followers is good to go, remove this function and all code paths
local function getFollowerStatus(selectedPlayer)
	-- we're going to check this flag first in case of a condition were the two flags are not set in sync
	-- in that case, followers will be disabled
	if not IsFollowersEnabled then
		return nil
	end

	if selectedPlayer == Player then
		return nil
	end

	-- ignore guest
	if selectedPlayer.userId <= 0 or Player.userId <= 0 then
		return
	end

	local myUserId = tostring(Player.userId)
	local theirUserId = tostring(selectedPlayer.userId)

	local isFollowingMe = isFollowing(myUserId, theirUserId)
	local isFollowingThem = isFollowing(theirUserId, myUserId)

	if isFollowingMe and isFollowingThem then 	-- mutual
		return FOLLOWER_STATUS.MUTUAL
	elseif isFollowingMe then
		return FOLLOWER_STATUS.FOLLOWER
	elseif isFollowingThem then
		return FOLLOWER_STATUS.FOLLOWING
	else
		return nil
	end
end

local function getFriendStatusIcon(friendStatus)
	if friendStatus == Enum.FriendStatus.Unknown or friendStatus == Enum.FriendStatus.NotFriend then
		return nil
	elseif friendStatus == Enum.FriendStatus.Friend then
		return FRIEND_ICON
	elseif friendStatus == Enum.FriendStatus.FriendRequestSent then
		return FRIEND_REQUEST_ICON
	elseif friendStatus == Enum.FriendStatus.FriendRequestReceived then
		return FRIEND_RECEIVED_ICON
	else
		error("PlayerList: Unknown value for friendStatus: "..tostring(friendStatus))
	end
end

local function getFollowerStatusIcon(followerStatus)
	if followerStatus == FOLLOWER_STATUS.MUTUAL then
		return MUTUAL_FOLLOWING_ICON
	elseif followerStatus == FOLLOWER_STATUS.FOLLOWING then
		return FOLLOWING_ICON
	elseif followerStatus == FOLLOWER_STATUS.FOLLOWER then
		return FOLLOWER_ICON
	else
		return nil
	end
end

local function getAdminIcon(player)
	local userIdStr = tostring(player.userId)
	if ADMINS[userIdStr] then return nil end
	--
	local success, result = pcall(function()
		return player:IsInGroup(1200769)	-- yields
	end)
	if not success then
		print("PlayerListScript2: getAdminIcon() failed because", result)
		return nil
	end
	--
	if result then
		return ADMIN_ICON
	end
end

local function setAvatarIconAsync(player, iconImage)
	-- this function is pretty much for xbox right now and makes use of modules that are part
	-- of the xbox app. Please see Kip or Jason if you have any questions
	local useSubdomainsFlagExists, useSubdomainsFlagValue = pcall(function() return settings():GetFFlag("UseNewSubdomainsInCoreScripts") end)
	local thumbsUrl = BaseUrl
	if(useSubdomainsFlagExists and useSubdomainsFlagValue and AssetGameUrl~=nil) then
		thumbsUrl = AssetGameUrl
	end

	local thumbnailLoader = nil
	pcall(function()
		thumbnailLoader = require(RobloxGui.Modules.ThumbnailLoader)
	end)

	local isFinalSuccess = false
	if thumbnailLoader then
		local loader = thumbnailLoader:Create(iconImage, player.userId,
			thumbnailLoader.Sizes.Small, thumbnailLoader.AssetType.Avatar, true)
		isFinalSuccess = loader:LoadAsync(false, true, nil)
	end

	if not isFinalSuccess then
		iconImage.Image = 'rbxasset://textures/ui/Shell/Icons/DefaultProfileIcon.png'
	end
end

local function getMembershipIcon(player)
	if isTenFootInterface then
		-- return nothing, we need to spawn off setAvatarIconAsync() as a later time to not block
		return ""
	else
		if blockingUtility:IsPlayerBlockedByUserId(player.userId) then
			return BLOCKED_ICON
		else
			local userIdStr = tostring(player.userId)
			local membershipType = player.MembershipType
			if ADMINS[userIdStr] then
				return ADMINS[userIdStr]
			elseif player.userId == game.CreatorId and game.CreatorType == Enum.CreatorType.User then
				return PLACE_OWNER_ICON
			elseif membershipType == Enum.MembershipType.None then
				return ""
			elseif membershipType == Enum.MembershipType.BuildersClub then
				return BC_ICON
			elseif membershipType == Enum.MembershipType.TurboBuildersClub then
				return TBC_ICON
			elseif membershipType == Enum.MembershipType.OutrageousBuildersClub then
				return OBC_ICON
			else
				return ""
			end
		end
	end

	return ""
end

local function isValidStat(obj)
	return obj:IsA('StringValue') or obj:IsA('IntValue') or obj:IsA('BoolValue') or obj:IsA('NumberValue') or
		obj:IsA('DoubleConstrainedValue') or obj:IsA('IntConstrainedValue')
end

local function sortPlayerEntries(a, b)
	if a.PrimaryStat == b.PrimaryStat then
		return a.Player.Name:upper() < b.Player.Name:upper()
	end
	if not a.PrimaryStat then return false end
	if not b.PrimaryStat then return true end
	return a.PrimaryStat > b.PrimaryStat
end

local function sortLeaderStats(a, b)
	if a.IsPrimary ~= b.IsPrimary then
		return a.IsPrimary
	end
	if a.Priority == b.Priority then
		return a.AddId < b.AddId
	end
	return a.Priority < b.Priority
end

local function sortTeams(a, b)
	if a.TeamScore == b.TeamScore then
		return a.Id < b.Id
	end
	if not a.TeamScore then return false end
	if not b.TeamScore then return true end
	return a.TeamScore < b.TeamScore
end

-- Start of Gui Creation
local Container = Instance.new('Frame')
Container.Name = "PlayerListContainer"
if isTenFootInterface then
	Container.Position = UDim2.new(0.5, -MinContainerSize.X.Offset/2, 0.25, 0)
	Container.Size = MinContainerSize
else
	Container.Position = UDim2.new(1, -167, 0, 2)
	Container.Size = MinContainerSize
end

Container.BackgroundTransparency = 1
Container.Visible = false
Container.Parent = RobloxGui

-- Scrolling Frame
local noSelectionObject = Instance.new("Frame")
noSelectionObject.BackgroundTransparency = 1
noSelectionObject.BorderSizePixel = 0

local ScrollList = Instance.new('ScrollingFrame')
ScrollList.Name = "ScrollList"
ScrollList.Size = UDim2.new(1, -1, 0, 0)
if isTenFootInterface then
	ScrollList.Position = UDim2.new(0, 0, 0, PlayerEntrySizeY + TILE_SPACING)
	ScrollList.Size = UDim2.new(1, 19, 0, 0)
end
ScrollList.BackgroundTransparency = 1
ScrollList.BackgroundColor3 = Color3.new()
ScrollList.BorderSizePixel = 0
ScrollList.CanvasSize = UDim2.new(0, 0, 0, 0)	-- NOTE: Look into if x needs to be set to anything
ScrollList.ScrollBarThickness = 6
ScrollList.BottomImage = 'rbxasset://textures/ui/scroll-bottom.png'
ScrollList.MidImage = 'rbxasset://textures/ui/scroll-middle.png'
ScrollList.TopImage = 'rbxasset://textures/ui/scroll-top.png'
ScrollList.SelectionImageObject = noSelectionObject
ScrollList.Parent = Container

-- PlayerDropDown clipping frame
local PopupClipFrame = Instance.new('Frame')
PopupClipFrame.Name = "PopupClipFrame"
PopupClipFrame.Size = UDim2.new(0, 150, 1.5, 0)
PopupClipFrame.Position = UDim2.new(0, -150 - ENTRY_PAD, 0, 0)
PopupClipFrame.BackgroundTransparency = 1
PopupClipFrame.ClipsDescendants = true
PopupClipFrame.Parent = Container


--[[ Creation Helper Functions ]]--
local function createEntryFrame(name, sizeYOffset, isTopStat)
	local containerFrame = Instance.new('Frame')
	containerFrame.Name = name
	containerFrame.Position = UDim2.new(0, 0, 0, 0)
	containerFrame.Size = UDim2.new(1, 0, 0, sizeYOffset)
	if isTenFootInterface then
		containerFrame.Position = UDim2.new(0, 10, 0, 0)
		containerFrame.Size = containerFrame.Size + UDim2.new(0, -20, 0, 0)
	end
	containerFrame.BackgroundTransparency = 1
	containerFrame.ZIndex = isTenFootInterface and 2 or 1

	local nameFrame = Instance.new('TextButton')
	nameFrame.Name = "BGFrame"
	nameFrame.Position = UDim2.new(0, 0, 0, 0)
	nameFrame.Size = UDim2.new(0, NameEntrySizeX, 0, sizeYOffset)
	nameFrame.BackgroundTransparency = isTopStat and 0 or BG_TRANSPARENCY
	nameFrame.BackgroundColor3 = isTopStat and BG_COLOR_TOP or BG_COLOR
	nameFrame.BorderSizePixel = 0
	nameFrame.AutoButtonColor = false
	nameFrame.Text = ""
	nameFrame.Parent = containerFrame
	nameFrame.ZIndex = isTenFootInterface and 2 or 1

	return containerFrame, nameFrame
end

local function createEntryNameText(name, text, sizeXOffset, posXOffset)
	local nameLabel = Instance.new('TextLabel')
	nameLabel.Name = name
	nameLabel.Size = UDim2.new(-0.01, sizeXOffset, 1, 0)
	nameLabel.Position = UDim2.new(0.01, posXOffset, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.SourceSans
	if isTenFootInterface then
		nameLabel.FontSize = Enum.FontSize.Size32
	else
		nameLabel.FontSize = Enum.FontSize.Size14
	end
	nameLabel.TextColor3 = TEXT_COLOR
	nameLabel.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
	nameLabel.TextStrokeColor3 = TEXT_STROKE_COLOR
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ClipsDescendants = true
	nameLabel.Text = text
	nameLabel.ZIndex = isTenFootInterface and 2 or 1

	return nameLabel
end

local function createStatFrame(offset, parent, name, isTopStat)
	local statFrame = Instance.new('Frame')
	statFrame.Name = name
	statFrame.Size = UDim2.new(0, StatEntrySizeX, 1, 0)
	statFrame.Position = UDim2.new(0, offset + TILE_SPACING, 0, 0)
	statFrame.BackgroundTransparency = isTopStat and 0 or BG_TRANSPARENCY
	statFrame.BackgroundColor3 = isTopStat and BG_COLOR_TOP or BG_COLOR
	statFrame.BorderSizePixel = 0
	statFrame.Parent = parent

	if isTenFootInterface then
		statFrame.ZIndex = 2

		local shadow = Instance.new("ImageLabel")
		shadow.BackgroundTransparency = 1
		shadow.Name = 'Shadow'
		shadow.Image = SHADOW_IMAGE
		shadow.Position = UDim2.new(0, -SHADOW_SLICE_SIZE, 0, 0)
		shadow.Size = UDim2.new(1, SHADOW_SLICE_SIZE*2, 1, SHADOW_SLICE_SIZE)
		shadow.ScaleType = 'Slice'
		shadow.SliceCenter = SHADOW_SLICE_RECT
		shadow.Parent = statFrame
	end

	return statFrame
end

local function createStatText(parent, text, isTopStat, isTeamStat)
	local statText = Instance.new('TextLabel')
	statText.Name = "StatText"
	statText.Size = isTopStat and UDim2.new(1, 0, 0.5, 0) or UDim2.new(1, 0, 1, 0)
	statText.Position = isTopStat and UDim2.new(0, 0, 0.5, 0) or UDim2.new(0, 0, 0, 0)
	statText.BackgroundTransparency = 1
	statText.Font = isTopStat and Enum.Font.SourceSansBold or Enum.Font.SourceSans
	if isTenFootInterface then
		statText.FontSize = Enum.FontSize.Size32
	else
		statText.FontSize = Enum.FontSize.Size14
	end
	statText.TextColor3 = TEXT_COLOR
	statText.TextStrokeColor3 = TEXT_STROKE_COLOR
	statText.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
	statText.Text = text
	statText.Active = true
	statText.Parent = parent
	if isTenFootInterface then
		statText.ZIndex = 2
	end

	if isTopStat then
		local statName = statText:Clone()
		statName.Name = "StatName"
		statName.Text = tostring(parent.Name)
		statName.Position = UDim2.new(0,0,0,0)
		statName.Font = Enum.Font.SourceSans
		statName.ClipsDescendants = true
		statName.Parent = parent
		if isTenFootInterface then
			statName.ZIndex = 2
		end
	end

	if isTeamStat then
		statText.Font = 'SourceSansBold'
	end

	return statText
end

local function createImageIcon(image, name, xOffset, parent)
	local imageLabel = Instance.new('ImageLabel')
	imageLabel.Name = name
	if isTenFootInterface then
		imageLabel.Size = UDim2.new(0, 64, 0, 64)
		imageLabel.ZIndex = 2

		local background = Instance.new("ImageLabel", imageLabel)
		background.Name = 'Background'
		background.BackgroundTransparency = 1
		background.Image = CHARACTER_BACKGROUND_IMAGE
		background.Size = UDim2.new(0, 66, 0, 66)
		background.Position = UDim2.new(0.5, -66/2, 0.5, -66/2)
		background.ZIndex = 2
	else
		imageLabel.Size = UDim2.new(0, 16, 0, 16)
	end
	imageLabel.Position = UDim2.new(0.01, xOffset, 0.5, -imageLabel.Size.Y.Offset/2)
	imageLabel.BackgroundTransparency = 1
	imageLabel.Image = image
	imageLabel.BorderSizePixel = 0
	imageLabel.Parent = parent

	return imageLabel
end

local function getScoreValue(statObject)
	if statObject:IsA('DoubleConstrainedValue') or statObject:IsA('IntConstrainedValue') then
		return statObject.ConstrainedValue
	elseif statObject:IsA('BoolValue') then
		if statObject.Value then return 1 else return 0 end
	else
		return statObject.Value
	end
end

local THIN_CHARS = "[^%[iIl\%.,']"
local function strWidth(str)
	return string.len(str) - math.floor(string.len(string.gsub(str, THIN_CHARS, "")) / 2)
end

local function formatNumber(value)
	local _,_,minusSign, int, fraction = tostring(value):find('([-]?)(%d+)([.]?%d*)')
	int = int:reverse():gsub("%d%d%d", "%1,")
	return minusSign..int:reverse():gsub("^,", "")..fraction
end

local function formatStatString(text)
	local numberValue = tonumber(text)
	if numberValue then
		text = formatNumber(numberValue)
	end

	if strWidth(text) <= MAX_STR_LEN then
		return text
	else
		return string.sub(text, 1, MAX_STR_LEN - 3).."..."
	end
end

--[[ Resize Functions ]]--
local LastMaxScrollSize = 0
local function setScrollListSize()
	local teamSize = #TeamEntries * TeamEntrySizeY
	local playerSize = #PlayerEntries * PlayerEntrySizeY
	local spacing = #PlayerEntries * ENTRY_PAD + #TeamEntries * ENTRY_PAD
	local canvasSize = teamSize + playerSize + spacing
	if #TeamEntries > 0 and NeutralTeam and IsShowingNeutralFrame then
		canvasSize = canvasSize + TeamEntrySizeY + ENTRY_PAD
	end
	ScrollList.CanvasSize = UDim2.new(0, 0, 0, canvasSize)
	local newScrollListSize = math.min(canvasSize, Container.AbsoluteSize.y)
	if ScrollList.Size.Y.Offset == LastMaxScrollSize then
		if isTenFootInterface then
			ScrollList.Size = UDim2.new(1, 20, 0, newScrollListSize)
		else
			ScrollList.Size = UDim2.new(1, 0, 0, newScrollListSize)
		end
	end
	LastMaxScrollSize = newScrollListSize
end

--[[ Re-position Functions ]]--
local function setPlayerEntryPositions()
	local position = 0
	for i = 1, #PlayerEntries do
		if isTenFootInterface and PlayerEntries[i].Frame ~= MyPlayerEntryTopFrame then
			PlayerEntries[i].Frame.Position = UDim2.new(0, 10, 0, position)
			position = position + PlayerEntrySizeY + TILE_SPACING
		elseif PlayerEntries[i].Frame ~= MyPlayerEntryTopFrame then
			PlayerEntries[i].Frame.Position = UDim2.new(0, 0, 0, position)
			position = position + PlayerEntrySizeY + TILE_SPACING
		end
	end
end

local function setTeamEntryPositions()
	local teams = {}
	for _,teamEntry in ipairs(TeamEntries) do
		local team = teamEntry.Team
		teams[tostring(team.TeamColor)] = {}
	end
	if NeutralTeam then
		teams.Neutral = {}
	end

	for _,playerEntry in ipairs(PlayerEntries) do
		if playerEntry.Frame ~= MyPlayerEntryTopFrame then
			local player = playerEntry.Player
			if player.Neutral then
				table.insert(teams.Neutral, playerEntry)
			elseif teams[tostring(player.TeamColor)] then
				table.insert(teams[tostring(player.TeamColor)], playerEntry)
			else
				table.insert(teams.Neutral, playerEntry)
			end
		end
	end

	local position = 0
	for _,teamEntry in ipairs(TeamEntries) do
		local team = teamEntry.Team
		teamEntry.Frame.Position = UDim2.new(0, isTenFootInterface and 10 or 0, 0, position)
		position = position + TeamEntrySizeY + TILE_SPACING
		local players = teams[tostring(team.TeamColor)]
		for _,playerEntry in ipairs(players) do
			playerEntry.Frame.Position = UDim2.new(0, isTenFootInterface and 10 or 0, 0, position)
			position = position + PlayerEntrySizeY + TILE_SPACING
		end
	end
	if NeutralTeam then
		NeutralTeam.Frame.Position = UDim2.new(0, isTenFootInterface and 10 or 0, 0, position)
		position = position + TeamEntrySizeY + TILE_SPACING
		if #teams.Neutral > 0 then
			IsShowingNeutralFrame = true
			local players = teams.Neutral
			for _,playerEntry in ipairs(players) do
				playerEntry.Frame.Position = UDim2.new(0, isTenFootInterface and 10 or 0, 0, position)
				position = position + PlayerEntrySizeY + TILE_SPACING
			end
		else
			IsShowingNeutralFrame = false
		end
	end
end

local function setEntryPositions()
	table.sort(PlayerEntries, sortPlayerEntries)
	if #TeamEntries > 0 then
		setTeamEntryPositions()
	else
		setPlayerEntryPositions()
	end
end

local function updateSocialIcon(newIcon, bgFrame)
	local socialIcon = bgFrame:FindFirstChild('SocialIcon')
	local nameFrame = bgFrame:FindFirstChild('PlayerName')
	local offset = 19
	if socialIcon then
		if newIcon then
			socialIcon.Image = newIcon
		else
			if nameFrame then
				local newSize = nameFrame.Size.X.Offset + socialIcon.Size.X.Offset + 2
				nameFrame.Size = UDim2.new(-0.01, newSize, 0.5, 0)
				nameFrame.Position = UDim2.new(0.01, offset, 0.245, 0)
			end
			socialIcon:Destroy()
		end
	elseif newIcon and bgFrame then
		socialIcon = createImageIcon(newIcon, "SocialIcon", offset, bgFrame)
		offset = offset + socialIcon.Size.X.Offset + 2
		if nameFrame then
			local newSize = bgFrame.Size.X.Offset - offset
			nameFrame.Size = UDim2.new(-0.01, newSize, 0.5, 0)
			nameFrame.Position = UDim2.new(0.01, offset, 0.245, 0)
		end
	end
end

local function getFriendStatus(selectedPlayer)
	if selectedPlayer == Player then
		return Enum.FriendStatus.NotFriend
	else
		local success, result = pcall(function()
			-- NOTE: Core script only
			return Player:GetFriendStatus(selectedPlayer)
		end)
		if success then
			return result
		else
			return Enum.FriendStatus.NotFriend
		end
	end
end

local function onFollowerStatusChanged()
	-- TODO: Remove this event completely when server version is stable
	if not IsFollowersEnabled and not LastSelectedFrame or not LastSelectedPlayer then
		return
	end

	-- don't update icon if already friends
	local friendStatus = getFriendStatus(LastSelectedPlayer)
	if friendStatus == Enum.FriendStatus.Friend then
		return
	end

	local bgFrame = LastSelectedFrame:FindFirstChild('BGFrame')
	local followerStatus = getFollowerStatus(LastSelectedPlayer)
	local newIcon = getFollowerStatusIcon(followerStatus)
	if bgFrame then
		updateSocialIcon(newIcon, bgFrame)
	end
end
-- Don't listen/show rbx follower status on xbox
if not isTenFootInterface then
	playerDropDownModule.FollowerStatusChanged:connect(onFollowerStatusChanged)
end

function popupHidden()
	if LastSelectedFrame then
		for _,childFrame in pairs(LastSelectedFrame:GetChildren()) do
			if childFrame:IsA('TextButton') or childFrame:IsA('Frame') then
				childFrame.BackgroundColor3 = BG_COLOR
			end
		end
	end
	ScrollList.ScrollingEnabled = true
	LastSelectedFrame = nil
	LastSelectedPlayer = nil
end
playerDropDown.HiddenSignal:connect(popupHidden)

local function onEntryFrameSelected(selectedFrame, selectedPlayer)
	if selectedPlayer ~= Player and selectedPlayer.userId > 1 and Player.userId > 1 then
		if LastSelectedFrame ~= selectedFrame then
			if LastSelectedFrame then
				for _,childFrame in pairs(LastSelectedFrame:GetChildren()) do
					if childFrame:IsA('TextButton') or childFrame:IsA('Frame') then
						childFrame.BackgroundColor3 = BG_COLOR
					end
				end
			end
			LastSelectedFrame = selectedFrame
			LastSelectedPlayer = selectedPlayer
			for _,childFrame in pairs(selectedFrame:GetChildren()) do
				if childFrame:IsA('TextButton') or childFrame:IsA('Frame') then
					childFrame.BackgroundColor3 = Color3.new(0, 1, 1)
				end
			end
			-- NOTE: Core script only
			ScrollList.ScrollingEnabled = false
			
			local PopupFrame = playerDropDown:CreatePopup(selectedPlayer)		
			PopupFrame.Position = UDim2.new(1, 1, 0, selectedFrame.Position.Y.Offset - ScrollList.CanvasPosition.y)
			PopupFrame.Parent = PopupClipFrame
			PopupFrame:TweenPosition(UDim2.new(0, 0, 0, selectedFrame.Position.Y.Offset - ScrollList.CanvasPosition.y), Enum.EasingDirection.InOut, Enum.EasingStyle.Quad, TWEEN_TIME, true)
		else
			playerDropDown:Hide()
			LastSelectedFrame = nil
			LastSelectedPlayer = nil
		end
	end
end

local function onFriendshipChanged(otherPlayer, newFriendStatus)
	local entryToUpdate = nil
	for _,entry in ipairs(PlayerEntries) do
		if entry.Player == otherPlayer then
			entryToUpdate = entry
			break
		end
	end
	if not entryToUpdate then
		return
	end
	local newIcon = getFriendStatusIcon(newFriendStatus)
	local frame = entryToUpdate.Frame
	local bgFrame = frame:FindFirstChild('BGFrame')
	if bgFrame then
		--no longer friends, but might still be following
		if not IsServerFollowers and IsFollowersEnabled and not newIcon then
			local followerStatus = getFollowerStatus(otherPlayer)
			newIcon = getFollowerStatusIcon(followerStatus)
		end

		updateSocialIcon(newIcon, bgFrame)
	end
end

-- NOTE: Core script only. This fires when a player joins the game.
-- Don't listen/show rbx friends status on xbox
if not isTenFootInterface then
	Player.FriendStatusChanged:connect(onFriendshipChanged)
end

--[[ Begin New Server Followers ]]--
local function setFollowRelationshipsView(relationshipTable)
	if not relationshipTable then
		return
	end

	for i = 1, #PlayerEntries do
		local entry = PlayerEntries[i]
		local player = entry.Player
		local userId = tostring(player.userId)

		-- don't update icon if already friends
		local friendStatus = getFriendStatus(player)
		if friendStatus == Enum.FriendStatus.Friend then
			return
		end

		local icon = nil
		if relationshipTable[userId] then
			local relationship = relationshipTable[userId]
			if relationship.IsMutual == true then
				icon = MUTUAL_FOLLOWING_ICON
			elseif relationship.IsFollowing == true then
				icon = FOLLOWING_ICON
			elseif relationship.IsFollower == true then
				icon = FOLLOWER_ICON
			end
		end

		local frame = entry.Frame
		local bgFrame = frame:FindFirstChild('BGFrame')
		if bgFrame then
			updateSocialIcon(icon, bgFrame)
		end
	end
end

local function getFollowRelationships()
	local result = nil
	if RemoteFunc_GetFollowRelationships then
		result = RemoteFunc_GetFollowRelationships:InvokeServer()
	end
	return result
end

--[[ End New Server Followers ]]--

local function updateAllTeamScores()
	local teamScores = {}
	for _,playerEntry in ipairs(PlayerEntries) do
		local player = playerEntry.Player
		local leaderstats = player:FindFirstChild('leaderstats')
		local team = player.Neutral and 'Neutral' or tostring(player.TeamColor)
		local isInValidColor = true
		if team ~= 'Neutral' then
			for _,teamEntry in ipairs(TeamEntries) do
				local color = teamEntry.Team.TeamColor
				if team == tostring(color) then
					isInValidColor = false
					break
				end
			end
		end
		if isInValidColor then
			team = 'Neutral'
		end
		if not teamScores[team] then
			teamScores[team] = {}
		end
		if playerEntry.Frame ~= MyPlayerEntryTopFrame then
			if leaderstats then
				for _,stat in ipairs(GameStats) do
					local statObject = leaderstats:FindFirstChild(stat.Name)
					if statObject and not statObject:IsA('StringValue') then
						if not teamScores[team][stat.Name] then
							teamScores[team][stat.Name] = 0
						end
						teamScores[team][stat.Name] = teamScores[team][stat.Name] + getScoreValue(statObject)
					end
				end
			end
		end
	end

	for _,teamEntry in ipairs(TeamEntries) do
		local team = teamEntry.Team
		local frame = teamEntry.Frame
		local color = tostring(team.TeamColor)
		local stats = teamScores[color]
		if stats then
			for statName,statValue in pairs(stats) do
				local statFrame = frame:FindFirstChild(statName)
				if statFrame then
					local statText = statFrame:FindFirstChild('StatText')
					if statText then
						statText.Text = formatStatString(tostring(statValue))
					end
				end
			end
		else
			for _,childFrame in pairs(frame:GetChildren()) do
				local statText = childFrame:FindFirstChild('StatText')
				if statText then
					statText.Text = ''
				end
			end
		end
	end
	if NeutralTeam then
		local frame = NeutralTeam.Frame
		local stats = teamScores['Neutral']
		if stats then
			frame.Visible = true
			for statName,statValue in pairs(stats) do
				local statFrame = frame:FindFirstChild(statName)
				if statFrame then
					local statText = statFrame:FindFirstChild('StatText')
					if statText then
						statText.Text = formatStatString(tostring(statValue))
					end
				end
			end
		else
			frame.Visible = false
		end
	end
end

local function updateTeamEntry(entry)
	local frame = entry.Frame
	local team = entry.Team
	local color = team.TeamColor.Color
	local offset = NameEntrySizeX
	for _,stat in ipairs(GameStats) do
		local statFrame = frame:FindFirstChild(stat.Name)
		if not statFrame then
			statFrame = createStatFrame(offset, frame, stat.Name)
			statFrame.BackgroundColor3 = color
			createStatText(statFrame, "", false, true)
		end
		statFrame.Position = UDim2.new(0, offset + TILE_SPACING, 0, 0)
		offset = offset + statFrame.Size.X.Offset + TILE_SPACING
	end
end

local function updatePrimaryStats(statName)
	for _,entry in ipairs(PlayerEntries) do
		local player = entry.Player
		local leaderstats = player:FindFirstChild('leaderstats')
		entry.PrimaryStat = nil
		if leaderstats then
			local statObject = leaderstats:FindFirstChild(statName)
			if statObject then
				local scoreValue = getScoreValue(statObject)
				entry.PrimaryStat = scoreValue
			end
		end
	end
end

local updateLeaderstatFrames = nil
-- TODO: fire event to top bar?
local function initializeStatText(stat, statObject, entry, statFrame, index, isTopStat)
	local player = entry.Player
	local statValue = getScoreValue(statObject)
	if statObject.Name == GameStats[1].Name then
		entry.PrimaryStat = statValue
	end
	local statText = createStatText(statFrame, formatStatString(tostring(statValue)), isTopStat)
	-- Top Bar insertion
	if player == Player then
		stat.Text = statText.Text
	end

	statObject.Changed:connect(function(newValue)
		local scoreValue = getScoreValue(statObject)
		statText.Text = formatStatString(tostring(scoreValue))
		if statObject.Name == GameStats[1].Name then
			entry.PrimaryStat = scoreValue
		end
		-- Top bar changed event
		if player == Player then
			stat.Text = statText.Text
			Playerlist.OnStatChanged:Fire(stat.Name, stat.Text)
		end
		updateAllTeamScores()
		setEntryPositions()
	end)
	statObject.ChildAdded:connect(function(child)
		if child.Name == "IsPrimary" then
			GameStats[1].IsPrimary = false
			stat.IsPrimary = true
			updatePrimaryStats(stat.Name)
			if updateLeaderstatFrames then updateLeaderstatFrames() end
			Playerlist.OnLeaderstatsChanged:Fire(GameStats)
		end
	end)
end

updateLeaderstatFrames = function()
	table.sort(GameStats, sortLeaderStats)
	if #TeamEntries > 0 then
		for _,entry in ipairs(TeamEntries) do
			updateTeamEntry(entry)
		end
		if NeutralTeam then
			updateTeamEntry(NeutralTeam)
		end
	end

	for _,entry in ipairs(PlayerEntries) do
		local player = entry.Player
		local mainFrame = entry.Frame
		local offset = NameEntrySizeX
		local leaderstats = player:FindFirstChild('leaderstats')
		local isTopStat = (entry.Frame == MyPlayerEntryTopFrame)

		if leaderstats then
			for _,stat in ipairs(GameStats) do
				local statObject = leaderstats:FindFirstChild(stat.Name)
				local statFrame = mainFrame:FindFirstChild(stat.Name)

				if not statFrame then
					statFrame = createStatFrame(offset, mainFrame, stat.Name, isTopStat)
					if statObject then
						initializeStatText(stat, statObject, entry, statFrame, _, isTopStat)
					end
				elseif statObject then
					local statText = statFrame:FindFirstChild('StatText')
					if not statText then
						initializeStatText(stat, statObject, entry, statFrame, _, isTopStat)
					end
				end
				statFrame.Position = UDim2.new(0, offset + TILE_SPACING, 0, 0)
				offset = offset + statFrame.Size.X.Offset + TILE_SPACING
			end
		else
			for _,stat in ipairs(GameStats) do
				local statFrame = mainFrame:FindFirstChild(stat.Name)
				if not statFrame then
					statFrame = createStatFrame(offset, mainFrame, stat.Name, isTopStat)
				end
				offset = offset + statFrame.Size.X.Offset + TILE_SPACING
			end
		end

		if entry.Frame ~= MyPlayerEntryTopFrame then
			if isTenFootInterface then
				Container.Position = UDim2.new(0.5, -offset/2, 0, 110)
				Container.Size = UDim2.new(0, offset, 0.8, 0)
			else
				Container.Position = UDim2.new(1, -offset, 0, 2)
				Container.Size = UDim2.new(0, offset, 0.5, 0)
			end

			local newMinContainerOffset = offset
			MinContainerSize = UDim2.new(0, newMinContainerOffset, 0.5, 0)
		end
	end
	updateAllTeamScores()
	setEntryPositions()
	Playerlist.OnLeaderstatsChanged:Fire(GameStats)
end

local function addNewStats(leaderstats)
	for i,stat in ipairs(leaderstats:GetChildren()) do
		if isValidStat(stat) and #GameStats < MAX_LEADERSTATS then
			local gameHasStat = false
			for _,gStat in ipairs(GameStats) do
				if stat.Name == gStat.Name then
					gameHasStat = true
					break
				end
			end

			if not gameHasStat then
				local newStat = {}
				newStat.Name = stat.Name
				newStat.Text = "-"
				newStat.Priority = 0
				local priority = stat:FindFirstChild('Priority')
				if priority then newStat.Priority = priority end
				newStat.IsPrimary = false
				local isPrimary = stat:FindFirstChild('IsPrimary')
				if isPrimary then
					newStat.IsPrimary = true
				end
				newStat.AddId = StatAddId
				StatAddId = StatAddId + 1
				table.insert(GameStats, newStat)
				table.sort(GameStats, sortLeaderStats)
				if #GameStats == 1 then
					setScrollListSize()
					setEntryPositions()
				end
			end
		end
	end
end

local function removeStatFrameFromEntry(stat, frame)
	local statFrame = frame:FindFirstChild(stat.Name)
	if statFrame then
		statFrame:Destroy()
	end
end

local function doesStatExists(stat)
	local doesExists = false
	for _,entry in ipairs(PlayerEntries) do
		local player = entry.Player
		if player then
			local leaderstats = player:FindFirstChild('leaderstats')
			if leaderstats and leaderstats:FindFirstChild(stat.Name) then
				doesExists = true
				break
			end
		end
	end

	return doesExists
end

local function onStatRemoved(oldStat, entry)
	if isValidStat(oldStat) then
		removeStatFrameFromEntry(oldStat, entry.Frame)
		local statExists = doesStatExists(oldStat)
		--
		local toRemove = nil
		for i, stat in ipairs(GameStats) do
			if stat.Name == oldStat.Name then
				toRemove = i
				break
			end
		end
		-- removed from player but not from game; another player still has this stat
		if statExists then
			if toRemove and entry.Player == Player then
				GameStats[toRemove].Text = "-"
				Playerlist.OnStatChanged:Fire(GameStats[toRemove].Name, GameStats[toRemove].Text)
			end
		-- removed from game
		else
			for _,playerEntry in ipairs(PlayerEntries) do
				removeStatFrameFromEntry(oldStat, playerEntry.Frame)
			end
			for _,teamEntry in ipairs(TeamEntries) do
				removeStatFrameFromEntry(oldStat, teamEntry.Frame)
			end
			if toRemove then
				table.remove(GameStats, toRemove)
				table.sort(GameStats, sortLeaderStats)
			end
		end
		if GameStats[1] then
			updatePrimaryStats(GameStats[1].Name)
		end
		updateLeaderstatFrames()
	end
end

local function onStatAdded(leaderstats, entry)
	leaderstats.ChildAdded:connect(function(newStat)
		if isValidStat(newStat) then
			addNewStats(newStat.Parent)
			updateLeaderstatFrames()
		end
	end)
	leaderstats.ChildRemoved:connect(function(child)
		onStatRemoved(child, entry)
	end)
	addNewStats(leaderstats)
	updateLeaderstatFrames()
end

local function setLeaderStats(entry)
	local player = entry.Player
	local leaderstats = player:FindFirstChild('leaderstats')

	if leaderstats then
		onStatAdded(leaderstats, entry)
	end

	local function onPlayerChildChanged(property, child)
		if property == 'Name' and child.Name == 'leaderstats' then
			onStatAdded(child, entry)
		end
	end

	player.ChildAdded:connect(function(child)
		if child.Name == 'leaderstats' then
			onStatAdded(child, entry)
		end
		child.Changed:connect(function(property) onPlayerChildChanged(property, child) end)
	end)
	for _,child in pairs(player:GetChildren()) do
		child.Changed:connect(function(property) onPlayerChildChanged(property, child) end)
	end

	player.ChildRemoved:connect(function(child)
		if child.Name == 'leaderstats' then
			for i,stat in ipairs(child:GetChildren()) do
				onStatRemoved(stat, entry)
			end
			updateLeaderstatFrames()
		end
	end)
end

local offsetSize = 18
if isTenFootInterface then offsetSize = 32 end

local function createPlayerEntry(player, isTopStat)
	local playerEntry = {}
	local name = player.Name

	local containerFrame, entryFrame = createEntryFrame(name, PlayerEntrySizeY, isTopStat)
	entryFrame.Active = true

	if not isTenFootInterface then
		local function localEntrySelected()
			onEntryFrameSelected(containerFrame, player)
		end
		entryFrame.MouseButton1Click:connect(localEntrySelected)
	end

	local currentXOffset = 1

	-- check membership
	local membershipIconImage = getMembershipIcon(player)
	local membershipIcon = nil
	if membershipIconImage then
		membershipIcon = createImageIcon(membershipIconImage, "MembershipIcon", currentXOffset, entryFrame)
		currentXOffset = currentXOffset + membershipIcon.Size.X.Offset + 2
	else
		currentXOffset = currentXOffset + offsetSize
	end

	spawn(function()
		if isTenFootInterface and membershipIcon then
			setAvatarIconAsync(player, membershipIcon)
		end
	end)

	-- Some functions yield, so we need to spawn off in order to not cause a race condition with other events like Players.ChildRemoved
	spawn(function()
		local success, result = pcall(function()
			return player:GetRankInGroup(game.CreatorId) == 255
		end)
		if success then
			if game.CreatorType == Enum.CreatorType.Group and result then
				membershipIconImage = PLACE_OWNER_ICON
				if not membershipIcon then
					membershipIcon = createImageIcon(membershipIconImage, "MembershipIcon", 1, entryFrame)
				else
					membershipIcon.Image = membershipIconImage
				end
			end
		else
			print("PlayerList: GetRankInGroup failed because", result)
		end
		local adminIconImage = getAdminIcon(player)
		if adminIconImage then
			if not membershipIcon then
				membershipIcon = createImageIcon(adminIconImage, "MembershipIcon", 1, entryFrame)
			else
				membershipIcon.Image = adminIconImage
			end
		end
		-- Friendship and Follower status is checked by onFriendshipChanged, which is called by the FriendStatusChanged
		-- event. This event is fired when any player joins the game. onFriendshipChanged will check Follower status in
		-- the case that we are not friends with the new player who is joining.
	end)

	local playerNameXSize = entryFrame.Size.X.Offset - currentXOffset
	local playerName = createEntryNameText("PlayerName", name, playerNameXSize, currentXOffset)
	playerName.Parent = entryFrame
	playerEntry.Player = player
	playerEntry.Frame = containerFrame

	if isTenFootInterface then
		local shadow = Instance.new("ImageLabel")
		shadow.BackgroundTransparency = 1
		shadow.Name = 'Shadow'
		shadow.Image = SHADOW_IMAGE
		shadow.Position = UDim2.new(0, -SHADOW_SLICE_SIZE, 0, 0)
		shadow.Size = UDim2.new(1, SHADOW_SLICE_SIZE*2, 1, SHADOW_SLICE_SIZE)
		shadow.ScaleType = 'Slice'
		shadow.SliceCenter = SHADOW_SLICE_RECT
		shadow.Parent = entryFrame
	end

	if isTopStat then
		playerName.Font = 'SourceSansBold'
	end

	return playerEntry
end

local function createTeamEntry(team)
	local teamEntry = {}
	teamEntry.Team = team
	teamEntry.TeamScore = 0

	local containerFrame, entryFrame = createEntryFrame(team.Name, TeamEntrySizeY)
	entryFrame.BackgroundColor3 = team.TeamColor.Color

	local teamName = createEntryNameText("TeamName", team.Name, entryFrame.AbsoluteSize.x, 1)
	teamName.Parent = entryFrame

	teamEntry.Frame = containerFrame

	if isTenFootInterface then
		local shadow = Instance.new("ImageLabel")
		shadow.BackgroundTransparency = 1
		shadow.Name = 'Shadow'
		shadow.Image = SHADOW_IMAGE
		shadow.Position = UDim2.new(0, -SHADOW_SLICE_SIZE, 0, 0)
		shadow.Size = UDim2.new(1, SHADOW_SLICE_SIZE*2, 1, SHADOW_SLICE_SIZE)
		shadow.ScaleType = 'Slice'
		shadow.SliceCenter = SHADOW_SLICE_RECT
		shadow.Parent = entryFrame
	end

	-- connections
	team.Changed:connect(function(property)
		if property == 'Name' then
			teamName.Text = team.Name
		elseif property == 'TeamColor' then
			for _,childFrame in pairs(containerFrame:GetChildren()) do
				if childFrame:IsA('GuiObject') then
					childFrame.BackgroundColor3 = team.TeamColor.Color
				end
			end

			setTeamEntryPositions()
			updateAllTeamScores()
			setEntryPositions()
			setScrollListSize()
		end
	end)

	return teamEntry
end

local function createNeutralTeam()
	if not NeutralTeam then
		local team = Instance.new('Team')
		team.Name = 'Neutral'
		team.TeamColor = BrickColor.new('White')
		NeutralTeam = createTeamEntry(team)
		NeutralTeam.Frame.Parent = ScrollList
	end
end

--[[ Insert/Remove Player Functions ]]--
local function setupEntry(player, newEntry, isTopStat)
	setLeaderStats(newEntry)
	
	if isTopStat then
		newEntry.Frame.Parent = Container
		table.insert(PlayerEntries, newEntry)
	else
		newEntry.Frame.Parent = ScrollList
		table.insert(PlayerEntries, newEntry)
		setScrollListSize()
	end
		
	updateLeaderstatFrames()

	player.Changed:connect(function(property)
		if #TeamEntries > 0 and (property == 'Neutral' or property == 'TeamColor') then
			setTeamEntryPositions()
			updateAllTeamScores()
			setEntryPositions()
			setScrollListSize()
		end
	end)
end

local function insertPlayerEntry(player)
	local entry = createPlayerEntry(player)
	setupEntry(player, entry)

	-- create an entry on the top of the playerlist
	if player == Player and isTenFootInterface then
		local localEntry = createPlayerEntry(player, true)
		MyPlayerEntryTopFrame = localEntry.Frame
		MyPlayerEntryTopFrame.BackgroundTransparency = 1
		MyPlayerEntryTopFrame.BorderSizePixel = 0
		setupEntry(player, localEntry, true)
	end
end

local function removePlayerEntry(player)
	for i = 1, #PlayerEntries do
		if PlayerEntries[i].Player == player then
			PlayerEntries[i].Frame:Destroy()
			table.remove(PlayerEntries, i)
			break
		end
	end
	setEntryPositions()
	setScrollListSize()
end

--[[ Team Functions ]]--
local function onTeamAdded(team)
	for i = 1, #TeamEntries do
		if TeamEntries[i].Team.TeamColor == team.TeamColor then
			TeamEntries[i].Frame:Destroy()
			table.remove(TeamEntries, i)
			break
		end
	end
	local entry = createTeamEntry(team)
	entry.Id = TeamAddId
	TeamAddId = TeamAddId + 1
	if not NeutralTeam then
		createNeutralTeam()
	end
	table.insert(TeamEntries, entry)
	table.sort(TeamEntries, sortTeams)
	setTeamEntryPositions()
	updateLeaderstatFrames()
	setScrollListSize()
	entry.Frame.Parent = ScrollList
end

local function onTeamRemoved(removedTeam)
	for i = 1, #TeamEntries do
		local team = TeamEntries[i].Team
		if team.Name == removedTeam.Name then
			TeamEntries[i].Frame:Destroy()
			table.remove(TeamEntries, i)
			break
		end
	end
	if #TeamEntries == 0 then
		if NeutralTeam then
			NeutralTeam.Frame:Destroy()
			NeutralTeam.Team:Destroy()
			NeutralTeam = nil
			IsShowingNeutralFrame = false
		end
	end
	setEntryPositions()
	updateLeaderstatFrames()
	setScrollListSize()
end

--[[ Resize/Position Functions ]]--
local function clampCanvasPosition()
	local maxCanvasPosition = ScrollList.CanvasSize.Y.Offset - ScrollList.Size.Y.Offset
	if maxCanvasPosition >= 0 and ScrollList.CanvasPosition.y > maxCanvasPosition then
		ScrollList.CanvasPosition = Vector2.new(0, maxCanvasPosition)
	end
end

local function resizePlayerList()
	setScrollListSize()
	clampCanvasPosition()
end

RobloxGui.Changed:connect(function(property)
	if property == 'AbsoluteSize' then
		spawn(function()	-- must spawn because F11 delays when abs size is set
			resizePlayerList()
		end)
	end
end)

UserInputService.InputBegan:connect(function(inputObject, isProcessed)
	if isProcessed then return end
	local inputType = inputObject.UserInputType
	if (inputType == Enum.UserInputType.Touch and  inputObject.UserInputState == Enum.UserInputState.Begin) or
		inputType == Enum.UserInputType.MouseButton1 then
		if LastSelectedFrame then
			playerDropDown:Hide()
		end
	end
end)

-- NOTE: Core script only

--[[ Player Add/Remove Connections ]]--
Players.ChildAdded:connect(function(child)
	if child:IsA('Player') then
		insertPlayerEntry(child)
	end
end)
for _,player in pairs(Players:GetPlayers()) do
	insertPlayerEntry(player)
end

--[[ Begin new Server Followers ]]--
-- Don't listen/show rbx followers status on console
if IsServerFollowers and not isTenFootInterface then
	-- spawn so we don't block script
	spawn(function()
		local RobloxReplicatedStorage = game:GetService('RobloxReplicatedStorage')
		RemoveEvent_OnFollowRelationshipChanged = RobloxReplicatedStorage:WaitForChild('FollowRelationshipChanged')
		RemoteFunc_GetFollowRelationships = RobloxReplicatedStorage:WaitForChild('GetFollowRelationships')

		RemoveEvent_OnFollowRelationshipChanged.OnClientEvent:connect(function(result)
			setFollowRelationshipsView(result)
		end)

		local result = getFollowRelationships()
		setFollowRelationshipsView(result)
	end)
end

Players.ChildRemoved:connect(function(child)
	if child:IsA('Player') then
		if LastSelectedPlayer and child == LastSelectedPlayer then
			playerDropDown:Hide()
		end
		removePlayerEntry(child)
	end
end)

--[[ Teams ]]--
local function initializeTeams(teams)
	for _,team in pairs(teams:GetTeams()) do
		onTeamAdded(team)
	end

	teams.ChildAdded:connect(function(team)
		if team:IsA('Team') then
			onTeamAdded(team)
		end
	end)

	teams.ChildRemoved:connect(function(team)
		if team:IsA('Team') then
			onTeamRemoved(team)
		end
	end)
end

TeamsService = game:FindService('Teams')
if TeamsService then
	initializeTeams(TeamsService)
end

game.ChildAdded:connect(function(child)
	if child:IsA('Teams') then
		initializeTeams(child)
	end
end)

--[[ Public API ]]--
Playerlist.GetStats = function()
	return GameStats
end

local noOpFunc = function ( )
end

local isOpen = not isTenFootInterface

local closeListFunc = function(name, state, input)
	if state ~= Enum.UserInputState.Begin then return end

	isOpen = false
	Container.Visible = false
	spawn(function() GuiService:SetMenuIsOpen(false) end)
	ContextActionService:UnbindCoreAction("CloseList")
	ContextActionService:UnbindCoreAction("StopAction")
	GuiService.SelectedCoreObject = nil
	UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None
end

local setVisible = function(state, fromTemp)
	Container.Visible = state

	if state then
		local children = ScrollList:GetChildren()
		if children and #children > 0 then
			local frame = children[1]
			local frameChildren = frame:GetChildren()
			for i = 1, #frameChildren do
				if frameChildren[i]:IsA("TextButton") then
					local lastInputType = UserInputService:GetLastInputType()
					local isUsingGamepad = (lastInputType == Enum.UserInputType.Gamepad1 or lastInputType == Enum.UserInputType.Gamepad2 or
												lastInputType == Enum.UserInputType.Gamepad3 or lastInputType == Enum.UserInputType.Gamepad4)
					if not isTenFootInterface then
						if isUsingGamepad and not fromTemp then
							GuiService.SelectedCoreObject = frameChildren[i]
						end
					elseif not fromTemp then
						GuiService.SelectedCoreObject = ScrollList
					end

					if isUsingGamepad and not fromTemp then
						UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceHide
						ContextActionService:BindCoreAction("StopAction", noOpFunc, false, Enum.UserInputType.Gamepad1)
						ContextActionService:BindCoreAction("CloseList", closeListFunc, false, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonStart)
					end
					break
				end
			end
		end
	else
		if isUsingGamepad then
			UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None
		end
		
		ContextActionService:UnbindCoreAction("CloseList")
		ContextActionService:UnbindCoreAction("StopAction")

		if GuiService.SelectedCoreObject and GuiService.SelectedCoreObject:IsDescendantOf(Container) then
			GuiService.SelectedCoreObject = nil
		end
	end
end

Playerlist.ToggleVisibility = function(name, inputState, inputObject)
	if inputState and inputState ~= Enum.UserInputState.Begin then return end
	if IsSmallScreenDevice then return end
	if not playerlistCoreGuiEnabled then return end

	isOpen = not isOpen

	if next(TempHideKeys) == nil then
		setVisible(isOpen)
	end
end

Playerlist.IsOpen = function()
	return isOpen
end

Playerlist.HideTemp = function(self, key, hidden)
	if not playerlistCoreGuiEnabled then return end
	if IsSmallScreenDevice then return end
	
	TempHideKeys[key] = hidden and true or nil

	if next(TempHideKeys) == nil then
		if isOpen then
			setVisible(true, true)
		end
	else
		if isOpen then
			setVisible(false, true)
		end
	end
end
local topStat = nil
if isTenFootInterface then
	topStat = TenFootInterface:SetupTopStat()
end

--[[ Core Gui Changed events ]]--
-- NOTE: Core script only
local function onCoreGuiChanged(coreGuiType, enabled)
	if coreGuiType == Enum.CoreGuiType.All or coreGuiType == Enum.CoreGuiType.PlayerList then
		playerlistCoreGuiEnabled = enabled and topbarEnabled

		-- not visible on small screen devices
		if IsSmallScreenDevice then
			Container.Visible = false
			return
		end
		
		setVisible(playerlistCoreGuiEnabled and isOpen and next(TempHideKeys) == nil, true)
		
		if isTenFootInterface and topStat then
			topStat:SetTopStatEnabled(playerlistCoreGuiEnabled)
		end
		
		if playerlistCoreGuiEnabled then
			ContextActionService:BindCoreAction("RbxPlayerListToggle", Playerlist.ToggleVisibility, false, Enum.KeyCode.Tab)
		else
			ContextActionService:UnbindCoreAction("RbxPlayerListToggle")
		end
	end
end

Playerlist.TopbarEnabledChanged = function(enabled)
	topbarEnabled = enabled
	-- Update coregui to reflect new topbar status
	onCoreGuiChanged(Enum.CoreGuiType.PlayerList, StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList))
end

onCoreGuiChanged(Enum.CoreGuiType.PlayerList, StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList))
StarterGui.CoreGuiChangedSignal:connect(onCoreGuiChanged)

resizePlayerList()

if GuiService then
	if isTenFootInterface then
		GuiService:AddSelectionTuple("PlayerListSelection", ScrollList)
	else
		GuiService:AddSelectionParent("PlayerListSelection", Container)
	end
end

local blockStatusChanged = function(userId, isBlocked)
	if userId < 0 then return end

	for _,playerEntry in ipairs(PlayerEntries) do
		if playerEntry.Player.UserId == userId then
			playerEntry.Frame.BGFrame.MembershipIcon.Image = getMembershipIcon(playerEntry.Player)
			return
		end
	end
end

blockingUtility:GetBlockedStatusChangedEvent():connect(blockStatusChanged)

return Playerlist
