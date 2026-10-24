-- ==============================================================================
-- NIMBUS AGENT SCRIPT UNTUK EXECUTOR DELTA & POTASSIUM (ANIME DICE EDITION)
-- ==============================================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- KONFIGURASI
-- ==========================================
local CONFIG = {
    -- Alamat WebSocket backend Nimbus
    WS_URL = "ws://127.0.0.1:3000/ws",
    HTTP_URL = "http://127.0.0.1:3000",
    
    -- Token Agent Nimbus Anda
    AGENT_TOKEN = "agent_8U0tEM-B0w_QOAoJBCe8pNZxAajX46ax",
    
    -- Interval pengiriman stats ke dashboard (detik)
    SYNC_INTERVAL = 8,
    
    -- Identifier game
    GAME_NAME = "anime-dice",
}

-- ==========================================
-- UNIVERSAL API RESOLVER (DELTA & POTASSIUM)
-- ==========================================
local httpRequest = (syn and syn.request) 
    or (http and http.request) 
    or http_request 
    or request 
    or (fluxus and fluxus.request)

local connectWS = nil
if WebSocket and WebSocket.connect then
    connectWS = WebSocket.connect
elseif websocket and websocket.connect then
    connectWS = websocket.connect
elseif syn and syn.websocket and syn.websocket.connect then
    connectWS = syn.websocket.connect
end

-- ==========================================
-- 1. LOAD GAME CONTROLLER
-- ==========================================
local function resolveControllers()
    local Framework = ReplicatedStorage:WaitForChild("Framework", 10)
    if not Framework then
        warn("[Nimbus] Folder ReplicatedStorage.Framework tidak ditemukan!")
        return nil, nil
    end

    local DataControllerModule = Framework:WaitForChild("Features"):WaitForChild("Data"):WaitForChild("DataController", 5)
    local EntryRegistryModule = Framework:WaitForChild("Features"):WaitForChild("Inventory"):WaitForChild("EntryRegistry", 5)

    local DataController, EntryRegistry = nil, nil

    if DataControllerModule and DataControllerModule:IsA("ModuleScript") then
        local ok, dc = pcall(require, DataControllerModule)
        if ok and dc then DataController = dc end
    end

    if EntryRegistryModule and EntryRegistryModule:IsA("ModuleScript") then
        local ok, er = pcall(require, EntryRegistryModule)
        if ok and er then EntryRegistry = er end
    end

    return DataController, EntryRegistry
end

-- ==========================================
-- 2. PEMINDAI INVENTORI
-- ==========================================
local function getInventoryTable(DataController)
    if not DataController or not DataController.Inventory then return nil end

    local ok, inv = pcall(function() return DataController.Inventory() end)
    if ok and type(inv) == "table" then return inv end
    if type(DataController.Inventory) == "table" then return DataController.Inventory end

    return nil
end

local function scanBackpack(DataController, EntryRegistry)
    local units = {}
    local itemMap = {}

    local inventory = getInventoryTable(DataController)
    if not inventory then return units, {} end

    for itemId, entry in pairs(inventory) do
        if type(entry) == "table" and type(entry.name) == "string" then
            local entryConfig = (EntryRegistry and type(EntryRegistry.getEntryConfig) == "function")
                and EntryRegistry.getEntryConfig(entry.name) or {}

            local kind = string.lower(entryConfig.kind or entry.kind or "")
            local attrs = entry.attributes or {}

            if kind == "unit" or kind == "pet" or kind == "character" then
                local rarity = "Common"
                if type(entryConfig.getRarity) == "function" then
                    local okR, resR = pcall(entryConfig.getRarity, attrs)
                    if okR and resR then rarity = tostring(resR) end
                elseif entryConfig.rarity then
                    rarity = tostring(entryConfig.rarity)
                end

                local mutations = {}
                if attrs.mutation and attrs.mutation ~= "" then
                    table.insert(mutations, tostring(attrs.mutation))
                end

                local income = 0
                if type(entryConfig.income) == "function" then
                    local okInc, resInc = pcall(entryConfig.income, attrs)
                    if okInc and tonumber(resInc) then income = tonumber(resInc) end
                end

                table.insert(units, {
                    uid = tostring(itemId),
                    name = entry.name,
                    rarity = rarity,
                    size = tostring(attrs.size or entryConfig.size or "Normal"),
                    mutations = mutations,
                    income = income,
                    location = attrs.equipped and "Equipped" or "Backpack",
                })
            else
                local currentQty = itemMap[entry.name] or 0
                itemMap[entry.name] = currentQty + (entry.amount or 1)
            end
        end
    end

    local items = {}
    for itemName, qty in pairs(itemMap) do
        table.insert(items, { name = itemName, qty = qty })
    end

    return units, items
