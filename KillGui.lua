--[[
    Kill Player GUI - Delta Executor
    Меню для уничтожения (респавна) ближайшего игрока.
    Подойди к игроку и нажми кнопку "KILL" (или хоткей E).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Удаляем старое меню если есть
if game.CoreGui:FindFirstChild("KillGui") then
    game.CoreGui:FindFirstChild("KillGui"):Destroy()
end

-- Настройки
local SETTINGS = {
    KillDistance     = 15,    -- Макс. дистанция для атаки (studs)
    AutoTarget       = true,  -- Авто-выбор ближайшего
    TeleportToPlayer = true,  -- Телепорт к жертве перед ударом
}

------------------------------------------------------------
-- Вспомогательные функции
------------------------------------------------------------

local function getMyRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function getNearestPlayer()
    local myRoot = getMyRoot()
    if not myRoot then return nil end

    local nearest, bestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local dist = (hrp.Position - myRoot.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    nearest = plr
                end
            end
        end
    end
    return nearest, bestDist
end

local function killPlayer(target)
    if not target or not target.Character then
        return false, "Нет цели"
    end
    local myChar = LocalPlayer.Character
    local myRoot = getMyRoot()
    local myHum  = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local tHrp   = target.Character:FindFirstChild("HumanoidRootPart")
    local tHum   = target.Character:FindFirstChildOfClass("Humanoid")
    if not (myRoot and myHum and tHrp and tHum) then
        return false, "Проверь персонажа"
    end

    local dist = (tHrp.Position - myRoot.Position).Magnitude
    if dist > SETTINGS.KillDistance and not SETTINGS.TeleportToPlayer then
        return false, ("Слишком далеко (%.1f)"):format(dist)
    end

    -- Сохраняем позицию, чтобы вернуться
    local savedCFrame = myRoot.CFrame

    if SETTINGS.TeleportToPlayer then
        -- Несколько "ударов" телепортом - распространённый трюк, чтобы прокнул
        -- любой touch-damage / kill-brick / батлграунды и т.п.
        for i = 1, 5 do
            if myRoot and myRoot.Parent and tHrp and tHrp.Parent then
                myRoot.CFrame = tHrp.CFrame
            end
            task.wait()
        end
    end

    -- Стандартные методы "убийства". Сработает только там, где разрешает игра.
    pcall(function() tHum:TakeDamage(tHum.MaxHealth) end)
    pcall(function() target.Character:BreakJoints() end)

    -- Возврат на исходную позицию
    task.wait(0.1)
    if myRoot and myRoot.Parent then
        myRoot.CFrame = savedCFrame
    end

    return true, "Цель уничтожена: " .. target.Name
end

------------------------------------------------------------
-- GUI
------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "KillGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- В Delta лучше класть в CoreGui
local parentGui = game:GetService("CoreGui")
pcall(function() gui.Parent = parentGui end)
if not gui.Parent then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- Главный фрейм
local main = Instance.new("Frame", gui)
main.Name = "Main"
main.Size = UDim2.new(0, 280, 0, 240)
main.Position = UDim2.new(0.5, -140, 0.5, -120)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true

local corner = Instance.new("UICorner", main)
corner.CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(255, 60, 60)
stroke.Thickness = 1.5

-- Заголовок
local title = Instance.new("TextLabel", main)
title.Size = UDim2.new(1, 0, 0, 35)
title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
title.BorderSizePixel = 0
title.Text = "  💀  KILL MENU"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 80, 80)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

-- Кнопка свернуть
local minBtn = Instance.new("TextButton", title)
minBtn.Size = UDim2.new(0, 30, 0, 30)
minBtn.Position = UDim2.new(1, -66, 0, 2)
minBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

-- Кнопка закрыть
local closeBtn = Instance.new("TextButton", title)
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -33, 0, 2)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Информация о цели
local targetLabel = Instance.new("TextLabel", main)
targetLabel.Size = UDim2.new(1, -20, 0, 22)
targetLabel.Position = UDim2.new(0, 10, 0, 45)
targetLabel.BackgroundTransparency = 1
targetLabel.Text = "Цель: ---"
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
targetLabel.Font = Enum.Font.Gotham
targetLabel.TextSize = 14

local distLabel = Instance.new("TextLabel", main)
distLabel.Size = UDim2.new(1, -20, 0, 22)
distLabel.Position = UDim2.new(0, 10, 0, 70)
distLabel.BackgroundTransparency = 1
distLabel.Text = "Дистанция: ---"
distLabel.TextXAlignment = Enum.TextXAlignment.Left
distLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
distLabel.Font = Enum.Font.Gotham
distLabel.TextSize = 13

-- Кнопка KILL
local killBtn = Instance.new("TextButton", main)
killBtn.Size = UDim2.new(1, -20, 0, 55)
killBtn.Position = UDim2.new(0, 10, 0, 105)
killBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
killBtn.Text = "💥 KILL ближайшего игрока"
killBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
killBtn.Font = Enum.Font.GothamBold
killBtn.TextSize = 15
killBtn.AutoButtonColor = true
Instance.new("UICorner", killBtn).CornerRadius = UDim.new(0, 8)

-- Тогл "Телепорт"
local tpToggle = Instance.new("TextButton", main)
tpToggle.Size = UDim2.new(0.5, -15, 0, 30)
tpToggle.Position = UDim2.new(0, 10, 0, 170)
tpToggle.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
tpToggle.Text = "TP: ON"
tpToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
tpToggle.Font = Enum.Font.GothamBold
tpToggle.TextSize = 13
Instance.new("UICorner", tpToggle).CornerRadius = UDim.new(0, 6)

-- Тогл "Авто-цель"
local autoToggle = Instance.new("TextButton", main)
autoToggle.Size = UDim2.new(0.5, -15, 0, 30)
autoToggle.Position = UDim2.new(0.5, 5, 0, 170)
autoToggle.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
autoToggle.Text = "AUTO: ON"
autoToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
autoToggle.Font = Enum.Font.GothamBold
autoToggle.TextSize = 13
Instance.new("UICorner", autoToggle).CornerRadius = UDim.new(0, 6)

-- Статус
local statusLabel = Instance.new("TextLabel", main)
statusLabel.Size = UDim2.new(1, -20, 0, 22)
statusLabel.Position = UDim2.new(0, 10, 1, -28)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Готов. Хоткей: [E]"
statusLabel.TextColor3 = Color3.fromRGB(120, 220, 120)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

------------------------------------------------------------
-- Логика
------------------------------------------------------------

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    local size = minimized and UDim2.new(0, 280, 0, 35) or UDim2.new(0, 280, 0, 240)
    main:TweenSize(size, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
end)

closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

tpToggle.MouseButton1Click:Connect(function()
    SETTINGS.TeleportToPlayer = not SETTINGS.TeleportToPlayer
    tpToggle.Text = "TP: " .. (SETTINGS.TeleportToPlayer and "ON" or "OFF")
    tpToggle.BackgroundColor3 = SETTINGS.TeleportToPlayer
        and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(120, 40, 40)
end)

autoToggle.MouseButton1Click:Connect(function()
    SETTINGS.AutoTarget = not SETTINGS.AutoTarget
    autoToggle.Text = "AUTO: " .. (SETTINGS.AutoTarget and "ON" or "OFF")
    autoToggle.BackgroundColor3 = SETTINGS.AutoTarget
        and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(120, 40, 40)
end)

local function setStatus(text, color)
    statusLabel.Text = text
    statusLabel.TextColor3 = color or Color3.fromRGB(120, 220, 120)
end

local busy = false
local function doKill()
    if busy then return end
    busy = true
    local target = getNearestPlayer()
    if not target then
        setStatus("Игроки не найдены", Color3.fromRGB(255, 120, 120))
        busy = false
        return
    end
    local ok, msg = killPlayer(target)
    setStatus(msg, ok and Color3.fromRGB(120, 220, 120) or Color3.fromRGB(255, 150, 80))
    task.wait(0.5)
    busy = false
end

killBtn.MouseButton1Click:Connect(function()
    task.spawn(doKill)
end)

-- Хоткей E
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.E then
        task.spawn(doKill)
    end
end)

-- Обновление информации о цели
RunService.Heartbeat:Connect(function()
    local target, dist = getNearestPlayer()
    if target then
        targetLabel.Text = "Цель: " .. target.Name
        distLabel.Text   = ("Дистанция: %.1f studs"):format(dist or 0)
        distLabel.TextColor3 = (dist and dist <= SETTINGS.KillDistance)
            and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 180, 80)
    else
        targetLabel.Text = "Цель: ---"
        distLabel.Text   = "Дистанция: ---"
    end
end)

setStatus("GUI загружен. Жми KILL или [E]")
print("[KillGui] Загружен. Игрок:", LocalPlayer.Name)
