---Contains all information pertaining to a player
---@class Playerdata
---@field index number Player index
---@field luaplayer LuaPlayer
---@field is_active boolean Is player gui open
---@field job Job Contains item requests for current job
---@field logistic_requests table<string, LogisticRequest> Active temporary logistic requests indexed by item name
---@field gui table Contains references to gui elements
---@field options table Player options

---Contains details of ghosts and requests currently being tracked by player
---@class Job
---@field area BoundingBox|nil Area selected by player, if any
---@field ghosts table<number, table> Table linking each ghost `unit_number to associated requests
---@field requests table<string, Request> Table of requests, indexed by item name
---@field requests_sorted Request[] Array of requests, sorted by required item count

---Contains details of an item request, including inventory and logistic request counts
---@class Request
---@field name string Item name
---@field count number Number of item needed
---@field inventory number Number of item currently in inventory
---@field logistic_request table Existing logistic request for item, empty if none

---Contains record of temporary logistic request set by player, with details of any prior logistic
---request for that item, to be restored when appropriate
---@class LogisticRequest
---@field slot_index number
---@field old_min number
---@field old_max number|nil
---@field new_min number
---@field is_new boolean
