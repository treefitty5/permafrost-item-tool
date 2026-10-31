-- SolarPanelFix (UE4SS Lua mod for the Permafrost Item Tool)
-- Problem: the loot box of a solar panel (its CoreMesh, the only part that answers the interaction ray) sits below the terrain surface, so no "Press F" ever appears.
-- Fix: the panel's cabinet (the Base part, the one with the white dot) also answers the interaction ray (collision channel 14 = block), so aiming at the cabinet reaches the panel.
-- Runtime only: nothing in the save or the game files is changed. Panels stream in and out, so it is re-applied every few seconds. Log: SolarPanelFix.log in the mod folder.
local TAG = "[SolarPanelFix] "
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\SolarPanelFix"
end
local LOG_FILE = modDir() .. "\\SolarPanelFix.log"
local started = os.time()
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(string.format("%s (+%ds) %s\n", os.date("%H:%M:%S"), os.time() - started, msg)); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- SolarPanelFix loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)
local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end; return nil end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end

local CHANNEL, BLOCK = 14, 2
local CLASSES = { "BP_SolarPanel_01_C", "BP_SolarPanel_02_C", "BP_SolarPanel_03_C", "BP_SolarPanel_04_C", "BP_SolarPanel_05_C", "BP_SolarPanel_06_C", "BP_SolarPanel_07_C" }
local total = 0

local function apply()
  local changed = 0
  for _, cn in ipairs(CLASSES) do
    for _, a in ipairs(safe(function() return FindAllOf(cn) end) or {}) do
      if valid(a) then
        local b = safe(function() return a.Base end)
        if valid(b) and safe(function() return b:GetCollisionResponseToChannel(CHANNEL) end) ~= BLOCK then
          safe(function() b:SetCollisionResponseToChannel(CHANNEL, BLOCK) end)
          changed = changed + 1
        end
      end
    end
  end
  if changed > 0 then total = total + changed; log(string.format("%d panel cabinet(s) now answer the interaction ray (%d so far this session)", changed, total)) end
end

LoopAsync(3000, function() ExecuteInGameThread(function() pcall(apply) end); return false end)
log("loaded; panels get their F prompt back as they load")
