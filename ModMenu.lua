local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService") 
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

local Config = {
    Movement = { NoClip = false },
    ESP = { Players = false, PlayerBases = false },
    Hitbox = { Enabled = false, Size = 10 }
}

local NoClipParts = {}
local PlayerESPObjects = {}
local ActivePlayerBasePrompts = {} 
local PlayerConnections = {}
local originalHoldDurations = {}
local promptAddedConnection = nil
local multiPromptConnection = nil
local farmThread = nil
local lastAttackTime = 0
local ATTACK_COOLDOWN = 0.05 

local selectedTargetName = "[Closest Player]"
local dropdownOpen = false
local dropdownButtons = {}

local toggles = {
    speedBoost = false,
    infiniteJump = false,
    autoBatToggled = false,
    instantProximity = false,
    multiPrompt = false,
    speedBypassCFrame = false,
    antiAFK = false,
    autoCollect = false
}

local TICK_RATE = 0.4
local MONEY_TARGETS = {
    ["collectpart"] = true, ["cash"] = true, ["money"] = true, ["gold"] = true,
    ["coin"] = true, ["coins"] = true, ["diamond"] = true, ["diamonds"] = true,
    ["gem"] = true, ["gems"] = true, ["ruby"] = true, ["rubies"] = true,
    ["dollar"] = true, ["dollars"] = true, ["bill"] = true, ["bills"] = true,
    ["point"] = true, ["points"] = true, ["token"] = true, ["tokens"] = true,
    ["bag"] = true, ["briefcase"] = true, ["currency"] = true, ["loot"] = true,
    ["drop"] = true, ["crystal"] = true, ["crystals"] = true
}

local cframeSpeedValue = 34 
local connections = {}
local savedPositions = { [1] = nil, [2] = nil, [3] = nil }

local physicsAttachment = nil
local physicsVelocityConstraint = nil
local themes = {
    { Background = Color3.fromRGB(46, 46, 46), TitleBar = Color3.fromRGB(36, 36, 36), Border = Color3.fromRGB(60, 60, 60), ButtonText = Color3.fromRGB(220, 220, 220) },
    { Background = Color3.fromRGB(15, 25, 45), TitleBar = Color3.fromRGB(10, 15, 30), Border = Color3.fromRGB(30, 50, 90), ButtonText = Color3.fromRGB(140, 200, 255) },
    { Background = Color3.fromRGB(10, 20, 10), TitleBar = Color3.fromRGB(5, 10, 5), Border = Color3.fromRGB(0, 255, 0), ButtonText = Color3.fromRGB(0, 255, 0) }
}
local currentThemeIndex = 1

local function GetCharacter() return player.Character end
local function GetRoot(character) return character and character:FindFirstChild("HumanoidRootPart") end

-- FIXED: Added missing createSpeedSlider function
local function createSpeedSlider(parentFrame, sliderConfig, callback)
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(1, -10, 0, 35)
    sliderFrame.Position = UDim2.new(0, 5, 0, 0)
    sliderFrame.BackgroundTransparency = 1
    sliderFrame.Parent = parentFrame

    local sliderLabel = Instance.new("TextLabel")
    sliderLabel.Size = UDim2.new(1, 0, 0, 15)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.Text = sliderConfig.label .. ": " .. sliderConfig.default
    sliderLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    sliderLabel.TextSize = 12
    sliderLabel.Font = Enum.Font.SourceSans
    sliderLabel.Parent = sliderFrame

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -20, 0, 4)
    track.Position = UDim2.new(0, 10, 0, 22)
    track.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    track.BorderSizePixel = 0
    track.Parent = sliderFrame

    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new((sliderConfig.default - sliderConfig.min) / (sliderConfig.max - sliderConfig.min), 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
    knob.Text = ""
    knob.Parent = track

    local draggingSlider = false

    local function updateSlider(input)
        local percentage = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        knob.Position = UDim2.new(percentage, 0, 0.5, 0)
        local value = math.floor(sliderConfig.min + (percentage * (sliderConfig.max - sliderConfig.min)))
        sliderLabel.Text = sliderConfig.label .. ": " .. value
        callback(value)
    end

    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
end

local function SetupPhysicsObjects(root)
    if not root then return end
    if not physicsAttachment or physicsAttachment.Parent ~= root then
        if physicsAttachment then pcall(function() physicsAttachment:Destroy() end) end
        physicsAttachment = Instance.new("Attachment")
        physicsAttachment.Name = "SafeMoveAttachment"
        physicsAttachment.Parent = root
    end
    if not physicsVelocityConstraint or physicsVelocityConstraint.Parent ~= root then
        if physicsVelocityConstraint then pcall(function() physicsVelocityConstraint:Destroy() end) end
        physicsVelocityConstraint = Instance.new("LinearVelocity")
        physicsVelocityConstraint.Name = "SafeMoveVelocity"
        physicsVelocityConstraint.Attachment0 = physicsAttachment
        physicsVelocityConstraint.MaxForce = 0 
        physicsVelocityConstraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        physicsVelocityConstraint.VectorVelocity = Vector3.new(0,0,0)
        physicsVelocityConstraint.Parent = root
    end
end

local targetParent = (type(gethui) == "function" and gethui()) or CoreGui
local existingGui = targetParent:FindFirstChild("ModMenu")
if existingGui then existingGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ModMenu"
gui.ResetOnSpawn = false
gui.Parent = targetParent 

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 230, 0, 320)
frame.Position = UDim2.new(0.5, -115, 0.5, -160)
frame.BackgroundColor3 = themes[currentThemeIndex].Background
frame.BorderSizePixel = 1
frame.BorderColor3 = themes[currentThemeIndex].Border
frame.Active = true
frame.Parent = gui 

