local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- Configuration
local FIELD_WIDTH = 30
local FIELD_DEPTH = 20
local SNAKE_GAP = 4

-- Data (Embedded from BSS-Zones.json)
local ZONES = {
    ["Starter"] = {
        ["Sunflower"] = Vector3.new(-212.53, 3.97, 170.00),
        ["Dandelion"] = Vector3.new(-40.38, 3.97, 218.76),
        ["Mushroom"] = Vector3.new(-92.92, 3.97, 115.72),
        ["BlueFlower"] = Vector3.new(153.60, 3.97, 98.12),
        ["Clover"] = Vector3.new(151.00, 33.47, 198.69)
    },
    ["LowerTier"] = {
        ["Spider"] = Vector3.new(-43.76, 19.97, -4.11),
        ["Bamboo"] = Vector3.new(132.39, 19.97, -24.32),
        ["Strawberry"] = Vector3.new(-182.93, 19.97, -15.73)
    },
    ["MidTier"] = {
        ["Pineapple"] = Vector3.new(255.21, 67.97, -206.35),
        ["Stump"] = Vector3.new(422.69, 95.95, -174.36)
    },
    ["HighTier"] = {
        ["Cactus"] = Vector3.new(-193.24, 67.97, -101.94),
        ["Pumpkin"] = Vector3.new(-189.57, 67.97, -185.54),
        ["PineTree"] = Vector3.new(-326.85, 67.97, -188.41),
        ["Rose"] = Vector3.new(-328.45, 19.92, 129.96),
        ["MountainTop"] = Vector3.new(78.28, 175.97, -172.09)
    },
    ["EliteTier"] = {
        ["Coconut"] = Vector3.new(-263.03, 71.42, 466.07),
        ["Pepper"] = Vector3.new(-491.53, 123.18, 530.59)
    }
}

-- Flatten Zones for easy selection
local FLAT_ZONES = {}
for category, fields in pairs(ZONES) do
    for name, pos in pairs(fields) do
        table.insert(FLAT_ZONES, {Name = name, Position = pos})
    end
end
table.sort(FLAT_ZONES, function(a, b) return a.Name < b.Name end)

-- State Variables
local isRunning = false
local currentTask = nil
local MovementMode = "Walk"
local Pattern = "Spiral"
local SelectedField = nil

-- UI Setup (Early definition so we can reference elements)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BSS_Macro_UI"
ScreenGui.ResetOnSpawn = false

-- Executor Compatibility
if RunService:IsStudio() then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
else
    pcall(function()
        if gethui then
            ScreenGui.Parent = gethui()
        elseif game:GetService("CoreGui") then
            ScreenGui.Parent = game:GetService("CoreGui")
        else
            ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
    end)
end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 300, 0, 350)
MainFrame.Position = UDim2.new(0.5, -150, 0.5, -175)
MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
Title.Text = "BSS Macro"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 24
Title.Parent = MainFrame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "ToggleButton"
ToggleButton.Size = UDim2.new(0, 50, 0, 25)
ToggleButton.Position = UDim2.new(1, -55, 0, 7)
ToggleButton.Text = "-"
ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ToggleButton.TextColor3 = Color3.new(1, 1, 1)
ToggleButton.Parent = MainFrame

local ContentFrame = Instance.new("Frame")
ContentFrame.Name = "ContentFrame"
ContentFrame.Size = UDim2.new(1, -20, 1, -50)
ContentFrame.Position = UDim2.new(0, 10, 0, 45)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

-- Helper Functions
local function getRoot()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("Humanoid")
end

