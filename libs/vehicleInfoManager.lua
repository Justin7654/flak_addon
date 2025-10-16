--[[
    Description: Contains functions used in callbacks like onVehicleLoad to gather/cache vehicle data
]]

---@class colliderData
---@field radius number the radius of the bounding sphere around the vehicle

---@class vehicleInfo
---@field needs_setup boolean whether the vehicle needs to be setup. If this is true, some data will be nil
---@field group_id number the group which this vehicle belongs to
---@field main_vehicle_id number? the main vehicle of this group
---@field owner number the peer_id of the player who spawned the vehicle, or -1 if the server spawned it
---@field components SWVehicleComponents?
---@field vehicle_data SWVehicleData?
---@field base_voxel SWVoxelPos?
---@field collider_data colliderData?
---@field mass number?
---@field voxels number?

---@class completeVehicleInfo : vehicleInfo
---@field needs_setup boolean whether the vehicle needs to be setup. If this is true, some data will be nil
---@field group_id number the group which this vehicle belongs to
---@field main_vehicle_id number? the main vehicle of this group
---@field owner number the peer_id of the player who spawned the vehicle, or -1 if the server spawned it
---@field components SWVehicleComponents
---@field vehicle_data SWVehicleData
---@field base_voxel SWVoxelPos?
---@field collider_data colliderData
---@field mass number
---@field voxels number

d = require("libs.script.debugging")

vehicleInfoManager = {}

--- Should be called when a vehicle is spawned
--- Creates the initial vehicle info object for it inside g_savedata with all the info it can gather while unloaded
--- @param vehicle_id number the id of the vehicle
--- @param peer_id number the id of the peer who spawned the vehicle
--- @param group_id number? the id of the vehicles group given by the onVehicleSpawn callback. If nil, it will use a slower method
function vehicleInfoManager.initNewVehicle(vehicle_id, peer_id, group_id)
    if g_savedata.vehicleInfo[vehicle_id] == nil then
        --Get group_id if it is not given
        if group_id == nil then
            local vehicle_data, is_success = s.getVehicleData(vehicle_id)
            if not is_success then
                d.printWarning("Failed to get vehicle data for ",vehicle_id, " - file:", SSSWTOOL_SRC_FILE,"... line:", SSSWTOOL_SRC_LINE,"\ninitNewVehicle failed!")
                return
            end
            group_id = vehicle_data.group_id
        end
        
		local main_vehicle_id = nil
		local vehicleGroupResult, success = s.getVehicleGroup(group_id)
		if success then
			main_vehicle_id = vehicleGroupResult[1]
		end

        --Create the table
		g_savedata.vehicleInfo[vehicle_id] = {
			needs_setup = true,
			group_id = group_id,
			main_vehicle_id = main_vehicle_id,
			owner = peer_id,
		}
        d.printDebug("Added incomplete vehicle info for ",vehicle_id)
	elseif g_savedata.vehicleInfo[vehicle_id].owner == nil and peer_id ~= -1 then
        d.printDebug("Updating peer_id for vehicle ",vehicle_id," to ",peer_id)
        g_savedata.vehicleInfo[vehicle_id].owner = peer_id
    end
end

