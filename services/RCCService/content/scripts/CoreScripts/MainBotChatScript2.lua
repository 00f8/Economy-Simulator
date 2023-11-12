local PURPOSE_DATA = {
	[Enum.DialogPurpose.Quest] = {"rbxasset://textures/DialogQuest.png", Vector2.new(10, 34)},
	[Enum.DialogPurpose.Help] = {"rbxasset://textures/DialogHelp.png", Vector2.new(20, 35)},
	[Enum.DialogPurpose.Shop] = {"rbxasset://textures/ui/DialogShop.png", Vector2.new(22, 43)},
}
local TEXT_HEIGHT = 24 -- Pixel height of one row
local FONT_SIZE = Enum.FontSize.Size24
local BAR_THICKNESS = 6
local STYLE_PADDING = 17
local CHOICE_PADDING = 6 * 2 -- (Added to vertical height)
local PROMPT_SIZE = Vector2.new(80, 90)
local FRAME_WIDTH = 350

local WIDTH_BONUS = (STYLE_PADDING * 2) - BAR_THICKNESS
local XPOS_OFFSET = -(STYLE_PADDING - BAR_THICKNESS)

local contextActionService = game:GetService("ContextActionService")
local guiService = game:GetService("GuiService")
local YPOS_OFFSET = -math.floor(STYLE_PADDING / 2)
local usingGamepad = false

function setUsingGamepad(input, processed)
	if input.UserInputType == Enum.UserInputType.Gamepad1 or input.UserInputType == Enum.UserInputType.Gamepad2 or
		input.UserInputType == Enum.UserInputType.Gamepad3 or input.UserInputType == Enum.UserInputType.Gamepad4 then
		usingGamepad = true
	else
		usingGamepad = false
	end
end

game:GetService("UserInputService").InputBegan:connect(setUsingGamepad)
game:GetService("UserInputService").InputChanged:connect(setUsingGamepad)

function waitForProperty(instance, name)
	while not instance[name] do
		instance.Changed:wait()
	end
end

function waitForChild(instance, name)
	while not instance:FindFirstChild(name) do
		instance.ChildAdded:wait()
	end
end

local filteringEnabledFixFlagSuccess, filteringEnabledFixFlagValue = pcall(function() return settings():GetFFlag("FilteringEnabledDialogFix") end)
local filterEnabledFixActive = (filteringEnabledFixFlagSuccess and filteringEnabledFixFlagValue)

local goodbyeChoiceActiveFlagSuccess, goodbyeChoiceActiveFlagValue = pcall(function() return settings():GetFFlag("GoodbyeChoiceActiveProperty") end)
local goodbyeChoiceActiveFlag = (goodbyeChoiceActiveFlagSuccess and goodbyeChoiceActiveFlagValue)

local mainFrame
local choices = {}
local lastChoice
local choiceMap = {}
local currentConversationDialog
local currentConversationPartner
local currentAbortDialogScript

local coroutineMap = {}
local currentDialogTimeoutCoroutine = nil

local tooFarAwayMessage =           "You are too far away to chat!"
local tooFarAwaySize = 300
local characterWanderedOffMessage = "Chat ended because you walked away"
local characterWanderedOffSize = 350
local conversationTimedOut =        "Chat ended because you didn't reply"
local conversationTimedOutSize = 350

local RobloxReplicatedStorage = game:GetService('RobloxReplicatedStorage')
local setDialogInUseEvent = RobloxReplicatedStorage:WaitForChild("SetDialogInUse")

local player
local screenGui
local chatNotificationGui
local messageDialog
local timeoutScript
local reenableDialogScript
local dialogMap = {}
local dialogConnections = {}
local touchControlGui = nil

local gui = nil
waitForChild(game,"CoreGui")
waitForChild(game:GetService("CoreGui"),"RobloxGui")

