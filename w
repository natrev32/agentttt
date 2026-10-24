-- ==============================================================================
-- NIMBUS AGENT SCRIPT UNTUK EXECUTOR POTASSIUM (ANIME DICE EDITION)
-- Langsung copy & paste seluruh script ini ke Potassium, lalu klik EXECUTE.
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
-- 1. LOAD GAME CONTROLLER (ANIME DICE FRAMEWORK)
-- ==========================================
local function resolveControllers()
    local Framework = ReplicatedStorage:WaitForChild("Framework", 10)
    if not Framework then
        warn("[Nimbus] Folder ReplicatedStorage.Framework tidak ditemukan!")
        return nil, nil
    end

    local DataControllerModule = Framework:WaitForChild("Features"):WaitForChild("Data"):WaitForChild("DataController", 5)
    local EntryRegistryModule = Framework:WaitForChild("Features"):WaitForChild("Inventory"):WaitForChild("EntryRegistry", 5)

    local DataController = nil
    local EntryRegistry = nil

    if DataControllerModule and DataControllerModule:IsA("ModuleScript") then
        local ok, dc = pcall(require, DataControllerModule)
        if ok and dc then
            DataController = dc
        else
            warn("[Nimbus] Gagal me-require DataController:", dc)
        end
    end

    if EntryRegistryModule and EntryRegistryModule:IsA("ModuleScript") then
        local ok, er = pcall(require, EntryRegistryModule)
        if ok and er then
            EntryRegistry = er
        else
            warn("[Nimbus] Gagal me-require EntryRegistry:", er)
        end
    end

    return DataController, EntryRegistry
end

-- ==========================================
-- 2. PEMINDAI (SCANNER) BACKPACK & INVENTORI
-- ==========================================
local function getInventoryTable(DataController)
    if not DataController or not DataController.Inventory then
        return nil
    end

    -- DataController.Inventory pada framework Anime Dice adalah objek Value dengan metamethod __call
    local ok, inv = pcall(function()
        return DataController.Inventory()
    end)

    if ok and type(inv) == "table" then
        return inv
    end

    -- Fallback jika berupa raw table
    if type(DataController.Inventory) == "table" then
        return DataController.Inventory
    end

    return nil
end

local function scanBackpack(DataController, EntryRegistry)
    local units = {}
    local itemMap = {}

    local inventory = getInventoryTable(DataController)
    if not inventory then
        warn("[Nimbus] DataController.Inventory belum siap atau kosong!")
        return units, {}
    end

    local totalEntries = 0
    for itemId, entry in pairs(inventory) do
        if type(entry) == "table" and type(entry.name) == "string" then
            totalEntries = totalEntries + 1
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
                    if okInc and tonumber(resInc) then
                        income = tonumber(resInc)
                    end
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
                -- Selain unit, masukkan ke Items (Boost, Spin, Token, Potion, dll)
                local currentQty = itemMap[entry.name] or 0
                itemMap[entry.name] = currentQty + (entry.amount or 1)
            end
        end
    end

    local items = {}
    for itemName, qty in pairs(itemMap) do
        table.insert(items, {
            name = itemName,
            qty = qty,
        })
    end

    return units, items
end

-- ==========================================
-- 3. PEMINDAI PLAYER ONLINE
-- ==========================================
local function scanOnlinePlayers(includeLocalPlayer)
    local results = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if includeLocalPlayer or player ~= LocalPlayer then
            local money = 0
            local leaderstats = player:FindFirstChild("leaderstats")
            local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")

            if moneyValue then
                money = moneyValue.Value
            end

            table.insert(results, {
                player = player,
                userId = player.UserId,
                name = player.Name,
                displayName = player.DisplayName,
                accountAge = player.AccountAge,
                money = money,
            })
        end
    end

    return results
end

-- ==========================================
-- 4. KONEKSI KE NIMBUS (WEBSOCKET & FALLBACK)
-- ==========================================
local connectWS = (WebSocket and WebSocket.connect) 
    or (websocket and websocket.connect) 
    or (syn and syn.websocket and syn.websocket.connect)

