--[[
For benchmarking the addon. Can run overall tests over multiple parts of the addon to score its performance.
Doesn't have much currently as i just needed to profile 1 thing
--]]

shrapnel = require("libs.shrapnel")

local benchmark = {}

benchmarking = false
phase = 0
profileData = {}
copys = {}
currentTimeSum = 0
currentRunTime = 0

function benchmark.tick()
    if phase == 0 then
        loadedVehiclesIndex = 1
        testVehicle = nil
        zeroPosition = nil
        while loadedVehiclesIndex <= #g_savedata.loadedVehicles do
            local thisVehicle = g_savedata.loadedVehicles[loadedVehiclesIndex]
            success, vehiclePosZero = shrapnel.calculateVehicleVoxelZeroPosition(thisVehicle)
            if success then
                testVehicle = thisVehicle
                zeroPosition = vehiclePosZero
            end
            loadedVehiclesIndex = loadedVehiclesIndex + 1
        end
        if not testVehicle then return end
        playerMatrix = s.getPlayerPos(0)
        playerX, playerY, playerZ = matrix.position(playerMatrix)
        RUN_ITERS = 1000*20
        RUN_AMOUNT = 500
        HIT_POSITION = matrix.translation(math.random(-1000,1000), math.random(-1000,1000), math.random(-1000,1000))
        start_time = s.getTimeMillisec()
        for i=1, RUN_ITERS do
            --m.translation(35,235,62)
            --matrixExtras.newMatrix(nil, 35, 235, 62)
            --shrapnel.getVehicleVoxelAtWorldPosition(testVehicle, HIT_POSITION, zeroPosition)
            --spatialHash.queryVehiclesInCell(playerX, playerY, playerZ)
            shrapnel.calculateVehicleVoxelZeroPosition(testVehicle)

        end
        end_time = s.getTimeMillisec()
        currentTimeSum = currentTimeSum + (end_time - start_time)
        currentRunTime = currentRunTime + 1
        if currentRunTime < RUN_AMOUNT then
            return
        end
        averageTime = (end_time - start_time)/RUN_ITERS --currentTimeSum / (RUN_ITERS * RUN_AMOUNT)
        --d.printDebug("Current sum: ", tostring(currentTimeSum), " over ", tostring(RUN_ITERS * RUN_AMOUNT), " runs")
        oneMsCalls = 1/averageTime
        d.printDebug("Benchmark phase 0 complete: "..tostring(averageTime).."ms average, "..tostring(oneMsCalls).." calls per 1ms\n")
        phase = 1
    else
        benchmark.endBenchmark()
    end
end

--- Starts timing how long something takes
function benchmark.startProfile(id)
    if profileData[id] == nil then
        profileData[id] = {sum=0, count=0, max=0}
    end
    profileData[id].startTime = s.getTimeMillisec()
end

function benchmark.endProfile(id)
    if profileData[id] == nil or profileData[id].startTime == nil then
        d.printError("No profile data for id ",id,". Did you forget to call startProfile?")
        return
    end
    local endTime = s.getTimeMillisec()
    local duration = endTime - profileData[id].startTime
    profileData[id].sum = profileData[id].sum + duration
    profileData[id].count = profileData[id].count + 1
    if duration > profileData[id].max then
        profileData[id].max = duration
    end
    profileData[id].startTime = nil
end

function benchmark.startBenchmark()
    benchmarking = true
    -- Reset variables
    phase = 0
    profileData = {}
    currentRunTime = 0
    currentTimeSum = 0
    -- Set all the functions to the real versions
    for functionName, realFunction in pairs(copys) do
        benchmark[functionName] = realFunction
    end
end
function benchmark.endBenchmark()
    benchmarking = false
    -- Set all the functions to empty versions
    for functionName, _ in pairs(copys) do
        benchmark[functionName] = function() end
    end
end

-- Copy all the functions to the copys table
FUNCTIONS_TO_COPY = {
    "startProfile",
    "endProfile",
    "tick",
}
for _, functionName in pairs(FUNCTIONS_TO_COPY) do
    copys[functionName] = benchmark[functionName]
    benchmark[functionName] = function() end
end

return benchmark