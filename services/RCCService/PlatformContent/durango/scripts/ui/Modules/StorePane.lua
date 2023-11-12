--[[
			// StorePane.lua by Kip Turner
]]
local CoreGui = game:GetService("CoreGui")
local GuiRoot = CoreGui:FindFirstChild("RobloxGui")
local Modules = GuiRoot:FindFirstChild("Modules")

local Utility = require(Modules:FindFirstChild('Utility'))
local GlobalSettings = require(Modules:FindFirstChild('GlobalSettings'))
local ScrollingGridModule = require(Modules:FindFirstChild('ScrollingGrid'))
local UserDataModule = require(Modules:FindFirstChild('UserData'))
local ScreenManager = require(Modules:FindFirstChild('ScreenManager'))
local Strings = require(Modules:FindFirstChild('LocalizedStrings'))
local AssetManager = require(Modules:FindFirstChild('AssetManager'))
local CreateConfirmPrompt = require(Modules:FindFirstChild('ConfirmPrompt'))
local LoadingWidget = require(Modules:FindFirstChild('LoadingWidget'))
local SoundManager = require(Modules:FindFirstChild('SoundManager'))
local PlatformCatalogData = require(Modules:FindFirstChild('PlatformCatalogData'))
local CurrencyWidgetModule = require(Modules:FindFirstChild('CurrencyWidget'))
local EventHub = require(Modules:FindFirstChild('EventHub'))

local RobuxBalanceOverlay = require(Modules:FindFirstChild('RobuxBalanceOverlay'))

local ErrorOverlayModule = require(Modules:FindFirstChild('ErrorOverlay'))
local Errors = require(Modules:FindFirstChild('Errors'))


local TextService = game:GetService('TextService')
local GuiService = game:GetService('GuiService')
local PlatformService;
pcall(function() PlatformService = game:GetService('PlatformService') end)

--[[ Constants ]]--
local GRID_ROWS = 2
local GRID_COLUMNS = 3
local GRID_SPACING = Vector2.new(20,20)
local GRID_SIZE = UDim2.new(0, 1620, 0, 610)
local GRID_CELL_SIZE = Vector2.new(520,285)
local GRID_POSITION = UDim2.new(0, 40, 0, 65)
local DESCRIPTION_SIZE = UDim2.new(1,0,0,50)
local PRICE_CORNER_OFFSET = Vector2.new(-15,-12)
local NO_ITEMS_MSG_POSITION = UDim2.new(0.1, 0, 0, 275)
local NO_ITEMS_MSG_SIZE = UDim2.new(0.8, 0, 0, 150)

local ROBUX_ASSETS =
{
	{
		Wide = 'Robux01.png';
		Square = 'RobuxSquare01.png';
	};
	{
		Wide = 'Robux02.png';
		Square = 'RobuxSquare02.png';
	};
	{
		Wide = 'Robux03.png';
		Square = 'RobuxSquare03.png';
	};
	{
		Wide = 'Robux04.png';
		Square = 'RobuxSquare04.png';
	};
	{
		Wide = 'Robux05.png';
		Square = 'RobuxSquare05.png';
	};
	{
		Wide = 'Robux06.png';
		Square = 'RobuxSquare06.png';
	};
}


