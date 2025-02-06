taskService = require("libs.taskService")
d = require("libs.debugging")
shrapnel = {}

--- Updats a shrapnel object
--- @param chunk shrapnelChunk The chunk to update
function shrapnel.tickShrapnelChunk(chunk)
    if chunk == nil then
        return d.printError("Shrapnel", "Failed to tick shrapnel chunk, chunk is nil")
    end

    --Before starting stepping, pre-decide which vehicles to check since they generally wont change inbetween steps, and it wont matter much if it does change
    local vehiclesToCheck = {}
    local futureX = chunk.positionX + (chunk.velocityX * g_savedata.settings.shrapnelSubSteps)
    local futureY = chunk.positionY + (chunk.velocityY * g_savedata.settings.shrapnelSubSteps)
    local futureZ = chunk.positionZ + (chunk.velocityZ * g_savedata.settings.shrapnelSubSteps)
    for i,vehicle_id in ipairs(g_savedata.loadedVehicles) do
        --Check if the vehicle is owned by a player so we dont waste time checking AI vehicles or static vehicles
        local owner = g_savedata.vehicleOwners[vehicle_id]
        if owner and owner >= 0 then
            --Check if it has a baseVoxel, otherwise it cant be checked
            if g_savedata.vehicleBaseVoxel[vehicle_id] ~= nil then
                --Check if its less than 25m away
                local vehicleMatrix = getVehiclePosCached(vehicle_id)
                local posX, posY, posZ = matrix.position(vehicleMatrix)
                if math.abs(futureX - posX) < 30 and math.abs(futureY - posY) < 30 and math.abs(futureZ - posZ) < 30 then
                    table.insert(vehiclesToCheck, vehicle_id)
                end
            end
        end
    end

    --Start stepping the position and checking if its hit anything yet
    local hit = false
    local checks = 0
    for step=1, g_savedata.settings.shrapnelSubSteps do
        -- Update position
        chunk.positionX = chunk.positionX + chunk.velocityX
        chunk.positionY = chunk.positionY + chunk.velocityY
        chunk.positionZ = chunk.positionZ + chunk.velocityZ

        -- Cache the shrapnel position
        local chunkPosX, chunkPosY, chunkPosZ = chunk.positionX, chunk.positionY, chunk.positionZ

        --Attempt to damage near vehicles
        for i,vehicle_id in ipairs(vehiclesToCheck) do
            --Attempt to damage
            checks = checks + 1
            local hitPosition = m.translation(chunkPosX, chunkPosY, chunkPosZ)
            hit = shrapnel.damageVehicleAtWorldPosition(vehicle_id, hitPosition, 5, 0.4)
            if hit then
                break
            end
        end

        --Break out of the stepping if it hit something
        if hit then
            break
        end
    end
    
    --Shrapnel debug
    if g_savedata.debug.shrapnel then
        if chunk.ui_id == nil then
            chunk.ui_id = s.getMapID()
        end
        local x, y, z = chunk.positionX, chunk.positionY, chunk.positionZ
        local text = "Shrapnel\nChecks: "..checks
        server.setPopup(-1, chunk.ui_id, "", true, text, x, y, z, 300)
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
    local SHRAPNEL_SPEED = 95
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
    if s.getGameSettings().vehicle_damage == false then
        return
    end

    --Convert velocitys to tick/s so we dont need to do this when ticking the shrapnel
    velocityX = velocityX / time.second
    velocityY = velocityY / time.second
    velocityZ = velocityZ / time.second

    --Divide the velocity by the amount of substeps so that the shrapnel stays the same speed as substeps increase
    velocityX = velocityX / g_savedata.settings.shrapnelSubSteps
    velocityY = velocityY / g_savedata.settings.shrapnelSubSteps
    velocityZ = velocityZ / g_savedata.settings.shrapnelSubSteps

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
        life = 90,
    }
    taskService:AddTask("tickShrapnelChunk", 1,  {shrapnelChunk})
end

