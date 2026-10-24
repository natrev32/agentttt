-- ==============================================================================
-- NIMBUS AGENT SCRIPT KHUSUS DELTA EXECUTOR (ANIME DICE EDITION)
-- Pure HTTP Version (100% Safe for Delta Mobile & PC)
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
    -- Jika Delta di HP/Android & Server di PC, ganti 127.0.0.1 ke IP PC (contoh: http://192.168.1.5:3000)
    HTTP_URL = "http://127.0.0.1:3000",
    
    -- Token Agent Nimbus Anda
    AGENT_TOKEN = "agent_8U0tEM-B0w_QOAoJBCe8pNZxAajX46ax",
    
    -- Interval pengiriman stats ke dashboard (detik)
    SYNC_INTERVAL = 8,
    
    -- Identifier game
    GAME_NAME = "anime-dice",
}

-- ==========================================
-- DELTA REQUEST FUNCTION DETECTOR
-- ==========================================
local httpReq = (request) 
    or (http and http.request) 
    or (syn and syn.request) 
    or http_request 
    or (fluxus and fluxus.request)

if not httpReq then
    warn("[Nimbus Delta Error] Executor Anda tidak mendukung fungsi HTTP request!")
    return
end

-- ==========================================
-- 1. LOAD GAME CONTROLLER
-- ==========================================
local DataController, EntryRegistry = nil, nil

local function resolveControllers()
    local Framework = ReplicatedStorage:WaitForChild("Framework", 10)
    if not Framework then
        warn("[Nimbus Delta] Folder Framework tidak ditemukan!")
        return nil, nil
    end

    local Features = Framework:WaitForChild("Features", 5)
    if not Features then return nil, nil end

    local DataFolder = Features:WaitForChild("Data", 5)
    local InventoryFolder = Features:WaitForChild("Inventory", 5)

    local DataControllerModule = DataFolder and DataFolder:WaitForChild("DataController", 5)
    local EntryRegistryModule = InventoryFolder and InventoryFolder:WaitForChild("EntryRegistry", 5)

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
local function getInventoryTable()
    if not DataController or not DataController.Inventory then return nil end

    local ok, inv = pcall(function() return DataController.Inventory() end)
    if ok and type(inv) == "table" then return inv end
    if type(DataController.Inventory) == "table" then return DataController.Inventory end

    return nil
end

local function scanBackpack()
    local units = {}
    local itemMap = {}

    local inventory = getInventoryTable()
    if not inventory then return units, {} end

    for itemId, entry in pairs(inventory) do
        if type(entry) == "table" and type(entry.name) == "string" then
            local entryConfig = (EntryRegistry and type(EntryRegistry.getEntryConfig) == "function")
                and EntryRegistry.getEntryConfig(entry.name) or {}

            local kind = string.lower(entryConfig.kind or entry.kind or "")
            local attrs = entry.attributes or {}

            if kind == "unit" or kind == "pet" or kind == "character" then
                -- Hitung Rarity
                local rarity = "Common"
                if type(entryConfig.getRarity) == "function" then
                    local okR, resR = pcall(entryConfig.getRarity, attrs)
                    if okR and resR then rarity = tostring(resR) end
                elseif type(entryConfig.rarity) == "function" then
                    local okR, resR = pcall(entryConfig.rarity, attrs)
                    if okR and resR then rarity = tostring(resR) end
                elseif entryConfig.rarity then
                    rarity = tostring(entryConfig.rarity)
                end

                -- Ambil Mutasi
                local mutations = {}
                if attrs.mutation and attrs.mutation ~= "" then
                    table.insert(mutations, tostring(attrs.mutation))
                elseif type(attrs.mutations) == "table" then
                    for _, m in ipairs(attrs.mutations) do
                        table.insert(mutations, tostring(m))
                    end
                end

                -- Hitung Income
                local income = 0
                if type(entryConfig.income) == "function" then
                    local okInc, resInc = pcall(entryConfig.income, attrs)
                    if okInc and tonumber(resInc) then income = tonumber(resInc) end
                elseif attrs.income then
                    income = tonumber(attrs.income) or 0
                end

                -- Hitung Odds / Peluang
                local odds = nil
                local chanceVal = nil
                if type(entryConfig.resolveChance) == "function" then
                    local okC, resC = pcall(entryConfig.resolveChance, attrs)
                    if okC then chanceVal = resC end
                elseif type(entryConfig.chance) == "function" then
                    local okC, resC = pcall(entryConfig.chance, attrs)
                    if okC then chanceVal = resC end
                elseif entryConfig.chance then
                    chanceVal = entryConfig.chance
                end
                if chanceVal and tonumber(chanceVal) then
                    odds = "1 in " .. tostring(math.floor(chanceVal))
                end

                local size = attrs.size or entryConfig.size or "Normal"
                local location = attrs.equipped and "Equipped" or "Backpack"

                table.insert(units, {
                    uid = tostring(itemId),
                    name = entry.name,
                    rarity = rarity,
                    size = tostring(size),
                    mutations = mutations,
                    income = income,
                    odds = odds,
                    location = location,
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
-- 3. UTILITAS SYNC HTTP KHUSUS DELTA
-- ==========================================
local function syncStatsDelta()
    if not DataController or not EntryRegistry then
        resolveControllers()
    end
    
    if not DataController then
        warn("[Nimbus Delta] Menunggu DataController siap...")
        return
    end

    local units, items = scanBackpack()
    local payload = {
        type = "sync",
        account = LocalPlayer.Name,
        serverId = game.JobId ~= "" and game.JobId or nil,
        game = CONFIG.GAME_NAME,
        units = units,
        items = items,
    }

    task.spawn(function()
        local ok, res = pcall(function()
            return httpReq({
                Url = CONFIG.HTTP_URL .. "/agent/sync",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["X-Agent-Key"] = CONFIG.AGENT_TOKEN,
                },
                Body = HttpService:JSONEncode(payload)
            })
        end)

        if ok and res then
            local statusCode = res.StatusCode or res.status_code or res.Status
            if statusCode and (statusCode >= 200 and statusCode < 300) then
                print(string.format("[Nimbus Delta] Berhasil Sync: %d unit, %d item terkirim!", #units, #items))
            else
                warn(string.format("[Nimbus Delta] Gagal Sync (HTTP Status %s): %s", tostring(statusCode), tostring(res.Body or res.body or "Unknown error")))
            end
        else
            warn("[Nimbus Delta] Gagal menghubungi backend (" .. CONFIG.HTTP_URL .. "). Pastikan server menyala dan IP/Port benar!")
        end
    end)
end

-- ==========================================
-- 4. START AGENT
-- ==========================================
print("==================================================")
print("[Nimbus Agent] Memulai Script di Delta Executor...")
print("==================================================")

resolveControllers()

-- Jalankan Loop Sync berkala
task.spawn(function()
    while true do
        syncStatsDelta()
        task.wait(CONFIG.SYNC_INTERVAL)
    end
end)
