-- BackpackSlots  (UE4SS Lua mod for the Permafrost Item Tool)
--
-- Changes the number of slots of backpacks inside the running game, using the sizes in tweaks.lua (next to the Scripts folder).
-- Nothing in your save is touched; the sizes exist only while the game runs. To undo everything: set "BackpackSlots : 0" in Mods\mods.txt
-- (or delete the mod folder, or remove a backpack from tweaks.lua).
--
--   * tweaks.lua:   return { slots = { DA_ScavengerBackpack = 50, DA_CasualBackpack = 25 } }
--     The game builds your worn backpack from its game data when the world loads (or when you put the backpack on), so the mod applies the sizes from
--     the moment the game starts, before your save loads. A change made in the app while the game runs applies after you take the backpack off and put it on again.
--   * Every change is written to BackpackSlots.log in the mod folder (and to UE4SS.log under [BackpackSlots]).
local TAG = "[BackpackSlots] "
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\BackpackSlots"
end
local DIR = modDir()
local LOG_FILE = DIR .. "\\BackpackSlots.log"
local started = os.time()
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(string.format("%s (+%ds) %s\n", os.date("%H:%M:%S"), os.time() - started, msg)); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- BackpackSlots loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)

local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end; return nil end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local function nameOf(o) return safe(function() return o:GetFName():ToString() end) or "?" end

local original = {}      -- backpack name -> the game's own slot count, remembered the first time we change it
local lastWanted = {}    -- backpack name -> what we last set (to log only changes)
local seenAssets = 0

local function readTweaks()
  local ok, t = pcall(dofile, DIR .. "\\tweaks.lua")
  if ok and type(t) == "table" and type(t.slots) == "table" then return t.slots end
  return {}
end

local function step()
  local want = readTweaks()
  local objs = safe(function() return FindAllOf("ItemConfig_Clothing") end) or {}
  if #objs ~= seenAssets then seenAssets = #objs; log("ItemConfig_Clothing objects loaded: " .. #objs) end
  for _, o in ipairs(objs) do
    if valid(o) then
      local name = nameOf(o)
      local cur = safe(function() return o.ContainerDimensions.X end)
      if cur and cur > 0 then
        if want[name] and want[name] ~= cur then
          if original[name] == nil then original[name] = cur end
          safe(function() local d = o.ContainerDimensions; d.X = want[name] end)
          local now = safe(function() return o.ContainerDimensions.X end)
          if lastWanted[name] ~= now then log(string.format("%s: %d -> %s slots", name, cur, tostring(now))); lastWanted[name] = now end
        elseif want[name] == nil and original[name] ~= nil and original[name] ~= cur then
          safe(function() local d = o.ContainerDimensions; d.X = original[name] end)   -- removed from tweaks.lua: put the game's own size back
          log(string.format("%s: back to the game's %d slots", name, original[name])); lastWanted[name] = nil; original[name] = nil
        end
      end
    end
  end
  objs = nil
  collectgarbage("collect")
end

-- ONE timer chain (a second chain running at the same time crashed another mod): every second for the first 3 minutes (the game's data loads around start-up and
-- when the world loads), then every 5 seconds so a change made in the app is picked up.
local ticks = 0
local function tick()
  ExecuteWithDelay(ticks < 180 and 1000 or 5000, function()
    ExecuteInGameThread(function()
      ticks = ticks + 1
      local ok, e = pcall(step); if not ok then log("step failed: " .. tostring(e)) end
      tick()
    end)
  end)
end
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function() log("player spawned in the world") end)
log("loaded; reading " .. DIR .. "\\tweaks.lua")
tick()