-- ═══════════════════════════════════════════════════════════════════
--  PlayerKinematicsControlSystem.lua — Advanced OOP Player Movement System
--  Обфусцированный модуль управления кинематикой и физикой игрока

--  АРХИТЕКТУРА:
--  - VelocityManipulationEngine: управление скоростью передвижения
--  - AerialLocomotionController: управление полетом персонажа
--  - CollisionNegationProcessor: управление прохождением сквозь стены (NoClip)
--  - RotationalMomentumSimulator: управление вращением персонажа
--  - GravityDefyingJumpModifier: управление бесконечным прыжком
--  - PlayerKinematicsControlSystem: главный менеджер движения
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- [БАГ #4 FIX] Ранняя инициализация jump-флагов
-- infiniteJumpEnabled/jumpBoostEnabled/jumpBoostForce объявлялись
-- в конце файла (строки 532-536), но _setupJumpModifier мог
-- вызваться раньше. jumpBoostForce == nil вызывал краш в Vector3.new().
-- ═══════════════════════════════════════════════════════════════════
infiniteJumpEnabled = infiniteJumpEnabled or false
jumpBoostEnabled    = jumpBoostEnabled    or false
jumpBoostForce      = jumpBoostForce      or 60

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] VelocityManipulationEngine
-- Управление скоростью передвижения персонажа
-- ═══════════════════════════════════════════════════════════════════
local VelocityManipulationEngine = {}
VelocityManipulationEngine.__index = VelocityManipulationEngine

function VelocityManipulationEngine.new()
    local self = setmetatable({}, VelocityManipulationEngine)
    
    -- Параметры двигателя скорости
    self._velocityEnhancementActive = false              -- состояние: увеличение скорости активно
    self._targetVelocityMagnitude = 28                   -- целевая скорость движения
    self._baselineVelocityMagnitude = 16                 -- базовая скорость персонажа
    
    return self
end

-- Применение модифицированной скорости
function VelocityManipulationEngine:_applyModifiedVelocity(targetSpeed)
    self._targetVelocityMagnitude = targetSpeed
    
    local characterModel = LocalPlayer.Character
    if not characterModel then return end
    
    local humanoidComponent = characterModel:FindFirstChildOfClass("Humanoid")
    if humanoidComponent then
        humanoidComponent.WalkSpeed = targetSpeed
        addLog("PKCS ▸ Velocity modified: " .. targetSpeed .. " studs/s")
    end
end

-- Восстановление базовой скорости
function VelocityManipulationEngine:_restoreBaselineVelocity()
    local characterModel = LocalPlayer.Character
    if not characterModel then return end
    
    local humanoidComponent = characterModel:FindFirstChildOfClass("Humanoid")
    if humanoidComponent then
        humanoidComponent.WalkSpeed = self._baselineVelocityMagnitude
        addLog("PKCS ▸ Baseline velocity restored")
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] AerialLocomotionController
-- Система управления полетом персонажа
-- ═══════════════════════════════════════════════════════════════════
local AerialLocomotionController = {}
AerialLocomotionController.__index = AerialLocomotionController

function AerialLocomotionController.new()
    local self = setmetatable({}, AerialLocomotionController)
    
    -- Параметры воздушной локомоции
    self._aerialLocomotionActive = false                 -- состояние: полет активен
    self._aerialVelocityMagnitude = 60                   -- скорость полета
    self._inertialDampingEnabled = true                  -- инерция включена
    self._inertialDecayCoefficient = 0.90                -- коэффициент затухания инерции
    
    -- Физические объекты управления
    self._bodyVelocityInstance = nil                     -- BodyVelocity для движения
    self._bodyGyroscopeInstance = nil                    -- BodyGyro для ориентации
    self._physicsCycleConnection = nil                   -- подключение физического цикла
    
    -- Архив состояний коллизии частей
    self._collisionStateArchive = {}                     -- {part, original_CanCollide}
    
    return self
end

