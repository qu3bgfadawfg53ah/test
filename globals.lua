-- ═══════════════════════════════════════════════════════════════════
--  globals.lua  —  Modernized Core System
--  Загружается ПЕРВЫМ
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- [СЕРВИСЫ]
-- БАГ #22 NOTE: сервисы намеренно объявлены глобально для совместимости
-- со всеми модулями (300+ обращений без префикса). Полный перевод на
-- local + module export — см. TODO в README. Пока добавляем защитный
-- алиас: если сервис уже был получен другим скриптом — не переписываем.
-- ═══════════════════════════════════════════════════════════════════
Players           = Players           or game:GetService("Players")
UserInputService  = UserInputService  or game:GetService("UserInputService")
RunService        = RunService        or game:GetService("RunService")
GuiService        = GuiService        or game:GetService("GuiService")
Lighting          = Lighting          or game:GetService("Lighting")
TweenService      = TweenService      or game:GetService("TweenService")
HttpService       = HttpService       or game:GetService("HttpService")
ReplicatedStorage = ReplicatedStorage or game:GetService("ReplicatedStorage")

LocalPlayer = Players.LocalPlayer
PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
camera      = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════════
-- [ВЕРСИЯ И АВТОР]
-- ═══════════════════════════════════════════════════════════════════
MENU_VERSION = "1.0.0"
MENU_AUTHOR  = "menu-main"

-- ═══════════════════════════════════════════════════════════════════
-- [ФЛАГИ СОСТОЯНИЯ — ИНИЦИАЛИЗАЦИЯ]
-- БАГ #1 FIX: speedEnabled/jumpEnabled/teleportEnabled/flyEnabled
-- использовались в MetatableProxy (строки 298-327) до инициализации.
-- nil в условии «if key == "WalkSpeed" and speedEnabled» безопасен,
-- но «if not speedEnabled and not jumpEnabled» на строке 351 давал
-- attempt to compare nil with boolean при определённых путях запуска.
-- ═══════════════════════════════════════════════════════════════════
speedEnabled    = false
jumpEnabled     = false
teleportEnabled = false
flyEnabled      = false

-- ═══════════════════════════════════════════════════════════════════
-- [ЦВЕТОВАЯ ПАЛИТРА]
-- ═══════════════════════════════════════════════════════════════════
C = {
    bg         = Color3.fromRGB(12,   5,  24),
    bar        = Color3.fromRGB(75,   8, 155),
    tabBg      = Color3.fromRGB(22,   6,  42),
    tabOn      = Color3.fromRGB(128,  12, 230),
    tabOff     = Color3.fromRGB(42,  15,  70),
    content    = Color3.fromRGB(16,   5,  30),
    rowBg      = Color3.fromRGB(28,  10,  52),
    rowHover   = Color3.fromRGB(38,  15,  68),
    togOn      = Color3.fromRGB(138,  8, 248),
    togOff     = Color3.fromRGB(48,  20,  80),
    sliderBg   = Color3.fromRGB(38,  13,  64),
    sliderFill = Color3.fromRGB(158, 28, 255),
    border     = Color3.fromRGB(118, 38, 218),
    borderDim  = Color3.fromRGB(58,  20, 108),
    text       = Color3.fromRGB(242, 215, 255),
    textDim    = Color3.fromRGB(155, 115, 205),
    sep        = Color3.fromRGB(62,  25, 110),
    toggleBtn  = Color3.fromRGB(58,   8, 120),
    inputBg    = Color3.fromRGB(24,   8,  46),
    btnAction  = Color3.fromRGB(85,   8, 165),
    btnHover   = Color3.fromRGB(108, 12, 198),
    accent     = Color3.fromRGB(182, 52, 255),
    accentDim  = Color3.fromRGB(115, 28, 190),
    logBg      = Color3.fromRGB(11,   5,  22),
    logText    = Color3.fromRGB(165, 235, 140),
    logSys     = Color3.fromRGB(110, 190, 255),
    green      = Color3.fromRGB(90,  220,  90),
    orange     = Color3.fromRGB(255, 175,  40),
    red        = Color3.fromRGB(240,  60,  60),
    yellow     = Color3.fromRGB(255, 230,  60),
    cyan       = Color3.fromRGB(90,  230, 255),
    white      = Color3.fromRGB(255, 255, 255),
    pink       = Color3.fromRGB(255, 135, 210),
}