local function travelTo(targetPos)
    if not isRunning then return end

    local root = getRoot()
    local humanoid = getHumanoid()

    if MovementMode == "Tween" then
        local distance = (root.Position - targetPos).Magnitude
        local speed = 40
        local tweenInfo = TweenInfo.new(distance / speed, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(root, tweenInfo, {CFrame = CFrame.new(targetPos)})
        tween:Play()
        tween.Completed:Wait()
    else -- Walk
        humanoid:MoveTo(targetPos)
        humanoid.MoveToFinished:Wait()
    end
end

local function clampPosition(pos, center)
    local relX = pos.X - center.X
    local relZ = pos.Z - center.Z

    local clampedX = math.clamp(relX, -FIELD_WIDTH/2, FIELD_WIDTH/2)
    local clampedZ = math.clamp(relZ, -FIELD_DEPTH/2, FIELD_DEPTH/2)

    return Vector3.new(center.X + clampedX, pos.Y, center.Z + clampedZ)
end

-- Pattern Logic
local function runSnakePattern(center, startY)
    local minX = center.X - (FIELD_WIDTH / 2)
    local maxX = center.X + (FIELD_WIDTH / 2)
    local minZ = center.Z - (FIELD_DEPTH / 2)
    local maxZ = center.Z + (FIELD_DEPTH / 2)

    local direction = 1

    for z = minZ, maxZ, SNAKE_GAP do
        if not isRunning then break end

        if direction == 1 then
            travelTo(Vector3.new(minX, startY, z))
            travelTo(Vector3.new(maxX, startY, z))
        else
            travelTo(Vector3.new(maxX, startY, z))
            travelTo(Vector3.new(minX, startY, z))
        end

        direction = direction * -1
    end
end

local function mainLoop()
    if not SelectedField then return end

    local center = SelectedField.Position
    local startY = center.Y

    -- Initial travel
    travelTo(center)

    while isRunning do
        if Pattern == "Spiral" then
            local radius = 2
            local angle = 0
            while isRunning and radius <= 20 do
                angle = angle + 1
                radius = radius + 0.5
                local x = center.X + math.cos(angle) * radius
                local z = center.Z + math.sin(angle) * radius
                local target = clampPosition(Vector3.new(x, startY, z), center)
                travelTo(target)
                task.wait()
            end

        elseif Pattern == "Snake" then
            runSnakePattern(center, startY)

        elseif Pattern == "Circle" then
            for angle = 0, 360, 20 do
                if not isRunning then break end
                local rad = math.rad(angle)
                local radius = 12
                local x = center.X + math.cos(rad) * radius
                local z = center.Z + math.sin(rad) * radius
                local target = clampPosition(Vector3.new(x, startY, z), center)
                travelTo(target)
            end

        elseif Pattern == "Figure-8" then
            for t = 0, 6.28, 0.3 do
                if not isRunning then break end
                local scale = 12
                local x = center.X + (scale * math.cos(t))
                local z = center.Z + (scale * math.sin(2 * t) / 2)
                local target = clampPosition(Vector3.new(x, startY, z), center)
                travelTo(target)
            end

        elseif Pattern == "Random" then
            local rX = math.random(-FIELD_WIDTH/2, FIELD_WIDTH/2)
            local rZ = math.random(-FIELD_DEPTH/2, FIELD_DEPTH/2)
            local target = Vector3.new(center.X + rX, startY, center.Z + rZ)
            travelTo(target)
            task.wait(0.5)
        end
        task.wait()
    end
end

-- UI Components (Continued)

-- Field Selector
local FieldLabel = Instance.new("TextLabel")
FieldLabel.Size = UDim2.new(1, 0, 0, 20)
FieldLabel.Text = "Select Field:"
FieldLabel.TextColor3 = Color3.new(1, 1, 1)
FieldLabel.BackgroundTransparency = 1
FieldLabel.Parent = ContentFrame

local FieldScroll = Instance.new("ScrollingFrame")
FieldScroll.Size = UDim2.new(1, 0, 0, 100)
FieldScroll.Position = UDim2.new(0, 0, 0, 25)
FieldScroll.CanvasSize = UDim2.new(0, 0, 0, #FLAT_ZONES * 25)
FieldScroll.Parent = ContentFrame

local FieldButtons = {}
local function updateFieldSelection(btn, fieldData)
    for _, b in pairs(FieldButtons) do
        b.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    end
    btn.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
    SelectedField = fieldData
end

for i, zone in ipairs(FLAT_ZONES) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -10, 0, 25)
    btn.Position = UDim2.new(0, 5, 0, (i-1) * 25)
    btn.Text = zone.Name
    btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Parent = FieldScroll

    btn.MouseButton1Click:Connect(function()
        updateFieldSelection(btn, zone)
    end)
    table.insert(FieldButtons, btn)
end

-- Movement Toggle
local MoveToggleBtn = Instance.new("TextButton")
MoveToggleBtn.Size = UDim2.new(0.45, 0, 0, 30)
MoveToggleBtn.Position = UDim2.new(0, 0, 0, 135)
MoveToggleBtn.Text = "Mode: Walk"
MoveToggleBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
MoveToggleBtn.TextColor3 = Color3.new(1, 1, 1)
MoveToggleBtn.Parent = ContentFrame

MoveToggleBtn.MouseButton1Click:Connect(function()
    if MovementMode == "Walk" then
        MovementMode = "Tween"
    else
        MovementMode = "Walk"
    end
    MoveToggleBtn.Text = "Mode: " .. MovementMode
end)

-- Pattern Selector
local PatternBtn = Instance.new("TextButton")
PatternBtn.Size = UDim2.new(0.45, 0, 0, 30)
PatternBtn.Position = UDim2.new(0.55, 0, 0, 135)
PatternBtn.Text = "Pattern: Spiral"
PatternBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
PatternBtn.TextColor3 = Color3.new(1, 1, 1)
PatternBtn.Parent = ContentFrame

local Patterns = {"Spiral", "Snake", "Circle", "Figure-8", "Random"}
local PatternIndex = 1

PatternBtn.MouseButton1Click:Connect(function()
    PatternIndex = PatternIndex + 1
    if PatternIndex > #Patterns then PatternIndex = 1 end
    Pattern = Patterns[PatternIndex]
    PatternBtn.Text = "Pattern: " .. Pattern
end)

-- Start/Stop Button
local StartStopBtn = Instance.new("TextButton")
StartStopBtn.Size = UDim2.new(1, 0, 0, 40)
StartStopBtn.Position = UDim2.new(0, 0, 1, -40)
StartStopBtn.Text = "START"
StartStopBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
StartStopBtn.TextColor3 = Color3.new(1, 1, 1)
StartStopBtn.Font = Enum.Font.SourceSansBold
StartStopBtn.TextSize = 20
StartStopBtn.Parent = ContentFrame

StartStopBtn.MouseButton1Click:Connect(function()
    if isRunning then
        -- Stop
        isRunning = false
        StartStopBtn.Text = "START"
        StartStopBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)

        -- Instant Stop Logic
        if currentTask then
            task.cancel(currentTask)
            currentTask = nil
        end

        -- Stop character movement instantly
        local root = getRoot()
        local humanoid = getHumanoid()
        humanoid:MoveTo(root.Position) -- Stop walking

        -- Cancel any running tweens?
        -- TweenService doesn't have a "StopAll" but cancelling the task stops the loop creating new ones.
        -- If a tween is currently playing, we can cancel it if we tracked it, but task.cancel kills the thread waiting on it.

    else
        -- Start
        if not SelectedField then
            StartStopBtn.Text = "SELECT FIELD"
            task.wait(1)
            StartStopBtn.Text = "START"
            return
        end

        isRunning = true
        StartStopBtn.Text = "STOP"
        StartStopBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)

        currentTask = task.spawn(mainLoop)
    end
end)

-- Minimize Logic
local minimized = false
ToggleButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        ContentFrame.Visible = false
        MainFrame.Size = UDim2.new(0, 300, 0, 40)
        ToggleButton.Text = "+"
    else
        ContentFrame.Visible = true
        MainFrame.Size = UDim2.new(0, 300, 0, 350)
        ToggleButton.Text = "-"
    end
end)

-- Cleanup Handler
local function cleanup()
    isRunning = false
    if currentTask then task.cancel(currentTask) end
    ScreenGui:Destroy()
end

-- Respawn Logic
LocalPlayer.CharacterAdded:Connect(function()
    isRunning = false
    StartStopBtn.Text = "START"
    StartStopBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    if currentTask then task.cancel(currentTask) end
end)
