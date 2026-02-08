local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer

-- Load Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- Configuration
local FIELD_WIDTH = 30
local FIELD_DEPTH = 20
local SNAKE_GAP = 3 -- Tighter gap for efficiency

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

-- Flatten Zones for Dropdown
local FLAT_ZONES = {}
local ZONE_NAMES = {}
for category, fields in pairs(ZONES) do
    for name, pos in pairs(fields) do
        table.insert(FLAT_ZONES, {Name = name, Position = pos})
        table.insert(ZONE_NAMES, name)
    end
end
table.sort(ZONE_NAMES)

-- State Variables
local isRunning = false
local currentTask = nil
local MovementMode = "Walk"
local Pattern = "Spiral"
local SelectedField = nil -- Will hold the Vector3 position
local TweenSpeed = 30
local AutoSprint = false

-- Helper Functions
local function getRoot()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("Humanoid")
end

local function getFieldPosition(name)
    for _, z in ipairs(FLAT_ZONES) do
        if z.Name == name then return z.Position end
    end
    return nil
end

-- Advanced Movement Logic
local function travelTo(targetPos, expectedField)
    if not isRunning then return end

    -- Fast seamless check
    if expectedField and SelectedField ~= expectedField then return end

    local root = getRoot()
    local humanoid = getHumanoid()

    -- Auto-Sprint
    if AutoSprint then
        humanoid.WalkSpeed = 24
    else
        humanoid.WalkSpeed = 16
    end

    if MovementMode == "Tween" then
        local distance = (root.Position - targetPos).Magnitude
        local duration = distance / TweenSpeed

        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(root, tweenInfo, {CFrame = CFrame.new(targetPos)})
        tween:Play()
        tween.Completed:Wait()

    else -- Walk with Pathfinding
        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentJumpHeight = 10,
            WaypointSpacing = 4
        })

        local success, errorMessage = pcall(function()
            path:ComputeAsync(root.Position, targetPos)
        end)

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            for _, waypoint in ipairs(waypoints) do
                if not isRunning then break end
                if expectedField and SelectedField ~= expectedField then break end -- Seamless abort

                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end
                humanoid:MoveTo(waypoint.Position)

                -- Wait for arrival at waypoint
                local timeOut = 0
                while (root.Position - waypoint.Position).Magnitude > 3 and timeOut < 5 do
                    task.wait(0.1)
                    timeOut = timeOut + 0.1
                end
            end
        else
            -- Fallback if pathfinding fails
            humanoid:MoveTo(targetPos)
            humanoid.MoveToFinished:Wait()
        end
    end
end

local function clampPosition(pos, center)
    local relX = pos.X - center.X
    local relZ = pos.Z - center.Z

    local clampedX = math.clamp(relX, -FIELD_WIDTH/2, FIELD_WIDTH/2)
    local clampedZ = math.clamp(relZ, -FIELD_DEPTH/2, FIELD_DEPTH/2)

    return Vector3.new(center.X + clampedX, pos.Y, center.Z + clampedZ)
end

-- Pattern Logic with Seamless Transition Checks
local function checkState(originalField, originalPattern)
    if not isRunning then return false end
    if SelectedField ~= originalField then return false end
    if Pattern ~= originalPattern then return false end
    return true
end

local function runSnakePattern(center, startY)
    local minX = center.X - (FIELD_WIDTH / 2)
    local maxX = center.X + (FIELD_WIDTH / 2)
    local minZ = center.Z - (FIELD_DEPTH / 2)
    local maxZ = center.Z + (FIELD_DEPTH / 2)

    local direction = 1
    local myField = SelectedField
    local myPattern = Pattern

    for z = minZ, maxZ, SNAKE_GAP do
        if not checkState(myField, myPattern) then return end

        if direction == 1 then
            travelTo(Vector3.new(minX, startY, z), myField)
            if not checkState(myField, myPattern) then return end
            travelTo(Vector3.new(maxX, startY, z), myField)
        else
            travelTo(Vector3.new(maxX, startY, z), myField)
            if not checkState(myField, myPattern) then return end
            travelTo(Vector3.new(minX, startY, z), myField)
        end

        direction = direction * -1
    end
end

local function runSpiralPattern(center, startY)
    local radius = 2
    local angle = 0
    local myField = SelectedField
    local myPattern = Pattern

    while isRunning and radius <= 20 do
        if not checkState(myField, myPattern) then return end

        angle = angle + 1
        radius = radius + 0.5
        local x = center.X + math.cos(angle) * radius
        local z = center.Z + math.sin(angle) * radius
        local target = clampPosition(Vector3.new(x, startY, z), center)

        travelTo(target, myField)
        task.wait()
    end
end

local function runCirclePattern(center, startY)
    local myField = SelectedField
    local myPattern = Pattern

    for angle = 0, 360, 20 do
        if not checkState(myField, myPattern) then return end

        local rad = math.rad(angle)
        local radius = 12
        local x = center.X + math.cos(rad) * radius
        local z = center.Z + math.sin(rad) * radius
        local target = clampPosition(Vector3.new(x, startY, z), center)

        travelTo(target, myField)
    end
end

