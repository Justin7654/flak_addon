--[[
This library finds a more accurate bounding box for vehicles by running voxel scans on them over time
--]]

---@class vehicleBoundsScanState
---@field vehicle_id integer the id of the vehicle being scanned
---@field paused boolean whether the scan is paused
---@field center_voxel table<number> the center voxel coordinates {x,y,z} from which to scan
---@field scan_id integer unique identifier for this scan
---@field start_tick integer the tick when the scan started
---@field current_radius integer the current radius being scanned
---@field best_sqdist number the best squared distance found so far
---@field best_bounds obb the best bounding box found so far (OBB in voxel space)
---@field has_any boolean whether any voxels have been found yet
---@field minVX integer the minimum X voxel offset found so far
---@field minVY integer the minimum Y voxel offset found so far
---@field minVZ integer the minimum Z voxel offset found so far
---@field maxVX integer the maximum X voxel offset found so far
---@field maxVY integer the maximum Y voxel offset found so far
---@field maxVZ integer the maximum Z voxel offset found so far
---@field face_idx integer which face is currently being scanned (1..6)
---@field face_u integer the current U iterator on the face (range -r..r)
---@field face_v integer the current V iterator on the face (range -r..r)
---@field min_radius integer the minimum radius to scan to
---@field last_successful_radius integer the last radius where we found any voxels. Used for knowing when to end

local boundsScanner = {}
local MAX_BUDGET = 999999
local BUDGET = -1
local tickIndex = 1

d = require("libs.script.debugging")
shrapnel = require("libs.shrapnel")

