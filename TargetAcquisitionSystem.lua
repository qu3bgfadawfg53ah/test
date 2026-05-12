-- ═══════════════════════════════════════════════════════════════════
--  TargetAcquisitionSystem.lua — Advanced OOP Targeting System V2.0
--  Enhanced with Perfect Prediction and Multi-Point Scanning
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] TargetingConfiguration
-- Управление конфигурацией системы прицеливания
-- ═══════════════════════════════════════════════════════════════════
local TargetingConfiguration = {}
TargetingConfiguration.__index = TargetingConfiguration

function TargetingConfiguration.new()
    local self = setmetatable({}, TargetingConfiguration)
    
    -- Режимы работы
    self._aimEnabled = false  -- assisted aiming enabled (обфусцировано)
    self._silentEnabled = false  -- silent targeting enabled
    self._autoFireEnabled = false  -- automatic fire enabled
    self._wallbangAllowed = false  -- wall penetration allowed
    
    -- Параметры управления
    self._activationInput = Enum.UserInputType.MouseButton2  -- activation input
    self._targetBodyPart = "Head"                            -- target body part
    self._smoothness = 0.15                              -- camera smoothness
    self._fovBoundary = 120                               -- viewport boundary
    self._showFovIndicator = false                             -- viewport indicator visibility
    
    -- Система предсказания (Enhanced)
    self._predictionEnabled = false                             -- trajectory prediction active (ОТКЛЮЧЕНО для точного прицела)
    self._predictionMult = 0.0                               -- prediction multiplier (установлено в 0)
    self._perfectPrediction = false                             -- perfect prediction mode (ОТКЛЮЧЕНО)
    self._multiPointEnabled = true                              -- multi-point scanning
    
    -- Таймеры
    self._fireCooldown = 0.10   -- fire interval cooldown
    self._lastFireTime = 0      -- last fire timestamp
    self._lastScanTime = 0      -- last target scan timestamp
    
    -- Состояние
    self._equippedTool = nil    -- current equipped tool
    self._lockedTarget = nil    -- current locked target
    
    return self
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] AdvancedNetworkAnalyzer
-- Анализ сетевых параметров для точного предсказания
-- ═══════════════════════════════════════════════════════════════════
local AdvancedNetworkAnalyzer = {}
AdvancedNetworkAnalyzer.__index = AdvancedNetworkAnalyzer

function AdvancedNetworkAnalyzer.new()
    local self = setmetatable({}, AdvancedNetworkAnalyzer)
    self._pingAvg = 0     -- average ping
    self._pingLastCheck = 0     -- last ping check time
    return self
end

-- Получение текущего пинга
function AdvancedNetworkAnalyzer:_getCurrentPingMilliseconds()
    local now = tick()
    
    -- Кэширование пинга (обновляем раз в секунду)
    if now - self._pingLastCheck < 1.0 then
        return self._pingAvg
    end
    
    self._pingLastCheck = now
    
    local pingValue = 0
    pcall(function()
        local stats = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]
        pingValue = stats:GetValue()
    end)
    
    self._pingAvg = pingValue
    return pingValue
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] MultiPointScanner
-- Сканирование всех точек тела для оптимального прицеливания
-- ═══════════════════════════════════════════════════════════════════
local MultiPointScanner = {}
MultiPointScanner.__index = MultiPointScanner

function MultiPointScanner.new()
    local self = setmetatable({}, MultiPointScanner)
    
    -- Приоритеты частей тела (чем выше, тем лучше)
    self._bodyPartPriority = {
        Head = 10,
        UpperTorso = 7,
        LowerTorso = 6,
        ["Left Arm"] = 4,
        ["Right Arm"] = 4,
        ["Left Leg"] = 3,
        ["Right Leg"] = 3,
        HumanoidRootPart = 5
    }
    
    return self
end

