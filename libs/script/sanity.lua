-- Attempts to fix critical issues with the addons current data
local sanity = {}

local function printMessage(msg)
    s.announce("[Flak Sanity Checker]", msg)
end

---@return number TotalIssues
---@return number TotalFixed
function sanity.verifyFlakList()
    local notFixed = 0
    local fixed = 0
    --Check for duplicates
    for i, flak in pairs(g_savedata.spawnedFlak) do
        for j, flak2 in pairs(g_savedata.spawnedFlak) do
            if i ~= j and flak.vehicle_id == flak2.vehicle_id then
                printMessage("Duplicate flak vehicle found: "..flak.vehicle_id)
                table.remove(g_savedata.spawnedFlak, i)
                issues = issues + 1
                fixed = fixed + 1
                break
            end
        end
    end
    return notFixed+fixed, fixed
end

---@return number TotalIssues
---@return number TotalFixed
function sanity.verifyLoadedVehicles()
    local notFixed = 0
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
            notFixed = notFixed + 1
        end
    end
    return notFixed+fixed, fixed
end

local CHECKS = {sanity.verifyFlakList, sanity.verifyLoadedVehicles}
function sanity.checkAll()
    local issues = 0
    local fixed = 0
    for i,func in ipairs(CHECKS) do
        local thisNotFixed, thisFixed = func()
        issues = issues + thisNotFixed
        fixed = fixed + thisFixed
    end
    if fixed > 0 or issues > 0 then
        printMessage("Sanity check complete. "..fixed.." issues fixed. "..issues.." issues remain.")
    else
        printMessage("Sanity check complete. No issues were found.")
    end
end

function sanity.idleCheck()
    local RATE = time.second*30 --Amount of time between each scan
    local SPACER = time.second --Time between each individual type of check once the checks start
    for index,func in ipairs(CHECKS) do
        if isTickID(index*SPACER, RATE) then
            func()
        end
    end
end

--Addon startup checks

return sanity