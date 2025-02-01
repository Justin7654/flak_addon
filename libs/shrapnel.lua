taskService = require("libs.taskService")
d = require("libs.debugging")
shrapnel = {}

--- Updats a shrapnel object
--- @param chunk shrapnelChunk The chunk to update
function shrapnel.tickShrapnelChunk(chunk)
    if chunk == nil then
        return d.printError("Shrapnel", "Failed to tick shrapnel chunk, chunk is nil")
    end

    -- Update position
    chunk.positionX = chunk.positionX + chunk.velocityX
    chunk.positionY = chunk.positionY + chunk.velocityY
    chunk.positionZ = chunk.positionZ + chunk.velocityZ

    -- Cache the shrapnel position
    local chunkPosX, chunkPosY, chunkPosZ = chunk.positionX, chunk.positionY, chunk.positionZ

    -- Attempt to damage near vehicles (TODO: Maybe spatial hashing can make this faster)
    local hit = false
    local checks = 0
    local closest = 100000 --TODO: Make the shrapnel delete itself if its super far away from anything (the plane flew past)
    for i,vehicle_id in ipairs(g_savedata.loadedVehicles) do
        local owner = g_savedata.vehicleOwners[vehicle_id]
        --Check if the vehicle is owned by a player so we dont waste time checking AI vehicles or static vehicles
        if owner and owner >= 0 then
            local vehicleMatrix, success = getVehiclePosCached(vehicle_id)
            local posX, posY, posZ = matrix.position(vehicleMatrix)
            --Check if its less than 50m away
            if math.abs(chunkPosX - posX) < 25 and math.abs(chunkPosY - posY) < 25 and math.abs(chunkPosZ - posZ) < 25 then
                --Attempt to damage
                checks = checks + 1
                local hitPosition = m.translation(chunkPosX, chunkPosY, chunkPosZ)
                hit = shrapnel.damageVehicleAtWorldPosition(vehicle_id, hitPosition, 15, 0.4)
                if hit then
                    d.printDebug("Shrapnel hit on vehicle ",vehicle_id," spawned by ",g_savedata.vehicleOwners[vehicle_id] or "nil","!")
                    break
                end 
            end
        end
    end
    
    --Shrapnel debug
    if g_savedata.debug.shrapnel then
        if chunk.ui_id == nil then
            chunk.ui_id = s.getMapID()
        end
        local x, y, z = chunk.positionX, chunk.positionY, chunk.positionZ
        local text = "Shrapnel\nChecks: "..checks
        server.setPopup(-1, chunk.ui_id, "", true, text, chunkPosX,chunkPosY,chunkPosZ, 600)
        if hit then
            d.debugLabel("shrapnel", m.translation(x, y, z), "Hit", 5*time.second)
        end
    end
    

    -- Tick its life and if its not dead yet then queue to tick again next game tick
    chunk.life = chunk.life - 1
    if chunk.life > 0 and not hit then
        taskService:AddTask("tickShrapnelChunk", 1, {chunk})
    elseif chunk.ui_id ~= nil then
        --Delete the debug UI
        server.removePopup(-1, chunk.ui_id)
    end
end

--- Spawns a explosion of shrapnel at the given position moving outwards
--- @param sourcePos SWMatrix The position to spawn the shrapnel at
--- @param shrapnelAmount number The amount of shrapnel to spawn
function shrapnel.explosion(sourcePos, shrapnelAmount)
    local SHRAPNEL_SPEED = 55
    --Cache some globals as locals
    local random = math.random
    local sin = math.sin
    local cos = math.cos
    local pi = math.pi
    for i=1, shrapnelAmount do
        --Generate a velocity
        local theta = random() * 2 * pi  -- Random yaw (0 to 2π)
        local phi = (random() - 0.5) * pi  -- Random pitch (-π/2 to π/2)

        local velocityX = SHRAPNEL_SPEED * cos(theta) * cos(phi)
        local velocityY = SHRAPNEL_SPEED * sin(theta) * cos(phi)
        local velocityZ = SHRAPNEL_SPEED * sin(phi)
        shrapnel.spawnShrapnel(sourcePos, velocityX, velocityY, velocityZ)
    end
