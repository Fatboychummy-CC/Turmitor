--- Turmitor Control Helper Methods

local expect = require "cc.expect".expect
local logging = require "logging"
local smn = require "single_modem_network"

local context = logging.create_context("control")

---@class TurmitorControl
local TurmitorControl = {}
---@fixme We need to ensure we are only grabbing turtles from one connected modem, so we don't accidentally grab turtles from other networks.

--- Start the turtles (reboots any currently running turtles, so as to make sure they are all on the same state).
function TurmitorControl.start_turtles()
  context.info("Starting turtles.")

  local turtles = table.pack(smn.find("turtle"))

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
function TurmitorControl.stop_turtles()
  context.info("Stopping turtles.")

  local turtles = table.pack(smn.find("turtle"))

  for i = 1, turtles.n do
    turtles[i].shutdown()
  end
end

--- Grab the concrete back from every turtle, and insert it into the chest.
function TurmitorControl.steal_concrete()
  local chest = smn.find("minecraft:chest") --[[@as Inventory]]
  if not chest then error("No chest found.") end

  context.info("Stealing concrete from turtles.")

  -- For each turtle...
  for _, turtle in ipairs({smn.find("turtle")}) do
    context.info("Stealing concrete from turtle ", peripheral.getName(turtle), ".")

    local parallel_pull_calls = {}

    -- For each slot of the turtle...
    for i = 1, 16 do
      -- Attempt to pull an item to the last slot of the chest.
      table.insert(parallel_pull_calls, function()
        chest.pullItems(peripheral.getName(turtle), i, nil)
      end)
    end

    parallel.waitForAll(table.unpack(parallel_pull_calls))
  end
end

--- Set the modem network to use.
---@param modem_side computerSide The side of the modem to use.
function TurmitorControl.set_modem(modem_side)
  expect(1, modem_side, "string")

  smn.set_modem(modem_side)
end

return TurmitorControl