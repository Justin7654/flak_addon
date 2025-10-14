---[[[
--- This file handles the bounding boxs of vehicles.
--- Used to optimize expensive calculations, by avoiding calculations when a simple distance check might false positive
--- Also should elimate false-negatives with distance checks
--- 
--- May not be 100% accurate, uses component data to approximate a bounding box.
---
--- Completely non-functional and abandoned
---]]]

local collisionDetection = {}
local d = require("libs.script.debugging")
local taskService = require("libs.script.taskService")
local vehicleInfoManager = require("libs.vehicleInfoManager")

---@class colliderData
---@field baseAABB baseAABB?
---@field aabb AABB?
---@field last_update number
---@field debug table

--- Generates the extreme components of the vehicle, which are the components on each corner of the vehicle.
--- 
--- @param vehicle_id number
--- @return colliderExtremes?
function collisionDetection.calculateExtremes(vehicle_id)
    --Get the farthest point from the center of the vehicle
    --Size in all directions is that distance*2
    local vehicleInfo = g_savedata.vehicleInfo[vehicle_id]
    local isSetup, vehicleInfo = vehicleInfoManager.isVehicleDataSetup(vehicleInfo)
    if isSetup then
        local com = vehicleInfo.components
		local allComponents = util.combineList(com.batteries, com.buttons, com.dials, com.guns, com.hoppers, com.rope_hooks, com.seats, com.signs, com.tanks)
        
        if #allComponents == 0 then
            return
        end

        ---@class colliderExtremes
        local extremes = {
            left = {x = math.huge, y = 0, z = 0},
            right = {x = -math.huge, y = 0, z = 0},
            top = {x = 0, y = -math.huge, z = 0},
            bottom = {x = 0, y = math.huge, z = 0},
            front = {x = 0, y = 0, z = -math.huge},
            back = {x = 0, y = 0, z = math.huge}
        }

        for _, component in ipairs(allComponents) do
            local pos = component.pos
            if pos.x < extremes.left.x then
                extremes.left = pos
            end
            if pos.x > extremes.right.x then
                extremes.right = pos
            end
            if pos.y > extremes.top.y then
                extremes.top = pos
            end
            if pos.y < extremes.bottom.y then
                extremes.bottom = pos
            end
            if pos.z > extremes.front.z then
                extremes.front = pos
            end
            if pos.z < extremes.back.z then
                extremes.back = pos
            end
        end

        --Remove duplicates
        for k, v in pairs(extremes) do
            for k2, v2 in pairs(extremes) do
                if k ~= k2 and v.x == v2.x and v.y == v2.y and v.z == v2.z then
                    --extremes[k] = nil
                    break
                end
            end
        end

        output = {extremes.left, extremes.right, extremes.top, extremes.bottom, extremes.front, extremes.back}

        return output
    else
        d.printError("collisionDetection", SSSWTOOL_SRC_FILE, "-",SSSWTOOL_SRC_LINE,": Attempt to calculate extreme for a vehicle that has not been setup")
    end
end

--- Generates a AABB of the vehicle based on it facing forward in the workbench.
--- This can then be transformed later based on the vehicles transform matrix to get a rotated version
--- @param vehicle_id number
--- @return baseAABB?
function collisionDetection.generateBaseAABB(vehicle_id)
    local vehicleInfo = g_savedata.vehicleInfo[vehicle_id]
    local isSetup, vehicleInfo = vehicleInfoManager.isVehicleDataSetup(vehicleInfo)
    if isSetup then
        local corners = collisionDetection.calculateExtremes(vehicle_id)
        if corners then
            local max = {-math.huge, -math.huge, -math.huge}
            local min = {math.huge, math.huge, math.huge}
            for k,corner in ipairs(corners) do
                max[1] = math.max(max[1], corner.x)
                max[2] = math.max(max[2], corner.y)
                max[3] = math.max(max[3], corner.z)

                min[1] = math.min(min[1], corner.x)
                min[2] = math.min(min[2], corner.y)
                min[3] = math.min(min[3], corner.z)

                if g_savedata.debug.bbox then
                    local vehiclePos = s.getVehiclePos(vehicle_id, 0, 0, 0)
                    local x,y,z,_ = matrix.multiplyXYZW(vehiclePos, corner.x/4, corner.y/4, corner.z/4, 1)
                    d.debugLabel("bbox", matrix.translation(x,y,z), "Corner", 15*time.second)
                end
            end
            ---@class baseAABB
            local baseAABB = {
                min = min,
                max = max
            }

            d.printDebug("Generated base AABB for ",tostring(vehicle_id))
            vehicleInfo.collider_data.baseAABB = baseAABB
            return baseAABB
        else
            d.printWarning("Failed to generate base AABB because couldn't calculate extremes")
        end
    else
        d.printWarning("Attempted to generate a base AABB for a vehicle that isn't setup!")
    end
