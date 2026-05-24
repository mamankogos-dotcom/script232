--[[
    Kill Player GUI - Natural Disaster Survival (Delta Executor)
    Метод: Fling (физический выброс игрока в небо/за карту).
    
    Как пользоваться:
        1. Запусти скрипт после спавна на острове.
        2. В меню выбери игрока (или включи AUTO - ближайший).
        3. Нажми "FLING" или хоткей [E].
        4. Жертву выбросит вверх с огромной скоростью - она умрёт от падения
           или вылетит за карту.

    ВНИМАНИЕ: пока активен Fling, твой персонаж сам "ломается" (это часть трюка).
    После броска нажми "RESET" или подожди - скрипт вернёт тебя в нормальное
    состояние и зарелоадит. В лобби fling часто не работает (там анти-урон) -
    делай это уже на острове во время раунда.
]]

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local LocalPlayer      = Players.LocalPlayer

if game.CoreGui:FindFirstChild("KillGui") then
    game.CoreGui.KillGui:Destroy()
end

local SETTINGS = {
    AutoTarget   = true,
    FlingPower   = 90000, -- сила выброса (чем больше - тем выше летит)
    FlingTime    = 0.7,   -- сколько секунд держать fling
}

------------------------------------------------------------
-- Утилиты
------------------------------------------------------------

local function getMyChar()
    local c = LocalPlayer.Character
    if not c then return nil end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function getNearestPlayer()
    local _, myRoot = getMyChar()
    if not myRoot then return nil end
    local best, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (hrp.Position - myRoot.Position).Magnitude
                if d < bestDist then bestDist, best = d, p end
            end
        end
    end
    return best, bestDist
end

------------------------------------------------------------
-- FLING (классический "void/space fling" для NDS)
-- Идея: даём собственному HumanoidRootPart огромный угловой импульс
-- и ставим CFrame в позицию жертвы. Из-за того, как Roblox передаёт
-- физику между клиентами при коллизии, импульс передаётся жертве
-- и её выбрасывает в небо. Сервер с FilteringEnabled этому не мешает,
-- т.к. движение твоего HRP легально, а коллизия рассчитывается физикой.
------------------------------------------------------------

local flinging = false

local function flingPlayer(target)
    if flinging then return false, "Уже летит..." end
    if not target or not target.Character then return false, "Нет цели" end

    local myChar, myRoot, myHum = getMyChar()
    local tHrp = target.Character:FindFirstChild("HumanoidRootPart")
    local tHum = target.Character:FindFirstChildOfClass("Humanoid")
    if not (myRoot and myHum and tHrp and tHum) then
        return false, "Проверь персонажа"
    end
    if tHum.Sit then
        pcall(function() tHum.Sit = false end) -- иначе flick не сработает
    end

    flinging = true
    local saved = myRoot.CFrame

    -- Снимаем коллизии и массу с собственных частей,
    -- иначе игра швырнёт нас, а не цель.
    local restore = {}
    for _, v in ipairs(myChar:GetDescendants()) do
        if v:IsA("BasePart") then
            restore[v] = { canCollide = v.CanCollide, massless = v.Massless }
            v.CanCollide = false
            v.Massless   = true
        end
    end
    -- Отключаем физику Humanoid - меньше "брыкается"
    pcall(function()
        myHum:ChangeState(Enum.HumanoidStateType.Physics)
        myHum.PlatformStand = true
    end)

    -- Сам fling: огромная угловая и линейная скорость + позиция жертвы
    local stop = false
    task.spawn(function()
        local t0 = tick()
        while not stop and tick() - t0 < SETTINGS.FlingTime do
            if not (myRoot and myRoot.Parent and tHrp and tHrp.Parent) then break end
            myRoot.Velocity    = Vector3.new(SETTINGS.FlingPower, SETTINGS.FlingPower, SETTINGS.FlingPower)
            myRoot.RotVelocity = Vector3.new(SETTINGS.FlingPower, SETTINGS.FlingPower, SETTINGS.FlingPower)
            myRoot.CFrame      = tHrp.CFrame
            RunService.Heartbeat:Wait()
        end
    end)

    task.wait(SETTINGS.FlingTime)
    stop = true

    -- Восстанавливаемся
    pcall(function()
        myHum.PlatformStand = false
        myHum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)
    for v, props in pairs(restore) do
        if v and v.Parent then
            v.CanCollide = props.canCollide
            v.Massless   = props.massless
        end
    end

    if myRoot and myRoot.Parent then
        myRoot.Velocity    = Vector3.new()
        myRoot.RotVelocity = Vector3.new()
        myRoot.CFrame      = saved + Vector3.new(0, 5, 0)
    end

    flinging = false
    return true, "Fling -> " .. target.Name
