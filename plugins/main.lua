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
    TurmitorHelper.grab_concrete()
    TurmitorHelper.save()
    logger.info("Turmitor Turtle initialized.")

    logger.info("Launching communication handler.")
    local x, y = TurmitorHelper.get_position()
    TurmitorCommunication.set_modem("back")
    thready.spawn(
      TurmitorCommunication.turtle_handle_comms, x, y, TurmitorHelper.place_concrete_color
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