-- ═══════════════════════════════════════════════════════════════════
-- [СИСТЕМА ЛОГИРОВАНИЯ]
-- БАГ #30 FIX: добавлены уровни логирования (DEBUG/INFO/WARN/ERROR).
-- addLog по-прежнему работает без уровня (= INFO).
-- Для фильтрации: установи LOG_LEVEL = "WARN" — меньше шума в консоли.
-- ═══════════════════════════════════════════════════════════════════
LOG_MAX   = 200
logBuffer = {}
logDirty  = false
logLabel  = nil

local LOG_LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
LOG_LEVEL = "DEBUG"  -- минимальный уровень для записи в буфер

function addLog(msg, level)
    level = level or "INFO"
    local levelNum  = LOG_LEVELS[level]  or 1
    local filterNum = LOG_LEVELS[LOG_LEVEL] or 0
    if levelNum < filterNum then return end  -- отфильтровываем ниже порога

    local prefix = (level == "WARN" and "⚠ " or level == "ERROR" and "❌ " or "")
    local ts    = string.format("[%05.1f]", tick() % 1000)
    local entry = ts .. " " .. prefix .. tostring(msg)
    logBuffer[#logBuffer + 1] = entry
    if #logBuffer > LOG_MAX then table.remove(logBuffer, 1) end
    logDirty = true
end

-- Хелперы для удобства
function addLogWarn(msg)  addLog(msg, "WARN")  end
function addLogError(msg) addLog(msg, "ERROR") end
function addLogDebug(msg) addLog(msg, "DEBUG") end

function clearLog()
    logBuffer = {}
    logDirty  = true
    addLog("LOG ▸ cleared")
end

-- ═══════════════════════════════════════════════════════════════════
-- [УТИЛИТЫ]
-- ═══════════════════════════════════════════════════════════════════
function notify(title, body, duration)
    duration = duration or 3
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title    = tostring(title or "System"),
            Text     = tostring(body  or ""),
            Duration = duration,
        })
    end)
end

function round(n, digits)
    local m = 10 ^ (digits or 0)
    return math.floor(n * m + 0.5) / m
end

function fmtDist(d)
    if d >= 1000 then return string.format("%.1fk", d / 1000) end
    return string.format("%d", math.floor(d))
end

function fmtHealth(hum)
    if not hum then return "? HP" end
    return string.format("%d/%d HP", math.floor(hum.Health), math.floor(hum.MaxHealth))
end

