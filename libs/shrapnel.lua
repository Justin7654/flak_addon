taskService = require("libs.script.taskService")
collisionDetection = require("libs.collisionDetection")
matrixExtras = require("libs.script.matrixExtras")
d = require("libs.script.debugging")
shrapnel = {}

-- Performance tracking excel sheet:https://1drv.ms/x/c/5e0eec0b38cb0474/EWqWCGP-O2VOr-6FV9Qp3EIBIXUpqVqg8FAa8HjlWxKk2g?e=Z7Dj0n

local FILTER_GROUND_VEHICLES = true
local FILTER_NON_PLAYER_VEHICLES = true
local SKIP_TICK_ALL_IF_NO_SHRAPNEL = true
local ALWAYS_CHECK_COLLISION_DEBUG = false
local DONT_DESTROY_ON_HIT_DEBUG = false

--- Ticks all shrapnel objects
--- Made to replace the system of using task service to loop it, since that is slow, and makes some optimizations impossible or complicated
function shrapnel.tickAll()
    -- Dont do anything if theres no shrapnel
    if util.getTableLength(g_savedata.shrapnelChunks) == 0 and SKIP_TICK_ALL_IF_NO_SHRAPNEL then
        return
    end
    d.startProfile("tickAllShrapnel")

    -- Decide the vehicles the each shrapnel will check, to minimize the checks needed to be done by each individual shrapnel
    d.startProfile("tickAll:decideVehicles")
    local vehicleInfoTable = g_savedata.vehicleInfo
    local vehiclesToCheck = {}
    local vehiclePositions = {}
    local vehicleZeroPositions = {}
    for _,vehicle_id in ipairs(g_savedata.loadedVehicles) do
        --Check if the vehicle is owned by a player so we dont waste time checking AI vehicles or static vehicles
        local vehicleInfo = vehicleInfoTable[vehicle_id]
        if vehicleInfo  == nil then
            d.printDebug("Vehicle info is nil for vehicle ",vehicle_id)
            --Recover from a error
            vehicleInfo = {owner = -1}
        end
        local owner = vehicleInfo.owner
        if (owner and owner >= 0) or (not FILTER_NON_PLAYER_VEHICLES) then
            --Check if it has a baseVoxel, otherwise it cant be checked
            if vehicleInfo.base_voxel ~= nil then
                --Should be valid, just make sure that you can get its data fine
                local vehicleMatrix, posSuccess = s.getVehiclePos(vehicle_id)
                if posSuccess then
                    --Check that its higher than the base altitude to exclude vehicles that cant be targeted by flak
                    local x,y,z = vehicleMatrix[13], vehicleMatrix[14], vehicleMatrix[15]
                    if y > g_savedata.settings.minAlt or not FILTER_GROUND_VEHICLES then
                        d.startProfile("calculateVehicleVoxelZeroPosition")
                        local zeroPosSuccess,vehicleZeroPosition = shrapnel.calculateVehicleVoxelZeroPosition(vehicle_id)
                        d.endProfile("calculateVehicleVoxelZeroPosition")
                        if zeroPosSuccess then
                            --This is a valid vehicle. Insert into the tables
                            local vehicleX, vehicleY, vehicleZ = matrix.positionFast(vehicleMatrix)
                            table.insert(vehiclesToCheck, vehicle_id)
                            vehiclePositions[vehicle_id] = {vehicleX, vehicleY, vehicleZ}
                            vehicleZeroPositions[vehicle_id] = matrixExtras.invert(vehicleZeroPosition)
                        end
                    end
                end
            end
        end
    end
    d.endProfile("tickAll:decideVehicles")

    -- Go through all the shrapnel chunks and tick them
    for _, chunk in pairs(g_savedata.shrapnelChunks) do
        shrapnel.tickShrapnelChunk(chunk, vehiclesToCheck, vehiclePositions, vehicleZeroPositions)
    end
    d.endProfile("tickAllShrapnel")
end

