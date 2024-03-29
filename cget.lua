--[[
  CraftGet by Ale32bit
  
  MIT License https://github.com/Ale32bit-CC/CraftGet/blob/master/LICENSE
]] --

local cget = {
  _VERSION = "0.0.6",
  _AUTHORS = {
    "AlexDevs"
  },
  BASE_DIR = ".craftget",
  cache = {},
  sources = {},
  packages = {},
  binDir = "bin"
}

local SOURCES =
  [[
# CraftGet sources list
# Each line is a source URL
# Comment with #
https://raw.githubusercontent.com/Ale32bit-CC/CraftGet/master/index.json
]]

local json = {
  encode = textutils.serialiseJSON,
  decode = textutils.unserialiseJSON
}

cget.cachePath = fs.combine(cget.BASE_DIR, "cache")
cget.packagesPath = fs.combine(cget.BASE_DIR, "packages")
cget.sourcesPath = fs.combine(cget.BASE_DIR, "sources")

local function fetch(url)
  local h, err = http.get(url)
  if not h then
    return nil, err
  end
  local content = h.readAll()
  h.close()
  return content
end

local function wget(url, path)
  local content, err = fetch(url)

  if not content then
    return false, err
  end

  local f = fs.open(path, "w")
  f.write(content)
  f.close()
  return true
end

-- Setup config
if not fs.exists(cget.BASE_DIR) then
  fs.makeDir(cget.BASE_DIR)
end

if not fs.exists(cget.cachePath) then
  local f = fs.open(cget.cachePath, "w")
  f.write("{}")
  f.close()
end

if not fs.exists(cget.packagesPath) then
  local f = fs.open(cget.packagesPath, "w")
  f.write("{}")
  f.close()
end

if not fs.exists(cget.sourcesPath) then
  local f = fs.open(cget.sourcesPath, "w")
  f.write(SOURCES)
  f.close()
end

if not fs.exists(fs.combine(cget.BASE_DIR, "bin")) then
  fs.makeDir(fs.combine(cget.BASE_DIR, "bin"))
end

local f = fs.open(cget.cachePath, "r")
cget.cache = textutils.unserialize(f.readAll())
f.close()

local f = fs.open(cget.packagesPath, "r")
cget.packages = textutils.unserialize(f.readAll())
f.close()

for line in io.lines(cget.sourcesPath) do
  if line:sub(1, 1) ~= "#" then
    table.insert(cget.sources, line)
  end
end

if not fs.exists(cget.binDir) then
  fs.makeDir(cget.binDir)
end

local function getPackage(address)
  for k, v in ipairs(cget.cache) do
    if v.meta.address == address then
      return v
    end
  end
end

local function installPackage(address, force) -- install packages, recursive stuff
  local pkg = getPackage(address)

  if not force and cget.packages[address] then
    if cget.packages[address].version == pkg.version then
      return true
    end
  end

  print("Installing " .. address)

  if not pkg then
    printError("Package " .. address .. " not found")
    return false
  end

  if type(pkg.files) == "table" then
    for path, url in pairs(pkg.files) do
      local ok, err = wget(url, path)
      if not ok then
        printError("Cannot fetch " .. url .. ": " .. err)
      end
    end
  end

  cget.packages[address] = pkg

  if type(pkg.dependencies) == "table" then
    for _, dAddr in ipairs(pkg.dependencies) do
      local dep = getPackage(dAddr)
      if dep then
        installPackage(dAddr)
      else
        printError("Dependency " .. dAddr .. " not found")
      end
    end
  end

  if type(pkg.autorun) == "table" then
    for _, cmd in ipairs(pkg.autorun) do
      if shell then
        shell.run(cmd)
      else
        printError('Cannot execute "' .. cmd .. '": Shell not found')
      end
    end
  end

  local f = fs.open(cget.packagesPath, "w")
  f.write(textutils.serialize(cget.packages))
  f.close()
  return true
end

