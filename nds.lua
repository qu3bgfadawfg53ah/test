-- ═══════════════════════════════════════════════════════════════════
--  nds.lua  —  Menu V1  |  NDS — Object Control
--  Захват свободных объектов карты, орбита вокруг игрока.
--  Режимы: Sphere / Disk / Cursor / Vortex (новый).
--  Зависит от: globals.lua
-- ═══════════════════════════════════════════════════════════════════

-- ─── НАСТРОЙКИ NDS ──────────────────────────────────────────────────────────
ndsEnabled          = false
ndsMode             = 1        -- 1=Sphere  2=Disk  3=Cursor  4=Vortex
ndsDistance         = 20       -- радиус орбиты (studs)
ndsSpeed            = 200      -- жёсткость BodyPosition (1–1000, масштаб в bp.P)
ndsRotSpeed         = 45       -- скорость вращения (deg/s)
ndsScatterSpeed     = 50       -- скорость откидывания при выкл
ndsAutoScan         = true     -- авто-захват новых объектов
ndsAutoInterval     = 2        -- интервал авто-скана (сек)
ndsMaxCapture       = 300      -- текущий лимит захвата (слайдер UI)
ndsAttractionStr    = 1000     -- базовая сила притяжения (P множитель, 100-5000)
ndsHeightOffset     = 0        -- вертикальное смещение орбиты (-50 до +50)
ndsMassCompensation = true     -- компенсация массы объектов

-- ─── КОНСТАНТЫ ──────────────────────────────────────────────────────────────
local MAX_NDS_OBJ = 1000   -- абсолютный потолок
local NDS_RADIUS  = 5000   -- радиус поиска объектов (studs)

-- ─── ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ───────────────────────────────────────────────────
ndsObjects    = {}     -- { part, bodyPos, bodyGyro, canCollide, phi, baseTheta, ring, angleOffset }
ndsCapturedSet = {}    -- { [part] = true } — дедупликация
ndsNumRings   = 1
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
--  Возвращает true если деталь не закреплена никакими соединениями.
local function isFreeStanding(part)
    -- Должна быть корнем своей физической сборки
    if part.AssemblyRootPart ~= part then return false end

    -- Прямые дочерние соединения
    for _, c in ipairs(part:GetChildren()) do
        if JOINT_TYPES[c.ClassName] then return false end
    end

    -- Соединения в родительском контейнере
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

-- ─── РАЗМЕТКА ────────────────────────────────────────────────────────────────

-- Диск: n объектов по концентрическим кольцам
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
                           + (k - 1) * 0.31  -- смещение для красивого паттерна
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

-- Сфера Фибоначчи: равномерное распределение по поверхности сферы
local function rebuildSphereLayout()
    local n = #ndsObjects
    if n == 0 then return end
    for i = 1, n do
        ndsObjects[i].phi       = math.acos(math.clamp(2 * (i / n) - 1, -1, 1))
        ndsObjects[i].baseTheta = (i - 1) * math.pi * (3 - math.sqrt(5))
    end
end

-- ─── КУРСОР В 3D ─────────────────────────────────────────────────────────────
function getCursorWorldPos()
    local mousePos = UserInputService:GetMouseLocation()
    local inset    = GuiService:GetGuiInset()
    local ray      = camera:ScreenPointToRay(mousePos.X, mousePos.Y - inset.Y)

    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Blacklist

    -- Фильтруем персонажа + первые 80 захваченных объектов (лимит API ~500)
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

    -- Fallback: проекция на горизонтальную плоскость Y=0
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

    -- Режим 1: СФЕРА
    if ndsMode == 1 then
        local sinPhi = math.sin(obj.phi)
        local x0 = sinPhi * math.cos(obj.baseTheta) * ndsDistance
        local y0 = math.cos(obj.phi)                * ndsDistance
        local z0 = sinPhi * math.sin(obj.baseTheta) * ndsDistance
        return Vector3.new(
            hrpX + x0*cosR - z0*sinR,
            heightY + y0,
            hrpZ + x0*sinR + z0*cosR)

    -- Режим 2: ДИСК
    elseif ndsMode == 2 then
        local nR    = math.max(ndsNumRings, 1)
        local rDist = (obj.ring / nR) * ndsDistance
        local angle = obj.angleOffset + rotRad
        return Vector3.new(
            hrpX + math.cos(angle) * rDist,
            heightY,
            hrpZ + math.sin(angle) * rDist)

    -- Режим 3: КУРСОР
    elseif ndsMode == 3 then
        local tPos  = getCursorWorldPos()
        local nR    = math.max(ndsNumRings, 1)
        local rDist = (obj.ring / nR) * ndsDistance * 0.45
        local angle = obj.angleOffset + rotRad
        local layerY = (obj.ring - 1) * 2.2
        return Vector3.new(
            tPos.X + math.cos(angle) * rDist,
            tPos.Y + layerY + 1,
            tPos.Z + math.sin(angle) * rDist)

    -- Режим 4: VORTEX (спираль, затягивающая объекты в центр, потом выбрасывающая)
    else
        local totalTime = ndsTime % 8   -- цикл 8 сек
        local phase     = totalTime / 8  -- 0..1
        -- 0..0.5 = сжатие к центру; 0.5..1 = разлёт
        local radiusScale
        if phase < 0.5 then
            radiusScale = 1 - phase * 2   -- 1 → 0
        else
            radiusScale = (phase - 0.5) * 2  -- 0 → 1
        end
        local nR    = math.max(ndsNumRings, 1)
        local rDist = (obj.ring / nR) * ndsDistance * radiusScale
        local angle = obj.angleOffset + rotRad * 3  -- быстрее вращается
        local layerY = math.sin(obj.phi) * ndsDistance * 0.3 * (1 - radiusScale)
        return Vector3.new(
            hrpX + math.cos(angle) * rDist,
            heightY + layerY,
            hrpZ + math.sin(angle) * rDist)
    end
