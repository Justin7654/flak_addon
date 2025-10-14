--[[

Flak scatter increases with distance and alt.

https://youtu.be/H8zPNMqVi2E?si=cixPLgSg4Ez3AXtc
--]]

-- Imports
sanity = require("libs.script.sanity")
util = require("libs.script.util")
d = require("libs.script.debugging")
flakMain = require("libs.flakMain")
taskService = require("libs.script.taskService")
aiming = require("libs.ai.aiming")
shrapnel = require("libs.shrapnel")
vehicleInfoManager = require("libs.vehicleInfoManager")
spatialHash = require("libs.spatialHash")

-- Data
g_savedata = {
	tickCounter = 0,
	settings = {
		simulateShrapnel = property.checkbox("Shrapnel Simulation (impacts performance)", "true"),
		ignoreWeather = property.checkbox("Weather does not affect flak accuracy",  false),
		flakShellSpeed = property.slider("Flak Shell Speed (m/s)", 100, 1000, 100, 500),
		fireRate = property.slider("Flak Fire Rate (seconds between shots)", 1, 20, 1, 4),
		minAlt = property.slider("Minimum Fire Altitude Base", 100, 700, 50, 200),
		flakAccuracyMult = property.slider("Flak Accuracy Multiplier", 0.5, 1.5, 0.1, 1),
		shrapnelSubSteps = property.slider("(ADVANCED) Shrapnel simulation substeps (multiplies performance impact for better collision detection)", 1, 4, 1, 3),
		shrapnelBombSkipping = true
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
		chat = false,
		warning = true,
		error = true,
		lead = false,
		task = false,
		shrapnel = false,
		bounds = false,
		detected_bombs = false,
		hash = false,
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

despawnedVehicleList = {} ---@type table<number, boolean> List of vehicles that have been despawned. Used to avoid weird issues with unVehicleLoad being called after onVehicleDespawn

s = server
m = matrix

matrix.emptyMatrix = matrix.translation(0,0,0)

spatialHash.init(20, 400)

function onCreate(is_world_create)
	if is_world_create then
		s.announce("ICM Flak", "Thanks for using my flak addon! Please be aware that this addon is new and may have bugs. If you encounter any issues, please report it!")
	end
end

---@param game_ticks number the number of ticks since the last onTick call (normally 1, while sleeping 400.)
function onTick(game_ticks)
	--s.announce("[]", g_savedata.tickCounter)
    g_savedata.tickCounter = g_savedata.tickCounter + 1

	--Update the spatial hash grid for loaded vehicles
	for i, vehicle_id in ipairs(g_savedata.loadedVehicles) do
		if isTickID(i, 2) then
			--d.printDebug("Updating spatial hash for vehicle ",vehicle_id)
			if shrapnel.vehicleEligableForShrapnel(vehicle_id) then
				local pos = s.getVehiclePos(vehicle_id)
				local vehicleInfo = g_savedata.vehicleInfo[vehicle_id]
				if vehicleInfo then
					local radius = vehicleInfo.collider_data.radius
					local bounds = spatialHash.boundsFromCenterRadius(pos[13], pos[14], pos[15], radius)
					spatialHash.updateVehicleInGrid(vehicle_id, bounds)
				end
			end
		end
	end

	--Loop through all flak once every 10 seconds and if they are targeting a player higher than 150m then
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
	
	sanity.idleCheck()
	taskService:handleTasks()
	d.tickDebugs()
end

function onVehicleLoad(vehicle_id)
	d.printDebug("onVehicleLoad:", vehicle_id)

	--Check if its already despawned, to avoid a weird stormworks issue
	if despawnedVehicleList[vehicle_id] then
		d.printDebug("Skipping onVehicleLoad for ",vehicle_id," as its already had onVehicleDespawn called previously")
		return
	end

	if not util.isValueInList(g_savedata.loadedVehicles, vehicle_id) then
		table.insert(g_savedata.loadedVehicles, vehicle_id)
		d.printDebug("Added vehicle ",vehicle_id," to loaded vehicles list")
	else
		d.printDebug("Vehicle ",vehicle_id," is already in loaded vehicles list. This may happen when a save is loaded")
	end

	--Change flak simulation status
	local isFlak, flakData = flakMain.vehicleIsInSpawnedFlak(vehicle_id)
	if isFlak and flakData then
		flakData.simulating = true
		d.printDebug("Set flak ",flakData.vehicle_id," to simulating")
	end

	--Complete setup if needed
	vehicleInfoManager.completeVehicleSetup(vehicle_id)

	--Add to spatial hash grid
	if shrapnel.vehicleEligableForShrapnel(vehicle_id) then
		local pos = s.getVehiclePos(vehicle_id)
		local vehicleInfo = g_savedata.vehicleInfo[vehicle_id]
		local radius = vehicleInfo.collider_data.radius
		local bounds = spatialHash.boundsFromCenterRadius(pos[13], pos[14], pos[15], radius)
		spatialHash.addVehicleToGrid(vehicle_id, bounds)
	end
end

function onVehicleSpawn(vehicle_id, peer_id, x, y, z, group_cost, group_id)
	d.printDebug("onVehicleSpawn:", vehicle_id)
	--Set vehicle data
	vehicleInfoManager.initNewVehicle(vehicle_id, peer_id, group_id)
end

function onGroupSpawn(group_id, peer_id, x, y, z, group_cost)
	d.printDebug("onGroupSpawn:", group_id)
	--Add to flak list if its flak
	local vehicle_group = s.getVehicleGroup(group_id)
	local main_vehicle_id = vehicle_group[1]
	if flakMain.isVehicleFlak(main_vehicle_id) then
		flakMain.addVehicleToSpawnedFlak(main_vehicle_id)
	end
end

function onVehicleUnload(vehicle_id)
	d.printDebug("onVehicleUnload:", vehicle_id)
	local index = util.removeFromList(g_savedata.loadedVehicles, vehicle_id)

	--Change flak simulating status
	local isFlak, flakData = flakMain.vehicleIsInSpawnedFlak(vehicle_id)
	if isFlak and flakData then
		flakData.simulating = false
		d.printDebug("Set flak ",flakData.vehicle_id," to not simulating")
	end

	--Remove from spatial hash grid
	spatialHash.removeVehicleFromGrid(vehicle_id)
end

function onVehicleDespawn(vehicle_id)
	d.printDebug("onVehicleDespawn:", vehicle_id)
	--Attempt to remove it from the flak list
	is_success = flakMain.removeVehicleFromFlak(vehicle_id)
	--Attempt to remove it from the loadedVehicles list
	local i = util.removeFromList(g_savedata.loadedVehicles, vehicle_id)
	if i ~= -1 then
		d.printDebug("Removed vehicle ",vehicle_id," from loaded vehicles list")
	end
	--Delete the vehicle info
	vehicleInfoManager.cleanVehicleData(vehicle_id)
	--Remove from spatial hash grid
	spatialHash.removeVehicleFromGrid(vehicle_id)
	--Add to despawned list to avoid weird issues with onVehicleUnload being called after this
	despawnedVehicleList[vehicle_id] = true
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, prefix, command, ...)
	if string.lower(prefix) ~= "?flak" then
		return
	end

	command = string.lower(command or "")

	args = {...}
	if command == "debug" then
		args[1] = args[1] or "none"
		debugType = string.lower(args[1])
		success = d.toggleDebug(debugType)
		if not success then
			s.announce("[Flak Commands]", "Debug mode not found; current configuration:\n"..util.tableToString(g_savedata.debug))
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
		sanity.checkAll()
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
	elseif command == "manbulletspeed" and args[1] then
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
		chosenKey = string.lower(args[1] or "")
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
		local velocity = args[1]
		if velocity ~= nil then
			velocity = tonumber(velocity) or -10
		else
			velocity = -10
		end
		local playerPos = s.getPlayerPos(user_peer_id)
		playerPos[14] = playerPos[14] + 5 --Move it up 5m
		shrapnel.spawnShrapnel(playerPos, 0, velocity, 0)
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
		local runTimes = 700*1000
		local start1 = s.getTimeMillisec()
		for i=1, runTimes do
			math.randomseed(i)
			local futureX, futureY, futureZ = math.random(-9000,9000), math.random(-100,100), math.random(-9000,9000)
			local posX, posY, posZ = futureX+math.random(-80,80), futureY+math.random(-80,80), futureZ+math.random(-80,80)
			if math.abs(futureX - posX) < 30 and math.abs(futureY - posY) < 30 and math.abs(futureZ - posZ) < 30 then
				-- Do nothing
			end
		end
		local end1 = s.getTimeMillisec()
		local radius = 30
    	local radiusSq = radius * radius
		local start2 = s.getTimeMillisec()
		for i=1, runTimes do
			math.randomseed(i)
			local futureX, futureY, futureZ = math.random(-9000,9000), math.random(-100,100), math.random(-9000,9000)
			local posX, posY, posZ = futureX+math.random(-80,80), futureY+math.random(-80,80), futureZ+math.random(-80,80)
			local dx = futureX - posX
            local dy = futureY - posY
            local dz = futureZ - posZ
			if (dx*dx + dy*dy + dz*dz) < radiusSq then
				-- Do nothing
			end
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