local dragging, dragInput, dragStart, startPos
local function updateDrag(input)
    local delta = input.Position - dragStart
    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then updateDrag(input) end
end)
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = themes[currentThemeIndex].TitleBar
title.Text = "Mod Menu"
title.TextColor3 = themes[currentThemeIndex].ButtonText
title.TextSize = 18
title.Font = Enum.Font.SourceSansBold
title.Parent = frame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -30, 0, 0)
closeButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = Enum.Font.SourceSansBold
closeButton.Parent = frame

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.new(0, 30, 0, 30)
minimizeButton.Position = UDim2.new(1, -60, 0, 0)
minimizeButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
minimizeButton.Text = "-"
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.Font = Enum.Font.SourceSansBold
minimizeButton.TextSize = 18
minimizeButton.Parent = frame

local menuContentContainer = Instance.new("Frame")
menuContentContainer.Name = "MenuContentContainer"
menuContentContainer.Size = UDim2.new(1, 0, 1, -30)
menuContentContainer.Position = UDim2.new(0, 0, 0, 30)
menuContentContainer.BackgroundTransparency = 1
menuContentContainer.Parent = frame

local isMinimized = false
minimizeButton.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    menuContentContainer.Visible = not isMinimized
    frame.Size = isMinimized and UDim2.new(0, 230, 0, 30) or UDim2.new(0, 230, 0, 320)
    minimizeButton.Text = isMinimized and "+" or "-"
end)

local content = Instance.new("ScrollingFrame")
content.Parent = menuContentContainer
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.ScrollBarThickness = 5

local contentLayout = Instance.new("UIListLayout")
contentLayout.Parent = content
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 5)

local function recalculateCanvasSize()
    content.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 15)
end
contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(recalculateCanvasSize)

local function setButtonState(button, stroke, enabled)
    local textColor = enabled and Color3.fromRGB(75, 255, 75) or Color3.fromRGB(255, 75, 75)
    local strokeColor = enabled and Color3.fromRGB(75, 180, 75) or Color3.fromRGB(55, 55, 60)
    TweenService:Create(button, TweenInfo.new(0.2), {TextColor3 = textColor}):Play()
    TweenService:Create(stroke, TweenInfo.new(0.2), {Color = strokeColor}):Play()
end

local categoryButtons = {}

local function createCategory(name)
    local catFrame = Instance.new("Frame")
    catFrame.Parent = content
    catFrame.BackgroundTransparency = 1
    catFrame.Size = UDim2.new(1, 0, 0, 30)

    local catLayout = Instance.new("UIListLayout")
    catLayout.Parent = catFrame
    catLayout.SortOrder = Enum.SortOrder.LayoutOrder
    catLayout.Padding = UDim.new(0, 5)

    local catButton = Instance.new("TextButton")
    catButton.Size = UDim2.new(1, 0, 0, 30)
    catButton.BackgroundColor3 = themes[currentThemeIndex].TitleBar
    catButton.Text = name .. " ▼"
    catButton.TextColor3 = themes[currentThemeIndex].ButtonText
    catButton.TextSize = 16
    catButton.Font = Enum.Font.SourceSansBold
    catButton.Parent = catFrame
    
    table.insert(categoryButtons, catButton)

    local subFrame = Instance.new("Frame")
    subFrame.Parent = catFrame
    subFrame.BackgroundTransparency = 1
    subFrame.Visible = true

    local subLayout = Instance.new("UIListLayout")
    subLayout.Parent = subFrame
    subLayout.SortOrder = Enum.SortOrder.LayoutOrder
    subLayout.Padding = UDim.new(0, 5)

    local function updateSizes()
        local subHeight = subFrame.Visible and subLayout.AbsoluteContentSize.Y or 0
        subFrame.Size = UDim2.new(1, 0, 0, subHeight)
        catFrame.Size = UDim2.new(1, 0, 0, catLayout.AbsoluteContentSize.Y)
        recalculateCanvasSize()
    end

    subLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSizes)
    catButton.MouseButton1Click:Connect(function()
        subFrame.Visible = not subFrame.Visible
        catButton.Text = name .. (subFrame.Visible and " ▼" or " ►")
        updateSizes()
    end)

    return function(subName, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -10, 0, 35)
        button.Position = UDim2.new(0, 5, 0, 0)
        button.BackgroundColor3 = themes[currentThemeIndex].Background
        button.Text = subName
        button.TextColor3 = Color3.fromRGB(255, 75, 75)
        button.TextSize = 14
        button.Font = Enum.Font.SourceSansBold
        button.Parent = subFrame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(55, 55, 60)
        stroke.Thickness = 1.5
        stroke.Parent = button

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = button

        button.MouseButton1Click:Connect(function() callback(button, stroke) end)
        return button, subFrame 
    end
end

local movementAddButton = createCategory("Movement")
local visualsAddButton = createCategory("Visuals")
local teleportAddButton = createCategory("Teleports")
local miscAddButton = createCategory("Misc")
local automationCategory = createCategory("Automation")
local settingsAddButton = createCategory("Settings")
local function SetNoClip(Enabled)
    Config.Movement.NoClip = Enabled
    if not Enabled then
        for Part, OriginalState in pairs(NoClipParts) do
            if Part and Part.Parent then Part.CanCollide = OriginalState end
        end
        table.clear(NoClipParts)
    end