local function runFigure8Pattern(center, startY)
    local myField = SelectedField
    local myPattern = Pattern

    for t = 0, 6.28, 0.3 do
        if not checkState(myField, myPattern) then return end

        local scale = 12
        local x = center.X + (scale * math.cos(t))
        local z = center.Z + (scale * math.sin(2 * t) / 2)
        local target = clampPosition(Vector3.new(x, startY, z), center)

        travelTo(target, myField)
    end
end

local function runRandomPattern(center, startY)
    local myField = SelectedField
    local myPattern = Pattern

    if not checkState(myField, myPattern) then return end

    local rX = math.random(-FIELD_WIDTH/2, FIELD_WIDTH/2)
    local rZ = math.random(-FIELD_DEPTH/2, FIELD_DEPTH/2)
    local target = Vector3.new(center.X + rX, startY, center.Z + rZ)

    travelTo(target, myField)
    task.wait(0.5)
end

local function mainLoop()
    while isRunning do
        if not SelectedField then
            task.wait(1)
            continue
        end

        local center = SelectedField
        local startY = center.Y

        -- Initial travel to center (if far away)
        -- We can just let the pattern handle it, but starting at center is good.
        -- But if we are seamless switching, we might already be there.
        -- Let's just run the pattern. The first point of the pattern will trigger travelTo.

        if Pattern == "Spiral" then
            runSpiralPattern(center, startY)
        elseif Pattern == "Snake" then
            runSnakePattern(center, startY)
        elseif Pattern == "Circle" then
            runCirclePattern(center, startY)
        elseif Pattern == "Figure-8" then
            runFigure8Pattern(center, startY)
        elseif Pattern == "Random" then
            runRandomPattern(center, startY)
        end

        task.wait()
    end
end

-- Anti-Stuck Loop
task.spawn(function()
    local lastPos = nil
    while true do
        task.wait(2)
        if isRunning then
            local root = getRoot()
            if lastPos and (root.Position - lastPos).Magnitude < 2 then
                -- Stuck!
                local humanoid = getHumanoid()
                humanoid.Jump = true

                -- Unstuck move
                local randomOffset = Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
                humanoid:MoveTo(root.Position + randomOffset)
                task.wait(0.5)
            end
            lastPos = root.Position
        end
    end
end)

-- UI Setup (Rayfield)
local Window = Rayfield:CreateWindow({
   Name = "BSS Macro V2.0",
   LoadingTitle = "Loading Macro...",
   LoadingSubtitle = "By Jules",
   ConfigurationSaving = {
      Enabled = false,
   },
   KeySystem = false,
})

local MainTab = Window:CreateTab("Main", 4483362458)

local Section = MainTab:CreateSection("Configuration")

local FieldDropdown = MainTab:CreateDropdown({
   Name = "Select Field",
   Options = ZONE_NAMES,
   CurrentOption = "",
   Flag = "FieldDropdown",
   Callback = function(Option)
       local fieldName = Option[1]
       SelectedField = getFieldPosition(fieldName)
   end,
})

local PatternDropdown = MainTab:CreateDropdown({
   Name = "Pattern",
   Options = {"Spiral", "Snake", "Circle", "Figure-8", "Random"},
   CurrentOption = "Spiral",
   Flag = "PatternDropdown",
   Callback = function(Option)
       Pattern = Option[1]
   end,
})

local ModeToggle = MainTab:CreateToggle({
   Name = "Tween Mode",
   CurrentValue = false,
   Flag = "ModeToggle",
   Callback = function(Value)
       if Value then
           MovementMode = "Tween"
       else
           MovementMode = "Walk"
       end
   end,
})

local SpeedSlider = MainTab:CreateSlider({
   Name = "Tween Speed",
   Range = {10, 100},
   Increment = 1,
   Suffix = "Studs/s",
   CurrentValue = 30,
   Flag = "SpeedSlider",
   Callback = function(Value)
       TweenSpeed = Value
   end,
})

local SprintToggle = MainTab:CreateToggle({
   Name = "Auto-Sprint",
   CurrentValue = false,
   Flag = "SprintToggle",
   Callback = function(Value)
       AutoSprint = Value
   end,
})

local ControlSection = MainTab:CreateSection("Control")

local ToggleBtn = MainTab:CreateButton({
   Name = "START / STOP",
   Callback = function()
       if isRunning then
           -- Stop
           isRunning = false
           Rayfield:Notify({Title = "Status", Content = "Macro Stopped", Duration = 3})
           if currentTask then
               task.cancel(currentTask)
               currentTask = nil
           end

           -- Stop Character
           local root = getRoot()
           local humanoid = getHumanoid()
           humanoid:MoveTo(root.Position)
       else
           -- Start
           if not SelectedField then
               Rayfield:Notify({Title = "Error", Content = "Please select a field first!", Duration = 3})
               return
           end

           isRunning = true
           Rayfield:Notify({Title = "Status", Content = "Macro Started", Duration = 3})
           currentTask = task.spawn(mainLoop)
       end
   end,
})

-- Handle Character Respawn
LocalPlayer.CharacterAdded:Connect(function()
    isRunning = false
    if currentTask then task.cancel(currentTask) end
end)
