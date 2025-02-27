--[[

Flak scatter increases with distance and alt.

https://youtu.be/H8zPNMqVi2E?si=cixPLgSg4Ez3AXtc
--]]

-- Imports
util = require("libs.util")
d = require("libs.debugging")
flakMain = require("libs.flakMain")
taskService = require("libs.taskService")
aiming = require("libs.ai.aiming")
shrapnel = require("libs.shrapnel")
collisionDetection = require("libs.collisionDetection")

-- Data
g_savedata = {
	tickCounter = 0,
	settings = {
		simulateShrapnel = property.checkbox("Shrapnel Simulation (impacts performance)", true),
		ignoreWeather = property.checkbox("Weather does not affect flak accuracy",  false),
		flakShellSpeed = property.slider("Flak Shell Speed (m/s)", 100, 1000, 100, 500),
		fireRate = property.slider("Flak Fire Rate (seconds between shots)", 1, 20, 1, 4),
		minAlt = property.slider("Minimum Fire Altitude Base", 100, 700, 50, 200),
		flakAccuracyMult = property.slider("Flak Accuracy Multiplier", 0.5, 1.5, 0.1, 1),
		shrapnelSubSteps = property.slider("Flak simulation substeps (SIGNIFICANT PERFORAMNCE IMPACT)", 1, 3, 2, 2),
		shrapnelBombSkipping = property.checkbox("(ADVANCED) Shrapnel optimization 1 (disables collision checks for likely bombs/missiles, very significantly improving performance)", true)
	},
	fun = {
		noPlayerIsSafe = {
			active = false,
			difficulty = 1,
			shots = 0,
			prevPlayerPositions = {} ---@type table<number, SWMatrix>
		}
	},
	spawnedFlak = {}, ---@type FlakData[]
	loadedVehicles = {}, ---@type number[]
	vehicleOwners = {},
	vehicleInfo = {}, ---@type table<number, vehicleInfo>
	debug = {
		chat = true,
		warning = true,
		error = true,
		lead = false,
		task = false,
		shrapnel = false,
		bbox = false,
		detected_bombs = false
	},
	tasks = {}, --List of all tasks
	taskCurrentID = 0, --The current ID for tasks
	taskDebugUI = server.getMapID(), --The UI_ID for the task debug UI screen
	debugLabelUI = {}, --UI_IDs for debug labels that are not in use
	debugAI = {}, --Used by debugging AI vehicles. Character IDs
	debugVoxelMaps = {}, --Used by debugging voxel positions. Vehicle IDS
	shrapnelChunks = {}, ---@type table<number, shrapnelChunk> A list of every active shrapnel object indexed by its ID
	shrapnelCurrentID = 0,
}

g_savedata.tickCounter = 0

--- @alias callbackID "freeDebugLabel" | "setPopup" | "flakExplosion" | "tickShrapnelChunk" | "debugVoxelPositions"
registeredTaskCallbacks = {
	freeDebugLabel = d.freeDebugLabel,
	setPopup = server.setPopup,
	flakExplosion = flakMain.flakExplosion,
	tickShrapnelChunk = shrapnel.tickShrapnelChunk,
	debugVoxelPositions = shrapnel.debugVoxelPositions
}

time = { -- the time unit in ticks
	second = 60,
	minute = 3600,
	hour = 216000,
	day = 5184000
}

s = server
m = matrix

matrix.emptyMatrix = matrix.translation(0,0,0)

---@class vehicleInfo
---@field needs_setup boolean whether the vehicle needs to be setup. If this is true, some data will be nil
---@field group_id number the group which this vehicle belongs to
---@field main_vehicle_id number the main vehicle of this group
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
---@field main_vehicle_id number the main vehicle of this group
---@field owner number the peer_id of the player who spawned the vehicle, or -1 if the server spawned it
---@field components SWVehicleComponents
---@field vehicle_data SWVehicleData
---@field base_voxel SWVoxelPos?
---@field collider_data colliderData
---@field mass number
---@field voxels number

