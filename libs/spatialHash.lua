-- Spatial hash for fast nearby-vehicle queries

---@class obb
---@field minX number
---@field minY number
---@field minZ number
---@field maxX number
---@field maxY number
---@field maxZ number

---@class bounds
---@field minX number
---@field minY number
---@field minZ number
---@field maxX number
---@field maxY number
---@field maxZ number

local spatialHash = {}

local grid = {}  ---@type table<string, table<number>>
local vehicleCells = {}      ---@type table<number, table<string>>
local largeVehicles = {}     ---@type table<number, boolean>
local vehicleCellRanges = {} ---@type table<number, table<number>>
local cellSize = 30
local maxCellsPerVehicle = 500 -- if a vehicle is in more than this many cells, treat as "large"

local function posToCell(v)
	return math.floor(v / cellSize)
end

local function cellKey(cx, cy, cz)
	return cx * 73856093 + cy * 19349663 + cz * 83492791
	--return tostring(cx)..','..tostring(cy)..','..tostring(cz)
end

--- @param bounds bounds
local function getCellRangeForBounds(bounds)
	local cx1 = posToCell(bounds.minX)
	local cy1 = posToCell(bounds.minY)
	local cz1 = posToCell(bounds.minZ)
	local cx2 = posToCell(bounds.maxX)
	local cy2 = posToCell(bounds.maxY)
	local cz2 = posToCell(bounds.maxZ)
	return cx1,cy1,cz1, cx2,cy2,cz2
end
spatialHash._getCellRangeForBounds = getCellRangeForBounds

