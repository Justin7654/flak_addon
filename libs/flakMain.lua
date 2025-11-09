flakMain = {}

d = require("libs.script.debugging")
taskService = require("libs.script.taskService")
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
    ---@field targetPositionData recentPositionData the recent position data of the flak target
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

--- @param flakData FlakData the vehicle id to check
--- @return SWMatrix|nil targetMatrix the location the flak is targeting
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
            --This player is still in range. Keep targeting them
            return playerPos
        else
            --This player is no longer in range. Stop targeting them
            d.printDebug("Pseudo flak is no longer targeting player ",Flak.pseudoTrackingPlayer)
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
                d.printDebug("Pseudo flak is targeting player ",player.id)
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
    local speed = g_savedata.settings.flakShellSpeed/time.second
    local travelTime = math.floor(distance/speed)
    d.printDebug("Travel time is ",travelTime, "ticks (",travelTime/time.second," seconds) because seperation is ",distance,"m and the speed is ",g_savedata.settings.flakShellSpeed,"m/s"..
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

--- Generates a flak explosion nearby the given matrix.
--- This does not enforce constraints, such as minimum altitude.
--- @param sourceMatrix SWMatrix the position of the gun thats firing
--- @param targetMatrix SWMatrix the matrix to generate the explosion at
function flakMain.fireFlak(sourceMatrix, targetMatrix) --Convert to using flakObject
    local targetX, targetAltitude, targetZ = matrix.position(targetMatrix)
    local sourceX, sourceY, sourceZ = matrix.position(sourceMatrix)
    local currentWeather = s.getWeather(targetMatrix)
    d.printDebug("Firing at ", targetX, ",", targetAltitude, ",", targetZ)

    -- Calculate weather multiplier
    local weatherMultiplier = 1
    if not g_savedata.settings.ignoreWeather then
        weatherMultiplier = weatherMultiplier + currentWeather.fog/2
        weatherMultiplier = weatherMultiplier + currentWeather.wind/2
        weatherMultiplier = weatherMultiplier + (currentWeather.rain + currentWeather.snow)/10
    end

    -- Calculate night visibility penalty
    local peakNightPenalty = 0.2 -- Accuracy degrades by up to 20% at night, with 0% at noon, and 20% at midnight
    local clock = s.getTime()
    local nightMultiplier = 1 + (1 - (clock.daylight_factor or 1)) * peakNightPenalty

    --- Generates a single random value from a Gaussian (normal) distribution
    --- Uses Box-Muller transform to convert uniform random values into bell curve distribution
    --- @param mean number the center point of the distribution
    --- @param standardDeviation number how spread out the values are (1-sigma)
    --- @return number gaussianValue a random value following the normal distribution
    local function gaussian(mean, standardDeviation)
        local uniformRandom1 = math.max(math.random(), 1e-6)  -- Avoid log(0)
        local uniformRandom2 = math.random()
        local radius = math.sqrt(-2 * math.log(uniformRandom1))
        local angle = 2 * math.pi * uniformRandom2
        return mean + standardDeviation * radius * math.cos(angle)
    end

    --- Generates two correlated random values from a bivariate Gaussian distribution
    --- Creates realistic shot grouping where horizontal errors are correlated (elliptical pattern)
    --- @param sigmaX number standard deviation in X direction
    --- @param sigmaZ number standard deviation in Z direction
    --- @param correlation number correlation coefficient between X and Z (-1 to 1)
    --- @return number errorX the X-axis error component
    --- @return number errorZ the Z-axis error component (correlated with X)
    local function correlatedGaussian2D(sigmaX, sigmaZ, correlation)
        local uniformRandom1 = math.max(math.random(), 1e-6)
        local uniformRandom2 = math.random()
        local radius = math.sqrt(-2 * math.log(uniformRandom1))
        local angle = 2 * math.pi * uniformRandom2
        local independentZ0 = radius * math.cos(angle)
        local independentZ1 = radius * math.sin(angle)
        
        -- Apply correlation to create dependent relationship between X and Z
        local errorX = sigmaX * independentZ0
        local errorZ = sigmaZ * (correlation * independentZ0 + math.sqrt(1 - (correlation * correlation)) * independentZ1)
        return errorX, errorZ
    end

    -- Calculate distance from the source to the target
    local deltaX = targetX - sourceX
    local deltaY = targetAltitude - sourceY
    local deltaZ = targetZ - sourceZ
    local rangeToTarget = math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)

    -- Base dispersion in milliradians
    local baseDispersionMils = 10.0 -- Biggest factor in accuracy, the angle precision of the gun
    local accuracyMultiplier = math.max(g_savedata.settings.flakAccuracyMult or 1, 0.1)
    
    -- Horizontal correlation factor, creates elliptical shot grouping instead of circular
    local horizontalCorrelation = 0.4

    -- Convert angular dispersion to linear distance at range, affected by weather and time of day
    local baseHorizontalSigma = (rangeToTarget * baseDispersionMils / 1000) * (weatherMultiplier * nightMultiplier) / accuracyMultiplier
    local horizontalSigmaX = baseHorizontalSigma
    local horizontalSigmaZ = baseHorizontalSigma

    -- Vertical dispersion is generally larger, so give it a extra multiplier when calculating its sigma
    local verticalMultiplier = 1.6 --Might remove, this now seems redundant
    local verticalSigma = baseHorizontalSigma * verticalMultiplier

    -- Calculate the shells time of flight for fuze error calculations
    local travelTimeInTicks = flakMain.calculateTravelTime(targetMatrix, sourceMatrix)
    local timeOfFlightSeconds = travelTimeInTicks / (time.second or 60)

    -- Calculate a fuze timing error based on its vertical velocity to add error vertically
    local fuzeTimingStdDevMs = 80 --milliseconds of error
    local verticalVelocityEstimate = deltaY / math.max(timeOfFlightSeconds, 1e-3)
    local fuzeAltitudeError = math.abs(verticalVelocityEstimate) * (fuzeTimingStdDevMs / 1000)
    
    -- Combine the base vertical dispersion with fuze error
    verticalSigma = math.sqrt(verticalSigma * verticalSigma + fuzeAltitudeError * fuzeAltitudeError)

    -- Sample correlated horizontal miss pattern (creates elliptical shot groups)
    local horizontalErrorX, horizontalErrorZ = correlatedGaussian2D(horizontalSigmaX, horizontalSigmaZ, horizontalCorrelation)
    
    -- Sample vertical miss (altitude errors are independent of horizontal)
    local verticalError = gaussian(0, verticalSigma)

    -- Calculate muzzle velocity variation, adds bias along the line-of-sight
    -- Shells don't leave the barrel at exactly the same speed
    local muzzleVelocityJitterPercent = 0.01 --1%
    local rangeErrorSigma = muzzleVelocityJitterPercent * rangeToTarget
    local muzzleVelocityRangeBias = gaussian(0, rangeErrorSigma)
    
    -- Adds error along the shot direction / line between the source and target
    local safeRange = math.max(rangeToTarget, 1e-6)
    local losUnitX, losUnitY, losUnitZ = deltaX / safeRange, deltaY / safeRange, deltaZ / safeRange

    horizontalErrorX = horizontalErrorX + losUnitX * muzzleVelocityRangeBias
    horizontalErrorZ = horizontalErrorZ + losUnitZ * muzzleVelocityRangeBias
    verticalError    = verticalError    + losUnitY * muzzleVelocityRangeBias

    -- Use the final errors to get the actual hit point
    local impactX = targetX + horizontalErrorX
    local impactZ = targetZ + horizontalErrorZ
    local impactAltitude = targetAltitude + verticalError
    d.printDebug(string.format("Impact error - Horizontal X: %.2f m, Horizontal Z: %.2f m, Vertical: %.2f m", horizontalErrorX, horizontalErrorZ, verticalError))

    local resultMatrix = matrix.translation(impactX, impactAltitude, impactZ)

    -- Calculate shell travel time for delayed explosion spawning
    local travelTime = flakMain.calculateTravelTime(resultMatrix, sourceMatrix)
    
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
    shrapnel.explosion(position,65)
end

return flakMain