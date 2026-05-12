-- ═══════════════════════════════════════════════════════════════════
--  EnvironmentRenderingManagementSystem.lua — Advanced OOP Environment System
--  Обфусцированный модуль управления визуальными эффектами окружения

--  АРХИТЕКТУРА:
--  - AtmosphericConditionsController: управление туманом и атмосферой
--  - IlluminationParametersManager: управление яркостью и освещением  
--  - TemporalStateRegulator: управление временем суток
--  - MaterialTransparencyProcessor: управление прозрачностью объектов
--  - ViewportCrosshairRenderer: рендеринг пользовательского прицела
--  - EnvironmentRenderingManagementSystem: главный менеджер всех систем
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] AtmosphericConditionsController
-- Управление туманом и атмосферными эффектами
-- ═══════════════════════════════════════════════════════════════════
local AtmosphericConditionsController = {}
AtmosphericConditionsController.__index = AtmosphericConditionsController

function AtmosphericConditionsController.new()
    local self = setmetatable({}, AtmosphericConditionsController)
    
    -- Флаги состояния
    self._atmosphericSuppressionActive = false           -- визуальное состояние: туман убран
    
    -- Архивные оригинальные значения для восстановления
    self._archivedFogTerminationDistance = nil
    self._archivedFogOriginationDistance = nil
    self._archivedFogColorationValue = nil
    
    -- Кэш эффектов частиц для производительности
    self._particleEffectsCache = {}
    self._cacheInitialized = false
    
    return self
end

-- Инициализация кэша эффектов частиц (один раз)
function AtmosphericConditionsController:_initializeParticleCache()
    if self._cacheInitialized then return end
    self._cacheInitialized = true  -- ставим флаг сразу чтобы не было двойного вызова
    
    -- БАГ #7 FIX: workspace:GetDescendants() блокировал поток на больших картах.
    -- Теперь делаем скан асинхронно батчами по 200 объектов с task.wait между ними.
    task.spawn(function()
        local BATCH_SIZE = 200
        local descendants = workspace:GetDescendants()
        for i = 1, #descendants, BATCH_SIZE do
            for j = i, math.min(i + BATCH_SIZE - 1, #descendants) do
                local descendantObject = descendants[j]
                if descendantObject:IsA("Smoke") or descendantObject:IsA("Fire") 
                    or descendantObject:IsA("Sparkles") then
                    table.insert(self._particleEffectsCache, descendantObject)
                end
            end
            task.wait()  -- уступаем поток между батчами
        end
    end)
    
    -- Слушаем новые эффекты
    workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
            table.insert(self._particleEffectsCache, obj)
        end
    end)
    
    -- БАГ #19 FIX: удалённые объекты оставались в кэше до следующего обхода.
    -- DescendantRemoving убирает их немедленно, предотвращая рост памяти.
    workspace.DescendantRemoving:Connect(function(obj)
        if obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
            for i = #self._particleEffectsCache, 1, -1 do
                if self._particleEffectsCache[i] == obj then
                    table.remove(self._particleEffectsCache, i)
                    break
                end
            end
        end
    end)
    
    self._cacheInitialized = true
end

-- Захват текущих параметров освещения
function AtmosphericConditionsController:_captureEnvironmentSnapshot()
    if self._archivedFogTerminationDistance == nil then
        self._archivedFogTerminationDistance = Lighting.FogEnd
        self._archivedFogOriginationDistance = Lighting.FogStart
        self._archivedFogColorationValue = Lighting.FogColor
    end
end

-- Применение подавления атмосферных эффектов
function AtmosphericConditionsController:_executeAtmosphericSuppression()
    self:_captureEnvironmentSnapshot()
    self:_initializeParticleCache()  -- Инициализация кэша при первом использовании
    
    pcall(function()
        -- Экстремальные значения дальности тумана
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 1000000
        Lighting.FogColor = Color3.fromRGB(0, 0, 0)
        
        -- Нейтрализация атмосферного компонента
        local atmosphericInstance = Lighting:FindFirstChildOfClass("Atmosphere")
        if atmosphericInstance then
            atmosphericInstance.Density = 0
            atmosphericInstance.Haze = 0
            atmosphericInstance.Glare = 0
        end
        
        -- Деактивация эффектов частиц из кэша (намного быстрее)
        for i = #self._particleEffectsCache, 1, -1 do
            local effect = self._particleEffectsCache[i]
            if effect and effect.Parent then
                pcall(function() effect.Enabled = false end)
            else
                -- Удаляем из кэша если объект был удален
                table.remove(self._particleEffectsCache, i)
            end
        end
    end)
    
    self._atmosphericSuppressionActive = true
    addLog("ERMS ▸ Atmospheric suppression applied")
