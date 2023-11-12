--[[
			// FileName: PlayerlistModule.lua
			// Version 1.0
			// Written by: jmargh
			// Description: Implements social features that need to be ran on the server

			// TODO
				We need to get module script working on the server. When we get that working
				This should be moved to a module, and http helper functions should be moved
				to a utility module.
]]
local HttpService = game:GetService('HttpService')
local HttpRbxApiService = game:GetService('HttpRbxApiService')
local Players = game:GetService('Players')
local RobloxReplicatedStorage = game:GetService('RobloxReplicatedStorage')
local RunService = game:GetService('RunService')

local GET_MULTI_FOLLOW = "user/multi-following-exists"

local PlayerToRelationshipMap = {}

--[[ Remotes ]]--
local RemoteEvent_FollowRelationshipChanged = Instance.new('RemoteEvent')
RemoteEvent_FollowRelationshipChanged.Name = "FollowRelationshipChanged"
RemoteEvent_FollowRelationshipChanged.Parent = RobloxReplicatedStorage

local RemoteEvent_NewFollower = Instance.new("RemoteEvent")
RemoteEvent_NewFollower.Name = "NewFollower"
RemoteEvent_NewFollower.Parent = RobloxReplicatedStorage

local RemoteFunc_GetFollowRelationships = Instance.new('RemoteFunction')
RemoteFunc_GetFollowRelationships.Name = "GetFollowRelationships"
RemoteFunc_GetFollowRelationships.Parent = RobloxReplicatedStorage

--[[ Helper Functions ]]--
local function decodeJSON(json)
	local success, result = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not success then
		print("decodeJSON() failed because", result, "Input:", json)
		return nil
	end

	return result
end

local function rbxApiPostAsync(path, params, useHttps, throttlePriority, contentType)
	local success, result = pcall(function()
		return HttpRbxApiService:PostAsync(path, params, useHttps, throttlePriority, contentType)
	end)
	--
	if not success then
		local label = string.format("%s: - path: %s, \njson: %s", tostring(result), tostring(path), tostring(params))
		return nil
	end

	return decodeJSON(result)
end

--[[
	// Return - table
		Key: FollowingDetails
			Value: Arrary of details
				Key: UserId1
					Value: number - userId of new client
				Key: UserId2
					Value: number - userId of other client
				Key: User1FollowsUser2
					Value: boolean
				Key: User2FollowsUser1
					Value: boolean
]]
local function getFollowRelationshipsAsync(uid)
	if RunService:IsStudio() then
		return
	end

	local otherUserIdTable = {}
	for _,player in pairs(Players:GetPlayers()) do
		if player.UserId > 0 then
			table.insert(otherUserIdTable, player.UserId)
		end
	end

	if #otherUserIdTable > 0 and uid and uid > 0 then
		local jsonPostBody = {
			userId = uid;
			otherUserIds = otherUserIdTable;
		}
		jsonPostBody = HttpService:JSONEncode(jsonPostBody)
		
		if jsonPostBody then
			return rbxApiPostAsync(GET_MULTI_FOLLOW, jsonPostBody, true, Enum.ThrottlingPriority.Default, Enum.HttpContentType.ApplicationJson)
		end
	end
end

local function createRelationshipObject(user1FollowsUser2, user2FollowsUser1)
	local object = {}
	object.IsFollower = user2FollowsUser1
	object.IsFollowing = user1FollowsUser2
	object.IsMutual = user1FollowsUser2 and user2FollowsUser1

	return object
end

local function updateAndNotifyClients(resultTable, newUserIdStr, newPlayer)
	local followingDetails = resultTable["FollowingDetails"]
	if followingDetails then
		local relationshipTable = PlayerToRelationshipMap[newUserIdStr] or {}

		for i = 1, #followingDetails do
			local detail = followingDetails[i]
			local otherUserId = detail["UserId2"]
			local otherUserIdStr = tostring(otherUserId)

			local followsOther = detail["User1FollowsUser2"]
			local followsNewPlayer = detail["User2FollowsUser1"]

			relationshipTable[otherUserIdStr] = createRelationshipObject(followsOther, followsNewPlayer)

			-- update other use
			local otherRelationshipTable = PlayerToRelationshipMap[otherUserIdStr]
			if otherRelationshipTable then
				local newRelationship = createRelationshipObject(followsNewPlayer, followsOther)
				otherRelationshipTable[newUserIdStr] = newRelationship

				local otherPlayer = Players:GetPlayerByUserId(otherUserId)
				if otherPlayer then
					-- create single entry table (keep format same) and send to other client
					local deltaTable = {}
					deltaTable[newUserIdStr] = newRelationship
					RemoteEvent_FollowRelationshipChanged:FireClient(otherPlayer, deltaTable)
				end
			end
		end

		PlayerToRelationshipMap[newUserIdStr] = relationshipTable
		RemoteEvent_FollowRelationshipChanged:FireClient(newPlayer, relationshipTable)
	end
end

--[[ Connections ]]--
function RemoteFunc_GetFollowRelationships.OnServerInvoke(player)
	local uid = player.userId
	local uidStr = tostring(player.userId)
	if uid and uid > 0 and PlayerToRelationshipMap[uidStr] then
		return PlayerToRelationshipMap[uidStr]
	else
		return {}
	end
end

-- client fires event to server on new follow
RemoteEvent_NewFollower.OnServerEvent:connect(function(player1, player2, player1FollowsPlayer2)
	if player1FollowsPlayer2 == nil then
		return
	end
	local userId1 = tostring(player1.userId)
	local userId2 = tostring(player2.userId)

	local user1map = PlayerToRelationshipMap[userId1]
	local user2map = PlayerToRelationshipMap[userId2]

	if user1map then
		local relationTable = user1map[userId2]
		if relationTable then
			relationTable.IsFollowing = player1FollowsPlayer2
			relationTable.IsMutual = relationTable.IsFollowing and relationTable.IsFollower

			local delta = {}
			delta[userId2] = relationTable
			RemoteEvent_FollowRelationshipChanged:FireClient(player1, delta)
			-- this should be updated, but current NotificationScript listens to this
			if player1FollowsPlayer2 then
				RemoteEvent_NewFollower:FireClient(player2, player1)
			end
		end
	end

	if user2map then
		local relationTable = user2map[userId1] 
		if relationTable then
			relationTable.IsFollower = player1FollowsPlayer2
			relationTable.IsMutual = relationTable.IsFollowing and relationTable.IsFollower

			local delta = {}
			delta[userId1] = relationTable
			RemoteEvent_FollowRelationshipChanged:FireClient(player2, delta)
		end
	end
end)

local function onPlayerAdded(newPlayer)
	local uid = newPlayer.UserId
	if uid > 0 then
		local uidStr = tostring(uid)
		local result = getFollowRelationshipsAsync(uid)
		if result then
			updateAndNotifyClients(result, uidStr, newPlayer)
		end
	end
end

Players.PlayerAdded:connect(onPlayerAdded)
for _,player in pairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:connect(function(prevPlayer)
	local uid = tostring(prevPlayer.UserId)
	if PlayerToRelationshipMap[uid] then
		PlayerToRelationshipMap[uid] = nil
	end
end)
