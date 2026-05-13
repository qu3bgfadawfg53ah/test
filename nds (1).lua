-- ═══════════════════════════════════════════════════════════════════
--  nds.lua  —  Menu V2  |  NDS — Object Control System
--  Захват свободных объектов карты, управление.
--  Режимы: 1=Cursor (курсор)  2=Tornado (торнадо)
--  Зависит от: globals.lua
-- ═══════════════════════════════════════════════════════════════════

-- ─── ОСНОВНЫЕ НАСТРОЙКИ ──────────────────────────────────────────────────────
ndsEnabled          = false
ndsMode             = 1        -- 1=Cursor  2=Tornado
ndsAutoScan         = true     -- авто-захват новых объектов
ndsAutoInterval     = 2        -- интервал авто-скана (сек)
ndsMaxCapture       = 300      -- текущий лимит захвата
ndsScatterSpeed     = 50       -- скорость откидывания при выкл
ndsMassCompensation = true     -- компенсация массы объектов

-- ─── ПАРАМЕТРЫ CURSOR (РЕЖИМ 1) ──────────────────────────────────────────────
cursorForce         = 200      -- сила притяжения к курсору (100-1000)
cursorHeightOffset  = 0        -- вертикальное смещение курсора

-- ─── ПАРАМЕТРЫ TORNADO (РЕЖИМ 2) ─────────────────────────────────────────────
-- ПОЛНАЯ КОПИЯ ИЗ script.lua
tornadoRadius       = 20       -- радиус торнадо (studs)
tornadoHeight       = 100      -- высота торнадо спирали
tornadoRotSpeed     = 45       -- скорость вращения (deg/s)
tornadoAttractionStr = 1000    -- сила притяжения Velocity

-- ─── КОНСТАНТЫ ──────────────────────────────────────────────────────────────
local MAX_NDS_OBJ = 1000   -- абсолютный потолок
local NDS_RADIUS  = 5000   -- радиус поиска объектов (studs)

-- ─── ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ───────────────────────────────────────────────────
ndsObjects    = {}     -- { part, bodyPos, bodyGyro, canCollide, mass }
ndsCapturedSet = {}    -- { [part] = true } — дедупликация
ndsConnection = nil    -- основной Heartbeat
ndsAutoLoop   = nil    -- поток авто-сканирования
ndsTime       = 0

-- UI-ссылки (назначаются в gui.lua)
ndsCountLabel = nil
ndsAutoTogBtn = nil

-- ─── ТИПЫ СОЕДИНЕНИЙ (не захватываем закреплённые объекты) ──────────────────
local JOINT_TYPES = {
    Weld                   = true,
    WeldConstraint         = true,
    Motor                  = true,
    Motor6D                = true,
    ManualWeld             = true,
    ManualGlue             = true,
    Glue                   = true,
    RigidConstraint        = true,
    BallSocketConstraint   = true,
    HingeConstraint        = true,
    RopeConstraint         = true,
    RodConstraint          = true,
    SpringConstraint       = true,
    CylindricalConstraint  = true,
    PrismaticConstraint    = true,
    UniversalConstraint    = true,
    TorsionSpringConstraint= true,
    AlignPosition          = true,
    AlignOrientation       = true,
}

-- ─── ПРОВЕРКА СВОБОДНОГО ОБЪЕКТА ────────────────────────────────────────────
local function isFreeStanding(part)
    if part.AssemblyRootPart ~= part then return false end

    for _, c in ipairs(part:GetChildren()) do
        if JOINT_TYPES[c.ClassName] then return false end
    end

    local par = part.Parent
    if par and par ~= workspace then
        for _, c in ipairs(par:GetChildren()) do
            if c ~= part and JOINT_TYPES[c.ClassName] then
                local ok0, p0 = pcall(function() return c.Part0 end)
                local ok1, p1 = pcall(function() return c.Part1 end)
                if (ok0 and p0 == part) or (ok1 and p1 == part) then
                    return false
                end
                local ok2, a0 = pcall(function() return c.Attachment0 end)
                local ok3, a1 = pcall(function() return c.Attachment1 end)
                if (ok2 and a0 and a0.Parent == part)
                or (ok3 and a1 and a1.Parent == part) then
                    return false
                end
            end
        end
    end

    return true
