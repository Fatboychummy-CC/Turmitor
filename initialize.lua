--- Initialization program for Turmitor.
--- This program acts as an aide to set up a Turmitor array.

-- This should be run on the server computer, not on one of the turtles.
if turtle then return end


package.path = package.path .. ";lib/?.lua;lib/?/init.lua"

local logging = require "logging"
logging.set_level(logging.LOG_LEVEL.DEBUG)
local init_context = logging.create_context("init")

local TurmitorServer = require "turmitor_server"

local args = table.pack(...)

-- Some crappy basic argument parsing.
local reset = false
local modem_selected = false
local modem_side
local i = 0
while i < args.n do
  i = i + 1
  if args[i] == "--reset" or args[i] == "-r" then
    reset = true
    init_context.debug("Reset argument found.")
  elseif args[i] == "--modem" or args[i] == "-m" then
    modem_selected = true
    modem_side = args[i + 1]
    i = i + 1
    init_context.debug("Modem argument found, side:", modem_side)
  end
end


-- Begin initialization, Step 1: Determine the modem side.
local set_modem = false
local selected_modem
if modem_selected then
  -- set_modem should throw an error if it is invalid.
  TurmitorServer.set_modem(modem_side)
  selected_modem = modem_side
  set_modem = true
else
  for _, side in pairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" and not peripheral.call(side, "isWireless") then
      TurmitorServer.set_modem(side)
      selected_modem = side
      set_modem = true
      break
    end
  end
end
if not set_modem then
  error("No wired modem found.", 0)
end
init_context.info("Modem set to:", selected_modem)

if reset then
  init_context.warn("Resetting turtles.")
  -- Step 2: Send a reset command, and wait a good 10 or so seconds to ensure
  -- the turtles have had time to process the command.
  TurmitorServer.steal_items()

  TurmitorServer.reset()
  init_context.info("Waiting a short amount of time to allow the turtles to process the request...")
  sleep(10)
end


while true do
  -- Step 3: Ensure no turtles are running.
  init_context.info("Stopping all turtles.")
  TurmitorServer.shutdown(300, 2)
  sleep(5)

  -- Step 4: Boot up all the turtles.
  init_context.info("Starting all turtles.")
  TurmitorServer.startup(100, 15)

  init_context.info("The turtles, while setting up, will consume concrete from any network-attached chests.")
  init_context.warn("Press the enter key to continue when all the turtles have finished starting up.")
  sleep()
  repeat
    local _, key = os.pullEvent("key")
  until key == keys.enter

  local success = false
  for j = 1, 5 do
    init_context.debug("Attempt", j, "of 5 to get the size of the turtles.")
    -- Step 5: Ensure we get a return value from get_size
    local x, y = TurmitorServer.get_size()

    if x == 0 or y == 0 then
      init_context.error("get_size returned 0, 0. Retrying in 5 seconds...")
      sleep(5)
    else
      init_context.info("get_size returned:", x, y)
      success = true
      break
    end
  end

  if success then
    break
  else
    init_context.error("Failed to get a valid size from the turtles.")
    init_context.warn("Press the enter key to repeat the startup process.")
    sleep()
    repeat
      local _, key = os.pullEvent("key")
    until key == keys.enter
  end
end

init_context.warn("Turmitor initialization complete. You may wish to double-check the array to ensure that all turtles are numbered correctly, as some minor issues can occur depending on server load and turtle count.")
