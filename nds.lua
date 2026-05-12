-- ═══════════════════════════════════════════════════════════════════
--  nds.lua  —  Menu V2  |  NDS — Object Control
--  Захват свободных объектов карты, управление орбитой.
--  Режимы: 1=Orbit (кольцо)  2=Cursor (курсор)  3=Tornado (торнадо)
--  Зависит от: globals.lua
-- ═══════════════════════════════════════════════════════════════════

-- ─── НАСТРОЙКИ NDS ──────────────────────────────────────────────────────────
ndsEnabled          = false
ndsMode             = 1        -- 1=Orbit  2=Cursor  3=Tornado
ndsDistance         = 20       -- радиус орбиты (studs)
ndsSpeed            = 200      -- сила притяжения (100–1000)
ndsRotSpeed         = 45       -- скорость вращения (deg/s)
ndsScatterSpeed     = 50       -- скорость откидывания при выкл
ndsAutoScan         = true     -- авто-захват новых объектов
ndsAutoInterval     = 2        -- интервал авто-скана (сек)
ndsMaxCapture       = 300      -- текущий лимит захвата (слайдер UI)
ndsAttractionStr    = 1000     -- базовая сила притяжения для Tornado
ndsHeightOffset     = 0        -- вертикальное смещение орбиты (-50 до +50)
ndsMassCompensation = true     -- компенсация массы объектов
ndsTornadoHeight    = 100      -- высота торнадо (только для режима 3)

-- ─── КОНСТАНТЫ ──────────────────────────────────────────────────────────────
local MAX_NDS_OBJ = 1000   -- абсолютный потолок
local NDS_RADIUS  = 5000   -- радиус поиска объектов (studs)

-- ─── ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ───────────────────────────────────────────────────
ndsObjects    = {}     -- { part, align/bodyPos, bodyGyro, attachment, canCollide, phi, baseTheta, ring, angleOffset, mass }
ndsCapturedSet = {}    -- { [part] = true } — дедупликация
ndsNumRings   = 1
ndsConnection = nil    -- основной Heartbeat
ndsAutoLoop   = nil    -- поток авто-сканирования
ndsTime       = 0

-- Общий Attachment для AlignPosition (для Orbit режима)
local ndsMainAttachment = nil
local ndsMainPart = nil

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

-- ─── РАЗМЕТКА ОРБИТЫ (кольца) ────────────────────────────────────────────────
local function computeDiskLayout(n)
    if n == 0 then return {}, {}, 0 end
    local numRings = math.max(1, math.round(math.sqrt(n)))
    local total    = numRings * (numRings + 1) / 2
    local ringOf   = {}
    local angleOf  = {}
    local perRing  = {}
    local assigned = 0
    for k = 1, numRings do
        local cnt = (k == numRings)
            and (n - assigned)
            or  math.max(1, math.round(n * k / total))
        cnt = math.min(cnt, n - assigned)
        perRing[k] = cnt
        assigned  += cnt
        if assigned >= n then numRings = k break end
    end
    local idx = 0
    for k = 1, numRings do
        for j = 1, (perRing[k] or 0) do
            idx += 1
            ringOf[idx]  = k
            angleOf[idx] = (j - 1) / math.max(perRing[k], 1) * math.pi * 2
                           + (k - 1) * 0.31
        end
    end
    return ringOf, angleOf, numRings
end

local function rebuildDiskLayout()
    local n = #ndsObjects
    local ringOf, angleOf, numR = computeDiskLayout(n)
    ndsNumRings = numR or 1
    for i = 1, n do
        ndsObjects[i].ring        = ringOf[i]  or 1
        ndsObjects[i].angleOffset = angleOf[i] or 0
    end
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

-- ─── ЦЕЛЕВАЯ ПОЗИЦИЯ ОБЪЕКТА ─────────────────────────────────────────────────
local function getNdsTargetPos(obj, hrpX, hrpY, hrpZ, rotRad)
    local cosR = math.cos(rotRad)
    local sinR = math.sin(rotRad)
    local heightY = hrpY + ndsHeightOffset

    -- Режим 1: ORBIT (кольцо - бывший Disk)
    if ndsMode == 1 then
        local k     = obj.ring or 1
        local rad   = ndsDistance * k / ndsNumRings
        local alpha = obj.angleOffset + rotRad
        local xOff  = math.cos(alpha) * rad
        local zOff  = math.sin(alpha) * rad
        return Vector3.new(
            hrpX + xOff * cosR - zOff * sinR,
            heightY,
            hrpZ + xOff * sinR + zOff * cosR
        )
    end

    -- Режим 2: CURSOR
    if ndsMode == 2 then
        local cursorPos = getCursorWorldPos()
        return Vector3.new(cursorPos.X, cursorPos.Y + ndsHeightOffset, cursorPos.Z)
    end

    -- Режим 3: TORNADO
    if ndsMode == 3 then
        -- Возвращаем текущую позицию объекта (для Tornado используется прямое управление Velocity)
        return obj.part.Position
    end

    return Vector3.new(hrpX, hrpY, hrpZ)
