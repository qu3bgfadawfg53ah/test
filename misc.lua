-- ═══════════════════════════════════════════════════════════════════
--  Misc  —  Utility Functions
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- ANTI-AFK
-- ═══════════════════════════════════════════════════════════════════
antiAfkEnabled = false
local _afkConn  = nil
local _afkConn2 = nil

local VU = game:GetService("VirtualUser")

local function _doAntiAfkTick()
    local ok = pcall(function()
        VU:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VU:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
    
    if not ok then
        pcall(function()
            VU:CaptureController()
            VU:ClickButton2(Vector2.new(0,0))
        end)
    end
end

function setAntiAfk(state)
    antiAfkEnabled = state
    
    if _afkConn  then _afkConn:Disconnect();  _afkConn  = nil end
    if _afkConn2 then _afkConn2:Disconnect(); _afkConn2 = nil end
    
    if not state then return end
    
    _afkConn = LocalPlayer.Idled:Connect(function()
        if not antiAfkEnabled then return end
        _doAntiAfkTick()
    end)
    
    -- БАГ #17 FIX: _afkConn2 был пустым Heartbeat — 60+ вызовов/сек без пользы.
    -- Удалён. Периодический тик обеспечивается task.spawn ниже.
    
    task.spawn(function()
        while antiAfkEnabled do
            task.wait(240)
            if not antiAfkEnabled then break end
            _doAntiAfkTick()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- FULLBRIGHT
-- ═══════════════════════════════════════════════════════════════════
fullbrightEnabled   = false
local _fbOrigAmb    = nil
local _fbOrigOutAmb = nil

function setFullbright(state)
    fullbrightEnabled = state
    if state then
        _fbOrigAmb    = Lighting.Ambient
        _fbOrigOutAmb = Lighting.OutdoorAmbient
        pcall(function()
            Lighting.Ambient        = Color3.new(1,1,1)
            Lighting.OutdoorAmbient = Color3.new(1,1,1)
        end)
    else
        pcall(function()
            Lighting.Ambient        = _fbOrigAmb    or Color3.fromRGB(70,70,70)
            Lighting.OutdoorAmbient = _fbOrigOutAmb or Color3.fromRGB(140,140,140)
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- PLAYER MUTE
-- ═══════════════════════════════════════════════════════════════════
-- БАГ #18 FIX: было _mutedPlayers[soundObj] = vol — нельзя размутить
-- конкретного игрока, только всех. Теперь _mutedPlayers[playerName] = {sound=vol}.
local _mutedPlayers = {}  -- { [playerName] = { [soundInstance] = originalVolume } }

function mutePlayer(name)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Name:lower():find(name:lower(), 1, true) then
            if p.Character then
                _mutedPlayers[p.Name] = _mutedPlayers[p.Name] or {}
                for _, v in ipairs(p.Character:GetDescendants()) do
                    if v:IsA("Sound") then
                        _mutedPlayers[p.Name][v] = v.Volume
                        pcall(function() v.Volume = 0 end)
                    end
                end
            end
            addLog("MUTE ▸ заглушён: " .. p.Name)
            return
        end
    end
    addLog("MUTE ▸ не найден: " .. name)
end

function unmutePlayer(name)
    local low = name:lower()
    for playerName, sounds in pairs(_mutedPlayers) do
        if playerName:lower():find(low, 1, true) then
            for sound, vol in pairs(sounds) do
                if sound and sound.Parent then
                    pcall(function() sound.Volume = vol end)
                end
            end
            _mutedPlayers[playerName] = nil
            addLog("MUTE ▸ размучен: " .. playerName)
            return
        end
    end
    addLog("MUTE ▸ не замьючен: " .. name)
end

function unmuteAll()
    for _, sounds in pairs(_mutedPlayers) do
        for sound, vol in pairs(sounds) do
            if sound and sound.Parent then
                pcall(function() sound.Volume = vol end)
            end
        end
    end
    _mutedPlayers = {}
    addLog("MUTE ▸ все звуки восстановлены")
end

-- ═══════════════════════════════════════════════════════════════════
-- SERVER INFO
-- ═══════════════════════════════════════════════════════════════════
function printServerInfo()
    addLog("─────────────── SERVER INFO ───────────────")
    addLog("SRV  ▸ PlaceId  : " .. game.PlaceId)
    addLog("SRV  ▸ JobId    : " .. tostring(game.JobId):sub(1,18) .. "…")
    addLog("SRV  ▸ Игроков  : " .. #Players:GetPlayers() .. " / " .. Players.MaxPlayers)
    addLog("SRV  ▸ Me       : " .. LocalPlayer.Name .. " [" .. LocalPlayer.UserId .. "]")
    addLog("SRV  ▸ Команда  : " .. (LocalPlayer.Team and LocalPlayer.Team.Name or "нет"))
    addLog("SRV  ▸ FE       : " .. (workspace.FilteringEnabled and "ON" or "OFF"))
    addLog("SRV  ▸ Gravity  : " .. workspace.Gravity)
    addLog("SRV  ▸ Ping     : " .. math.floor(LocalPlayer.NetworkPing * 1000) .. " ms")
    addLog("SRV  ▸ Version  : " .. MENU_VERSION)
    addLog("SRV  ▸ Author   : " .. MENU_AUTHOR)
    
    for _, p in ipairs(Players:GetPlayers()) do
        local team = p.Team and p.Team.Name or "—"
        local hum  = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        local hp   = hum and string.format("%d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth)) or "dead"
        local ping = math.floor(p.NetworkPing * 1000)
        addLog(string.format("  %-20s  hp=%-9s  ping=%-4d  team=%s",
            p.Name, hp, ping, team))
    end
    addLog("──────────────────────────────────────────")
end

-- ═══════════════════════════════════════════════════════════════════
-- AUTO-REJOIN
-- ═══════════════════════════════════════════════════════════════════
function autoRejoin()
    local ok = pcall(function()
        local TS = game:GetService("TeleportService")
        TS:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
    addLog("REJOIN▸ " .. (ok and "✅ переподключение…" or "❌ TeleportService заблокирован"))
end

-- ═══════════════════════════════════════════════════════════════════
-- GRAVITY
-- ═══════════════════════════════════════════════════════════════════
gravityEnabled = false
gravityValue   = 196.2

function applyGravity()
    pcall(function() workspace.Gravity = gravityValue end)
end

function resetGravity()
    pcall(function() workspace.Gravity = 196.2 end)
end

-- ═══════════════════════════════════════════════════════════════════
-- TOOL BINDINGS
-- ═══════════════════════════════════════════════════════════════════
local _toolConns = {}

local function unbindTool(tool)
    if not _toolConns[tool] then return end
    for _, c in ipairs(_toolConns[tool]) do c:Disconnect() end
    _toolConns[tool] = nil
end

function bindTool(tool)
    if not tool or _toolConns[tool] then return end
    local conns = {}
    conns[#conns+1] = tool.AncestryChanged:Connect(function()
        if not tool.Parent then unbindTool(tool) end
    end)
    _toolConns[tool] = conns
end

function bindAllTools()
    local char     = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if char then
        for _, v in ipairs(char:GetChildren()) do
            if v:IsA("Tool") then bindTool(v) end
        end
    end
    if backpack then
        for _, v in ipairs(backpack:GetChildren()) do
            if v:IsA("Tool") then bindTool(v) end
        end
    end
end
