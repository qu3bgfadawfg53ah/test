-- ═══════════════════════════════════════════════════════════════════
--  main_loop.lua  —  Advanced Task Scheduler
--  Загружается ПОСЛЕДНИМ
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- [БАГ #5 FIX] Инициализация переменных TriggerBot
-- isTriggerBotEnabled и aimLockedTarget не были объявлены —
-- первое использование в Heartbeat давало nil при обращении.
-- ═══════════════════════════════════════════════════════════════════
isTriggerBotEnabled = isTriggerBotEnabled or false
aimLockedTarget     = aimLockedTarget     or nil

-- ═══════════════════════════════════════════════════════════════════
-- [БАГ #5 FIX] hasDirectLoS — функция не была определена нигде в коде.
-- Raycast от origin к target; игнорируем character цели и LocalPlayer.
-- ═══════════════════════════════════════════════════════════════════
local _losParams = RaycastParams.new()
_losParams.FilterType = Enum.RaycastFilterType.Blacklist

function hasDirectLoS(origin, targetPos, targetCharacter)
    local filter = { LocalPlayer.Character }
    if targetCharacter then
        table.insert(filter, targetCharacter)
    end
    _losParams.FilterDescendantsInstances = filter

    local direction = (targetPos - origin)
    local result = workspace:Raycast(origin, direction, _losParams)
    -- Если raycast ничего не задел — прямая видимость есть
    return result == nil
end

-- ═══════════════════════════════════════════════════════════════════
-- [TASK SCHEDULER]
-- Умная система обновлений модулей по приоритетам
-- ═══════════════════════════════════════════════════════════════════

local UpdateScheduler = {
    _timers = {
        MEDIUM = 0,  -- Обновляется 10 раз в секунду
        LOW = 0      -- Обновляется 1 раз в секунду
    },
    _intervals = ENGINE_CONFIG and ENGINE_CONFIG.scheduler and ENGINE_CONFIG.scheduler.intervals or {
        MEDIUM = 0.10,  -- 100ms
        LOW = 1.0       -- 1000ms
    }
}

-- ═══════════════════════════════════════════════════════════════════
-- [HIGH PRIORITY LOOP]
-- Обновляется каждый кадр (Heartbeat)
-- Модули: Targeting, Movement, Kinematics
-- ═══════════════════════════════════════════════════════════════════
RunService.Heartbeat:Connect(function(dt)
    local myChar = LocalPlayer.Character
    if not myChar then return end
    
    -- Обновление HIGH priority модулей через Registry
    if ModuleRegistry then
        ModuleRegistry:UpdateAllModules(dt, "HIGH")
    end
    
    -- Совместимость со старым кодом
    -- БАГ #20 FIX: операции с инстансами не были в pcall — один удалённый объект
    -- крашил весь Heartbeat. Теперь каждый блок защищён pcall.
    local hum = myChar:FindFirstChildOfClass("Humanoid")
    local hrp = myChar:FindFirstChild("HumanoidRootPart")
    
    if speedEnabled and hum then
        pcall(function() hum.WalkSpeed = speedValue end)
    end
    
    if spinEnabled and hrp then
        pcall(function() hrp.CFrame = hrp.CFrame * getSpinDelta(dt) end)
    end
    
    if flyEnabled then
        pcall(function()
            local ac = _G.PlayerKinematicsSystem and _G.PlayerKinematicsSystem._aerialController
            if ac then
                ac._aerialVelocityMagnitude = flySpeed
                ac._inertialDampingEnabled  = flyInertia
            end
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- [MEDIUM/LOW PRIORITY LOOP]
-- RenderStepped для визуальных обновлений
-- Модули: ESP, Visuals, Environment Rendering
-- ═══════════════════════════════════════════════════════════════════
RunService.RenderStepped:Connect(function(dt)
    -- Обновление таймеров
    UpdateScheduler._timers.MEDIUM = UpdateScheduler._timers.MEDIUM + dt
    UpdateScheduler._timers.LOW = UpdateScheduler._timers.LOW + dt
    
    -- MEDIUM Priority (10 раз в секунду)
    if UpdateScheduler._timers.MEDIUM >= UpdateScheduler._intervals.MEDIUM then
        UpdateScheduler._timers.MEDIUM = 0
        
        if ModuleRegistry then
            ModuleRegistry:UpdateAllModules(dt, "MEDIUM")
        end
        
        -- ESP метки (совместимость)
        if espEnabled then 
            pcall(updateESPLabels) 
        end
    end
    
    -- LOW Priority (1 раз в секунду)
    if UpdateScheduler._timers.LOW >= UpdateScheduler._intervals.LOW then
        UpdateScheduler._timers.LOW = 0
        
        if ModuleRegistry then
            ModuleRegistry:UpdateAllModules(dt, "LOW")
        end
    end
    
    -- FOV квадрат (всегда обновляется каждый кадр)
    if fovSquare and fovSquare.Visible then
        local inset = GuiService:GetGuiInset()
        local m     = UserInputService:GetMouseLocation()
        fovSquare.Size     = UDim2.fromOffset(fovHalfSize * 2, fovHalfSize * 2)
        fovSquare.Position = UDim2.fromOffset(
            m.X - fovHalfSize,
            m.Y - fovHalfSize - inset.Y)
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- [TRIGGER BOT]
    -- Автоматическая стрельба при наведении
    -- ═══════════════════════════════════════════════════════════════
    if not isTriggerBotEnabled then return end
    if not espEnabled then
        forceDisableTriggerBot("ESP disabled")
        return
    end
    
    local equippedTool = LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not equippedTool then return end
    if not aimLockedTarget then return end
    
    local now = tick()
    if now - lastTriggerFireAt < triggerCooldownSec then return end
    if now - lastTargetScanAt  < 0.05              then return end
    lastTargetScanAt = now
    
    local tgt = getBestTarget(allowWallbang)
    if not tgt or not tgt.Character then return end
    
    local aimPart = tgt.Character:FindFirstChild(aimPartName)
                 or tgt.Character:FindFirstChild("HumanoidRootPart")
    if not aimPart then return end
    
    local hum = tgt.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    
    if not allowWallbang then
        if not hasDirectLoS(camera.CFrame.Position, aimPart.Position, tgt.Character) then
            return
        end
    end
    
    simulateLMB()
    lastTriggerFireAt = now
    addLog("BOT ▸ 🔫 " .. tgt.Name)
end)

-- ═══════════════════════════════════════════════════════════════════
-- [INPUT HANDLER]
-- Обработка пользовательского ввода
-- ═══════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
    -- ═══════════════════════════════════════════════════════════════
    -- [AIM ASSIST]
    -- Удержание ПКМ для автоматического прицеливания
    -- ═══════════════════════════════════════════════════════════════
    if input.UserInputType == aimKey and isAimAssistEnabled then
        -- Проверка контроля камеры через Data Bus
        if DataBus and not DataBus:RequestControl("Camera", "AimAssist", 10) then
            addLog("AIM ▸ Camera busy")
            return
        end
        
        task.spawn(function()
            local lastLocked = nil
            while UserInputService:IsMouseButtonPressed(aimKey) do
                local tgt = getBestTarget(allowWallbang)
                if tgt then
                    if tgt ~= lastLocked then
                        lastLocked      = tgt
                        aimLockedTarget = tgt
                        addLog("AIM ▸ locked: " .. tgt.Name)
                    end
                    aimCameraAt(getAimPos(tgt))
                else
                    lastLocked      = nil
                    aimLockedTarget = nil
                end
                RunService.Heartbeat:Wait()
            end
            aimLockedTarget = nil
            
            -- Освобождение контроля камеры
            if DataBus then
                DataBus:ReleaseControl("Camera", "AimAssist")
            end
            
            if lastLocked then addLog("AIM ▸ released") end
        end)
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- [CLICK TELEPORT]
    -- Ctrl + ЛКМ для телепортации
    -- ═══════════════════════════════════════════════════════════════
    if input.UserInputType == Enum.UserInputType.MouseButton1
       and teleportEnabled
       and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        pcall(handleClickTP, input)
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- [СИСТЕМА МОНИТОРИНГА]
-- Проверка окружения и защита
-- ═══════════════════════════════════════════════════════════════════
task.spawn(function()
    task.wait(1)
    
    -- Проверка FilteringEnabled
    local _feOk, feEnabled = pcall(function() return workspace.FilteringEnabled end)
    feEnabled = _feOk and feEnabled
    if feEnabled then
        addLog("SYS  ▸ FE=ON (local effects only)")
    else
        addLog("SYS  ▸ FE=OFF (full control)")
    end
    
    -- Проверка CFrame доступа
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local ok = pcall(function() local _ = hrp.CFrame end)
        addLog("SYS  ▸ CFrame access: " .. (ok and "✅ OK" or "❌ BLOCKED"))
    end
    
    -- Проверка AlignPosition
    local hasAlignPos = pcall(function()
        local ap = Instance.new("AlignPosition"); ap:Destroy()
    end)
    addLog("SYS  ▸ AlignPosition: " .. (hasAlignPos and "✅ available" or "❌ unavailable"))
    
    addLog("SYS  ▸ Players on server: " .. #Players:GetPlayers())
    
    -- ═══════════════════════════════════════════════════════════════
    -- [ОПТИМИЗИРОВАННЫЙ МОНИТОРИНГ АНТИЧИТА]
    -- Используем кэширование вместо повторного GetDescendants()
    -- ═══════════════════════════════════════════════════════════════
    task.spawn(function()
        local scriptCache = {}
        local suspiciousCount = 0
        
        -- Кэшируем существующие скрипты при старте
        -- БАГ #11 FIX: GetDescendants() блокировал выполнение 1-2 сек на больших картах.
        -- Теперь скан асинхронный — батчи по 150 объектов с task.wait() между ними.
        local function scanScripts()
            scriptCache = {}
            suspiciousCount = 0
            local BATCH = 150
            local all = workspace:GetDescendants()
            for i = 1, #all, BATCH do
                for j = i, math.min(i + BATCH - 1, #all) do
                    local descendant = all[j]
                    if descendant:IsA("LocalScript") or descendant:IsA("Script") then
                        local name = descendant.Name:lower()
                        if name:find("anti") or name:find("detect") or name:find("check") then
                            scriptCache[descendant] = true
                            suspiciousCount = suspiciousCount + 1
                        end
                    end
                end
                task.wait()  -- уступаем поток между батчами
            end
        end
        
        -- Начальное сканирование
        scanScripts()
        
        if suspiciousCount > 0 then
            addLog("⚠️ Suspicious scripts: " .. suspiciousCount)
        end
        
        -- Слушаем новые скрипты (только workspace для производительности)
        workspace.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("LocalScript") or descendant:IsA("Script") then
                local name = descendant.Name:lower()
                if name:find("anti") or name:find("detect") or name:find("check") then
                    if not scriptCache[descendant] then
                        scriptCache[descendant] = true
                        suspiciousCount = suspiciousCount + 1
                        addLog("⚠️ New suspicious script: " .. descendant.Name)
                    end
                end
            end
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- [ИНИЦИАЛИЗАЦИЯ ЗАВЕРШЕНА]
-- ═══════════════════════════════════════════════════════════════════
addLog("CORE ▸ Task Scheduler initialized")
addLog("CORE ▸ HIGH priority: every frame")
addLog("CORE ▸ MEDIUM priority: 10Hz")
addLog("CORE ▸ LOW priority: 1Hz")
addLog("ESP  ▸ tracking " .. math.max(#Players:GetPlayers() - 1, 0) .. " players")

-- ═══════════════════════════════════════════════════════════════════
-- БАГ #32 FIX: Обработка respawn игрока
-- При смерти и респавне некоторые системы не переинициализировались
-- ═══════════════════════════════════════════════════════════════════
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    addLog("CORE ▸ 🔄 Character respawned, reinitializing systems...")
    
    -- Ждём полной загрузки персонажа
    task.wait(0.5)
    
    -- Переинициализация PlayerKinematicsSystem
    if _G.PlayerKinematicsSystem then
        pcall(function()
            _G.PlayerKinematicsSystem:_reinitializeCharacterReference()
            addLog("CORE ▸ ✅ PlayerKinematicsSystem reinitialized")
        end)
    end
    
    -- Переинициализация PlayerVisualTracker
    if _G.MenuV1_PVT then
        pcall(function()
            -- Обновляем кэш частей персонажа
            task.wait(0.2)
            _G.MenuV1_PVT:_executeFullSystemRefresh()
            addLog("CORE ▸ ✅ PlayerVisualTracker refreshed")
        end)
    end
    
    -- Сброс DataBus приоритетов (персонаж новый)
    if DataBus then
        pcall(function()
            DataBus._controlPriorities = {
                Camera = nil,
                Movement = nil,
                Character = nil
            }
            addLog("CORE ▸ ✅ DataBus priorities reset")
        end)
    end
    
    -- Обновление MetatableProxy оригинальных значений
    if MetatableProxy then
        pcall(function()
            task.wait(0.3)
            MetatableProxy:UpdateOriginalValues()
            addLog("CORE ▸ ✅ MetatableProxy updated")
        end)
    end
    
    addLog("CORE ▸ ✅ All systems reinitialized after respawn")
end)

-- Горячая клавиша для экстренного отключения
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
    -- Delete = экстренное отключение
    if input.KeyCode == Enum.KeyCode.Delete then
        if _G.EmergencyShutdown then
            _G.EmergencyShutdown()
        end
    end
end)