function safeCall(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then addLog("[ERR] " .. tostring(tag) .. ": " .. tostring(err)) end
    return ok
end

function isEnemy(p)
    if p == LocalPlayer       then return false end
    if not p.Character        then return false end
    if not p.Team or not LocalPlayer.Team then return true end
    return p.Team ~= LocalPlayer.Team
end

function getHRP(p)
    return p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

function getHum(p)
    return p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
end

function lerp(a, b, t) return a + (b - a) * t end

-- ═══════════════════════════════════════════════════════════════════
-- [ENGINE CONFIG]
-- Централизованные настройки движка модулей и планировщика
-- ═══════════════════════════════════════════════════════════════════
ENGINE_CONFIG = {
    registry = {
        defaultPriority = "MEDIUM",
        validPriorities = { HIGH = true, MEDIUM = true, LOW = true },
        duplicatePolicy = "replace", -- replace | ignore
    },
    scheduler = {
        intervals = {
            MEDIUM = 0.10,
            LOW    = 1.00,
        }
    }
}

-- ═══════════════════════════════════════════════════════════════════
-- [МОДУЛЬ: MODULE REGISTRY]
-- Система регистрации и управления модулями
-- ═══════════════════════════════════════════════════════════════════
ModuleRegistry = {
    _registered = {},
    _metadata = {},
    _priorities = {
        HIGH   = {},  -- Обновляется каждый кадр (Targeting, Movement)
        MEDIUM = {},  -- 10 раз в секунду (ESP, Visuals)
        LOW    = {}   -- 1 раз в секунду (System checks)
    }
}

function ModuleRegistry:_normalizePriority(priority)
    priority = priority or ENGINE_CONFIG.registry.defaultPriority
    if not ENGINE_CONFIG.registry.validPriorities[priority] then
        addLog("[REGISTRY] ⚠ Unknown priority '" .. tostring(priority) .. "', fallback to " .. ENGINE_CONFIG.registry.defaultPriority)
        return ENGINE_CONFIG.registry.defaultPriority
    end
    return priority
end

function ModuleRegistry:_removeFromPriorityLists(moduleName)
    for _, list in pairs(self._priorities) do
        for i = #list, 1, -1 do
            if list[i].Name == moduleName then
                table.remove(list, i)
            end
        end
    end
end

function ModuleRegistry:Register(module, priority)
    if type(module) ~= "table" then
        addLog("[REGISTRY] ❌ Module must be a table")
        return false
    end

    if not module.Name then
        addLog("[REGISTRY] ❌ Module missing Name field")
        return false
    end
    
    if not module.OnUpdate then
        addLog("[REGISTRY] ❌ Module " .. module.Name .. " missing OnUpdate")
        return false
    end
    
    priority = self:_normalizePriority(priority)

    if self._registered[module.Name] then
        if ENGINE_CONFIG.registry.duplicatePolicy == "ignore" then
            addLog("[REGISTRY] ⚠ Duplicate ignored: " .. module.Name)
            return false
        end
        self:_removeFromPriorityLists(module.Name)
        addLog("[REGISTRY] ↻ Replacing duplicate: " .. module.Name)
    end
    
    self._registered[module.Name] = module
    self._metadata[module.Name] = {
        priority = priority,
        registeredAt = tick(),
        updates = 0,
        errors = 0,
    }
    table.insert(self._priorities[priority], module)
    
    addLog("[REGISTRY] ✅ Registered: " .. module.Name .. " [" .. priority .. "]")
    
    if module.OnEnable then
        module:OnEnable()
    end
    
    return true
end

function ModuleRegistry:EnableModule(name)
    local mod = self._registered[name]
    if mod then
        mod.Enabled = true
        if mod.OnEnable then mod:OnEnable() end
        addLog("[REGISTRY] Enabled: " .. name)
    end
end

function ModuleRegistry:DisableModule(name)
    local mod = self._registered[name]
    if mod then
        mod.Enabled = false
        if mod.OnDisable then mod:OnDisable() end
        addLog("[REGISTRY] Disabled: " .. name)
    end
end

function ModuleRegistry:GetModule(name)
    return self._registered[name]
end

function ModuleRegistry:UpdateAllModules(deltaTime, priority)
    priority = self:_normalizePriority(priority)
    local modules = self._priorities[priority]
    
    for _, module in ipairs(modules) do
        if module.Enabled and module.OnUpdate then
            local ok, err = pcall(module.OnUpdate, module, deltaTime)
            local meta = self._metadata[module.Name]
            if meta then
                meta.updates = meta.updates + 1
                meta.lastUpdateAt = tick()
            end
            if not ok then
                if meta then meta.errors = meta.errors + 1 end
                addLog("[REGISTRY] Error in " .. module.Name .. ": " .. tostring(err))
            end
        end
    end
end

function ModuleRegistry:GetStats(name)
    if name then return self._metadata[name] end
    return self._metadata
end

-- ═══════════════════════════════════════════════════════════════════
-- [МОДУЛЬ: METATABLE PROXY]
-- Защита от античита через подмену метатаблиц
-- БАГ #26 NOTE: MetatableProxy активен — UpdateOriginalValues вызывается
-- из централизованного 10Hz тика в блоке ИНИЦИАЛИЗАЦИЯ СИСТЕМ ниже.
-- CreateSpoofedHumanoid / CreateSpoofedRootPart вызываются из
-- PlayerKinematicsControlSystem при включении speed/fly/teleport.
-- Если нужно отключить spoofing полностью — установи MetatableProxy.disabled = true.
-- ═══════════════════════════════════════════════════════════════════
MetatableProxy = {
    _originalValues = {},
    _spoofedInstances = {},
    disabled = false,  -- #26: явный флаг отключения для отладки
}

function MetatableProxy:CreateSpoofedHumanoid(realHumanoid)
    if not realHumanoid then return nil end
    
    -- Сохраняем оригинальные значения
    self._originalValues.WalkSpeed = realHumanoid.WalkSpeed
    self._originalValues.JumpPower = realHumanoid.JumpPower
    self._originalValues.JumpHeight = realHumanoid.JumpHeight
    
    local proxy = setmetatable({}, {
        __index = function(_, key)
            -- Если античит запрашивает модифицированные свойства
            if key == "WalkSpeed" and speedEnabled then
                return self._originalValues.WalkSpeed or 16
            elseif key == "JumpPower" and jumpEnabled then
                return self._originalValues.JumpPower or 50
            elseif key == "JumpHeight" and jumpEnabled then
                return self._originalValues.JumpHeight or 7.2
            end
            
            return realHumanoid[key]
        end,
        
        __newindex = function(_, key, value)
            realHumanoid[key] = value
        end
    })
    
    self._spoofedInstances[realHumanoid] = proxy
    return proxy
end

function MetatableProxy:CreateSpoofedRootPart(realRootPart)
    if not realRootPart then return nil end
    
    self._originalValues.CFrame = realRootPart.CFrame
    self._originalValues.AssemblyLinearVelocity = realRootPart.AssemblyLinearVelocity
    
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == "CFrame" and (teleportEnabled or flyEnabled) then
                return self._originalValues.CFrame
            elseif key == "AssemblyLinearVelocity" and speedEnabled then
                return self._originalValues.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
            end
            
            return realRootPart[key]
        end,
        
        __newindex = function(_, key, value)
            realRootPart[key] = value
        end
    })
    
    self._spoofedInstances[realRootPart] = proxy
    return proxy
