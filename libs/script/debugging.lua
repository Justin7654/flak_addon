--[[
  Handles debugging of the addon
--]]
local spatialHash = require("libs.spatialHash") --Spatial hash uses the global d variable to use debugging.lua, so no require loop happens

debugging = {}

function debugging.tickDebugs()
    if g_savedata.debug.task then
        local total = util.getTableLength(g_savedata.tasks)
        local taskDebugText = "Total Tasks: "..tostring(total).."\nTask List: \n"
        local num = 0
        for id, task in pairs(g_savedata.tasks) do
            taskDebugText = taskDebugText.."Task "..task.callback.." ("..task.id..")\nRemaining: "..tostring(g_savedata.tickCounter-task.endTime).."\n"
            num = num + 1
            if num >= 8 then
                taskDebugText = taskDebugText.."... "..(total-num).." more"
                break
            end
        end
        server.setPopupScreen(-1, g_savedata.taskDebugUI, "", true, taskDebugText, 0.6, 0)
    elseif g_savedata.taskDebugUI then
        --TODO: Rework this, this is running constantly when task debug is off
        --server.setPopupScreen(-1, g_savedata.taskDebugUI, "", false, "", 0.6, 0)
        server.removePopup(-1, g_savedata.taskDebugUI)
    end

    local BOUNDS_UPDATE_RATE = 20
    if g_savedata.debug.bounds and isTickID(0, BOUNDS_UPDATE_RATE) then
        for _, vehicle_id in pairs(g_savedata.loadedVehicles) do
            local info = g_savedata.vehicleInfo[vehicle_id]
			if info and info.collider_data and info.collider_data.radius then
				local vehiclePos = s.getVehiclePos(vehicle_id)
				local playerPos = s.getPlayerPos(0)
				local dx = vehiclePos[13] - playerPos[13]
				local dy = vehiclePos[14] - playerPos[14]
				local dz = vehiclePos[15] - playerPos[15]
				local distSq = dx*dx + dy*dy + dz*dz
				if distSq < (info.collider_data.radius * info.collider_data.radius) then
                    dist = math.sqrt(distSq)
                    roundedDist = math.floor(dist / 0.1 + 0.5) * 0.1
                    roundedRadius = math.floor(info.collider_data.radius / 0.1 + 0.5) * 0.1
					text = "Within collider radius ("..roundedDist.." / ".. roundedRadius..")"
					d.debugLabel("bounds", vehiclePos, text, BOUNDS_UPDATE_RATE, 200)
				end
			end
		end
    end

    if g_savedata.debug.hash and isTickID(0, 60) then
        for _, player_id in pairs(s.getPlayers()) do
            local pos = s.getPlayerPos(player_id.id)
            local vehicles, count = spatialHash.queryVehiclesNearPoint(pos[13], pos[14], pos[15], 1)
            local playerBounds = spatialHash.boundsFromCenterRadius(pos[13], pos[14], pos[15], 0.1)
            local playerCell = spatialHash._getCellRangeForBounds(playerBounds)
            s.announce("Hash Debug","Player "..tostring(player_id.id).." (in "..playerCell..") found "..count.." vehicles nearby: "..vehicles)
        end
    end

    if g_savedata.debug.scan then
        if g_savedata.debugBoundsScanState == -1 then
            -- Display a GUI showing the overall status
            -- Generate the text
            local scanDebugText = ""
            local header = "?flak viewscan {id} to view details\n\n"
            local pausedScans = 0
            local activeScans = 0
            local optionsText = "\nActive Scans:\n"
            for i, scanState in pairs(g_savedata.vehicleBoundScans) do
                if scanState.paused then
                    pausedScans = pausedScans + 1
                else
                    activeScans = activeScans + 1
                    -- Limit the amount so it doesn't go off the screen
                    if activeScans <= 7 then
                        minutesSinceStart = tostring(math.floor((g_savedata.tickCounter - scanState.start_tick) / (time.minute)))
                        optionsText = optionsText.."\nScan "..tostring(math.floor(scanState.scan_id)).."\n"
                        optionsText = optionsText..minutesSinceStart.."m old\n"
                        optionsText = optionsText.."Radius: "..tostring(scanState.current_radius).."\n"
                    end
                end
            end
            if activeScans == 0 then
                optionsText = optionsText.."None\n"
            end
            if activeScans > 7 then
                optionsText = optionsText.."\n... "..(activeScans-5).." more active scans\n"
            end
            header = header.."Active: "..tostring(activeScans).."\nPaused: "..tostring(pausedScans).."\nIdx: "..boundsScanner.getTickIndex().."\n"
            scanDebugText = header..optionsText
            server.setPopupScreen(-1, g_savedata.debugBoundScanUI, "", true, scanDebugText, 0.8, 0)
            --Clean debug bound labels
            if g_savedata.debugBoundScanLabelUI then
                for _, ui_id in pairs(g_savedata.debugBoundScanLabelUI) do
                    d.freeDebugLabel(-1, ui_id)
                end
                g_savedata.debugBoundScanLabelUI = nil
            end
        else
            --Instead show the details for a specific scan
            --Find the scan
            local found = false
            for i, scanState in pairs(g_savedata.vehicleBoundScans) do
                if scanState.scan_id == g_savedata.debugBoundsScanState then
                    --Generate the text
                    local scanDebugText = "To exit, type ?flak viewscan\n\n"
                    scanDebugText = scanDebugText..tostring(scanState.scan_id).."\n"
                    --Display paused or unpaused
                    scanDebugText = scanDebugText..(scanState.paused and "Paused\n" or "Active\n")
                    scanDebugText = scanDebugText.."Vehicle ID: "..tostring(scanState.vehicle_id).."\n"
                    scanDebugText = scanDebugText.."Center Voxel: {"..tostring(scanState.center_voxel[1])..","..tostring(scanState.center_voxel[2])..","..tostring(scanState.center_voxel[3]).."}\n"
                    scanDebugText = scanDebugText.."Radius: "..tostring(scanState.current_radius).."\n"
                    scanDebugText = scanDebugText.."Last Successful Radius: "..tostring(scanState.last_successful_radius).."\n"
                    scanDebugText = scanDebugText.."Best SqDist: "..tostring(scanState.best_sqdist).."\n"
                    --Add labels around the vehicle showing the current obb bounds
                    if scanState.best_bounds then
                        --Get where to put the labels
                        local vehiclePos = s.getVehiclePos(scanState.vehicle_id)
                        local worldBounds = spatialHash.boundsFromOBB(vehiclePos, scanState.best_bounds)
                        --[[
                        local corners = {
                            {minX, minY, minZ},
                            {maxX, maxY, maxZ}
                        }
                        --]]
                        local corners = spatialHash.debugBounds(worldBounds, 6)
                        local numCorners = #corners
                        --Get the UI IDs
                        if g_savedata.debugBoundScanLabelUI == nil then
                            g_savedata.debugBoundScanLabelUI = {}
                        end
                        while #g_savedata.debugBoundScanLabelUI > numCorners do
                            local ui_id = table.remove(g_savedata.debugBoundScanLabelUI)
                            d.freeDebugLabel(-1, ui_id)
                        end
                        while #g_savedata.debugBoundScanLabelUI < numCorners do
                            table.insert(g_savedata.debugBoundScanLabelUI, d.getDebugLabelID())
                        end
                        --Place each corner
                        for x, corner in pairs(corners) do
                            local ui_id = g_savedata.debugBoundScanLabelUI[x]
                            server.setPopup(-1, ui_id, "", true, "-----------", corner[1], corner[2], corner[3], 1500)
                        end
                        -- Also add if if the player is standing inside
                        local playerPos = s.getPlayerPos(0)
                        local isInBounds = spatialHash.pointInBounds(playerPos[13], playerPos[14], playerPos[15], worldBounds)
                        if isInBounds then
                            scanDebugText = scanDebugText.."Player is inside bounds\n"
                        else
                            scanDebugText = scanDebugText.."Player is outside bounds\n"
                        end
                    end

                    server.setPopupScreen(-1, g_savedata.debugBoundScanUI, "", true, scanDebugText, 0.6, 0)
                    found=true
                    break
                end
            end
            --If scan wasn't found, reset instead of freezing and doing nothing
            if not found then
                g_savedata.debugBoundsScanState = -1
            end
        end
    else
        server.removePopup(-1, g_savedata.debugBoundScanUI)
        --Clean debug bound labels
        if g_savedata.debugBoundScanLabelUI then
            for _, ui_id in pairs(g_savedata.debugBoundScanLabelUI) do
                d.freeDebugLabel(-1, ui_id)
            end
            g_savedata.debugBoundScanLabelUI = nil
        end
    end