function boundsScanner.tick()
    -- Calculate budget if not set
    if BUDGET < 0 then
        BUDGET = math.max(boundsScanner.calculateBudgetTime(g_savedata.settings.scanningBudget), 100)
        return
    end

    -- Get the current scan to process
    local allScans = g_savedata.vehicleBoundScans
    local totalScans = #allScans

    if #allScans == 0 then return end
    if tickIndex > totalScans then tickIndex = 1 end

    local attempts = 0
    while allScans[tickIndex] and allScans[tickIndex].paused == true do
        --Skip vehicles that are not simulating
        tickIndex = tickIndex + 1
        attempts = attempts + 1
        if tickIndex > totalScans then tickIndex = 1 end
        if attempts >= totalScans then
            return --Theres nothing to scan currrently, everythings unloaded
        end
    end
    local chosenScan = allScans[tickIndex]
    tickIndex = tickIndex + 1

    -- Initialize/resume scan state
    local center_x, center_y, center_z = chosenScan.center_voxel[1], chosenScan.center_voxel[2], chosenScan.center_voxel[3]
    local radius = chosenScan.current_radius or 0
    local face_idx = chosenScan.face_idx or 1
    local u = chosenScan.face_u or -radius
    local v = chosenScan.face_v or -radius
    local last_successful_radius = chosenScan.last_successful_radius or 0

    -- Decide a maximum radius in voxels using collider_data.radius (meters) if available
    local min_radius = chosenScan.min_radius or 5

    -- Track best bounds in voxel space relative to center
    local has_any = chosenScan.has_any or false
    local minVX = chosenScan.minVX or 0
    local minVY = chosenScan.minVY or 0
    local minVZ = chosenScan.minVZ or 0
    local maxVX = chosenScan.maxVX or 0
    local maxVY = chosenScan.maxVY or 0
    local maxVZ = chosenScan.maxVZ or 0
    local best_sqdist = chosenScan.best_sqdist or 0

    local remaining = BUDGET
    local complete = false

    -- Helper to update best bounds when a voxel is found at offset (dx,dy,dz)
    local function on_hit(ix, iy, iz)
        local d2 = ix*ix + iy*iy + iz*iz
        if not has_any then
            has_any = true
            minVX, minVY, minVZ = ix, iy, iz
            maxVX, maxVY, maxVZ = ix, iy, iz
            best_sqdist = d2
        else
            if ix < minVX then minVX = ix end
            if iy < minVY then minVY = iy end
            if iz < minVZ then minVZ = iz end
            if ix > maxVX then maxVX = ix end
            if iy > maxVY then maxVY = iy end
            if iz > maxVZ then maxVZ = iz end
            if d2 > best_sqdist then best_sqdist = d2 end
        end
        last_successful_radius = radius
    end

    -- Compute offsets for a given face (1..6): +X, -X, +Y, -Y, +Z, -Z
    --- @param face integer which face to use (1..6)
    --- @param r integer Current radius from the center voxel
    --- @param uu integer U coordinate on the face
    --- @param vv integer V coordinate on the face
    --- @return integer OffsetX
    --- @return integer OffsetY
    --- @return integer OffsetZ
    local function face_offsets(face, r, uu, vv)
        if face == 1 then return  r, uu, vv
        elseif face == 2 then return -r, uu, vv
        elseif face == 3 then return  uu,  r, vv
        elseif face == 4 then return  uu, -r, vv
        elseif face == 5 then return  uu, vv,  r
        else                 return  uu, vv, -r end
    end

    -- Budgeted scanning (face-only): iterate center, then per-face grid at current radius
    while remaining > 0 do
        if radius == 0 then
            if shrapnel.checkVoxelExists(chosenScan.vehicle_id, center_x, center_y, center_z) then
                on_hit(0,0,0)
                best_sqdist = 0.25 --on_hit sets it to 0 causing issues in future systems
            end
            remaining = remaining - 1
            radius = 1
            u, v = -radius, -radius
            face_idx = 1
        else
            -- Stop scanning if completed
            if (radius-last_successful_radius) > 2 and radius > min_radius then
                complete = true
                break
            end

            -- Skip invalid iterators (in case radius changed)
            if u < -radius or u > radius then u = -radius end
            if v < -radius or v > radius then v = -radius end

            -- Scan current face point
            local ox, oy, oz = face_offsets(face_idx, radius, u, v)
            local vx = center_x + ox
            local vy = center_y + oy
            local vz = center_z + oz
            if shrapnel.checkVoxelExists(chosenScan.vehicle_id, vx, vy, vz) then
                on_hit(ox, oy, oz)
                if false and g_savedata.debug.scan then
                    local real_pos = s.getVehiclePos(chosenScan.vehicle_id, vx, vy, vz)
                    d.debugLabel("scan", real_pos, "Scan Hit", 40)
                end
            end
            remaining = remaining - 1

            -- Advance u,v then face, then radius
            v = v + 1
            if v > radius then
                v = -radius
                u = u + 1
                if u > radius then
                    u = -radius
                    face_idx = face_idx + 1
                    if face_idx > 6 then
                        face_idx = 1
                        radius = radius + 1
                        u, v = -radius, -radius
                    end
                end
            end
        end
    end

    -- Persist scan state
    chosenScan.current_radius = radius
    chosenScan.face_idx = face_idx
    chosenScan.face_u = u
    chosenScan.face_v = v
    chosenScan.has_any = has_any
    chosenScan.minVX = minVX
    chosenScan.minVY = minVY
    chosenScan.minVZ = minVZ
    chosenScan.maxVX = maxVX
    chosenScan.maxVY = maxVY
    chosenScan.maxVZ = maxVZ
    chosenScan.best_sqdist = best_sqdist
    chosenScan.best_bounds = has_any and {minX=minVX/4, minY=minVY/4, minZ=minVZ/4, maxX=maxVX/4, maxY=maxVY/4, maxZ=maxVZ/4} or chosenScan.best_bounds
    chosenScan.last_successful_radius = last_successful_radius

    -- If complete
    if complete then
        g_savedata.vehicleInfo[chosenScan.vehicle_id].collider_data.obb_bounds = chosenScan.best_bounds
        g_savedata.vehicleInfo[chosenScan.vehicle_id].collider_data.radius = math.sqrt(best_sqdist) * 0.25
        boundsScanner.stopScanForVehicle(chosenScan.vehicle_id)
        d.printDebug("Bounds Scanner completed scan for vehicle ",chosenScan.vehicle_id," after reaching radius ",chosenScan.current_radius)
    end
end

-------------------------------
--- Vehicle Scan Management ---
-------------------------------