-- Вычисление вектора направления полета на основе ввода
function AerialLocomotionController:_computeFlightDirectionVector()
    local cameraCFrame = camera.CFrame
    local forwardVector = cameraCFrame.LookVector
    local rightVector = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z)
    
    if rightVector.Magnitude > 0.001 then
        rightVector = rightVector.Unit
    end
    
    local directionAccumulator = Vector3.zero
    
    -- Обработка клавиш WASD
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        directionAccumulator = directionAccumulator + forwardVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        directionAccumulator = directionAccumulator - forwardVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        directionAccumulator = directionAccumulator + rightVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        directionAccumulator = directionAccumulator - rightVector
    end
    
    -- Вертикальное движение (Space / Shift)
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        directionAccumulator = directionAccumulator + Vector3.new(0, 1, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) 
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
        directionAccumulator = directionAccumulator - Vector3.new(0, 1, 0)
    end
    
    -- Модификаторы скорости
    local speedMultiplier = 1
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        speedMultiplier = 0.30  -- замедление
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
        speedMultiplier = 2.0   -- ускорение
    end
    
    return directionAccumulator, speedMultiplier
end

-- Активация воздушной локомоции
function AerialLocomotionController:_initiateAerialLocomotion()
    local characterModel = LocalPlayer.Character
    if not characterModel then return end
    
    local humanoidRootPart = characterModel:FindFirstChild("HumanoidRootPart")
    local humanoidComponent = characterModel:FindFirstChildOfClass("Humanoid")
    if not humanoidRootPart or not humanoidComponent then return end
    
    -- Очистка предыдущих экземпляров
    if self._bodyVelocityInstance then
        self._bodyVelocityInstance:Destroy()
    end
    if self._bodyGyroscopeInstance then
        self._bodyGyroscopeInstance:Destroy()
    end
    if self._physicsCycleConnection then
        self._physicsCycleConnection:Disconnect()
    end
    
    -- Отключение автоповорота
    humanoidComponent.AutoRotate = false
    
    -- Архивирование состояний коллизии
    self._collisionStateArchive = {}
    for _, partInstance in pairs(characterModel:GetDescendants()) do
        if partInstance:IsA("BasePart") then
            table.insert(self._collisionStateArchive, {
                part = partInstance,
                originalCollisionState = partInstance.CanCollide
            })
            pcall(function() partInstance.CanCollide = false end)
        end
    end
    
    -- Создание BodyVelocity (управление движением)
    local bodyVelocityObject = Instance.new("BodyVelocity")
    bodyVelocityObject.MaxForce = Vector3.new(100000, 100000, 100000)
    bodyVelocityObject.P = 1250
    bodyVelocityObject.Velocity = Vector3.zero
    bodyVelocityObject.Parent = humanoidRootPart
    self._bodyVelocityInstance = bodyVelocityObject
    
    -- Создание BodyGyro (управление ориентацией)
    local bodyGyroObject = Instance.new("BodyGyro")
    bodyGyroObject.MaxTorque = Vector3.new(400000, 400000, 400000)
    bodyGyroObject.P = 5000
    bodyGyroObject.D = 200
    bodyGyroObject.CFrame = humanoidRootPart.CFrame
    bodyGyroObject.Parent = humanoidRootPart
    self._bodyGyroscopeInstance = bodyGyroObject
    
    -- Текущая скорость для инерции
    local currentVelocityVector = Vector3.zero
    
    -- Физический цикл обновления
    self._physicsCycleConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not self._aerialLocomotionActive then return end
        if not humanoidRootPart or not humanoidRootPart.Parent then
            self._aerialLocomotionActive = false
            return
        end
        
        -- Вычисление целевой скорости
        local directionVector, speedMultiplier = self:_computeFlightDirectionVector()
        local targetVelocityVector
        
        if directionVector.Magnitude > 0.001 then
            -- Активное движение
            targetVelocityVector = directionVector.Unit 
                * self._aerialVelocityMagnitude * speedMultiplier
        else
            -- Инерция или остановка
            if self._inertialDampingEnabled then
                targetVelocityVector = currentVelocityVector * self._inertialDecayCoefficient
                if targetVelocityVector.Magnitude < 0.3 then
                    targetVelocityVector = Vector3.zero
                end
            else
                targetVelocityVector = Vector3.zero
            end
        end
        
        -- Обновление скорости и ориентации
        currentVelocityVector = targetVelocityVector
        self._bodyVelocityInstance.Velocity = targetVelocityVector
        self._bodyGyroscopeInstance.CFrame = CFrame.new(
            humanoidRootPart.Position,
            humanoidRootPart.Position + camera.CFrame.LookVector
        )
        
        -- Принудительное отключение коллизий (для защиты от сброса)
        for _, archiveEntry in ipairs(self._collisionStateArchive) do
            if archiveEntry.part and archiveEntry.part.Parent 
                and archiveEntry.part.CanCollide then
                pcall(function() archiveEntry.part.CanCollide = false end)
            end
        end
    end)
    
    addLog("PKCS ▸ Aerial locomotion initiated")