end

--- Spawns a shrapnel object at a given position and velocity.
--- @param position SWMatrix The position to spawn the shrapnel at
--- @param velocityX number The x velocity of the shrapnel in m/s
--- @param velocityY number The y velocity of the shrapnel in m/s
--- @param velocityZ number The z velocity of the shrapnel in m/s
function shrapnel.spawnShrapnel(position, velocityX, velocityY, velocityZ)
    --Convert velocitys to tick/s so we dont need to do this when ticking the shrapnel
    velocityX = velocityX / time.second
    velocityY = velocityY / time.second
    velocityZ = velocityZ / time.second

    --Convert the position matrix to just xyz so that it can be stored cheaper and retrieved faster during ticks
    local x, y, z = matrix.position(position)

    --- @class shrapnelChunk
    --- @field ui_id number? If debug is enabled, this is the ui id of the debug label to display the shrapnel. Otherwise its nil
    --- @field life number How many ticks the shrapnel has left until it despawns
    local shrapnelChunk = {
        positionX = x,
        positionY = y,
        positionZ = z,
        velocityX = velocityX,
        velocityY = velocityY,
        velocityZ = velocityZ,
        ui_id = nil,
        life = 120,
    }
    taskService:AddTask("tickShrapnelChunk", 1,  {shrapnelChunk})
end

--- Damages a vehicle using a world position instead of a voxel position.
--- @param vehicle_id number The id of the vehicle to damage
--- @param position SWMatrix The position in the world to damage the vehicle at
--- @param amount number The amount of damage to apply (0-100)
--- @param radius number the radius to apply the damage over, in meters
function shrapnel.damageVehicleAtWorldPosition(vehicle_id, position, amount, radius)
    --Get the vehicle position, and adjust as necessary
    local vehiclePos
    if g_savedata.vehicleToMainVehicle[vehicle_id] == vehicle_id then
        --This is the main vehicle, can use direct current position
        vehiclePos,success = s.getVehiclePos(vehicle_id,0,0,0)
        if not success then
            d.printError("Shrapnel", SSSWTOOL_OUT_LINE,": Failed to get vehicle position for vehicle ",vehicle_id)
            return false
        end
    else
        local rawVehiclePos, success = getVehiclePosCached(vehicle_id)
        if not success then
            d.printError("Shrapnel", SSSWTOOL_OUT_LINE,": Failed to get vehicle position for vehicle ",vehicle_id)
            return false
        end
        ---[[
        --- This offset will make sure that the voxel calculations are generated from the pov from the main_vehicle_id, since this can move.
        --- For example, a truck 10 blocks tall. It falls into place after spawn. Instead of calculating 10, calculate the actual voxel
        --- positions for the truck which is how high up from the main vehicle it is.
        ---]]
        local offset = g_savedata.vehicleInitialOffsets[vehicle_id]
        vehiclePos = matrix.multiply(rawVehiclePos, matrix.invert(offset))
    end
    --Calculate the voxel positions
    local combinedX, combinedY, combinedZ = matrix.position(matrix.multiply(matrix.invert(vehiclePos), position))
    combinedX, combinedY, combinedZ = math.floor(combinedX*4), math.floor(combinedY*4), math.floor(combinedZ*4) --Each voxel is 0.25m and then round

	local success = s.addDamage(vehicle_id, amount, combinedX, combinedY, combinedZ, radius)

    --Debug
    if success then
        d.printDebug("Hit at ", tostring(combinedX),",", tostring(combinedY),",", tostring(combinedZ), " with radius ", tostring(radius))
        local realPosition, success = s.getVehiclePos(vehicle_id, combinedX, combinedY, combinedZ)
	    if success then
            d.debugLabel("shrapnel", realPosition, "Real Voxel", 3*time.second)
        end
    end

    return success
end

return shrapnel