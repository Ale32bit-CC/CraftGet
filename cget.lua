--[[
  CraftGet by Ale32bit
  
  MIT License https://github.com/Ale32bit-CC/CraftGet/blob/master/LICENSE
]]--

local args = {...}
local cget = {
  _VERSION = "0.0.1",
  _AUTHORS = {
    "Ale32bit",
  },
  
  INDEX_HOST = "https://raw.githubusercontent.com/Ale32bit-CC/CraftGet/master/index.json",
  JSON_HOST = "https://raw.githubusercontent.com/rxi/json.lua/master/json.lua",
  cachePath = "/.craftget/cache",
  installIndexPath = "/.craftget/packages",
  
  binPath = "/bin",
  
  installed = {},
  index = {},
  cache = {},
}
cget._MOTD = "CraftGet " .. cget._VERSION

local function fetch(url)
  local h, err = http.get(url)
  if not h then
    return nil, err
  end
  local content = h.readAll()
  h.close()
  return content
end

function cget.update()
  cget.cache = {}
  print("Fetching index...")
  cget.index = json.decode(fetch(cget.INDEX_HOST))
  print("Updating repositories...")
  
  for maintainer, host in pairs(cget.index) do
    print("Updating maintainer", maintainer)
    
    local mIndex = json.decode(fetch(host))
    for name, pkg in pairs(mIndex.packages) do
      print(name)
      table.insert(cget.cache, {
        name = name,
        maintainer = maintainer,
        package = pkg,
      })
    end
  end
  
  local f = fs.open(cget.cachePath, "w")
  f.write(textutils.serialize(cget.cache))
  f.close()
  print("Updated lists")
  print(#cget.cache .. " entries")
end

function cget.install(...)
  local args = {...}
  local packages = {}
  for i = 1, #args do
    packages[args[i]] = true -- to avoid reps
  end
  
  for k in pairs(packages) do
    local possibilities = {}
    for i, pkg in ipairs(cget.cache) do
      if pkg.name == k then
        table.insert(possibilities, pkg)
      end
    end
    
    local pkg
    
    if #possibilities > 1 then -- oh no
      print("There are multiple packages with the same name.")
      print("Pick the package you need:")
      for i = 1, #possibilities do
        print("- " .. i ..": " .. possibilities[i].maintainer .. "/" .. possibilities[i].name)
      end
      while true do
        write("> ")
        local input = tonumber(read())
        if not input or not possibilities[input] then
          printError("Invalid input")
        else
          pkg = possibilities[input]
          print("Picked " .. possibilities[input].maintainer .. "/" .. possibilities[input].name)
          break
        end
        
      end
    else
      pkg = possibilities[1]
    end
    
    if pkg then
      print("Installing " .. k)
      
      for fileName, url in pairs(pkg.package.files) do
        local content, err = fetch(url)
        if content then
          local f = fs.open(fileName, "w")
          f.write(content)
          f.close()
        else
          printError("Cannot fetch ".. fileName .." at " .. url .. ": " .. err)
        end
      end
      
      
      print("Installed " .. k)
      
      
    else
      print("Could not find package " .. k)
    end
    
  end
end

function cget.upgrade(pkg)
  
end

function cget.remove(pkg)
  
end

if #args < 1 then
  print("Usage:")
  print("cget update - Update repositories list and cache")
  print("cget install <package[, ...]> - Install packages")
  print("cget upgrade <package[, ...]> - Upgrade packages")
  print("cget remove <package[, ...]> - Remove packages")
  return
end

print(cget._MOTD)

json = load(fetch(cget.JSON_HOST))()

print("Loading cache")

if not fs.exists(cget.cachePath) then
  local f = fs.open(cget.cachePath, "w")
  f.write({})
  f.close()
  print("Cache file created")
end

local f = fs.open(cget.cachePath, "r")
cget.cache = textutils.unserialize(f.readAll()) or {}
f.close()

if not fs.exists(cget.installIndexPath) then
  local f = fs.open(cget.installIndexPath, "w")
  f.write({})
  f.close()
  print("Packages file created")
end

local f = fs.open(cget.installIndexPath, "r")
cget.installed = textutils.unserialize(f.readAll()) or {}
f.close()

local command = args[1]
if command == "update" then
  cget.update()
elseif command == "install" then
  local pkgs = {}
  for i = 2, #args do
    table.insert(pkgs, args[i])
  end
  cget.install(unpack(pkgs))
end