end

-- Деактивация воздушной локомоции
function AerialLocomotionController:_terminateAerialLocomotion()
    -- Отключение физического цикла
    if self._physicsCycleConnection then
        self._physicsCycleConnection:Disconnect()
        self._physicsCycleConnection = nil
    end
    
    -- Удаление физических объектов
    if self._bodyVelocityInstance then
        self._bodyVelocityInstance:Destroy()
        self._bodyVelocityInstance = nil
    end
    if self._bodyGyroscopeInstance then
        self._bodyGyroscopeInstance:Destroy()
        self._bodyGyroscopeInstance = nil
    end
    
    -- Восстановление автоповорота
    local characterModel = LocalPlayer.Character
    local humanoidComponent = characterModel and characterModel:FindFirstChildOfClass("Humanoid")
    if humanoidComponent then
        humanoidComponent.AutoRotate = true
    end
    
    -- Восстановление коллизий
    for _, archiveEntry in ipairs(self._collisionStateArchive) do
        if archiveEntry.part and archiveEntry.part.Parent then
            pcall(function() 
                archiveEntry.part.CanCollide = archiveEntry.originalCollisionState 
            end)
        end
    end
    self._collisionStateArchive = {}
    
    addLog("PKCS ▸ Aerial locomotion terminated")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] CollisionNegationProcessor
-- Обработка отключения коллизий (NoClip)
-- ═══════════════════════════════════════════════════════════════════
local CollisionNegationProcessor = {}
CollisionNegationProcessor.__index = CollisionNegationProcessor

function CollisionNegationProcessor.new()
    local self = setmetatable({}, CollisionNegationProcessor)
    
    -- Параметры процессора
    self._collisionNegationActive = false                -- состояние: NoClip активен
    
    -- Кэш частей персонажа
    self._characterPartsCacheArray = {}
    self._negationCycleConnection = nil
    
    return self
end

-- Обновление кэша частей персонажа
function CollisionNegationProcessor:_refreshCharacterPartsCache()
    self._characterPartsCacheArray = {}
    
    local characterModel = LocalPlayer.Character
    if not characterModel then return end
    
    for _, descendantInstance in pairs(characterModel:GetDescendants()) do
        if descendantInstance:IsA("BasePart") then
            table.insert(self._characterPartsCacheArray, descendantInstance)
        end
    end
end

-- Инициализация циклического отключения коллизий
function CollisionNegationProcessor:_initiateCollisionNegation()
    if self._negationCycleConnection then
        self._negationCycleConnection:Disconnect()
    end
    
    self._negationCycleConnection = RunService.Stepped:Connect(function()
        if not self._collisionNegationActive then return end
        
        for _, partInstance in ipairs(self._characterPartsCacheArray) do
            if partInstance and partInstance.Parent then
                partInstance.CanCollide = false
            end
        end
    end)
    
    addLog("PKCS ▸ Collision negation initiated")
end

-- Остановка отключения коллизий
function CollisionNegationProcessor:_terminateCollisionNegation()
    self._collisionNegationActive = false
    
    -- Восстановление коллизий
    for _, partInstance in ipairs(self._characterPartsCacheArray) do
        if partInstance and partInstance.Parent then
            pcall(function() partInstance.CanCollide = true end)
        end
    end
    
    addLog("PKCS ▸ Collision negation terminated")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] RotationalMomentumSimulator
-- Симулятор вращательного момента персонажа
-- ═══════════════════════════════════════════════════════════════════
local RotationalMomentumSimulator = {}
RotationalMomentumSimulator.__index = RotationalMomentumSimulator

function RotationalMomentumSimulator.new()
    local self = setmetatable({}, RotationalMomentumSimulator)
    
    -- Параметры симулятора
    self._rotationalSimulationActive = false             -- состояние: вращение активно
    self._angularVelocityDegPerSec = 600                 -- скорость вращения (градусы/сек)
    self._rotationAxisIdentifier = "Y"                   -- ось вращения (X/Y/Z)
    
    return self