end

-- ─── ТЕЛЕПОРТ НОВЫХ ОБЪЕКТОВ НА ОРБИТУ ──────────────────────────────────────
function ndsTeleportNewObjects(startIdx)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local hrpX, hrpY, hrpZ = hrp.Position.X, hrp.Position.Y, hrp.Position.Z
    local rotRad = -ndsTime * math.rad(ndsRotSpeed)

    for i = startIdx or 1, #ndsObjects do
        local obj = ndsObjects[i]
        if obj and obj.part and obj.part.Parent then
            local tgt = getNdsTargetPos(obj, hrpX, hrpY, hrpZ, rotRad)
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
        if not dead then
            if ndsMode == 1 then
                dead = not (obj.alignPos and obj.alignPos.Parent)
            elseif ndsMode == 2 then
                dead = not (obj.bodyPos and obj.bodyPos.Parent)
            end
        end

        if dead then
            if obj.alignPos  and obj.alignPos.Parent  then pcall(function() obj.alignPos:Destroy()  end) end
            if obj.bodyPos   and obj.bodyPos.Parent   then pcall(function() obj.bodyPos:Destroy()   end) end
            if obj.bodyGyro  and obj.bodyGyro.Parent  then pcall(function() obj.bodyGyro:Destroy()  end) end
            if obj.attachment and obj.attachment.Parent then pcall(function() obj.attachment:Destroy() end) end
            if obj.torque    and obj.torque.Parent    then pcall(function() obj.torque:Destroy()    end) end
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
    if cleaned > 0 then rebuildDiskLayout() end
    return cleaned
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

        -- Режим 1 (Orbit): используем AlignPosition для жесткого удержания
        if ndsMode == 1 then
            local att = Instance.new("Attachment")
            att.Parent = part

            local ap = Instance.new("AlignPosition")
            ap.Attachment0     = att
            ap.Attachment1     = ndsMainAttachment
            ap.MaxForce        = 9999999999
            ap.MaxVelocity     = math.huge
            ap.Responsiveness  = 200
            ap.Parent          = part

            local torque = Instance.new("Torque")
            torque.Torque     = Vector3.new(100000, 100000, 100000)
            torque.Attachment0 = att
            torque.Parent     = part

            local origCC = part.CanCollide
            pcall(function() part.CanCollide = false end)

            local idx = #ndsObjects + 1
            ndsObjects[idx] = {
                part        = part,
                alignPos    = ap,
                attachment  = att,
                torque      = torque,
                canCollide  = origCC,
                ring        = 1,
                angleOffset = 0,
                mass        = partMass,
            }
            ndsCapturedSet[part] = true
            added += 1

        -- Режим 2 (Cursor): используем BodyPosition с повышенной силой
        elseif ndsMode == 2 then
            local bp = Instance.new("BodyPosition")
            bp.MaxForce = Vector3.new(1e8, 1e8, 1e8)
            bp.P        = ndsSpeed * 100 * 25
            bp.D        = ndsSpeed * 100 * 0.8
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

        -- Режим 3 (Tornado): без физических ограничителей, управление через Velocity
        elseif ndsMode == 3 then
            local origCC = part.CanCollide
            pcall(function()
                part.CanCollide = false
                part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
            end)

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

    if added > 0 then
        local prevCount = #ndsObjects - added
        rebuildDiskLayout()
        ndsTeleportNewObjects(prevCount + 1)
    end

    return added
end

