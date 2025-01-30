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
    local positionMatrix = matrix.translation(chunk.positionX, chunk.positionY, chunk.positionZ)

    -- Attempt to damage near vehicles (TODO: Maybe spatial hashing can make this faster)
    local hit = false
    for i,vehicle_id in ipairs(g_savedata.loadedVehicles) do
        local owner = g_savedata.vehicleOwners[vehicle_id]
        if owner and owner >= 0 then
            local vehicleMatrix, success = s.getVehiclePos(vehicle_id)
            local posX, posY, posZ = matrix.position(vehicleMatrix)
            --Check if its less than 50m away
            if math.abs(chunk.positionX - posX) < 50 and math.abs(chunk.positionY - posY) < 50 and math.abs(chunk.positionZ - posZ) < 50 then
                --Attempt to damage
                hit = shrapnel.damageVehicleAtWorldPosition(vehicle_id, positionMatrix, 30, 0.5)
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
        local x, y, z = matrix.position(positionMatrix)
        server.setPopup(-1, chunk.ui_id, "", true, "Shrapnel", x,y,z, 600)
    end
    

    -- Tick its life and if its not dead yet then queue to tick again next game tick
    chunk.life = chunk.life - 1
    if chunk.life > 0 and not hit then
        taskService:AddTask("tickShrapnelChunk", 1, {chunk})
    elseif chunk.ui_id ~= nil then
        --Delete the debug UI
        d.printDebug("Deleting shrapnel debug label")
        server.removePopup(-1, chunk.ui_id)
    end
end

--- Spawns a explosion of shrapnel at the given position moving outwards
function shrapnel.explosion(sourcePos, shrapnelAmount)

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
        vehiclePos,success = s.getVehiclePos(vehicle_id, 0, 0, 0)
        if not success then
            d.printError("Shrapnel", SSSWTOOL_OUT_LINE,": Failed to get vehicle position for vehicle ",vehicle_id)
            return false
        end
    else
        local mainVehicleID = g_savedata.vehicleToMainVehicle[vehicle_id]
        if not success then
            d.printError("Shrapnel", SSSWTOOL_OUT_LINE,": Failed to get vehicle position for vehicle ",mainVehicleID)
            return false
        end
        ---[[
        --- This offset will make sure that the voxel calculations are generated from the pov from the main_vehicle_id, since this can move.
        --- For example, a truck 10 blocks tall. It falls into place after spawn. Instead of calculating 10, calculate the actual voxel
        --- positions for the truck which is how high up from the main vehicle it is.
        ---]]
        local rawVehiclePos = s.getVehiclePos(vehicle_id)
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