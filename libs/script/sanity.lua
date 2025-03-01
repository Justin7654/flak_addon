-- Attempts to fix critical issues with the addons current data
local sanity = {}

local function printMessage(msg)
    s.announce("[Flak Sanity Checker]", msg)
end

function sanity.verifyFlakList()
    local fixed = 0
    --Check for duplicates
    for i, flak in pairs(g_savedata.spawnedFlak) do
        for j, flak2 in pairs(g_savedata.spawnedFlak) do
            if i ~= j and flak.vehicle_id == flak2.vehicle_id then
                printMessage("Duplicate flak vehicle found: "..flak.vehicle_id)
                table.remove(g_savedata.spawnedFlak, i)
                fixed = fixed + 1
                break
            end
        end
    end
    return fixed
end

function sanity.verifyLoadedVehicles()
    local fixed = 0
    --Check for duplicates
    for i, vehicle in pairs(g_savedata.loadedVehicles) do
        for j, vehicle2 in pairs(g_savedata.loadedVehicles) do
            if i ~= j and vehicle == vehicle2 then
                printMessage("Duplicate loaded vehicle found: "..vehicle)
                table.remove(g_savedata.loadedVehicles, i)
                fixed = fixed + 1
                break
            end
        end
    end
    --Check for vehicles that dont exist
    for i, vehicle_id in pairs(g_savedata.loadedVehicles) do
        _, success = s.getVehicleSimulating(vehicle_id)
        if not success then
            printMessage("Non-existant loaded vehicle entry found: "..vehicle_id)
            table.remove(g_savedata.loadedVehicles, i)
            fixed = fixed + 1
        end
    end
    --Make sure all loaded vehicles have vehicle info
    for i, vehicle_id in pairs(g_savedata.loadedVehicles) do
        if not g_savedata.vehicleInfo[vehicle_id] then
            printMessage("Loaded vehicle missing vehicle info: "..vehicle_id)
        end
    end
end

function sanity.checkAll()
    local fixed = 0
    fixed = fixed + sanity.verifyFlakList()
    fixed = fixed + sanity.verifyLoadedVehicles()
    printMessage("Sanity check complete. "..fixed.." issues fixed.")
end

function sanity.idleCheck()
    local RATE = time.minute --Amount of time between each scan
    local SPACER = time.second --Time between each individual type of check once the checks start
    local CHECKS = {sanity.verifyFlakList, sanity.verifyLoadedVehicles}
    for index,func in ipairs(CHECKS) do
        if isTickID(index*SPACER, RATE) then
            func()
        end
    end
end

--Addon startup checks

return sanity