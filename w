-- ==========================================
-- SCRIPT AUTO BUY & DISCORD WEBHOOK MONITOR (FIXED)
-- ==========================================

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local WebhookURL = "https://discord.com/api/webhooks/1563525889583743106/gutwd2T6TV2G2KEB9MaWTcllL5OdGDGK97LSpe09DIftrfr_0FH9GhIPbFihpwSLAxPR"

-- 1. REMOTE EVENT BUY
local BuyEvent = ReplicatedStorage:WaitForChild("Network"):WaitForChild("QuestService"):WaitForChild("RE"):WaitForChild("Buy")

-- 2. CARI CONTROLLER DATA SECARA DINAMIS
local function getDataController()
    local success, controller = pcall(function()
        -- Coba beberapa path Controller yang biasa digunakan
        if LocalPlayer.PlayerScripts:FindFirstChild("Client") then
            local client = LocalPlayer.PlayerScripts.Client
            if client:FindFirstChild("Controllers") and client.Controllers:FindFirstChild("DataController") then
                return require(client.Controllers.DataController)
            end
        end
        -- Fallback jika ada di Controllers langsung
        if LocalPlayer.PlayerScripts:FindFirstChild("Controllers") and LocalPlayer.PlayerScripts.Controllers:FindFirstChild("DataController") then
            return require(LocalPlayer.PlayerScripts.Controllers.DataController)
        end
        return nil
    end)
    
    if success and controller then
        return controller
    end
    return nil
end

-- 3. PEMINDAI INVENTORY (MENGGUNAKAN LOGIKA SCANNER ANDA)
local function getInventoryTable(DataController)
    if not DataController or not DataController.Inventory then
        return nil
    end

    local ok, inv = pcall(function()
        return DataController.Inventory()
    end)

    if ok and type(inv) == "table" then
        return inv
    end

    if type(DataController.Inventory) == "table" then
        return DataController.Inventory
    end

    return nil
end

local function scanBackpackAndGems(DataController)
    local traitRerollQty = 0
    local gemsCount = nil

    -- 1. Pindai Inventory
    local inventory = getInventoryTable(DataController)
    if inventory then
        for _, entry in pairs(inventory) do
            if type(entry) == "table" then
                local itemName = entry.name or (entry.config and entry.config.name) or ""
                if string.lower(itemName) == "trait reroll" then
                    traitRerollQty = traitRerollQty + (entry.amount or entry.quantity or 1)
                end
            end
        end
    end

    -- 2. Pindai Gems dari DataController / Replica
    if DataController then
        pcall(function()
            if type(DataController.Gems) == "function" then
                gemsCount = DataController.Gems()
            elseif DataController.Gems then
                gemsCount = DataController.Gems
            elseif type(DataController.GetData) == "function" then
                local data = DataController.GetData()
                if data then gemsCount = data.Gems or data.Gem end
            elseif DataController.Data then
                gemsCount = DataController.Data.Gems or DataController.Data.Gem
            end
        end)
    end

    -- Fallback jika Gems tersimpan di leaderstats
    if not gemsCount then
        local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
        if leaderstats then
            local g = leaderstats:FindFirstChild("Gems") or leaderstats:FindFirstChild("Gem")
            if g then gemsCount = g.Value end
        end
    end

    return traitRerollQty, gemsCount or "Tidak Diketahui"
end

-- 4. FUNGSI KIRIM WEBHOOK
local function sendWebhook(traitRerollCount, gemsCount)
    local jobId = game.JobId
    local profileName = LocalPlayer.Name
    local scriptTeleport = string.format('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game.Players.LocalPlayer)', game.PlaceId, jobId)

    local data = {
        ["embeds"] = {{
            ["title"] = "🛒 Status Auto Buy Trait Reroll",
            ["color"] = 65280,
            ["fields"] = {
                {
                    ["name"] = "👤 Player",
                    ["value"] = "```" .. profileName .. "```",
                    ["inline"] = true
                },
                {
                    ["name"] = "💎 Gems",
                    ["value"] = "```" .. tostring(gemsCount) .. "```",
                    ["inline"] = true
                },
                {
                    ["name"] = "🎲 Trait Reroll",
                    ["value"] = "```" .. tostring(traitRerollCount) .. "```",
                    ["inline"] = true
                },
                {
                    ["name"] = "🆔 Job ID (Current Server)",
                    ["value"] = "```" .. (jobId ~= "" and jobId or "Studio / Offline") .. "```",
                    ["inline"] = false
                },
                {
                    ["name"] = "🔗 Script Join Server",
                    ["value"] = "```lua\n" .. scriptTeleport .. "\n```",
                    ["inline"] = false
                }
            },
            ["footer"] = {
                ["text"] = os.date("%Y-%m-%d %H:%M:%S")
            }
        }}
    }

    local body = HttpService:JSONEncode(data)
    local headers = {["Content-Type"] = "application/json"}
    local requestFunc = (syn and syn.request) or http_request or request or HttpPost
    
    if requestFunc then
        pcall(function()
            requestFunc({Url = WebhookURL, Method = "POST", Headers = headers, Body = body})
        end)
    end
end

-- 5. LOOP UTAMA
task.spawn(function()
    while true do
        -- Eksekusi Auto Buy
        pcall(function()
            BuyEvent:FireServer("Trait Reroll")
        end)

        task.wait(2)

        -- Pindai Data
        local DataController = getDataController()
        local traitCount, gems = scanBackpackAndGems(DataController)

        -- Kirim ke Discord Webhook
        sendWebhook(traitCount, gems)

        task.wait(60) -- Interval pengiriman
    end
end)
