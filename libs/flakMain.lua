flakMain = {}

d = require("libs.debugging")
taskService = require("libs.taskService")
shrapnel = require("libs.shrapnel")

--- @param vehicle_id number
--- @return boolean isFlak True if the vehicle has a IS_AI_FLAK sign on it
function flakMain.isVehicleFlak(vehicle_id)
    local vehicle_data, is_success = s.getVehicleData(vehicle_id)
    if is_success then
	    local hasTag = util.hasTag(vehicle_data.tags, "is_ai_flak")
        return hasTag
    end
    return false
    --local _, is_success = server.getVehicleSign(vehicle_id, "IS_AI_FLAK")
    --return is_success
end

--- Adds the specified vehicle to the loaded flak list.
--- @param vehicle_id number
function flakMain.addVehicleToSpawnedFlak(vehicle_id)
    local flak_pos, pos_success = s.getVehiclePos(vehicle_id)
    if not pos_success then
        d.printError("Could not get position of flak vehicle ",vehicle_id)
        return
    end

    ---@class FlakData
	---@field vehicle_id number the vehicle_id of the flak vehicle
	---@field tick_id number a random number between 0 and the fire rate for the flak
    ---@field simulating boolean if the flak vehicle is currently simulating
    ---@field position SWMatrix the position of the flak vehicle at the time of spawn
    ---@field pseudoTrackingPlayer number|nil the player id the flak is tracking if its unloaded
    ---@field targetPositionData RecentPositionData the recent position data of the flak target
    local flakData = {
        vehicle_id = vehicle_id,
        tick_id = math.random(0, time.second*g_savedata.settings.fireRate-1),
        simulating = false,
        position = flak_pos,
        pseudoTrackingPlayer = nil,
        targetPositionData = {}
    }
	table.insert(g_savedata.spawnedFlak, flakData)
    d.printDebug("Vehicle ",vehicle_id, " registered as flak")
end

--- Checks if the specified vehicle is in the loaded flak list.
--- @Param vehicle_id number the vehicle id to check
--- @return boolean isFlak True if the vehicle is in the list
--- @return FlakData|nil flakData The flak data of the vehicle if it was found
function flakMain.vehicleIsInSpawnedFlak(vehicle_id)
    for _, flak in pairs(g_savedata.spawnedFlak) do
        if flak.vehicle_id == vehicle_id then
            return true, flak
        end
    end
    return false, nil
end

--- Attempts to remove the specified vehicle the loaded flak list.
--- @return boolean is_success True if the vehicle was removed from the list
function flakMain.removeVehicleFromFlak(vehicle_id)
    for i, flak in pairs(g_savedata.spawnedFlak) do
        if flak.vehicle_id == vehicle_id then
            d.printDebug("Vehicle ",vehicle_id, " unregistered as flak")
            table.remove(g_savedata.spawnedFlak, i)
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
    for i, flak in pairs(g_savedata.spawnedFlak) do
        for j, flak2 in pairs(g_savedata.spawnedFlak) do
            if i ~= j and flak.vehicle_id == flak2.vehicle_id then
                s.announce("[Flak Sanity Check]", "Duplicate flak vehicle found: "..flak.vehicle_id)
                table.remove(g_savedata.spawnedFlak, i)
                fixed = fixed + 1
                break
            end
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

--- @param flakData FlakData the vehicle id to check
--- @return SWMatrix|nil targetMatrix the location the flak is targetting
--- Returns a matrix of the flak vehicles target using its dials. If a dial is not found, it will return a nil
function flakMain.getFlakTarget(flakData)
    if flakData.simulating and false then
        --If the flak vehicle is simulating, use the target provided by ICM
        local vehicle_id = flakData.vehicle_id
        local xDial, success1 = s.getVehicleDial(vehicle_id, "FLAK_TARGET_X")
        local yDial, success2 = s.getVehicleDial(vehicle_id, "FLAK_TARGET_Y")
        local zDial, success3 = s.getVehicleDial(vehicle_id, "FLAK_TARGET_Z")
        if success1 and success2 and success3 then
            return matrix.translation(xDial.value, yDial.value, zDial.value)
        else
            configError("Flak vehicle "..vehicle_id.." does not have all the required dials")
            flakMain.removeVehicleFromFlak(vehicle_id)
            return nil
        end
    else
        --If the flak vehicle is not simulating, try to find a target on our own
        local pseudoTarget = flakMain.getPseudoTarget(flakData)
        return pseudoTarget
    end
end

--- Trys to find a target to aim at even when the flak vehicle is unloaded.
--- @param Flak FlakData the flak vehicle to get the pseudo target of
--- @return SWMatrix|nil targetMatrix the target location
function flakMain.getPseudoTarget(Flak)
    local flakVehicleID = Flak.vehicle_id
    local flakPos = Flak.position
    local sightDistance = flakMain.calculateFlakSight(flakPos)

    --Check if the previous player we tracked is still in range
    if Flak.pseudoTrackingPlayer ~= nil then 
        --Check if the player is still in range
        local playerPos, success = server.getPlayerPos(Flak.pseudoTrackingPlayer)
        if success and playerPos[14] > flakMain.calculateMinAlt(Flak,playerPos) and matrix.distance(flakPos, playerPos) < sightDistance then
            --This player is still in range. Keep targetting them
            return playerPos
        else
            --This player is no longer in range. Stop targetting them
            d.printDebug("Pseudo flak is no longer targetting player ",Flak.pseudoTrackingPlayer)
            Flak.pseudoTrackingPlayer = nil
        end
    end

    --Check player locations
    for i, player in pairs(server.getPlayers()) do
        --For each player, check if they are high enough and close enough to flak
        local playerPos, success = server.getPlayerPos(player.id)
        if success and playerPos[14] > flakMain.calculateMinAlt(Flak,playerPos) then
            --This player is high enough to be shot by flak
            if success and matrix.distance(flakPos, playerPos) < sightDistance then
                --This player is close enough to the flak
                d.printDebug("Pseudo flak is targetting player ",player.id)
                Flak.pseudoTrackingPlayer = player.id
                return playerPos
            end
        end
    end

    return nil
