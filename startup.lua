if not turtle then return end -- Only run on turtles.

-- Set the working directory, so require works properly.
-- We use this in case we get set to `disk5` or something silly like that.
shell.setDir(fs.getDir(shell.getRunningProgram()))

-- Set the package path to include the lib directory.
package.path = package.path .. ";lib/?.lua;lib/?/init.lua"

-- Optional: Set logging level:
-- local logging = require "logging"
-- logging.set_level(logging.LOG_LEVEL.DEBUG)

-- Import the turtle client.
local turmitor_client = require "turmitor_client"

-- Optional: Set whether or not the Turmitor clients are built horizontally
-- or vertically. By default, this value is "vertical".
-- turmitor_client.array_style = "horizontal"
--- 
-- Run the Turmitor client.
local ok, err = pcall(
  turmitor_client.run
)

if not ok then
  logging.create_context("startup.lua").error(err)
  logging.dump_log("log.txt")
end