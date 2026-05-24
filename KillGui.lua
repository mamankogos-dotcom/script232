--[[
    Auto-Block + Auto-Attack GUI (Delta Executor)
    Под игру, использующую remote: Character.Network
        FDown / FUp     -> блок
        M1Down / M1Up   -> удар
        Skill {Number}  -> 1..4 скиллы

    Логика:
      * Слушаем анимации каждого вражеского Animator.
      * Когда враг (из вайтлиста) в радиусе и смотрит на нас начинает
        анимацию (любую, кроме walk/idle) - мгновенно жмём FDown.
      * Через короткое окно отпускаем FUp и сразу бьём M1 (комбо).
]]

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local LocalPlayer      = Players.LocalPlayer

if game.CoreGui:FindFirstChild("AutoBlockGui") then
    game.CoreGui.AutoBlockGui:Destroy()
end

------------------------------------------------------------
-- Настройки
------------------------------------------------------------
local CFG = {
    AutoBlock     = true,
    AutoAttack    = true,
    Radius        = 14,        -- studs
    BlockHold     = 0.18,      -- сколько держать блок
    AttackCombo   = 4,         -- сколько M1 после блока
    AttackDelay   = 0.08,      -- пауза между ударами
    FacingDot     = 0.35,      -- насколько враг должен смотреть на нас (0..1)
    Cooldown      = 0.35,      -- мин. пауза между срабатываниями (анти-спам)
    IgnoreAnims   = {          -- игнорируем эти ключевые слова в имени анимы
        ["walk"]=true, ["run"]=true, ["idle"]=true, ["jump"]=true,
        ["fall"]=true, ["climb"]=true, ["sit"]=true, ["swim"]=true,
        ["land"]=true, ["pose"]=true, ["dance"]=true,
    },
}

local Whitelist = {} -- [UserId] = true (кого автоблочить/бить). По умолчанию все.

------------------------------------------------------------
-- Network firer
------------------------------------------------------------
local function getNetwork()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("Network")
end

local function fire(payload)
    local net = getNetwork()
    if not net then return end
    pcall(function() net:FireServer(payload) end)
end

local function blockDown() fire({Request = "FDown"}) end
local function blockUp()   fire({Request = "FUp"})   end
local function m1Down()    fire({Request = "M1Down"}) end
local function m1Up()      fire({Request = "M1Up"})   end
local function useSkill(n) fire({Number = tostring(n), Request = "Skill"}) end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function getMyRoot()
    local c = LocalPlayer.Character
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

local function isWhitelisted(plr)
    -- По умолчанию (если вайтлист пуст) - все враги
    if next(Whitelist) == nil then return true end
    return Whitelist[plr.UserId] == true
end

local function distAndFacing(enemy)
    local myRoot = getMyRoot()
    if not myRoot or not enemy.Character then return nil, nil end
    local hrp = enemy.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    local d = (hrp.Position - myRoot.Position).Magnitude
    local toMe = (myRoot.Position - hrp.Position)
    if toMe.Magnitude < 0.001 then return d, 1 end
    local dot = hrp.CFrame.LookVector:Dot(toMe.Unit)
    return d, dot
end

------------------------------------------------------------
-- Реакция на атаку
------------------------------------------------------------
local lastReact = 0
local reacting  = false

local function isAttackAnim(track)
    local name = (track.Animation and track.Animation.Name or track.Name or ""):lower()
    if name == "" then return true end -- нет имени - на всякий случай считаем атакой
    for k in pairs(CFG.IgnoreAnims) do
        if name:find(k, 1, true) then return false end
        end
    return true
end

local function react(enemy)
    if reacting then return end
    if tick() - lastReact < CFG.Cooldown then return end
    if not CFG.AutoBlock then return end

    reacting  = true
    lastReact = tick()

    -- Блок
    blockDown()
    task.wait(CFG.BlockHold)
    blockUp()

    -- Контратака
    if CFG.AutoAttack then
        for i = 1, CFG.AttackCombo do
            if not enemy or not enemy.Character then break end
            m1Down()
            task.wait(0.02)
            m1Up()
            task.wait(CFG.AttackDelay)
        end
    end

    reacting = false
end

------------------------------------------------------------
-- Подключение слушателей анимаций к каждому врагу
------------------------------------------------------------
local hooked = {} -- [Player] = {connections}

local function unhook(plr)
    local h = hooked[plr]
    if not h then return end
    for _, c in ipairs(h) do pcall(function() c:Disconnect() end) end
    hooked[plr] = nil
end