end

-- Восстановление оригинальных атмосферных параметров
function AtmosphericConditionsController:_restoreAtmosphericConditions()
    if not self._archivedFogTerminationDistance then return end
    
    pcall(function()
        Lighting.FogEnd = self._archivedFogTerminationDistance
        Lighting.FogStart = self._archivedFogOriginationDistance
        Lighting.FogColor = self._archivedFogColorationValue or Color3.fromRGB(191, 191, 191)
        
        local atmosphericInstance = Lighting:FindFirstChildOfClass("Atmosphere")
        if atmosphericInstance then
            atmosphericInstance.Density = 0.3
            atmosphericInstance.Haze = 0
        end
        
        -- Восстанавливаем эффекты частиц из кэша (намного быстрее)
        for i = #self._particleEffectsCache, 1, -1 do
            local effect = self._particleEffectsCache[i]
            if effect and effect.Parent then
                pcall(function() effect.Enabled = true end)
            else
                -- Удаляем из кэша если объект был удален
                table.remove(self._particleEffectsCache, i)
            end
        end
    end)
    
    self._atmosphericSuppressionActive = false
    addLog("ERMS ▸ Atmospheric conditions restored")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] IlluminationParametersManager
-- Управление яркостью и параметрами освещения
-- ═══════════════════════════════════════════════════════════════════
local IlluminationParametersManager = {}
IlluminationParametersManager.__index = IlluminationParametersManager

function IlluminationParametersManager.new()
    local self = setmetatable({}, IlluminationParametersManager)
    
    -- Флаги и параметры
    self._enhancedIlluminationActive = false             -- состояние: яркость активна
    self._illuminationIntensityCoefficient = 2           -- коэффициент яркости (1-10)
    
    -- Архивированные оригинальные значения
    self._archivedBrightnessLevel = nil
    self._archivedAmbientColorization = nil
    self._archivedOutdoorAmbientColorization = nil
    self._archivedShadowSoftnessParameter = nil
    
    return self
end

-- Захват текущего состояния освещения
function IlluminationParametersManager:_captureIlluminationSnapshot()
    if self._archivedBrightnessLevel == nil then
        self._archivedBrightnessLevel = Lighting.Brightness
        self._archivedAmbientColorization = Lighting.Ambient
        self._archivedOutdoorAmbientColorization = Lighting.OutdoorAmbient
        self._archivedShadowSoftnessParameter = Lighting.ShadowSoftness
    end
end

-- Применение усиленного освещения
function IlluminationParametersManager:_applyEnhancedIllumination(intensityValue)
    self:_captureIlluminationSnapshot()
    self._illuminationIntensityCoefficient = intensityValue
    
    pcall(function()
        Lighting.Brightness = intensityValue
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        Lighting.ShadowSoftness = 0
        
        -- Деактивация Bloom эффекта (затемняет при высокой яркости)
        local bloomEffectInstance = Lighting:FindFirstChildOfClass("BloomEffect")
        if bloomEffectInstance then
            bloomEffectInstance.Enabled = false
        end
        
        -- Настройка коррекции цвета
        local colorCorrectionInstance = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        if colorCorrectionInstance then
            colorCorrectionInstance.Brightness = 0.3
            colorCorrectionInstance.Contrast = 0
            colorCorrectionInstance.Saturation = 0
        end
    end)
    
    self._enhancedIlluminationActive = true
    addLog("ERMS ▸ Enhanced illumination: intensity=" .. intensityValue)
end