end

--- @param debugMode string the debug mode to check
--- @param position SWMatrix the position to place the label
--- @param text string the text to display
--- @param length number the length of time to display the label in ticks
--- @param renderDistance number? the distance the label will render from in meters
--- @return number|nil ui_id the id of the ui element generated
function debugging.debugLabel(debugMode, position, text, length, renderDistance)
    if not g_savedata.debug[debugMode] and debugMode ~= "none" then
        return
    end
    if type(length) ~= "number" then
        debugging.printWarning("(debugging.debugLabel) expected number for length but got ",type(length),". Defaulted to 100")
        length = 100
    end
    if renderDistance == nil then
        renderDistance = 1200
    end
    --Get the UI_ID
    local ui_id = nil
    if #g_savedata.debugLabelUI > 0 then
        ui_id = table.remove(g_savedata.debugLabelUI)
    else
        ui_id = s.getMapID()
    end
    local x,y,z = matrix.position(position)
    server.setPopup(-1, ui_id, "", true, text, x,y,z, renderDistance)
    taskService:AddTask("freeDebugLabel", length, {-1, ui_id})
    return ui_id
end

function debugging.getDebugLabelID()
    if #g_savedata.debugLabelUI > 0 then
        return table.remove(g_savedata.debugLabelUI)
    else
        return s.getMapID()
    end
