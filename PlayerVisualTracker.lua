-- ═══════════════════════════════════════════════════════════════════
--  PlayerVisualTracker.lua — Advanced OOP Visual Tracking System
--  Обфусцированный модуль отслеживания игроков с визуальными эффектами

--  АРХИТЕКТУРА:
--  - VisualTrackerConfiguration: конфигурация параметров отображения
--  - PlayerHighlightRenderer: рендеринг подсветки персонажей
--  - PlayerInfoOverlay: информационные оверлеи над игроками
--  - VisualTrackingSystem: главный менеджер системы
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] VisualTrackerConfiguration
-- Управление конфигурацией визуального трекера
-- ═══════════════════════════════════════════════════════════════════
local VisualTrackerConfiguration = {}
VisualTrackerConfiguration.__index = VisualTrackerConfiguration

function VisualTrackerConfiguration.new()
    local self = setmetatable({}, VisualTrackerConfiguration)
    
    -- Основные переключатели системы
    self._trackerActivationState = false              -- включение основного трекера
    self._healthMetricsDisplay = false                -- отображение здоровья
    self._distanceCalculationDisplay = false          -- отображение дистанции
    self._playerIdentifierDisplay = false             -- отображение имени
    self._healthBasedColorization = false             -- окраска по здоровью
    self._teamAffiliationColorization = false         -- окраска по команде
    
    -- Параметры прозрачности и цвета
    self._innerTransparencyCoefficient = 0.80         -- прозрачность заливки
    self._outlineTransparencyCoefficient = 0.0        -- прозрачность контура
    self._defaultVisualizationTint = Color3.fromRGB(170, 0, 255)
    
    return self
end

-- Получение цвета на основе конфигурации
function VisualTrackerConfiguration:_computePlayerColorization(targetPlayer)
    -- Приоритет 1: командная окраска
    if self._teamAffiliationColorization and targetPlayer.Team then 
        return targetPlayer.Team.TeamColor.Color 
    end
    
    -- Приоритет 2: окраска по здоровью
    if self._healthBasedColorization then
        local humanoidComponent = targetPlayer.Character 
            and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoidComponent and humanoidComponent.MaxHealth > 0 then
            local healthRatio = math.clamp(
                humanoidComponent.Health / humanoidComponent.MaxHealth, 0, 1)
            return Color3.fromRGB(
                math.floor((1 - healthRatio) * 220), 
                math.floor(healthRatio * 200), 
                60)
        end
    end
    
    -- Приоритет 3: базовый цвет
    return self._defaultVisualizationTint
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] PlayerHighlightRenderer
-- Рендеринг подсветки персонажа игрока
-- ═══════════════════════════════════════════════════════════════════
local PlayerHighlightRenderer = {}
PlayerHighlightRenderer.__index = PlayerHighlightRenderer

function PlayerHighlightRenderer.new(characterModel, playerInstance, configurationRef)
    local self = setmetatable({}, PlayerHighlightRenderer)
    
    self._targetCharacterModel = characterModel
    self._associatedPlayerInstance = playerInstance
    self._configurationReference = configurationRef
    self._highlightInstanceObject = nil
    
    self:_initializeHighlightEffect()
    return self
end

-- Инициализация эффекта подсветки
function PlayerHighlightRenderer:_initializeHighlightEffect()
    -- Проверка существования старого эффекта
    if self._targetCharacterModel:FindFirstChild("_PVT_Highlight") then 
        return 
    end
    
    -- Создание нового Highlight объекта
    local highlightEffect = Instance.new("Highlight")
    highlightEffect.Name = "_PVT_Highlight"
    highlightEffect.FillTransparency = self._configurationReference._innerTransparencyCoefficient
    highlightEffect.OutlineTransparency = self._configurationReference._outlineTransparencyCoefficient
    highlightEffect.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    
    -- Применение цветовой схемы
    local computedColor = self._configurationReference:_computePlayerColorization(
        self._associatedPlayerInstance)
    highlightEffect.OutlineColor = computedColor
    highlightEffect.FillColor = computedColor
    highlightEffect.Parent = self._targetCharacterModel
    
    self._highlightInstanceObject = highlightEffect
    addLog("PVT ▸ Highlight ON  : " .. self._associatedPlayerInstance.Name)