local function hookCharacter(plr, char)
    unhook(plr)
    if plr == LocalPlayer then return end

    local conns = {}
    hooked[plr] = conns

    local function attach(animator)
        if not animator then return end
        local c = animator.AnimationPlayed:Connect(function(track)
            if not CFG.AutoBlock then return end
            if not isWhitelisted(plr) then return end
            if not isAttackAnim(track) then return end

            local dist, dot = distAndFacing(plr)
            if not dist then return end
            if dist > CFG.Radius then return end
            if (dot or 1) < CFG.FacingDot then return end

            task.spawn(react, plr)
        end)
        table.insert(conns, c)
    end

    -- Animator может появиться не сразу
    local hum = char:FindFirstChildOfClass("Humanoid")
        or char:WaitForChild("Humanoid", 5)
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator")
        or hum:WaitForChild("Animator", 5)
    attach(animator)

    -- Если переcоздадут аниматор
    table.insert(conns, hum.ChildAdded:Connect(function(c)
        if c:IsA("Animator") then attach(c) end
    end))
end

local function hookPlayer(plr)
    if plr == LocalPlayer then return end
    if plr.Character then hookCharacter(plr, plr.Character) end
    plr.CharacterAdded:Connect(function(c) hookCharacter(plr, c) end)
end

for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(p)
    unhook(p)
    Whitelist[p.UserId] = nil
end)

------------------------------------------------------------
-- GUI
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AutoBlockGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 320, 0, 420)
main.Position = UDim2.new(0, 30, 0.5, -210)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(100, 200, 255)
stroke.Thickness = 1.5

-- Title
local title = Instance.new("TextLabel", main)
title.Size = UDim2.new(1, 0, 0, 36)
title.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
title.Text = "  ⚔  AUTO-BLOCK / AUTO-HIT"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(120, 200, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

local closeBtn = Instance.new("TextButton", title)
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -32, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local minBtn = Instance.new("TextButton", title)
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -64, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 13
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

------------------------------------------------------------
-- Хелпер для тогла
------------------------------------------------------------
local function makeToggle(parent, posY, label, initial, onChange)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -20, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, posY)
    btn.BackgroundColor3 = initial and Color3.fromRGB(40,120,60) or Color3.fromRGB(120,40,40)
    btn.Text = label .. ": " .. (initial and "ON" or "OFF")
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local state = initial
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.Text = label .. ": " .. (state and "ON" or "OFF")
        btn.BackgroundColor3 = state and Color3.fromRGB(40,120,60) or Color3.fromRGB(120,40,40)
        onChange(state)
    end)
    return btn
end

makeToggle(main, 46, "AUTO-BLOCK", CFG.AutoBlock, function(s) CFG.AutoBlock = s end)
makeToggle(main, 82, "AUTO-HIT (после блока)", CFG.AutoAttack, function(s) CFG.AutoAttack = s end)

------------------------------------------------------------
-- Радиус +/-
------------------------------------------------------------
local rLbl = Instance.new("TextLabel", main)
rLbl.Size = UDim2.new(1, -100, 0, 26)
rLbl.Position = UDim2.new(0, 10, 0, 120)
rLbl.BackgroundTransparency = 1
rLbl.Text = "Радиус: " .. CFG.Radius
rLbl.TextXAlignment = Enum.TextXAlignment.Left
rLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
rLbl.Font = Enum.Font.GothamBold
rLbl.TextSize = 13

local rMinus = Instance.new("TextButton", main)
rMinus.Size = UDim2.new(0, 36, 0, 26)
rMinus.Position = UDim2.new(1, -85, 0, 120)
rMinus.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
rMinus.Text = "-"
rMinus.TextColor3 = Color3.new(1,1,1)
rMinus.Font = Enum.Font.GothamBold
rMinus.TextSize = 16
Instance.new("UICorner", rMinus).CornerRadius = UDim.new(0, 4)

local rPlus = Instance.new("TextButton", main)
rPlus.Size = UDim2.new(0, 36, 0, 26)
rPlus.Position = UDim2.new(1, -45, 0, 120)
rPlus.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
rPlus.Text = "+"
rPlus.TextColor3 = Color3.new(1,1,1)
rPlus.Font = Enum.Font.GothamBold
rPlus.TextSize = 16
Instance.new("UICorner", rPlus).CornerRadius = UDim.new(0, 4)

rMinus.MouseButton1Click:Connect(function()
    CFG.Radius = math.max(3, CFG.Radius - 1)
    rLbl.Text = "Радиус: " .. CFG.Radius
end)
rPlus.MouseButton1Click:Connect(function()
    CFG.Radius = math.min(80, CFG.Radius + 1)
    rLbl.Text = "Радиус: " .. CFG.Radius
end)

------------------------------------------------------------
-- Список игроков (вайтлист)
------------------------------------------------------------
local listLbl = Instance.new("TextLabel", main)
listLbl.Size = UDim2.new(1, -20, 0, 20)
listLbl.Position = UDim2.new(0, 10, 0, 154)
listLbl.BackgroundTransparency = 1
listLbl.Text = "Цели (пусто = все):"
listLbl.TextXAlignment = Enum.TextXAlignment.Left
listLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
listLbl.Font = Enum.Font.GothamBold
listLbl.TextSize = 12