end

function MetatableProxy:UpdateOriginalValues()
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = getHum(LocalPlayer)
    local hrp = getHRP(LocalPlayer)
    
    if hum and not speedEnabled and not jumpEnabled then
        self._originalValues.WalkSpeed = hum.WalkSpeed
        self._originalValues.JumpPower = hum.JumpPower
        self._originalValues.JumpHeight = hum.JumpHeight
    end
    
    if hrp and not teleportEnabled and not flyEnabled and not speedEnabled then
        self._originalValues.CFrame = hrp.CFrame
        self._originalValues.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- [МОДУЛЬ: DATA BUS]
-- Централизованная шина данных и управление приоритетами
-- ═══════════════════════════════════════════════════════════════════
DataBus = {
    _controlPriorities = {
        Camera = nil,      -- Кто управляет камерой (Targeting, Visuals)
        Movement = nil,    -- Кто управляет движением (Movement, Teleport)
        Character = nil    -- Кто управляет персонажем (Kinematics)
    },
    _sharedData = {}
}

function DataBus:RequestControl(resource, moduleName, priority)
    priority = priority or 1
    
    local current = self._controlPriorities[resource]
    if not current or priority > current.priority then
        self._controlPriorities[resource] = {
            module = moduleName,
            priority = priority,
            timestamp = tick()
        }
        return true
    end
    
    return false
end

function DataBus:ReleaseControl(resource, moduleName)
    local current = self._controlPriorities[resource]
    if current and current.module == moduleName then
        self._controlPriorities[resource] = nil
    end
end

function DataBus:HasControl(resource, moduleName)
    local current = self._controlPriorities[resource]
    return current and current.module == moduleName
end

function DataBus:SetData(key, value)
    self._sharedData[key] = value
end

function DataBus:GetData(key)
    return self._sharedData[key]
end

-- ═══════════════════════════════════════════════════════════════════
-- [ИНИЦИАЛИЗАЦИЯ СИСТЕМ]
-- ═══════════════════════════════════════════════════════════════════
-- БАГ #32 FIX: централизованный обработчик CharacterAdded.
-- Каждый модуль слушал своё — при respawn некоторые системы
-- не переинициализировались. Теперь один хаб: подписывайся через
-- CharacterCallbacks.register(fn) вместо LocalPlayer.CharacterAdded:Connect.
-- ═══════════════════════════════════════════════════════════════════
CharacterCallbacks = { _handlers = {} }

function CharacterCallbacks.register(fn)
    table.insert(CharacterCallbacks._handlers, fn)
end

local function _onCharacterAdded(char)
    -- Сбрасываем флаги состояния при respawn
    aimLockedTarget = nil
    for _, fn in ipairs(CharacterCallbacks._handlers) do
        task.spawn(pcall, fn, char)  -- каждый хендлер в своём потоке, с защитой
    end
    addLog("CORE ▸ CharacterAdded: " .. LocalPlayer.Name)
end

LocalPlayer.CharacterAdded:Connect(_onCharacterAdded)
-- Если персонаж уже есть на момент загрузки (execute после spawn)
if LocalPlayer.Character then
    task.spawn(_onCharacterAdded, LocalPlayer.Character)
end

task.spawn(function()
    task.wait(0.5)
    
    -- ИСПРАВЛЕНИЕ: UpdateOriginalValues запускалась каждый кадр (60+ раз/сек).
    -- Она делает поиск Character/Humanoid/HRP — это дорого при частом вызове.
    -- Достаточно 10 раз в секунду: значения меняются медленно, это просто снапшот.
    local _proxyTimer = 0
    RunService.Heartbeat:Connect(function(dt)
        _proxyTimer = _proxyTimer + dt
        if _proxyTimer < 0.10 then return end  -- 10 Hz вместо 60+ Hz
        _proxyTimer = 0
        MetatableProxy:UpdateOriginalValues()
    end)
    
    addLog("CORE ▸ Module Registry initialized")
    addLog("CORE ▸ Metatable Proxy initialized (10 Hz)")
    addLog("CORE ▸ Data Bus initialized")
end)