game:GetService("CoreGui").RobloxGui:WaitForChild("Modules"):WaitForChild("TenFootInterface")
local isTenFootInterface = require(game:GetService("CoreGui").RobloxGui.Modules.TenFootInterface):IsEnabled()
local utility = require(game:GetService("CoreGui").RobloxGui.Modules.Settings.Utility)
local isSmallTouchScreen = utility:IsSmallTouchScreen()

if isTenFootInterface then
	FONT_SIZE = Enum.FontSize.Size36
	TEXT_HEIGHT = 36
	FRAME_WIDTH = 500
elseif isSmallTouchScreen then
	FONT_SIZE = Enum.FontSize.Size14
	TEXT_HEIGHT = 14
	FRAME_WIDTH = 250
end

if game:GetService("CoreGui").RobloxGui:FindFirstChild("ControlFrame") then
	gui = game:GetService("CoreGui").RobloxGui.ControlFrame
else
	gui = game:GetService("CoreGui").RobloxGui
end
local touchEnabled = game:GetService("UserInputService").TouchEnabled

function currentTone()
	if currentConversationDialog then
		return currentConversationDialog.Tone
	else
		return Enum.DialogTone.Neutral
	end
end


function createChatNotificationGui()
	chatNotificationGui = Instance.new("BillboardGui")
	chatNotificationGui.Name = "ChatNotificationGui"

	chatNotificationGui.ExtentsOffset = Vector3.new(0,1,0)
	chatNotificationGui.Size = UDim2.new(PROMPT_SIZE.X / 31.5, 0, PROMPT_SIZE.Y / 31.5, 0)
	chatNotificationGui.SizeOffset = Vector2.new(0,0)
	chatNotificationGui.StudsOffset = Vector3.new(0, 3.7, 0)
	chatNotificationGui.Enabled = true
	chatNotificationGui.RobloxLocked = true
	chatNotificationGui.Active = true

	local button = Instance.new("ImageButton")
	button.Name = "Background"
	button.Active = false
	button.BackgroundTransparency = 1
	button.Position = UDim2.new(0, 0, 0, 0)
	button.Size = UDim2.new(1, 0, 1, 0)
	button.Image = ""
	button.RobloxLocked = true
	button.Parent = chatNotificationGui

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Position = UDim2.new(0, 0, 0, 0)
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.Image = ""
	icon.BackgroundTransparency = 1
	icon.RobloxLocked = true
	icon.Parent = button
	
	local activationButton = Instance.new("ImageLabel")
	activationButton.Name = "ActivationButton"
	activationButton.Position = UDim2.new(-0.3, 0, -0.4, 0)
	activationButton.Size = UDim2.new(.8, 0, .8*(PROMPT_SIZE.X/PROMPT_SIZE.Y), 0)
	activationButton.Image = "rbxasset://textures/ui/Settings/Help/XButtonDark.png"
	activationButton.BackgroundTransparency = 1
	activationButton.Visible = false
	activationButton.RobloxLocked = true
	activationButton.Parent = button
end

function getChatColor(tone)
	if tone == Enum.DialogTone.Neutral then
		return Enum.ChatColor.Blue
	elseif tone == Enum.DialogTone.Friendly then
		return Enum.ChatColor.Green
	elseif tone == Enum.DialogTone.Enemy then
		return Enum.ChatColor.Red
	end
end

function styleChoices()
	for _, obj in pairs(choices) do
		obj.BackgroundTransparency = 1
	end
	lastChoice.BackgroundTransparency = 1
end

function styleMainFrame(tone)
	if tone == Enum.DialogTone.Neutral then
		mainFrame.Style = Enum.FrameStyle.ChatBlue
	elseif tone == Enum.DialogTone.Friendly then
		mainFrame.Style = Enum.FrameStyle.ChatGreen
	elseif tone == Enum.DialogTone.Enemy then
		mainFrame.Style = Enum.FrameStyle.ChatRed
	end

	styleChoices()