function boundsScanner.startScanForVehicle(vehicle_id)
    --Calculate the center voxel using s.getVehiclePos
    local vehicle_pos, success = s.getVehiclePos(vehicle_id)
    if not success then 
        d.printWarning("Failed to get vehicle pos for ",vehicle_id,"... startScanForVehicle failed!")
        return
    end
    local vehicle_x, vehicle_y, vehicle_z = vehicle_pos[13], vehicle_pos[14], vehicle_pos[15]
    local voxel_success, voxel_x, voxel_y, voxel_z = shrapnel.getVehicleVoxelAtWorldPosition(vehicle_id, vehicle_x, vehicle_y, vehicle_z)
    if not voxel_success then
        d.printWarning("Failed to get vehicle voxel for ",vehicle_id,"... startScanForVehicle failed!")
        return
    end
    d.printDebug("Starting bounds scan for vehicle ",vehicle_id," at voxel (",voxel_x,",",voxel_y,",",voxel_z,")")
    --Add the scan to the list
    g_savedata.scanCurrentID = g_savedata.scanCurrentID + 1
    table.insert(g_savedata.vehicleBoundScans, {
        vehicle_id = vehicle_id,
        paused = false,
        center_voxel = {voxel_x, voxel_y, voxel_z},
        scan_id = math.floor(g_savedata.scanCurrentID),
        start_tick = g_savedata.tickCounter,
        last_successful_radius = 0
    })
end

--- Pauses the scan for the given vehicle
--- @param vehicle_id integer the id of the vehicle to pause the scan for
--- @return boolean success returns true if it found the vehicle
function boundsScanner.pauseScanForVehicle(vehicle_id)
    local allScans = g_savedata.vehicleBoundScans
    for _, scan in ipairs(allScans) do
        if scan.vehicle_id == vehicle_id then
            scan.paused = true
            return true
        end
    end
    return false
end

--- Resumes the scan for the given vehicle
--- @param vehicle_id integer the id of the vehicle to resume the scan for
--- @return boolean success returns true if it found the vehicle
function boundsScanner.resumeScanForVehicle(vehicle_id)
    local allScans = g_savedata.vehicleBoundScans
    for _, scan in ipairs(allScans) do
        if scan.vehicle_id == vehicle_id then
            scan.paused = false
            return true
        end
    end
    return false
end

--- Cancels the scan for the given vehicle
--- @param vehicle_id integer the id of the vehicle to cancel the scan for
--- @return boolean success returns true if it successfully canceled the scan
function boundsScanner.stopScanForVehicle(vehicle_id)
    local allScans = g_savedata.vehicleBoundScans
    for i, scan in ipairs(allScans) do
        if scan.vehicle_id == vehicle_id then
            table.remove(allScans, i)
            return true
        end
    end
    return false
end

--- Gets the scanning status for the given vehicle
--- @param vehicle_id integer the id of the vehicle to check
--- @return boolean is_scanning returns true if the vehicle is currently being scanned
--- @return boolean is_paused returns true if the scan is currently paused
function boundsScanner.isScanningVehicle(vehicle_id)
    local allScans = g_savedata.vehicleBoundScans
    for _, scan in ipairs(allScans) do
        if scan.vehicle_id == vehicle_id then
            return true, scan.paused
        end
    end
    return false, false
end

--- Dynamically adjust the budget based on a target time per tick and the computers speed
--- @param time_per_tick number the target time per tick in milliseconds
--- @return number budget the calculated budget
function boundsScanner.calculateBudgetTime(time_per_tick)
    if #g_savedata.loadedVehicles == 0 then
        return 0
    end
    -- Test how long it takes for s.addDamage to run
    local targetVehicle = g_savedata.loadedVehicles[1]
    local start_time = s.getTimeMillisec()
    local time_passed = 0
    local total_calls = 0
    local CALLS_PER_ITER = 1000
    while time_passed < 15 do
        for i=1, CALLS_PER_ITER do
            shrapnel.checkVoxelExists(targetVehicle, 0, 0, 0)
        end
        total_calls = total_calls + CALLS_PER_ITER
        time_passed = s.getTimeMillisec() - start_time
    end
    local time_per_call = time_passed / total_calls
    -- Calculate the amount of calls that we can do within the target time per tick
    local overhead_divisor = 3 --Account for overhead of everything else it does
    local calls_per_tick = math.floor((time_per_tick / time_per_call) / overhead_divisor)
    local calls_per_tick_limited = math.min(calls_per_tick, MAX_BUDGET)
    d.printDebug("Calculated bounds scanner budget: ",calls_per_tick_limited," calls per tick (",time_per_call,"ms per call, ",time_passed,"ms spent testing)")
    return calls_per_tick_limited
end

function boundsScanner.setBudget(new_budget)
    BUDGET = new_budget
end

function boundsScanner.getTickIndex()
    return tickIndex
end

return boundsScanner