end

-- ─── ПЕРСОНАЖИ (кэш, обновляется каждые 2 сек) ──────────────────────────────
local _charSetCache  = {}
local _charSetExpire = 0

local function buildCharSet()
    local now = tick()
    if now < _charSetExpire then return _charSetCache end
    local s = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then s[p.Character] = true end
    end
    _charSetCache  = s
    _charSetExpire = now + 2
    return s
end

local function isCharacterPart(part, charSet)
    local node = part.Parent
    while node and node ~= workspace do
        if charSet[node] then return true end
        node = node.Parent
    end
    return false
end

-- ─── КУРСОР В 3D ─────────────────────────────────────────────────────────────
function getCursorWorldPos()
    local mousePos = UserInputService:GetMouseLocation()
    local inset    = GuiService:GetGuiInset()
    local ray      = camera:ScreenPointToRay(mousePos.X, mousePos.Y - inset.Y)

    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Blacklist

    local flt = {}
    local char = LocalPlayer.Character
    if char then flt[#flt + 1] = char end
    local maxF = math.min(#ndsObjects, 80)
    for j = 1, maxF do
        if ndsObjects[j] and ndsObjects[j].part then
            flt[#flt + 1] = ndsObjects[j].part
        end
    end
    rp.FilterDescendantsInstances = flt

    local result = workspace:Raycast(ray.Origin, ray.Direction * 3000, rp)
    if result then return result.Position end

    if math.abs(ray.Direction.Y) > 0.0001 then
        local t = -ray.Origin.Y / ray.Direction.Y
        if t > 0 then return ray.Origin + ray.Direction * t end
    end
    return ray.Origin + ray.Direction * 200
end

-- ─── ТЕЛЕПОРТ НОВЫХ ОБЪЕКТОВ ────────────────────────────────────────────────
function ndsTeleportNewObjects(startIdx)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local hrpX, hrpY, hrpZ = hrp.Position.X, hrp.Position.Y, hrp.Position.Z

    for i = startIdx or 1, #ndsObjects do
        local obj = ndsObjects[i]
        if obj and obj.part and obj.part.Parent then
            local tgt = Vector3.new(hrpX, hrpY, hrpZ)
            if ndsMode == 1 then
                local cursorPos = getCursorWorldPos()
                tgt = Vector3.new(cursorPos.X, cursorPos.Y + cursorHeightOffset, cursorPos.Z)
            end
            pcall(function()
                obj.part.CFrame = CFrame.new(tgt)
                obj.part.AssemblyLinearVelocity  = Vector3.zero
                obj.part.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end

-- ─── УДАЛЕНИЕ МЕРТВЫХ ОБЪЕКТОВ ──────────────────────────────────────────────
function ndsCleanDead()
    local cleaned = 0
    local i = 1
    while i <= #ndsObjects do
        local obj = ndsObjects[i]
        local dead = not (obj.part and obj.part.Parent)
        if not dead and ndsMode == 1 then
            dead = not (obj.bodyPos and obj.bodyPos.Parent)
        end

        if dead then
            if obj.bodyPos and obj.bodyPos.Parent then pcall(function() obj.bodyPos:Destroy() end) end
            if obj.bodyGyro and obj.bodyGyro.Parent then pcall(function() obj.bodyGyro:Destroy() end) end
            if obj.part and obj.part.Parent and obj.canCollide ~= nil then
                pcall(function() obj.part.CanCollide = obj.canCollide end)
            end
            ndsCapturedSet[obj.part] = nil
            table.remove(ndsObjects, i)
            cleaned += 1
        else
            i += 1
        end
    end
    return cleaned
end

-- ─── ФУНКЦИЯ ИЗ script.lua: RetainPart ──────────────────────────────────────
local function RetainPart(part)
    if part:IsA("BasePart") and not part.Anchored and part:IsDescendantOf(workspace) then
        if part.Parent == LocalPlayer.Character or part:IsDescendantOf(LocalPlayer.Character) then
            return false
        end
        -- ПОЛНАЯ КОПИЯ ИЗ script.lua строка 354-355
        part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
        part.CanCollide = false
        return true
    end
    return false
end

-- ─── СКАНИРОВАНИЕ И ЗАХВАТ ──────────────────────────────────────────────────
function ndsScan()
    local char    = LocalPlayer.Character
    local hrp     = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end

    local limit   = math.min(ndsMaxCapture - #ndsObjects, MAX_NDS_OBJ - #ndsObjects)
    if limit <= 0 then return 0 end

    local hrpPos  = hrp.Position
    local charSet = buildCharSet()
    local pool    = {}
    local region  = Region3.new(hrpPos - Vector3.new(NDS_RADIUS, NDS_RADIUS, NDS_RADIUS),
                                hrpPos + Vector3.new(NDS_RADIUS, NDS_RADIUS, NDS_RADIUS))
    region = region:ExpandToGrid(4)

    for _, part in ipairs(workspace:FindPartsInRegion3(region, nil, math.huge)) do
        if part:IsA("BasePart")
           and not part.Anchored
           and not ndsCapturedSet[part]
           and not isCharacterPart(part, charSet)
           and isFreeStanding(part)
        then
            local dist = (part.Position - hrpPos).Magnitude
            if dist <= NDS_RADIUS then
                pool[#pool + 1] = { part = part, dist = dist }
            end
        end
    end

    table.sort(pool, function(a, b) return a.dist < b.dist end)
    local added = 0

    for _, entry in ipairs(pool) do
        if added >= limit then break end
        local part     = entry.part
        local partMass = part:GetMass()

        -- Режим 1 (Cursor): BodyPosition с силой притяжения к курсору
        if ndsMode == 1 then
            local bp = Instance.new("BodyPosition")
            bp.MaxForce = Vector3.new(1e8, 1e8, 1e8)
            bp.P        = cursorForce * 100 * 25
            bp.D        = cursorForce * 100 * 0.8
            bp.Position = hrpPos
            bp.Parent   = part

            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            bg.P        = 40000
            bg.D        = 1200
            bg.CFrame   = CFrame.new()
            bg.Parent   = part

            local origCC = part.CanCollide
            pcall(function() part.CanCollide = false end)

            local idx = #ndsObjects + 1
            ndsObjects[idx] = {
                part        = part,
                bodyPos     = bp,
                bodyGyro    = bg,
                canCollide  = origCC,
                mass        = partMass,
            }
            ndsCapturedSet[part] = true
            added += 1

        -- Режим 2 (Tornado): ПОЛНАЯ КОПИЯ ИЗ script.lua (функция RetainPart)
        elseif ndsMode == 2 then
            local origCC = part.CanCollide
            if RetainPart(part) then
                local idx = #ndsObjects + 1
                ndsObjects[idx] = {
                    part        = part,
                    canCollide  = origCC,
                    mass        = partMass,
                }
                ndsCapturedSet[part] = true
                added += 1
            end
        end
    end

    if added > 0 then
        local prevCount = #ndsObjects - added
        ndsTeleportNewObjects(prevCount + 1)
    end

    return added
end

-- ─── ПОЛНЫЙ СБРОС И ПЕРВИЧНЫЙ ЗАХВАТ ─────────────────────────────────────────
local function ndsFullCapture()
    for _, obj in ipairs(ndsObjects) do
        if obj.bodyPos and obj.bodyPos.Parent then pcall(function() obj.bodyPos:Destroy() end) end
        if obj.bodyGyro and obj.bodyGyro.Parent then pcall(function() obj.bodyGyro:Destroy() end) end
        if obj.part and obj.part.Parent and obj.canCollide ~= nil then
            pcall(function() obj.part.CanCollide = obj.canCollide end)
        end
    end
    ndsObjects     = {}
    ndsCapturedSet = {}
    local added    = ndsScan()
    addLog("NDS  ▸ захват: " .. added .. " obj  режим=" .. ndsMode
           .. "  R=" .. NDS_RADIUS .. " st")
    return added
end

-- ─── ОСНОВНОЙ ЦИКЛ ───────────────────────────────────────────────────────────
function startNDS()
    ndsFullCapture()
    ndsTime = 0

    if ndsConnection then ndsConnection:Disconnect(); ndsConnection = nil end

    local _ndsFrameOffset = 0
    local NDS_MAX_PER_FRAME = 100

    -- ПОЛНАЯ КОПИЯ ЛОГИКИ ИЗ script.lua (строки 384-406)
    ndsConnection = RunService.Heartbeat:Connect(function(dt)
        if not ndsEnabled then return end
        ndsTime += dt

        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local n = #ndsObjects

        -- Обновляем счётчик UI
        if ndsCountLabel then
            ndsCountLabel.Text       = "🔵 Захвачено: " .. n .. " объектов"
            ndsCountLabel.TextColor3 = n > 0 and C.green or C.textDim
        end
        if n == 0 then return end

        local hrpX, hrpY, hrpZ = hrp.Position.X, hrp.Position.Y, hrp.Position.Z

        -- ═══════════════════════════════════════════════════════════════════
        -- РЕЖИМ 1: CURSOR — Объекты следуют за курсором
        -- ═══════════════════════════════════════════════════════════════════
        if ndsMode == 1 then
            local speedScale = cursorForce / 200
            local baseP = cursorForce * 100 * 25 * speedScale
            local baseD = cursorForce * 100 * 0.8 * speedScale
            local bpP = math.clamp(baseP, 50000, 5000000)
            local bpD = math.clamp(baseD, 4000, 200000)

            local startIdx, endIdx
            if n <= NDS_MAX_PER_FRAME then
                startIdx, endIdx = 1, n
            else
                startIdx = (_ndsFrameOffset % n) + 1
                endIdx   = math.min(startIdx + NDS_MAX_PER_FRAME - 1, n)
                _ndsFrameOffset = _ndsFrameOffset + NDS_MAX_PER_FRAME
            end

            for i = startIdx, endIdx do
                local obj = ndsObjects[i]
                if not obj then continue end
                if not (obj.part.Parent and obj.bodyPos and obj.bodyPos.Parent) then continue end

                local cursorPos = getCursorWorldPos()
                local tgt = Vector3.new(cursorPos.X, cursorPos.Y + cursorHeightOffset, cursorPos.Z)
                obj.bodyPos.Position = tgt

                local massFactor = ndsMassCompensation and (obj.mass or 1) or 1
                local massScale  = math.sqrt(massFactor)

                obj.bodyPos.P = bpP * massScale * 2.5
                obj.bodyPos.D = bpD * massScale * 0.7

                if obj.part.CanCollide then
                    pcall(function() obj.part.CanCollide = false end)
                end
            end

        -- ═══════════════════════════════════════════════════════════════════
        -- РЕЖИМ 2: TORNADO — ПОЛНАЯ КОПИЯ ИЗ script.lua (строки 384-406)
        -- ═══════════════════════════════════════════════════════════════════
        elseif ndsMode == 2 then
            local tornadoCenter = hrp.Position
            
            for i = 1, n do
                local obj = ndsObjects[i]
                if not obj or not obj.part or not obj.part.Parent then continue end
                
                local part = obj.part
                if part.Anchored then continue end
                
                -- ТОЧНАЯ КОПИЯ ИЗ script.lua строки 392-402
                local pos = part.Position
                local distance = (Vector3.new(pos.X, tornadoCenter.Y, pos.Z) - tornadoCenter).Magnitude
                local angle = math.atan2(pos.Z - tornadoCenter.Z, pos.X - tornadoCenter.X)
                local newAngle = angle + math.rad(tornadoRotSpeed)
                local targetPos = Vector3.new(
                    tornadoCenter.X + math.cos(newAngle) * math.min(tornadoRadius, distance),
                    tornadoCenter.Y + (tornadoHeight * (math.abs(math.sin((pos.Y - tornadoCenter.Y) / tornadoHeight)))),
                    tornadoCenter.Z + math.sin(newAngle) * math.min(tornadoRadius, distance)
                )
                local directionToTarget = (targetPos - part.Position).Unit
                part.Velocity = directionToTarget * tornadoAttractionStr
            end
        end
    end)

    -- Поток авто-сканирования
    if ndsAutoLoop then task.cancel(ndsAutoLoop); ndsAutoLoop = nil end
    ndsAutoLoop = task.spawn(function()
        while ndsEnabled do
            task.wait(ndsAutoInterval)
            if not ndsEnabled then break end
            local cleaned = ndsCleanDead()
            local added   = ndsAutoScan and ndsScan() or 0
            if added > 0 or cleaned > 0 then
                addLog("NDS  ▸ авто-скан  +" .. added
                       .. "  -" .. cleaned
                       .. "  итого=" .. #ndsObjects)
            end
        end
    end)
end

-- ─── ОСТАНОВКА NDS ───────────────────────────────────────────────────────────
function stopNDS()
    if ndsConnection then ndsConnection:Disconnect(); ndsConnection = nil end
    if ndsAutoLoop   then task.cancel(ndsAutoLoop);  ndsAutoLoop   = nil end

    local count = #ndsObjects
    for _, obj in ipairs(ndsObjects) do
        if obj.bodyPos and obj.bodyPos.Parent then pcall(function() obj.bodyPos:Destroy() end) end
        if obj.bodyGyro and obj.bodyGyro.Parent then pcall(function() obj.bodyGyro:Destroy() end) end
        if obj.part and obj.part.Parent and obj.canCollide ~= nil then
            pcall(function() obj.part.CanCollide = obj.canCollide end)
        end
        -- Откидываем в случайном направлении
        if obj.part and obj.part.Parent then
            local d = Vector3.new(
                math.random() * 2 - 1,
                math.random() * 2 - 1,
                math.random() * 2 - 1)
            if d.Magnitude > 0.001 then d = d.Unit end
            pcall(function()
                obj.part.AssemblyLinearVelocity = d * ndsScatterSpeed
            end)
        end
    end

    ndsObjects     = {}
    ndsCapturedSet = {}

    if ndsCountLabel then
        ndsCountLabel.Text       = "⚫ NDS отключён"
        ndsCountLabel.TextColor3 = C.textDim
    end

    addLog("NDS  ▸ ВЫКЛ  откинуто=" .. count .. "  v=" .. ndsScatterSpeed)
end

-- ─── SCATTER (без отключения) ────────────────────────────────────────────────
function ndsScatterAll()
    local count = #ndsObjects
    for _, obj in ipairs(ndsObjects) do
        if not (obj.part and obj.part.Parent) then continue end
        local d = Vector3.new(
            math.random() * 2 - 1,
            math.random() * 2 - 1,
            math.random() * 2 - 1)
        if d.Magnitude > 0.001 then d = d.Unit end
        pcall(function()
            if obj.bodyPos then
                obj.bodyPos.MaxForce = Vector3.zero
            end
            if obj.bodyGyro then
                obj.bodyGyro.MaxTorque = Vector3.zero
            end
            obj.part.AssemblyLinearVelocity = d * ndsScatterSpeed
        end)
        -- Возвращаем силы через 0.12 сек
        task.delay(0.12, function()
            if obj.bodyPos and obj.bodyPos.Parent then
                obj.bodyPos.MaxForce = Vector3.new(1e8, 1e8, 1e8)
            end
            if obj.bodyGyro and obj.bodyGyro.Parent then
                obj.bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            end
        end)
    end
    addLog("NDS  ▸ scatter " .. count .. " obj @ " .. ndsScatterSpeed .. " st/s")
end

addLog("NDS  ▸ nds.lua загружен  (cursor/tornado  max=" .. MAX_NDS_OBJ .. ")")