-- Восстановление оригинального освещения
function IlluminationParametersManager:_restoreOriginalIllumination()
    if not self._archivedBrightnessLevel then return end
    
    pcall(function()
        Lighting.Brightness = self._archivedBrightnessLevel
        Lighting.Ambient = self._archivedAmbientColorization or Color3.fromRGB(70, 70, 70)
        Lighting.OutdoorAmbient = self._archivedOutdoorAmbientColorization 
            or Color3.fromRGB(140, 140, 140)
        Lighting.ShadowSoftness = self._archivedShadowSoftnessParameter or 0.5
        
        local bloomEffectInstance = Lighting:FindFirstChildOfClass("BloomEffect")
        if bloomEffectInstance then
            bloomEffectInstance.Enabled = true
        end
        
        local colorCorrectionInstance = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        if colorCorrectionInstance then
            colorCorrectionInstance.Brightness = 0
            colorCorrectionInstance.Contrast = 0
            colorCorrectionInstance.Saturation = 0
        end
    end)
    
    self._enhancedIlluminationActive = false
    addLog("ERMS ▸ Original illumination restored")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] TemporalStateRegulator
-- Управление фиксированным временем суток
-- ═══════════════════════════════════════════════════════════════════
local TemporalStateRegulator = {}
TemporalStateRegulator.__index = TemporalStateRegulator

function TemporalStateRegulator.new()
    local self = setmetatable({}, TemporalStateRegulator)
    
    -- Параметры временного регулятора
    self._temporalLockActive = false                     -- состояние: время зафиксировано
    self._lockedTemporalValue = 14                       -- зафиксированный час (0-24)
    
    -- Архивные данные
    self._archivedClockTimeValue = nil
    self._temporalEnforcementConnection = nil            -- подключение для поддержания времени
    
    return self
end

-- Захват текущего времени
function TemporalStateRegulator:_captureTemporalSnapshot()
    if self._archivedClockTimeValue == nil then
        self._archivedClockTimeValue = Lighting.ClockTime
    end
end

-- Применение фиксированного времени с непрерывным обновлением
function TemporalStateRegulator:_enforceTemporalLock(targetHourValue)
    self:_captureTemporalSnapshot()
    self._lockedTemporalValue = targetHourValue
    
    -- Отключение предыдущего подключения
    if self._temporalEnforcementConnection then
        self._temporalEnforcementConnection:Disconnect()
        self._temporalEnforcementConnection = nil
    end
    
    if not self._temporalLockActive then return end
    
    -- Немедленная установка времени
    pcall(function() Lighting.ClockTime = targetHourValue end)
    
    -- БАГ #8 FIX: Heartbeat проверял время 60+ раз/сек без нужды.
    -- Lighting:GetPropertyChangedSignal стреляет только когда игра
    -- сама меняет ClockTime — нулевая нагрузка в остальное время.
    self._temporalEnforcementConnection = Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
        if not self._temporalLockActive then
            if self._temporalEnforcementConnection then
                self._temporalEnforcementConnection:Disconnect()
                self._temporalEnforcementConnection = nil
            end
            return
        end
        
        -- Коррекция если игра сдвинула время
        if math.abs(Lighting.ClockTime - targetHourValue) > 0.05 then
            pcall(function() Lighting.ClockTime = targetHourValue end)
        end
    end)
    
    addLog("ERMS ▸ Temporal lock enforced: " .. string.format("%.1fh", targetHourValue))
end

-- Освобождение временной фиксации
function TemporalStateRegulator:_releaseTemporalLock()
    if self._temporalEnforcementConnection then
        self._temporalEnforcementConnection:Disconnect()
        self._temporalEnforcementConnection = nil
    end
    
    if self._archivedClockTimeValue then
        pcall(function() Lighting.ClockTime = self._archivedClockTimeValue end)
    end
    
    self._temporalLockActive = false
    addLog("ERMS ▸ Temporal lock released")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] MaterialTransparencyProcessor
-- Обработка прозрачности материалов персонажей (чамсы)
-- ═══════════════════════════════════════════════════════════════════
local MaterialTransparencyProcessor = {}
MaterialTransparencyProcessor.__index = MaterialTransparencyProcessor

function MaterialTransparencyProcessor.new()
    local self = setmetatable({}, MaterialTransparencyProcessor)
    
    -- Параметры процессора
    self._transparencyProcessingActive = false           -- состояние: чамсы активны
    self._targetTransparencyCoefficient = 0.55           -- коэффициент прозрачности (0-1)
    
    -- Архив оригинальных значений прозрачности
    self._transparencyArchiveMapping = {}                -- {BasePart -> original_transparency}
    
    return self