end

local function resetCharacter()
    local _, _, hum = getMyChar()
    if hum then
        hum.Health = 0
    else
        LocalPlayer.Character = nil
    end
end

------------------------------------------------------------
-- GUI
------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "KillGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 300, 0, 320)
main.Position = UDim2.new(0.5, -150, 0.5, -160)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(255, 80, 80)
stroke.Thickness = 1.5

local title = Instance.new("TextLabel", main)
title.Size = UDim2.new(1, 0, 0, 36)
title.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
title.Text = "  🌪  NDS KILL MENU"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 90, 90)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

local closeBtn = Instance.new("TextButton", title)
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -33, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local minBtn = Instance.new("TextButton", title)
minBtn.Size = UDim2.new(0, 30, 0, 30)
minBtn.Position = UDim2.new(1, -66, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

-- Лейблы цели
local targetLbl = Instance.new("TextLabel", main)
targetLbl.Size = UDim2.new(1, -20, 0, 22)
targetLbl.Position = UDim2.new(0, 10, 0, 46)
targetLbl.BackgroundTransparency = 1
targetLbl.Text = "Цель: ---"
targetLbl.TextXAlignment = Enum.TextXAlignment.Left
targetLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
targetLbl.Font = Enum.Font.GothamBold
targetLbl.TextSize = 14

local distLbl = Instance.new("TextLabel", main)
distLbl.Size = UDim2.new(1, -20, 0, 22)
distLbl.Position = UDim2.new(0, 10, 0, 70)
distLbl.BackgroundTransparency = 1
distLbl.Text = "Дистанция: ---"
distLbl.TextXAlignment = Enum.TextXAlignment.Left
distLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
distLbl.Font = Enum.Font.Gotham
distLbl.TextSize = 13

-- Список игроков (TextBox для выбора по имени)
local nameBox = Instance.new("TextBox", main)
nameBox.Size = UDim2.new(1, -20, 0, 30)
nameBox.Position = UDim2.new(0, 10, 0, 100)
nameBox.PlaceholderText = "Имя игрока (пусто = ближайший)"
nameBox.Text = ""
nameBox.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
nameBox.TextColor3 = Color3.new(1,1,1)
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 13
nameBox.ClearTextOnFocus = false
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 6)

-- Кнопка FLING
local flingBtn = Instance.new("TextButton", main)
flingBtn.Size = UDim2.new(1, -20, 0, 50)
flingBtn.Position = UDim2.new(0, 10, 0, 140)
flingBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
flingBtn.Text = "🌪 FLING (выбросить)"
flingBtn.TextColor3 = Color3.new(1,1,1)
flingBtn.Font = Enum.Font.GothamBold
flingBtn.TextSize = 16
Instance.new("UICorner", flingBtn).CornerRadius = UDim.new(0, 8)

-- Слайдер силы (просто +/-)
local powerLbl = Instance.new("TextLabel", main)
powerLbl.Size = UDim2.new(1, -20, 0, 20)
powerLbl.Position = UDim2.new(0, 10, 0, 198)
powerLbl.BackgroundTransparency = 1
powerLbl.Text = "Сила: " .. SETTINGS.FlingPower
powerLbl.TextXAlignment = Enum.TextXAlignment.Left
powerLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
powerLbl.Font = Enum.Font.Gotham
powerLbl.TextSize = 12

local minusBtn = Instance.new("TextButton", main)
minusBtn.Size = UDim2.new(0, 30, 0, 25)
minusBtn.Position = UDim2.new(1, -75, 0, 196)
minusBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
minusBtn.Text = "-"
minusBtn.TextColor3 = Color3.new(1,1,1)
minusBtn.Font = Enum.Font.GothamBold
minusBtn.TextSize = 16
Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 4)

local plusBtn = Instance.new("TextButton", main)
plusBtn.Size = UDim2.new(0, 30, 0, 25)
plusBtn.Position = UDim2.new(1, -40, 0, 196)
plusBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
plusBtn.Text = "+"
plusBtn.TextColor3 = Color3.new(1,1,1)
plusBtn.Font = Enum.Font.GothamBold
plusBtn.TextSize = 16
Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 4)

-- Тогл AUTO
local autoBtn = Instance.new("TextButton", main)
autoBtn.Size = UDim2.new(0.5, -15, 0, 30)
autoBtn.Position = UDim2.new(0, 10, 0, 228)
autoBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
autoBtn.Text = "AUTO: ON"
autoBtn.TextColor3 = Color3.new(1,1,1)
autoBtn.Font = Enum.Font.GothamBold
autoBtn.TextSize = 13
Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 6)