end

-- ─── МГНОВЕННЫЙ ТЕЛЕПОРТ НОВЫХ ОБЪЕКТОВ ──────────────────────────────────────
local function ndsTeleportNewObjects(startIdx)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    local hrpX, hrpY, hrpZ = hrp.Position.X, hrp.Position.Y, hrp.Position.Z
    local rotRad = -ndsTime * math.rad(ndsRotSpeed)
    local teleported = 0
    for i = startIdx, #ndsObjects do
        local obj = ndsObjects[i]
        if obj and obj.part and obj.part.Parent
           and obj.bodyPos and obj.bodyPos.Parent then
            local tgt = getNdsTargetPos(obj, hrpX, hrpY, hrpZ, rotRad)
            pcall(function()
                obj.part.AssemblyLinearVelocity  = Vector3.zero
                obj.part.AssemblyAngularVelocity = Vector3.zero
                obj.part.CFrame                  = CFrame.new(tgt)
            end)
            obj.bodyPos.Position = tgt
            teleported += 1
        end
    end
    return teleported
end

-- ─── ОЧИСТКА МЁРТВЫХ ОБЪЕКТОВ ────────────────────────────────────────────────
--  Swap-remove: O(1) на каждое удаление вместо O(n).
local function ndsCleanDead()
    local cleaned = 0
    local i = 1
    local n = #ndsObjects
    while i <= n do
        local obj = ndsObjects[i]
        local dead = (not obj.part) or (not obj.part.Parent)
               or   (not obj.bodyPos) or (not obj.bodyPos.Parent)
        if dead then
            if obj.bodyPos and obj.bodyPos.Parent then
                pcall(function() obj.bodyPos:Destroy() end)
            end
            if obj.bodyGyro and obj.bodyGyro.Parent then
                pcall(function() obj.bodyGyro:Destroy() end)
            end
            if obj.part and obj.part.Parent and obj.canCollide ~= nil then
                pcall(function() obj.part.CanCollide = obj.canCollide end)
            end
            if obj.part then ndsCapturedSet[obj.part] = nil end
            ndsObjects[i] = ndsObjects[n]
            ndsObjects[n] = nil
            n       -= 1
            cleaned += 1
        else
            i += 1
        end
    end
    if cleaned > 0 then
        rebuildDiskLayout()
        rebuildSphereLayout()
    end
    return cleaned
end