-- Сканирование всех частей тела и выбор лучшей видимой точки
function MultiPointScanner:_scanAllBodyParts(targetCharacter, allowWallPenetration)
    if not targetCharacter then return nil, 0 end
    
    local cameraPosition = camera.CFrame.Position
    local bestPart, bestScore = nil, -1
    
    -- ОПТИМИЗАЦИЯ: сканируем только основные части тела вместо всех BasePart
    local bodyPartsToScan = {
        "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
        "Left Arm", "Right Arm", "Left Leg", "Right Leg"
    }
    
    -- ИСПРАВЛЕНИЕ: RaycastParams создаётся ОДИН РАЗ за пределами цикла.
    -- Раньше он создавался на каждый bodyPart (до 8× за вызов × кол-во игроков).
    -- Это была главная причина лагов при ESP/targeting.
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, targetCharacter}
    raycastParams.IgnoreWater = true
    
    for _, partName in ipairs(bodyPartsToScan) do
        local bodyPart = targetCharacter:FindFirstChild(partName)
        if not bodyPart or not bodyPart:IsA("BasePart") then continue end
        
        -- Получаем приоритет части тела
        local priority = self._bodyPartPriority[bodyPart.Name] or 1
        
        -- Проверка видимости
        local rayDirection = bodyPart.Position - cameraPosition
        if rayDirection.Magnitude < 0.001 then continue end
        
        local raycastResult = workspace:Raycast(cameraPosition, rayDirection, raycastParams)
        
        local isVisible = false
        if not raycastResult then
            isVisible = true
        elseif raycastResult.Instance and raycastResult.Instance:IsDescendantOf(targetCharacter) then
            isVisible = true
        elseif allowWallPenetration then
            isVisible = true
        end
        
        if isVisible then
            -- Вычисляем score на основе приоритета и расстояния
            local distance = (bodyPart.Position - cameraPosition).Magnitude
            local score = priority / (distance * 0.01 + 1)
            
            if score > bestScore then
                bestScore = score
                bestPart = bodyPart
            end
        end
    end
    
    return bestPart, bestScore
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] PerfectTrajectoryPredictor
-- Математически точное предсказание с учетом пинга и физики
-- ═══════════════════════════════════════════════════════════════════
local PerfectTrajectoryPredictor = {}
PerfectTrajectoryPredictor.__index = PerfectTrajectoryPredictor

function PerfectTrajectoryPredictor.new(configRef, networkAnalyzer)
    local self = setmetatable({}, PerfectTrajectoryPredictor)
    self._config = configRef
    self._network = networkAnalyzer
    return self
end

-- Вычисление предсказания с учетом всех факторов
function PerfectTrajectoryPredictor:_computePerfectPrediction(targetPlayer, targetBodyPart)
    if not (targetPlayer and targetPlayer.Character and targetBodyPart) then 
        return nil 
    end
    
    local hrp = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return targetBodyPart.Position end
    
    local basePosition = targetBodyPart.Position
    
    -- Если предсказание отключено
    if not self._config._predictionEnabled then
        return basePosition
    end
    
    -- Получаем параметры движения
    local velocity = hrp.AssemblyLinearVelocity
    local acceleration = Vector3.new(0, 0, 0)
    
    -- Вычисляем ускорение (если цель меняет направление)
    if self._config._perfectPrediction then  -- Perfect prediction mode
        local hum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            -- Учитываем MoveDirection для предсказания изменения направления
            local moveDir = hum.MoveDirection
            if moveDir.Magnitude > 0.1 then
                acceleration = moveDir * hum.WalkSpeed * 0.5
            end
        end
    end
    
    -- Получаем пинг
    local ping = self._network:_getCurrentPingMilliseconds()
    local pingSeconds = ping / 1000
    
    -- Расстояние до цели
    local distanceToTarget = (camera.CFrame.Position - basePosition).Magnitude
    
    -- Время полета снаряда (приблизительно)
    local projectileSpeed = 1000  -- стандартная скорость пули
    local projectileFlightTime = distanceToTarget / projectileSpeed
    
    -- Общее время задержки = пинг + время полета
    local totalPredictionTime = pingSeconds + projectileFlightTime + 
        self._config._predictionMult  -- + базовый множитель предсказания
    
    -- Формула кинематики: s = ut + 0.5at²
    local predictedPosition = basePosition + 
        (velocity * totalPredictionTime) + 
        (acceleration * 0.5 * totalPredictionTime * totalPredictionTime)
    
    -- ВАЖНО: не вычитаем workspace.Gravity из точки прицеливания.
    -- Для камеры/лучевого оружия гравитация мира уже отражена в реальной
    -- позиции и AssemblyLinearVelocity персонажа. Повторная поправка
    -- опускала predictedPosition ниже модели, из-за чего прицел уходил
    -- в землю при наведении на цель.
    return predictedPosition
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] ViewportAnalyzer (Enhanced)
-- ═══════════════════════════════════════════════════════════════════
local ViewportAnalyzer = {}
ViewportAnalyzer.__index = ViewportAnalyzer

function ViewportAnalyzer.new(configRef, multiPointScanner)
    local self = setmetatable({}, ViewportAnalyzer)
    self._config = configRef
    self._scanner = multiPointScanner
    return self