end

-- Маппинг функций вращения по осям
local ROTATION_AXIS_FUNCTION_MAP = {
    X = function(deltaTime, angularVelocity)
        return CFrame.Angles(math.rad(angularVelocity * deltaTime), 0, 0)
    end,
    Y = function(deltaTime, angularVelocity)
        return CFrame.Angles(0, math.rad(angularVelocity * deltaTime), 0)
    end,
    Z = function(deltaTime, angularVelocity)
        return CFrame.Angles(0, 0, math.rad(angularVelocity * deltaTime))
    end,
}

-- Вычисление дельты вращения
function RotationalMomentumSimulator:_computeRotationDelta(deltaTime)
    local rotationFunction = ROTATION_AXIS_FUNCTION_MAP[self._rotationAxisIdentifier] 
        or ROTATION_AXIS_FUNCTION_MAP["Y"]
    return rotationFunction(deltaTime, self._angularVelocityDegPerSec)
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] GravityDefyingJumpModifier
-- Модификатор бесконечного прыжка и усиления прыжка
-- ═══════════════════════════════════════════════════════════════════
local GravityDefyingJumpModifier = {}
GravityDefyingJumpModifier.__index = GravityDefyingJumpModifier

function GravityDefyingJumpModifier.new()
    local self = setmetatable({}, GravityDefyingJumpModifier)
    
    -- Параметры модификатора
    self._infiniteJumpActive = false                     -- бесконечный прыжок
    self._jumpVelocityBoostActive = false                -- усиление прыжка
    self._jumpBoostForceMagnitude = 60                   -- сила усиления прыжка
    
    -- Подключение для обработки прыжков
    self._jumpRequestConnection = nil
    
    return self
end

-- Привязка обработчика прыжков к персонажу
function GravityDefyingJumpModifier:_attachJumpHandlerToCharacter(characterModel)
    if self._jumpRequestConnection then
        self._jumpRequestConnection:Disconnect()
        self._jumpRequestConnection = nil
    end
    
    if not characterModel then return end
    
    local humanoidComponent = characterModel:WaitForChild("Humanoid", 5)
    if not humanoidComponent then return end
    
    self._jumpRequestConnection = UserInputService.JumpRequest:Connect(function()
        if not infiniteJumpEnabled then return end

        humanoidComponent:ChangeState(Enum.HumanoidStateType.Jumping)

        if jumpBoostEnabled then
            local humanoidRootPart = characterModel:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                pcall(function()
                    humanoidRootPart.AssemblyLinearVelocity = Vector3.new(
                        humanoidRootPart.AssemblyLinearVelocity.X,
                        jumpBoostForce,
                        humanoidRootPart.AssemblyLinearVelocity.Z
                    )
                end)
            end
        end
    end)
    
    addLog("PKCS ▸ Jump modifier attached to character")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] PlayerKinematicsControlSystem
-- Главный менеджер всех систем движения
-- ═══════════════════════════════════════════════════════════════════
local PlayerKinematicsControlSystem = {}
PlayerKinematicsControlSystem.__index = PlayerKinematicsControlSystem

function PlayerKinematicsControlSystem.new()
    local self = setmetatable({}, PlayerKinematicsControlSystem)
    
    -- Инициализация подсистем
    self._velocityEngine = VelocityManipulationEngine.new()
    self._aerialController = AerialLocomotionController.new()
    self._collisionProcessor = CollisionNegationProcessor.new()
    self._rotationSimulator = RotationalMomentumSimulator.new()
    self._jumpModifier = GravityDefyingJumpModifier.new()
    
    -- Регистрация обработчиков появления персонажа
    self:_initializeCharacterMonitoring()
    
    return self
end

