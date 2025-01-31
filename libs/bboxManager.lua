---[[[
--- This file handles the bounding boxs of vehicles.
--- Used to optimize expensive calculations, by avoiding calculations when a simple distance check might false positive
--- Also should elimate false-negatives with distance checks
--- 
--- May not be 100% accurate, uses component data to approximate a bounding box.
---]]]

local bboxManager = {}

function bboxManager.generateBBOX(vehicle_id)

end

function bboxManager.isInsideBBOX(vehicle_id, position)

end

return bboxManager