end

--- Uses ICMs equation to calculate how far a flak can see based on the weather and time of day
--- @param location SWMatrix the location to calculate the sight radius
function flakMain.calculateFlakSight(location)
    --Calculation from ICM tickVision, assuming flak has radar.
    BASE_RADIUS = 3500
    local weather = s.getWeather(location)
    local clock = s.getTime()
    return BASE_RADIUS * (1 - (weather.fog * 0.2)) * (0.8 + (math.min(clock.daylight_factor*1.8, 1) * 0.2)) * (1 - (weather.rain * 0.2))
end

--- @param flak FlakData The flak object, used to get the position
--- @param searchPosition SWMatrix? The position to calculate the minimum altitude for. If left blank, uses the flak's last target position
--- @return number minAltitude the minimum altitude the flak can fire at
function flakMain.calculateMinAlt(flak, searchPosition)
    if searchPosition == nil then
        searchPosition = flak.targetPositionData[#flak.targetPositionData].pos
    end
    local flakPosition = flak.position
    local XZDistance =  util.calculateEuclideanDistance(flakPosition[13], searchPosition[13], flakPosition[15], searchPosition[15])
    return g_savedata.settings.minAlt + (XZDistance/20)
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

--- Calculate the position the flak should aim at to hit the target
--- @param flak FlakData the flak vehicle to calculate the lead for
function flakMain.calculateLead(flak)
    if #flak.targetPositionData < 3 then
        d.printDebug("Not enough target data to calculate lead")
        return
    end
    local flakPosition = s.getVehiclePos(flak.vehicle_id)
    local targetPosition = flak.targetPositionData[#flak.targetPositionData].pos
    local travelTime = flakMain.calculateTravelTime(targetPosition, flakPosition)
    local lead = aiming.predictPosition(flak.targetPositionData, travelTime)
    
    --Refine it iteratively to account for the fact that the lead position might take longer/shorter to get to
    local prevTravelTime = travelTime
    for i=1, 3 do
        travelTime = flakMain.calculateTravelTime(lead, flakPosition)
        if travelTime == prevTravelTime then d.printDebug("Exiting early on iteration ",i); break end --Exit out early if we hit the point where its fully refined
        lead = aiming.predictPosition(flak.targetPositionData, travelTime)
    end

    d.debugLabel("lead", lead, "Iteration Enhanced Lead", travelTime)
    return lead
end

--[[
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

    travelTime = flakMain.calculateTravelTime(matrix.translation(x,y,z), flakMatrix)
    d.debugLabel("lead", targetMatrix, "Target", travelTime)
    d.debugLabel("lead", lastTargetMatrix, "Last Target", travelTime)
    d.debugLabel("lead", matrix.translation(x,y,z), "Lead", travelTime)
    return matrix.translation(x, y, z)
end--]]


--- Generates a flak explosion nearby the given matrix.
--- @param sourceMatrix SWMatrix the position of the gun thats firing
--- @param targetMatrix SWMatrix the matrix to generate the explosion at
function flakMain.fireFlak(sourceMatrix, targetMatrix) --Convert to using flakObject
    local x,alt,z = matrix.position(targetMatrix)
    local currentWeather = s.getWeather(targetMatrix)
    d.printDebug("Firing at ",x,",",alt,",",z)

    --Calculate if its too high
    if alt < g_savedata.settings.minAlt then
        d.printDebug("Target is too low to fire at (",alt,"m)")
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
    local clock = s.getTime()

    --Calculate accuracy
    local spread = 0
    local altFactor = 15/(0.5 ^ (alt/320)) --10+(0.2*alt)
    local spread = altFactor
    local spread = spread * weatherMultiplier
    spread = spread / math.max(g_savedata.settings.flakAccuracyMult, 0.1)

    if spread == math.huge then
        d.printError("Fire", "Spread is infinite! Defaulting to 10. AltFactor: ",altFactor,", weatherMultiplier: ",weatherMultiplier)
        spread = 10
    end

    --Randomize the targetMatrix based on spread
    spread = math.floor(spread)
    x = x + math.random(-spread, spread)
    alt = alt + math.random(-spread, spread)
    z = z + math.random(-spread, spread)
    local resultMatrix = matrix.translation(x,alt, z)

    --Randomize travel time alittle
    local travelTime = flakMain.calculateTravelTime(targetMatrix, sourceMatrix)
    --travelTime = travelTime + math.random() * 3 -- 0-3 seconds ahead
    
    --Spawn the explosion
    --- @class ExplosionData
    thisExplosionData = {
        position = resultMatrix,
        magnitude = math.random()/8
    }
    TaskService:AddTask("flakExplosion", travelTime, {thisExplosionData})
end

function flakMain.flakExplosion(explosionData)
    magnitude = explosionData.magnitude
    position = explosionData.position
    d.printDebug("Explosion is at ",s.getTile(position).name," as magnitude ",magnitude)
    s.spawnExplosion(position, magnitude)
    shrapnel.explosion(position,15)
end

return flakMain