-- ─── СКАН И ЗАХВАТ ОБЪЕКТОВ ──────────────────────────────────────────────────
local function ndsScan()
    local char    = LocalPlayer.Character
    local hrp     = char and char:FindFirstChild("HumanoidRootPart")
    local hrpPos  = hrp and hrp.Position or Vector3.zero
    local charSet = buildCharSet()

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Blacklist
    local filterList = {}
    for c in pairs(charSet) do filterList[#filterList + 1] = c end
    overlapParams.FilterDescendantsInstances = filterList
    -- БАГ #9 FIX: было MAX_NDS_OBJ * 4 = 4000 — зависание при первом скане.
    overlapParams.MaxParts = math.min(MAX_NDS_OBJ * 2, 1000)

    local parts    = workspace:GetPartBoundsInRadius(hrpPos, NDS_RADIUS, overlapParams)
    local added    = 0
    local capLimit = math.min(ndsMaxCapture, MAX_NDS_OBJ)

    for _, part in ipairs(parts) do
        if #ndsObjects >= capLimit          then break    end
        if part.Anchored                    then continue end
        if part == workspace.Terrain        then continue end
        if ndsCapturedSet[part]             then continue end
        if not isFreeStanding(part)         then continue end
        if isCharacterPart(part, charSet)   then continue end

        -- Гасим начальную скорость
        pcall(function()
            part.AssemblyLinearVelocity  = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end)

        -- Адаптивная сила притяжения: базовая сила * ndsAttractionStr
        -- С компенсацией массы для равномерного поведения
        local partMass = 1
        if ndsMassCompensation then
            local success, mass = pcall(function() return part.AssemblyMass end)
            partMass = (success and mass) and math.clamp(mass, 0.1, 100) or 1
        end
        
        local baseP = ndsAttractionStr * 25
        local baseD = ndsAttractionStr * 0.8
        
        -- BodyPosition: управляемое удержание с компенсацией массы
        local bp    = Instance.new("BodyPosition")
        bp.MaxForce = Vector3.new(1e8, 1e8, 1e8)
        bp.P        = baseP * math.sqrt(partMass)  -- компенсация массы через sqrt
        bp.D        = baseD * math.sqrt(partMass)
        bp.Position = part.Position
        bp.Parent   = part

        -- BodyGyro: горизонтальная ориентация (грань вверх)
        local bg    = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
        bg.P        = 40000
        bg.D        = 1200
        bg.CFrame   = CFrame.new()  -- identity = плоская грань вверх
        bg.Parent   = part

        local origCC = part.CanCollide
        pcall(function() part.CanCollide = false end)

        local idx = #ndsObjects + 1
        ndsObjects[idx] = {
            part        = part,
            bodyPos     = bp,
            bodyGyro    = bg,
            canCollide  = origCC,
            phi         = 0,
            baseTheta   = 0,
            ring        = 1,
            angleOffset = 0,
            mass        = partMass,  -- сохраняем массу для использования в цикле
        }
        ndsCapturedSet[part] = true
        added += 1
    end

    if added > 0 then
        local prevCount = #ndsObjects - added
        rebuildDiskLayout()
        rebuildSphereLayout()
        ndsTeleportNewObjects(prevCount + 1)
    end

    return added
end

-- Полный сброс и первичный захват
local function ndsFullCapture()
    for _, obj in ipairs(ndsObjects) do
        if obj.bodyPos  and obj.bodyPos.Parent  then pcall(function() obj.bodyPos:Destroy()  end) end
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

-- ─── ОСНОВНОЙ ЦИКЛ (Heartbeat) ───────────────────────────────────────────────
function startNDS()
    ndsFullCapture()
    ndsTime = 0

    if ndsConnection then ndsConnection:Disconnect(); ndsConnection = nil end

    -- БАГ #10 FIX: Heartbeat → RenderStepped (позиции NDS — визуальное обновление,
    -- правильнее синхронизировать с кадром, а не с физикой).
    -- Добавлен MAX_PER_FRAME: при 200+ объектах обновляем не все сразу,
    -- а скользящим окном, чтобы не дропать FPS.
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

        -- Параметры BodyPosition: базовая сила * ndsAttractionStr * масштаб от ndsSpeed
        local speedScale = ndsSpeed / 200  -- нормализация (200 = базовое значение)
        local baseP = ndsAttractionStr * 25 * speedScale
        local baseD = ndsAttractionStr * 0.8 * speedScale
        
        local bpP = math.clamp(baseP,  5000, 500000)
        local bpD = math.clamp(baseD,   400,  20000)

        -- Вращение по часовой (отрицательный угол = правосторонний)
        local rotRad = -ndsTime * math.rad(ndsRotSpeed)
        local hrpX, hrpY, hrpZ = hrp.Position.X, hrp.Position.Y, hrp.Position.Z

        -- BodyGyro обновляем раз в ~10 кадров (экономия)
        local updateGyro = (math.floor(ndsTime * 10) % 5 == 0)
        local levelCF    = CFrame.new()

        -- Скользящее окно: если объектов много — делим на батчи
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
            if not (obj.part.Parent and obj.bodyPos.Parent) then continue end

            local tgt = getNdsTargetPos(obj, hrpX, hrpY, hrpZ, rotRad)
            obj.bodyPos.Position = tgt
            
            -- Применяем компенсацию массы к силе притяжения
            local massFactor = ndsMassCompensation and (obj.mass or 1) or 1
            local massScale  = math.sqrt(massFactor)
            
            obj.bodyPos.P = (ndsMode == 3) and (bpP * massScale * 2.5) or (bpP * massScale)
            obj.bodyPos.D = (ndsMode == 3) and (bpD * massScale * 0.7) or (bpD * massScale)

            if updateGyro and obj.bodyGyro and obj.bodyGyro.Parent then
                obj.bodyGyro.CFrame = levelCF
            end

            if obj.part.CanCollide then
                pcall(function() obj.part.CanCollide = false end)
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
        if obj.bodyPos  and obj.bodyPos.Parent  then pcall(function() obj.bodyPos:Destroy()  end) end
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
            obj.bodyPos.MaxForce  = Vector3.zero
            if obj.bodyGyro then obj.bodyGyro.MaxTorque = Vector3.zero end
            obj.part.AssemblyLinearVelocity = d * ndsScatterSpeed
        end)
        -- Через 0.12 сек возвращаем MaxForce
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

addLog("NDS  ▸ nds.lua загружен  (sphere/disk/cursor/vortex  max=" .. MAX_NDS_OBJ .. ")")
