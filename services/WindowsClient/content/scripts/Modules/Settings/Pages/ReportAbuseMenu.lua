--[[
		Filename: ReportAbuseMenu.lua
		Written by: jeditkacheff
		Version 1.0
		Description: Takes care of the report abuse page in Settings Menu
--]]

-------------- SERVICES --------------
local CoreGui = game:GetService("CoreGui")
local RobloxGui = CoreGui:WaitForChild("RobloxGui")
local GuiService = game:GetService("GuiService")
local PlayersService = game:GetService("Players")

----------- UTILITIES --------------
local utility = require(RobloxGui.Modules.Settings.Utility)

------------ CONSTANTS -------------------
local ABUSE_TYPES_PLAYER = {
	"Swearing",
	"Inappropriate Username",
	"Bullying",
	"Scamming",
	"Dating",
	"Cheating/Exploiting",
	"Personal Question",
	"Offsite Links",
}

local ABUSE_TYPES_GAME = {
	"Inappropriate Content",
	"Bad Model or Script",
	"Offsite Link",
}
local DEFAULT_ABUSE_DESC_TEXT = "   Short Description (Optional)"
if utility:IsSmallTouchScreen() then
	DEFAULT_ABUSE_DESC_TEXT = "   (Optional)"
end

------------ VARIABLES -------------------
local PageInstance = nil