end

-- Применение прозрачности к персонажу игрока
function MaterialTransparencyProcessor:_applyTransparencyToCharacter(targetPlayerInstance)
    if not targetPlayerInstance.Character then return end
    
    for _, descendantObject in ipairs(targetPlayerInstance.Character:GetDescendants()) do
        if descendantObject:IsA("BasePart") and descendantObject.Name ~= "HumanoidRootPart" then
            -- Архивирование оригинального значения
            if self._transparencyArchiveMapping[descendantObject] == nil then
                self._transparencyArchiveMapping[descendantObject] = descendantObject.Transparency
            end
            
            -- Применение новой прозрачности
            pcall(function() 
                descendantObject.Transparency = self._targetTransparencyCoefficient 
            end)
        end
    end
end

-- Удаление прозрачности с персонажа
function MaterialTransparencyProcessor:_removeTransparencyFromCharacter(targetPlayerInstance)
    if not targetPlayerInstance.Character then return end
    
    for _, descendantObject in ipairs(targetPlayerInstance.Character:GetDescendants()) do
        if descendantObject:IsA("BasePart") then
            local archivedTransparency = self._transparencyArchiveMapping[descendantObject]
            if archivedTransparency ~= nil then
                pcall(function() 
                    descendantObject.Transparency = archivedTransparency 
                end)
                self._transparencyArchiveMapping[descendantObject] = nil
            end
        end
    end
end

-- Массовое применение ко всем враждебным игрокам
function MaterialTransparencyProcessor:_executeGlobalTransparencyApplication()
    for _, playerInstance in ipairs(Players:GetPlayers()) do
        if playerInstance ~= LocalPlayer and isEnemy(playerInstance) then
            self:_applyTransparencyToCharacter(playerInstance)
        end
    end
    addLog("ERMS ▸ Material transparency applied  alpha=" .. self._targetTransparencyCoefficient)
end

-- Массовое удаление прозрачности
function MaterialTransparencyProcessor:_executeGlobalTransparencyRemoval()
    for _, playerInstance in ipairs(Players:GetPlayers()) do
        self:_removeTransparencyFromCharacter(playerInstance)
    end
    self._transparencyArchiveMapping = {}
    addLog("ERMS ▸ Material transparency removed")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] ViewportCrosshairRenderer
-- Рендеринг пользовательского прицела
-- ═══════════════════════════════════════════════════════════════════
local ViewportCrosshairRenderer = {}
ViewportCrosshairRenderer.__index = ViewportCrosshairRenderer

function ViewportCrosshairRenderer.new()
    local self = setmetatable({}, ViewportCrosshairRenderer)
    
    -- Параметры рендерера
    self._crosshairRenderingActive = false               -- состояние: прицел отображается
    
    -- Параметры геометрии прицела
    self._crosshairLineHalfExtent = 14                   -- половина длины линии (px)
    self._crosshairCenterGapDistance = 4                 -- зазор в центре (px)
    self._crosshairLineThickness = 1.5                   -- толщина линии (px)
    self._crosshairColorization = Color3.fromRGB(0, 255, 100)
    
    -- GUI объекты
    self._crosshairGuiContainer = nil
    self._crosshairUpdateConnection = nil
    
    return self
end