--- Updates a shrapnel object
--- @param chunk shrapnelChunk The chunk to update
--- @param vehiclesToCheck table<number, number> a list of all the vehicles to check collision for
--- @param vehicleZeroPositions table<number, SWMatrix> a list of all the vehicles cached zero positions
function shrapnel.tickShrapnelChunk(chunk, vehiclesToCheck, vehiclePositions, vehicleZeroPositions)
    if chunk == nil then
        return d.printError("Shrapnel", "Failed to tick shrapnel chunk, chunk is nil")
    end
    --d.startProfile("tickShrapnelChunk")

    --Pre-decide which vehicles are close enough since they generally wont change between steps, and it wont matter much if it does change
    --d.startProfile("decideVehicles")
    local finalVehicles = {}
    local futureX = chunk.positionX + chunk.fullVelocityX
    local futureY = chunk.positionY + chunk.fullVelocityY
    local futureZ = chunk.positionZ + chunk.fullVelocityZ
    for i,vehicle_id in ipairs(vehiclesToCheck) do
        --Check if its more than 25m away from the final position of this tick
        local vehicleMatrix = vehiclePositions[vehicle_id]
        local posX, posY, posZ = vehicleMatrix[1], vehicleMatrix[2], vehicleMatrix[3]
        if ALWAYS_CHECK_COLLISION_DEBUG or (math.abs(futureX - posX) < 30 and math.abs(futureY - posY) < 30 and math.abs(futureZ - posZ) < 30) then
            table.insert(finalVehicles, vehicle_id)
        end
    end
    --d.endProfile("decideVehicles")

    --Start stepping the position and checking if its hit anything
    local hit = false
    local checks = 0
    local totalSteps = g_savedata.settings.shrapnelSubSteps
    
    if #finalVehicles == 0 then
        --If there are no vehicles to check, then we can skip the steps and just move it to the final position
        chunk.positionX = futureX
        chunk.positionY = futureY
        chunk.positionZ = futureZ
        totalSteps = 0
    end

    for step=1, totalSteps do
        -- Update position
        chunk.positionX = chunk.positionX + chunk.velocityX
        chunk.positionY = chunk.positionY + chunk.velocityY
        chunk.positionZ = chunk.positionZ + chunk.velocityZ

        -- Cache the shrapnel position
        local hitPosition = m.translation(chunk.positionX, chunk.positionY, chunk.positionZ)

        --Attempt to damage near vehicles
        for i,vehicle_id in ipairs(finalVehicles) do
            --Attempt to damage
            checks = checks + 1
            hit = shrapnel.damageVehicleAtWorldPosition(vehicle_id, hitPosition, vehicleZeroPositions[vehicle_id],5, 0.4)
            if DONT_DESTROY_ON_HIT_DEBUG then
                hit = false
            end
            if hit then
                break
            end
        end
        
        --d.debugLabel("shrapnel", hitPosition, "!", 1400, 40)
        
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
    

    -- Tick its life and if its dead then remove itself from the shrapnelChunks list
    chunk.life = chunk.life - 1
    if chunk.life <= 0 or hit then
        if chunk.ui_id ~= nil then
            --Delete the debug UI
            server.removePopup(-1, chunk.ui_id)
        end
        g_savedata.shrapnelChunks[chunk.id] = nil
    end
    --d.endProfile("tickShrapnelChunk")
end

--- Spawns a explosion of shrapnel at the given position moving outwards
--- @param sourcePos SWMatrix The position to spawn the shrapnel at
--- @param shrapnelAmount number The amount of shrapnel to spawn
function shrapnel.explosion(sourcePos, shrapnelAmount)
    local SHRAPNEL_SPEED = 120 --95
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

    --Increment the ID
    g_savedata.shrapnelCurrentID = g_savedata.shrapnelCurrentID + 1

    --Convert velocitys to tick/s so we dont need to do this when ticking the shrapnel
    velocityX = velocityX / time.second
    velocityY = velocityY / time.second
    velocityZ = velocityZ / time.second

    --Convert the position matrix to just xyz so that it can be stored cheaper and retrieved faster during ticks
    local x, y, z = matrix.positionFast(position)

    --- @class shrapnelChunk
    --- @field ui_id number? If debug is enabled, this is the ui id of the debug label to display the shrapnel. Otherwise its nil
    --- @field life number How many ticks the shrapnel has left until it despawns
    local shrapnelChunk = {
        positionX = x,
        positionY = y,
        positionZ = z,
        velocityX = velocityX / g_savedata.settings.shrapnelSubSteps,
        velocityY = velocityY / g_savedata.settings.shrapnelSubSteps,
        velocityZ = velocityZ / g_savedata.settings.shrapnelSubSteps,
        fullVelocityX = velocityX,
        fullVelocityY = velocityY,
        fullVelocityZ = velocityZ,
        ui_id = nil,
        life = 60,
        id = g_savedata.shrapnelCurrentID,
    }
    g_savedata.shrapnelChunks[g_savedata.shrapnelCurrentID] = shrapnelChunk
    --taskService:AddTask("tickShrapnelChunk", 1,  {shrapnelChunk})
end