-- Инициализация мониторинга появления персонажа
function PlayerKinematicsControlSystem:_initializeCharacterMonitoring()
    LocalPlayer.CharacterAdded:Connect(function(characterModel)
        -- Сброс физических объектов при респауне
        self._aerialController._bodyVelocityInstance = nil
        self._aerialController._bodyGyroscopeInstance = nil
        self._aerialController._collisionStateArchive = {}
        
        if self._aerialController._physicsCycleConnection then
            self._aerialController._physicsCycleConnection:Disconnect()
            self._aerialController._physicsCycleConnection = nil
        end
        
        -- Привязка обработчика прыжков
        self._jumpModifier:_attachJumpHandlerToCharacter(characterModel)
        
        task.wait(0.4)
        
        -- Переактивация полета если был активен
        if self._aerialController._aerialLocomotionActive then
            self._aerialController:_initiateAerialLocomotion()
        end
        
        -- Обновление кэша частей для NoClip
        self._collisionProcessor:_refreshCharacterPartsCache()
        
        -- Восстановление скорости
        if self._velocityEngine._velocityEnhancementActive then
            local humanoidComponent = characterModel:FindFirstChildOfClass("Humanoid")
            if humanoidComponent then
                humanoidComponent.WalkSpeed = self._velocityEngine._targetVelocityMagnitude
            end
        end
    end)
    
    -- Инициализация для текущего персонажа
    if LocalPlayer.Character then
        self._jumpModifier:_attachJumpHandlerToCharacter(LocalPlayer.Character)
        task.defer(function()
            self._collisionProcessor:_refreshCharacterPartsCache()
        end)
    end
    
    -- Запуск NoClip процессора
    self._collisionProcessor:_initiateCollisionNegation()
end

-- ═══════════════════════════════════════════════════════════════════
-- Глобальный экземпляр системы
-- ═══════════════════════════════════════════════════════════════════
_G.PlayerKinematicsSystem = PlayerKinematicsControlSystem.new()

-- ═══════════════════════════════════════════════════════════════════
-- Экспорт переменных для обратной совместимости с GUI
-- ═══════════════════════════════════════════════════════════════════
speedEnabled = false
speedValue = 28
BASE_SPEED = 16

flyEnabled = false
flySpeed = 60
flyBodyVelocity = nil
flyBodyGyro = nil
flyConnection = nil
flyCanCollideParts = {}
flyInertia = true
flyInertiaDecay = 0.90

noClipEnabled = false
noClipParts = {}
noClipConnection = nil

spinEnabled = false
spinSpeedDegPerSec = 600
spinAxis = "Y"

infiniteJumpEnabled = false
ijConn = nil

jumpBoostEnabled = false
jumpBoostForce = 60

-- Функции обратной совместимости
function getFlyDir()
    return _G.PlayerKinematicsSystem._aerialController:_computeFlightDirectionVector()
end

function startFly()
    -- БАГ #27 FIX: запрашиваем контроль движения через DataBus
    if not DataBus:RequestControl("Movement", "AerialController", 3) then
        addLog("FLY  ▸ ⚠ Movement занят другим модулем")
    end
    
    local ac = _G.PlayerKinematicsSystem._aerialController
    ac._aerialLocomotionActive    = true
    ac._aerialVelocityMagnitude   = flySpeed
    ac._inertialDampingEnabled    = flyInertia
    ac:_initiateAerialLocomotion()
    flyBodyVelocity = ac._bodyVelocityInstance
    flyBodyGyro     = ac._bodyGyroscopeInstance
end

function stopFly()
    local ac = _G.PlayerKinematicsSystem._aerialController
    ac._aerialLocomotionActive = false
    ac:_terminateAerialLocomotion()
    flyBodyVelocity = nil
    flyBodyGyro     = nil
    
    -- Освобождаем контроль движения
    DataBus:ReleaseControl("Movement", "AerialController")
end

function updateNoClipCache()
    _G.PlayerKinematicsSystem._collisionProcessor:_refreshCharacterPartsCache()
end

function startNoClip()
    local cp = _G.PlayerKinematicsSystem._collisionProcessor
    cp._collisionNegationActive = true
    cp:_initiateCollisionNegation()
end

function stopNoClip()
    _G.PlayerKinematicsSystem._collisionProcessor:_terminateCollisionNegation()
end

function getSpinDelta(dt)
    _G.PlayerKinematicsSystem._rotationSimulator._angularVelocityDegPerSec = spinSpeedDegPerSec
    return _G.PlayerKinematicsSystem._rotationSimulator:_computeRotationDelta(dt)
end

addLog("PKCS ▸ Player kinematics system initialized")