---@param game_ticks number the number of ticks since the last onTick call (normally 1, while sleeping 400.)
function onTick(game_ticks)
	--s.announce("[]", g_savedata.tickCounter)
    g_savedata.tickCounter = g_savedata.tickCounter + 1

	--Loop through all flak once every 10 seconds and if they are targetting a player higher than 150m then
	local updateRate = time.second
	local fireRate = time.second*g_savedata.settings.fireRate
    for index, flak in pairs(g_savedata.spawnedFlak) do
		--Check if its time to update target data
		local updated_pos = false
		if isTickID(flak.tick_id, updateRate) then
			local targetMatrix = flakMain.getFlakTarget(flak)
			if targetMatrix ~= nil then
				aiming.addPositionData(flak.targetPositionData, targetMatrix)
				updated_pos = true
			else
				flak.targetPositionData = aiming.newRecentPositionData() --Reset it
			end
		end
		
		--Check if its time to fire
		if isTickID(flak.tick_id, fireRate) then
			--Check if theres any targets
			local sourceMatrix = flak.position
			local targetMatrix = flakMain.getFlakTarget(flak)
			
			if targetMatrix ~= nil and aiming.isPositionDataFull(flak.targetPositionData) then --Either not airborne or the AI doesnt have a target anymore. Dont fire
				--Make sure position was updated this tick
				if not updated_pos then
					d.printWarning("Did not update position this tick! This should never happen and will cause flak lead issues")
				end

				--Calculate lead
				if g_savedata.debug.lead then
					--local travelTime = flakMain.calculateTravelTime(targetMatrix, sourceMatrix)
					--local secondLead = aiming.predictPosition(flak.targetPositionData, travelTime)
					--if secondLead ~= nil then d.debugLabel("lead", secondLead, "Advanced Lead", travelTime) end
				end
				local leadMatrix = flakMain.calculateLead(flak)
				
				--Fire the flak
				if leadMatrix then
					flakMain.fireFlak(sourceMatrix, leadMatrix)
				end
			end
		end
	end

	--Tick shrapnel
	shrapnel:tickAll()
	
	--Fun Events
	if g_savedata.fun.noPlayerIsSafe.active then
		for _, player in pairs(s.getPlayers()) do
			playerPosition, success = s.getPlayerPos(player.id)
			if success and isTickID(1, math.floor(updateRate/g_savedata.fun.noPlayerIsSafe.difficulty)) or math.random(1,60) == 1 then
				flakMain.fireFlak(playerPosition, playerPosition)
				g_savedata.fun.noPlayerIsSafe.shots = g_savedata.fun.noPlayerIsSafe.shots + 1
			end
		end
	end

	for i, vehicle_id in pairs(g_savedata.loadedVehicles) do
		local vehicleInfo = g_savedata.vehicleInfo[vehicle_id]
		local isSetup, vehicleInfo = isVehicleDataSetup(vehicleInfo)
		if isSetup and vehicleInfo.collider_data.aabb then
			--Update collider data
			local playerPosition = s.getPlayerPos(0)
			local x,y,z = matrix.position(playerPosition)
			if collisionDetection.isPointInsideAABB(vehicleInfo.collider_data.aabb, x, y, z) then
				d.printDebug("Player is inside vehicle ",vehicle_id)
			else
				d.printDebug("Player is not inside vehicle ",vehicle_id)
			end
		end
	end
	
	taskService:handleTasks()
	d.tickDebugs()
end

