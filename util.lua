util = {}

---@param location SWMatrix
---@param distance number
---@return table<number, SWPlayer> 
function util.getPlayersNear(location, distance)
    local players = {}
    for i, player in pairs(server.getPlayers()) do
        local transform_matrix, success = server.getPlayerPos(player.id)
        if success then
            if matrix.distance(location, transform_matrix) < distance then
                table.insert(players, player)
            end
        end
    end
    return players
end


---@param location SWMatrix
---@param distance number
---@return table<number>
function util.getVehiclesNear(location, distance)
    local vehicles = {}
    for i, vehicle in pairs(g_savedata.loadedOther) do
        local transform_matrix, success = server.getVehiclePos(vehicle)
        if success then
            if matrix.distance(location, transform_matrix) < distance then
                table.insert(vehicles, vehicle)
            end
        end
    end
end

---@param list table the list to search
---@param value any the value to remove
---@return number the index of the removed value, if no values was removed then its -1
---Removes the first instance of the value from the given list
function util.removeFromList(list, value)
    for i, v in pairs(list) do
        if v == value then
            table.remove(list, i)
            return i
        end
    end
    return -1
end

return util