end

function debugging.freeDebugLabel(peer_id, ui_id)
    server.removePopup(peer_id, ui_id)
    table.insert(g_savedata.debugLabelUI, ui_id)
end

function debugging._argsToString(...)
    local args = {...}
    local str = ""
    for i, arg in ipairs(args) do
        if type(arg) == "table" then
            if util.getTableLength(arg) > 50 then
                str = str.."(table too large)"
            else
                str = str..util.tableToString(arg)
            end
        else
            str = str..tostring(arg)
        end
    end
    return str
end

--Each argument is converted to a string and added together to make the message
function debugging.printDebug(...)
	if not g_savedata.debug.chat then
		return
	end
	local msg = debugging._argsToString(...)
	s.announce("[Flak Debug]", msg)
    debug.log("ICM FLAK DEBUG | (d.printDebug) "..msg)
end

--- @param ... any the error message
function debugging.printWarning(...)
    if not g_savedata.debug.warning then
        return
    end
    local msg = debugging._argsToString(...)
    s.announce("[Flak Warning]", msg)
    debug.log("ICM FLAK WARNING | (d.printWarning) "..msg)
end

--- @param errType string the displayed error type
--- @param ... any the error message
function debugging.printError(errType, ...)
    if not g_savedata.debug.error then
        return
    end
    local msg = debugging._argsToString(...)
    s.announce("[Flak "..errType.." Error]", msg)
    debug.log("ICM FLAK ERROR | (d.printError) "..msg)
end

--- Pauses the tick until the given time is over. The game will freeze
function debugging.wait(seconds)
    local endTime = server.getTimeMillisec() + seconds*1000
    while server.getTimeMillisec() < endTime do
        
    end
end

--- @param mode string the debug mode to toggle
--- @return boolean is_success True if the mode was toggled
function debugging.toggleDebug(mode)
    if g_savedata.debug[mode] ~= nil then
        if g_savedata.debug[mode] then
            g_savedata.debug[mode] = false
            s.announce("[Flak Debug]", mode.." debug mode disabled")
        else
            g_savedata.debug[mode] = true
            s.announce("[Flak Debug]", mode.." debug mode enabled")
        end
        return true
    end
    return false
end

local profileData = {}
local profileSamples = {}
local sampleCounter = 1
local ticksProfiled = 0
local profiling = false

function debugging.startProfile(name)
    if profiling == false then return end

    local t = server.getTimeMillisec()
    --is_start, name, time
    profileSamples[sampleCounter]   = true
    profileSamples[sampleCounter+1] = name
    profileSamples[sampleCounter+2] = t
    sampleCounter = sampleCounter + 3
end

