-- RecipeTweaks  (UE4SS Lua mod, installed by the Permafrost Item Tool's "Recipe tweaks" window)
--
-- Changes crafting recipes inside the running game, using the values in tweaks.lua (next to the Scripts folder).
-- Nothing in your save is touched; the changes exist only while the game runs. To undo everything: set the line
-- "RecipeTweaks : 0" in Mods\mods.txt (or delete the mod folder).
--
--   * tweaks.lua lists, per recipe, the ingredient amounts, the amount(s) made and the crafting time:
--         ["DA_CraftingRecipe_Tent"] = { cost = {4, 2, 4}, result = {1}, time = 5 },
--     Recipes that are not listed keep the game's own values. A recipe removed from the file is put back to the game's values.
--   * The values are applied: shortly after the game starts, when you spawn into the world, and whenever you press F8.
--     So you can change a value in the app, press F8 in the game and craft right away.
--   * Every change is written to UE4SS.log (search for [RecipeTweaks]) and a summary to status.txt in the mod folder.

local TAG = "[RecipeTweaks] "
local function log(msg) print(TAG .. msg .. "\n") end

-- folder of this mod (…\Mods\RecipeTweaks), found from this script's own path
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\RecipeTweaks"
end
local DIR = modDir()
local TWEAKS_FILE = DIR .. "\\tweaks.lua"
local STATUS_FILE = DIR .. "\\status.txt"

local originals = {}   -- recipe name -> { cost = {amounts}, result = {amounts}, time = number }  (the game's own values, captured the first time a recipe is seen)

local function writeStatus(text)
  local f = io.open(STATUS_FILE, "w"); if f then f:write(text); f:close() end
end

local lastApplied = nil   -- text of tweaks.lua as it was when F8 / start-up last applied it

local function readRaw()
  local f = io.open(TWEAKS_FILE, "r"); if not f then return "" end
  local s = f:read("*a"); f:close(); return s or ""
end

local function readTweaks()
  local chunk, err = loadfile(TWEAKS_FILE)
  if not chunk then log("no tweaks file read (" .. tostring(err) .. ")"); return {} end
  local ok, t = pcall(chunk)
  if not ok or type(t) ~= "table" then log("tweaks.lua could not be run: " .. tostring(t)); return {} end
  return t.recipes or {}
end

local function arrayLength(a)
  local ok, n = pcall(function() return #a end)
  return (ok and n) or 0
end

-- remember the game's own values of a recipe object
local function capture(obj, name)
  if originals[name] then return originals[name] end
  local o = { cost = {}, result = {}, time = nil }
  local ok, err = pcall(function()
    local cost = obj.Cost
    for i = 1, arrayLength(cost) do o.cost[i] = cost[i].Amount end
    local result = obj.Result
    for i = 1, arrayLength(result) do o.result[i] = result[i].Amount end
    o.time = obj.Time
  end)
  if not ok then log(name .. ": could not read the recipe (" .. tostring(err) .. ")"); return nil end
  originals[name] = o
  return o
end

-- set a recipe to the wanted values (nil = the game's own); returns the list of what changed
local function setValues(obj, name, want, base)
  local changed = {}
  local ok, err = pcall(function()
    local cost = obj.Cost
    for i = 1, #base.cost do
      local v = (want and want.cost and want.cost[i]) or base.cost[i]
      if cost[i].Amount ~= v then cost[i].Amount = v; changed[#changed + 1] = ("ingredient %d = %s"):format(i, tostring(v)) end
    end
    local result = obj.Result
    for i = 1, #base.result do
      local v = (want and want.result and want.result[i]) or base.result[i]
      if result[i].Amount ~= v then result[i].Amount = v; changed[#changed + 1] = ("makes %d = %s"):format(i, tostring(v)) end
    end
    if base.time ~= nil then
      local v = (want and want.time) or base.time
      if obj.Time ~= v then obj.Time = v; changed[#changed + 1] = ("time = %s"):format(tostring(v)) end
    end
  end)
  if not ok then log(name .. ": could not write the recipe (" .. tostring(err) .. ")") end
  return changed
end

local function applyAll(reason)
  ExecuteInGameThread(function()
    local raw = readRaw()
    local tweaks = readTweaks()
    local list = FindAllOf("CraftingRecipeConfig")
    if not list or #list == 0 then
      log(reason .. ": the recipes are not loaded yet - will try again")
      writeStatus(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. reason .. ": recipes not loaded yet")
      return
    end
    local seen, changedRecipes, listed = 0, 0, 0
    for _ in pairs(tweaks) do listed = listed + 1 end
    for _, obj in ipairs(list) do
      local okName, name = pcall(function() return obj:GetFName():ToString() end)
      if okName and name and obj:IsValid() then
        local base = capture(obj, name)
        if base then
          seen = seen + 1
          local changed = setValues(obj, name, tweaks[name], base)
          if #changed > 0 then
            changedRecipes = changedRecipes + 1
            log(name .. ": " .. table.concat(changed, ", "))
          end
        end
      end
    end
    lastApplied = raw
    local summary = ("%s: %d recipes in the game, %d listed in tweaks.lua, %d changed just now"):format(reason, seen, listed, changedRecipes)
    log(summary)
    writeStatus(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. summary)
  end)
end

-- Auto-apply: when tweaks.lua is saved while the game runs, apply it a moment later (no key press needed).
-- The file must read the same on two checks in a row, so a half-written file is never applied.
-- A bench screen that is already open keeps the numbers it showed when it opened: close and reopen it.
local lastSeen = nil
LoopAsync(2000, function()
  if lastApplied == nil then return false end        -- start-up apply has not run yet
  local raw = readRaw()
  if raw ~= lastApplied and raw == lastSeen then
    applyAll("tweaks.lua changed")
  end
  lastSeen = raw
  return false
end)

-- when it runs: after start-up, when you spawn into the world, whenever tweaks.lua is saved, and on F8 (manual re-apply)
ExecuteWithDelay(8000, function() applyAll("start-up") end)
pcall(function()
  RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteWithDelay(4000, function() applyAll("spawned in the world") end)
  end)
end)
RegisterKeyBind(Key.F8, function() applyAll("F8 pressed") end)

log("loaded - values come from " .. TWEAKS_FILE .. "; saved changes apply by themselves (F8 also re-applies)")