end

-- Обновление цветовой схемы
function PlayerHighlightRenderer:_refreshColorization()
    if not self._highlightInstanceObject then return end
    
    local updatedColor = self._configurationReference:_computePlayerColorization(
        self._associatedPlayerInstance)
    self._highlightInstanceObject.OutlineColor = updatedColor
    self._highlightInstanceObject.FillColor = updatedColor
end

-- Деструктор эффекта
function PlayerHighlightRenderer:_terminateHighlightEffect()
    if self._highlightInstanceObject then
        addLog("PVT ▸ Highlight OFF : " .. self._associatedPlayerInstance.Name)
        self._highlightInstanceObject:Destroy()
        self._highlightInstanceObject = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] PlayerInfoOverlay
-- Информационный оверлей над игроком (Billboard)
-- ═══════════════════════════════════════════════════════════════════
local PlayerInfoOverlay = {}
PlayerInfoOverlay.__index = PlayerInfoOverlay

function PlayerInfoOverlay.new(playerInstance, configurationRef)
    local self = setmetatable({}, PlayerInfoOverlay)
    
    self._associatedPlayerInstance = playerInstance
    self._configurationReference = configurationRef
    self._billboardGuiInstance = nil
    
    self:_constructOverlayInterface()
    return self
end

-- Построение UI оверлея
function PlayerInfoOverlay:_constructOverlayInterface()
    if not (self._associatedPlayerInstance and self._associatedPlayerInstance.Character) then 
        return 
    end
    
    local humanoidRootPart = self._associatedPlayerInstance.Character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    
    -- Создание BillboardGui
    local overlayBillboard = Instance.new("BillboardGui")
    overlayBillboard.Name = "_PVT_Overlay"
    overlayBillboard.Size = UDim2.new(0, 92, 0, 50)
    overlayBillboard.StudsOffset = Vector3.new(0, 3.6, 0)
    overlayBillboard.AlwaysOnTop = true
    overlayBillboard.ResetOnSpawn = false
    overlayBillboard.LightInfluence = 0
    overlayBillboard.Parent = humanoidRootPart
    
    -- Функция создания текстовых меток
    local function _createTextLabel(displayText, heightPx, offsetYPx, textColor, fontSize)
        local labelInstance = Instance.new("TextLabel")
        labelInstance.Size = UDim2.new(1, 0, 0, heightPx)
        labelInstance.Position = UDim2.new(0, 0, 0, offsetYPx)
        labelInstance.BackgroundTransparency = 1
        labelInstance.Text = displayText
        labelInstance.TextColor3 = textColor or C.white
        labelInstance.Font = Enum.Font.GothamBold
        labelInstance.TextSize = fontSize or 11
        labelInstance.TextStrokeTransparency = 0.35
        labelInstance.TextStrokeColor3 = Color3.new(0, 0, 0)
        labelInstance.Parent = overlayBillboard
        return labelInstance
    end
    
    -- Создание меток
    _createTextLabel(self._associatedPlayerInstance.Name, 18, 0, C.white, 11).Name = "IdentityLabel"
    _createTextLabel("", 13, 18, C.logText, 9).Name = "MetricsLabel"
    
    -- Создание полоски здоровья
    local healthBarBackground = Instance.new("Frame")
    healthBarBackground.Name = "HealthBarBg"
    healthBarBackground.Size = UDim2.new(1, 0, 0, 4)
    healthBarBackground.Position = UDim2.new(0, 0, 0, 34)
    healthBarBackground.BackgroundColor3 = Color3.fromRGB(30, 8, 50)
    healthBarBackground.BorderSizePixel = 0
    healthBarBackground.Parent = overlayBillboard
    
    local healthBarFill = Instance.new("Frame")
    healthBarFill.Name = "HealthBarFill"
    healthBarFill.Size = UDim2.new(1, 0, 1, 0)
    healthBarFill.BackgroundColor3 = C.green
    healthBarFill.BorderSizePixel = 0
    healthBarFill.Parent = healthBarBackground
    
    self._billboardGuiInstance = overlayBillboard
