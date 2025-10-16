-- Spatial hash for fast nearby-vehicle queries

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
	return tostring(cx)..','..tostring(cy)..','..tostring(cz)
end

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

-- Register a vehicle by world-space AABB. Bounds must have minX,minY,minZ,maxX,maxY,maxZ
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

function spatialHash.updateVehicleInGrid(vehicle_id, bounds)
	-- Only re-register if the cell range changed or large-vehicle status toggled.
	local cx1,cy1,cz1, cx2,cy2,cz2 = getCellRangeForBounds(bounds)
	local newCount = (cx2 - cx1 + 1) * (cy2 - cy1 + 1) * (cz2 - cz1 + 1)
	
	-- If currently a large vehicle
	if largeVehicles[vehicle_id] then
		if newCount <= maxCellsPerVehicle then
			-- it shrank enough to be registered normally
			largeVehicles[vehicle_id] = nil
			-- proceed to add into grid
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
			-- no cell-coordinate change, do nothing
			return
		end
    end
		
		
	-- Otherwise (not registered or range changed), remove existing registration and add new one
	spatialHash.removeVehicleFromGrid(vehicle_id)
	-- If newCount is too large, mark as large
	if newCount > maxCellsPerVehicle then
		largeVehicles[vehicle_id] = true
		vehicleCellRanges[vehicle_id] = nil
		return
	end
	spatialHash.addVehicleToGrid(vehicle_id, bounds)
end

-- Query nearby vehicles around a point. Returns an array of candidate vehicle IDs (deduped) and the raw count.
function spatialHash.queryVehiclesNearPoint(x,y,z, queryRadius)
	local cx = posToCell(x)
	local cy = posToCell(y)
	local cz = posToCell(z)
	local cellRadius = math.ceil((queryRadius or 0) / cellSize)
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

-- Directly accesses a cell for if you only need 1 point. Way faster than queryVehiclesNearPoint
spatialHash.queryCache = {}
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

-- Clears the entire spatial hash grid
function spatialHash.clearGrid()
	grid = {}
	vehicleCells = {}
	largeVehicles = {}
end

-- Outputs an AABB from center+radius
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

return spatialHash