end

-- ==========================================
-- 3. KONEKSI & AUTOSYNC
-- ==========================================
local wsConnection = nil
local isConnected = false
local DataController, EntryRegistry = nil, nil

local function sendWS(payload)
    if wsConnection then
        wsConnection:Send(HttpService:JSONEncode(payload))
    end
end

local function syncStats()
    if not DataController or not EntryRegistry then
        DataController, EntryRegistry = resolveControllers()
    end
    if not DataController then return end

    local units, items = scanBackpack(DataController, EntryRegistry)
    local payload = {
        type = "sync",
        account = LocalPlayer.Name,
        serverId = game.JobId ~= "" and game.JobId or nil,
        game = CONFIG.GAME_NAME,
        units = units,
        items = items,
    }

    if isConnected and wsConnection then
        sendWS(payload)
        print(string.format("[Nimbus Delta] WS Sync berhasil: %d unit, %d item", #units, #items))
    elseif httpRequest then
        -- Fallback HTTP jika WebSocket Delta tidak terhubung ke 127.0.0.1
        task.spawn(function()
            pcall(function()
                httpRequest({
                    Url = CONFIG.HTTP_URL .. "/agent/sync",
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["X-Agent-Key"] = CONFIG.AGENT_TOKEN,
                    },
                    Body = HttpService:JSONEncode(payload)
                })
            end)
        end)
        print(string.format("[Nimbus Delta] HTTP Fallback Sync: %d unit, %d item", #units, #items))
    end
end

-- ==========================================
-- 4. START AGENT
-- ==========================================
local function startAgent()
    print("[Nimbus] Menginisialisasi Agent untuk Delta Executor...")
    DataController, EntryRegistry = resolveControllers()

    -- Jika Delta tidak mendukung WebSocket ke Localhost
    if not connectWS then
        warn("[Nimbus] Executor Delta tidak mendukung WebSocket API standar. Menggunakan HTTP Mode.")
        task.spawn(function()
            while true do
                syncStats()
                task.wait(CONFIG.SYNC_INTERVAL)
            end
        end)
        return
    end

    local function connect()
        local ok, ws = pcall(function()
            return connectWS(CONFIG.WS_URL)
        end)

        if not ok or not ws then
            warn("[Nimbus] Gagal terhubung via WS. Menmencoba HTTP polling mode...")
            task.spawn(function()
                while not isConnected do
                    syncStats()
                    task.wait(CONFIG.SYNC_INTERVAL)
                end
            end)
            return
        end

        wsConnection = ws

        sendWS({
            type = "auth",
            role = "agent",
            token = CONFIG.AGENT_TOKEN,
            account = LocalPlayer.Name,
        })

        ws.OnMessage:Connect(function(raw)
            local okDecode, msg = pcall(function() return HttpService:JSONDecode(raw) end)
            if not okDecode or not msg then return end

            if msg.type == "ready" then
                isConnected = true
                print(">>> [Nimbus] Berhasil Terhubung di Delta Executor! <<<")
                syncStats()
            end
        end)

        ws.OnClose:Connect(function()
            isConnected = false
            wsConnection = nil
            task.delay(5, connect)
        end)
    end

    task.spawn(connect)

    task.spawn(function()
        while true do
            task.wait(CONFIG.SYNC_INTERVAL)
            syncStats()
        end
    end)
end

startAgent()