-- Построение UI элементов прицела
function ViewportCrosshairRenderer:_constructCrosshairInterface()
    if self._crosshairGuiContainer then
        self._crosshairGuiContainer:Destroy()
    end
    
    -- Создание ScreenGui контейнера
    local screenGuiContainer = Instance.new("ScreenGui")
    screenGuiContainer.Name = "_ERMS_Crosshair"
    screenGuiContainer.ResetOnSpawn = false
    screenGuiContainer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGuiContainer.IgnoreGuiInset = true
    screenGuiContainer.Parent = PlayerGui
    
    self._crosshairGuiContainer = screenGuiContainer
    
    -- Функция создания линии прицела
    local function _fabricateCrosshairLine(isHorizontalOrientation)
        local frameInstance = Instance.new("Frame")
        frameInstance.BackgroundColor3 = self._crosshairColorization
        frameInstance.BorderSizePixel = 0
        
        if isHorizontalOrientation then
            frameInstance.Size = UDim2.new(0, self._crosshairLineHalfExtent, 
                0, self._crosshairLineThickness)
            frameInstance.AnchorPoint = Vector2.new(0.5, 0.5)
        else
            frameInstance.Size = UDim2.new(0, self._crosshairLineThickness, 
                0, self._crosshairLineHalfExtent)
            frameInstance.AnchorPoint = Vector2.new(0.5, 0.5)
        end
        
        frameInstance.Parent = screenGuiContainer
        return frameInstance
    end
    
    -- Создание четырех линий (лево, право, верх, низ)
    local lineLeft = _fabricateCrosshairLine(true)
    local lineRight = _fabricateCrosshairLine(true)
    local lineUp = _fabricateCrosshairLine(false)
    local lineDown = _fabricateCrosshairLine(false)
    
    -- Циклическое обновление позиций (следование за курсором)
    self._crosshairUpdateConnection = RunService.RenderStepped:Connect(function()
        if not self._crosshairRenderingActive then return end
        
        local mouseLocationVector = UserInputService:GetMouseLocation()
        local cursorX = mouseLocationVector.X
        local cursorY = mouseLocationVector.Y
        
        -- Позиционирование линий относительно курсора
        lineLeft.Position = UDim2.new(0, 
            cursorX - self._crosshairCenterGapDistance - self._crosshairLineHalfExtent / 2, 
            0, cursorY)
        lineRight.Position = UDim2.new(0, 
            cursorX + self._crosshairCenterGapDistance + self._crosshairLineHalfExtent / 2, 
            0, cursorY)
        lineUp.Position = UDim2.new(0, cursorX, 
            0, cursorY - self._crosshairCenterGapDistance - self._crosshairLineHalfExtent / 2)
        lineDown.Position = UDim2.new(0, cursorX, 
            0, cursorY + self._crosshairCenterGapDistance + self._crosshairLineHalfExtent / 2)
    end)
end

-- Активация рендеринга прицела
function ViewportCrosshairRenderer:_activateCrosshairRendering()
    self._crosshairRenderingActive = true
    self:_constructCrosshairInterface()
    addLog("ERMS ▸ Crosshair rendering activated")
end

-- Деактивация рендеринга прицела
function ViewportCrosshairRenderer:_deactivateCrosshairRendering()
    self._crosshairRenderingActive = false
    
    if self._crosshairUpdateConnection then
        self._crosshairUpdateConnection:Disconnect()
        self._crosshairUpdateConnection = nil
    end
    
    if self._crosshairGuiContainer then
        self._crosshairGuiContainer:Destroy()
        self._crosshairGuiContainer = nil
    end
    
    addLog("ERMS ▸ Crosshair rendering deactivated")
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] EnvironmentRenderingManagementSystem
-- Главный менеджер всех визуальных систем окружения
-- ═══════════════════════════════════════════════════════════════════
local EnvironmentRenderingManagementSystem = {}
EnvironmentRenderingManagementSystem.__index = EnvironmentRenderingManagementSystem

function EnvironmentRenderingManagementSystem.new()
    local self = setmetatable({}, EnvironmentRenderingManagementSystem)
    
    -- Инициализация подсистем
    self._atmosphericController = AtmosphericConditionsController.new()
    self._illuminationManager = IlluminationParametersManager.new()
    self._temporalRegulator = TemporalStateRegulator.new()
    self._transparencyProcessor = MaterialTransparencyProcessor.new()
    self._crosshairRenderer = ViewportCrosshairRenderer.new()
    
    -- Регистрация обработчиков появления новых персонажей
    self:_initializePlayerMonitoring()
    
    return self
end

-- Инициализация мониторинга игроков (для чамсов)
function EnvironmentRenderingManagementSystem:_initializePlayerMonitoring()
    Players.PlayerAdded:Connect(function(playerInstance)
        playerInstance.CharacterAdded:Connect(function()
            if self._transparencyProcessor._transparencyProcessingActive then
                task.wait(0.5)
                if isEnemy(playerInstance) then
                    self._transparencyProcessor:_applyTransparencyToCharacter(playerInstance)
                end
            end
        end)
    end)
    
    -- Подключение для существующих игроков
    for _, playerInstance in ipairs(Players:GetPlayers()) do
        if playerInstance ~= LocalPlayer then
            playerInstance.CharacterAdded:Connect(function()
                if self._transparencyProcessor._transparencyProcessingActive then
                    task.wait(0.5)
                    if isEnemy(playerInstance) then
                        self._transparencyProcessor:_applyTransparencyToCharacter(playerInstance)
                    end
                end
            end)
        end
    end