local function createGridItem(productInfo)
	local this = {}

	local container = Utility.Create'ImageButton'
	{
		Name = "StoreItemContainer",
		BackgroundTransparency = 1,
		BackgroundColor3 = Color3.new(220/255, 220/255, 220/255),
		-- Image = '',
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = 2;
		AssetManager.CreateShadow(1);

		SoundManager:CreateSound('MoveSelection');
	}
		local priceText = Utility.Create'TextLabel'
		{
			Name = "PriceText",
			Size = UDim2.new(0, 0, 0, 0),
			Position = UDim2.new(1, -15, 1, -12),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = 'Bottom';
			TextColor3 = GlobalSettings.WhiteTextColor,
			Font = GlobalSettings.HeadingFont,
			FontSize = GlobalSettings.LargeFontSize,
			Text = '',
			ZIndex = 2;
			Parent = container,
		}
			local dollarSign = Utility.Create'TextLabel'
			{
				Name = "DollarSign",
				Size = UDim2.new(0, 0, 1, -15),
				Position = UDim2.new(0, 0, 0, 15),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextColor3 = GlobalSettings.WhiteTextColor,
				Font = GlobalSettings.BoldFont,
				FontSize = GlobalSettings.MediumFontSize,
				Text = Strings:LocalizedString('CurrencySymbol'),
				ZIndex = 2;
				Parent = priceText,
			}

		local robuxIcon = Utility.Create'ImageLabel'
		{
			Name = 'RobuxIcon';
			Position = UDim2.new(0,5,0,5);
			Size = UDim2.new(0,80,0,80);
			Image = 'rbxasset://textures/ui/Shell/Icons/ROBUXIcon@1080.png';
			BackgroundTransparency = 1;
			ZIndex = 2;
			Parent = container;
		};
			local robuxAmount = Utility.Create'TextLabel'
			{
				Name = 'RobuxAmount';
				Text = '';
				Size = UDim2.new(0,0,1,0);
				Position = UDim2.new(1,10,0,0);
				TextXAlignment = 'Left';
				TextColor3 = GlobalSettings.WhiteTextColor;
				Font = GlobalSettings.BoldFont;
				FontSize = GlobalSettings.LargeFontSize;
				BackgroundTransparency = 1;
				ZIndex = 2;
				Parent = robuxIcon;
			};
			local percentMoreText = Utility.Create'TextLabel'
			{
				Name = "PercentMoreText",
				Size = UDim2.new(0, 0, 0, 0),
				Position = UDim2.new(0, 5, 1, 10),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextColor3 = GlobalSettings.GreenTextColor,
				Font = GlobalSettings.BoldFont,
				FontSize = GlobalSettings.ButtonSize,
				-- Visible = false,
				Text = '',
				ZIndex = 2;
				Parent = robuxIcon,
			}


	local function UpdateInfo()
		local priceTextSize = TextService:GetTextSize(priceText.Text, Utility.ConvertFontSizeEnumToInt(priceText.FontSize), priceText.Font, Vector2.new())
		priceText.Size = UDim2.new(0, priceTextSize.x , 0, priceTextSize.y)
		priceText.Position = UDim2.new(1, PRICE_CORNER_OFFSET.x - priceTextSize.x, 1, PRICE_CORNER_OFFSET.y - priceTextSize.y)
	end

	UpdateInfo()

	function this:GetContainer()
		return container
	end

	function this:SetDollarPrice(value)
		priceText.Text = value
		UpdateInfo()
	end

	function this:SetRobuxValue(value)
		robuxAmount.Text = Utility.FormatNumberString(tostring(value))
	end

	function this:SetPercentMore(value)
		percentMoreText.Visible = value > 0
		percentMoreText.Text = string.format(Strings:LocalizedString('PercentMoreRobuxPhrase'), tostring(value))
	end

	function this:SetImage(image)
		container.Image = image
	end

	return this
end