end

--- Generates a rotated AABB based on the vehicles transform matrix and a base AABB.
--- Output is the AABB min point and max point in local space
function collisionDetection.calculateAABB(vehicle_id)
    local vehicleData = g_savedata.vehicleInfo[vehicle_id]
    local isSetup, vehicleData = vehicleInfoManager.isVehicleDataSetup(vehicleData)
    if not isSetup then
        return d.printError("collisionDetection", "Attempted to calculate AABB for a vehicle that isn't setup!")
    end
    local baseAABB = vehicleData.collider_data.baseAABB
    if baseAABB == nil then
        return d.printError("collisionDetection", "Attempted to calculate AABB for a vehicle that doesn't have a base AABB!")
    end
    local transformMatrix = s.getVehiclePos(vehicle_id, 0, 0, 0)
    
    --[[local corners = {
        {baseAABB.min[1], baseAABB.min[2], baseAABB.min[3]},
        {baseAABB.min[1], baseAABB.min[2], baseAABB.max[3]},
        {baseAABB.min[1], baseAABB.max[2], baseAABB.min[3]},
        {baseAABB.min[1], baseAABB.max[2], baseAABB.max[3]},
        {baseAABB.max[1], baseAABB.min[2], baseAABB.min[3]},
        {baseAABB.max[1], baseAABB.min[2], baseAABB.max[3]},
        {baseAABB.max[1], baseAABB.max[2], baseAABB.min[3]},
        {baseAABB.max[1], baseAABB.max[2], baseAABB.max[3]}
    }]]
    local corners = collisionDetection.calculateExtremes(vehicle_id)
    if corners == nil then
        return d.printError("collisionDetection", "Failed to calculate corners for vehicle_id: " .. vehicle_id)
    end

    -- Transform each corner using the transformation matrix
    local newMin = {math.huge, math.huge, math.huge}
    local newMax = {-math.huge, -math.huge, -math.huge}

    local step = 1
    for _, corner in ipairs(corners) do
        --local x, y, z, _ = matrix.multiplyXYZW(transformMatrix, corner[1], corner[2], corner[3], 1)
        local position = s.getVehiclePos(vehicle_id, corner.x, corner.y, corner.z)
        local x, y, z = matrix.position(position)

        if step == 10 then
            break
        end

        -- Update the new AABB bounds
        newMin[1] = math.min(newMin[1], x)
        newMin[2] = math.min(newMin[2], y)
        newMin[3] = math.min(newMin[3], z)

        newMax[1] = math.max(newMax[1], x)
        newMax[2] = math.max(newMax[2], y)
        newMax[3] = math.max(newMax[3], z)

        --d.printDebug("Corner ".._.." is at ",math.floor(x),",",math.floor(y),",",math.floor(z))
        --d.printDebug("Step ",step,". X: ",math.floor(newMin[1]),", Y: ",math.floor(newMin[2]),", Z: ",math.floor(newMin[3]))

        step = step + 1
    end

    if g_savedata.debug.bbox then
        local debugData = vehicleData.collider_data.debug
        local playerPos = s.getPlayerPos(0)
        local playerX, playerY, playerZ = matrix.position(playerPos)
        s.setPopup(-1, debugData.minLabel, "", true, "min", newMin[1], newMin[2], newMin[3], 35)
        s.setPopup(-1, debugData.maxLabel, "", true, "max", newMax[1], newMax[2], newMax[3], 35)
        if debugData.cleanTask1 and g_savedata.tasks[debugData.cleanTask1.id] ~= nil then
            debugData.cleanTask1.endTime = g_savedata.tickCounter + 1
            debugData.cleanTask2.endTime = g_savedata.tickCounter + 1
        else
            debugData.cleanTask1 = taskService:AddTask("setPopup", 1, {-1, debugData.minLabel, "", false, "", 0, 0, 0, 0})
            debugData.cleanTask2 = taskService:AddTask("setPopup", 1, {-1, debugData.maxLabel, "", false, "", 0, 0, 0 ,0})
        end
    end

    ---@class AABB
    rotatedAABB = {
        min = newMin,
        max = newMax
    }
    vehicleData.collider_data.aabb = rotatedAABB
    vehicleData.collider_data.last_update = g_savedata.tickCounter
    return rotatedAABB
end

