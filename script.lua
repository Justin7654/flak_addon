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

-- Data
g_savedata = {
	tickCounter = 0,
	settings = {
		simulateShrapnel = property.checkbox("Shrapnel Simulation (may impact performance)", true),
		ignoreWeather = property.checkbox("Weather does not affect flak accuracy",  false),
		flakShellSpeed = property.slider("Flak Shell Speed (m/s)", 100, 1000, 100, 500),
		fireRate = property.slider("Flak Fire Rate (seconds between shots)", 1, 20, 1, 4),
		minAlt = property.slider("Minimum Fire Altitude Base", 100, 700, 50, 200),
		flakAccuracyMult = property.slider("Flak Accuracy Multiplier", 0.5, 1.5, 0.1, 1),
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
	vehicleToMainVehicle = {}, ---@type table<number, number> Use to get the main_vehicle_id of a group from a vehicle id
	vehicleInitialOffsets = {}, ---@type table<number, SWMatrix> The initial offset this vehicle had from the main vehicle when it spawned
	debug = {
		chat = false,
		warning = true,
		error = true,
		lead = false,
		task = false,
		shrapnel = false,
	},
	tasks = {}, --List of all tasks
	taskCurrentID = 0, --The current ID for tasks
	taskDebugUI = server.getMapID(), --The UI_ID for the task debug UI screen
	debugLabelUI = {}, --UI_IDs for debug labels that are not in use
	debugAI = {} --Used by debugging AI vehicles. Character IDs
}

--- @alias callbackID "freeDebugLabel" | "flakExplosion" | "tickShrapnelChunk"
registeredTaskCallbacks = {
	freeDebugLabel = d.freeDebugLabel,
	flakExplosion = flakMain.flakExplosion,
	tickShrapnelChunk = shrapnel.tickShrapnelChunk
}

time = { -- the time unit in ticks
	second = 60,
	minute = 3600,
	hour = 216000,
	day = 5184000
}

s = server

cachedPositions = {}
--- Same as server.getVehiclePos but it caches the result for the current tick. Use when this operation might be repeated
function server.getVehiclePosCached(vehicle_id)
	if cachedPositions[vehicle_id] == nil then
		cachedPositions[vehicle_id] = s.getVehiclePos(vehicle_id)
	end
	return cachedPositions[vehicle_id]
end

---@param game_ticks number the number of ticks since the last onTick call (normally 1, while sleeping 400.)
function onTick(game_ticks)
    g_savedata.tickCounter = g_savedata.tickCounter + 1

	--Loop through all flak once every 10 seconds and if they are targetting a player higher than 150m then
	local updateRate = time.second
	local fireRate = time.second*g_savedata.settings.fireRate
    for index, flak in pairs(g_savedata.spawnedFlak) do
		--Check if its time to update target data
		local updated_pos = false
		if isTickID(flak.tick_id, 60) then
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
					d.printWarning("Did not update position this tick!")
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
	
	--Fun Events
	if g_savedata.fun.noPlayerIsSafe.active then
		for _, player in pairs(s.getPlayers()) do
			playerPosition, success = s.getPlayerPos(player.id)
			if success and isTickID(1, math.floor(rate/g_savedata.fun.noPlayerIsSafe.difficulty)) or math.random(1,60) == 1 then
				flakMain.fireFlak(playerPosition, playerPosition)
				g_savedata.fun.noPlayerIsSafe.shots = g_savedata.fun.noPlayerIsSafe.shots + 1
			end
		end
	end
	
	taskService:handleTasks()
	d.tickDebugs()
	cachedPositions = {}
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

	if g_savedata.vehicleInitialOffsets[vehicle_id] == nil then
		--Calculate offset from main vehicle so it can be put into 
		local vehicleMatrix = s.getVehiclePos(vehicle_id)
		local mainVehicleMatrix = s.getVehiclePos(g_savedata.vehicleToMainVehicle[vehicle_id])
			
		local offset = matrix.multiply(matrix.invert(mainVehicleMatrix), vehicleMatrix)

		--d.debugLabel("chat", mainVehicleMatrix, "Main", 8*time.second)
		--d.debugLabel("chat", vehicleMatrix, "Vehicle", 5*time.second)
		--d.printDebug("Calculated offset for vehicle ",vehicle_id," to be ",math.floor(x),",",math.floor(y),",",math.floor(z))
		g_savedata.vehicleInitialOffsets[vehicle_id] = offset
	end
	
	d.printDebug("End callback")
end

function onGroupSpawn(group_id, peer_id, x, y, z, group_cost)
	--Add to flak list if its flak
	local vehicle_group = s.getVehicleGroup(group_id)
	local main_vehicle_id = vehicle_group[1]
	if flakMain.isVehicleFlak(main_vehicle_id) then
		flakMain.addVehicleToSpawnedFlak(main_vehicle_id)		
	end
	local mainVehicleMatrix, success = s.getVehiclePos(main_vehicle_id)
	local p1,p2,p3 = matrix.position(mainVehicleMatrix)
	d.printDebug("Main vehicle matrix: ",p1,",",p2,",",p3)

	for _, vehicle_id in pairs(vehicle_group) do
		--Set vehicle owners
		g_savedata.vehicleOwners[vehicle_id] = peer_id
		--Set vehicleToMainVehicle
		g_savedata.vehicleToMainVehicle[vehicle_id] = main_vehicle_id
		--Set vehicleInitialOffsets
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

	--Remove from player vehicles
	g_savedata.vehicleOwners[vehicle_id] = nil
	--Remove from vehicleToMainVehicle
	g_savedata.vehicleToMainVehicle[vehicle_id] = nil
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
				s.announce("[Flak Commands]", "Debug mode not found; available modes:\nchat\nwarning\nerror\nlead\ntask")
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
		for vehicle_id, owner in pairs(g_savedata.vehicleOwners) do
			if s.getVehicleSimulating(vehicle_id) then
				local position = s.getVehiclePos(vehicle_id)
				d.debugLabel("none", position, tostring(owner), 5*time.second)
			end
		end
	elseif command == "viewtasks" then
		local text = ""
		local tasks = taskService:GetTasks()
		for _, task in pairs(tasks) do
			text = text.."\nTask "..task.id..": \n - Started At: "..tostring(task.startedAt).."\n - Ends At: "..tostring(task.endTime)
			text = text.."\n - Time elapsed: "..tostring(g_savedata.tickCounter - task.startedAt)
		end
		if text == "" then
			text = "No tasks are currently running"
		end
		s.announce("[Flak Commands]", "Tasks: "..text)
		debug.log(text)
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
	elseif command == "test1" then
		local playerPos = s.getPlayerPos(user_peer_id)
		playerPos[14] = playerPos[14] + 5 --Move it up 5m
		shrapnel.spawnShrapnel(playerPos, 0, -10, 0)
	elseif command == "testkeypads" and args[1] then
		local vehicle_id = tonumber(args[1])
		local components = s.getVehicleComponents(vehicle_id)
		local position = components.components.signs[1].pos
		s.setVehicleKeypad(vehicle_id, "x", position.x)
		s.setVehicleKeypad(vehicle_id, "y", position.y)
		s.setVehicleKeypad(vehicle_id, "z", position.z)
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