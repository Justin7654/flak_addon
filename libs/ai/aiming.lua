--[[
Handles ai target leading and collecting position points for the leading
--]]

aiming = {}
d = require("libs.debugging")

--- @alias RecentPositionData table<integer, PositionData>

--- @class PositionData
--- @field pos SWMatrix the position of the target at the time
--- @field time number the g_savedata tickCounter when the position was recorded

--- @return RecentPositionData
function aiming.newRecentPositionData()
    return {}
end

--- @param RecentPositionData RecentPositionData the table to add the position data to
--- @param pos SWMatrix the position to add to the table
--- @return RecentPositionData newData the modified data
function aiming.addPositionData(RecentPositionData, pos)
    table.insert(RecentPositionData, {pos = pos, time = g_savedata.tickCounter})
    if #RecentPositionData > 3 then
        table.remove(RecentPositionData, 1)
    end
    return RecentPositionData
end

--- @param RecentPositionData RecentPositionData
--- @return boolean isFull
function aiming.isPositionDataFull(RecentPositionData)
    return #RecentPositionData >= 3
end

--- @param positionData PositionData
---@param futureTicks number
function aiming.predictPosition(positionData, futureTicks)
    -- Check if there are at least 3 points for velocity and acceleration calculation
    if #positionData < 3 then
        d.printDebug("At least 3 data points are required for prediction.")
        return matrix.translation(0, 0, 0)
    end

    -- Extract the last three points from the data
    local p3, p2, p1 = positionData[#positionData], positionData[#positionData - 1], positionData[#positionData - 2]

    -- Extract positions and times
    local x1, y1, z1 = matrix.position(p1.pos)
    local x2, y2, z2 = matrix.position(p2.pos)
    local x3, y3, z3 = matrix.position(p3.pos)

    local t1, t2, t3 = p1.time, p2.time, p3.time

    -- Calculate velocities (v = dx / dt)
    local vx1 = (x2 - x1) / (t2 - t1)
    local vy1 = (y2 - y1) / (t2 - t1)
    local vz1 = (z2 - z1) / (t2 - t1)

    local vx2 = (x3 - x2) / (t3 - t2)
    local vy2 = (y3 - y2) / (t3 - t2)
    local vz2 = (z3 - z2) / (t3 - t2)

    -- Calculate accelerations (a = dv / dt)
    local ax = (vx2 - vx1) / (t3 - t2)
    local ay = (vy2 - vy1) / (t3 - t2)
    local az = (vz2 - vz1) / (t3 - t2)

    -- Current velocity (from the latest two points)
    local vx = vx2
    local vy = vy2
    local vz = vz2

    -- Current position (latest point)
    local x, y, z = x3, y3, z3

    -- Future time interval in seconds
    local dt = futureTicks-- / 60 -- Convert ticks to seconds (60 ticks per second)

    -- Predict future position using quadratic formula: x_f = x + v * dt + 0.5 * a * dt^2
    local futureX = x + vx * dt + 0.5 * ax * dt^2
    local futureY = y + vy * dt + 0.5 * ay * dt^2
    local futureZ = z + vz * dt + 0.5 * az * dt^2    

    return matrix.translation(futureX, futureY, futureZ)
end

return aiming