function debugging.endProfile(name)
    if profiling == false then return end

    local t = server.getTimeMillisec()
    --is_start, name, time
    profileSamples[sampleCounter]   = false
    profileSamples[sampleCounter+1] = name
    profileSamples[sampleCounter+2] = t
    sampleCounter = sampleCounter + 3
    --[[
    local endTime = server.getTimeMillisec()
    local treeLocation = profileData

    for i, stackData in pairs(profileStack) do
        if stackData.name == name then
            local totalTime = (endTime-stackData.startTime)
            local selfTime = totalTime - stackData.otherTime

            --Subtract overhead from self time
            selfTime = math.max(0, selfTime - profilingOverhead)

            --Add otherTime to parent
            if i > 1 then
                profileStack[i-1].otherTime = profileStack[i-1].otherTime + totalTime + profilingOverhead
            end

            --Add time data to the current functions data
            if treeLocation[name] == nil then
                ---@class timeData
                treeLocation[name] = {self=0, total=0, calls=0, children={}}
            end
            treeLocation[name].self = treeLocation[name].self + selfTime;
            treeLocation[name].total = treeLocation[name].total + totalTime;
            treeLocation[name].calls = treeLocation[name].calls + 1;

            table.remove(profileStack, i)
            return
        else
            if treeLocation[stackData.name] == nil then
                treeLocation[stackData.name] = {self=0, total=0, calls=0, children={}}
            end
            treeLocation = treeLocation[stackData.name].children
        end
    end
    --]]
end

