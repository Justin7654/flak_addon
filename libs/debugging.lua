--[[
  Handles debugging of the addon
--]]

debugging = {}
utils = require("libs.utils")

function debugging.tickDebug()
    --Tick lead debug
    if g_savedata.debug.lead then
        --Get the current tick cleanup list
        local cleanupList = g_savedata.debugVariables.lead.mapLabels[g_savedata.tickCounter]
        
        --Delete the debug labels
        if cleanupList ~= nil then
            for _, ui_id in ipairs(cleanupList) do
                server.removePopup(-1, ui_id)
            end
        end
        g_savedata.debugVariables.lead.mapLabels[g_savedata.tickCounter] = nil --Delete it so it gets garbage collected. We will never need this info again
    elseif util.getTableLength(g_savedata.debugVariables.lead.mapLabels) > 0 then
        --Clean them up
        for i, v in pairs(g_savedata.debugVariables.lead.mapLabels) do
            debugging.printDebug("Removing ")
            for _, ui_id in ipairs(v) do
                debugging.printDebug("Removing map label ", ui_id)
                server.removePopup(-1, ui_id)
            end
        end
        g_savedata.debugVariables.lead.mapLabels = {}
    end
end

--- @param debugMode string the debug mode to check
--- @param position SWMatrix the position to place the label
--- @param text string the text to display
--- @param length number the length of time to display the label in ticks
--- @return number|nil ui_id the id of the ui element generated
function debugging.debugLabel(debugMode, position, text, length)
    if not g_savedata.debug[debugMode] then
        return
    end
    local x,y,z = matrix.position(position)
    local ui_id = s.getMapID()
    server.setPopup(-1, ui_id, "", true, text, x,y,z, 9999)
    if g_savedata.debugVariables.lead.mapLabels[g_savedata.tickCounter+length] == nil then
        g_savedata.debugVariables.lead.mapLabels[g_savedata.tickCounter+length] = {}
    end
    table.insert(g_savedata.debugVariables.lead.mapLabels[g_savedata.tickCounter+length], 1, ui_id)
end

--Each argument is converted to a string and added together to make the message
function debugging.printDebug(...)
	if not g_savedata.debug.chat then
		return
	end
	local msg = table.concat({...}, "")
	s.announce("[Flak Debug]", msg)
end

--- @param errType string the displayed error type
--- @param ... any the error message
function debugging.printError(errType, ...)
    if not g_savedata.debug.error then
        return
    end
    local msg = table.concat({...}, "")
    s.announce("[Flak "..errType.." Error]", msg)
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