local function sync()
  print("Syncing with sources...")
  local final = {}

  for i, url in ipairs(cget.sources) do
    print(i .. ": " .. url)

    local source, err = fetch(url)
    if source then
      source = json.decode(source)
      for maintainer, indexURL in pairs(source) do
        local index, err = fetch(indexURL)
        if index then
          index = json.decode(index)
          for name, pkg in pairs(index.packages) do
            pkg.meta = {
              name = name,
              address = maintainer .. "/" .. name,
              maintainer = maintainer
            }
            final[maintainer .. "/" .. name] = pkg -- Avoid duplicates
          end
        else
          printError("Cannot fetch " .. indexURL .. ": " .. err)
        end
      end
    else
      printError("Cannot fetch: " .. err)
    end
  end

  cget.cache = {}

  for address, pkg in pairs(final) do
    table.insert(cget.cache, pkg)
  end

  local f = fs.open(cget.cachePath, "w")
  f.write(textutils.serialize(cget.cache))
  f.close()

  print("Updated " .. #cget.cache .. " entries")
end

local function install(...)
  local args = {...}

  if args[1] == "-S" then
    sync()
    local newArgs = {}
    for i = 2, #args do
      table.insert(newArgs, args[i])
    end
    args = newArgs
  end

  local requestedPackages = {}
  for _, v in ipairs(args) do
    requestedPackages[v] = true
  end
  local forceYes = requestedPackages["-y"] or false
  requestedPackages["-y"] = nil

  local packages = {}
  local willInstall = {}

  for name in pairs(requestedPackages) do
    local possibilities = {}
    for _, pkg in ipairs(cget.cache) do
      if name == pkg.meta.address then
        possibilities = {pkg}
        break
      elseif name == pkg.meta.name then
        table.insert(possibilities, pkg)
      end
    end

    local pkg

    if #possibilities > 1 then
      print("There are multiple packages with the same name.")
      print("Pick the package you need:")
      for i = 1, #possibilities do
        print("- " .. i .. ": " .. possibilities[i].meta.address)
      end
      while true do
        write("> ")
        local input = tonumber(read())
        if not input or not possibilities[input] then
          printError("Invalid input")
        else
          pkg = possibilities[input]
          print("Picked " .. possibilities[input].meta.address)
          break
        end
      end
    elseif #possibilities == 1 then
      pkg = possibilities[1]
    else
      printError("Package " .. name .. " not found!")
      pkg = nil
    end

    if pkg then
      table.insert(packages, pkg.meta.address)
      table.insert(willInstall, pkg.meta.name .. "@" .. pkg.version or "1.0.0")
    end
  end

  if #packages == 0 then
    print("No packages found")
    return
  end

  if not forceYes then
    print("The following packages will be installed: ")
    print(" - " .. table.concat(willInstall, ", "))
    print("Press ENTER to continue")
    repeat
      local _, key = os.pullEvent("key")
    until key == keys.enter
  end

  for _, pkg in ipairs(packages) do
    installPackage(pkg, true)
  end

  print("Installed " .. #packages .. " packages")
end

local function upgrade(...)
  if select("#", ...) == 0 then
    local packages = {}
    for k in pairs(cget.packages) do
      table.insert(packages, k)
    end
    install(unpack(packages))
  else
    install(...)
  end
end

local function remove(...)
  local args = {...}
  local requestedPackages = {}
  for _, v in ipairs(args) do
    requestedPackages[v] = true
  end
  local forceYes = requestedPackages["-y"] or false
  requestedPackages["-y"] = nil

  local packages = {}

  for name in pairs(requestedPackages) do
    local possibilities = {}
    for _, pkg in ipairs(cget.cache) do
      if name == pkg.meta.address then
        possibilities = {pkg}
        break
      elseif name == pkg.meta.name then
        table.insert(possibilities, pkg)
      end
    end

    local pkg

    if #possibilities > 1 then
      print("There are multiple packages with the same name.")
      print("Pick the package you need to remove:")
      for i = 1, #possibilities do
        print("- " .. i .. ": " .. possibilities[i].meta.address)
      end
      while true do
        write("> ")
        local input = tonumber(read())
        if not input or not possibilities[input] then
          printError("Invalid input")
        else
          pkg = possibilities[input]
          print("Picked " .. possibilities[input].meta.address)
          break
        end
      end
    elseif #possibilities == 1 then
      pkg = possibilities[1]
    else
      printError("Package " .. name .. " not found!")
      pkg = nil
    end

    if pkg then
      table.insert(packages, pkg.meta.address)
    end
  end

  if #packages == 0 then
    print("No packages found")
    return
  end

  if not forceYes then
    print("The following packages will be removed: ")
    print(" - " .. table.concat(packages, ", "))
    print("Press ENTER to continue")
    repeat
      local _, key = os.pullEvent("key")
    until key == keys.enter
  end

  for _, addr in ipairs(packages) do
    local pkg = getPackage(addr)

    if pkg then
      if type(pkg.files) == "table" then
        for path in pairs(pkg.files) do
          fs.delete(path)
        end
      end
    end
  end

  print("Removed " .. #packages .. " packages")
end

local function list()
  local list = {}

  for i, pkg in ipairs(cget.cache) do
    table.insert(list, string.format("%d. %s @ %s", i, pkg.meta.address, pkg.version))
  end

  local _, h = term.getSize()

  textutils.pagedPrint(table.concat(list, "\n"), h)
end

local function editSources()
  shell.run("/rom/programs/edit.lua /.craftget/sources")
end

local function init()
  shell.setPath(shell.path() .. ":/bin:/.craftget/bin")
  shell.setAlias("craftget", "cget")
end

local commands
local function help()
  print("Usage: cget <command> [args[, ...]]")
  print("Available commands:")
  for i, cmd in ipairs(commands) do
    print("- " .. cmd[1] .. " " .. (cmd[3] or "[No usage specified]"))
  end
end

local args = {...}

commands = {
  {"help", help, "- Show this help message"},
  {"update", sync, "- Update packages list from sources"},
  {"install", install, "<package>... - Install packages"},
  {"upgrade", upgrade, "[package, ...] - Upgrade packages to latest version"},
  {"remove", remove, "<package>... - Remove packages"},
  {"list", list, "- List packages in cache"},
  {"edit", editSources, "- Edit sources file"},
  {"init", init, "- Integrate with shell"}
}

print("CraftGet " .. cget._VERSION)

if #args < 1 then
  help()
  return
end

for i, cmd in ipairs(commands) do
  if cmd[1] == args[1] then
    local cmdArgs = {}
    for i = 2, #args do
      table.insert(cmdArgs, args[i])
    end
    cmd[2](unpack(cmdArgs))
    return
  end
end
print("Command not found")