end
function setChatNotificationTone(gui, purpose, tone)
	if tone == Enum.DialogTone.Neutral then
		gui.Background.Image = "rbxasset://textures/ui/chatBubble_blue_notify_bkg.png"
	elseif tone == Enum.DialogTone.Friendly then
		gui.Background.Image = "rbxasset://textures/ui/chatBubble_green_notify_bkg.png"
	elseif tone == Enum.DialogTone.Enemy then
		gui.Background.Image = "rbxasset://textures/ui/chatBubble_red_notify_bkg.png"
	end

	local newIcon, size = unpack(PURPOSE_DATA[purpose])
	local relativeSize = size / PROMPT_SIZE
	gui.Background.Icon.Size = UDim2.new(relativeSize.X, 0, relativeSize.Y, 0)
	gui.Background.Icon.Position = UDim2.new(0.5 - (relativeSize.X / 2), 0, 0.4 - (relativeSize.Y / 2), 0)
	gui.Background.Icon.Image = newIcon
end

function createMessageDialog()
	messageDialog = Instance.new("Frame");
	messageDialog.Name = "DialogScriptMessage"
	messageDialog.Style = Enum.FrameStyle.Custom
	messageDialog.BackgroundTransparency = 0.5
	messageDialog.BackgroundColor3 = Color3.new(31/255, 31/255, 31/255)
	messageDialog.Visible = false

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Position = UDim2.new(0,0,0,-1)
	text.Size = UDim2.new(1,0,1,0)
	text.FontSize = Enum.FontSize.Size14
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1,1,1)
	text.RobloxLocked = true
	text.Parent = messageDialog
end

function showMessage(msg, size)
	messageDialog.Text.Text = msg
	messageDialog.Size = UDim2.new(0,size,0,40)
	messageDialog.Position = UDim2.new(0.5, -size/2, 0.5, -40)
	messageDialog.Visible = true
	wait(2)
	messageDialog.Visible = false
end

function variableDelay(str)
	local length = math.min(string.len(str), 100)
	wait(0.75 + ((length/75) * 1.5))
end

function resetColor(frame)
	frame.BackgroundTransparency = 1
end

function wanderDialog()
	mainFrame.Visible = false
	endDialog()
	showMessage(characterWanderedOffMessage, characterWanderedOffSize)
end

function timeoutDialog()
	mainFrame.Visible = false
	endDialog()
	showMessage(conversationTimedOut, conversationTimedOutSize)
end

function normalEndDialog()
	endDialog()
end

function endDialog()
	if filterEnabledFixActive then
		if currentDialogTimeoutCoroutine then
			coroutineMap[currentDialogTimeoutCoroutine] = false
			currentDialogTimeoutCoroutine = nil
		end
	else
		if currentAbortDialogScript then
			currentAbortDialogScript:Destroy()
			currentAbortDialogScript = nil
		end
	end

	local dialog = currentConversationDialog
	currentConversationDialog = nil
	if dialog and dialog.InUse then
		if filterEnabledFixActive then
			spawn(function()
				wait(5)
				setDialogInUseEvent:FireServer(dialog, false)
			end)
		else
			local reenableScript = reenableDialogScript:Clone()
			reenableScript.Archivable = false
			reenableScript.Disabled = false
			reenableScript.Parent = dialog
		end
	end

	for dialog, gui in pairs(dialogMap) do
		if dialog and gui then
			gui.Enabled = not dialog.InUse
		end
	end

	contextActionService:UnbindCoreAction("Nothing")
	currentConversationPartner = nil
	
	if touchControlGui then
		touchControlGui.Visible = true
	end
end

function sanitizeMessage(msg)
  if string.len(msg) == 0 then
     return "..."
  else
     return msg
  end
end