local httpRequest = (syn and syn.request) 
    or (http and http.request) 
    or http_request 
    or request

local wsConnection = nil
local isConnected = false
local DataController, EntryRegistry = nil, nil

local function sendWS(payload)
    if wsConnection then
        wsConnection:Send(HttpService:JSONEncode(payload))
    end
end

local function logAgent(msg, data)
    print("[Nimbus] " .. tostring(msg))
    sendWS({
        type = "agent_log",
        message = tostring(msg),
        data = data
    })
end

local function getTradeNetwork()
    local NetworkFolder = ReplicatedStorage:FindFirstChild("Network")
    if not NetworkFolder then return nil, nil, nil end
    local TradeService = NetworkFolder:FindFirstChild("TradeService") or NetworkFolder:FindFirstChild("Trade")
    if not TradeService then return nil, nil, nil end
    local TradeRE = TradeService:FindFirstChild("RE")
    local TradeRF = TradeService:FindFirstChild("RF")
    return TradeService, TradeRE, TradeRF
end

local function findRemote(folder, candidates)
    if not folder then return nil end
    for _, name in ipairs(candidates) do
        local r = folder:FindFirstChild(name)
        if r then return r end
    end
    for _, child in ipairs(folder:GetChildren()) do
        for _, name in ipairs(candidates) do
            if child.Name:lower() == name:lower() then
                return child
            end
        end
    end
    return nil
end

local function findTradeGui()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    for _, g in ipairs(playerGui:GetChildren()) do
        if g:IsA("ScreenGui") and g.Name:lower():find("trade") then
            return g
        end
    end
    return nil
end

local function isTradeGuiActive(tradeGui)
    if not tradeGui then return false end
    if tradeGui.Enabled then return true end
    for _, d in ipairs(tradeGui:GetDescendants()) do
        if d:IsA("GuiObject") and d.Visible and (d.Name:lower():find("trade") or d.Name:lower():find("main") or d.Name:lower():find("frame")) then
            return true
        end
    end
    return false
end

local function clickGuiButton(btn)
    if not btn then return end
    pcall(function()
        if firesignal then
            if btn.Activated then firesignal(btn.Activated) end
            if btn.MouseButton1Click then firesignal(btn.MouseButton1Click) end
        end
    end)
end

local function inspectTradeSystem()
    local TradeService, TradeRE, TradeRF = getTradeNetwork()
    local reList, rfList = {}, {}
    if TradeRE then
        for _, r in ipairs(TradeRE:GetChildren()) do table.insert(reList, r.Name) end
    end
    if TradeRF then
        for _, r in ipairs(TradeRF:GetChildren()) do table.insert(rfList, r.Name) end
    end

    local Framework = ReplicatedStorage:FindFirstChild("Framework")
    local features = {}
    local tradeModulesInfo = {}
    if Framework and Framework:FindFirstChild("Features") then
        for _, f in ipairs(Framework.Features:GetChildren()) do
            table.insert(features, f.Name)
            if f.Name:lower():find("trade") then
                for _, m in ipairs(f:GetDescendants()) do
                    if m:IsA("ModuleScript") then
                        local okR, modTable = pcall(require, m)
                        local funcInfo = {}
                        if okR and type(modTable) == "table" then
                            for k, v in pairs(modTable) do
                                local desc = type(v)
                                if type(v) == "function" and getconstants then
                                    local okC, consts = pcall(getconstants, v)
                                    if okC and consts then
                                        local strConsts = {}
                                        for _, c in ipairs(consts) do
                                            if type(c) == "string" and #c < 40 then
                                                table.insert(strConsts, c)
                                            end
                                        end
                                        desc = "func(" .. table.concat(strConsts, ",") .. ")"
                                    end
                                end
                                funcInfo[tostring(k)] = desc
                            end
                        end
                        tradeModulesInfo[m.Name] = funcInfo
                    end
                end
            end
        end
    end

    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
    local guiNames = {}
    local tradeElements = {}
    if pGui then
        for _, g in ipairs(pGui:GetChildren()) do
            table.insert(guiNames, g.Name)
            for _, el in ipairs(g:GetDescendants()) do
                if el:IsA("GuiObject") and el.Visible then
                    local nm = el.Name:lower()
                    if nm:find("trade") or nm:find("ready") or nm:find("decline") or nm:find("offer") or nm:find("slot") or nm:find("unit") or nm:find("item") or nm:find("gem") then
                        local textVal = (el:IsA("TextLabel") or el:IsA("TextButton") or el:IsA("TextBox")) and el.Text or ""
                        table.insert(tradeElements, string.format("%s:%s (parent=%s, text=%s)", el.ClassName, el.Name, el.Parent and el.Parent.Name or "", textVal))
                        if #tradeElements >= 25 then break end
                    end
                end
            end
        end
    end

    local data = {
        re = reList,
        rf = rfList,
        features = features,
        tradeModules = tradeModulesInfo,
        allGuis = guiNames,
        tradeElements = tradeElements
    }
    logAgent("Trade System Diagnostik:", data)