end

connections.noClipLoop = RunService.Stepped:Connect(function()
    if not Config.Movement.NoClip then return end
    local Character = GetCharacter()
    if not Character then return end
    for _, Object in ipairs(Character:GetDescendants()) do
        if Object:IsA("BasePart") then
            if NoClipParts[Object] == nil then NoClipParts[Object] = Object.CanCollide end
            Object.CanCollide = false
        end
    end
end)

movementAddButton("NoClip", function(button, stroke)
    local newState = not Config.Movement.NoClip
    SetNoClip(newState)
    setButtonState(button, stroke, newState)
end)

connections.infiniteJump = UserInputService.JumpRequest:Connect(function()
    if toggles.infiniteJump then
        local character = GetCharacter()
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

movementAddButton("Infinite Jump", function(button, stroke)
    toggles.infiniteJump = not toggles.infiniteJump
    setButtonState(button, stroke, toggles.infiniteJump)
end)

local SPEED_SLIDER_CONFIG = {
    Walk = { min = 10, max = 500, default = 50, label = "Walk Speed" },
    CFrame = { min = 10, max = 500, default = 34, label = "Physics Speed" }
}

local speedValueWalk = SPEED_SLIDER_CONFIG.Walk.default
local _, speedSubContainer = movementAddButton("Speed Boost", function(button, stroke)
    toggles.speedBoost = not toggles.speedBoost
    setButtonState(button, stroke, toggles.speedBoost)
    local hum = GetCharacter() and GetCharacter():FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = toggles.speedBoost and speedValueWalk or 16 end
end)

createSpeedSlider(speedSubContainer, SPEED_SLIDER_CONFIG.Walk, function(value)
    speedValueWalk = value
    local hum = GetCharacter() and GetCharacter():FindFirstChildOfClass("Humanoid")
    if hum and toggles.speedBoost then hum.WalkSpeed = value end
end)

local _, movementSubContainer = movementAddButton("Speed Bypass (Physics)", function(button, stroke)
    toggles.speedBypassCFrame = not toggles.speedBypassCFrame
    setButtonState(button, stroke, toggles.speedBypassCFrame)
    if toggles.speedBypassCFrame then
        local root = GetRoot(GetCharacter())
        SetupPhysicsObjects(root)
        if connections.speedCFrame then connections.speedCFrame:Disconnect() end
        connections.speedCFrame = RunService.Heartbeat:Connect(function()
            local char = GetCharacter()
            local activeRoot = GetRoot(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if activeRoot and hum and hum.MoveDirection.Magnitude > 0 then
                SetupPhysicsObjects(activeRoot)
                physicsVelocityConstraint.MaxForce = 999999
                physicsVelocityConstraint.VectorVelocity = hum.MoveDirection * cframeSpeedValue
            elseif activeRoot and physicsVelocityConstraint then
                physicsVelocityConstraint.MaxForce = 0
            end
        end)
    else
        if connections.speedCFrame then connections.speedCFrame:Disconnect() connections.speedCFrame = nil end
        if physicsVelocityConstraint then physicsVelocityConstraint.MaxForce = 0 end
    end
end)

createSpeedSlider(movementSubContainer, SPEED_SLIDER_CONFIG.CFrame, function(value) cframeSpeedValue = value end)

player.CharacterAdded:Connect(function(char)
    local root = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if root then SetupPhysicsObjects(root) end
    if hum and toggles.speedBoost then hum.WalkSpeed = speedValueWalk end
end)
local function RemovePlayerESP(Player)
    local Data = PlayerESPObjects[Player]
    if Data then
        if Data.LoopActive then Data.LoopActive = false end 
        for _, Object in pairs(Data) do
            if typeof(Object) == "Instance" and Object.Parent then pcall(function() Object:Destroy() end) end
        end
        PlayerESPObjects[Player] = nil
    end
end

local function CreatePlayerESP(Player)
    if Player == player then return end
    local Character = Player.Character
    if not Character then return end
    RemovePlayerESP(Player)
    local Root = Character:FindFirstChild("HumanoidRootPart")
    if not Root then return end

    local Highlight = Instance.new("Highlight")
    Highlight.Name = "CustomYellowHighlight"
    Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    Highlight.FillColor = Color3.fromRGB(255, 255, 0) 
    Highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
    Highlight.FillTransparency = 0.25 
    Highlight.Enabled = Config.ESP.Players
    Highlight.Parent = Character

    local Billboard = Instance.new("BillboardGui")
    Billboard.Name = "CustomOrangeBillboard"
    Billboard.Size = UDim2.fromOffset(200, 40)
    Billboard.StudsOffset = Vector3.new(0, 4.0, 0)
    Billboard.AlwaysOnTop = true
    Billboard.Enabled = Config.ESP.Players
    Billboard.Parent = Character

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.fromScale(1, 1)
    Label.BackgroundTransparency = 1
    Label.TextColor3 = Color3.fromRGB(255, 120, 0) 
    Label.TextStrokeColor3 = Color3.new(0, 0, 0)
    Label.Font = Enum.Font.GothamBold
    Label.TextScaled = true
    Label.Parent = Billboard

    local runtimeToken = { Highlight = Highlight, Billboard = Billboard, LoopActive = true }
    PlayerESPObjects[Player] = runtimeToken

    task.spawn(function()
        while Character.Parent and Player.Parent and PlayerESPObjects[Player] == runtimeToken and runtimeToken.LoopActive do
            local currentConfigState = Config.ESP.Players
            Highlight.Enabled = currentConfigState
            Billboard.Enabled = currentConfigState
            if currentConfigState and Root.Parent then
                local MyCharacter = player.Character
                local MyRoot = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
                if MyRoot then
                    local Distance = math.floor((MyRoot.Position - Root.Position).Magnitude)
                    Label.Text = string.format("👤 %s [%d studs]", Player.Name, Distance)
                else
                    Label.Text = "👤 " .. Player.Name
                end
            end
            task.wait(0.1)
        end
        if PlayerESPObjects[Player] == runtimeToken then RemovePlayerESP(Player) end
    end)
end

local function AttachPlayerESP(Player)
    if Player == player then return end
    if PlayerConnections[Player] then PlayerConnections[Player]:Disconnect() PlayerConnections[Player] = nil end
    if Player.Character then task.spawn(CreatePlayerESP, Player) end
    PlayerConnections[Player] = Player.CharacterAdded:Connect(function(char)
        if char:WaitForChild("HumanoidRootPart", 5) then CreatePlayerESP(Player) end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do AttachPlayerESP(p) end
connections.playerAddedESP = Players.PlayerAdded:Connect(AttachPlayerESP)
connections.playerRemovingESP = Players.PlayerRemoving:Connect(function(p)
    RemovePlayerESP(p)
    if PlayerConnections[p] then PlayerConnections[p]:Disconnect() PlayerConnections[p] = nil end
end)

visualsAddButton("Player ESP", function(button, stroke)
    Config.ESP.Players = not Config.ESP.Players
    setButtonState(button, stroke, Config.ESP.Players)
end)

local function getBluePromptESPFolder()
    local folder = CoreGui:FindFirstChild("BlueTextPromptESP")
    if not folder then folder = Instance.new("Folder") folder.Name = "BlueTextPromptESP" folder.Parent = CoreGui end
    return folder
end

local function ApplyBluePromptESP(part, playerUsername, espFolder)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BluePromptBillboard"
    billboard.AlwaysOnTop = true
    billboard.StudsOffset = Vector3.new(0, 5.5, 0)
    billboard.Adornee = part
    billboard.Size = UDim2.new(14, 0, 4, 0)
    billboard.Parent = espFolder

    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(1, 0, 1, 0)
    panel.BackgroundColor3 = Color3.fromRGB(10, 20, 35)
    panel.BackgroundTransparency = 0.18
    panel.Parent = billboard

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 220, 255)
    stroke.Thickness = 2.6
    stroke.Parent = panel

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -12, 1, -10)
    label.Position = UDim2.new(0, 6, 0, 5)
    label.BackgroundTransparency = 1
    label.Text = playerUsername
    label.Font = Enum.Font.GothamBold
    label.TextSize = 22
    label.TextColor3 = Color3.fromRGB(120, 220, 255)
    label.Parent = panel
    return billboard
end

local function StartPlayerBaseTracking()
    if connections.playerBaseLoop then return end
    local doorKeywords = {"enter", "open", "door", "gate", "access", "lock", "house", "base"}
    connections.playerBaseLoop = task.spawn(function()
        while Config.ESP.PlayerBases do
            local espFolder = getBluePromptESPFolder()
            local discoveredThisPass = {}
            local playerLookup = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= Players.LocalPlayer then
                    playerLookup[p.Name:lower()] = p.Name
                    playerLookup[tostring(p.UserId)] = p.Name
                end
            end
            for _, object in pairs(Workspace:GetDescendants()) do
                if object:IsA("ProximityPrompt") then
                    local actionTextLower = string.lower(object.ActionText)
                    local objectTextLower = string.lower(object.ObjectText)
                    local fullNameLower = object:GetFullName():lower()
                    local isDoorPrompt = false
                    for _, keyword in ipairs(doorKeywords) do
                        if string.find(actionTextLower, keyword) or string.find(objectTextLower, keyword) then isDoorPrompt = true break end
                    end
                    if isDoorPrompt and object.Parent and object.Parent:IsA("BasePart") then
                        local targetPart = object.Parent
                        discoveredThisPass[targetPart] = true
                        if not ActivePlayerBasePrompts[targetPart] then
                            local matchedOwner = "Other Player"
                            local ownerFound = false
                            for key, originalName in pairs(playerLookup) do
                                if string.find(fullNameLower, key) then matchedOwner = originalName; ownerFound = true; break end
                            end
                            if not ownerFound then
                                for attrName, attrValue in pairs(targetPart:GetAttributes()) do
                                    local valStr = tostring(attrValue):lower()
                                    if playerLookup[valStr] or playerLookup[attrName:lower()] then
                                        matchedOwner = playerLookup[valStr] or playerLookup[attrName:lower()]
                                        ownerFound = true
                                        break
                                    end
                                end
                            end
                            if not string.find(fullNameLower, Players.LocalPlayer.Name:lower()) then
                                ActivePlayerBasePrompts[targetPart] = ApplyBluePromptESP(targetPart, matchedOwner, espFolder)
                            end
                        end
                    end
                end
            end
            for savedPart, billboardInstance in pairs(ActivePlayerBasePrompts) do
                if not discoveredThisPass[savedPart] or not savedPart.Parent then
                    if billboardInstance and billboardInstance.Parent then billboardInstance:Destroy() end
                    ActivePlayerBasePrompts[savedPart] = nil
                end
            end
            task.wait(0.5) 
        end
    end)
end

local function StopPlayerBaseTracking()
    if connections.playerBaseLoop then
        if type(connections.playerBaseLoop) == "thread" then task.cancel(connections.playerBaseLoop) else connections.playerBaseLoop:Disconnect() end
        connections.playerBaseLoop = nil
    end
    table.clear(ActivePlayerBasePrompts)
    local folder = CoreGui:FindFirstChild("BlueTextPromptESP")
    if folder then folder:Destroy() end
end

visualsAddButton("Base ESP", function(button, stroke)
    Config.ESP.PlayerBases = not Config.ESP.PlayerBases
    setButtonState(button, stroke, Config.ESP.PlayerBases)
    if Config.ESP.PlayerBases then StartPlayerBaseTracking() else StopPlayerBaseTracking() end
end)

connections.hitboxLoop = RunService.Stepped:Connect(function()
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            local root = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                if Config.Hitbox.Enabled then
                    root.Size = Vector3.new(Config.Hitbox.Size, Config.Hitbox.Size, Config.Hitbox.Size)
                    root.Transparency = 0.65 
                    root.CanCollide = false
                else
                    root.Size = Vector3.new(2, 2, 1) 
                    root.Transparency = 1 
                    root.CanCollide = false
                end
            end
        end
    end
end)

local _, hitboxSubContainer = visualsAddButton("Hitbox Expansion", function(button, stroke)
Config.Hitbox.Enabled = not Config.Hitbox.Enabled
setButtonState(button, stroke, Config.Hitbox.Enabled)
end)
local slotButtons = {}
local function updateSlotUI(slot)
if slotButtons[slot] then
if savedPositions[slot] then
slotButtons[slot].Save.Text = "Resave Slot " .. slot
slotButtons[slot].TP.TextColor3 = Color3.fromRGB(75, 255, 75)
else
slotButtons[slot].Save.Text = "Save Slot " .. slot
slotButtons[slot].TP.TextColor3 = Color3.fromRGB(255, 75, 75)
end
end
end
local function createTeleportSlotUI(slot, parentFrame)
local slotRow = Instance.new("Frame")
slotRow.Size = UDim2.new(1, -10, 0, 30)
slotRow.Position = UDim2.new(0, 5, 0, 0)
slotRow.BackgroundTransparency = 1
slotRow.Parent = parentFrame
local saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(0.5, -3, 1, 0)
saveBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
saveBtn.Text = "Save Slot " .. slot
saveBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
saveBtn.Font = Enum.Font.SourceSansBold
saveBtn.Parent = slotRow
local tpBtn = Instance.new("TextButton")
tpBtn.Size = UDim2.new(0.5, -3, 1, 0)
tpBtn.Position = UDim2.new(0.5, 3, 0, 0)
tpBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
tpBtn.Text = "TP Slot " .. slot
tpBtn.TextColor3 = Color3.fromRGB(255, 75, 75)
tpBtn.Font = Enum.Font.SourceSansBold
tpBtn.Parent = slotRow
slotButtons[slot] = { Save = saveBtn, TP = tpBtn }
saveBtn.MouseButton1Click:Connect(function()
local root = GetRoot(GetCharacter())
if root then savedPositions[slot] = root.CFrame updateSlotUI(slot) end
end)
tpBtn.MouseButton1Click:Connect(function()
local root = GetRoot(GetCharacter())
if root and savedPositions[slot] then root.CFrame = savedPositions[slot] end
end)
end
local _, tpSubContainer = teleportAddButton("Manage System", function() end)
createTeleportSlotUI(1, tpSubContainer)
createTeleportSlotUI(2, tpSubContainer)
createTeleportSlotUI(3, tpSubContainer)
local clearAllBtn = Instance.new("TextButton")
clearAllBtn.Size = UDim2.new(1, -10, 0, 30)
clearAllBtn.Position = UDim2.new(0, 5, 0, 0)
clearAllBtn.BackgroundColor3 = Color3.fromRGB(70, 30, 30)
clearAllBtn.Text = "Wipe Stored Pinpoints"
clearAllBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
clearAllBtn.Font = Enum.Font.SourceSansBold
clearAllBtn.Parent = tpSubContainer
clearAllBtn.MouseButton1Click:Connect(function()
for i = 1, 3 do savedPositions[i] = nil updateSlotUI(i) end
end)

local function findBat()
    local character = player.Character
    if not character then return nil end
    for _, tool in ipairs(character:GetChildren()) do
        local lowerName = tool.Name:lower()
        if tool:IsA("Tool") and (lowerName:find("bat") or lowerName:find("slap") or lowerName:find("glove") or lowerName:find("weapon")) then return tool end
    end
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            local lowerName = tool.Name:lower()
            if tool:IsA("Tool") and (lowerName:find("bat") or lowerName:find("slap") or lowerName:find("glove") or lowerName:find("weapon")) then return tool end
        end
    end
    return nil
end

local function getClosestTarget()
    local root = GetRoot(GetCharacter())
    if not root then return nil end
    local closest, minDist = nil, math.huge
    if selectedTargetName ~= "[Closest Player]" then
        local targetPlayer = Players:FindFirstChild(selectedTargetName)
        if targetPlayer and targetPlayer.Character then
            local tRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            local hum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            if tRoot and hum and hum.Health > 0 then return tRoot end
        end
        return nil 
    end
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            local tRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
            local hum = otherPlayer.Character:FindFirstChildOfClass("Humanoid")
            if tRoot and hum and hum.Health > 0 then
                local dist = (tRoot.Position - root.Position).Magnitude
                if dist < minDist then minDist = dist; closest = tRoot end
            end
        end
    end
    return closest
end

local function startBatAimbot()
    if connections.aimbot then connections.aimbot:Disconnect() end
    local char = GetCharacter()
    local root = GetRoot(char)
    SetupPhysicsObjects(root)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = false end

    connections.aimbot = RunService.RenderStepped:Connect(function()
        if not toggles.autoBatToggled then return end
        local activeChar = GetCharacter()
        local activeRoot = GetRoot(activeChar)
        local activeHum = activeChar and activeChar:FindFirstChildOfClass("Humanoid")
        if not activeRoot or not activeHum then return end
        SetupPhysicsObjects(activeRoot)

        if not activeChar:FindFirstChildOfClass("Tool") then
            local bat = findBat()
            if bat then pcall(function() activeHum:EquipTool(bat) end) end
        end

        local target = getClosestTarget()
        if not target or not target.Parent then 
            if physicsVelocityConstraint then physicsVelocityConstraint.MaxForce = 0 end
            return 
        end

        local targetVelocity = Vector3.new(0, 0, 0)
        pcall(function() targetVelocity = target.AssemblyLinearVelocity end)
        local myPosition = activeRoot.Position
        local targetPosition = target.Position
        local distance = (myPosition - targetPosition).Magnitude

        local pingCompensation = distance / 55
        local predictedPosition = targetPosition + (targetVelocity * math.clamp(pingCompensation, 0.03, 0.18))
        local lookGoal = Vector3.new(predictedPosition.X, myPosition.Y, predictedPosition.Z)
        if (lookGoal - myPosition).Magnitude > 0.1 then activeRoot.CFrame = CFrame.lookAt(myPosition, lookGoal) end

        if distance > 8 then
            local direction = (lookGoal - myPosition).Unit
            local speedMultiplier = activeHum.WalkSpeed > 16 and activeHum.WalkSpeed or 32
            physicsVelocityConstraint.MaxForce = 999999
            physicsVelocityConstraint.VectorVelocity = Vector3.new(direction.X * (speedMultiplier * 2), activeRoot.AssemblyLinearVelocity.Y, direction.Z * (speedMultiplier * 2))
        else
            local combatOffset = target.CFrame.LookVector * -1.5 
            activeRoot.CFrame = CFrame.lookAt(targetPosition + combatOffset, Vector3.new(targetPosition.X, myPosition.Y, targetPosition.Z))
            physicsVelocityConstraint.MaxForce = 999999
            physicsVelocityConstraint.VectorVelocity = Vector3.new(0, activeRoot.AssemblyLinearVelocity.Y, 0)
        end

        if distance < 11 and (tick() - lastAttackTime) >= ATTACK_COOLDOWN then
            lastAttackTime = tick()
            local tool = activeChar:FindFirstChildOfClass("Tool")
            if tool then
                local remote = tool:FindFirstChildOfClass("RemoteEvent") or tool:FindFirstChildWhichIsA("RemoteEvent", true)
                pcall(function() if remote then remote:FireServer() end; tool:Activate() end)
            end
        end
    end)
end

local function stopBatAimbot()
    if connections.aimbot then connections.aimbot:Disconnect() connections.aimbot = nil end
    if physicsVelocityConstraint then physicsVelocityConstraint.MaxForce = 0 end
    local hum = GetCharacter() and GetCharacter():FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = true end
end

local _, miscSubContainer = miscAddButton("BAT AIMBOT", function(button, stroke)
    toggles.autoBatToggled = not toggles.autoBatToggled
    setButtonState(button, stroke, toggles.autoBatToggled)
    if toggles.autoBatToggled then startBatAimbot() else stopBatAimbot() end
end)

local function applyPromptFix(prompt)
    if prompt:IsA("ProximityPrompt") and not originalHoldDurations[prompt] then
        originalHoldDurations[prompt] = prompt.HoldDuration
        if toggles.instantProximity then prompt.HoldDuration = 0 end
    end
end

miscAddButton("Toggle Instant Proximity", function(button, stroke)
    toggles.instantProximity = not toggles.instantProximity
    setButtonState(button, stroke, toggles.instantProximity)
    if toggles.instantProximity then
        for _, prompt in ipairs(Workspace:GetDescendants()) do applyPromptFix(prompt) if originalHoldDurations[prompt] then prompt.HoldDuration = 0 end end
        if not promptAddedConnection then
            promptAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
                task.spawn(function() if descendant:IsA("ProximityPrompt") then applyPromptFix(descendant) end end)
            end)
        end
    else
        if promptAddedConnection then promptAddedConnection:Disconnect() promptAddedConnection = nil end
        for prompt, dur in pairs(originalHoldDurations) do if prompt and prompt.Parent then prompt.HoldDuration = dur end end
        table.clear(originalHoldDurations)
    end
end)

