--[[
  Handles debugging of the addon
--]]


debugging = {}

function debugging.tickDebugs()
    if g_savedata.debug.task then
        local taskDebugText = "Total Tasks: "..tostring(util.getTableLength(g_savedata.tasks)).."\nTask List: \n"
        for id, task in pairs(g_savedata.tasks) do
            taskDebugText = taskDebugText.."Task "..task.callback.." ("..task.id..")\nRemaining: "..tostring(g_savedata.tickCounter-task.endTime).."\n"
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
--- @return number|nil ui_id the id of the ui element generated
function debugging.debugLabel(debugMode, position, text, length)
    if not g_savedata.debug[debugMode] and debugMode ~= "none" then
        return
    end
    if type(length) ~= "number" then
        debugging.printWarning("(debugging.debugLabel) expected number for length but got ",type(length),". Defaulted to 100")
        length = 100
    end
    --Get the UI_ID
    local ui_id = nil
    if #g_savedata.debugLabelUI > 0 then
        ui_id = table.remove(g_savedata.debugLabelUI)
    else
        ui_id = s.getMapID()
    end
    local x,y,z = matrix.position(position)
    server.setPopup(-1, ui_id, "", true, text, x,y,z, 1200)
    taskService:AddTask("freeDebugLabel", length, {-1, ui_id})
end

function debugging.freeDebugLabel(peer_id, ui_id)
    server.removePopup(peer_id, ui_id)
    table.insert(g_savedata.debugLabelUI, ui_id)
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

return debugging