-- ─── ПОЛНЫЙ СБРОС И ПЕРВИЧНЫЙ ЗАХВАТ ─────────────────────────────────────────
local function ndsFullCapture()
    for _, obj in ipairs(ndsObjects) do
        if obj.alignPos  and obj.alignPos.Parent  then pcall(function() obj.alignPos:Destroy()  end) end
        if obj.bodyPos   and obj.bodyPos.Parent   then pcall(function() obj.bodyPos:Destroy()   end) end
        if obj.bodyGyro  and obj.bodyGyro.Parent  then pcall(function() obj.bodyGyro:Destroy()  end) end
        if obj.attachment and obj.attachment.Parent then pcall(function() obj.attachment:Destroy() end) end
        if obj.torque    and obj.torque.Parent    then pcall(function() obj.torque:Destroy()    end) end
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
    -- Создаем главный Attachment для Orbit режима
    if ndsMainPart then pcall(function() ndsMainPart:Destroy() end) end
    ndsMainPart = Instance.new("Part")
    ndsMainPart.Anchored = true
    ndsMainPart.CanCollide = false
    ndsMainPart.Transparency = 1
    ndsMainPart.Size = Vector3.new(1, 1, 1)
    ndsMainPart.Parent = workspace

    ndsMainAttachment = Instance.new("Attachment")
    ndsMainAttachment.Parent = ndsMainPart

    ndsFullCapture()
    ndsTime = 0

    if ndsConnection then ndsConnection:Disconnect(); ndsConnection = nil end

    local _ndsFrameOffset = 0
    local NDS_MAX_PER_FRAME = 100

    ndsConnection = RunService.RenderStepped:Connect(function(dt)
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
        local rotRad = -ndsTime * math.rad(ndsRotSpeed)

        -- Обновляем позицию главного Attachment (для Orbit)
        if ndsMainPart and ndsMode == 1 then
            ndsMainPart.Position = Vector3.new(hrpX, hrpY + ndsHeightOffset, hrpZ)
        end

        -- Режим 1: ORBIT - обновляем только позицию главного Attachment
        if ndsMode == 1 then
            -- AlignPosition автоматически притягивает объекты к нужной точке
            -- Позиционирование через целевые позиции не нужно

        -- Режим 2: CURSOR - обновляем BodyPosition
        elseif ndsMode == 2 then
            local speedScale = ndsSpeed / 200
            local baseP = ndsSpeed * 100 * 25 * speedScale
            local baseD = ndsSpeed * 100 * 0.8 * speedScale
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

                local tgt = getNdsTargetPos(obj, hrpX, hrpY, hrpZ, rotRad)
                obj.bodyPos.Position = tgt

                local massFactor = ndsMassCompensation and (obj.mass or 1) or 1
                local massScale  = math.sqrt(massFactor)

                obj.bodyPos.P = bpP * massScale * 2.5
                obj.bodyPos.D = bpD * massScale * 0.7

                if obj.part.CanCollide then
                    pcall(function() obj.part.CanCollide = false end)
                end
            end

        -- Режим 3: TORNADO - прямое управление Velocity
        elseif ndsMode == 3 then
            local tornadoCenter = hrp.Position
            for i = 1, n do
                local obj = ndsObjects[i]
                if not obj or not obj.part or not obj.part.Parent then continue end

                local part = obj.part
                local pos = part.Position
                local distance = (Vector3.new(pos.X, tornadoCenter.Y, pos.Z) - tornadoCenter).Magnitude
                local angle = math.atan2(pos.Z - tornadoCenter.Z, pos.X - tornadoCenter.X)
                local newAngle = angle + math.rad(ndsRotSpeed)

                -- Целевая позиция с спиралью вверх
                local targetPos = Vector3.new(
                    tornadoCenter.X + math.cos(newAngle) * math.min(ndsDistance, distance),
                    tornadoCenter.Y + (ndsTornadoHeight * (math.abs(math.sin((pos.Y - tornadoCenter.Y) / ndsTornadoHeight)))),
                    tornadoCenter.Z + math.sin(newAngle) * math.min(ndsDistance, distance)
                )

                local directionToTarget = (targetPos - part.Position)
                if directionToTarget.Magnitude > 0.001 then
                    directionToTarget = directionToTarget.Unit
                end

                pcall(function()
                    part.Velocity = directionToTarget * ndsAttractionStr
                end)

                if part.CanCollide then
                    pcall(function() part.CanCollide = false end)
                end
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
    if ndsMainPart   then pcall(function() ndsMainPart:Destroy() end); ndsMainPart = nil end

    local count = #ndsObjects
    for _, obj in ipairs(ndsObjects) do
        if obj.alignPos  and obj.alignPos.Parent  then pcall(function() obj.alignPos:Destroy()  end) end
        if obj.bodyPos   and obj.bodyPos.Parent   then pcall(function() obj.bodyPos:Destroy()   end) end
        if obj.bodyGyro  and obj.bodyGyro.Parent  then pcall(function() obj.bodyGyro:Destroy()  end) end
        if obj.attachment and obj.attachment.Parent then pcall(function() obj.attachment:Destroy() end) end
        if obj.torque    and obj.torque.Parent    then pcall(function() obj.torque:Destroy()    end) end
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
            if obj.alignPos then
                obj.alignPos.MaxForce = 0
            end
            if obj.bodyPos then
                obj.bodyPos.MaxForce = Vector3.zero
            end
            if obj.bodyGyro then
                obj.bodyGyro.MaxTorque = Vector3.zero
            end
            if obj.torque then
                obj.torque.Torque = Vector3.zero
            end
            obj.part.AssemblyLinearVelocity = d * ndsScatterSpeed
        end)
        -- Возвращаем силы через 0.12 сек
        task.delay(0.12, function()
            if obj.alignPos and obj.alignPos.Parent then
                obj.alignPos.MaxForce = 9999999999
            end
            if obj.bodyPos and obj.bodyPos.Parent then
                obj.bodyPos.MaxForce = Vector3.new(1e8, 1e8, 1e8)
            end
            if obj.bodyGyro and obj.bodyGyro.Parent then
                obj.bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            end
            if obj.torque and obj.torque.Parent then
                obj.torque.Torque = Vector3.new(100000, 100000, 100000)
            end
        end)
    end
    addLog("NDS  ▸ scatter " .. count .. " obj @ " .. ndsScatterSpeed .. " st/s")
end

addLog("NDS  ▸ nds.lua загружен  (orbit/cursor/tornado  max=" .. MAX_NDS_OBJ .. ")")