--- Damages a vehicle using a world position instead of a voxel position.
--- @param vehicle_id number The id of the vehicle to damage
--- @param position SWMatrix The position in the world to damage the vehicle at
--- @return boolean success weather the damage was successful or not
--- @return number voxelX the x voxel position
--- @return number voxelY the y voxel position
--- @return number voxelZ the z voxel position
function shrapnel.getVehicleVoxelAtWorldPosition(vehicle_id, position, amount, radius)
    local SUPER_DEBUG = false
    ---[[[
    --- In Depth Explanation:
    ---  1. its gets the baseVoxel (the closest voxel to 0,0,0 which exists)
    ---  2. gets the vehicle position at the baseVoxel
    ---  3. offsets the vehicle position variable by the baseVoxel so that the vehiclePos is at where 0,0,0 should be
    ---]]]

    --Get the base voxel to use for getting the vehicle position
    local baseVoxel = g_savedata.vehicleBaseVoxel[vehicle_id]
    if baseVoxel == nil then
        return false,0,0,0
    end
    local voxelX, voxelY, voxelZ = baseVoxel.x, baseVoxel.y, baseVoxel.z
    
    --Get the vehicle position
    vehiclePos,success = s.getVehiclePos(vehicle_id, voxelX, voxelY, voxelZ)
    if not success then
        d.printError("Shrapnel", SSSWTOOL_SRC_LINE,": Failed to get vehicle position for vehicle ",vehicle_id)
        return false,0,0,0
    end
    if SUPER_DEBUG then d.debugLabel("shrapnel", vehiclePos, "Raw pos: "..voxelX..", "..voxelY..", "..voxelZ.." ("..vehicle_id..")", time.second*2) end
    
    --If the used voxels are 0,0,0 then offset the position so that they are at where 0,0,0 would be if it existed
    if voxelX ~= 0 or voxelY ~= 0 or voxelZ ~= 0 then   
        vehiclePos = matrix.multiply(vehiclePos, matrix.translation(-voxelX/4, -voxelY/4, -voxelZ/4))
    end
    if SUPER_DEBUG then d.debugLabel("shrapnel", vehiclePos, "Detected 0,0,0 ("..vehicle_id..")", 2*time.second) end
    
    --Calculate the voxel positions
    local finalMatrix = matrix.multiply(matrix.invert(vehiclePos), position)
    local combinedX, combinedY, combinedZ = matrix.position(finalMatrix)
    combinedX, combinedY, combinedZ = math.floor(combinedX*4), math.floor(combinedY*4), math.floor(combinedZ*4) --Each voxel is 0.25m and then round

    if SUPER_DEBUG then d.debugLabel("shrapnel", position, combinedX..","..combinedY..","..combinedZ, 6*time.second) end

    return true, combinedX, combinedY, combinedZ
    --[[ Left over code from when this damaged
	local success = s.addDamage(vehicle_id, amount, combinedX, combinedY, combinedZ, radius)
    
    --Debug
    --d.setVoxelMap(vehicle_id, matrix.multiply(vehiclePos, matrix.translation(0,0.2,0)), "shrapnel")
    if SUPER_DEBUG then d.debugLabel("shrapnel", position, combinedX..","..combinedY..","..combinedZ, 6*time.second) end
    if success then
        d.printDebug("Hit at ", tostring(combinedX),",", tostring(combinedY),",", tostring(combinedZ), " with radius ", tostring(radius))
        local realPosition, success = s.getVehiclePos(vehicle_id, combinedX, combinedY, combinedZ)
	    if success then
            d.debugLabel("shrapnel", realPosition, "Real Voxel", 2*time.second)
        end
    end

    return success]]
end

function shrapnel.damageVehicleAtWorldPosition(vehicle_id, position, amount, radius)
    local success, voxelX, voxelY, voxelZ = shrapnel.getVehicleVoxelAtWorldPosition(vehicle_id, position, amount, radius)
    if success then
        return s.addDamage(vehicle_id, amount, voxelX, voxelY, voxelZ, radius)
    end
    return false
end
--- @param vehicle_id number The id of the vehicle to check
--- @param x number The x voxel position to check
--- @param y number The y voxel position to check
--- @param z number The z voxel position to check
--- @return boolean exists weather the voxel exists or not
function shrapnel.checkVoxelExists(vehicle_id, x, y, z)
    --Checking for damage success is way faster than comparing the centerPos
    return s.addDamage(vehicle_id, 0, x, y, z, 0)
end

function shrapnel.debugVoxelPositions(vehicle_id, resume_range)
    local _, success = s.getVehiclePos(vehicle_id)
    if not success then
        return d.printWarning("Stopping debugVoxelPositions due to failed getVehiclePos")
    end
    local range = 45
    local z = resume_range or -range
    d.printDebug("Debugging voxel positions at z=",tostring(z))
    for x=-range, range, 1 do
        for y=-range, range, 1 do
            if shrapnel.checkVoxelExists(vehicle_id,x,y,z) then
                local realPosition, success = s.getVehiclePos(vehicle_id, x, y, z)
                d.debugLabel("shrapnel", realPosition, x..","..y..","..z, 10*time.second, 3)
            end
        end
    end

    if z < range then
        taskService:AddTask("debugVoxelPositions", 45, {vehicle_id, z+1})
    end
end

return shrapnel