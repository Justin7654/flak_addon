---[[[
--- This file handles the bounding boxs of vehicles.
--- Used to optimize expensive calculations, by avoiding calculations when a simple distance check might false positive
--- Also should elimate false-negatives with distance checks
--- 
--- May not be 100% accurate, uses component data to approximate a bounding box.
---]]]

local collisionDetection = {}
local d = require("libs.debugging")

--- Generates the extreme components of the vehicle, which are the components on the outmost part of the vehicle
--- @param vehicle_id number
function collisionDetection.calculateExtremes(vehicle_id)
    --Get the farthest point from the center of the vehicle
    --Size in all directions is that distance*2
end

--- Generates a AABB of the vehicle based on it facing forward in the workbench.
--- This can then be transformed later based on the vehicles transform matrix to get a rotated version
function collisionDetection.generateBaseAABB(vehicle_id)

end

--- Generates a rotated AABB based on the vehicles transform matrix and a base AABB.
--- Output is the AABB min point and max point in local space
function collisionDetection.calculateAABB(baseAABB, transformMatrix)

end

--- Checks if a given point is inside a given AABB
--- @return boolean isInside
function collisionDetection.isPointInsideAABB(point, box)

end

function collisionDetection.getBaseAABB(vehicle_id)

end

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
return collisionDetection