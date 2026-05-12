-- ═══════════════════════════════════════════════════════════════════
--  config.lua — Centralized Configuration System
-- ═══════════════════════════════════════════════════════════════════

local Config = {
    -- ═══════════════════════════════════════════════════════════════
    -- СИСТЕМА
    -- ═══════════════════════════════════════════════════════════════
    VERSION = "1.0.0",
    AUTHOR = "menu-main",
    
    -- ═══════════════════════════════════════════════════════════════
    -- ЛОГИРОВАНИЕ
    -- ═══════════════════════════════════════════════════════════════
    Logging = {
        defaultLevel = "DEBUG",        -- DEBUG, INFO, WARN, ERROR
        bufferSize = 150,              -- максимум строк в буфере
        timestampFormat = "%H:%M:%S",  -- формат времени
    },
    
    -- ═══════════════════════════════════════════════════════════════
    -- PERFORMANCE OPTIMIZATION
    -- ═══════════════════════════════════════════════════════════════
    Performance = {
        -- Батч-сканирование для больших карт
        batchSize = 200,               -- объектов за раз (GetDescendants)
        batchSizeScripts = 150,        -- скриптов за раз (античит)
        batchDelay = 0,                -- задержка между батчами (task.wait)
        
        -- NDS (No-Damage System)
        maxNdsObjects = 500,           -- максимум объектов в NDS
        maxPartsOverlap = 1000,        -- MaxParts для OverlapParams
        ndsUpdateMode = "RenderStepped", -- RenderStepped или Heartbeat
        ndsAttractionStrength = 1000,  -- базовая сила притяжения (100-5000)
        ndsHeightOffset = 0,           -- вертикальное смещение орбиты (-50 до +50)
        ndsMassCompensation = true,    -- компенсация массы объектов
    },
    
    -- ═══════════════════════════════════════════════════════════════
    -- TARGETING SYSTEM
    -- ═══════════════════════════════════════════════════════════════
    Targeting = {
        defaultBodyPart = "Head",
        cameraSmoothness = 0.15,
        fovBoundary = 120,
        fireCooldown = 0.10,
        
        -- Prediction
        predictionEnabled = false,
        predictionMultiplier = 0.0,
        perfectPrediction = false,
        
        -- Multi-point scanning
        multiPointEnabled = true,
        bodyPartPriorities = {
            Head = 10,
            UpperTorso = 7,
            LowerTorso = 6,
            ["Left Arm"] = 4,
            ["Right Arm"] = 4,
            ["Left Leg"] = 3,
            ["Right Leg"] = 3,
        },
    },
    
    -- ═══════════════════════════════════════════════════════════════
    -- MOVEMENT SYSTEM
    -- ═══════════════════════════════════════════════════════════════
    Movement = {
        -- Speed
        defaultWalkSpeed = 16,
        speedBoostValue = 100,
        
        -- Jump
        defaultJumpPower = 50,
        jumpBoostForce = 60,
        infiniteJumpEnabled = false,
        
        -- Fly
        flySpeed = 50,
        flyControlMode = "WASD",  -- WASD или Mouse
        
        -- Teleport
        loopTpInterval = 0.5,
        teleportOffset = 3,  -- расстояние от цели
        groundCheckDistance = 20,  -- raycast вниз для поиска земли
    },
    
    -- ═══════════════════════════════════════════════════════════════
    -- VISUAL EFFECTS
    -- ═══════════════════════════════════════════════════════════════
    Visual = {
        -- ESP
        defaultEspEnabled = false,
        defaultShowHealth = true,
        defaultShowDistance = true,
        defaultShowName = true,
        defaultHealthColor = true,
        defaultTeamColor = false,
        
        -- Environment
        particleCacheEnabled = true,
        fogEnabled = false,
        timeFreeze = false,
        defaultClockTime = 14,
    },
    
    -- ═══════════════════════════════════════════════════════════════
    -- ANTI-CHEAT MONITORING
    -- ═══════════════════════════════════════════════════════════════
    AntiCheat = {
        enabled = true,
        scanInterval = 5,  -- секунд между сканами
        suspiciousPatterns = {
            "anti",
            "detect",
            "ban",
            "kick",
            "flag",
            "ac_",
            "anticheat",
        },
    },
    
    -- ═══════════════════════════════════════════════════════════════
    -- DATABUS (Resource Control)
    -- ═══════════════════════════════════════════════════════════════
    DataBus = {
        requestTimeout = 5,  -- секунд до таймаута
        lockDuration = 0.5,  -- минимальное время владения
        debugMode = false,   -- логировать все запросы
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

function Config:Get(path)
    -- Получить значение по пути "Targeting.defaultBodyPart"
    local parts = {}
    for part in path:gmatch("[^.]+") do
        table.insert(parts, part)
    end
    
    local value = self
    for _, part in ipairs(parts) do
        value = value[part]
        if value == nil then return nil end
    end
    return value
end

function Config:Set(path, newValue)
    -- Установить значение по пути "Targeting.defaultBodyPart"
    local parts = {}
    for part in path:gmatch("[^.]+") do
        table.insert(parts, part)
    end
    
    local target = self
    for i = 1, #parts - 1 do
        target = target[parts[i]]
        if target == nil then return false end
    end
    
    target[parts[#parts]] = newValue
    return true
end

return Config