--- Can only be called while the vehicle is loaded
function vehicleInfoManager.completeVehicleSetup(vehicle_id)
    if g_savedata.vehicleInfo[vehicle_id] == nil then
        d.printDebug("completeVehicleSetup was called on ",vehicle_id," but was never initialized!")
        vehicleInfoManager.initNewVehicle(vehicle_id, -1, nil)
    end

    if g_savedata.vehicleInfo[vehicle_id] == nil or not g_savedata.vehicleInfo[vehicle_id].needs_setup then
        return
    end

	d.printDebug("Setting up vehicle ",vehicle_id)
	local vehicleInfo = g_savedata.vehicleInfo[vehicle_id]
	local loadedVehicleData = s.getVehicleComponents(vehicle_id)
	local com = loadedVehicleData.components
	local allComponents = util.combineList(com.batteries, com.buttons, com.dials, com.guns, com.hoppers, com.rope_hooks, com.seats, com.signs, com.tanks)
	vehicleInfo.vehicle_data = s.getVehicleData(vehicle_id)
	vehicleInfo.components = loadedVehicleData.components
	vehicleInfo.mass = loadedVehicleData.mass
	vehicleInfo.voxels = loadedVehicleData.voxels
	vehicleInfo.needs_setup = false

	--Decide if to process this vehicle for shrapnel based on if it has any tags (no tags mean its likely player spawned)
	--This will allow players to spawn in
	if vehicleInfo.owner == -1 and vehicleInfo.vehicle_data.tags_full ~= "" then
		return
	end

	--Setup base voxel data
    local voxel_exists = s.addDamage(vehicle_id, 0, 0, 0, 0, 0) --Same as checkVoxelExists in shrapnel.lua
	if voxel_exists then
		--Safe to use 0,0,0
		vehicleInfo.base_voxel = {x=0, y=0, z=0}
	else
		--In case that 0,0,0 is not a valid voxel, find the closest component and use that instead
		local closest = {dist=math.huge, x=0, y=0, z=0}
		for _, component in pairs(allComponents) do
			local x,y,z = component.pos.x, component.pos.y, component.pos.z
			local dist = x*x + y*y + z*z
			if dist < closest.dist then
				closest.dist = dist
				closest.x = x
				closest.y = y
				closest.z = z
			end
		end
		
		if #allComponents == 0 then
			d.printDebug("Unable to get base voxel for vehicle ",vehicle_id," because it has no components")
			--TODO: Maybe brute force scan over a large area of voxels over time using tasks like how the debugVoxels command work?
		elseif g_savedata.settings.shrapnelBombSkipping and #allComponents ~= 0 and #allComponents == #com.guns then
			--Skip if it doesn't have a 0,0,0 block, and all its components are bombs. Very high success rate and surprisingly low false positive rate
			d.debugLabel("detected_bombs", s.getVehiclePos(vehicle_id), "Likely bomb? "..tostring(#com.guns), 5*time.second)
			d.printDebug("Skipping getting base voxel for vehicle ",vehicle_id," because its likely a bomb")
		else
			d.printDebug("Set base voxel for vehicle ",vehicle_id," to ",closest.x,",",closest.y,",",closest.z)
			vehicleInfo.base_voxel = {x=closest.x, y=closest.y, z=closest.z}
		end
	end

	-- Compute a bounding sphere using the center of the components' bounding box.
	if #allComponents < 2 then
		d.printDebug("Computing collider data for vehicle ",vehicle_id," with ",#allComponents," components using voxel count")
		--base it off the voxel count
		--calculate the radius of a filled cube with this many voxels
		local BLOCK_SIZE = 0.25
		local MULTIPLIER = 3
		local diameter = (vehicleInfo.voxels)^(1/3) * BLOCK_SIZE --Calculates the diameter of how big a cube would be filled with this many voxels
		local radius = diameter/2 -- radius is half the diameter
		local scaledRadius = radius * MULTIPLIER --Scale it up since its not really a filled cube, its hallow and possibly a rectangle
		vehicleInfo.collider_data = {
			radius = math.max(scaledRadius, 4),
		}
		d.printDebug(vehicleInfo.voxels)
	else
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		for _, component in pairs(allComponents) do
			local x, y, z = component.pos.x, component.pos.y, component.pos.z
			if x < minX then minX = x end
			if y < minY then minY = y end
			if z < minZ then minZ = z end
			if x > maxX then maxX = x end
			if y > maxY then maxY = y end
			if z > maxZ then maxZ = z end
		end

		-- center of bounding box
		local centerX = (minX + maxX) / 2
		local centerY = (minY + maxY) / 2
		local centerZ = (minZ + maxZ) / 2

		-- compute farthest distance from center
		local farthestSq = 0
		for _, component in pairs(allComponents) do
			local x, y, z = component.pos.x, component.pos.y, component.pos.z
			local dx = x - centerX
			local dy = y - centerY
			local dz = z - centerZ
			local d2 = dx*dx + dy*dy + dz*dz
			if d2 > farthestSq then farthestSq = d2 end
		end

		--The actual stormworks vehicle position is based off center of mass, which we cant calculate
		--Since we also can only get component positions, add a multiplier to the collider radius to be safe
		--Wings also usually lack components
		local MULTIPLIER = 2.5
		local BLOCK_SIZE = 0.25
		local radius = (math.sqrt(farthestSq)*BLOCK_SIZE) * MULTIPLIER
		vehicleInfo.collider_data = {
			radius = math.max(radius, 4),
		}
		d.printDebug("Set collider data for vehicle ",vehicle_id," to radius ",radius)
	end
end

--- Deletes the given vehicle info from g_savedata to save unnecessary space
function vehicleInfoManager.cleanVehicleData(vehicle_id)
    if g_savedata.vehicleInfo[vehicle_id] ~= nil then
        d.printDebug("Cleaning up vehicle info for ",vehicle_id)
        g_savedata.vehicleInfo[vehicle_id] = nil
    end
end

---@param info vehicleInfo
---@return boolean, completeVehicleInfo
function vehicleInfoManager.isVehicleDataSetup(info)
    if not info.needs_setup then
		---@diagnostic disable-next-line: return-type-mismatch
        return true, info
    end
	---@diagnostic disable-next-line: return-type-mismatch
    return false, info
end

return vehicleInfoManager