-- Swap-remove helper for arrays
local function arrayRemoveSwap(arr, idx)
	arr[idx] = arr[#arr]
	arr[#arr] = nil
end

function spatialHash.init(size, maxCells)
	cellSize = size or 30
	if maxCells then maxCellsPerVehicle = maxCells end
	grid = {}
	vehicleCells = {}
	largeVehicles = {}
end

---  Register a vehicle by world-space AABB. Bounds must have minX,minY,minZ,maxX,maxY,maxZ
--- @param vehicle_id integer
--- @param bounds bounds
function spatialHash.addVehicleToGrid(vehicle_id, bounds)
	if not vehicle_id or not bounds then return end
	-- remove existing registration if present
	if vehicleCells[vehicle_id] or largeVehicles[vehicle_id] then
		spatialHash.removeVehicleFromGrid(vehicle_id)
	end

	local cx1,cy1,cz1, cx2,cy2,cz2 = getCellRangeForBounds(bounds)
	local cells = {}
	local count = 0
	for cx = cx1, cx2 do
		for cy = cy1, cy2 do
			for cz = cz1, cz2 do
				local k = cellKey(cx,cy,cz)
				local list = grid[k]
				if not list then
					list = {}
					grid[k] = list
				end
				list[#list+1] = vehicle_id
				cells[#cells+1] = k
				count = count + 1
				if count > maxCellsPerVehicle then
					-- too many cells, treat as a large vehicle to avoid huge registration cost
					-- cleanup cells we added
					for _,k2 in ipairs(cells) do
						local l = grid[k2]
						if l then
							for i=#l,1,-1 do
								if l[i] == vehicle_id then
									arrayRemoveSwap(l, i)
									break
								end
							end
							if #l == 0 then grid[k2] = nil end
						end
					end
					largeVehicles[vehicle_id] = true
					vehicleCells[vehicle_id] = nil
                    d.printDebug("Vehicle ",vehicle_id," is too large for spatial hash, treating as large vehicle (",count," cells)")
					return
				end
			end
		end
	end
	vehicleCells[vehicle_id] = cells
	vehicleCellRanges[vehicle_id] = { cx1,cy1,cz1, cx2,cy2,cz2 }
end

--- Removes the given vehicle_id from the spatial hash grid. Silently fails if not already present.
--- @param vehicle_id integer
function spatialHash.removeVehicleFromGrid(vehicle_id)
	if largeVehicles[vehicle_id] then
		largeVehicles[vehicle_id] = nil
		vehicleCellRanges[vehicle_id] = nil
		d.printDebug("Removed large vehicle ",vehicle_id," from spatial hash")
		return
	end
	local cells = vehicleCells[vehicle_id]
	if not cells then return end
	for _, k in ipairs(cells) do
		local list = grid[k]
		if list then
			for i=#list,1,-1 do
				if list[i] == vehicle_id then
					arrayRemoveSwap(list, i)
					break
				end
			end
			if #list == 0 then grid[k] = nil end
		end
	end
	vehicleCells[vehicle_id] = nil
	vehicleCellRanges[vehicle_id] = nil
end

--- @param vehicle_id integer
--- @param bounds bounds
function spatialHash.updateVehicleInGrid(vehicle_id, bounds)
	-- Only re-register if the cell range changed or large-vehicle status toggled.
	local cx1,cy1,cz1, cx2,cy2,cz2 = getCellRangeForBounds(bounds)
	local newCount = (cx2 - cx1 + 1) * (cy2 - cy1 + 1) * (cz2 - cz1 + 1)
	
	-- If currently a large vehicle
	if largeVehicles[vehicle_id] then
		if newCount <= maxCellsPerVehicle then
			-- it shrank enough to be registered normally
			largeVehicles[vehicle_id] = nil
			spatialHash.addVehicleToGrid(vehicle_id, bounds)
		else
			-- still large, no change required
			return
		end
		return
	end

	-- If currently registered in cells, compare ranges
	local oldRange = vehicleCellRanges[vehicle_id]
	if oldRange then
		local same = oldRange[1] == cx1 and oldRange[2] == cy1 and oldRange[3] == cz1
		             and oldRange[4] == cx2 and oldRange[5] == cy2 and oldRange[6] == cz2
		if same then
			-- no cell change, do nothing
			return
		end
    end
		
		
	-- Otherwise, remove existing registration and add new one
	spatialHash.removeVehicleFromGrid(vehicle_id)
	-- If newCount is too large, mark as large
	if newCount > maxCellsPerVehicle then
		largeVehicles[vehicle_id] = true
		vehicleCellRanges[vehicle_id] = nil
		return
	end
	spatialHash.addVehicleToGrid(vehicle_id, bounds)
end

function spatialHash.finalizeGridUpdate()
	-- Clear query cache
	spatialHash.queryCache = {}
	queryResults = {0,0,0,0,0}
end

--- Query nearby vehicles around a point. Returns an array of candidate vehicle IDs (deduped) and the raw count.
--- @param x number
--- @param y number
--- @param z number
--- @param queryRadius number|nil
function spatialHash.queryVehiclesNearPoint(x,y,z, queryRadius)
	local cx = posToCell(x)
	local cy = posToCell(y)
	local cz = posToCell(z)
	local cellRadius = math.ceil((queryRadius or 1) / cellSize)
	local seen = {}
	local results = {}
	for dz = -cellRadius, cellRadius do
		for dy = -cellRadius, cellRadius do
			for dx = -cellRadius, cellRadius do
				local k = cellKey(cx+dx, cy+dy, cz+dz)
				local list = grid[k]
				if list then
					for _, vid in ipairs(list) do
						if not seen[vid] then
							seen[vid] = true
							results[#results+1] = vid
						end
					end
				end
			end
		end
	end
	-- include large vehicles
	for vid,_ in pairs(largeVehicles) do
		if not seen[vid] then
			seen[vid] = true
			results[#results+1] = vid
		end
	end
	return results, #results
end

local queryResults = {}
local querySeen = {}
local min = math.min
local max = math.max
--- Queries for vehicles along a line between 2 points. The distance between them must be less than the cell size, otherwise
--- it will return inaccurate results
--- @param x1 number X of start point
--- @param y1 number Y of start point
--- @param z1 number Z of start point
--- @param x2 number X of end point
--- @param y2 number Y of end point
--- @param z2 number Z of end point
--- @return table<number> results array of vehicle IDs
--- @return number count number of vehicle IDs in results. Must use this to loop through the results to prevent overreading
function spatialHash.queryShortLine(x1,y1,z1, x2,y2,z2)
    local count = 0
	local results = queryResults
    
    -- Calculate Cell Coordinates
    local cx1, cy1, cz1 = posToCell(x1), posToCell(y1), posToCell(z1)
    local cx2, cy2, cz2 = posToCell(x2), posToCell(y2), posToCell(z2)

    -- Do simple operation if both points are in the same cell
    if cx1 == cx2 and cy1 == cy2 and cz1 == cz2 then
        -- Check if the cell exists
		local cellID = cellKey(cx1, cy1, cz1)
		local cellContents = grid[cellID]
		if cellContents then
			-- Add the cell contents to results
			for i=1, #cellContents do
				count = count + 1
				results[count] = cellContents[i]
			end
		end
    else
    	-- More in-depth search if its crossed cells
		local seen = querySeen 
    	local minX, maxX = min(cx1, cx2), max(cx1, cx2)
    	local minY, maxY = min(cy1, cy2), max(cy1, cy2)
    	local minZ, maxZ = min(cz1, cz2), max(cz1, cz2)
		
    	for x = minX, maxX do
    	    for y = minY, maxY do
				for z = minZ, maxZ do
					-- Check if the cell exists
					local cellID = cellKey(x, y, z)
					local cellContents = grid[cellID]
					if cellContents then
						-- Add the cell contents to results
						for i=1, #cellContents do
							local vid = cellContents[i]
							if not seen[vid] then
								count = count + 1
								results[count] = vid
								seen[vid] = true
							end
						end
					end
				end
			end
    	end

		-- Clear the seen table for the next run
		-- seen only has to be used in this search type because large vehicles are never in the grid and theres never
		-- duplicates in cells.
		for i=1, count do
			seen[results[i]] = nil
		end
	end

	-- Add large vehicles
	for vid,_ in pairs(largeVehicles) do
		count = count + 1
		results[count] = vid
	end

    return results, count
end

spatialHash.queryCache = {}
--- Directly accesses a cell for if you only need 1 point. Way faster than queryVehiclesNearPoint
--- @param x number
--- @param y number
--- @param z number
function spatialHash.queryVehiclesInCell(x,y,z)
	-- Directly access cell contents
	local cellID = cellKey(posToCell(x), posToCell(y), posToCell(z))
	local cacheResult = spatialHash.queryCache[cellID]
	if cacheResult then
		return cacheResult, #cacheResult
	end
	local cellContents = grid[cellID]
	-- Copy everything in the cell to a new list so the output isn't mutable
	--(which would also cause issues with adding large vehicles to the output)
	local out = {}
	if cellContents then
		for i=1, #cellContents do
			out[i] = cellContents[i]
		end
	end
	-- Add large vehicles
	for vid,_ in pairs(largeVehicles) do
		out[#out+1] = vid
	end
	spatialHash.queryCache[cellID] = out
	return out, #out
end

--- Clears the entire spatial hash grid
function spatialHash.clearGrid()
	grid = {}
	vehicleCells = {}
	largeVehicles = {}
end

--- Outputs an AABB from center+radius
--- @param cx number the center x
--- @param cy number the center y
--- @param cz number the center z
--- @param radius number the radius of the bounds
function spatialHash.boundsFromCenterRadius(cx,cy,cz, radius)
	return {
		minX = cx - radius,
		minY = cy - radius,
		minZ = cz - radius,
		maxX = cx + radius,
		maxY = cy + radius,
		maxZ = cz + radius,
	}
end

--- point-in-AABB test
--- @param x number
--- @param y number
--- @param z number
--- @param b bounds
--- @return boolean is_inside
function spatialHash.pointInBounds(x,y,z,b)
	local minX, minY, minZ = b.minX, b.minY, b.minZ
	if x < minX or y < minY or z < minZ then return false end
	local maxX, maxY, maxZ = b.maxX, b.maxY, b.maxZ
	if x > maxX or y > maxY or z > maxZ then return false end
	return true
end

--- Computes a world-space AABB from a object-oriented bounding box (OBB)
--- transforms the local AABB center and expands by |R|*halfExtents.
--- @param transform SWMatrix the vehicle/world transform matrix from s.getVehiclePos
--- @param obb obb the object-oriented bounding box
--- @return bounds worldAABB a world-space axis-aligned bounding box table {minX,minY,minZ,maxX,maxY,maxZ}
function spatialHash.boundsFromOBB(transform, obb)
	local minX, minY, minZ = obb.minX, obb.minY, obb.minZ
	local maxX, maxY, maxZ = obb.maxX, obb.maxY, obb.maxZ

	-- Local AABB center and half-extents
	local cx = 0.5 * (minX + maxX)
	local cy = 0.5 * (minY + maxY)
	local cz = 0.5 * (minZ + maxZ)
	local hx = 0.5 * (maxX - minX)
	local hy = 0.5 * (maxY - minY)
	local hz = 0.5 * (maxZ - minZ)

	-- Transform OBB to world (M * [cx,cy,cz,1])
	local m = transform
	local wcx = cx * m[1] + cy * m[5] + cz * m[9]  + m[13]
	local wcy = cx * m[2] + cy * m[6] + cz * m[10] + m[14]
	local wcz = cx * m[3] + cy * m[7] + cz * m[11] + m[15]

	-- Expand by absolute rotation times half-extents: worldHalf = |R| * half
	local abs = math.abs
	local whx = abs(m[1]) * hx + abs(m[5]) * hy + abs(m[9])  * hz
	local why = abs(m[2]) * hx + abs(m[6]) * hy + abs(m[10]) * hz
	local whz = abs(m[3]) * hx + abs(m[7]) * hy + abs(m[11]) * hz

	return {
		minX = wcx - whx,
		minY = wcy - why,
		minZ = wcz - whz,
		maxX = wcx + whx,
		maxY = wcy + why,
		maxZ = wcz + whz,
	}
end

--- outputs points which when drawn will make a outline visualizing the bounds
--- @param bounds bounds
--- @param step number the seperation between each point
function spatialHash.debugBounds(bounds, step)
	-- Returns an array of points along the 12 edges of the AABB
	local pts = {}
	step = (step and step > 0) and step or 2

	local function push(x,y,z)
		pts[#pts+1] = {x,y,z}
	end

	local function drawLine(x1,y1,z1, x2,y2,z2)
		-- Outputs points from (x1,y1,z1) to (x2,y2,z2)
		local dx,dy,dz = x2-x1, y2-y1, z2-z1
		local lenSq = dx*dx + dy*dy + dz*dz
		if lenSq == 0 then
			push(x1,y1,z1)
			return
		end
		local len = math.sqrt(lenSq)
		local segments = math.max(1, math.floor(len / step))
		for i=0, segments do
			local t = i/segments
			push(x1 + dx*t, y1 + dy*t, z1 + dz*t)
		end
	end

	local minX, minY, minZ = bounds.minX, bounds.minY, bounds.minZ
	local maxX, maxY, maxZ = bounds.maxX, bounds.maxY, bounds.maxZ

	-- 8 corners
	local c000x,c000y,c000z = minX, minY, minZ
	local c100x,c100y,c100z = maxX, minY, minZ
	local c010x,c010y,c010z = minX, maxY, minZ
	local c110x,c110y,c110z = maxX, maxY, minZ
	local c001x,c001y,c001z = minX, minY, maxZ
	local c101x,c101y,c101z = maxX, minY, maxZ
	local c011x,c011y,c011z = minX, maxY, maxZ
	local c111x,c111y,c111z = maxX, maxY, maxZ

	-- 12 edges (X-edges)
	drawLine(c000x,c000y,c000z, c100x,c100y,c100z)
	drawLine(c010x,c010y,c010z, c110x,c110y,c110z)
	drawLine(c001x,c001y,c001z, c101x,c101y,c101z)
	drawLine(c011x,c011y,c011z, c111x,c111y,c111z)
	-- 12 edges (Y-edges)  (Has more points)
	step = step / 2
	drawLine(c000x,c000y,c000z, c010x,c010y,c010z)
	drawLine(c100x,c100y,c100z, c110x,c110y,c110z)
	drawLine(c001x,c001y,c001z, c011x,c011y,c011z)
	drawLine(c101x,c101y,c101z, c111x,c111y,c111z)
	step = step * 2
	-- 12 edges (Z-edges)
	drawLine(c000x,c000y,c000z, c001x,c001y,c001z)
	drawLine(c100x,c100y,c100z, c101x,c101y,c101z)
	drawLine(c010x,c010y,c010z, c011x,c011y,c011z)
	drawLine(c110x,c110y,c110z, c111x,c111y,c111z)

	return pts
end

return spatialHash
