--- Turmitor Control Helper Methods

local logging = require "logging"

local context = logging.create_context("control")

---@fixme We need to ensure we are only grabbing turtles from one connected modem, so we don't accidentally grab turtles from other networks.

--- Start the turtles (reboots any currently running turtles, so as to make sure they are all on the same state).
local function start_turtles()
  context.info("Starting turtles.")

  local turtles = table.pack(peripheral.find("turtle"))

  for i = 1, turtles.n do
    context.info("Shutting down turtle ", i, ":", peripheral.getName(turtles[i]), ".")
    turtles[i].shutdown()
  end

  sleep(0.25)

  for i = 1, turtles.n do
    context.info("Starting turtle ", i, ":", peripheral.getName(turtles[i]), ".")
    turtles[i].turnOn()
  end
end

--- Stop the turtles (shuts down any currently running turtles).
local function stop_turtles()
  context.info("Stopping turtles.")

  local turtles = table.pack(peripheral.find("turtle"))

  for i = 1, turtles.n do
    turtles[i].shutdown()
  end
end

--- Find a position to put the specified item.
---@param item_name string The name of the item to find a space for.
---@param chest_list table The chest.list() table.
---@param chest_size integer The size of the chest.
---@return integer slot The slot to put the item in.
local function get_space_for_item(item_name, chest_list, chest_size)
  -- Prefer to put the item in a used slot. The item we want to move is in the last slot, so we ignore it (hence the -1)
  for i = 1, chest_size - 1 do
    if chest_list[i] and chest_list[i].name == item_name and chest_list[i].count < 64 then
      return i
    end
  end

  -- Otherwise find an empty slot.
  for i = 1, chest_size do
    if not chest_list[i] then
      return i
    end
  end

  error("No space for item " .. item_name .. " in chest.")
end

--- Grab the concrete back from every turtle, and insert it into the chest.
local function steal_concrete()
  local chest = peripheral.find("minecraft:chest") --[[@as Inventory]]
  local chest_name = peripheral.getName(chest)
  local size = chest.size()
  if not chest then error("No chest found.") end

  context.info("Stealing concrete from turtles.")

  -- For each turtle...
  for _, turtle in ipairs({peripheral.find("turtle")}) do
    context.info("Stealing concrete from turtle ", peripheral.getName(turtle), ".")

    local parallel_pull_calls = {}

    -- For each slot of the turtle...
    for i = 1, 16 do
      -- Attempt to pull an item to the last slot of the chest.
      table.insert(parallel_pull_calls, function()
        chest.pullItems(peripheral.getName(turtle), i, 1)
      end)
    end

    parallel.waitForAll(table.unpack(parallel_pull_calls))
  end
end

