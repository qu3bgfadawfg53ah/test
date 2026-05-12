-- ═══════════════════════════════════════════════════════════════════
--  teleport.lua  —  Matt-script | Телепорт
--  Режимы: клик (Ctrl+ЛКМ), по нику, история, loop TP, вейпоинты.
--  Зависит от: globals.lua
-- ═══════════════════════════════════════════════════════════════════

-- Настройки телепорта
teleportEnabled = false
targetPlayerName = ""
TP_MAX_DIST = 10000
TP_HISTORY_MAX = 15
tpHistory = {}
WAYPOINTS_MAX = 20
waypoints = {}

-- Добавление позиции в историю
local function pushTpHistory(pos, label)
    table.insert(tpHistory, 1, {
        pos = pos,
        label = label or string.format("%.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z),
        time = os.time(),
    })
    if #tpHistory > TP_HISTORY_MAX then
        table.remove(tpHistory, #tpHistory)
    end
end

-- Сохранение вейпоинта
function waypointSave(name)
    local hrp = getHRP(LocalPlayer)
    if not hrp then
        addLog("TP   ▸ ⚠ нет персонажа для сохранения вейпоинта")
        return false
    end
    for i, wp in ipairs(waypoints) do
        if wp.name == name then
            waypoints[i].pos = hrp.Position
            addLog("TP   ▸ 📍 вейпоинт обновлён: " .. name)
            return true
        end
    end
    if #waypoints >= WAYPOINTS_MAX then
        addLog("TP   ▸ ⚠ лимит вейпоинтов (" .. WAYPOINTS_MAX .. ")")
        return false
    end
    waypoints[#waypoints+1] = { name = name, pos = hrp.Position }
    addLog("TP   ▸ 📍 вейпоинт сохранён: " .. name
           .. "  @ " .. string.format("%.0f, %.0f, %.0f",
               hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
    return true
end

-- Переход к вейпоинту
function waypointGoto(name)
    for _, wp in ipairs(waypoints) do
        if wp.name == name then
            doTeleport(wp.pos, "wp:" .. name)
            return true
        end
    end
    addLog("TP   ▸ вейпоинт не найден: " .. name)
    return false
end

-- Удаление вейпоинта
function waypointDelete(name)
    for i, wp in ipairs(waypoints) do
        if wp.name == name then
            table.remove(waypoints, i)
            addLog("TP   ▸ 🗑 вейпоинт удалён: " .. name)
            return true
        end
    end
    return false
end

-- Базовая функция телепорта
function doTeleport(tgtPos, reason)
    -- БАГ #27 FIX: запрашиваем контроль движения через DataBus
    if not DataBus:RequestControl("Movement", "Teleport", 2) then
        addLog("TP   ▸ ⚠ Movement занят другим модулем")
        -- продолжаем но с меньшим приоритетом
    end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        addLog("TP   ▸ ❌ нет HRP (персонаж не загружен?)")
        DataBus:ReleaseControl("Movement", "Teleport")
        return false
    end

    local dist = (hrp.Position - tgtPos).Magnitude

    if dist > TP_MAX_DIST then
        addLog("TP   ▸ ❌ слишком далеко (" .. fmtDist(dist) .. " > " .. fmtDist(TP_MAX_DIST) .. ")")
        DataBus:ReleaseControl("Movement", "Teleport")
        return false
    end

    local ok = pcall(function()
        -- БАГ #12 FIX: уничтожаем старый BodyVelocity если остался от предыдущего TP
        local existingBV = hrp:FindFirstChildOfClass("BodyVelocity")
        if existingBV then existingBV:Destroy() end

        local bv = Instance.new("BodyVelocity")
        bv.Velocity = Vector3.zero
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Parent = hrp
        hrp.CFrame = CFrame.new(tgtPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        task.delay(0.18, function()
            if bv and bv.Parent then bv:Destroy() end
        end)
    end)

    local label = reason and ("  [" .. reason .. "]") or ""
    addLog("TP   ▸ " .. (ok and "✅ " or "❌ ")
           .. string.format("%.0f, %.0f, %.0f", tgtPos.X, tgtPos.Y, tgtPos.Z)
           .. "  " .. fmtDist(dist) .. " st" .. label)

    if ok then pushTpHistory(tgtPos, reason) end
    
    -- Освобождаем контроль после небольшой задержки (для стабилизации)
    task.delay(0.2, function()
        DataBus:ReleaseControl("Movement", "Teleport")
    end)
    
    return ok
end

-- Телепорт к игроку
function tpToPlayer(partialName)
    if not partialName or partialName == "" then
        addLog("TP   ▸ ⚠ введи имя игрока")
        return false
    end
    local low = string.lower(partialName)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and string.lower(p.Name):find(low, 1, true) then
            local tgtHrp = getHRP(p)
            if not tgtHrp then
                addLog("TP   ▸ ⚠ у " .. p.Name .. " нет HRP (мёртв?)")
                return false
            end
            -- БАГ #13 FIX: CFrame * new(0,0,3) мог поместить игрока в воздух/стену.
            -- Делаем raycast вниз из точки смещения, чтобы найти реальную поверхность.
            local rawOffset = tgtHrp.CFrame * CFrame.new(0, 0, 3)
            local rayOrigin = rawOffset.Position + Vector3.new(0, 5, 0)
            local groundParams = RaycastParams.new()
            groundParams.FilterType = Enum.RaycastFilterType.Blacklist
            groundParams.FilterDescendantsInstances = { p.Character, LocalPlayer.Character }
            local groundHit = workspace:Raycast(rayOrigin, Vector3.new(0, -20, 0), groundParams)
            local safePos = groundHit and (groundHit.Position + Vector3.new(0, 3, 0))
                                       or rawOffset.Position
            return doTeleport(safePos, "→" .. p.Name)
        end
    end
    addLog("TP   ▸ игрок не найден: " .. partialName)
    return false
end

-- Телепорт назад
function tpBack()
    if #tpHistory < 2 then
        addLog("TP   ▸ история пуста")
        return
    end
    local entry = tpHistory[2]
    doTeleport(entry.pos, "back:" .. entry.label)
end

-- Loop TP: повторный телепорт к выбранному игроку из GUI.
local loopTpActive = false
local loopTpTarget = ""
local loopTpInterval = 0.35

function startLoopTP(partialName, interval)
    if not partialName or partialName == "" then
        addLog("TP   ▸ ⚠ введи имя игрока для Loop TP")
        return false
    end

    loopTpTarget = partialName
    loopTpInterval = interval or loopTpInterval

    if loopTpActive then
        addLog("TP   ▸ Loop TP target updated: " .. loopTpTarget)
        return true
    end

    loopTpActive = true
    addLog("TP   ▸ Loop TP started: " .. loopTpTarget)

    task.spawn(function()
        while loopTpActive do
            -- БАГ #14 FIX: проверяем что игрок ещё в игре до телепорта,
            -- иначе tpToPlayer давал спам "не найден" в консоль
            local targetStillOnline = false
            local low = loopTpTarget:lower()
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Name:lower():find(low, 1, true) then
                    targetStillOnline = true
                    break
                end
            end
            if not targetStillOnline then
                addLog("TP   ▸ Loop TP: игрок вышел, остановка")
                loopTpActive = false
                break
            end

            local ok = pcall(tpToPlayer, loopTpTarget)
            if not ok then
                addLog("TP   ▸ ❌ Loop TP error")
            end
            task.wait(loopTpInterval)
        end
    end)

    return true
end

function stopLoopTP()
    if loopTpActive then
        addLog("TP   ▸ Loop TP stopped")
    end
    loopTpActive = false
    loopTpTarget = ""
end

-- Click-TP обработчик (Ctrl + ЛКМ)
function handleClickTP(input)
    if not teleportEnabled then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then return end

    local mPos = UserInputService:GetMouseLocation()
    local ray = camera:ScreenPointToRay(mPos.X, mPos.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character }

    local result = workspace:Raycast(ray.Origin, ray.Direction * 10000, params)
    if not result then return end

    local tgtPos = result.Position + Vector3.new(0, 3, 0)
    doTeleport(tgtPos, "click")
end

-- Быстрое сохранение и переход к вейпоинту
function tpQuickSave()
    waypointSave("quick")
    notify("Waypoint", "Позиция сохранена как 'quick'", 2)
end

function tpQuickGoto()
    waypointGoto("quick")
end

addLog("TP   ▸ teleport.lua loaded (click/nick/history/loop/waypoints)")
