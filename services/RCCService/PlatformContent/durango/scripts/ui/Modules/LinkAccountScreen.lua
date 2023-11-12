--[[
				// LinkAccountScreen.lua
]]
local CoreGui = Game:GetService("CoreGui")
local GuiRoot = CoreGui:FindFirstChild("RobloxGui")
local Modules = GuiRoot:FindFirstChild("Modules")

local ContextActionService = game:GetService('ContextActionService')
local GuiService = game:GetService('GuiService')

local AccountManager = require(Modules:FindFirstChild('AccountManager'))
local AssetManager = require(Modules:FindFirstChild('AssetManager'))
local BaseSignInScreen = require(Modules:FindFirstChild('BaseSignInScreen'))
local Errors = require(Modules:FindFirstChild('Errors'))
local ErrorOverlay = require(Modules:FindFirstChild('ErrorOverlay'))
local EventHub = require(Modules:FindFirstChild('EventHub'))
local GlobalSettings = require(Modules:FindFirstChild('GlobalSettings'))
local LoadingWidget = require(Modules:FindFirstChild('LoadingWidget'))
local ScreenManager = require(Modules:FindFirstChild('ScreenManager'))
local SoundManager = require(Modules:FindFirstChild('SoundManager'))
local Strings = require(Modules:FindFirstChild('LocalizedStrings'))
local TextBox = require(Modules:FindFirstChild('TextBox'))
local Utility = require(Modules:FindFirstChild('Utility'))

local function createLinkAccountScreen()
	local this = BaseSignInScreen()

	this:SetTitle(string.upper(Strings:LocalizedString("LinkAccountTitle")))
	this:SetDescriptionText(Strings:LocalizedString("LinkAccountPhrase"))

	local ModalOverlay = Utility.Create'Frame'
	{
		Name = "ModalOverlay";
		Size = UDim2.new(1, 0, 1, 0);
		BackgroundTransparency = GlobalSettings.ModalBackgroundTransparency;
		BackgroundColor3 = GlobalSettings.ModalBackgroundColor;
		BorderSizePixel = 0;
		ZIndex = 4;
	}

	local myUsername = nil
	local myPassword = nil

	this.UsernameObject:SetDefaultText(Strings:LocalizedString("UsernameWord"))
	this.UsernameObject:SetKeyboardTitle(Strings:LocalizedString("UsernameWord"))
	local usernameChangedCn = nil

	this.PasswordObject:SetDefaultText(Strings:LocalizedString("PasswordWord"))
	this.PasswordObject:SetKeyboardTitle(Strings:LocalizedString("PasswordWord"))
	this.PasswordObject:SetKeyboardType(Enum.XboxKeyBoardType.Password)
	local passwordChangedCn = nil

	local function linkAccountAsync()
		local linkResult = nil
		local signInResult = nil
		local loader = LoadingWidget(
			{ Parent = this.Container }, {
			-- try link account
			function()
				linkResult = AccountManager:LinkAccountAsync(myUsername, myPassword)

				-- sign in here on success
				if linkResult == AccountManager.AuthResults.Success then
					signInResult = AccountManager:SignInAsync(Enum.UserInputType.Gamepad1)
				end
			end
		})

		-- set up full screen loader
		ModalOverlay.Parent = GuiRoot
		ContextActionService:BindCoreAction("BlockB", function() end, false, Enum.KeyCode.ButtonB)
		local selectedObject = GuiService.SelectedCoreObject
		GuiService.SelectedCoreObject = nil

		-- call loader
		loader:AwaitFinished()

		-- clean up
		loader:Cleanup()
		loader = nil
		GuiService.SelectedCoreObject = selectedObject
		ContextActionService:UnbindCoreAction("BlockB")
		ModalOverlay.Parent = nil

		if linkResult ~= AccountManager.AuthResults.Success then
			local err = linkResult and Errors.Authentication[linkResult] or Errors.Default
			ScreenManager:OpenScreen(ErrorOverlay(err), false)
		else
			if signInResult == AccountManager.AuthResults.Success then
				ScreenManager:CloseCurrent()
				EventHub:dispatchEvent(EventHub.Notifications["AuthenticationSuccess"])
			else
				local err = signInResult and Errors.Authentication[signInResult] or Errors.Default
				ScreenManager:OpenScreen(ErrorOverlay(err), false)
			end
		end
	end

	local isSigningIn = false
	this.SignInButton.MouseButton1Click:connect(function()
		if isSigningIn then return end
		isSigningIn = true
		SoundManager:Play('ButtonPress')
		if (myUsername and #myUsername > 0) and (myPassword and #myPassword > 0) then
			linkAccountAsync()
		else
			local err = Errors.SignIn.NoUsernameOrPasswordEntered
			ScreenManager:OpenScreen(ErrorOverlay(err), false)
		end
		isSigningIn = false
	end)

	--[[ Public API ]]--
	--override
	local baseFocus = this.Focus
	function this:Focus()
		baseFocus(self)
		usernameChangedCn = this.UsernameObject.OnTextChanged:connect(function(text)
			myUsername = text
			if #myUsername > 0 then
				GuiService.SelectedCoreObject = this.PasswordSelection
			else
				GuiService.SelectedCoreObject = this.UsernameSelection
			end
		end)
		passwordChangedCn = this.PasswordObject.OnTextChanged:connect(function(text)
			myPassword = text
			if #myPassword > 0 then
				GuiService.SelectedCoreObject = this.SignInButton
			else
				GuiService.SelectedCoreObject = this.PasswordSelection
			end
		end)
	end

	--override
	local baseRemoveFocus = this.RemoveFocus
	function this:RemoveFocus()
		baseRemoveFocus(self)
		Utility.DisconnectEvent(usernameChangedCn)
		Utility.DisconnectEvent(passwordChangedCn)
	end

	return this
end

return createLinkAccountScreen