local promptSweepRadius = 25
local _, radiusPickupSubContainer = miscAddButton("Radius Multi-Pickup", function(button, stroke)
    toggles.multiPrompt = not toggles.multiPrompt
    setButtonState(button, stroke, toggles.multiPrompt)
    if toggles.multiPrompt then
        multiPromptConnection = task.spawn(function()
            while toggles.multiPrompt do
                local character = GetCharacter()
                local rootPart = GetRoot(character)
                if rootPart then
                    for _, descendant in ipairs(Workspace:GetDescendants()) do
                        if descendant:IsA("ProximityPrompt") and descendant.Parent and descendant.Parent:IsA("BasePart") then
                            local distance = (rootPart.Position - descendant.Parent.Position).Magnitude
                            if distance <= promptSweepRadius then
                                task.spawn(function() descendant:InputHoldBegan() task.wait() descendant:InputHoldEnded() end)
                            end
                        end
                    end
                end
                task.wait(0.2)
            end
        end)
    else
        if multiPromptConnection then 
            if type(multiPromptConnection) == "thread" then task.cancel(multiPromptConnection) else multiPromptConnection:Disconnect() end
            multiPromptConnection = nil 
        end
    end
end)

local afkConnection = player.Idled:Connect(function()
    if toggles.antiAFK then
        local virtualUser = game:GetService("VirtualUser")
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(0, 0))
    end