function onVehicleLoad(vehicle_id)
	table.insert(g_savedata.loadedVehicles, vehicle_id)
	d.printDebug("Added vehicle ",vehicle_id," to loaded vehicles list")

	--Change flak simulation status
	local isFlak, flakData = flakMain.vehicleIsInSpawnedFlak(vehicle_id)
	if isFlak and flakData then
		flakData.simulating = true
		d.printDebug("Set flak ",flakData.vehicle_id," to simulating")
	end

	--Backup for if the vehicleInfo value isn't set yet. Because onVehicleSpawn doesn't call for vehicles that are there at world start
	if g_savedata.vehicleInfo[vehicle_id] == nil then
		local group_id = s.getVehicleData(vehicle_id).group_id
		g_savedata.vehicleInfo[vehicle_id] = {
			needs_setup = true,
			group_id = group_id,
			main_vehicle_id = s.getVehicleGroup(group_id)[1],
			owner = -1,
		}
		d.printDebug("Added incomplete vehicle info for ",vehicle_id)
	end

	--Setup the vehicle if its not already
	if g_savedata.vehicleInfo[vehicle_id].needs_setup then
		d.printDebug("Setting up vehicle ",vehicle_id)
		local vehicleInfo = g_savedata.vehicleInfo[vehicle_id]
		local loadedVehicleData = s.getVehicleComponents(vehicle_id)
		vehicleInfo.vehicle_data = s.getVehicleData(vehicle_id)
		vehicleInfo.components = loadedVehicleData.components
		vehicleInfo.mass = loadedVehicleData.mass
		vehicleInfo.voxels = loadedVehicleData.voxels
		vehicleInfo.needs_setup = false

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

		--Setup base voxel data
		if shrapnel.checkVoxelExists(vehicle_id, 0, 0, 0) then
			--Safe to use 0,0,0
			vehicleInfo.base_voxel = {x=0, y=0, z=0}
		else
			--In case that 0,0,0 is not a valid voxel, find the closest component and use that instead
			local com = loadedVehicleData.components
			local allComponents = util.combineList(com.batteries, com.buttons, com.dials, com.guns, com.hoppers, com.rope_hooks, com.seats, com.signs, com.tanks)
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
				--Skip if it doesn't have a 0,0,0 block, and all its components are bombs. Very high success rate and suprisingly low false positive rate
				d.debugLabel("detected_bombs", s.getVehiclePos(vehicle_id), "Likely bomb? "..tostring(#com.guns), 5*time.second)
				d.printDebug("Skipping getting base voxel for vehicle ",vehicle_id," because its likely a bomb")
			else
				d.printDebug("Set base voxel for vehicle ",vehicle_id," to ",closest.x,",",closest.y,",",closest.z)
				vehicleInfo.base_voxel = {x=closest.x, y=closest.y, z=closest.z}
			end
		end
	end

	d.printDebug("End callback")
end

function onVehicleSpawn(vehicle_id, peer_id, x, y, z, group_cost, group_id)
	--Set vehicle data
	d.printDebug("onVehicleSpawn")
	
	if g_savedata.vehicleInfo[vehicle_id] == nil then
		d.printDebug("Added incomplete vehicle info for ",vehicle_id)
		g_savedata.vehicleInfo[vehicle_id] = {
			needs_setup = true,
			group_id = group_id,
			main_vehicle_id = s.getVehicleGroup(group_id)[1],
			owner = peer_id,
		}
	end
end

function onGroupSpawn(group_id, peer_id, x, y, z, group_cost)
	--Add to flak list if its flak
	local vehicle_group = s.getVehicleGroup(group_id)
	local main_vehicle_id = vehicle_group[1]
	if flakMain.isVehicleFlak(main_vehicle_id) then
		flakMain.addVehicleToSpawnedFlak(main_vehicle_id)		
	end
end

function onVehicleUnload(vehicle_id)
	local index = util.removeFromList(g_savedata.loadedVehicles, vehicle_id)

	--Change flak simulating status
	local isFlak, flakData = flakMain.vehicleIsInSpawnedFlak(vehicle_id)
	if isFlak and flakData then
		flakData.simulating = false
		d.printDebug("Set flak ",flakData.vehicle_id," to not simulating")
	end
end

function onVehicleDespawn(vehicle_id)
	--Attempt to remove it from the flak list
	is_success = flakMain.removeVehicleFromFlak(vehicle_id)
	--Attempt to remove it from the loadedVehicles list
	local i = util.removeFromList(g_savedata.loadedVehicles, vehicle_id)
	if i ~= -1 then
		d.printDebug("Removed vehicle ",vehicle_id," from loaded vehicles list")
	end
	--Delete the vehicle info
	g_savedata.vehicleInfo[vehicle_id] = nil
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, prefix, command, ...)
	if string.lower(prefix) ~= "?flak" then
		return
	end
	command = string.lower(command)
	args = {...}
	if command == "debug" then
		if args[1] == nil then
			s.announce("[Flak Commands]", "Available modes:\nchat\nwarning\nerror\nlead\ntask")
		else
			debugType = string.lower(args[1])
			success = d.toggleDebug(debugType)
			if not success then
				s.announce("[Flak Commands]", "Debug mode not found; current configuration:\n"..util.tableToString(g_savedata.debug))
			end
		end
	elseif command == "clear" or command == "reset" then
		if args[1] == "tracking" then
			g_savedata.loadedVehicles = {}
			s.announce("[Flak Commands]", "All memory of loaded vehicles has been reset")
		elseif args[1] == "tasks" then
			taskService:HardReset()
			s.announce("[Flak Commands]", "TaskService has been reset to initial state successfully")
		else
			s.announce("[Flak Commands]", "Available reset commands:\ntracking\ntasks")
		end
	elseif command == "sanity" then
		flakMain.verifyFlakList()
	elseif command == "event" then
		if string.lower(args[1]) == "noplayerissafe" then
			g_savedata.fun.noPlayerIsSafe.active = not g_savedata.fun.noPlayerIsSafe.active
			if g_savedata.fun.noPlayerIsSafe.active then
				g_savedata.fun.noPlayerIsSafe.difficulty = tonumber(args[2]) or 1
				s.announce("[Flak Commands]", "Event 'No Player Is Safe' is now active. Difficulty: "..g_savedata.fun.noPlayerIsSafe.difficulty)
				s.notify(-1, "Emergency Alert", "All players are now being targetted by ghost flak. It is advised to stay out of the skies until this blows over.", 2)
			else
				s.announce("[Flak Commands]", "Event 'No Player Is Safe' is now inactive. In total "..g_savedata.fun.noPlayerIsSafe.shots.." shots were fired")
				s.notify(-1, "Emergency Alert", "The skies are clear of ghost flak. It is safe to fly again", 0)
				g_savedata.fun.noPlayerIsSafe.shots = 0
			end
		else
			s.announce("[Flak Commands]", "Event not found; available events:\nNoPlayerIsSafe <difficulty>")
		end
	elseif command == "manbulletspeed" and arg[1] then
		g_savedata.settings.flakShellSpeed = tonumber(args[1])
		s.announce("[Flak Commands]", "Flak shell speed set to "..g_savedata.settings.flakShellSpeed.." m/s by "..s.getPlayerName(user_peer_id))
	elseif command == "checkowners" then
		for vehicle_id, info in pairs(g_savedata.vehicleInfo) do
			if s.getVehicleSimulating(vehicle_id) then
				local position = s.getVehiclePos(vehicle_id)
				d.debugLabel("none", position, tostring(info.owner), 5*time.second)
			end
		end
	elseif command == "viewflak" then
		s.announce("[Flak Commands]", "Flak Amount: "..#g_savedata.spawnedFlak)
	elseif command == "loadedvehicles" then
		s.announce("[Flak Commands]", "Loaded Vehicles: "..table.concat(g_savedata.loadedVehicles, ", "))
	elseif command == "setting" then
		chosenKey = string.lower(args[1])
		chosenValue = args[2]
		if chosenKey == "accuracy" then
			if chosenValue then
				g_savedata.settings.flakAccuracyMult = tonumber(chosenValue)
				s.announce("[Flak Commands]", "Flak Accuracy Multiplier set to "..g_savedata.settings.flakAccuracyMult.." by "..s.getPlayerName(user_peer_id))
			else
				s.announce("[Flak Commands]", "Current Flak Accuracy Multiplier: "..tostring(g_savedata.settings.flakAccuracyMult))
			end
		end
		if chosenKey == "substeps" then
			if chosenValue then
				g_savedata.settings.shrapnelSubSteps = tonumber(chosenValue)
				s.announce("[Flak Commands]", "Flak Simulation Substeps set to "..g_savedata.settings.shrapnelSubSteps.." by "..s.getPlayerName(user_peer_id))
			else
				s.announce("[Flak Commands]", "Current Flak Simulation Substeps: "..tostring(g_savedata.settings.shrapnelSubSteps))
			end
		end
	elseif command == "testshrapnel" then
		local playerPos = s.getPlayerPos(user_peer_id)
		playerPos[14] = playerPos[14] + 5 --Move it up 5m
		shrapnel.spawnShrapnel(playerPos, 0, -10, 0)
	elseif command == "spawnshrapnel" or command == "spawnshrap" then
		local num
		if args[1] ~= nil then 
			num = tonumber(args[1])
			if num == nil then
				num = 200
			end
		else
			num = 200
		end
		local playerPos = s.getPlayerPos(user_peer_id)
		playerPos[14] = playerPos[14] + 5 --Move it up 5m
		s.announce("[Flak Commands]", "Spawned "..num.." shrapnel at your position")
		local startTime = s.getTimeMillisec()
		shrapnel.explosion(playerPos, num)
		local endTime = s.getTimeMillisec()
		d.printDebug("Spawn time: "..(endTime - startTime).."ms")
	elseif command == "testkeypads" and args[1] then
		local vehicle_id = tonumber(args[1])
		if type(vehicle_id) == "number" then
			s.announce("[Flak Commands]", "Setting keypads for vehicle "..args[1])
			local components = s.getVehicleComponents(vehicle_id)
			for i, sign in ipairs(components.components.signs) do
				local name = sign.name
				local position = sign.pos
				s.setVehicleKeypad(vehicle_id, name.."_x", position.x)
				s.setVehicleKeypad(vehicle_id, name.."_y", position.y)
				s.setVehicleKeypad(vehicle_id, name.."_z", position.z)
			end
		else
			s.announce("[Flak Commands]", "Malformed vehicle ID")
		end
	elseif command == "cleanmaps" then
		local num = 0
		for id, map in pairs(g_savedata.debugVoxelMaps) do
			d.cleanVoxelMap(id)
			num = num + 1
		end
		s.announce("[Flak Commands]", "Cleaned "..num.." voxel maps")
	elseif command == "debugvoxels" then
		shrapnel.debugVoxelPositions(tostring(args[1]))
	elseif command == "bench" then
		local vehicle_id = tonumber(args[1])
		local runTimes = 50*1000
		local testMatrix = s.getVehiclePos(vehicle_id)
		local start1 = s.getTimeMillisec()
		for i=1, runTimes do
			s.getVehiclePos(vehicle_id)
		end
		local end1 = s.getTimeMillisec()
		local start2 = s.getTimeMillisec()
		for i=1, runTimes do
			matrix.multiplyXYZW(testMatrix, 1, 5, 2, 1)
		end
		local end2 = s.getTimeMillisec()
		local time1 = (end1 - start1)/runTimes
		local time2 = (end2 - start2)/runTimes
		--Print raw
		s.announce("[Flak Commands]", "Raw time 1: "..(end1-start1).."ms\nRaw time 2: "..(end2-start2).."ms")
		--Print averaged
		s.announce("[Flak Commands]", "Time 1: "..time1.."ms\nTime 2: "..time2.."ms")
	elseif command == "printprofile" then
		local beforeState = g_savedata.debug.chat
		g_savedata.debug.chat = true
		d.printProfile()
		g_savedata.debug.chat = beforeState
	elseif command == "clearprofile" then
		local beforeState = g_savedata.debug.chat
		g_savedata.debug.chat = true
		d.clearProfile()
		g_savedata.debug.chat = beforeState
	elseif command == "checkprofile" then
		debugging.checkOpenStacks()
	else
		s.announce("[Flak Commands]", "Command not found")
	end
end

---@param msg string
function configError(msg)
    s.announce("[Flak Configuration Error]", msg)
end

---@param id integer the tick you want to check that it is
---@param rate integer the total amount of ticks, for example, a rate of 60 means it returns true once every second* (if the tps is not low)
---@return boolean isTick if its the current tick that you requested
function isTickID(id, rate)
	return (g_savedata.tickCounter + id) % rate == 0
end

---@param info vehicleInfo
---@return boolean, completeVehicleInfo
function isVehicleDataSetup(info)
    if not info.needs_setup then
		---@diagnostic disable-next-line: return-type-mismatch
        return true, info
    end
	---@diagnostic disable-next-line: return-type-mismatch
    return false, info
end