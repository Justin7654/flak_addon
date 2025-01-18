flakMain = {}

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
    local flakData = {
        vehicle_id = vehicle_id,
        tick_id = math.random(0, time.second*g_savedata.settings.fireRate-1),
		lastTargetMatrix = matrix.translation(0,0,0)
    }
	table.insert(g_savedata.loadedFlak, 1, flakData)
    printDebug("Vehicle ",vehicle_id, " registered as flak")
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
            printDebug("Vehicle ",vehicle_id, " unregistered as flak")
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

function flakMain.calculateTravelTime(targetMatrix, flakMatrix)
    local distance = matrix.distance(targetMatrix, flakMatrix)
    local speed = 300
    return distance/speed
end

--[[
Fire: Calculate the accuracy and travel time, then add to queue for the calculated arrival tick to make a explosion at a specified point using a detonateFlak function
using the spawnExplosion code from here


]]

--- Generates a flak explosion nearby the given matrix.
--- @param targetMatrix SWMatrix the matrix to generate the explosion at
function flakMain.fireFlak(targetMatrix) --Convert to using flakObject
    local x,alt,z = matrix.position(targetMatrix)
    local currentWeather = s.getWeather(targetMatrix)
    printDebug("Firing at ",x,",",alt,",",z)

    --Calculate if its too high
    if alt < g_savedata.settings.minAlt then
        printDebug("Target is too low to fire at")
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
    local altFactor = 10/(0.5 ^ (x/250)) --10+(0.2*alt) 
    printDebug("Altitude Spread: ",altFactor)
    local spread = altFactor
    printDebug("Total Spread: ",spread)
    local spread = spread * weatherMultiplier
    printDebug("Spread after multipliers: ",spread)
    
    --Randomize the targetMatrix based on spread
    spread = math.floor(spread)
    x = x + math.random(-spread, spread)
    alt = alt + math.random(-spread, spread)
    z = z + math.random(-spread, spread)
    local resultMatrix = matrix.translation(x,alt, z)

    --Spawn the explosion
    magnitude = math.random()/8
    printDebug("Explosion is at ",s.getTile(resultMatrix).name," as magnitude ",magnitude)
    s.spawnExplosion(resultMatrix, magnitude)
end

return flakMain