end)

miscAddButton("Anti-AFK System", function(button, stroke)
    toggles.antiAFK = not toggles.antiAFK
    setButtonState(button, stroke, toggles.antiAFK)
end)

local function handlePickup(part)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and part:IsA("BasePart") then
        if firetouchinterest then
            firetouchinterest(root, part, 0) task.wait(0.01) firetouchinterest(root, part, 1)
        else
            local originalPosition = root.CFrame
            root.CFrame = part.CFrame task.wait(0.1) root.CFrame = originalPosition
        end
    end
end

-- OPTIMIZED LOOP: Safe target folder integration or throttle checks
miscAddButton("Auto-Collect Currency", function(button, stroke)
    toggles.autoCollect = not toggles.autoCollect
    setButtonState(button, stroke, toggles.autoCollect)
    if toggles.autoCollect then
        farmThread = task.spawn(function()
            while toggles.autoCollect do
                for _, object in ipairs(Workspace:GetDescendants()) do
                    if not toggles.autoCollect then break end
                    if object:IsA("BasePart") and object.Transparency < 1 then
                        local objectNameLower = string.lower(object.Name)
                        if MONEY_TARGETS[objectNameLower] or string.find(objectNameLower, "cash") or string.find(objectNameLower, "money") or string.find(objectNameLower, "coin") then
                            handlePickup(object)
                        end
                    end
                end
                task.wait(TICK_RATE)
            end
        end)
    else
        if farmThread then task.cancel(farmThread) farmThread = nil end
    end
end)

