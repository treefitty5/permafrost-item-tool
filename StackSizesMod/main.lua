-- StackSizes  (UE4SS Lua mod, TEST VERSION for the Permafrost Item Tool)
-- Changes how many of an item fit in one slot, for EVERY inventory (backpack, hotbar, storage, containers): the limit belongs to the item's game data.
-- tweaks.lua (next to the Scripts folder):
--   return { stacks = { DA_Consumable_Medication_AFAK_Medkit = 5 }, singleuse = { DA_Consumable_Medication_AFAK_Medkit = true } }
--   stacks    = how many fit in one slot (also marks the item stackable)
--   singleuse = turns the item's durability OFF, so every use consumes one whole item (needed to stack things that have a condition, like first aid kits)
-- Nothing in your save is touched; the changes exist only while the game runs. Everything is written to StackSizes.log in the mod folder.
local TAG = "[StackSizes] "
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\StackSizes"
end
local DIR = modDir()
local LOG_FILE = DIR .. "\\StackSizes.log"
local started = os.time()
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(string.format("%s (+%ds) %s\n", os.date("%H:%M:%S"), os.time() - started, msg)); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- StackSizes loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)
local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end; return nil end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local function nameOf(o) return safe(function() return o:GetFName():ToString() end) or "?" end

local original = {}     -- item asset name -> { amount =, can = } as the game has it
local origDur = {}      -- item asset name -> true when we turned its durability off
local lastWanted, lastDur, seen = {}, {}, {}
local CLASSES = { "ItemConfig_Consumable", "ItemConfig_Clothing", "ItemConfig_Weapon", "ItemConfig_RangeWeapon", "ItemConfig_BuildPart", "ItemConfig_Holdable" }

local function readTweaks()
  local ok, t = pcall(dofile, DIR .. "\\tweaks.lua")
  if ok and type(t) == "table" then return (type(t.stacks) == "table" and t.stacks or {}), (type(t.singleuse) == "table" and t.singleuse or {}) end
  return {}, {}
end

local function step()
  local want, wantSingle = readTweaks()
  for _, cn in ipairs(CLASSES) do
    local objs = safe(function() return FindAllOf(cn) end) or {}
    if (seen[cn] or 0) ~= #objs then seen[cn] = #objs; log(cn .. " objects loaded: " .. #objs) end
    for _, o in ipairs(objs) do
      if valid(o) then
        local name = nameOf(o)
        local cur = safe(function() return o.StackableConfig.StackAmount end)
        local can = safe(function() return o.StackableConfig.bCanBeStackable end)
        if cur ~= nil then
          local w = want[name]
          if w and (cur ~= w or can ~= true) then
            if original[name] == nil then original[name] = { amount = cur, can = can } end
            safe(function() local d = o.StackableConfig; d.StackAmount = w; d.bCanBeStackable = true end)
            local n2 = safe(function() return o.StackableConfig.StackAmount end); local c2 = safe(function() return o.StackableConfig.bCanBeStackable end)
            if lastWanted[name] ~= n2 then log(string.format("%s: stack %s (stackable %s) -> %s (stackable %s)", name, tostring(cur), tostring(can), tostring(n2), tostring(c2))); lastWanted[name] = n2 end
          elseif w == nil and original[name] ~= nil then
            local orig = original[name]
            safe(function() local d = o.StackableConfig; d.StackAmount = orig.amount; d.bCanBeStackable = (orig.can == true) end)
            log(string.format("%s: back to the game's stack %s", name, tostring(orig.amount))); lastWanted[name] = nil; original[name] = nil
          end
        end
        local dur = safe(function() return o.DurabilityConfig.bUsesDurability end)
        if dur ~= nil then
          if wantSingle[name] and dur == true then
            origDur[name] = true
            safe(function() local d = o.DurabilityConfig; d.bUsesDurability = false end)
            local d2 = safe(function() return o.DurabilityConfig.bUsesDurability end)
            if lastDur[name] ~= d2 then log(string.format("%s: uses durability %s -> %s (single use)", name, tostring(dur), tostring(d2))); lastDur[name] = d2 end
          elseif not wantSingle[name] and origDur[name] then
            safe(function() local d = o.DurabilityConfig; d.bUsesDurability = true end)
            log(name .. ": durability back on"); origDur[name] = nil; lastDur[name] = nil
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