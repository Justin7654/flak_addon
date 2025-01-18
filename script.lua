--[[

Flak scatter increases with distance and alt.

https://youtu.be/H8zPNMqVi2E?si=cixPLgSg4Ez3AXtc
--]]

-- Imports
util = require("util")
flakMain = require("flakMain")

-- Data
g_savedata = {
	tickCounter = 0,
	settings = {
		ignoreWeather = property.checkbox("Weather does not affect flak accuracy",  false),
		realisticFlakTravelTime = property.checkbox("Simulate flak bullet physics & target lead prediction", false),
		fireRate = property.slider("Flak Fire Rate (seconds between shots)", 1, 20, 1, 4),
		minAlt = property.slider("Minimum Fire Altitude", 100, 700, 50, 200),
		flakAccuracyMult = property.slider("Flak Accuracy Multiplier", 0.1, 2, 0.1, 1),
	},
	fun = {
		noPlayerIsSafe = {
			active = false,
			difficulty = 1,
			shots = 0,
		}
	},
	loadedFlak = {}, ---@type FlakData[]
	loadedOther = {}, ---@type number[]
	queuedExplosions = {}, ---@type table<number, ExplosionData>
	debug = false
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
	local rate = time.second*g_savedata.settings.fireRate/40
    for index, flak in pairs(g_savedata.loadedFlak) do
		
		--Check if its time to fire
		if isTickID(flak.tick_id, rate) then

			--Check if theres any targets
			local targetMatrix = flakMain.getFlakTarget(flak.vehicle_id)
			
			if targetMatrix ~= nil and targetMatrix ~= flak.lastTargetMatrix then --Either not airborne or the AI doesnt have a target anymore. Dont fire
				--Fire the flak
				flakMain.fireFlak(targetMatrix)
				flak.lastTargetMatrix = targetMatrix
			end
		end
	end
	
	--Fun Events
	if g_savedata.fun.noPlayerIsSafe.active then
		for _, player in pairs(s.getPlayers()) do
			playerPosition, success = s.getPlayerPos(player.id)
			if success and isTickID(1, math.floor(rate/g_savedata.fun.noPlayerIsSafe.difficulty)) or math.random(1,60) == 1 then
				flakMain.fireFlak(playerPosition)
				g_savedata.fun.noPlayerIsSafe.shots = g_savedata.fun.noPlayerIsSafe.shots + 1
			end
		end
	end
end

function onVehicleLoad(vehicle_id)
	data, is_success = server.getVehicleSign(vehicle_id, "IS_AI_FLAK")
	if is_success and not flakMain.vehicleIsInLoadedFlak(vehicle_id) then
		flakMain.addVehicleToLoadedFlak(vehicle_id)
	elseif not is_success then
		table.insert(g_savedata.loadedOther, 1, vehicle_id)
	end
end

function onVehicleUnload(vehicle_id)
	is_success = flakMain.removeVehicleFromLoadedFlak(vehicle_id)
	if not is_success then
		util.removeFromList(g_savedata.loadedOther, vehicle_id)
	end
end

function onVehicleDespawn(vehicle_id)
	is_success = flakMain.removeVehicleFromLoadedFlak(vehicle_id)
	if not is_success then
		util.removeFromList(g_savedata.loadedOther, vehicle_id)
	end
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, prefix, command, ...)
	if string.lower(prefix) ~= "?flak" then
		return
	end
	command = string.lower(command)
	args = {...}
	if command == "debug" then
		if g_savedata.debug then
			g_savedata.debug = false
			s.announce("[Flak Commands]", "Debug mode disabled")
		elseif not g_savedata.debug then
			g_savedata.debug = true
			s.announce("[Flak Commands]", "Debug mode enabled")
		end
	elseif command == "reset" then
		if args[1] == "tracking" then
			g_savedata.loadedFlak = {}
			s.announce("[Flak Commands]", "All memory of flak vehicles has been reset")
		end
	elseif command == "sanity" then
		flakMain.verifyFlakList()
	elseif command == "num" then
		s.announce("[Flak Commands]", "There are currently "..#g_savedata.loadedFlak.." flak vehicles loaded")
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
	end
end
	
--Each argument is converted to a string and added together to make the message
function printDebug(...)
	if not g_savedata.debug then
		return
	end
	local msg = table.concat({...}, "")
	s.announce("[Flak Debug]", msg)
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