-- Quick and dirty program to manually set the position of the turtle.

if not turtle then
  error("This script is meant to be run on a turtle.", 0)
end

package.path = package.path .. ";lib/?.lua;lib/?/init.lua"

local logging = require "logging"
logging.set_level(logging.LOG_LEVEL.DEBUG)
local pos_context = logging.create_context("set_position")
local file_helper = require "file_helper":instanced()

---@diagnostic disable-next-line: inject-field -- We need to be in the root folder.
file_helper.working_directory = "data"

local x, z = ...
x = tonumber(x)
z = tonumber(z)

if not x or not z then
  error("Invalid arguments, expected two numbers.", 0)
end

pos_context.debug("Setting position to:", x, z)
file_helper:serialize("turmitor_data.lson", {x = x, z = z})
pos_context.info("Position set.")