local allBtn = Instance.new("TextButton", main)
allBtn.Size = UDim2.new(0, 60, 0, 22)
allBtn.Position = UDim2.new(1, -130, 0, 153)
allBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
allBtn.Text = "Все"
allBtn.TextColor3 = Color3.new(1,1,1)
allBtn.Font = Enum.Font.Gotham
allBtn.TextSize = 12
Instance.new("UICorner", allBtn).CornerRadius = UDim.new(0, 4)

local noneBtn = Instance.new("TextButton", main)
noneBtn.Size = UDim2.new(0, 60, 0, 22)
noneBtn.Position = UDim2.new(1, -65, 0, 153)
noneBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
noneBtn.Text = "Снять"
noneBtn.TextColor3 = Color3.new(1,1,1)
noneBtn.Font = Enum.Font.Gotham
noneBtn.TextSize = 12
Instance.new("UICorner", noneBtn).CornerRadius = UDim.new(0, 4)

local list = Instance.new("ScrollingFrame", main)
list.Size = UDim2.new(1, -20, 0, 180)
list.Position = UDim2.new(0, 10, 0, 180)
list.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 6)

local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local rowsByUid = {}

local function refreshCanvas()
    list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 4)
end

local function updateRow(row, plr)
    local active = isWhitelisted(plr) and (next(Whitelist) ~= nil)
    if next(Whitelist) == nil then
        row.BackgroundColor3 = Color3.fromRGB(50, 70, 50) -- "все" режим
    elseif Whitelist[plr.UserId] then
        row.BackgroundColor3 = Color3.fromRGB(40, 110, 60)
    else
        row.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    end
end

local function addRow(plr)
    if plr == LocalPlayer then return end
    if rowsByUid[plr.UserId] then return end
    local row = Instance.new("TextButton", list)
    row.Size = UDim2.new(1, -8, 0, 26)
    row.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    row.Text = "  " .. plr.Name .. (plr.DisplayName ~= plr.Name and ("  ("..plr.DisplayName..")") or "")
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextColor3 = Color3.new(1,1,1)
    row.Font = Enum.Font.Gotham
    row.TextSize = 12
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
    row.MouseButton1Click:Connect(function()
        Whitelist[plr.UserId] = not Whitelist[plr.UserId] or nil
        for uid, r in pairs(rowsByUid) do
            local p = Players:GetPlayerByUserId(uid)
            if p then updateRow(r, p) end
        end
    end)
    rowsByUid[plr.UserId] = row
    updateRow(row, plr)
    refreshCanvas()
end

local function removeRow(uid)
    local r = rowsByUid[uid]
    if r then r:Destroy() end
    rowsByUid[uid] = nil
    refreshCanvas()
end

for _, p in ipairs(Players:GetPlayers()) do addRow(p) end
Players.PlayerAdded:Connect(addRow)
Players.PlayerRemoving:Connect(function(p) removeRow(p.UserId) end)

allBtn.MouseButton1Click:Connect(function()
    Whitelist = {}
    for uid, r in pairs(rowsByUid) do
        local p = Players:GetPlayerByUserId(uid)
        if p then updateRow(r, p) end
    end
end)

noneBtn.MouseButton1Click:Connect(function()
    -- помечаем всех нулём, но Whitelist должен быть НЕ пустым (иначе режим "все")
    Whitelist = {}
    for uid, r in pairs(rowsByUid) do
        Whitelist[uid] = false -- любое значение, чтобы next(Whitelist) ~= nil, но isWhitelisted вернёт false
        local p = Players:GetPlayerByUserId(uid)
        if p then updateRow(r, p) end
    end
end)

------------------------------------------------------------
-- Статус
------------------------------------------------------------
local statusLbl = Instance.new("TextLabel", main)
statusLbl.Size = UDim2.new(1, -20, 0, 18)
statusLbl.Position = UDim2.new(0, 10, 1, -22)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Готов. Кликни по нику в списке - добавить/убрать."
statusLbl.TextColor3 = Color3.fromRGB(120, 220, 120)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 11
statusLbl.TextXAlignment = Enum.TextXAlignment.Left

------------------------------------------------------------
-- Минимизация / закрытие
------------------------------------------------------------
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    main:TweenSize(minimized and UDim2.new(0,320,0,36) or UDim2.new(0,320,0,420),
        Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

------------------------------------------------------------
-- Безопасность: при респе LocalPlayer Network теряется,
-- но fire() сама пере-резолвит. Дополнительно сбрасываем флаг
LocalPlayer.CharacterAdded:Connect(function() reacting = false end)

print("[AutoBlockGui] Загружен. LP:", LocalPlayer.Name)
