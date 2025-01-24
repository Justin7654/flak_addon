d = require("libs.debugging")
flakMain = require("libs.flakMain")

TaskService = {}

registeredCallbacks = {
    removePopup = server.removePopup,
    flakExplosion = flakMain.flakExplosion
}

--- @alias callbackID "removePopup" | "flakExplosion"

--- @param callbackID callbackID the registered ID of the function to call when the task is done
--- @param duration number the duration of the task in ticks
--- @param arguments table the arguments to pass to the callback
--- @return Task
function TaskService:AddTask(callbackID, duration, arguments)
    --- @class Task
    local task = {
        id = g_savedata.taskCurrentID + 1,
        callback = callbackID,
        endTime = g_savedata.tickCounter + math.floor(duration),
        arguments = arguments,
        startedAt = g_savedata.tickCounter
    }
    g_savedata.taskCurrentID = task.id
    g_savedata.taskCurrentID = g_savedata.taskCurrentID + 1
    g_savedata.tasks[task.id] = task
    return task
end

--- @param id string the backup name of the task to get the callback from
function TaskService:GetCallbackFromID(id)
    local callback = registeredCallbacks[id]
    if callback == nil then
        d.printError("TaskService:GetCallbackFromID", "No callback found for id ", id)
    end
    return callback
end

--- @return table<integer, Task>
function TaskService:GetTasks()
    return g_savedata.tasks
end

function TaskService:HardReset()
    g_savedata.tasks = {}
    g_savedata.taskCurrentID = 0
    d.printWarning("The task system has been hard reset. Any waiting tasks have been lost and will never be ran. This can cause bugs")
end

--- Call this every tick for tasks to work correctly. This can be throttled to not be every tick but that will
--- result in tasks lag and not being ran at the correct time.
function TaskService:handleTasks()
    local tickCounter = g_savedata.tickCounter
    for id, task in pairs(TaskService:GetTasks()) do
        if tickCounter >= math.floor(task.endTime) then
            local callbackFunc = TaskService:GetCallbackFromID(task.callback)
            if callbackFunc ~= nil then
                callbackFunc(table.unpack(task.arguments))
            end
            g_savedata.tasks[id] = nil
        end
    end
end

return TaskService