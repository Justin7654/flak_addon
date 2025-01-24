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

-- Data
g_savedata = {
	tickCounter = 0,
	settings = {
		ignoreWeather = property.checkbox("Weather does not affect flak accuracy",  false),
		flakShellSpeed = property.slider("Flak Shell Speed (m/s)", 100, 1000, 100, 500),
		fireRate = property.slider("Flak Fire Rate (seconds between shots)", 1, 20, 1, 4),
		minAlt = property.slider("Minimum Fire Altitude", 100, 700, 50, 200),
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
	debug = {
		chat = false,
		warning = true,
		error = true,
		lead = false,
		task = false,
	},
	tasks = {},
	taskCurrentID = 0,
	taskDebugUI = nil,
}

time = { -- the time unit in ticks
	second = 60,
	minute = 3600,
	hour = 216000,
	day = 5184000
}

s = server


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
			local sourceMatrix, source_is_success = server.getVehiclePos(flak.vehicle_id)
			local targetMatrix = flakMain.getFlakTarget(flak)
			
			if targetMatrix ~= nil and aiming.isPositionDataFull(flak.targetPositionData) then --Either not airborne or the AI doesnt have a target anymore. Dont fire
				if source_is_success then
					--Make sure position was updated this tick
					if not updated_pos then
						d.printWarning("Did not update position this tick!")
					end

					--Calculate lead
					local travelTime = flakMain.calculateTravelTime(targetMatrix, sourceMatrix)
					local secondLead = aiming.predictPosition(flak.targetPositionData, travelTime)
					if secondLead ~= nil then d.debugLabel("lead", secondLead, "Advanced Lead", travelTime) end
					local leadMatrix = flakMain.calculateLead(flak)

					--Fire the flak
					if leadMatrix then
						flakMain.fireFlak(sourceMatrix, leadMatrix)
					end
				else
					d.printError("Fire", "Flak vehicle ",flak.vehicle_id," failed to get position")
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
	d.printDebug("End callback")
end

function onGroupSpawn(group_id, peer_id, x, y, z, group_cost)
	--Add to flak list if its flak
	local vehicle_group = s.getVehicleGroup(group_id)
	local main_vehicle_id = vehicle_group[1]
	if flakMain.isVehicleFlak(main_vehicle_id) then
		flakMain.addVehicleToSpawnedFlak(main_vehicle_id)		
	end
	--Set vehicle owners
	for _, vehicle_id in pairs(vehicle_group) do
		g_savedata.vehicleOwners[vehicle_id] = peer_id
	end
end

function onVehicleUnload(vehicle_id)
	local index = util.removeFromList(g_savedata.loadedVehicles, vehicle_id)
	if index == -1 then
		d.printWarning("Could not remove ",vehicle_id," from loaded vehicles list when it unlaoded. Not found")
	end

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
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, prefix, command, ...)
	if string.lower(prefix) ~= "?flak" then
		return
	end
	command = string.lower(command)
	args = {...}
	if command == "debug" then
		if args[1] == nil then
			s.announce("[Flak Commands]", "Available debug modes:\nchat\nerror\nlead")
		else
			debugType = string.lower(args[1])
			success = d.toggleDebug(debugType)
			if not success then
				s.announce("[Flak Commands]", "Debug mode not found; available modes:\nchat\nerror\nlead")
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
	elseif command == "viewFlak" then
		s.announce("[Flak Commands]", "Flak Amount: "..#g_savedata.spawnedFlak)
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