end

-- Проверка точки в FOV
function ViewportAnalyzer:_isPointWithinFOV(screenPosition2D)
    local mouseLocation = UserInputService:GetMouseLocation()
    local deltaX = math.abs(screenPosition2D.X - mouseLocation.X)
    local deltaY = math.abs(screenPosition2D.Y - mouseLocation.Y)
    
    local isWithinBounds = (deltaX <= self._config._fovBoundary 
        and deltaY <= self._config._fovBoundary)
    local distanceMetric = math.max(deltaX, deltaY)
    
    return isWithinBounds, distanceMetric
end

-- Получение оптимальной цели (Enhanced с Multi-Point)
-- Возвращает: (closestTarget, bestBodyPartForTarget) — чтобы избежать двойного скана в OnUpdate
function ViewportAnalyzer:_acquireOptimalTarget(allowWallPenetration)
    local cameraPos = camera.CFrame.Position
    local closestTarget, bestScore = nil, -1
    local closestBodyPart = nil  -- ИСПРАВЛЕНИЕ: кэшируем лучший bodyPart вместе с целью
    
    for _, player in ipairs(Players:GetPlayers()) do
        if not isEnemy(player) or not player.Character then continue end
        
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then continue end
        
        -- Multi-Point Scanning: сканируем все части тела
        local bestBodyPart, partScore = nil, 0
        
        if self._config._multiPointEnabled then  -- Multi-point scanning enabled
            bestBodyPart, partScore = self._scanner:_scanAllBodyParts(
                player.Character, allowWallPenetration)
        else
            -- Fallback к старому методу
            bestBodyPart = player.Character:FindFirstChild(self._config._targetBodyPart) or
                          player.Character:FindFirstChild("HumanoidRootPart")
            -- ИСПРАВЛЕНИЕ: раньше partScore оставался 0, и все цели получали одинаковый
            -- score 0/(distMetric+1) = 0. Выбирался первый игрок в списке независимо от
            -- позиции. Теперь используем обратное расстояние от камеры как базовый score.
            if bestBodyPart then
                local dist = (bestBodyPart.Position - cameraPos).Magnitude
                partScore = 1.0 / (dist * 0.01 + 1)
            end
        end
        
        if not bestBodyPart then continue end
        
        -- Проверка видимости на экране
        local viewportPos, isOnScreen = camera:WorldToViewportPoint(bestBodyPart.Position)
        if not isOnScreen then continue end
        
        -- Проверка в пределах FOV
        local isInFOV, distMetric = self:_isPointWithinFOV(
            Vector2.new(viewportPos.X, viewportPos.Y))
        if not isInFOV then continue end
        
        -- Вычисляем итоговый score
        local finalScore = partScore / (distMetric + 1)
        
        -- БАГ #15 FIX: при равном finalScore выбирался случайный игрок (первый в списке).
        -- Теперь используем дистанцию до камеры как тайбрейкер.
        local isBetter = finalScore > bestScore
        if not isBetter and finalScore == bestScore and closestTarget then
            local currentDist  = (bestBodyPart and (bestBodyPart.Position - cameraPos).Magnitude) or math.huge
            local previousPart = closestBodyPart
            local previousDist = previousPart and (previousPart.Position - cameraPos).Magnitude or math.huge
            isBetter = currentDist < previousDist
        end

        if isBetter then
            closestTarget = player
            bestScore = finalScore
            closestBodyPart = bestBodyPart
        end
    end
    
    -- БАГ #3 FIX: если цели не нашлось — явно возвращаем nil, nil
    -- чтобы вызывающий код не получил частичный результат.
    if not closestTarget then
        return nil, nil
    end
    
    return closestTarget, closestBodyPart  -- возвращаем оба значения
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] AutoTargetingController (Enhanced)
-- ═══════════════════════════════════════════════════════════════════
local AutoTargetingController = {}
AutoTargetingController.__index = AutoTargetingController

function AutoTargetingController.new()
    local self = setmetatable({}, AutoTargetingController)
    
    self._config = TargetingConfiguration.new()
    self._network = AdvancedNetworkAnalyzer.new()
    self._scanner = MultiPointScanner.new()
    self._viewport = ViewportAnalyzer.new(self._config, self._scanner)
    self._predictor = PerfectTrajectoryPredictor.new(self._config, self._network)
    
    return self
end

-- Мгновенный захват цели (Instant Lock)
function AutoTargetingController:_instantLockCamera(worldTargetPosition)
    if not worldTargetPosition then return end
    
    local currentPos = camera.CFrame.Position
    camera.CFrame = CFrame.new(currentPos, worldTargetPosition)