local function CreateStorePane(parent)
	local this = {}

	local storeItemClickConns = {}

	local cachedBalance = nil
	local cachedTotalBalance = nil
	local inFocus = false

	local currencyWidget = nil

	local StorePaneContainer = Utility.Create'Frame'
	{
		Name = 'StorePane',
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}
		local StoreDescriptionText = Utility.Create'TextLabel'
		{
			Name = "StoreDescriptionText",
			Size = DESCRIPTION_SIZE,
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = GlobalSettings.WhiteTextColor,
			Font = GlobalSettings.LightFont,
			FontSize = GlobalSettings.TitleSize,
			TextWrapped = true,
			Visible = false;
			Text = Strings:LocalizedString('RobuxStoreDescription'),
			Parent = StorePaneContainer,
		}
		local StoreNoItemsText = Utility.Create'TextLabel'
		{
			Name = "StoreNoItemsText",
			Size = NO_ITEMS_MSG_SIZE,
			Position = NO_ITEMS_MSG_POSITION,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			FontSize = GlobalSettings.TitleSize,
			TextWrapped = true,

			TextColor3 = GlobalSettings.GreyTextColor;
			TextTransparency = GlobalSettings.FriendStatusTextTransparency;
			Font = GlobalSettings.BoldFont;

			Text = Strings:LocalizedString('RobuxStoreNoItemsPhrase'),
			Visible = false;
			Parent = StorePaneContainer,
		}

		local RobuxBalanceButton = Utility.Create'ImageButton'
		{
			Name = "RobuxBalanceButton";
			-- size will change based on text bounds of balance
			Size = UDim2.new(0, 436, 0, 75);
			Position = UDim2.new(0, 0, 1, -100);
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			BackgroundColor3 = GlobalSettings.GreySelectionColor;
			Selectable = false;
			Parent = StorePaneContainer;

			SoundManager:CreateSound('MoveSelection')
		};
		RobuxBalanceButton.SelectionGained:connect(function()
			RobuxBalanceButton.BackgroundTransparency = 0;
		end)
		RobuxBalanceButton.SelectionLost:connect(function()
			RobuxBalanceButton.BackgroundTransparency = 1;
		end)

			local RobuxHelpIcon = Utility.Create'ImageLabel'
			{
				Name = "RobuxHelpIcon";
				Size = UDim2.new(0, 42, 0, 42);
				Position = UDim2.new(0, 10, 0, 0);
				BackgroundTransparency = 1;
				Image = 'rbxasset://textures/ui/Shell/Icons/HelpIconSmall.png';
				Visible = false;
				Parent = RobuxBalanceButton;
			};
			Utility.CalculateAnchor(RobuxHelpIcon, UDim2.new(0, 10, 0.5, 4), Utility.Enum.Anchor.CenterLeft)

	local function setBalanceButtonSize(balanceObjectSize)
		local sizeX = 56 + RobuxHelpIcon.Size.X.Offset + (balanceObjectSize and balanceObjectSize.X or 0) + 10
		RobuxBalanceButton.Size = UDim2.new(0, sizeX, 0, 75)
	end


	local showBalanceHelp = true
	local showBalanceOverlayDebounce = false
	RobuxBalanceButton.MouseButton1Click:connect(function()
		if showBalanceOverlayDebounce then return end
		--
		showBalanceOverlayDebounce = true
		if showBalanceHelp then
			local robuxBalanceOverlay = RobuxBalanceOverlay(cachedBalance, cachedTotalBalance)
			ScreenManager:OpenScreen(robuxBalanceOverlay, false)
		end
		showBalanceOverlayDebounce = false
	end)

	local function setBalanceHelpOption(platformBalance)
		local totalBalance = UserDataModule.GetTotalUserBalanceAsync()
		if totalBalance then
			cachedTotalBalance = totalBalance
			showBalanceHelp = platformBalance ~= totalBalance
			RobuxHelpIcon.Visible = showBalanceHelp
			RobuxBalanceButton.Selectable = showBalanceHelp
		end
	end

	local function PopulateBalance()
		spawn(function()
			local platformBalance = currencyWidget and currencyWidget:GetRobuxAmountAsync() or UserDataModule.GetPlatformUserBalanceAsync()
			if platformBalance then
				cachedBalance = platformBalance
				setBalanceHelpOption(platformBalance)
				if currencyWidget then
					setBalanceButtonSize(currencyWidget:GetAbsoluteSize())
				end
			else
				print("Unable to update user's balance because web call failed.")
			end
		end)
	end


	local storeScrollingGrid = ScrollingGridModule()
	storeScrollingGrid:SetSize(GRID_SIZE)
	storeScrollingGrid:SetScrollDirection(storeScrollingGrid.Enum.ScrollDirection.Vertical)
	storeScrollingGrid:SetCellSize(GRID_CELL_SIZE)
	storeScrollingGrid:SetPosition(GRID_POSITION)
	storeScrollingGrid:SetRowColumnConstraint(GRID_COLUMNS)
	storeScrollingGrid:SetSpacing(GRID_SPACING)
	storeScrollingGrid:SetParent(StorePaneContainer)
	--

	local SuccessfullyLoadedCatalog = false
	local catalogLoading = false
	local function OnLoad()
		if catalogLoading or SuccessfullyLoadedCatalog then return end
		catalogLoading = true

		if PlatformService then
			local catalogInfo, success, errormsg;

			-- Hide these text labels while we are loading
			StoreDescriptionText.Visible = false
			StoreNoItemsText.Visible = false

			local loader = LoadingWidget({Parent = StorePaneContainer}, {function() catalogInfo, success, errormsg = PlatformCatalogData:GetCatalogInfoAsync() end})
			loader:AwaitFinished()
			loader:Cleanup()
			loader = nil
			ScreenManager:DefaultFadeIn(storeScrollingGrid:GetGuiObject())
			if inFocus and GuiService.SelectedCoreObject == nil then
				if storeScrollingGrid.GridItems[1] then
					GuiService.SelectedCoreObject = storeScrollingGrid.GridItems[1]
				end
			end

			if success and catalogInfo then
				while #storeItemClickConns > 0 do
					Utility.DisconnectEvent(table.remove(storeItemClickConns, 1))
				end

				table.sort(catalogInfo, function(a, b)
					local aPrice = PlatformCatalogData:ParseRobuxValue(a)
					local bPrice = PlatformCatalogData:ParseRobuxValue(b)
					if aPrice and bPrice then
						return aPrice < bPrice
					end
					return a < b
				end)

				local worstRatio = nil
				for _, productInfo in pairs(catalogInfo) do
					local ratio = PlatformCatalogData:CalculateRobuxRatio(productInfo)
					if Utility.IsFinite(ratio) and ratio ~= 0 then
						if worstRatio == nil or ratio < worstRatio then
							worstRatio = ratio
						end
					end
				end

				if #catalogInfo == 0 then
					StoreDescriptionText.Visible = false
					StoreNoItemsText.Visible = true
				elseif not SuccessfullyLoadedCatalog then
					SuccessfullyLoadedCatalog = true

					StoreDescriptionText.Visible = true
					StoreNoItemsText.Visible = false

					local i = 1
					for _, productInfo in pairs(catalogInfo) do
						local productImageData = ROBUX_ASSETS[math.min(i, #ROBUX_ASSETS)]
						local catalogItemImage = 'rbxasset://textures/ui/Shell/Images/Robux/' .. productImageData['Wide']
						local confirmItemImage = 'rbxasset://textures/ui/Shell/Images/Robux/' .. productImageData['Square']

						local debounce = false
						local function onClick()
							if debounce then return end
							debounce = true

							local confirmPrompt = CreateConfirmPrompt({ProductName = productInfo and productInfo.Name or 'Unknown'; Balance = cachedBalance; Cost = productInfo and productInfo.DisplayListPrice or "Unknown"; ProductImage = confirmItemImage; ProductImageSize = Vector2.new(484, 540); CurrencySymbol = '';},
								                                      {ShowRemainingBalance = false; ShowRobuxIcon = false; ConfirmWithPrice = true;})

							do
								local selectedObject = GuiService.SelectedCoreObject
								if selectedObject and selectedObject:IsDescendantOf(StorePaneContainer) then
									this.SavedSelection = selectedObject
								end
							end

							confirmPrompt:SetParent(GuiRoot)
							ScreenManager:OpenScreen(confirmPrompt)
							confirmPrompt:FadeInBackground()
							local function onConfirmFinished(result)
								if result == true then
									print("Do buy")
									local purchaseResult = nil
									if not UserSettings().GameSettings:InStudioMode() then
										local purchaseCallSuccess, purchaseErrorMsg = pcall(function()
											purchaseResult = PlatformService:BeginPlatformStorePurchase(productInfo.ProductId)
										end)
										if purchaseCallSuccess then
											-- 0 means we bought it
											-- print("purchaseResult" , purchaseResult)
											if purchaseResult == 0 then
												-- print("dispatchEvent RobuxCatalogPurchaseInitiated")
												EventHub:dispatchEvent(EventHub.Notifications["RobuxCatalogPurchaseInitiated"], purchaseResult);
											end
										else
											print("Purchase Robux failed with pcall status:" , purchaseCallSuccess , "and purchaseResult:" , purchaseResult , "because of:" , purchaseErrorMsg)
										end
									else
										spawn(function()
											ScreenManager:OpenScreen(ErrorOverlayModule(Errors.RobuxPurchase[1]), false)
										end)
									end
									PopulateBalance()
									print("Done with purchase; result was:" , purchaseResult)
								else
									print("Declined to buy")
								end
							end
							-- confirmPrompt:AddResultCallback(onConfirmFinished)
							local result = confirmPrompt:ResultAsync()
							onConfirmFinished(result)

							debounce = false
						end

						local extractedPrice = productInfo and productInfo.DisplayPrice and string.gsub(productInfo.DisplayPrice, "%$", "") or ""
						-- local extractedRobuxValue = productInfo and productInfo.Name and string.match(productInfo.Name, "[0-9,]+") or "1000"
						local thisRatio = PlatformCatalogData:CalculateRobuxRatio(productInfo)

						local item = createGridItem()
						item:SetDollarPrice(extractedPrice)
						item:SetRobuxValue(PlatformCatalogData:ParseRobuxValue(productInfo))
						if thisRatio and worstRatio then
							item:SetPercentMore(math.floor(((thisRatio / worstRatio) - 1) * 100))
						else
							item:SetPercentMore(0)
						end
						item:SetImage(catalogItemImage)
						storeScrollingGrid:AddItem(item:GetContainer())
						table.insert(storeItemClickConns, item:GetContainer().MouseButton1Click:connect(onClick))

						i = math.min(#ROBUX_ASSETS, i + 1)
					end
				end
			else
				StoreNoItemsText.Visible = true
				print("StorePane - BeginGetCatalogInfo failed because:" , errormsg)
			end
		end
		catalogLoading = false
	end

	if not SuccessfullyLoadedCatalog then
		spawn(OnLoad)
	end

	--[[ Public API ]]--
	function this:GetName()
		return Strings:LocalizedString('CatalogWord')
	end

	function this:IsFocused()
		return inFocus
	end


	local RobuxChangedConn = nil
	local robuxChangedEventCount = 0
	local robuxAmountChangedLoader = nil

	function this:Show()
		StorePaneContainer.Visible = true

		if not currencyWidget then
			currencyWidget = CurrencyWidgetModule({Parent = RobuxBalanceButton; Position = UDim2.new(0, RobuxHelpIcon.Position.X.Offset + RobuxHelpIcon.Size.X.Offset + 10, 0.5, -30);})
		else
			spawn(function()
				currencyWidget:RefreshRobuxAmountAsync()
			end)
		end
		setBalanceButtonSize(currencyWidget:GetAbsoluteSize())
		Utility.DisconnectEvent(RobuxChangedConn)
		RobuxChangedConn = currencyWidget.RobuxChanged:connect(function()
				PopulateBalance()
				currencyWidget:GetRobuxAmountAsync()
				setBalanceButtonSize(currencyWidget:GetAbsoluteSize())
				SoundManager:Play('PurchaseSuccess')
			end)
		PopulateBalance()

		self.TransitionTweens = ScreenManager:DefaultFadeIn(StorePaneContainer)
		ScreenManager:PlayDefaultOpenSound()

		if not SuccessfullyLoadedCatalog then
			spawn(OnLoad)
		end
	end

	function this:Hide()
		StorePaneContainer.Visible = false

		RobuxChangedConn = Utility.DisconnectEvent(RobuxChangedConn)

		ScreenManager:DefaultCancelFade(self.TransitionTweens)
		self.TransitionTweens = nil

		-- Let's not do this it creates weird race conditions
		-- if currencyWidget then
		-- 	currencyWidget:Destroy()
		-- 	currencyWidget = nil
		-- end
	end

	function this:Focus()
		-- TODO: What is the selection if the packages fail to load?
		inFocus = true
		if self.SavedSelection and self.SavedSelection:IsDescendantOf(StorePaneContainer) then
			GuiService.SelectedCoreObject = self.SavedSelection
		elseif storeScrollingGrid.GridItems[1] then
			GuiService.SelectedCoreObject = storeScrollingGrid.GridItems[1]
		end
		self.SavedSelection = nil
	end

	function this:RemoveFocus()
		inFocus = false
		local selectedObject = GuiService.SelectedCoreObject
		if selectedObject and selectedObject:IsDescendantOf(StorePaneContainer) then
			GuiService.SelectedCoreObject = nil
		end
	end

	function this:SetPosition(newPosition)
		StorePaneContainer.Position = newPosition
	end

	function this:SetParent(newParent)
		StorePaneContainer.Parent = newParent
	end

	function this:IsAncestorOf(object)
		return StorePaneContainer and StorePaneContainer:IsAncestorOf(object)
	end

	return this
end

return CreateStorePane