----------- CLASS DECLARATION --------------
local function Initialize()
	local settingsPageFactory = require(RobloxGui.Modules.Settings.SettingsPageFactory)
	local this = settingsPageFactory:CreateNewPage()

	local playerNames = {}
	local nameToRbxPlayer = {}

	function this:GetPlayerFromIndex(index)
		local playerName = playerNames[index]
		if playerName then
			return nameToRbxPlayer[nameToRbxPlayer]
		end

		return nil
	end

	function this:UpdatePlayerDropDown()
		playerNames = {}
	    	nameToRbxPlayer = {}

		local players = PlayersService:GetPlayers()
		local index = 1
		for i = 1, #players do
			local player = players[i]
			if player ~= PlayersService.LocalPlayer and player.UserId > 0 then
				playerNames[index] = player.Name
				nameToRbxPlayer[player.Name] = player
				index = index + 1
			end
		end

		this.WhichPlayerMode:UpdateDropDownList(playerNames)
		
		if index == 1 then
			this.GameOrPlayerMode:SetSelectionIndex(1)
			this.TypeOfAbuseMode:UpdateDropDownList(ABUSE_TYPES_GAME)
		end

		this.WhichPlayerMode:SetInteractable(index > 1 and this.GameOrPlayerMode.CurrentIndex ~= 1)
		this.GameOrPlayerMode:SetInteractable(index > 1)
	end

	------ TAB CUSTOMIZATION -------
	this.TabHeader.Name = "ReportAbuseTab"

	this.TabHeader.Icon.Image = "rbxasset://textures/ui/Settings/MenuBarIcons/ReportAbuseTab.png"
	if utility:IsSmallTouchScreen() then
		this.TabHeader.Icon.Size = UDim2.new(0,27,0,32)
		this.TabHeader.Size = UDim2.new(0,120,1,0)
	else
		this.TabHeader.Size = UDim2.new(0,150,1,0)
		this.TabHeader.Icon.Size = UDim2.new(0,36,0,43)
	end
	this.TabHeader.Icon.Position = UDim2.new(this.TabHeader.Icon.Position.X.Scale, this.TabHeader.Icon.Position.X.Offset + 10, 0.5,-this.TabHeader.Icon.Size.Y.Offset/2)

	this.TabHeader.Icon.Title.Text = "Report"

	------ PAGE CUSTOMIZATION -------
	this.Page.Name = "ReportAbusePage"

	-- need to override this function from SettingsPageFactory
	-- DropDown menus require hub to to be set when they are initialized
	function this:SetHub(newHubRef)
		this.HubRef = newHubRef

		if utility:IsSmallTouchScreen() then
			this.GameOrPlayerFrame, 
			this.GameOrPlayerLabel,
			this.GameOrPlayerMode = utility:AddNewRow(this, "Game or Player?", "Selector", {"Game", "Player"}, 1)
		else
			this.GameOrPlayerFrame, 
			this.GameOrPlayerLabel,
			this.GameOrPlayerMode = utility:AddNewRow(this, "Game or Player?", "Selector", {"Game", "Player"}, 1, 3)
		end

		this.WhichPlayerFrame, 
		this.WhichPlayerLabel,
		this.WhichPlayerMode = utility:AddNewRow(this, "Which Player?", "DropDown", {"update me"})
		this.WhichPlayerMode:SetInteractable(false)
		this.WhichPlayerLabel.ZIndex = 1

		this.TypeOfAbuseFrame, 
		this.TypeOfAbuseLabel,
		this.TypeOfAbuseMode = utility:AddNewRow(this, "Type Of Abuse", "DropDown", ABUSE_TYPES_GAME)

		if utility:IsSmallTouchScreen() then
			this.AbuseDescriptionFrame, 
			this.AbuseDescriptionLabel,
			this.AbuseDescription = utility:AddNewRow(this, DEFAULT_ABUSE_DESC_TEXT, "TextBox", nil, nil)
		else
			this.AbuseDescriptionFrame, 
			this.AbuseDescriptionLabel,
			this.AbuseDescription = utility:AddNewRow(this, DEFAULT_ABUSE_DESC_TEXT, "TextBox", nil, nil, 5)
		end
		
		if utility:IsSmallTouchScreen() then
			this.AbuseDescription.Selection.Size = UDim2.new(0, 290, 0, 30)
			this.AbuseDescription.Selection.Position = UDim2.new(1,-345,this.AbuseDescription.Selection.Position.Y.Scale, this.AbuseDescription.Selection.Position.Y.Offset)

			this.AbuseDescriptionLabel = this.TypeOfAbuseLabel:clone()
			this.AbuseDescriptionLabel.Text = "Abuse Description"
			this.AbuseDescriptionLabel.Position = UDim2.new(this.AbuseDescriptionLabel.Position.X.Scale, this.AbuseDescriptionLabel.Position.X.Offset,
														0,50)
			this.AbuseDescriptionLabel.Parent = this.Page
		end

		local SelectionOverrideObject = utility:Create'ImageLabel'
		{
			Image = "",
			BackgroundTransparency = 1
		};

		local submitButton, submitText = nil, nil

		local function makeSubmitButtonActive()
			submitButton.ZIndex = 2
			submitButton.Selectable = true
			submitText.ZIndex = 2
		end

		local function makeSubmitButtonInactive()
			submitButton.ZIndex = 1
			submitButton.Selectable = false
			submitText.ZIndex = 1
		end

		local function updateAbuseDropDown()
			this.WhichPlayerMode:ResetSelectionIndex()
			this.TypeOfAbuseMode:ResetSelectionIndex()

			if this.GameOrPlayerMode.CurrentIndex == 1 then
				this.TypeOfAbuseMode:UpdateDropDownList(ABUSE_TYPES_GAME)
				this.WhichPlayerMode:SetInteractable(false)
				this.WhichPlayerLabel.ZIndex = 1
				this.GameOrPlayerMode.SelectorFrame.NextSelectionDown = this.TypeOfAbuseMode.DropDownFrame
			else
				this.TypeOfAbuseMode:UpdateDropDownList(ABUSE_TYPES_PLAYER)
				this.WhichPlayerMode:SetInteractable(true)
				this.WhichPlayerLabel.ZIndex = 2
				this.GameOrPlayerMode.SelectorFrame.NextSelectionDown = this.WhichPlayerMode.DropDownFrame
			end
			makeSubmitButtonInactive()
		end

		local function cleanupReportAbuseMenu()
			updateAbuseDropDown()
			this.AbuseDescription.Selection.Text = DEFAULT_ABUSE_DESC_TEXT
			this.HubRef:SetVisibility(false, true)
		end

		local function onReportSubmitted()
			local abuseReason = nil
			if this.GameOrPlayerMode.CurrentIndex == 2 then
				abuseReason = ABUSE_TYPES_PLAYER[this.TypeOfAbuseMode.CurrentIndex]

				local currentAbusingPlayer = this:GetPlayerFromIndex(this.WhichPlayerMode.CurrentIndex)
				if currentAbusingPlayer and abuseReason then
					spawn(function()
						game.Players:ReportAbuse(currentAbusingPlayer, abuseReason, this.AbuseDescription.Selection.Text)
					end)
				end
			else
				abuseReason = ABUSE_TYPES_GAME[this.TypeOfAbuseMode.CurrentIndex]
				if abuseReason then
					spawn(function()
						game.Players:ReportAbuse(nil, abuseReason, this.AbuseDescription.Selection.Text)
					end)
				end
			end

			if abuseReason then
				local alertText = "Thanks for your report! Our moderators will review the chat logs and evaluate what happened."

				if abuseReason == 'Cheating/Exploiting' then
					alertText = "Thanks for your report! We've recorded your report for evaluation."
				elseif abuseReason == 'Inappropriate Username' then
					alertText = "Thanks for your report! Our moderators will evaluate the username."
				elseif abuseReason == "Bad Model or Script" or  abuseReason == "Inappropriate Content" or abuseReason == "Offsite Link" or abuseReason == "Offsite Links" then
					alertText = "Thanks for your report! Our moderators will review the place and make a determination."
				end

				utility:ShowAlert(alertText, "Ok", this.HubRef, cleanupReportAbuseMenu)

				this.LastSelectedObject = nil
			end
		end

		submitButton, submitText = utility:MakeStyledButton("SubmitButton", "Submit", UDim2.new(0,198,0,50), onReportSubmitted, this)
		if utility:IsSmallTouchScreen() then
			submitButton.Position = UDim2.new(1,-220,1,5)
		else
			submitButton.Position = UDim2.new(1,-194,1,5)
		end
		submitButton.Selectable = false
		submitButton.ZIndex = 1
		submitText.ZIndex = 1
		submitButton.Parent = this.AbuseDescription.Selection

		local function playerSelectionChanged(newIndex)
			if newIndex ~= nil and this.TypeOfAbuseMode:GetSelectedIndex() ~= nil then
				makeSubmitButtonActive()
			else
				makeSubmitButtonInactive()
			end
		end
		this.WhichPlayerMode.IndexChanged:connect(playerSelectionChanged)

		local function typeOfAbuseChanged(newIndex)
			if newIndex ~= nil then
				if this.GameOrPlayerMode.CurrentIndex == 1 or this.WhichPlayerMode:GetSelectedIndex() ~= nil then
					makeSubmitButtonActive()
				else
					makeSubmitButtonInactive()
				end
			else
				makeSubmitButtonInactive()
			end
		end
		this.TypeOfAbuseMode.IndexChanged:connect(typeOfAbuseChanged)

		this.GameOrPlayerMode.IndexChanged:connect(updateAbuseDropDown)

		this:AddRow(nil, nil, this.AbuseDescription)

		this.Page.Size = UDim2.new(1,0,0,submitButton.AbsolutePosition.Y + submitButton.AbsoluteSize.Y)
	end

	return this
end


----------- Public Facing API Additions --------------
do
	PageInstance = Initialize()

	PageInstance.Displayed.Event:connect(function()
		PageInstance:UpdatePlayerDropDown()
	end)
end


return PageInstance