end

-- Плавное наведение камеры
function AutoTargetingController:_smoothAimCamera(worldTargetPosition)
    if not worldTargetPosition then return end
    
    local currentFrame = camera.CFrame
    local desiredDir = (worldTargetPosition - currentFrame.Position).Unit
    local smoothFactor = 1 - math.clamp(self._config._smoothness, 0, 0.999)
    local interpolatedDir = currentFrame.LookVector:Lerp(desiredDir, smoothFactor)
    
    camera.CFrame = CFrame.new(currentFrame.Position, currentFrame.Position + interpolatedDir)
end

-- OnUpdate для интеграции с Module Registry
function AutoTargetingController:OnUpdate(deltaTime)
    if not self._config._aimEnabled then return end  -- assisted aiming disabled
    
    -- Проверка контроля камеры через Data Bus
    if DataBus and not DataBus:HasControl("Camera", "TargetingSystem") then
        if not DataBus:RequestControl("Camera", "TargetingSystem", 10) then
            return  -- Камера занята другим модулем
        end
    end
    
    -- Получение оптимальной цели.
    -- ИСПРАВЛЕНИЕ: _acquireOptimalTarget теперь возвращает и bestPart,
    -- поэтому двойного сканирования (_scanAllBodyParts снова ниже) больше нет.
    local target, bestPart = self._viewport:_acquireOptimalTarget(self._config._wallbangAllowed)
    
    if target and target.Character then
        -- Если multi-point отключён, bestPart уже выбран в _acquireOptimalTarget.
        -- Если включён — тоже. Дополнительный вызов _scanAllBodyParts не нужен.
        
        if bestPart then
            -- Perfect Prediction
            local predictedPos = self._predictor:_computePerfectPrediction(target, bestPart)
            
            -- Применяем наведение
            if self._config._smoothness > 0.01 then
                self:_smoothAimCamera(predictedPos)
            else
                self:_instantLockCamera(predictedPos)  -- Мгновенный захват
            end
            
            self._config._lockedTarget = target
        end
    else
        self._config._lockedTarget = nil
        
        -- Освобождаем контроль камеры
        if DataBus then
            DataBus:ReleaseControl("Camera", "TargetingSystem")
        end
    end
end

function AutoTargetingController:OnEnable()
    addLog("TARGET ▸ System enabled")
    addLog("TARGET ▸ Perfect Prediction: " .. tostring(self._config._perfectPrediction))
    addLog("TARGET ▸ Multi-Point Scan: " .. tostring(self._config._multiPointEnabled))
end

function AutoTargetingController:OnDisable()
    self._config._lockedTarget = nil
    addLog("TARGET ▸ System disabled")
end

-- ═══════════════════════════════════════════════════════════════════
-- [РЕГИСТРАЦИЯ МОДУЛЯ]
-- ═══════════════════════════════════════════════════════════════════
local targetingSystemInstance = AutoTargetingController.new()
targetingSystemInstance.Name = "TargetingSystem"
targetingSystemInstance.Enabled = false

if ModuleRegistry then
    ModuleRegistry:Register(targetingSystemInstance, "HIGH")
end

-- ═══════════════════════════════════════════════════════════════════
-- [СОВМЕСТИМОСТЬ СО СТАРЫМ КОДОМ]
-- ═══════════════════════════════════════════════════════════════════
_G.TargetingSystem = targetingSystemInstance

function getBestTarget(allowWallbang)
    -- _acquireOptimalTarget теперь возвращает (target, bodyPart), нам нужен только target
    local target, _ = targetingSystemInstance._viewport:_acquireOptimalTarget(allowWallbang)
    return target
end

function getAimPos(target)
    if not (target and target.Character) then return nil end
    
    -- ИСПРАВЛЕНИЕ: переиспользуем _acquireOptimalTarget чтобы не делать третий скан,
    -- но getAimPos вызывается когда цель уже известна — делаем скан только для неё.
    local bestPart = targetingSystemInstance._scanner:_scanAllBodyParts(
        target.Character, targetingSystemInstance._config._wallbangAllowed)
    
    if not bestPart then return nil end
    
    return targetingSystemInstance._predictor:_computePerfectPrediction(target, bestPart)
end

function aimCameraAt(position)
    if not position then return end
    targetingSystemInstance:_smoothAimCamera(position)
end

addLog("TARGET ▸ Advanced Targeting System V2.0 loaded")
