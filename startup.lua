--- This program simply checks if it is running on a turtle, and if so, runs the
--- turtle redirect system. Mainly just a simple helper program to be put on a
--- startup disk.

if turtle then
  -- Get the directory of this startup program.
  local dir = fs.getDir(shell.getRunningProgram())

  -- CD into the directory of this program and run the turtle redirect system.
  shell.setDir(dir)
  shell.run("turmitor_turtle.lua")
end