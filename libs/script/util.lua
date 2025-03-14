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
    for i, vehicle in pairs(g_savedata.loadedVehicles) do
        local transform_matrix, success = server.getVehiclePos(vehicle)
        if success then
            if matrix.distance(location, transform_matrix) < distance then
                table.insert(vehicles, vehicle)
            end
        end
    end
	return vehicles
end

---@param list table the list to search
---@param value any the value to search for
---@return boolean found true if the value was found, false if not
---@return number index the index of the value in the list, if not found then its -1
function util.isValueInList(list, value)
	for i, v in pairs(list) do
		if v == value then
			return true, i
		end
	end
	return false, -1
end

---@param list table the list to search
---@param value any the value to remove
---@return number index the index of the removed value, if no values was removed then its -1
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

--- returns the number of elements in a table. Credit: Toastery
--- @param t table table to get the size of
--- @return number count the size of the table
function util.getTableLength(t)
	if not t or type(t) ~= "table" then
		return 0 -- invalid input
	end

	local count = 0

	for _ in pairs(t) do -- goes through each element in the table
		count = count + 1 -- adds 1 to the count
	end

	return count -- returns number of elements
end

--- returns the total velocity (m/s) between the two matrices
function util.calculateVelocity(matrix1, matrix2, ticks_between) --Credit: Toastery
	ticks_between = ticks_between or 1
	return util.calculateEuclideanDistance(matrix1[13], matrix2[13], matrix1[15], matrix2[15], matrix1[14], matrix2[14]) * 60/ticks_between
end

---@diagnostic disable-next-line: undefined-doc-param
---@param x1 number x coordinate of position 1
---@diagnostic disable-next-line: undefined-doc-param
---@param x2 number x coordinate of position 2
---@diagnostic disable-next-line: undefined-doc-param
---@param z1 number z coordinate of position 1
---@diagnostic disable-next-line: undefined-doc-param
---@param z2 number z coordinate of position 2
---@diagnostic disable-next-line: undefined-doc-param
---@param y1 number? y coordinate of position 1 (exclude for 2D distance, include for 3D distance)
---@diagnostic disable-next-line: undefined-doc-param
---@param y2 number? y coordinate of position 2 (exclude for 2D distance, include for 3D distance)
---@return number distance the euclidean distance between position 1 and position 2
function util.calculateEuclideanDistance(...)
	local c = table.pack(...)

	local rx = c[1] - c[2]
	local rz = c[3] - c[4]

	if c.n == 4 then
		-- 2D distance
		return math.sqrt(rx*rx+rz*rz)
	end

	-- 3D distance
	local ry = c[5] - c[6]
	return math.sqrt(rx*rx+ry*ry+rz*rz)
end

function util.hasTag(tags, tag)
	if type(tags) ~= "table" then
		d.printError("(Tags.has) was expecting a table, but got a "..type(tags).." instead! searching for tag: ",tag)
		return false
	end

	for tag_index = 1, #tags do
		if tags[tag_index] == tag then
			return true
		end
	end

	return false
end

--- @param original table the table to copy
--- @return table the copied table
function util.shallowCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = value
    end
    return copy
end

--- takes in any amount of lists and combines them into one list
--- @param ... table<number> all the lists you would like to combine together
--- @return table<number> combined the combined list
function util.combineList(...)
	local combined = {}
	local lists = table.pack(...)
	for i = 1, lists.n do
		for j = 1, #lists[i] do
			table.insert(combined, lists[i][j])
		end
	end
	return combined
end

--- Returns x,y,z when given a matrix. Over 100x faster than the original function during testing
--- @param matrix SWMatrix the matrix to get the position from
--- @return number x the x position of the matrix
--- @return number y the y position of the matrix
--- @return number z the z position of the matrix
function matrix.positionFast(matrix)
	return matrix[13], matrix[14], matrix[15]
end

---Credit to toastery
--- Credit: Toastery (USE: Debugging) (Helped me find the batterys-batteries typo that i debugged for an entire 2 hours)
--- Returns a string in a format that looks like how the table would be written.
---@param t table the table you want to turn into a string
---@return string str the table but in string form.
function util.tableToString(t)

	--- @return boolean is_whole returns true if x is whole, false if not, nil if x is nil
	function isWhole(x) -- returns wether x is a whole number or not
		return math.type(x) == "integer"
	end

	if type(t) ~= "table" then
		d.printDebug(("(string.fromTable) t is not a table! type of t: %s t: %s"):format(type(t), t), true, -1)
	end

	local function tableToString(T, S, ind)
		S = S or "{"
		ind = ind or "  "

		local table_length = #T
		local table_counter = 0

		for index, value in pairs(T) do

			table_counter = table_counter + 1
			if type(index) == "number" then
				S = ("%s\n%s[%s] = "):format(S, ind, tostring(index))
			elseif type(index) == "string" and tonumber(index) and isWhole(tonumber(index)) then
				S = ("%s\n%s\"%s\" = "):format(S, ind, index)
			else
				S = ("%s\n%s%s = "):format(S, ind, tostring(index))
			end

			if type(value) == "table" then
				S = ("%s{"):format(S)
				S = tableToString(value, S, ind.."  ")
			elseif type(value) == "string" then
				S = ("%s\"%s\""):format(S, tostring(value))
			else
				S = ("%s%s"):format(S, tostring(value))
			end

			S = ("%s%s"):format(S, table_counter == table_length and "" or ",")
		end

		S = ("%s\n%s}"):format(S, string.gsub(ind, "  ", "", 1))

		return S
	end

	return tableToString(t)
end

--- Takes in a table which contains named keys and then sorts the table using the provided sorting function
--- Adds a additional key to each value named "name" which contains the original key it was stored under
--- @param inputTable table the table to sort
--- @param compareFunc function the function to use to compare the values
--- @return table<number, any> the sorted table
function util.sortNamedTable(inputTable, compareFunc)
	local sortedTable = {}
	
	for k, v in pairs(inputTable) do
		newTable = util.shallowCopy(v)
		newTable.name = k
		table.insert(sortedTable, newTable)
	end
	table.sort(sortedTable, compareFunc)
	return sortedTable
end

--- Checks if the given vehicle_id is a valid vehicle
function util.vehicleExists(vehicle_id)
	local _, success = s.getVehicleSimulating(vehicle_id)
	return success
end

return util