local upgradeRemote = game:GetService("ReplicatedStorage").Gasifier.Services.PlotService.RF.UpgradeBrainrot
local TOTAL_SLOTS = 30
local COOLDOWN_RATE = 0.15

local selectedSlots = {}
local isAutoUpgrading = false
local automationDropdownOpen = false
local automationButtons = {}

for i = 1, TOTAL_SLOTS do selectedSlots[i] = true end

local slotDropdownContainer = Instance.new("Frame")
slotDropdownContainer.Name = "SlotDropdownContainer"
slotDropdownContainer.Size = UDim2.new(1, -10, 0, 25)
slotDropdownContainer.Position = UDim2.new(0, 5, 0, 0)
slotDropdownContainer.BackgroundTransparency = 1
slotDropdownContainer.Parent = select(2, automationCategory("Configure Targets", function() end))

local slotDropdownMainButton = Instance.new("TextButton")
slotDropdownMainButton.Size = UDim2.new(1, 0, 1, 0)
slotDropdownMainButton.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
slotDropdownMainButton.Text = "Targeting: All Slots"
slotDropdownMainButton.TextColor3 = Color3.fromRGB(200, 200, 200)
slotDropdownMainButton.Font = Enum.Font.SourceSansBold
slotDropdownMainButton.Parent = slotDropdownContainer

