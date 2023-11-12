--[[
		Filename: SettingsPageFactory.lua
		Written by: jeditkacheff
		Version 1.0
		Description: Base Page Functionality for all Settings Pages
--]]
----------------- SERVICES ------------------------------
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local CoreGui = game:GetService("CoreGui")
local RobloxGui = CoreGui:WaitForChild("RobloxGui")

----------- UTILITIES --------------
local utility = require(RobloxGui.Modules.Settings.Utility)


----------- VARIABLES --------------
RobloxGui:WaitForChild("Modules"):WaitForChild("TenFootInterface")
local isTenFootInterface = require(RobloxGui.Modules.TenFootInterface):IsEnabled()

----------- CONSTANTS --------------
local HEADER_SPACING = 5
if utility:IsSmallTouchScreen() then
	HEADER_SPACING = 0
end

----------- CLASS DECLARATION --------------
local function Initialize()
	local this = {}
	this.HubRef = nil
	this.LastSelectedObject = nil
	this.TabPosition = 0
	this.Active = false
	this.OpenStateChangedCount = 0
	local rows = {}
	local displayed = false

	------ TAB CREATION -------
	this.TabHeader = utility:Create'TextButton'
	{
		Name = "Header",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(0,169,1,0),
		Position = UDim2.new(0.5,0,0,0)
	};
	if utility:IsSmallTouchScreen() then
		this.TabHeader.Size = UDim2.new(0,84,1,0)
	elseif isTenFootInterface then
		this.TabHeader.Size = UDim2.new(0,220,1,0)
	end
	this.TabHeader.MouseButton1Click:connect(function()
		if this.HubRef then
			this.HubRef:SwitchToPage(this, true)
		end
	end)

	local icon = utility:Create'ImageLabel'
	{
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.new(0,44,0,37),
		Position = UDim2.new(0,10,0.5,-18),
		Image = "",
		ImageTransparency = 0.5,
		Parent = this.TabHeader
	};

	local title = utility:Create'TextLabel'
	{
		Name = "Title",
		Text = "Change Me",
		Font = Enum.Font.SourceSansBold,
		FontSize = Enum.FontSize.Size24,
		TextColor3 = Color3.new(1,1,1),
		BackgroundTransparency = 1,
		Size = UDim2.new(1.05,0,1,0),
		Position = UDim2.new(1.2,0,0,0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.5,
		Parent = icon
	};
	if utility:IsSmallTouchScreen() then
		title.FontSize = Enum.FontSize.Size18
	elseif isTenFootInterface then
		title.FontSize = Enum.FontSize.Size48
	end

	local tabSelection = utility:Create'ImageLabel'
	{
		Name = "TabSelection",
		Image = "rbxasset://textures/ui/Settings/MenuBarAssets/MenuSelection.png",
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(3,1,4,5),
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1,0,0,6),
		Position = UDim2.new(0,0,1,-6),
		Parent = this.TabHeader
	};

	------ PAGE CREATION -------
	this.Page = utility:Create'Frame'
	{
		Name = "Page",
		BackgroundTransparency = 1,
		Size = UDim2.new(1,0,1,0)
	};

	-- make sure each page has a unique selection group (for gamepad selection)
	GuiService:AddSelectionParent(HttpService:GenerateGUID(false), this.Page)

	----------------- Events ------------------------

	this.Displayed = Instance.new("BindableEvent")
	this.Displayed.Name = "Displayed"
	
	this.Displayed.Event:connect(function()
		if not this.HubRef.Shield.Visible then return end

		this:SelectARow()
	end)

	this.Hidden = Instance.new("BindableEvent")
	this.Hidden.Event:connect(function()
		if GuiService.SelectedCoreObject and GuiService.SelectedCoreObject:IsDescendantOf(this.Page) then
			GuiService.SelectedCoreObject = nil
		end
	end)
	this.Hidden.Name = "Hidden"

	----------------- FUNCTIONS ------------------------
	function this:SelectARow(forced) -- Selects the first row or the most recently selected row
		if forced or not GuiService.SelectedCoreObject or not GuiService.SelectedCoreObject:IsDescendantOf(this.Page) then
			if this.LastSelectedObject then
				GuiService.SelectedCoreObject = this.LastSelectedObject
			else
				if rows and #rows > 0 then
					local valueChangerFrame = nil

					if type(rows[1].ValueChanger) ~= "table" then
						valueChangerFrame = rows[1].ValueChanger
					else
						valueChangerFrame = rows[1].ValueChanger.SliderFrame and 
													rows[1].ValueChanger.SliderFrame or rows[1].ValueChanger.SelectorFrame
					end
					GuiService.SelectedCoreObject = valueChangerFrame
				end
			end
		end
	end

	function this:Display(pageParent, skipAnimation)
		this.OpenStateChangedCount = this.OpenStateChangedCount + 1

		if this.TabHeader then
			this.TabHeader.TabSelection.Visible = true
			this.TabHeader.Icon.ImageTransparency = 0
			this.TabHeader.Icon.Title.TextTransparency = 0
		end

		this.Page.Parent = pageParent
		this.Page.Visible = true

		local endPos = UDim2.new(0,0,0,0)
		local animationComplete = function()
			this.Page.Visible = true
			displayed = true
			this.Displayed:Fire()
		end
		if skipAnimation then
			this.Page.Position = endPos
			animationComplete()
		else
			this.Page:TweenPosition(endPos, Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.1, true, animationComplete)
		end
	end
	function this:Hide(direction, newPagePos, skipAnimation, delayBeforeHiding)
		this.OpenStateChangedCount = this.OpenStateChangedCount + 1

		if this.TabHeader then
			this.TabHeader.TabSelection.Visible = false
			this.TabHeader.Icon.ImageTransparency = 0.5
			this.TabHeader.Icon.Title.TextTransparency = 0.5
		end

		if this.Page.Parent then
			local endPos = UDim2.new(1 * direction,0,0,0)
			local animationComplete = function()
				this.Page.Visible = false
				this.Page.Position = UDim2.new(this.TabPosition - newPagePos,0,0,0)
				displayed = false
				this.Hidden:Fire()
			end

			local remove = function()
				if skipAnimation then
					this.Page.Position = endPos
					animationComplete()
				else
					this.Page:TweenPosition(endPos, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true, animationComplete)
				end
			end

			if delayBeforeHiding then
				local myOpenStateChangedCount = this.OpenStateChangedCount
				delay(delayBeforeHiding, function()
					if myOpenStateChangedCount == this.OpenStateChangedCount then
						remove()
					end
				end)
			else
				remove()
			end
		end
	end

	function this:GetDisplayed()
		return displayed
	end

	function this:GetVisibility()
		return this.Page.Parent
	end

	function this:GetTabHeader()
		return this.TabHeader
	end

	function this:SetHub(hubRef)
		this.HubRef = hubRef

		for i, row in next, rows do
			if type(row.ValueChanger) == 'table' then
				row.ValueChanger.HubRef = this.HubRef
			end
		end
	end

	function this:GetSize()
		return this.Page.AbsoluteSize
	end

	function this:AddRow(RowFrame, RowLabel, ValueChangerInstance, ExtraRowSpacing)
		rows[#rows + 1] = {SelectionFrame = RowFrame, Label = RowLabel, ValueChanger = ValueChangerInstance}

		local rowFrameYSize = 0
		if RowFrame then 
			rowFrameYSize = RowFrame.Size.Y.Offset
		end

		if ExtraRowSpacing then
			this.Page.Size = UDim2.new(1, 0, 0, this.Page.Size.Y.Offset + rowFrameYSize + ExtraRowSpacing)
		else
			this.Page.Size = UDim2.new(1, 0, 0, this.Page.Size.Y.Offset + rowFrameYSize)
		end

		if this.HubRef and type(ValueChangerInstance) == 'table' then
			ValueChangerInstance.HubRef = this.HubRef
		end
	end

	return this
end


-------- public facing API ----------------
local moduleApiTable = {}

function moduleApiTable:CreateNewPage()
	return Initialize()
end

return moduleApiTable