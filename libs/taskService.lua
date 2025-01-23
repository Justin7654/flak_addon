d = require("libs.debugging")

TaskService = {
    _tasks = {}, --Used internally
    _currentID = 0, --Used internally
}

--- @param callback function the function to call when the task is done
--- @param duration number the duration of the task in ticks
--- @param arguments table the arguments to pass to the callback
--- @return Task
function TaskService:AddTask(callback, duration, arguments)
    --- @class Task
    local task = {
        id = TaskService._currentID + 1,
        callback = callback,
        endTime = g_savedata.tickCounter + math.floor(duration),
        arguments = arguments,
        startedAt = g_savedata.tickCounter
    }
    TaskService._currentID = task.id
    TaskService._currentID = TaskService._currentID + 1
    TaskService._tasks[task.id] = task
    return task
end

--- @return table<integer, Task>
function TaskService:GetTasks()
    return TaskService._tasks
end

function TaskService:HardReset()
    TaskService._tasks = {}
    TaskService._currentID = 0
    d.printWarning("The task system has been hard reset. Any waiting tasks have been lost and will never be ran. This can cause bugs")
end

--- Call this every tick for tasks to work correctly. This can be throttled to not be every tick but that will
--- result in tasks lag and not being ran at the correct time.
function TaskService:handleTasks()
    local tickCounter = g_savedata.tickCounter
    for id, task in pairs(TaskService:GetTasks()) do
        if tickCounter >= math.floor(task.endTime) then
            task.callback(table.unpack(task.arguments))
            TaskService._tasks[id] = nil
        end
    end
end

return TaskService