end

-- Pasang listener TradeEvent segera saat script mulai
pcall(function()
    local _, TradeRE = getTradeNetwork()
    if TradeRE and TradeRE:FindFirstChild("TradeEvent") then
        TradeRE.TradeEvent.OnClientEvent:Connect(function(...)
            local args = {...}
            logAgent("TradeEvent ClientEvent:", args)
        end)
    end
end)

-- Menangani instruksi trade yang masuk dari dashboard
local function handleTrade(trade)
    logAgent(string.format("Antrean trade diterima: ID %s -> Target: %s (%d units, %d items)", 
        tostring(trade.id), tostring(trade.to), #(trade.units or {}), #(trade.items or {})))

    -- 1. Cari target player di server
    local targetPlayer = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and (p.Name:lower() == trade.to:lower() or (p.DisplayName and p.DisplayName:lower() == trade.to:lower())) then
            targetPlayer = p
            break
        end
    end

    if not targetPlayer then
        warn("[Nimbus] Target player tidak ditemukan di server: " .. tostring(trade.to))
        sendWS({
            type = "trade_result",
            id = trade.id,
            status = "failed",
            error = "Player target (" .. tostring(trade.to) .. ") tidak ada di server ini"
        })
        return
    end

    -- 2. Dapatkan Remote TradeService
    local TradeService, TradeRE, TradeRF = getTradeNetwork()
    if not TradeRE then
        warn("[Nimbus] Remote TradeService.RE tidak ditemukan!")
        sendWS({
            type = "trade_result",
            id = trade.id,
            status = "failed",
            error = "Folder TradeService.RE tidak ditemukan"
        })
        return
    end

    -- 3. Cari remote RequestTrade
    local reqRemote = TradeRE:FindFirstChild("RequestTrade")
    if not reqRemote then
        warn("[Nimbus] Remote RequestTrade tidak ditemukan!")
        sendWS({
            type = "trade_result",
            id = trade.id,
            status = "failed",
            error = "Remote RequestTrade tidak ditemukan"
        })
        return
    end

    -- Kirim permintaan trade ke target
    logAgent("Mengirim trade request in-game ke: " .. targetPlayer.Name)
    pcall(function() reqRemote:FireServer(targetPlayer) end)

    -- 4. Tunggu event TradeEvent:"Started" — ini tanda sesi BENAR-BENAR siap
    --    (bukan hanya RequestSent/Decline notification yang muncul lebih awal)
    local sessionStarted = false
    local sessionEnded = false
    local tradeEventConn

    tradeEventConn = TradeRE.TradeEvent.OnClientEvent:Connect(function(eventName, data)
        if eventName == "Started" then
            sessionStarted = true
        elseif eventName == "Ended" then
            sessionEnded = true
        end
    end)

    logAgent("Menunggu sesi trade terbuka (menunggu TradeEvent Started)...")
    local startTime = tick()
    while not sessionStarted and (tick() - startTime) < 35 do
        task.wait(0.3)
    end

    if not sessionStarted then
        tradeEventConn:Disconnect()
        warn("[Nimbus] Target player tidak menerima trade dalam 35 detik.")
        sendWS({
            type = "trade_result",
            id = trade.id,
            status = "failed",
            error = "Penerima tidak menerima trade dalam 35 detik (pastikan Auto Receive aktif)"
        })
        return
    end

    logAgent("Sesi trade BENAR-BENAR terbuka (Started)! Memulai pengisian units dan items...")
    task.wait(0.5) -- jeda singkat agar server siap menerima ChangeOffer

    -- Cari TradeController jika ada di Framework
    local Framework = ReplicatedStorage:FindFirstChild("Framework")
    local TradeCtrl = nil
    if Framework and Framework:FindFirstChild("Features") then
        local tFeat = Framework.Features:FindFirstChild("Trading") or Framework.Features:FindFirstChild("Trade")
        if tFeat then
            for _, m in ipairs(tFeat:GetDescendants()) do
                if m:IsA("ModuleScript") then
                    local ok, ctrl = pcall(require, m)
                    if ok and type(ctrl) == "table" then
                        TradeCtrl = ctrl
                        break
                    end
                end
            end
        end
    end

    -- Helper pemanggil ChangeOffer
    -- Format CONFIRMED via Cobalt spy: ChangeOffer:FireServer(itemName, amount)
    -- Untuk unit: ChangeOffer:FireServer(unitUID, 1) — UID adalah ID inventori integer
    local function sendChangeOffer(idOrName, amount, isItem)
        local ChangeOffer = TradeRE:FindFirstChild("ChangeOffer")
        if not ChangeOffer then
            warn("[Nimbus] Remote ChangeOffer tidak ditemukan!")
            return
        end

        logAgent(string.format("Mengirim ChangeOffer: %s x%s", tostring(idOrName), tostring(amount)))

        -- Format PERSIS seperti yang dikonfirmasi Cobalt:
        -- Event:FireServer("Luck III", 1)
        pcall(function() ChangeOffer:FireServer(idOrName, amount) end)
        task.wait(0.1)
    end

    -- 5. Masukkan UNITS ke dalam trade
    if trade.units and #trade.units > 0 then
        for _, uid in ipairs(trade.units) do
            logAgent("Memasukkan unit UID: " .. tostring(uid))
            sendChangeOffer(tostring(uid), 1, false)
            task.wait(0.25)
        end
    end

    -- 6. Masukkan ITEMS ke dalam trade
    if trade.items and #trade.items > 0 then
        for _, item in ipairs(trade.items) do
            local itemName = item.name
            local itemQty = tonumber(item.qty) or 1

            logAgent(string.format("Memasukkan item: %s x%d", itemName, itemQty))

            -- Format dikonfirmasi Cobalt: ChangeOffer:FireServer("Luck III", 1)
            sendChangeOffer(itemName, itemQty, true)

            task.wait(0.3)
        end
    end

    task.wait(1.5)

    -- 7. Kunci tawaran / Tekan tombol READY (AdvanceTrade)
    logAgent("Mengunci tawaran (AdvanceTrade -> Ready)...")
    local advRemote = TradeRE:FindFirstChild("AdvanceTrade")
    if advRemote then
        pcall(function() advRemote:FireServer(true) end)
        pcall(function() advRemote:FireServer() end)
    end

    local function clickMatchingButton(candidates)
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
        if not pGui then return false end
        for _, btn in ipairs(pGui:GetDescendants()) do
            if btn:IsA("GuiButton") and btn.Visible then
                local txt = (btn:FindFirstChildWhichIsA("TextLabel") and btn:FindFirstChildWhichIsA("TextLabel").Text:lower()) or btn.Name:lower()
                for _, target in ipairs(candidates) do
                    if txt == target or txt:find(target) then
                        clickGuiButton(btn)
                        return true
                    end
                end
            end
        end
        return false
    end

    clickMatchingButton({"ready"})

    -- 8. Menunggu partner siap, countdown 4-5 detik, lalu otomatis ACCEPT
    logAgent("Menunggu partner siap & countdown selesai...")
    local acceptStartTime = tick()
    while not sessionEnded and (tick() - acceptStartTime) < 25 do
        task.wait(1)
        
        -- Cek dan klik tombol Accept/Confirm jika sudah aktif
        local clickedAccept = clickMatchingButton({"accept", "confirm"})
        if clickedAccept or (tick() - acceptStartTime) >= 4 then
            if advRemote then
                pcall(function() advRemote:FireServer(true) end)
                pcall(function() advRemote:FireServer() end)
            end
        end
    end

    -- 9. Tunggu hingga sesi trade selesai menutup
    task.wait(1.5)
    pcall(function() tradeEventConn:Disconnect() end)
    logAgent("Trade berhasil diselesaikan!")
    
    pcall(syncStats)

    sendWS({
        type = "trade_result",
        id = trade.id,
        status = "done"
    })
end

-- Menangani perintah dari dashboard (server join / hop)
local function handleCommand(command)
    if command.type == "join" and command.serverId then
        print("[Nimbus] Menjalankan perintah server hop ke:", command.serverId)
        TeleportService:TeleportToPlaceInstance(game.PlaceId, command.serverId, LocalPlayer)
    end
end

-- Kirim sinkronisasi data TrackStats ke Nimbus backend
local function syncStats()
    if not DataController or not EntryRegistry then
        DataController, EntryRegistry = resolveControllers()
    end

    if not DataController then
        warn("[Nimbus] DataController belum siap.")
        return
    end

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
        print(string.format("[Nimbus] Sinkronisasi berhasil: %d unit, %d item terkirim ke TrackStats", #units, #items))
    elseif httpRequest then
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
    end
end

-- Memulai Nimbus Agent Client
local function startAgent()
    print("[Nimbus] Menginisialisasi Nimbus Agent di Potassium...")
    DataController, EntryRegistry = resolveControllers()

    if not connectWS then
        warn("[Nimbus] WebSocket tidak didukung di environment ini. Beralih ke HTTP polling.")
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
            warn("[Nimbus] Gagal menghubungi " .. CONFIG.WS_URL .. ". Menghubungkan ulang dalam 5 detik...")
            task.delay(5, connect)
            return
        end

        wsConnection = ws

        -- Handshake pertama ke server Nimbus
        sendWS({
            type = "auth",
            role = "agent",
            token = CONFIG.AGENT_TOKEN,
            account = LocalPlayer.Name,
        })

        ws.OnMessage:Connect(function(raw)
            local okDecode, msg = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if not okDecode or not msg then return end

            if msg.type == "ready" then
                isConnected = true
                print(string.format(">>> [Nimbus] Berhasil terhubung! Akun: %s <<<", LocalPlayer.Name))
                task.spawn(inspectTradeSystem)
                syncStats()
            elseif msg.type == "synced" then
                -- Backend mengonfirmasi unit & item sudah masuk
            elseif msg.type == "trade" then
                task.spawn(handleTrade, msg.trade)
            elseif msg.type == "command" then
                task.spawn(handleCommand, msg.command)
            elseif msg.type == "error" then
                warn("[Nimbus Backend Error]: " .. tostring(msg.message))
            end
        end)

        ws.OnClose:Connect(function()
            isConnected = false
            wsConnection = nil
            print("[Nimbus] Koneksi tertutup. Menghubungkan ulang...")
            task.delay(5, connect)
        end)
    end

    task.spawn(connect)

    -- Auto-Sync berkala ke TrackStats
    task.spawn(function()
        while true do
            task.wait(CONFIG.SYNC_INTERVAL)
            if isConnected then
                syncStats()
            end
        end
    end)
end

startAgent()
