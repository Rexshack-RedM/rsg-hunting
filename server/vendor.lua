local RSGCore = exports['rsg-core']:GetCoreObject()
local stockFile = 'vendor_stock.json'
local stockData = {}
lib.locale()

-- itemName -> item config, built once instead of scanning every vendor's
-- item list on every single buy/sell call
local ItemConfigLookup = {}

CreateThread(function()
    for _, vendor in ipairs(Config.Vendors) do
        for _, item in ipairs(vendor.items) do
            ItemConfigLookup[item.name] = item
        end
    end
end)

local function LoadStock()
    local file = LoadResourceFile(GetCurrentResourceName(), stockFile)
    if file then
        stockData = json.decode(file) or {}
    else
        stockData = {}
        for _, vendor in ipairs(Config.Vendors) do
            for _, item in ipairs(vendor.items) do
                if item.canBuy then
                    stockData[item.name] = item.initialStock or 10
                end
            end
        end
        SaveResourceFile(GetCurrentResourceName(), stockFile, json.encode(stockData), -1)
    end
end

local function SaveStock()
    SaveResourceFile(GetCurrentResourceName(), stockFile, json.encode(stockData), -1)
end

CreateThread(function()
    Wait(1000)
    LoadStock()
end)

lib.callback.register('rsg-hunting:server:getStock', function()
    return stockData
end)

--------------------------------------
-- anti-spam: throttle buy/sell so a macro can't fire the events faster
-- than the UI could ever produce them
--------------------------------------
local PlayerCooldowns = {}
local TRADE_COOLDOWN = 500 -- ms
local MAX_TRADE_AMOUNT = 500

local function isOnCooldown(src)
    local now = GetGameTimer()
    local last = PlayerCooldowns[src]
    if last and (now - last) < TRADE_COOLDOWN then
        return true
    end
    PlayerCooldowns[src] = now
    return false
end

-- amount must be a whole, positive number within sane bounds
local function isValidAmount(amount)
    return type(amount) == 'number'
        and amount > 0
        and amount <= MAX_TRADE_AMOUNT
        and amount % 1 == 0
end

RegisterNetEvent('rsg-hunting:server:buyItem', function(itemName, amount)
    local src = source
    if type(itemName) ~= 'string' or not isValidAmount(amount) then return end
    if isOnCooldown(src) then return end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local itemConfig = ItemConfigLookup[itemName]
    if not itemConfig or not itemConfig.canBuy then return end

    local currentStock = stockData[itemName] or 0
    if currentStock < amount then
        TriggerClientEvent('ox_lib:notify', src, { title = locale('vendor'), description = locale('not_enough_stock'), type = 'error' })
        return
    end

    local totalPrice = itemConfig.buyPrice * amount
    local cash = Player.Functions.GetMoney('cash')

    if cash < totalPrice then
        TriggerClientEvent('ox_lib:notify', src, { title = locale('vendor'), description = locale('not_enough_cash'), type = 'error' })
        return
    end

    if not Player.Functions.RemoveMoney('cash', totalPrice, 'vendor-purchase') then
        return
    end

    Player.Functions.AddItem(itemName, amount)
    stockData[itemName] = currentStock - amount
    SaveStock()

    TriggerClientEvent('ox_lib:notify', src, { title = locale('vendor'), description = locale('bought_item', amount, itemConfig.label, totalPrice), type = 'success' })
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[itemName], 'add', amount)
end)

RegisterNetEvent('rsg-hunting:server:sellItem', function(itemName, amount)
    local src = source
    if type(itemName) ~= 'string' or not isValidAmount(amount) then return end
    if isOnCooldown(src) then return end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local itemConfig = ItemConfigLookup[itemName]
    if not itemConfig or not itemConfig.canSell then return end

    local playerItem = Player.Functions.GetItemByName(itemName)
    if not playerItem or playerItem.amount < amount then
        TriggerClientEvent('ox_lib:notify', src, { title = locale('vendor'), description = locale('not_enough_items'), type = 'error' })
        return
    end

    local currentStock = stockData[itemName] or 0
    local dynamicPrice = itemConfig.sellPrice

    -- Increase sell price when stock is low (vendor pays more for items they need)
    if itemConfig.stockBasedPrice then
        local stockRatio = currentStock / (itemConfig.maxStock or 50)
        if stockRatio < 0.25 then
            dynamicPrice = dynamicPrice * 1.5
        elseif stockRatio < 0.5 then
            dynamicPrice = dynamicPrice * 1.25
        end
    end

    -- Round to the nearest whole dollar with a $1 floor. Server-side money
    -- functions store cash as integers, so a fractional totalPrice (most
    -- sell prices are well under $1) was being truncated to $0 - letting
    -- players hand in items and get paid nothing. This guarantees every
    -- sale pays out at least $1.
    local totalPrice = math.max(1, math.floor((dynamicPrice * amount) + 0.5))

    if not Player.Functions.RemoveItem(itemName, amount) then
        return
    end

    Player.Functions.AddMoney('cash', totalPrice, 'vendor-sale')
    stockData[itemName] = currentStock + amount
    SaveStock()

    TriggerClientEvent('ox_lib:notify', src, { title = locale('vendor'), description = locale('sold_item', amount, itemConfig.label, totalPrice), type = 'success' })
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[itemName], 'remove', amount)
end)

RegisterCommand('resetvendorstock', function(src)
    if src ~= 0 then return end

    for _, vendor in ipairs(Config.Vendors) do
        for _, item in ipairs(vendor.items) do
            if item.canBuy then
                stockData[item.name] = item.initialStock or 10
            end
        end
    end
    SaveStock()
    print('[rsg-hunting] Vendor stock reset to initial values')
end, false)

--------------------------------------
-- cleanup on player disconnect
--------------------------------------
AddEventHandler('playerDropped', function()
    PlayerCooldowns[source] = nil
end)
