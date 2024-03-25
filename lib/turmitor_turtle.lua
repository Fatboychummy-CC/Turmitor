--- Helper methods for the turmitor turtle.

-- Set the package path so lib is included.
package.path = package.path .. ";lib/?.lua;lib/?/init.lua"

if not turtle then
  error("This program requires a turtle to run.", 0)
end

shell.run "rm /data" -- temporary just to ensure this is working
os.setComputerLabel()
sleep(1)

local logging = require "logging"
local TurmitorHelper = require "turmitor_helper"

logging.set_level(logging.LOG_LEVEL.DEBUG)

local context = logging.create_context("turmitor_turtle")

local function main()
  context.info("Starting turmitor turtle.")

  TurmitorHelper.determine_position()

  TurmitorHelper.grab_concrete()
end

main()