function collisionDetection.getAABBForVehicle(vehicle_id)
    local vehicleData = g_savedata.vehicleInfo[vehicle_id]
    local isSetup, vehicleData = vehicleInfoManager.isVehicleDataSetup(vehicleData)
    if isSetup and vehicleData.collider_data then
        
    end
end

--- Checks if a given point is inside a given AABB
--- @return boolean isInside
function collisionDetection.isPointInsideAABB(aabb, x, y, z)
    return (x >= aabb.min[1] and x <= aabb.max[1]) and
           (y >= aabb.min[2] and y <= aabb.max[2]) and
           (z >= aabb.min[3] and z <= aabb.max[3])
end

--- Returns a base AABB previously pre-computed for the vehicle given a vehicle_id
function collisionDetection.getBaseAABB(vehicle_id)

end

--- Returns the most recent computed AABB for the given vehicle_id
function collisionDetection.getAABB(vehicle_id)

end

--[[
function collisionDetection.generateBBOX(vehicle_id)
    local front = -1000
    local back = 1000
    local left = 1000
    local right = -1000
    local top = -1000
    local bottom = 1000

    -- Get the component data
    local components, success = server.getVehicleComponents(vehicle_id)
    if not success then
        return d.printError("bbox", "Failed to get vehicle components for vehicle_id: " .. vehicle_id)
    end
    -- Go through each component and find the min/max values for the bounding box
    local totalComponents = 0
    for _, componentType in pairs(components.components) do
        for _, component in ipairs(componentType) do
            local pos = component.pos --- @type SWVoxelPos
            totalComponents = totalComponents + 1
            --Update the bounding box based on its position
            if pos.x < left then
                left = pos.x
            end
            if pos.x > right then
                right = pos.x
            end
            if pos.y < bottom then
                bottom = pos.y
            end
            if pos.y > top then
                top = pos.y
            end
            if pos.z > front then
                front = pos.z
            end
            if pos.z < back then
                back = pos.z
            end
        end
    end

    --If the vehicle has no components to track, estimate
    if totalComponents == 0 then
        local voxelCount = components.voxels
        local factor = voxelCount/50
        local zeroPos = s.getVehiclePos(vehicle_id, 0, 0, 0)
        local CoM = s.getVehiclePos(vehicle_id)
        local offset_x, offset_y, offset_z = matrix.position(matrix.multiply(zeroPos, CoM))
        d.debugLabel("bbox", s.getVehiclePos(vehicle_id, offset_x, offset_y, offset_z), "Estimated BBOX", 15*time.second)
        top = offset_x + factor
        bottom = offset_x - factor
        left = offset_y - factor
        right = offset_y + factor
        front = offset_z + factor
        back = offset_z - factor
        d.printDebug("Factor: ",factor,". offset_x: ",offset_x,". offset_y: ",offset_y,". offset_z: ",offset_z)
        d.printDebug("Used backup estimation for vehicle_id ",vehicle_id," because it had no trackable components")
    end


    --Account for the fact that voxels are 0.25m
    --We dont want the voxel bbox, we want the vehicle bbox
    top = top / 4
    bottom = bottom / 4
    left = left / 4
    right = right / 4
    front = front / 4
    back = back / 4
    
    if g_savedata.debug.bbox then
        local vehiclePos = s.getVehiclePos(vehicle_id, 0, 0, 0)
        local x, y, z = matrix.position(vehiclePos)

        d.printDebug("--------------")
        d.printDebug("Voxel count: ", components.voxels)
        d.printDebug("Component count: ", totalComponents)
        d.printDebug("Front: ", front)
        d.printDebug("Back: ", back)
        d.printDebug("Left: ", left)
        d.printDebug("Right: ", right)
        d.printDebug("Top: ", top)
        d.printDebug("Bottom: ", bottom)
        d.debugLabel("bbox", m.translation(x+left, y, z), "left", 15*time.second)
        d.debugLabel("bbox", m.translation(x+right, y, z), "right", 15*time.second)
        d.debugLabel("bbox", m.translation(x, y+top, z), "top", 15*time.second)
        d.debugLabel("bbox", m.translation(x, y+bottom, z), "bottom", 15*time.second)
        d.debugLabel("bbox", m.translation(x, y, z+front), "front", 15*time.second)
        d.debugLabel("bbox", m.translation(x, y, z+back), "back", 15*time.second)
    end
end
]]

--[[
Originally in onVehicleLoad - removed in cleanup

--Set colliderData
vehicleInfo.collider_data = {
	baseAABB = nil,
	aabb = nil,
	last_update = -1,
	debug = {
		minLabel = s.getMapID(),
		maxLabel = s.getMapID(),
		cleanTask = nil
	}
}
collisionDetection.generateBaseAABB(vehicle_id)
]]

return collisionDetection