function selectChoice(choice)
	renewKillswitch(currentConversationDialog)

	--First hide the Gui
	mainFrame.Visible = false
	if choice == lastChoice then
		game:GetService("Chat"):Chat(game:GetService("Players").LocalPlayer.Character, lastChoice.UserPrompt.Text, getChatColor(currentTone()))

		normalEndDialog()
	else
		local dialogChoice = choiceMap[choice]

		game:GetService("Chat"):Chat(game:GetService("Players").LocalPlayer.Character, sanitizeMessage(dialogChoice.UserDialog), getChatColor(currentTone()))
		wait(1)
		currentConversationDialog:SignalDialogChoiceSelected(player, dialogChoice)
		game:GetService("Chat"):Chat(currentConversationPartner, sanitizeMessage(dialogChoice.ResponseDialog), getChatColor(currentTone()))

		variableDelay(dialogChoice.ResponseDialog)
		presentDialogChoices(currentConversationPartner, dialogChoice:GetChildren(), dialogChoice)
	end
end

function newChoice()
	local dummyFrame = Instance.new("Frame")
	dummyFrame.Visible = false

	local frame = Instance.new("TextButton")
	frame.BackgroundColor3 = Color3.new(227/255, 227/255, 227/255)
	frame.BackgroundTransparency = 1
	frame.AutoButtonColor = false
	frame.BorderSizePixel = 0
	frame.Text = ""
	frame.MouseEnter:connect(function() frame.BackgroundTransparency = 0 end)
	frame.MouseLeave:connect(function() frame.BackgroundTransparency = 1 end)
	frame.SelectionImageObject = dummyFrame
	frame.MouseButton1Click:connect(function() selectChoice(frame) end)
	frame.RobloxLocked = true

	local prompt = Instance.new("TextLabel")
	prompt.Name = "UserPrompt"
	prompt.BackgroundTransparency = 1
	prompt.Font = Enum.Font.SourceSans
	prompt.FontSize = FONT_SIZE
	prompt.Position = UDim2.new(0, 40, 0, 0)
	prompt.Size = UDim2.new(1, -32-40, 1, 0)
	prompt.TextXAlignment = Enum.TextXAlignment.Left
	prompt.TextYAlignment = Enum.TextYAlignment.Center
	prompt.TextWrap = true
	prompt.RobloxLocked = true
	prompt.Parent = frame

	local selectionButton = Instance.new("ImageLabel")
	selectionButton.Name = "RBXchatDialogSelectionButton"
	selectionButton.Position = UDim2.new(0, 0, 0.5, -33/2)
	selectionButton.Size = UDim2.new(0, 33, 0, 33)
	selectionButton.Image = "rbxasset://textures/ui/Settings/Help/AButtonLightSmall.png"
	selectionButton.BackgroundTransparency = 1
	selectionButton.Visible = false
	selectionButton.RobloxLocked = true
	selectionButton.Parent = frame
	
	return frame
end
function initialize(parent)
	choices[1] = newChoice()
	choices[2] = newChoice()
	choices[3] = newChoice()
	choices[4] = newChoice()

	lastChoice = newChoice()
	lastChoice.UserPrompt.Text = "Goodbye!"
	lastChoice.Size = UDim2.new(1, WIDTH_BONUS, 0, TEXT_HEIGHT + CHOICE_PADDING)

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "UserDialogArea"
	mainFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, 200)
	mainFrame.Style = Enum.FrameStyle.ChatBlue
	mainFrame.Visible = false

	for n, obj in pairs(choices) do
      obj.RobloxLocked = true
		obj.Parent = mainFrame
	end
	
	lastChoice.RobloxLocked = true
	lastChoice.Parent = mainFrame

	mainFrame.RobloxLocked = true
	mainFrame.Parent = parent
end

