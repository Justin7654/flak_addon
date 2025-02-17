--[[
  Handles debugging of the addon
--]]


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
        --server.setPopupScreen(-1, g_savedata.taskDebugUI, "", false, "", 0.6, 0)
        server.removePopup(-1, g_savedata.taskDebugUI)
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
end

function debugging.freeDebugLabel(peer_id, ui_id)
    server.removePopup(peer_id, ui_id)
    table.insert(g_savedata.debugLabelUI, ui_id)
end

--- @param id any the id of the voxel map
--- @param transform_matrix SWMatrix the matrix to place the voxel map at
--- @param debugMode string the debug that needs to be enabled
function debugging.setVoxelMap(id, transform_matrix, debugMode)
    if not g_savedata.debug[debugMode] and debugMode ~= "none" then
        return
    end
    debugging.printDebug("Setting voxel map ",id)
    if g_savedata.debugVoxelMaps[id] ~= nil then
        local is_success = s.moveVehicle(g_savedata.debugVoxelMaps[id], transform_matrix)
        d.printDebug("Move success: ",tostring(is_success))
        return
    end
    d.printDebug("Spawning")
    local addonIndex = s.getAddonIndex()
    local locationIndex = s.getLocationIndex(addonIndex, "debugVoxelMap")
    local componentIndex = 0
    local componentData, is_success = s.getLocationComponentData(addonIndex, locationIndex, componentIndex)
    if not is_success then
        debugging.printWarning("Failed to get component data for voxel map ",id,". Addon index: ",addonIndex," Location index: ",locationIndex," Component index: ",componentIndex)
        return
    end
    local componentID = componentData.id
    local primary_vehicle_id, success, vehicle_ids, group_id = s.spawnAddonVehicle(transform_matrix, addonIndex, componentID)
    g_savedata.debugVoxelMaps[id] = primary_vehicle_id
    if success then
        debugging.printDebug("Spawned voxel map ",id)
    else
        debugging.printWarning("Failed to spawn voxel map ",id)
    end
end

function debugging.cleanVoxelMap(id)
    if g_savedata.debugVoxelMaps[id] then
        local is_success = s.despawnVehicle(g_savedata.debugVoxelMaps[id], true)
        if is_success then
            g_savedata.debugVoxelMaps[id] = nil
            debugging.printDebug("Despawned voxel map ",id)
        else
            debugging.printWarning("Failed to despawn voxel map ",id)
        end
    end
end

--Each argument is converted to a string and added together to make the message
function debugging.printDebug(...)
	if not g_savedata.debug.chat then
		return
	end
	local msg = table.concat({...}, "")
	s.announce("[Flak Debug]", msg)
    debug.log("ICM FLAK DEBUG | (d.printDebug) "..msg)
end

--- @param ... any the error message
function debugging.printWarning(...)
    if not g_savedata.debug.warning then
        return
    end
    local msg = table.concat({...}, "")
    s.announce("[Flak Warning]", msg)
    debug.log("ICM FLAK WARNING | (d.printWarning) "..msg)
end

--- @param errType string the displayed error type
--- @param ... any the error message
function debugging.printError(errType, ...)
    if not g_savedata.debug.error then
        return
    end
    local msg = table.concat({...}, "")
    s.announce("[Flak "..errType.." Error]", msg)
    debug.log("ICM FLAK ERROR | (d.printError) "..msg)
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

profileStack = {} ---@type stackData[]
profileData = {}
profiling = false
function debugging.startProfile(name)
    if profiling == false then return end
    ---@class stackData
    local stackData = {name = name, otherTime = 0, startTime = s.getTimeMillisec()}
    table.insert(profileStack, stackData)
end

function debugging.endProfile(name)
    if profiling == false then return end

    for i, stackData in pairs(profileStack) do
        if stackData.name == name then
            local endTime = s.getTimeMillisec()
            local totalTime = (endTime-stackData.startTime)
            local selfTime = totalTime - stackData.otherTime

            if profileData[name] == nil then
                profileData[name] = {self=0, total=0}
            end
            profileData[name].self = profileData[name].self + selfTime;
            profileData[name].total = profileData[name].total + totalTime;

            for _, otherData in pairs(profileStack) do
                otherData.otherTime = otherData.otherTime + (totalTime - stackData.otherTime)
            end

            table.remove(profileStack, i)
        end
    end
end

function debugging.printProfile()
    local sortedProfileData = {}
    --Sort the profile data so the highest self time is first
    for name, timeData in pairs(profileData) do
        table.insert(sortedProfileData, {name = name, self = timeData.self, total = timeData.total})
    end
    table.sort(sortedProfileData, function(a, b) return a.self > b.self end)
    local myString = "Profile Data:"
    for name, timeData in ipairs(sortedProfileData) do
        myString = myString.."\n"..timeData.name..": "..tostring(timeData.self).."ms | "..tostring(timeData.total).."ms"
    end
    debugging.printDebug(myString)
end

function debugging.clearProfile()
    profileData = {}
    profileStack = {}
    d.printDebug("Cleared profile data")
end

function debugging.checkOpenStacks()
    for i in pairs(profileStack) do
        d.printWarning("Open stack: ",profileStack[i].name)
    end
end

return debugging