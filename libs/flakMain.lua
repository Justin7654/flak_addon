flakMain = {}

d = require("libs.debugging")
taskService = require("libs.taskService")

--- @param vehicle_id number
--- @return boolean isFlak True if the vehicle has a IS_AI_FLAK sign on it
function flakMain.isVehicleFlak(vehicle_id)
    local _, is_success = server.getVehicleSign(vehicle_id, "IS_AI_FLAK")
    return is_success
end

--- Adds the specified vehicle to the loaded flak list.
--- @param vehicle_id number
function flakMain.addVehicleToLoadedFlak(vehicle_id)
    ---@class FlakData
	---@field vehicle_id number the vehicle_id of the flak vehicle
	---@field tick_id number a random number between 0 and the fire rate for the flak
	---@field lastTargetMatrix SWMatrix the last matrix of the flak target
    ---@field lastTargetTime number the g_savedata counter of the lastTargetMatrix time
    local flakData = {
        vehicle_id = vehicle_id,
        tick_id = math.random(0, time.second*g_savedata.settings.fireRate-1),
		lastTargetMatrix = matrix.translation(0,0,0),
        lastTargetTime = g_savedata.tickCounter
    }
	table.insert(g_savedata.loadedFlak, 1, flakData)
    d.printDebug("Vehicle ",vehicle_id, " registered as flak")
end

--- Checks if the specified vehicle is in the loaded flak list.
--- @Param vehicle_id number the vehicle id to check
function flakMain.vehicleIsInLoadedFlak(vehicle_id)
    for _, flak in pairs(g_savedata.loadedFlak) do
        if flak.vehicle_id == vehicle_id then
            return true
        end
    end
    return false
end

--- Attempts to remove the specified vehicle the loaded flak list.
--- @return boolean is_success True if the vehicle was removed from the list
function flakMain.removeVehicleFromLoadedFlak(vehicle_id)
    for i, flak in pairs(g_savedata.loadedFlak) do
        if flak.vehicle_id == vehicle_id then
            d.printDebug("Vehicle ",vehicle_id, " unregistered as flak")
            table.remove(g_savedata.loadedFlak, i)
            return true
        end
    end
    return false
end

--- Verifys that nothings going wrong with the flak list.
--- @return boolean found_issues True if any issues were found
--- @return number issues_fixed The total amount of issues fixed
function flakMain.verifyFlakList()
    local fixed = 0

    --Check if theres any duplicates
    for i, flak in pairs(g_savedata.loadedFlak) do
        for j, flak2 in pairs(g_savedata.loadedFlak) do
            if i ~= j and flak.vehicle_id == flak2.vehicle_id then
                s.announce("[Flak Sanity Check]", "Duplicate flak vehicle found: "..flak.vehicle_id)
                table.remove(g_savedata.loadedFlak, i)
                fixed = fixed + 1
                break
            end
        end
    end

    --Check if each flak vehicle is simulating
    for i, flak in pairs(g_savedata.loadedFlak) do
        if not server.getVehicleSimulating(flak.vehicle_id) then
            s.announce("[Flak Sanity Check]", "Found flak vehicle that is not simulating: "..flak.vehicle_id)
            table.remove(g_savedata.loadedFlak, i)
            fixed = fixed + 1
        end
    end

    --Show Results
    if fixed > 0 then
        s.announce("[Flak Sanity Check]", "Sanity check complete. "..tostring(fixed).." issues fixed")
        return true, fixed
    end
    
    server.announce("[Flak Sanity Check]", "Sanity check complete. No issues found")
    return false, 0
end

--- @param vehicle_id number the vehicle id to check
--- @return SWMatrix|nil targetMatrix the location the flak is targetting
--- Returns a matrix of the flak vehicles target using its dials. If a dial is not found, it will return a nil
function flakMain.getFlakTarget(vehicle_id)
    local xDial, success1 = s.getVehicleDial(vehicle_id, "FLAK_TARGET_X")
    local yDial, success2 = s.getVehicleDial(vehicle_id, "FLAK_TARGET_Y")
    local zDial, success3 = s.getVehicleDial(vehicle_id, "FLAK_TARGET_Z")
    if success1 and success2 and success3 then
        return matrix.translation(xDial.value, yDial.value, zDial.value)
    else
        configError("Flak vehicle "..vehicle_id.." does not have all the required dials")
        flakMain.removeVehicleFromLoadedFlak(vehicle_id)
        return nil
    end
end

--- Calculate the time it will take for the flak to reach the target
--- @param targetMatrix SWMatrix the matrix of the target
--- @param flakMatrix SWMatrix the matrix of the flak vehicle
--- @return number travelTime the time in ticks it will take for the flak to reach the target
function flakMain.calculateTravelTime(targetMatrix, flakMatrix)
    local distance = matrix.distance(targetMatrix, flakMatrix)
    local speed = g_savedata.settings.flakShellSpeed/time.second --The speed in m/s
    local travelTime = math.floor(distance/speed)
    d.printDebug("Travel time is ",travelTime, "ticks (",travelTime/60," seconds) because seperation is ",distance,"m and the speed is ",g_savedata.settings.flakShellSpeed,"m/s"..
        " (",speed,"m/tick)")
    return travelTime
