local TurmitorHelper = require "turmitor_helper"
local TurmitorCommunication = require "turmitor_communication"
local TurmitorControl = require "turmitor_control"

---@class TurmitorMainPlugin : Plugin
local TurmitorMainPlugin = {
  name = "Turmitor Main",
  description = "The main manager for Turmitor.",
  author = "Fatboychummy",
  version = "0.0.1",
}

function TurmitorMainPlugin.init()
  ---@type plugin_thready
  local thready = thready ---@diagnostic disable-line: undefined-global
  ---@type plugin_context_loader
  local loader = loader ---@diagnostic disable-line: undefined-global
  ---@type logging-log_context
  local logger = logger ---@diagnostic disable-line: undefined-global

  if turtle then
    -- Initialize as turtle
    logger.info("Initializing Turmitor Turtle.")
    TurmitorHelper.determine_position()
    TurmitorHelper.face_correct_direction()
    while not TurmitorHelper.grab_concrete() do
      logger.info("Waiting for concrete.")
      sleep(5)
    end
    TurmitorHelper.save()
    logger.info("Turmitor Turtle initialized.")

    logger.info("Launching communication handler.")
    local x, y = TurmitorHelper.get_position()
    TurmitorCommunication.set_modem("back")

    local function wrapper(color)
      if color == "reset" then
        -- Reset the turtle by wiping the data file and shutting down.
        TurmitorHelper.reset()
      else
        TurmitorHelper.place_concrete_color(color)
      end
    end

    thready.spawn(
      TurmitorCommunication.turtle_handle_comms, x, y, wrapper
    )

    logger.info("Placing black screen.")
    -- And then clear the canvas by placing black concrete.
    TurmitorHelper.place_concrete_color("black")
  else
    -- Launch as control
    logger.info("Initializing Turmitor Control.")
    TurmitorCommunication.set_modem("bottom")
    TurmitorControl.start_turtles()
  end
end

function TurmitorMainPlugin.run()
  ---@type plugin_thready
  local thready = thready ---@diagnostic disable-line: undefined-global
  ---@type plugin_context_loader
  local loader = loader ---@diagnostic disable-line: undefined-global
  ---@type logging-log_context
  local logger = logger ---@diagnostic disable-line: undefined-global

  if not turtle then
    while true do
      print("Enter color.")write("> ")
      local color = read() --[[@as string]]
      if TurmitorHelper.color_map[color] then
        TurmitorCommunication.send_color_clear(color)
      elseif color == "take_concrete" then
        TurmitorControl.steal_concrete()
        os.queueEvent("terminate")
      elseif color == "wipe_turtles" then
        TurmitorCommunication.transmit_reset()
        sleep(3)
        --TurmitorControl.stop_turtles()
        --os.queueEvent("terminate")
      end
    end
  end
end

function TurmitorMainPlugin.teardown()
  ---@type plugin_thready
  local thready = thready ---@diagnostic disable-line: undefined-global
  ---@type plugin_context_loader
  local loader = loader ---@diagnostic disable-line: undefined-global
  ---@type logging-log_context
  local logger = logger ---@diagnostic disable-line: undefined-global
  -- ...
end

return TurmitorMainPlugin