function presentDialogChoices(talkingPart, dialogChoices, parentDialog)
	if not currentConversationDialog then
		return
	end

	currentConversationPartner = talkingPart
	sortedDialogChoices = {}
	for n, obj in pairs(dialogChoices) do
		if obj:IsA("DialogChoice") then
			table.insert(sortedDialogChoices, obj)
		end
	end
	table.sort(sortedDialogChoices, function(a,b) return a.Name < b.Name end)

	if #sortedDialogChoices == 0 then
		normalEndDialog()
		return
	end

	local pos = 1
	local yPosition = 0
	choiceMap = {}
	for n, obj in pairs(choices) do
		obj.Visible = false
	end

	for n, obj in pairs(sortedDialogChoices) do
		if pos <= #choices then
			--3 lines is the maximum, set it to that temporarily
			choices[pos].Size = UDim2.new(1, WIDTH_BONUS, 0, TEXT_HEIGHT * 3)
			choices[pos].UserPrompt.Text = obj.UserDialog
			local height = (math.ceil(choices[pos].UserPrompt.TextBounds.Y / TEXT_HEIGHT) * TEXT_HEIGHT) + CHOICE_PADDING

			choices[pos].Position = UDim2.new(0, XPOS_OFFSET, 0, YPOS_OFFSET + yPosition)
			choices[pos].Size = UDim2.new(1, WIDTH_BONUS, 0, height)
			choices[pos].Visible = true

			choiceMap[choices[pos]] = obj

			yPosition = yPosition + height + 1 -- The +1 makes highlights not overlap
			pos = pos + 1
		end
	end

	lastChoice.Size = UDim2.new(1, WIDTH_BONUS, 0, TEXT_HEIGHT * 3)
	lastChoice.UserPrompt.Text = parentDialog.GoodbyeDialog == "" and "Goodbye!" or parentDialog.GoodbyeDialog
	local height = (math.ceil(lastChoice.UserPrompt.TextBounds.Y / TEXT_HEIGHT) * TEXT_HEIGHT) + CHOICE_PADDING
	lastChoice.Size = UDim2.new(1, WIDTH_BONUS, 0, height)
	lastChoice.Position = UDim2.new(0, XPOS_OFFSET, 0, YPOS_OFFSET + yPosition)
	lastChoice.Visible = true
	
	if goodbyeChoiceActiveFlag and not parentDialog.GoodbyeChoiceActive then
		lastChoice.Visible = false
		mainFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, yPosition + (STYLE_PADDING * 2) + (YPOS_OFFSET * 2))
	else
		mainFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, yPosition + lastChoice.AbsoluteSize.Y + (STYLE_PADDING * 2) + (YPOS_OFFSET * 2))
	end
	
	mainFrame.Position = UDim2.new(0,20,1.0, -mainFrame.Size.Y.Offset-20)
	if isSmallTouchScreen then
		local touchScreenGui = game.Players.LocalPlayer.PlayerGui:FindFirstChild("TouchGui")
		if touchScreenGui then
			touchControlGui = touchScreenGui:FindFirstChild("TouchControlFrame")
			if touchControlGui then
				touchControlGui.Visible = false
			end
		end
		mainFrame.Position = UDim2.new(0,10,1.0, -mainFrame.Size.Y.Offset)
	end
	styleMainFrame(currentTone())
	mainFrame.Visible = true

	if usingGamepad then
		Game:GetService("GuiService").SelectedCoreObject = choices[1]
	end
end

function doDialog(dialog)
	if dialog.InUse then
		return
	else
		dialog.InUse = true
		if filterEnabledFixActive then
			setDialogInUseEvent:FireServer(dialog, true)
		end
	end

	currentConversationDialog = dialog
	game:GetService("Chat"):Chat(dialog.Parent, dialog.InitialPrompt, getChatColor(dialog.Tone))
	variableDelay(dialog.InitialPrompt)

	presentDialogChoices(dialog.Parent, dialog:GetChildren(), dialog)
end