end

--- Calculate the position the flak should aim at to hit the target, accounting for t
--- @param flakMatrix SWMatrix the matrix of the flak vehicle
--- @param targetMatrix SWMatrix the matrix of the target
--- @param lastTargetMatrix SWMatrix the last matrix of the flak target, used to calculate velocity and acceleration for the target
--- @param timeBetween number the amount of time in ticks between when the current target position was taken and the last target matrix was taken
function flakMain.calculateLead(flakMatrix, targetMatrix, lastTargetMatrix, timeBetween)
    local travelTime = flakMain.calculateTravelTime(targetMatrix, flakMatrix) --Travel time in ticks

    --Calculate the velocity of the target
    local x1, y1, z1 = matrix.position(targetMatrix)
    local x2, y2, z2 = matrix.position(lastTargetMatrix)
    local vx = x1 - x2
    local vy = y1 - y2
    local vz = z1 - z2

    --Have velocity account for the timeBetween
    vx = vx/timeBetween
    vy = vy/timeBetween
    vz = vz/timeBetween

    -- Move the targetMatrix using the bullets travelTime and target velocity
    x3,y3,z3 = matrix.position(targetMatrix)
    x = x1 + vx * travelTime
    y = y1 + vy * travelTime
    z = z1 + vz * travelTime

    d.debugLabel("lead", targetMatrix, "Target", travelTime)
    d.debugLabel("lead", lastTargetMatrix, "Last Target", travelTime)
    d.debugLabel("lead", matrix.translation(x,y,z), "Lead", travelTime)
    return matrix.translation(x, y, z)
    
    --[[
    --Calculate the delta between the target matrix and the last target matrix
    local x1, y1, z1 = matrix.position(targetMatrix)
    local x2, y2, z2 = matrix.position(lastTargetMatrix)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    -- Move the targetMatrix forward by the delta times the travel time
    local x, y, z = matrix.position(targetMatrix)
    x = x + dx * travelTime
    y = y + dy * travelTime
    z = z + dz * travelTime
    return matrix.translation(x, y, z)
    --]]
end

--[[
Fire: Calculate the accuracy and travel time, then add to queue for the calculated arrival tick to make a explosion at a specified point using a detonateFlak function
using the spawnExplosion code from here


]]

--- Generates a flak explosion nearby the given matrix.
--- @param sourceMatrix SWMatrix the position of the gun thats firing
--- @param targetMatrix SWMatrix the matrix to generate the explosion at
function flakMain.fireFlak(sourceMatrix, targetMatrix) --Convert to using flakObject
    local x,alt,z = matrix.position(targetMatrix)
    local currentWeather = s.getWeather(targetMatrix)
    d.printDebug("Firing at ",x,",",alt,",",z)

    --Calculate if its too high
    if alt < g_savedata.settings.minAlt then
        d.printDebug("Target is too low to fire at")
        return
    end

    --Calculate the weather multiplier, bad weather will multiply the existing penaltys
    local weatherMultiplier = 1
    if not g_savedata.settings.ignoreWeather then
        weatherMultiplier = weatherMultiplier + currentWeather.fog/2
        weatherMultiplier = weatherMultiplier + currentWeather.wind/2
        weatherMultiplier = weatherMultiplier + (currentWeather.rain + currentWeather.snow)/10
    end

    --Calculate the night multiplier
    
    --Calculate accuracy
    local spread = 0
    local altFactor = 10/(0.5 ^ (alt/250)) --10+(0.2*alt)
    d.printDebug("Alt factor: ",altFactor)
    local spread = altFactor
    local spread = spread * weatherMultiplier
    
    --Randomize the targetMatrix based on spread
    spread = math.floor(spread)
    d.printDebug("Spread is ",spread)
    x = x + math.random(-spread, spread)
    alt = alt + math.random(-spread, spread)
    z = z + math.random(-spread, spread)
    local resultMatrix = matrix.translation(x,alt, z)

    --Randomize travel time alittle
    local travelTime = flakMain.calculateTravelTime(targetMatrix, sourceMatrix)
    travelTime = travelTime + math.random() * 3 -- 0-3 seconds ahead
    
    --Spawn the explosion
    --- @class ExplosionData
    thisExplosionData = {
        position = resultMatrix,
        magnitude = math.random()/8
    }
    --[[if g_savedata.queuedExplosions[g_savedata.tickCounter + travelTime] == nil then
        g_savedata.queuedExplosions[g_savedata.tickCounter + travelTime] = {}
    end
    table.insert(g_savedata.queuedExplosions[g_savedata.tickCounter + travelTime], 1, thisExplosionData)]]
    TaskService:AddTask(flakMain.flakExplosion, travelTime, {thisExplosionData})
end

function flakMain.flakExplosion(explosionData)
    d.printDebug("Running!")
    magnitude = explosionData.magnitude
    position = explosionData.position
    d.printDebug("Explosion is at ",s.getTile(position).name," as magnitude ",magnitude)
    s.spawnExplosion(position, magnitude)
end

return flakMain