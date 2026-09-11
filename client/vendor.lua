local RSGCore = exports['rsg-core']:GetCoreObject()
local vendorPeds = {}
lib.locale()

CreateThread(function()
    for _, vendor in ipairs(Config.Vendors) do
        local model = GetHashKey(vendor.pedModel)
        RequestModel(model)
        local timeout = 0
        while not HasModelLoaded(model) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end

        if not HasModelLoaded(model) then
            print(('[rsg-hunting] vendor: failed to load ped model "%s", skipping vendor "%s"'):format(tostring(vendor.pedModel), tostring(vendor.blipname or vendor.pedModel)))
            goto continue
        end

        local ped = CreatePed(model, vendor.coords.x, vendor.coords.y, vendor.coords.z - 1.0, vendor.coords.w, false, false)
        SetRandomOutfitVariation(ped, true)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        TaskStandStill(ped, -1)

        vendorPeds[#vendorPeds + 1] = ped

        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'vendor_shop',
                label = locale('open_shop'),
                icon = 'fa-solid fa-store',
                distance = 2.0,
                onSelect = function()
                    OpenVendorMenu(vendor.items)
                end
            },
            {
                name = 'vendor_sell',
                label = locale('sell_items'),
                icon = 'fa-solid fa-hand-holding-dollar',
                distance = 2.0,
                onSelect = function()
                    OpenSellMenu(vendor.items)
                end
            }
        })

        ::continue::
    end
end)

function OpenVendorMenu(vendorItems)
    local stockData = lib.callback.await('rsg-hunting:server:getStock', false)
    local options = {}

    for _, item in ipairs(vendorItems) do
        if item.canBuy then
            local stock = stockData[item.name] or 0
            table.insert(options, {
                title = item.label,
                description = locale('price_stock', item.buyPrice, stock),
                icon = 'nui://' .. Config.Image .. item.name .. '.png',
                disabled = stock <= 0,
                onSelect = function()
                    local input = lib.inputDialog(locale('buy_title', item.label), {
                        { type = 'number', label = locale('amount'), default = 1, min = 1, max = stock }
                    })
                    if input then
                        TriggerServerEvent('rsg-hunting:server:buyItem', item.name, input[1])
                    end
                end
            })
        end
    end

    lib.registerContext({
        id = 'vendor_shop_menu',
        title = locale('vendor_shop_title'),
        options = options
    })
    lib.showContext('vendor_shop_menu')
end

function OpenSellMenu(vendorItems)
    local PlayerData = RSGCore.Functions.GetPlayerData()
    local inventory = PlayerData.items or {}
    local options = {}

    for _, invItem in pairs(inventory) do
        if invItem then
            for _, vendorItem in ipairs(vendorItems) do
                if vendorItem.name == invItem.name and vendorItem.canSell then
                    table.insert(options, {
                        title = invItem.label,
                        description = locale('sell_price_inv', vendorItem.sellPrice, invItem.amount),
                        icon = invItem.image and ('nui://' .. Config.Image .. invItem.image) or 'fa-solid fa-box',
                        onSelect = function()
                            local input = lib.inputDialog(locale('sell_title', invItem.label), {
                                { type = 'number', label = locale('amount'), default = 1, min = 1, max = invItem.amount }
                            })
                            if input then
                                TriggerServerEvent('rsg-hunting:server:sellItem', invItem.name, input[1])
                            end
                        end
                    })
                    break
                end
            end
        end
    end

    if #options == 0 then
        lib.notify({ title = locale('vendor'), description = locale('no_items_to_sell'), type = 'inform' })
        return
    end

    lib.registerContext({
        id = 'vendor_sell_menu',
        title = locale('vendor_sell_title'),
        options = options
    })
    lib.showContext('vendor_sell_menu')
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        for _, ped in ipairs(vendorPeds) do
            DeleteEntity(ped)
        end
    end
end)