function renewKillswitch(dialog)
	if filterEnabledFixActive then
		if currentDialogTimeoutCoroutine then
			coroutineMap[currentDialogTimeoutCoroutine] = false
			currentDialogTimeoutCoroutine = nil
		end
	else
		if currentAbortDialogScript then
			currentAbortDialogScript:Destroy()
			currentAbortDialogScript = nil
		end
	end

	if filterEnabledFixActive then
		currentDialogTimeoutCoroutine = coroutine.create(function(thisCoroutine)
			wait(15)
			if thisCoroutine ~= nil then
				if coroutineMap[thisCoroutine] == nil then
					setDialogInUseEvent:FireServer(dialog, false)
				end
				coroutineMap[thisCoroutine] = nil
			end
		end)
		coroutine.resume(currentDialogTimeoutCoroutine, currentDialogTimeoutCoroutine)
	else
		currentAbortDialogScript = timeoutScript:Clone()
		currentAbortDialogScript.Archivable = false
		currentAbortDialogScript.Disabled = false
		currentAbortDialogScript.Parent = dialog
	end
end

function checkForLeaveArea()
	while currentConversationDialog do
		if currentConversationDialog.Parent and (player:DistanceFromCharacter(currentConversationDialog.Parent.Position) >= currentConversationDialog.ConversationDistance) then
			wanderDialog()
		end
		wait(1)
	end
end

function startDialog(dialog)
	if dialog.Parent and dialog.Parent:IsA("BasePart") then
		if player:DistanceFromCharacter(dialog.Parent.Position) >= dialog.ConversationDistance then
			showMessage(tooFarAwayMessage, tooFarAwaySize)
			return
		end

		for dialog, gui in pairs(dialogMap) do
			if dialog and gui then
				gui.Enabled = false
			end
		end
		
		contextActionService:BindCoreAction("Nothing", function() end, false, Enum.UserInputType.Gamepad1, Enum.UserInputType.Gamepad2, Enum.UserInputType.Gamepad3, Enum.UserInputType.Gamepad4)

		renewKillswitch(dialog)

		delay(1, checkForLeaveArea)
		doDialog(dialog)
	end
end

function removeDialog(dialog)
   if dialogMap[dialog] then
      dialogMap[dialog]:Destroy()
      dialogMap[dialog] = nil
   end
	if dialogConnections[dialog] then
		dialogConnections[dialog]:disconnect()
		dialogConnections[dialog] = nil
	end
end

function addDialog(dialog)
	if dialog.Parent then
		if dialog.Parent:IsA("BasePart") then
			local chatGui = chatNotificationGui:clone()
			chatGui.Enabled = not dialog.InUse
			chatGui.Adornee = dialog.Parent
			chatGui.RobloxLocked = true

			chatGui.Parent = game:GetService("CoreGui")
			
			chatGui.Background.MouseButton1Click:connect(function() startDialog(dialog) end)
			setChatNotificationTone(chatGui, dialog.Purpose, dialog.Tone)

			dialogMap[dialog] = chatGui

			dialogConnections[dialog] = dialog.Changed:connect(function(prop)
				if prop == "Parent" and dialog.Parent then
					--This handles the reparenting case, seperate from removal case
					removeDialog(dialog)
					addDialog(dialog)
				elseif prop == "InUse" then
					chatGui.Enabled = not currentConversationDialog and not dialog.InUse
					if dialog == currentConversationDialog then
						timeoutDialog()
					end
				elseif prop == "Tone" or prop == "Purpose" then
					setChatNotificationTone(chatGui, dialog.Purpose, dialog.Tone)
				end
			end)
		else -- still need to listen to parent changes even if current parent is not a BasePart
			dialogConnections[dialog] = dialog.Changed:connect(function(prop)
				if prop == "Parent" and dialog.Parent then
					--This handles the reparenting case, seperate from removal case
					removeDialog(dialog)
					addDialog(dialog)
				end
			end)
		end
	end
end

function fetchScripts()
	local model = game:GetService("InsertService"):LoadAsset(39226062)
    if type(model) == "string" then -- load failed, lets try again
		wait(0.1)
		model = game:GetService("InsertService"):LoadAsset(39226062)
	end
	if type(model) == "string" then -- not going to work, lets bail
		return
	end

	waitForChild(model,"TimeoutScript")
	timeoutScript = model.TimeoutScript
	waitForChild(model,"ReenableDialogScript")
	reenableDialogScript = model.ReenableDialogScript
end