local slotDropdownStroke = Instance.new("UIStroke")
slotDropdownStroke.Color = Color3.fromRGB(55, 55, 60)
slotDropdownStroke.Thickness = 1
slotDropdownStroke.Parent = slotDropdownMainButton

local slotDropdownListFrame = Instance.new("ScrollingFrame")
slotDropdownListFrame.Size = UDim2.new(1, 0, 0, 0) 
slotDropdownListFrame.Position = UDim2.new(0, 0, 1, 2)
slotDropdownListFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
slotDropdownListFrame.Visible = false
slotDropdownListFrame.ZIndex = 15
slotDropdownListFrame.ScrollBarThickness = 5
slotDropdownListFrame.Parent = slotDropdownContainer

local slotDropdownLayout = Instance.new("UIListLayout")
slotDropdownLayout.Parent = slotDropdownListFrame
slotDropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function updateDropdownLabel()
    local selectedCount = 0
    for i = 1, TOTAL_SLOTS do if selectedSlots[i] then selectedCount = selectedCount + 1 end end
    if selectedCount == TOTAL_SLOTS then slotDropdownMainButton.Text = "Targeting: All Slots"
    elseif selectedCount == 0 then slotDropdownMainButton.Text = "Targeting: None Selected"
    else slotDropdownMainButton.Text = "Targeting: (" .. selectedCount .. ") Slots" end
end

