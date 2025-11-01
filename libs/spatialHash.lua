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
    d.printDebug("Added vehicle ",vehicle_id," to spatial hash in ",count," cells")
	vehicleCells[vehicle_id] = cells
	vehicleCellRanges[vehicle_id] = { cx1,cy1,cz1, cx2,cy2,cz2 }
end

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
		return cacheResult
	end
	local cellContents = grid[cellID] or {}
	-- Add large vehicles
	-- Needed to add result caching for this, a single large vehicle made this super slow and caching fixed it
	for vid,_ in pairs(largeVehicles) do
		cellContents[#cellContents+1] = vid
	end
	spatialHash.queryCache[cellID] = cellContents
	return cellContents
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

--- Computes a world-space AABB from a object-oriented bounding box (OBB)
--- transforms the local AABB center and expands by |R|*halfExtents.
--- @param transform SWMatrix the vehicle/world transform matrix (Stormworks 4x4)
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

return spatialHash
