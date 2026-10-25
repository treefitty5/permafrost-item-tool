-- WeaponTweaks  (UE4SS Lua mod for the Permafrost Item Tool)
-- Changes the damage of weapons for the whole game: a weapon's damage belongs to its game data (the ItemConfig_Weapon / ItemConfig_RangeWeapon asset), so every copy of
-- that weapon is affected (hotbar, backpack, containers, newly found ones). Nothing in your save is touched; the changes exist only while the game runs.
-- tweaks.lua (next to the Scripts folder), written by the tool:
--   return { version = 1, damage = { DA_Weapon_Firearms_CompoundBow = { 300, 300 }, DA_Weapon_IronAxe = { 40, 40 } } }
--   damage = { min, max } replaces the weapon's Damage (X = min, Y = max; most weapons have both equal)
-- Everything the mod does is written to WeaponTweaks.log in the mod folder.
local TAG = "[WeaponTweaks] "
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\WeaponTweaks"
end
local DIR = modDir()
local LOG_FILE = DIR .. "\\WeaponTweaks.log"
local started = os.time()
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(string.format("%s (+%ds) %s\n", os.date("%H:%M:%S"), os.time() - started, msg)); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- WeaponTweaks loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)
local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end; return nil end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local function nameOf(o) return safe(function() return o:GetFName():ToString() end) or "?" end

local original = {}     -- weapon asset name -> { x =, y = } as the game has it
local lastSet, seen = {}, {}
local CLASSES = { "ItemConfig_Weapon", "ItemConfig_RangeWeapon" }

local function readTweaks()
  local ok, t = pcall(dofile, DIR .. "\\tweaks.lua")
  if ok and type(t) == "table" and type(t.damage) == "table" then return t.damage end
  return {}
end

local function step()
  local want = readTweaks()
  for _, cn in ipairs(CLASSES) do
    local objs = safe(function() return FindAllOf(cn) end) or {}
    if (seen[cn] or 0) ~= #objs then seen[cn] = #objs; log(cn .. " objects loaded: " .. #objs) end
    for _, o in ipairs(objs) do
      if valid(o) then
        local name = nameOf(o)
        local cx = safe(function() return o.Damage.X end); local cy = safe(function() return o.Damage.Y end)
        if cx ~= nil and cy ~= nil then
          local w = want[name]
          if type(w) == "table" and tonumber(w[1]) and tonumber(w[2]) then
            local wx, wy = tonumber(w[1]) + 0.0, tonumber(w[2]) + 0.0
            if math.abs(cx - wx) > 0.001 or math.abs(cy - wy) > 0.001 then
              if original[name] == nil then original[name] = { x = cx, y = cy } end
              safe(function() local d = o.Damage; d.X = wx; d.Y = wy end)
              local x2 = safe(function() return o.Damage.X end); local y2 = safe(function() return o.Damage.Y end)
              local key = tostring(x2) .. "/" .. tostring(y2)
              if lastSet[name] ~= key then log(string.format("%s: damage %s-%s -> %s-%s%s", name, tostring(cx), tostring(cy), tostring(x2), tostring(y2), (x2 == wx and y2 == wy) and "" or "  (READ-BACK DIFFERS: the game did not take the value)")); lastSet[name] = key end
            end
          elseif w == nil and original[name] ~= nil then
            local orig = original[name]
            safe(function() local d = o.Damage; d.X = orig.x; d.Y = orig.y end)
            log(string.format("%s: back to the game's damage %s-%s", name, tostring(orig.x), tostring(orig.y))); lastSet[name] = nil; original[name] = nil
          end
        end
      end
    end
    objs = nil
  end
  collectgarbage("collect")
end

-- ONE timer chain (a second chain at the same time crashed another mod): every second for the first 3 minutes, then every 5 seconds
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