end

-- Пресет: Ночное видение (ночь + полная яркость)
function EnvironmentRenderingManagementSystem:_executeNightVisionPreset()
    self._temporalRegulator._temporalLockActive = true
    self._temporalRegulator:_enforceTemporalLock(0)
    self._illuminationManager:_applyEnhancedIllumination(6)
    addLog("ERMS ▸ NIGHT VISION preset activated")
end

-- Пресет: Полный сброс всех эффектов
function EnvironmentRenderingManagementSystem:_executeCompleteSystemReset()
    if self._atmosphericController._atmosphericSuppressionActive then
        self._atmosphericController:_restoreAtmosphericConditions()
    end
    if self._illuminationManager._enhancedIlluminationActive then
        self._illuminationManager:_restoreOriginalIllumination()
    end
    if self._temporalRegulator._temporalLockActive then
        self._temporalRegulator:_releaseTemporalLock()
    end
    if self._transparencyProcessor._transparencyProcessingActive then
        self._transparencyProcessor:_executeGlobalTransparencyRemoval()
    end
    
    addLog("ERMS ▸ Complete system reset executed")
end

-- ═══════════════════════════════════════════════════════════════════
-- Глобальный экземпляр системы
-- ═══════════════════════════════════════════════════════════════════
_G.EnvironmentRenderingSystem = EnvironmentRenderingManagementSystem.new()

-- ═══════════════════════════════════════════════════════════════════
-- Экспорт переменных для обратной совместимости с GUI
-- ═══════════════════════════════════════════════════════════════════
visualFogEnabled = false
visualBrightEnabled = false
visualTimeEnabled = false
visualChamsEnabled = false
visualCrosshairOn = false

brightnessValue = 2
visualTimeValue = 14
visualChamsAlpha = 0.55

-- Функции обратной совместимости
function applyNoFog()
    _G.EnvironmentRenderingSystem._atmosphericController:_executeAtmosphericSuppression()
end

function restoreFog()
    _G.EnvironmentRenderingSystem._atmosphericController:_restoreAtmosphericConditions()
end

function applyBrightness(val)
    _G.EnvironmentRenderingSystem._illuminationManager:_applyEnhancedIllumination(val)
end

function restoreBrightness()
    _G.EnvironmentRenderingSystem._illuminationManager:_restoreOriginalIllumination()
end

function applyFixedTime(hour)
    visualTimeValue = hour
    _G.EnvironmentRenderingSystem._temporalRegulator._lockedTemporalValue = hour
    _G.EnvironmentRenderingSystem._temporalRegulator:_enforceTemporalLock(hour)
end

function restoreTime()
    _G.EnvironmentRenderingSystem._temporalRegulator:_releaseTemporalLock()
end

function applyChams()
    _G.EnvironmentRenderingSystem._transparencyProcessor._targetTransparencyCoefficient = visualChamsAlpha
    _G.EnvironmentRenderingSystem._transparencyProcessor:_executeGlobalTransparencyApplication()
end

function clearChams()
    _G.EnvironmentRenderingSystem._transparencyProcessor:_executeGlobalTransparencyRemoval()
end

function showCrosshair()
    _G.EnvironmentRenderingSystem._crosshairRenderer:_activateCrosshairRendering()
end

function hideCrosshair()
    _G.EnvironmentRenderingSystem._crosshairRenderer:_deactivateCrosshairRendering()
end

function presetNightVision()
    _G.EnvironmentRenderingSystem:_executeNightVisionPreset()
end

function presetRestore()
    _G.EnvironmentRenderingSystem:_executeCompleteSystemReset()
    visualFogEnabled = false
    visualBrightEnabled = false
    visualTimeEnabled = false
    visualChamsEnabled = false
end

addLog("ERMS ▸ EnvironmentRenderingManagementSystem.lua loaded successfully")