--- To minimize overhead affecting profiling, we store samples in a flat array
--- This function flushes the gathered samples into the profileData tree, replaying it from start to end
--- as if its still being recorded live like it used to.
--- This is also really fast compared to the old one for some reason, i dont see any noticable slowdown.
function debugging.flushProfilingSamples()
    if not profiling or sampleCounter == 1 then
        return
    end
    local replayStack = {} -- { {name, startTime, otherTime} }

    for i = 1, sampleCounter - 1, 3 do
        local is_start = profileSamples[i]
        local name     = profileSamples[i + 1]
        local time     = profileSamples[i + 2]

        if is_start then
            replayStack[#replayStack + 1] = { name = name, startTime = time, otherTime = 0 }
        else
            -- find matching frame from top of stack down
            local idx
            for j = #replayStack, 1, -1 do
                if replayStack[j].name == name then
                    idx = j
                    break
                end
            end
            if idx ~= nil then
                local frame = replayStack[idx]
                local totalTime = time - frame.startTime
                local selfTime  = totalTime - frame.otherTime
                if selfTime < 0 then selfTime = 0 end

                -- walk tree according to current stack path
                local treeLocation = profileData
                for k = 1, idx - 1 do
                    local ancestorName = replayStack[k].name
                    if treeLocation[ancestorName] == nil then
                        treeLocation[ancestorName] = { self = 0, total = 0, calls = 0, children = {} }
                    end
                    treeLocation = treeLocation[ancestorName].children
                end

                if treeLocation[name] == nil then
                    treeLocation[name] = { self = 0, total = 0, calls = 0, children = {} }
                end
                treeLocation[name].self  = treeLocation[name].self  + selfTime
                treeLocation[name].total = treeLocation[name].total + totalTime
                treeLocation[name].calls = treeLocation[name].calls + 1

                -- add total time to parent otherTime
                if idx > 1 then
                    replayStack[idx - 1].otherTime = replayStack[idx - 1].otherTime + totalTime
                end

                table.remove(replayStack, idx)
            end
        end
    end

    --clear samples for next tick
    for i = 1, #profileSamples do
        profileSamples[i] = nil
    end
    sampleCounter = 1 --MUST RESET OR VERY BAD THINGS HAPPEN! (Also would cause a memory leak if didnt reset)
end

-- Call if you want this tick to be included. Call when you know somethings happening this tick
function debugging.profilingTickUpdate()
    ticksProfiled = ticksProfiled + 1
end

function debugging.printProfile()
    if not profiling then return end
    --Make a version of the data that has the total time each function took
    local aggergatedProfileData = {}
    function processAggregate(children)
        for name,v in pairs(children) do
            if aggergatedProfileData[name] == nil then
                aggergatedProfileData[name] = {self=0, total=0, calls=0}
            end
            aggergatedProfileData[name].self = aggergatedProfileData[name].self + v.self
            aggergatedProfileData[name].total = aggergatedProfileData[name].total + v.total
            aggergatedProfileData[name].calls = aggergatedProfileData[name].calls + v.calls
            processAggregate(v.children)
        end
    end
    processAggregate(profileData)
    aggergatedProfileData = util.sortNamedTable(aggergatedProfileData, function(a, b) return a.self > b.self end)

    -- Calculate average times per tick in the aggergatedProfileData
    for _, data in pairs(aggergatedProfileData) do
        data.avgSelf = math.floor((data.self / ticksProfiled) * 100 + 0.5) / 100 --Rounded to 0.01
        data.avgTotal = math.floor((data.total / ticksProfiled) * 100 + 0.5) / 100 --Rounded to 0.01
        data.avgCalls = math.floor(data.calls / ticksProfiled)
    end

    --Display the aggergated data
    local outputString = "Aggergated Data:"
    for _, timeData in ipairs(aggergatedProfileData) do
        if timeData.self > 0 then
            outputString = outputString.."\n"..tostring(timeData.name)..": "..tostring(timeData.avgSelf).."ms/tick"..
            " ("..tostring(timeData.avgCalls).." calls/tick)"
        end
    end
    
    --Display a tree visualization of the data
    local function printTree(tree, indent, prefix)
        local sortedTree = util.sortNamedTable(tree, function(a, b) return a.total > b.total end)

        for i, timeData in pairs(sortedTree) do
            local isLast = (i == #sortedTree)
            if timeData.total > 0 then
                -- Draw the branch character
                local avgTotal = math.floor((timeData.total / ticksProfiled) * 100 + 0.5) / 100 --Rounded to 0.01
                outputString = outputString.."\n"..prefix.."|->"..timeData.name..": "..tostring(avgTotal).."ms"
                
                -- Calculate unaccounted time if there are children
                local hasChildren = false
                local childrenTotal = 0
                for _, child in pairs(timeData.children) do
                    hasChildren = true
                    childrenTotal = childrenTotal + child.total
                end
                
                if hasChildren then
                    -- Determine the new prefix for children
                    local newPrefix = prefix .. "|  " --(isLast and "   " or "|  ")
                    printTree(timeData.children, indent+1, newPrefix)
                    local childrenAvgTotal = math.floor((childrenTotal / ticksProfiled) * 100 + 0.5) / 100 --Rounded to 0.01
                    local unknown = avgTotal - childrenAvgTotal
                    if unknown > 0 then
                        outputString = outputString.."\n"..newPrefix.."|->unknown: "..tostring(unknown).."ms"
                    end
                end
            end
        end
    end
    outputString = outputString.."\n \nTree data:"
    printTree(profileData, 0, "")
    
    --Print the data to chat
    --server.announce("[Profile]", outputString)

    --Print the data to the console (it doesn't support new lines)
    for line in string.gmatch(outputString, "[^\r\n]+") do
        debug.log("FLAK PROFILE        "..line)
    end
end

function debugging.clearProfile()
    profileData = {}
    for i = 1, #profileSamples do
        profileSamples[i] = nil
    end
    sampleCounter = 1
    ticksProfiled = 0
    d.printDebug("Cleared profile data")
end

local originalFunctionCopys = {startProfile=debugging.startProfile, endProfile=debugging.endProfile}
--- Overwrites startProfile and endProfile with empty functions to reduce overhead
function debugging.disableProfiling()
    for i = 1, #profileSamples do
        profileSamples[i] = nil
    end
    sampleCounter = 1
    debugging.startProfile = function() end
    debugging.endProfile = function() end
end

function debugging.enableProfiling()
    debugging.startProfile = originalFunctionCopys.startProfile
    debugging.endProfile = originalFunctionCopys.endProfile

end

function debugging._hookFunctionForProfiling(func, name)
    if not profiling then return func end
    debug.log("FLAK | Hooking function "..name)
    local originalFunction = func
    return function(...)
        debugging.startProfile(name)
        local results = {originalFunction(...)}
        debugging.endProfile(name)
        return table.unpack(results)
    end
end

if profiling then
    --Hook some of the functions in server
    --[[
    for key, value in pairs(server) do
        if type(value) == "function" and key ~= "getTimeMillisec" and key ~= "announce" then
            server[key] = debugging._hookFunctionForProfiling(value, "server."..key)
        end
    end]]
else
    debugging.disableProfiling()
end

return debugging