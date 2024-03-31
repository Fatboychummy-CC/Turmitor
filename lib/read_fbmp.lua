return function(filename)
  local file, err = fs.open(filename, "r")
  if not file then
    error(err, 2)
  end

  local header = file.readLine()
  if not header then
    error("Invalid file", 2)
  end

  local header_name, width = header:match("^(....)(..)$")
  if header_name ~= "FBMP" then
    error("Invalid fbmp header: " .. header_name)
  end
  width = string.unpack("<I2", width)

  local data = {}

  for line in file.readLine do
    -- expand bits to black or white
    local row = {}
    local current_pos = 1
    for i = 1, #line do
      local byte = string.unpack("<B", line, i)

      for j = 0, 7 do
        if current_pos + j > width then
          break
        end

        row[#row + 1] = bit32.extract(byte, 7-j, 1) == 1
      end
      current_pos = current_pos + 8
    end

    table.insert(data, row)
  end

  file.close()

  return data
end