--- Damages a vehicle using a world position instead of a voxel position.
--- @param vehicle_id number The id of the vehicle to damage
--- @param position SWMatrix The position in the world to damage the vehicle at
--- @param vehicleZeroPos SWMatrix? The position calculated by calculateVehicleVoxelZeroPosition. If not provided, it will be calculated
--- @return boolean success weather the damage was successful or not
--- @return number voxelX the x voxel position
--- @return number voxelY the y voxel position
--- @return number voxelZ the z voxel position
function shrapnel.getVehicleVoxelAtWorldPosition(vehicle_id, position, vehicleZeroPos, amount, radius)
    ---[[[
    --- In Depth Explanation:
    ---  1. its gets the baseVoxel (the closest voxel to 0,0,0 which exists)
    ---  2. gets the vehicle position at the baseVoxel
    ---  3. offsets the vehicle position variable by the baseVoxel so that the vehiclePos is at where 0,0,0 should be
    ---]]]

    --Get the vehicle position at 0,0,0
    --d.startProfile("getVehicleVoxelAtWorldPosition")
    local vehiclePos = vehicleZeroPos
    if vehiclePos == nil then
        d.printDebug("Calculating own voxel zero position manually")
        success, vehiclePos = shrapnel.calculateVehicleVoxelZeroPosition(vehicle_id)
        if not success then
            d.printDebug("(shrapnel.getVehicleVoxelAtWorldPosition) Failed to get voxel zero position")
            d.endProfile("getVehicleVoxelAtWorldPosition")
            return false, 0, 0, 0
        end
        --d.debugLabel("shrapnel", vehiclePos, "Zero position ("..vehicle_id..")", time.second)
    end
    
    --Calculate the voxel positions
    local finalMatrix = matrixExtras.multiplyMatrix(position, vehiclePos)
    local combinedX, combinedY, combinedZ = finalMatrix[13], finalMatrix[14], finalMatrix[15] --Converts the matrix to xyz variables
    combinedX, combinedY, combinedZ = (combinedX * 4) // 1, (combinedY * 4) // 1, (combinedZ * 4) // 1 --Each voxel is 0.25m and then floors the result (this is slightly faster than math.floor) 

    --d.debugLabel("shrapnel", position, combinedX..","..combinedY..","..combinedZ, 6*time.second)

    --d.endProfile("getVehicleVoxelAtWorldPosition")
    return true, combinedX, combinedY, combinedZ
end

--- Attempts to get the 0,0,0 position of the vehicle using the base voxel system
--- Used to be built-in to getVehicleVoxelAtWorldPosition but has been split to allow for optimization
--- @param vehicle_id number The id of the vehicle to get the position of
--- @return boolean success if it was successfully calculated. This can fail for several reasons
--- @return SWMatrix vehiclePosZero
function shrapnel.calculateVehicleVoxelZeroPosition(vehicle_id)
    local SUPER_DEBUG = false

    --Get the base voxel to use for getting the vehicle position
    local baseVoxel = g_savedata.vehicleInfo[vehicle_id].base_voxel
    if baseVoxel == nil then
        return false, matrix.translation(0,0,0)
    end
    local voxelX, voxelY, voxelZ = baseVoxel.x, baseVoxel.y, baseVoxel.z
    
    --Get the vehicle position
    local vehiclePos,success = s.getVehiclePos(vehicle_id, voxelX, voxelY, voxelZ)
    if not success then
        d.printError("Shrapnel", SSSWTOOL_SRC_LINE,": Failed to get vehicle position for vehicle ",vehicle_id)
        return false, matrix.translation(0,0,0)
    end
    if SUPER_DEBUG then d.debugLabel("shrapnel", vehiclePos, "Raw pos: "..voxelX..", "..voxelY..", "..voxelZ.." ("..vehicle_id..")", time.second) end
    
    --If the used voxels are not 0,0,0 then offset the position so that they are at where 0,0,0 would be if it existed
    if voxelX ~= 0 or voxelY ~= 0 or voxelZ ~= 0 then   
        vehiclePos = matrix.multiply(vehiclePos, matrix.translation(-voxelX/4, -voxelY/4, -voxelZ/4))
    end
    if SUPER_DEBUG then d.debugLabel("shrapnel", vehiclePos, "Detected 0,0,0 ("..vehicle_id..")", time.second) end
    
    return true, vehiclePos
end

function shrapnel.damageVehicleAtWorldPosition(vehicle_id, position, zeroPosition, amount, radius)
    local success, voxelX, voxelY, voxelZ = shrapnel.getVehicleVoxelAtWorldPosition(vehicle_id, position, zeroPosition, amount, radius)
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