function onLoad()
  waitForProperty(game:GetService("Players"), "LocalPlayer")
  player = game:GetService("Players").LocalPlayer
  waitForProperty(player, "Character")

  --print("Creating Guis")
  createChatNotificationGui()

  --print("Creating MessageDialog")
  createMessageDialog()
  messageDialog.RobloxLocked = true
  messageDialog.Parent = gui

  if not filterEnabledFixActive then
	fetchScripts()
  end 
  
  --print("Waiting for BottomLeftControl")
  waitForChild(gui, "BottomLeftControl")

  --print("Initializing Frame")
  local frame = Instance.new("Frame")
  frame.Name = "DialogFrame"
  frame.Position = UDim2.new(0,0,0,0)
  frame.Size = UDim2.new(0,0,0,0)
  frame.BackgroundTransparency = 1
  frame.RobloxLocked = true
  game:GetService("GuiService"):AddSelectionParent("RBXDialogGroup", frame)

  if (touchEnabled and not isSmallTouchScreen) then
	frame.Position = UDim2.new(0,20,0.5,0)
	frame.Size = UDim2.new(0.25,0,0.1,0)
	frame.Parent = gui
  elseif isSmallTouchScreen then
	frame.Position = UDim2.new(0,0,.9,-10)
	frame.Size = UDim2.new(0.25,0,0.1,0)
	frame.Parent = gui
  else
	frame.Parent = gui.BottomLeftControl
  end
  initialize(frame)

  --print("Adding Dialogs")
  game:GetService("CollectionService").ItemAdded:connect(function(obj) if obj:IsA("Dialog") then addDialog(obj) end end)
  game:GetService("CollectionService").ItemRemoved:connect(function(obj) if obj:IsA("Dialog") then removeDialog(obj) end end)
  for i, obj in pairs(game:GetService("CollectionService"):GetCollection("Dialog")) do
    if obj:IsA("Dialog") then
       addDialog(obj)
    end
  end
end

local lastClosestDialog = nil
local getClosestDialogToPosition = guiService.GetClosestDialogToPosition

game:GetService("RunService").Heartbeat:connect(function()
	local closestDistance = math.huge
	local closestDialog = nil
	if usingGamepad == true then
		if game.Players.LocalPlayer and game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
			local characterPosition = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart").Position
			closestDialog = getClosestDialogToPosition(guiService, characterPosition)
		end
	end

	if closestDialog ~= lastClosestDialog then
		if dialogMap[lastClosestDialog] then
			dialogMap[lastClosestDialog].Background.ActivationButton.Visible = false
		end
		lastClosestDialog = closestDialog
		contextActionService:UnbindCoreAction("StartDialogAction")
		if closestDialog ~= nil then
			contextActionService:BindCoreAction("StartDialogAction",
												function(actionName, userInputState, inputObject) 
													if userInputState == Enum.UserInputState.Begin then 
														if closestDialog and closestDialog.Parent then
															startDialog(closestDialog) 
														end
													end
												end, 
												false, 
												Enum.KeyCode.ButtonX)
			if dialogMap[closestDialog] then
				dialogMap[closestDialog].Background.ActivationButton.Visible = true
			end
		end
	end
end)

local lastSelectedChoice = nil

guiService.Changed:connect(function(property)
	if property == "SelectedCoreObject" then
		if lastSelectedChoice and lastSelectedChoice:FindFirstChild("RBXchatDialogSelectionButton") then
			lastSelectedChoice:FindFirstChild("RBXchatDialogSelectionButton").Visible = false
			lastSelectedChoice.BackgroundTransparency = 1
		end
		lastSelectedChoice = guiService.SelectedCoreObject
		if lastSelectedChoice and lastSelectedChoice:FindFirstChild("RBXchatDialogSelectionButton") then
			lastSelectedChoice:FindFirstChild("RBXchatDialogSelectionButton").Visible = true
			lastSelectedChoice.BackgroundTransparency = 0
		end
	end
end)

onLoad()