-- Reset character
local resetBtn = Instance.new("TextButton", main)
resetBtn.Size = UDim2.new(0.5, -15, 0, 30)
resetBtn.Position = UDim2.new(0.5, 5, 0, 228)
resetBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 160)
resetBtn.Text = "🔄 RESET ME"
resetBtn.TextColor3 = Color3.new(1,1,1)
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 13
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)

-- Статус
local statusLbl = Instance.new("TextLabel", main)
statusLbl.Size = UDim2.new(1, -20, 0, 40)
statusLbl.Position = UDim2.new(0, 10, 1, -45)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Готов. Хоткей: [E] - fling, [R] - reset"
statusLbl.TextColor3 = Color3.fromRGB(120, 220, 120)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextWrapped = true
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextYAlignment = Enum.TextYAlignment.Top

------------------------------------------------------------
-- Обработчики
------------------------------------------------------------

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    main:TweenSize(minimized and UDim2.new(0,300,0,36) or UDim2.new(0,300,0,320),
        Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

autoBtn.MouseButton1Click:Connect(function()
    SETTINGS.AutoTarget = not SETTINGS.AutoTarget
    autoBtn.Text = "AUTO: " .. (SETTINGS.AutoTarget and "ON" or "OFF")
    autoBtn.BackgroundColor3 = SETTINGS.AutoTarget
        and Color3.fromRGB(40,120,60) or Color3.fromRGB(120,40,40)
end)

minusBtn.MouseButton1Click:Connect(function()
    SETTINGS.FlingPower = math.max(10000, SETTINGS.FlingPower - 10000)
    powerLbl.Text = "Сила: " .. SETTINGS.FlingPower
end)
plusBtn.MouseButton1Click:Connect(function()
    SETTINGS.FlingPower = math.min(500000, SETTINGS.FlingPower + 10000)
    powerLbl.Text = "Сила: " .. SETTINGS.FlingPower
end)

resetBtn.MouseButton1Click:Connect(resetCharacter)

local function setStatus(text, color)
    statusLbl.Text = text
    statusLbl.TextColor3 = color or Color3.fromRGB(120, 220, 120)
end

local function resolveTarget()
    local typed = nameBox.Text and nameBox.Text:gsub("^%s+",""):gsub("%s+$","") or ""
    if typed ~= "" then
        local low = typed:lower()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and (p.Name:lower():sub(1, #low) == low
               or (p.DisplayName and p.DisplayName:lower():sub(1, #low) == low)) then
                return p
            end
        end
        return nil, "Игрок '" .. typed .. "' не найден"
    end
    if SETTINGS.AutoTarget then
        return getNearestPlayer()
    end
    return nil, "Введи имя или включи AUTO"
end

local function doFling()
    local target, err = resolveTarget()
    if not target then
        setStatus(err or "Нет цели", Color3.fromRGB(255,120,120))
        return
    end
    setStatus("Fling -> " .. target.Name .. " ...", Color3.fromRGB(255,200,80))
    local ok, msg = flingPlayer(target)
    setStatus(msg, ok and Color3.fromRGB(120,220,120) or Color3.fromRGB(255,150,80))
end

flingBtn.MouseButton1Click:Connect(function() task.spawn(doFling) end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.E then
        task.spawn(doFling)
    elseif input.KeyCode == Enum.KeyCode.R then
        resetCharacter()
    end
end)

-- Реселект персонажа после respawn
LocalPlayer.CharacterAdded:Connect(function() flinging = false end)

-- Обновление инфо
RunService.Heartbeat:Connect(function()
    local target, dist
    local typed = nameBox.Text and nameBox.Text:gsub("^%s+",""):gsub("%s+$","") or ""
    if typed ~= "" then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Name:lower():sub(1,#typed) == typed:lower() then
                target = p
                local _, myRoot = getMyChar()
                local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if myRoot and hrp then dist = (myRoot.Position - hrp.Position).Magnitude end
                break
            end
        end
    else
        target, dist = getNearestPlayer()
    end
    if target then
        targetLbl.Text = "Цель: " .. target.Name
        distLbl.Text   = dist and ("Дистанция: %.1f studs"):format(dist) or "Дистанция: ---"
    else
        targetLbl.Text = "Цель: ---"
        distLbl.Text   = "Дистанция: ---"
    end
end)

setStatus("GUI загружен. Жми FLING или [E].")
print("[NDS-KillGui] Загружен. Игрок:", LocalPlayer.Name)