local function refreshSlotDropdownList()
    for _, btn in ipairs(automationButtons) do btn:Destroy() end
    table.clear(automationButtons)
    for slotIndex = 1, TOTAL_SLOTS do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 22)
        btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        btn.Text = "Slot #" .. slotIndex
        btn.TextSize = 12
        btn.Font = Enum.Font.SourceSans
        btn.ZIndex = 16
        btn.LayoutOrder = slotIndex
        btn.Parent = slotDropdownListFrame
        btn.TextColor3 = selectedSlots[slotIndex] and Color3.fromRGB(75, 255, 75) or Color3.fromRGB(180, 75, 75)

        btn.MouseButton1Click:Connect(function()
            selectedSlots[slotIndex] = not selectedSlots[slotIndex]
            btn.TextColor3 = selectedSlots[slotIndex] and Color3.fromRGB(75, 255, 75) or Color3.fromRGB(180, 75, 75)
            updateDropdownLabel()
        end)
        table.insert(automationButtons, btn)
    end
    slotDropdownListFrame.CanvasSize = UDim2.new(0, 0, 0, slotDropdownLayout.AbsoluteContentSize.Y)
end

slotDropdownMainButton.MouseButton1Click:Connect(function()
    automationDropdownOpen = not automationDropdownOpen
    if automationDropdownOpen then
        refreshSlotDropdownList() slotDropdownListFrame.Visible = true slotDropdownListFrame.Size = UDim2.new(1, 0, 0, 110)
    else slotDropdownListFrame.Visible = false slotDropdownListFrame.Size = UDim2.new(1, 0, 0, 0) end
end)

automationCategory("Toggle Auto-Upgrade", function(button, stroke)
    isAutoUpgrading = not isAutoUpgrading
    setButtonState(button, stroke, isAutoUpgrading)
    if isAutoUpgrading then
        task.spawn(function()
            while isAutoUpgrading do
                local fundsExhausted = false local attemptedAny = false
                for slotIndex = 1, TOTAL_SLOTS do
                    if not isAutoUpgrading then break end
                    if selectedSlots[slotIndex] then
                        attemptedAny = true
                        local success, response = upgradeRemote:InvokeServer(slotIndex)
                        local responseStr = string.lower(tostring(response))
                        if success then print("Successfully upgraded targeted Slot #" .. slotIndex)
                        else
                            warn("Failed targeted Slot #" .. slotIndex .. " | Response: " .. tostring(response))
                            if string.find(responseStr, "money") or string.find(responseStr, "cash") or string.find(responseStr, "fund") or string.find(responseStr, "afford") then
                                print("🛑 Insufficient funds. Halted loop.") fundsExhausted = true break
                            end
                        end
                        task.wait(COOLDOWN_RATE)
                    end
                end
                if not attemptedAny and isAutoUpgrading then
                    warn("No targets set!") isAutoUpgrading = false setButtonState(button, stroke, false) break
                end
                if fundsExhausted or not isAutoUpgrading then isAutoUpgrading = false setButtonState(button, stroke, false) break end
                task.wait(1)
            end
        end)
    end
end)

local function updateUITheme()
    local theme = themes[currentThemeIndex]
    frame.BackgroundColor3 = theme.Background frame.BorderColor3 = theme.Border
    title.BackgroundColor3 = theme.TitleBar title.TextColor3 = theme.ButtonText
    for _, catBtn in ipairs(categoryButtons) do catBtn.BackgroundColor3 = theme.TitleBar catBtn.TextColor3 = theme.ButtonText end
end

settingsAddButton("Cycle UI Theme", function(button, stroke)
    currentThemeIndex = currentThemeIndex + 1 if currentThemeIndex > #themes then currentThemeIndex = 1 end updateUITheme()
    setButtonState(button, stroke, true) task.delay(0.2, function() setButtonState(button, stroke, false) end)
end)

local function cleanup()
    toggles.speedBoost = false; toggles.infiniteJump = false; toggles.autoBatToggled = false
    toggles.speedBypassCFrame = false; toggles.instantProximity = false; toggles.multiPrompt = false
    toggles.antiAFK = false; toggles.autoCollect = false; isAutoUpgrading = false
    SetNoClip(false); Config.ESP.Players = false; Config.ESP.PlayerBases = false; Config.Hitbox.Enabled = false

    for _, conn in pairs(connections) do if conn then pcall(function() conn:Disconnect() end) end end
    table.clear(connections) if afkConnection then afkConnection:Disconnect() end
    stopBatAimbot() StopPlayerBaseTracking()
    if farmThread then task.cancel(farmThread); farmThread = nil end
    if physicsVelocityConstraint then pcall(function() physicsVelocityConstraint:Destroy() end) end
    if physicsAttachment then pcall(function() physicsAttachment:Destroy() end) end
    local hum = GetCharacter() and GetCharacter():FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
    for p in pairs(PlayerESPObjects) do RemovePlayerESP(p) end
    for _, conn in pairs(PlayerConnections) do if conn then conn:Disconnect() end end
    if promptAddedConnection then promptAddedConnection:Disconnect() end
    if multiPromptConnection then if type(multiPromptConnection) == "thread" then task.cancel(multiPromptConnection) else multiPromptConnection:Disconnect() end end
    for prompt, dur in pairs(originalHoldDurations) do if prompt and prompt.Parent then prompt.HoldDuration = dur end end
end

closeButton.MouseButton1Click:Connect(function() cleanup(); gui:Destroy() end)