end

-- Обновление отображаемой информации
function PlayerInfoOverlay:_updateDisplayedMetrics()
    if not (self._billboardGuiInstance and self._billboardGuiInstance.Parent) then 
        return 
    end
    
    local localHumanoidRoot = getHRP(LocalPlayer)
    local targetHumanoid = getHum(self._associatedPlayerInstance)
    local targetHumanoidRoot = getHRP(self._associatedPlayerInstance)
    
    local metricsLabel = self._billboardGuiInstance:FindFirstChild("MetricsLabel")
    local healthBarBg = self._billboardGuiInstance:FindFirstChild("HealthBarBg")
    local healthBarFill = healthBarBg and healthBarBg:FindFirstChild("HealthBarFill")
    local identityLabel = self._billboardGuiInstance:FindFirstChild("IdentityLabel")
    
    -- Управление видимостью имени
    if identityLabel then 
        identityLabel.Visible = self._configurationReference._playerIdentifierDisplay 
    end
    
    -- Формирование текста метрик
    if metricsLabel then
        local metricsParts = {}
        
        if self._configurationReference._healthMetricsDisplay and targetHumanoid then
            metricsParts[#metricsParts + 1] = string.format("%d/%d hp", 
                math.floor(targetHumanoid.Health), 
                math.floor(targetHumanoid.MaxHealth))
        end
        
        if self._configurationReference._distanceCalculationDisplay 
            and localHumanoidRoot and targetHumanoidRoot then
            local distanceValue = (localHumanoidRoot.Position - targetHumanoidRoot.Position).Magnitude
            metricsParts[#metricsParts + 1] = fmtDist(distanceValue) .. " st"
        end
        
        metricsLabel.Text = table.concat(metricsParts, "  │  ")
        metricsLabel.Visible = (#metricsParts > 0)
    end
    
    -- Управление полоской здоровья
    if healthBarBg then
        healthBarBg.Visible = self._configurationReference._healthMetricsDisplay
    end
    
    if healthBarFill and self._configurationReference._healthMetricsDisplay 
        and targetHumanoid and targetHumanoid.MaxHealth > 0 then
        local healthRatio = math.clamp(targetHumanoid.Health / targetHumanoid.MaxHealth, 0, 1)
        healthBarFill.Size = UDim2.new(healthRatio, 0, 1, 0)
        healthBarFill.BackgroundColor3 = Color3.fromRGB(
            math.floor((1 - healthRatio) * 220 + healthRatio * 80),
            math.floor(healthRatio * 200 + (1 - healthRatio) * 50), 
            60)
    end
    
    -- Скрытие billboard если все опции выключены
    local anyMetricEnabled = self._configurationReference._playerIdentifierDisplay 
        or self._configurationReference._healthMetricsDisplay 
        or self._configurationReference._distanceCalculationDisplay
    self._billboardGuiInstance.Enabled = anyMetricEnabled
end

-- Деструктор оверлея
function PlayerInfoOverlay:_terminateOverlay()
    if self._billboardGuiInstance then
        pcall(function() self._billboardGuiInstance:Destroy() end)
        self._billboardGuiInstance = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- [КЛАСС] VisualTrackingSystem
-- Главный менеджер системы визуального трекинга
-- ═══════════════════════════════════════════════════════════════════
local VisualTrackingSystem = {}
VisualTrackingSystem.__index = VisualTrackingSystem

function VisualTrackingSystem.new()
    local self = setmetatable({}, VisualTrackingSystem)
    
    self._systemConfiguration = VisualTrackerConfiguration.new()
    self._registeredPlayersPool = {}
    self._highlightRenderersMap = {}
    self._overlayInstancesMap = {}
    self._eventConnectionsMap = {}
    
    return self
end

-- Регистрация игрока в системе
function VisualTrackingSystem:_registerPlayerIntoSystem(playerInstance)
    if playerInstance == LocalPlayer or self._registeredPlayersPool[playerInstance] then 
        return 
    end
    
    self._registeredPlayersPool[playerInstance] = true
    
    -- Подключение к событию появления персонажа
    local characterAddedConnection = playerInstance.CharacterAdded:Connect(function(characterModel)
        task.spawn(function()
            task.wait(0.25)
            self:_applyVisualsToPlayer(playerInstance)
        end)
        
        local humanoidComponent = characterModel:WaitForChild("Humanoid", 10)
        if humanoidComponent then
            humanoidComponent.Died:Connect(function()
                task.wait(0.05)
                self:_removeVisualsFromPlayer(playerInstance)
            end)
        end
    end)
    
    -- Подключение к событию удаления персонажа
    local characterRemovingConnection = playerInstance.CharacterRemoving:Connect(function()
        self:_removeVisualsFromPlayer(playerInstance)
    end)
    
    -- Подключение к событию смены команды
    local teamChangedConnection = playerInstance:GetPropertyChangedSignal("Team"):Connect(function()
        task.wait(0.1)
        if not isEnemy(playerInstance) then 
            self:_removeVisualsFromPlayer(playerInstance)
        elseif self._systemConfiguration._trackerActivationState then 
            task.spawn(function() self:_applyVisualsToPlayer(playerInstance) end)
        end
    end)
    
    -- Сохранение подключений
    self._eventConnectionsMap[playerInstance] = {
        _charAddConn = characterAddedConnection,
        _charRemConn = characterRemovingConnection,
        _teamChgConn = teamChangedConnection
    }
    
    -- Применение визуалов если система активна и игрок враг
    if self._systemConfiguration._trackerActivationState and isEnemy(playerInstance) then 
        task.spawn(function() self:_applyVisualsToPlayer(playerInstance) end)
    end
    
    addLog("PVT ▸ Player registered: " .. playerInstance.Name)
end

-- Удаление игрока из системы
function VisualTrackingSystem:_unregisterPlayerFromSystem(playerInstance)
    if self._registeredPlayersPool[playerInstance] then
        addLog("PVT ▸ Player unregistered: " .. playerInstance.Name)
    end
    
    -- Отключение событий
    local connectionsBundle = self._eventConnectionsMap[playerInstance]
    if connectionsBundle then
        if connectionsBundle._charAddConn then connectionsBundle._charAddConn:Disconnect() end
        if connectionsBundle._charRemConn then connectionsBundle._charRemConn:Disconnect() end
        if connectionsBundle._teamChgConn then connectionsBundle._teamChgConn:Disconnect() end
        self._eventConnectionsMap[playerInstance] = nil
    end
    
    self:_removeVisualsFromPlayer(playerInstance)
    self._registeredPlayersPool[playerInstance] = nil
end

-- Применение визуальных эффектов к игроку
function VisualTrackingSystem:_applyVisualsToPlayer(playerInstance)
    if not playerInstance.Character then return end
    
    local humanoidRootPart = playerInstance.Character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then
        humanoidRootPart = playerInstance.Character:WaitForChild("HumanoidRootPart", 10)
    end
    if not humanoidRootPart then return end
    
    task.wait(0.1)
    if not self._systemConfiguration._trackerActivationState or not isEnemy(playerInstance) then 
        return 
    end
    
    -- Создание подсветки
    if not self._highlightRenderersMap[playerInstance] then
        self._highlightRenderersMap[playerInstance] = PlayerHighlightRenderer.new(
            playerInstance.Character, 
            playerInstance, 
            self._systemConfiguration)
    end
    
    -- Создание оверлея
    if not self._overlayInstancesMap[playerInstance] then
        self._overlayInstancesMap[playerInstance] = PlayerInfoOverlay.new(
            playerInstance, 
            self._systemConfiguration)
    end
end

-- Удаление визуальных эффектов от игрока
function VisualTrackingSystem:_removeVisualsFromPlayer(playerInstance)
    if self._highlightRenderersMap[playerInstance] then
        self._highlightRenderersMap[playerInstance]:_terminateHighlightEffect()
        self._highlightRenderersMap[playerInstance] = nil
    end
    
    if self._overlayInstancesMap[playerInstance] then
        self._overlayInstancesMap[playerInstance]:_terminateOverlay()
        self._overlayInstancesMap[playerInstance] = nil
    end
end

-- Полное обновление всех визуалов
function VisualTrackingSystem:_executeFullSystemRefresh()
    local registeredCount = 0
    for _ in pairs(self._registeredPlayersPool) do registeredCount = registeredCount + 1 end
    addLog("PVT ▸ System refresh  pool=" .. registeredCount)
    
    for playerInstance in pairs(self._registeredPlayersPool) do
        if self._systemConfiguration._trackerActivationState and isEnemy(playerInstance) then 
            task.spawn(function() self:_applyVisualsToPlayer(playerInstance) end)
        else 
            self:_removeVisualsFromPlayer(playerInstance)
        end
    end
end

-- Очистка всех визуалов
function VisualTrackingSystem:_purgeAllVisualEffects()
    addLog("PVT ▸ Purging all visual effects")
    for playerInstance in pairs(self._registeredPlayersPool) do
        self:_removeVisualsFromPlayer(playerInstance)
    end
end

-- Обновление визуалов (вызывается из main loop)
function VisualTrackingSystem:_performCyclicUpdate()
    if not self._systemConfiguration._trackerActivationState then return end
    
    for playerInstance in pairs(self._registeredPlayersPool) do
        if not (playerInstance and playerInstance.Character) then continue end
        
        -- Watchdog: восстановление отсутствующих подсветок
        if isEnemy(playerInstance) and not playerInstance.Character:FindFirstChild("_PVT_Highlight") then
            if not self._highlightRenderersMap[playerInstance] then
                self._highlightRenderersMap[playerInstance] = PlayerHighlightRenderer.new(
                    playerInstance.Character, 
                    playerInstance, 
                    self._systemConfiguration)
            end
        end
        
        -- Обновление оверлея
        local overlayInstance = self._overlayInstancesMap[playerInstance]
        if not (overlayInstance and overlayInstance._billboardGuiInstance 
            and overlayInstance._billboardGuiInstance.Parent) and isEnemy(playerInstance) then
            self._overlayInstancesMap[playerInstance] = PlayerInfoOverlay.new(
                playerInstance, 
                self._systemConfiguration)
            overlayInstance = self._overlayInstancesMap[playerInstance]
        end
        
        if overlayInstance then 
            overlayInstance:_updateDisplayedMetrics() 
        end
        
        -- Обновление цветов при необходимости
        if self._systemConfiguration._healthBasedColorization 
            or self._systemConfiguration._teamAffiliationColorization then
            if self._highlightRenderersMap[playerInstance] then
                self._highlightRenderersMap[playerInstance]:_refreshColorization()
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Глобальный экземпляр системы
-- ═══════════════════════════════════════════════════════════════════
-- БАГ #16 FIX: _G.PlayerVisualTrackingSystem — слишком общее имя, конфликтует
-- с другими скриптами. Используем уникальный namespace MenuV1_PVT.
_G.MenuV1_PVT = VisualTrackingSystem.new()
-- Алиас для обратной совместимости (устарело — убрать после миграции GUI)
_G.PlayerVisualTrackingSystem = _G.MenuV1_PVT

-- Экспорт переменных для GUI (совместимость со старым интерфейсом)
espEnabled = false
espShowHealth = false
espShowDist = false
espShowName = false
espHealthColor = false
espShowTeamColor = false

-- Функции обратной совместимости
function espRefreshAll()
    _G.PlayerVisualTrackingSystem._systemConfiguration._trackerActivationState = espEnabled
    _G.PlayerVisualTrackingSystem:_executeFullSystemRefresh()
end

function espClearAll()
    _G.PlayerVisualTrackingSystem:_purgeAllVisualEffects()
end

function updateESPLabels()
    _G.PlayerVisualTrackingSystem._systemConfiguration._trackerActivationState = espEnabled
    _G.PlayerVisualTrackingSystem._systemConfiguration._healthMetricsDisplay = espShowHealth
    _G.PlayerVisualTrackingSystem._systemConfiguration._distanceCalculationDisplay = espShowDist
    _G.PlayerVisualTrackingSystem._systemConfiguration._playerIdentifierDisplay = espShowName
    _G.PlayerVisualTrackingSystem._systemConfiguration._healthBasedColorization = espHealthColor
    _G.PlayerVisualTrackingSystem._systemConfiguration._teamAffiliationColorization = espShowTeamColor
    _G.PlayerVisualTrackingSystem:_performCyclicUpdate()
end

-- ═══════════════════════════════════════════════════════════════════
-- Инициализация системы
-- ═══════════════════════════════════════════════════════════════════
for _, playerInstance in ipairs(Players:GetPlayers()) do 
    _G.PlayerVisualTrackingSystem:_registerPlayerIntoSystem(playerInstance) 
end

Players.PlayerAdded:Connect(function(playerInstance) 
    _G.PlayerVisualTrackingSystem:_registerPlayerIntoSystem(playerInstance) 
end)

Players.PlayerRemoving:Connect(function(playerInstance) 
    _G.PlayerVisualTrackingSystem:_unregisterPlayerFromSystem(playerInstance) 
end)

LocalPlayer:GetPropertyChangedSignal("Team"):Connect(espRefreshAll)

-- ═══════════════════════════════════════════════════════════════════
-- Watchdog процесс очистки
-- ═══════════════════════════════════════════════════════════════════
task.spawn(function()
    local cycleCounter = 0
    while true do
        task.wait(5)
        cycleCounter = cycleCounter + 1
        local removedPlayers = 0
        
        -- Удаление отключенных игроков
        for playerInstance in pairs(_G.PlayerVisualTrackingSystem._registeredPlayersPool) do
            if not playerInstance or playerInstance.Parent ~= Players then
                _G.PlayerVisualTrackingSystem:_unregisterPlayerFromSystem(playerInstance)
                removedPlayers = removedPlayers + 1
            end
        end
        
        -- Подсчет активных игроков
        local activePlayersCount = 0
        for _ in pairs(_G.MenuV1_PVT._registeredPlayersPool) do 
            activePlayersCount = activePlayersCount + 1 
        end
        
        addLog("PVT ▸ Watchdog #" .. cycleCounter .. "  pool=" .. activePlayersCount .. 
               (removedPlayers > 0 and "  removed=" .. removedPlayers or ""))
        
        -- Восстановление отсутствующих подсветок
        -- БАГ #2 FIX: проверяем _highlightRenderersMap перед созданием нового рендерера,
        -- иначе watchdog плодил дубликаты → утечка памяти + множественные подсветки.
        if espEnabled then
            local restoredCount = 0
            for playerInstance in pairs(_G.MenuV1_PVT._registeredPlayersPool) do
                if playerInstance and playerInstance.Parent == Players and playerInstance.Character then
                    if isEnemy(playerInstance) and not playerInstance.Character:FindFirstChild("_PVT_Highlight") then
                        -- Создаём только если не существует в map
                        if not _G.MenuV1_PVT._highlightRenderersMap[playerInstance] then
                            task.spawn(function() 
                                _G.MenuV1_PVT:_applyVisualsToPlayer(playerInstance) 
                            end)
                            restoredCount = restoredCount + 1
                        end
                    end
                end
            end
        end
    end
end)

addLog("PVT ▸ PlayerVisualTracker.lua loaded successfully")
