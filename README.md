# Permafrost Item Tool

<img src="assets/app-icon.png" width="96" align="right" alt="icon">

A Windows tool for **single-player** [Permafrost](https://store.steampowered.com/app/2254990/) saves. Everything it shows comes from the game's own data files, which you extract from **your own copy** of the game (this repository contains no game files).

**What it does**

| | |
|---|---|
| **Item catalog** | Every item with its in-game name and description, stack size, condition, damage, frost protection, value, ammo, and where it can be found (with the chance per container opening). |
| **Add items** | Queue items, preview, and write them to your save (backpack or hotbar). Stack sizes, condition and backpack capacity come from the game data, and it warns when there is not enough room. A backup is made before every change. |
| **Player tools** | Vitals, skills (with the game's level caps), skill points, known recipes, teleport, and a read-only quest view. |
| **Game data browser** | Search everything: reward pools, quests (with a spoiler guard), recipes, loot tables, building parts, recordings and notes, game rules (effects, difficulty, animals, NPCs, skills, ...). |
| **Recipe tweaks** | Change ingredient amounts, amount crafted and crafting time through a small in-game mod. Changes apply while the game is running; your save file is never touched. |
| **World reset** | Put chopped trees, mined boulders and ores, picked-up items and looted containers back, per world, so you can harvest them again (the game never respawns them). Backup first; optional radius around you. |
| **Build move** | Pick up a placed building (furniture, storage, workbench, lamp...) from the Q wheel and put it down somewhere else, through a small in-game mod. Storage can be stacked and put on walls. |

> **Unofficial fan tool, not affiliated with the developers or publisher of Permafrost.** Single-player only. Editing saves can corrupt them: the tool makes a backup first, but keep your own copy too.

---

## How do I run it?

There is no installer and no `.exe`. The tool is a set of plain-text PowerShell scripts, and you start it by **double-clicking one file**:

1. Install **PowerShell 7** once (free, from Microsoft): open the Start menu, search for *Terminal*, and run `winget install Microsoft.PowerShell`. Or get it from the Microsoft Store.
2. Download this repository (**Code → Download ZIP**) and unzip it somewhere you own, such as `C:\Tools\PermafrostItemTool`.
3. Do the one-time data setup below (steps 3-5). It makes the item list from your own copy of the game.
4. **Close Permafrost**, then double-click **`Run Permafrost Item Tool.cmd`**. The window opens (no black console window).

That is all. If Windows says *"Windows protected your PC"* the first time, click **More info → Run anyway**: the file came from the internet and is not signed. You can open any `.ps1` or `.cmd` file in Notepad to read exactly what it does. If PowerShell 7 is missing, the launcher tells you so.
---

## Contents

0. [How do I run it?](#how-do-i-run-it)
1. [Requirements](#1-requirements)
2. [Get the tool](#2-get-the-tool)
3. [Make the mappings file (one time)](#3-make-the-mappings-file-one-time)
4. [Export the game files with FModel](#4-export-the-game-files-with-fmodel)
5. [Build the data](#5-build-the-data)
6. [Start the tool](#6-start-the-tool)
7. [Using it](#7-using-it)
8. [Recipe tweaks (in-game mod)](#8-recipe-tweaks-in-game-mod)
9. [World reset](#9-world-reset)
10. [Build move (in-game mod)](#10-build-move-in-game-mod)
11. [After a game update](#11-after-a-game-update)
12. [Troubleshooting](#12-troubleshooting)
13. [How it works / repository layout](#13-how-it-works--repository-layout)
14. [Legal](#14-legal)

---

## 1. Requirements

| What | Why | Where |
|---|---|---|
| Windows 10 or 11 | the window uses Windows Forms | |
| **PowerShell 7** (`pwsh`) | the tool is written in PowerShell 7 | `winget install Microsoft.PowerShell` or the Microsoft Store |
| **Permafrost** (Steam) | the game and its save files | |
| **FModel** | reads the game's files so you can export them | <https://fmodel.app> (4.4.4 was used) |
| **UE4SS, experimental build** | makes the mappings file; also runs the recipe mod | <https://github.com/UE4SS-RE/RE-UE4SS/releases> (`v3.0.1-1181` experimental was used; newer builds are untested) |
| About 5 GB free disk (temporary) | the export is about 0.1 GB for `Blueprints` and 4 GB for `Assets\Items` (the item pictures); you can delete the export after step 5 | |

You do **not** need to install anything else: no Python, no .NET SDK, no compiler. The tool is plain `.ps1` scripts, so you can read every line before running it.

## 2. Get the tool

Download this repository (green **Code** button, **Download ZIP**) and unzip it somewhere you own, for example `C:\Tools\PermafrostItemTool`. Do not put it inside the game folder.

If Windows blocks the scripts, open PowerShell 7 in that folder and run `Get-ChildItem -Recurse | Unblock-File` once. The launcher already starts the tool with `-ExecutionPolicy Bypass`.

## 3. Make the mappings file (one time)

Permafrost stores its data without field names ("unversioned properties"), so FModel can only turn it into readable JSON if you give it a **mappings** (`.usmap`) file. UE4SS can produce one from the running game.

1. **Install UE4SS** into the game by following its documentation (the files go next to `Permafrost-Win64-Shipping.exe`, in `Permafrost\Binaries\Win64`; you end up with `dwmapi.dll` there and a `ue4ss` folder).
2. Copy the folder `UE4SSMods\DumpUsmapNative` from this repository into `...\Binaries\Win64\ue4ss\Mods\`.
3. Open `...\ue4ss\Mods\mods.txt` and add this line **above** the `; Built-in keybinds` comment:
   ```
   DumpUsmapNative : 1
   ```
4. Start the game, load to the main menu (or into your world), and press **F9**. UE4SS writes a file named like `Permafrost-5.4.4-....usmap` into the `ue4ss` folder.
   - This mod calls `DumpUSMAP(false)` (native types only). The full dump (Ctrl+Numpad6) crashed UE4SS on this game; if it works for you, it is not needed.
5. Close the game. Copy the `.usmap` file somewhere permanent, for example next to FModel.

## 4. Export the game files with FModel

1. Start FModel. In **Directory selector** add an *undetected game*, point it at `...\steamapps\common\Permafrost\Permafrost\Content\Paks`, and choose **UE 5.4**. (No AES key was needed for the Steam version at the time of writing.)
2. **Settings → Endpoints → Mapping**: tick *Overwrite* and set *File path* to your `.usmap` file. Restart FModel when asked. (Menu names can differ slightly between FModel versions: what matters is that FModel loads a *local* mappings file for Permafrost.)
3. In **Settings**, note the **Output directory**. The export ends up in `<Output directory>\Exports\Permafrost\...`. The tool finds it by itself (it reads FModel's setting), and `config.json` can override it (see below).
4. In the left folder tree, open `Permafrost\Content\Permafrost`, **right-click the folder, and export:**

   | Folder | Export as | Why |
   |---|---|---|
   | `Blueprints` | **Raw data (.uasset)**: *Export Folder's Packages Raw Data* | item, loot and reward structure |
   | `Blueprints` | **JSON**: *Save Folder's Packages Properties (.json)* | names, amounts, quests, effects, text |
   | `Assets\Items` | **Raw data (.uasset)** | the item pictures (the tool turns them into small PNGs on *your* machine) |

   - You can skip `Blueprints\AI` and `Blueprints\Characters\Hero`: the tool does not read them. If FModel struggles with the whole `Blueprints` folder, export it sub-folder by sub-folder (`Items`, `BuildingParts`, `QuestSystem`, `Interactions`, `RewardPools`, `GAS`, `CharacterStatus`, `Difficulty`, `Skills`, `Characters`, `World`, `RandomEncounters`, `Destructable`, `Farming`, `FastTravel`, `AchievementsAndStatistics`, `Utils`).
   - Folders that are exported as JSON get a `.json` file next to each `.uasset`; that is expected.
   - The `Assets\Items` export is only for pictures. Without it the tool works, it just shows text instead of icons.

## 5. Build the data

Open PowerShell 7 in the tool folder and run:

```powershell
pwsh -NoProfile -File .\Build-Everything.ps1
```

It finds the game folder (through Steam's library list) and FModel's export folder, then builds, in this order: the item list, the item pictures, and every table the tool uses (recipes, loot, quests, text, ...). On a typical PC this takes about a minute. It creates `items.json`, `icons\` and `catalog\` next to the scripts.

If it cannot find something, create `config.json` next to the scripts and tell it:

```json
{
  "GameDir":    "E:\\Games\\steamapps\\common\\Permafrost",
  "SavePath":   "E:\\Games\\steamapps\\common\\Permafrost\\Permafrost\\SaveGame\\World#1.pfs",
  "ExportRoot": "E:\\FModel\\Output\\Exports"
}
```

`ExportRoot` is the folder that **contains** the `Permafrost` folder. `GameDir` is the folder that contains the inner `Permafrost` folder. Only the entries you need have to be there.

## 6. Start the tool

**Close the game first**, then double-click `Run Permafrost Item Tool.cmd`.

It picks the most recently saved `.pfs` in `...\Permafrost\SaveGame`. Use **Browse...** to choose another save; the choice is remembered in `config.json`.

If you see *"The game data has not been made yet"*, go back to step 5.

## 7. Using it

**Adding items (the main window)**

1. Close the game. (Keep Steam Cloud off for Permafrost while you experiment, otherwise it can restore the old save.)
2. Search the catalog on the left and **click** an item. The panel shows its name, description, stack size, condition and where to find it.
3. Choose how many stacks (1-10) or an exact amount, then **Add to queue**. The *free backpack slots* line turns red with *NOT ENOUGH SPACE* if it will not fit; the tool refuses to write in that case.
4. **Preview** shows exactly what will change; **Apply to save** writes it. A copy of the save is stored in `Backups\` first, and **Restore** puts it back.
5. Start the game and load your save.

**Player tools** (button at the top): vitals, skills, skill points, recipes, teleport, quest progress (read-only). Change values, then apply with the game closed. Hover a recipe in the Recipes tab to see its picture, cost or ingredients (pictures are built by `Build-RecipeIcons.ps1`, part of the full rebuild).

**Game data** (button at the top): every table the tool built. Quest and dialogue text is hidden behind a **spoiler guard** that is on by default.

**World reset** and **Build move** (buttons at the top): see sections 9 and 10. The **Help / how it works** window has a Find bar (Ctrl+F) that highlights matches as you type.

**Theme:** the combo box at the top right switches between three colour themes. It is remembered.

## 8. Recipe tweaks (in-game mod)

**Recipe tweaks...** edits crafting recipes: ingredient amounts, how many you get, and crafting time. It works through a small UE4SS mod. Your save file is never changed, so this window can be used **while the game is running**.

1. Click **Install / update mod** once (needs UE4SS from step 3). It copies the mod into `...\ue4ss\Mods\RecipeTweaks` and adds `RecipeTweaks : 1` to `mods.txt` (a backup of `mods.txt` is made). **Restart the game** after installing or updating the mod: UE4SS loads mods at start-up only.
2. Pick recipes, change the boxes (or use the multipliers), and press **Save to game**.
3. In the game: a saved change is applied by itself within a few seconds. **Close and reopen the bench** to see it (an open bench keeps the numbers it showed when it opened). F8 re-applies by hand.
4. To undo: **Reset ALL recipes**, then **Save to game**. Or set `RecipeTweaks : 0` in `mods.txt`.

You can edit recipes you have not learned yet; the values are there when you learn them. Everything the mod does is written to `UE4SS.log` (search for `[RecipeTweaks]`) and to `status.txt` in the mod folder.

## 9. World reset

The game never respawns trees, boulders, picked-up items or container loot. **World reset...** puts them back by editing your save (**close the game first**; a backup is made before every change, and the result is checked before it replaces the save).

1. Pick the **World**. The box lists every `.pfs` in your SaveGame folder; under it you see the hours played, when it was last saved and how many backups that world has.
2. Tick what to put back: trees you chopped down; boulders and ores (rock, coal, flint, iron, copper, sulfur, gold, moon rock); items that lay in the world (scrap, oil, plastic, food...); loot in containers (cars, cabinets, crates, corpses, trash cans...); and, if you want, other breakables (pallets, rubble, trash piles, furniture). *Leave containers alone that still hold items* keeps half-emptied containers.
3. Optionally limit it to N metres around where you stand in the save (0 = the whole world). Try **150** first, load the game, check, then do the rest.
4. **Preview** shows how many of each would be put back and what is left alone. **Reset the world now...** runs its own preview, asks you to confirm, makes the backup, writes the change and verifies it. You do not have to press Preview first.

**How it works.** The save has a record for every object of every area you have visited; a destroyed or picked-up object simply has no record any more. Felled trees are removed from the record (they stand again); partly mined boulders go back to full health; destroyed boulders and picked-up items are put back from your **earlier backups** (so keep the `Backups` folder: a world without backups cannot get destroyed ores or picked-up items back); looted containers get their original loot back from a backup, or the loot of another container with the same loot table. Quest items and keys are never re-rolled.

**Not covered:** bushes (no save shows how the game remembers a harvested bush) and containers without a loot sample (solar panels). Undo a reset with **Restore a backup...** in the main window.

## 10. Build move (in-game mod)

**Build move...** installs a small UE4SS mod that lets you pick up a building you placed and put it somewhere else, without rebuilding it. Click it once (needs UE4SS from step 3): it copies the mod into `...\ue4ss\Mods\BuildMove` and adds `BuildMove : 1` to `mods.txt` (a backup of `mods.txt` is made). **Restart the game** after installing or updating: UE4SS loads mods at start-up only.

* In the game: look at a placed part (furniture, storage chest, barrel, workbench, lamp, brazier, bed), press **Q** and choose **Move** (the mod puts it in the wheel's empty padlock slot). The part follows your crosshair. **Left click** puts it down; choosing Move again or pressing **F7** also puts it down, and F7 starts a move without opening the wheel.
* The same object is moved: health, contents and variation stay, and no materials are used or refunded. The game saves the new position itself.
* There is **no collision check, on purpose**: you can put a part on top of another one, stack storage (chests on chests, barrels on barrels) and put storage on walls. If a part ends up inside a wall, pick it up again.
* Page Up / Page Down (turn 15 degrees), F6 (cancel) and the refusal of structural pieces (walls, floors, foundations, roofs, doors, beams, stairs) are in the mod but have not been tested yet.
* Everything the mod does is written to `UE4SS.log` and to `BuildMove.log` in the mod folder (search for `[BuildMove]`). Switch it off with `BuildMove : 0` in `mods.txt`.

## 11. After a game update

Permafrost is in active development, so updates will come. The tool does not guess: everything it shows is read from the game files, so after an update **its data is out of date until you rebuild it**. Out-of-date data is the main risk: new items are missing, and a stack size or condition that the developers changed would still be the old value.

**Short version:** update the game, make a copy of your save, re-export the game files, run `Build-Everything.ps1`, then test on the copy.

1. **Let Steam update the game, then start it once** and load your save, to make sure the game itself runs. Note the version number shown on screen (top-right corner of the in-game menus) so you know which version your data is for.
2. **Do not use *Apply to save* yet.** Until you rebuild, the item list can be wrong for the new version.
3. **Copy your save file** (the `.pfs` in `SaveGame`) to a safe place. The tool also makes its own backup, but this is cheap insurance.
4. **Delete the old exported `Blueprints` folder**, then re-export it as in step 4 (raw **and** JSON). Deleting first matters: files the developers removed would otherwise stay behind and show up as items that no longer exist. Re-export `Assets\Items` too if new items were added (otherwise they simply have no picture).
5. **Check the JSON still has field names.** If FModel now shows errors, or the JSON files contain only values without names, the update changed the game's classes: **make a new mappings file** (step 3) and set it in FModel again.
6. Run `Build-Everything.ps1` and read the output. Each builder prints a one-line summary (items, recipes, quests, ...). Numbers far below the previous run, or a line saying *problems:* with a number above 0, mean something in the data changed shape: open an issue and include that output.
7. Start the tool and look at the items you care about. Then **try one small change on your save copy** (or apply, start the game, and check) before trusting a big queue.
8. **Recipe tweaks:** restart the game once. The mod changes recipes only in memory, so after an update the worst case is that it logs an error (look for `[RecipeTweaks]` in `UE4SS.log`) and changes nothing; your save is never touched. Press *Install / update mod* again if this tool was updated.
9. **Build move:** restart the game once. If Move disappears from the Q wheel or F7 stops working after an update, read `BuildMove.log` (in `...\ue4ss\Mods\BuildMove`) and open an issue with it; your save is never touched by the mod.

**Also worth knowing**

* **UE4SS:** a game update that moves to a new Unreal Engine version can stop UE4SS from loading (the game may even crash at start). If that happens, remove `dwmapi.dll` from `Binaries\Win64` to start the game normally, then install a UE4SS build that supports the new engine version. Steam's *Verify integrity of game files* can also remove UE4SS files; reinstall them if your mods stop loading.
* **The save format:** the tool only edits inventory entries and checks its work, and it refuses to write when the checks fail. If an update changes how saves are stored, the tool will refuse rather than guess; wait for a tool update and do not edit around it.
* **Saves made in a newer version** may not open in an older one. Keep your save copy from before the update if you might go back.
* **Update the tool too:** download the new zip from this repository (or `git pull`), keep your `config.json`, and re-run `Build-Everything.ps1`.
* **World reset uses your backups as its history.** Keep the `Backups` folder; after a game update an old backup may no longer match the new world layout.
* **Do not share your extracted data.** Each player rebuilds it from their own copy of the game.

## 12. Troubleshooting

| Problem | What to do |
|---|---|
| *"The game data has not been made yet"* | Do step 5. |
| `FModel's export folder was not found` | The export must contain `Permafrost\Content\...`. Put the path of the folder that contains `Permafrost` in `config.json` as `ExportRoot`. |
| FModel shows no *Save ... Properties (.json)* entry, or the JSON has no field names | The mappings file is not loaded. Redo step 4.2 and restart FModel. |
| F9 does nothing in the game | UE4SS is not loaded (is `dwmapi.dll` next to the game exe?) or `DumpUsmapNative : 1` is missing/below the `Built-in keybinds` line in `mods.txt`. Check `UE4SS.log`. |
| The game crashes when you use the full mappings dump (Ctrl+Numpad6) | Known on this game; use the F9 mod from step 3 instead. |
| Items added but not in the game | The game was open, or Steam Cloud restored the old save. Close the game, keep Steam Cloud off, apply again. |
| Recipe change does not show | The bench was already open (reopen it), or the mod was updated without restarting the game. Look for `[RecipeTweaks]` lines in `UE4SS.log`. |
| Move is missing from the Q wheel, or F7 does nothing | The mod is not installed, or the game was not restarted after installing. Click **Build move...** again, restart the game, and read `BuildMove.log` in `...\ue4ss\Mods\BuildMove`. |
| World reset says there is nothing to put back | Nothing qualifies with these tick boxes and radius, or the world has no backups (destroyed ores and picked-up items need earlier backups). Preview lists what is left alone and why. |
| Some item has no picture | The texture was not in your `Assets\Items` export or it is not an `Assets\Items` texture. The tool shows text instead. The list is in `icons-missing.txt`. |
| A window is blank or the tool closes at once | Start it from PowerShell 7 with `pwsh -NoProfile -STA -File .\PermafrostItemTool.ps1` to see the error; it is also written to `error.log`. |

## 13. How it works / repository layout

* `PermafrostItemTool.ps1` - the main window. `SaveCore.ps1` - reading and writing the `.pfs` save (the inventory exists in **three synced copies** inside it; all are patched together and verified). `PlayerCore.ps1` / `PlayerTools.ps1` - player data. `GameData.ps1` - the data browser. `RecipeTweaks.ps1` - the recipe editor. `WorldCore.ps1` / `WorldReset.ps1` / `WorldResetUI.ps1` - the world reset (reading and rewriting the world block of the save, which is checked to round-trip byte for byte; planning; the window). `BuildMove.ps1` - installs the Build move mod. `Theme.ps1` - colours.
* `Paths.ps1` - finds your game folder, save and FModel export; reads `config.json`.
* `Build-*.ps1` - turn FModel's exports into `items.json` and `catalog\*.csv`. `Build-Everything.ps1` runs them all; `Rebuild-All.ps1` runs the JSON-based ones.
* `RecipeTweaksMod\main.lua` - the in-game recipe mod. `BuildMoveMod\main.lua` - the in-game Build move mod. `UE4SSMods\DumpUsmapNative` - the F9 mappings helper.
* `TextureDecode.ps1` - decodes the exported item textures into PNGs.
* Nothing under `catalog\`, `icons\`, `items.json` or `Backups\` is part of the repository: they are made on your computer (see `.gitignore`).

To check what the tool will do to your save, read `SaveCore.ps1`: it only touches the inventory entries, and it refuses to write if its checks fail.

## 14. Legal

* This is an **unofficial** project, **not affiliated with, endorsed by, or sponsored by** the developers or publisher of Permafrost. "Permafrost" and all game content belong to their owners.
* The repository contains **only original code**. It ships no game files, text, textures or extracted data; you create those locally from a copy of the game you own, and you should not redistribute them.
* **Modding is not officially supported.** The developers and publisher have said they do not support modding during Early Access and do not support problems caused by mods (see the notice in the "unofficial modding hub" of the official Permafrost Discord). **Please do not report problems with this tool to them.** Open an issue in this repository instead.
* For use with **single-player** saves only. Do not use it to gain an advantage in multiplayer.
* Provided as is, without warranty (see `LICENSE`). Back up your saves.
* **How it was made:** built by [treefitty5](https://github.com/treefitty5) together with Claude, Anthropic's AI assistant. The goals and all in-game testing are the author's; the AI wrote the code and decoded the data files. All the source is here to read.
* Third-party tools used (not included): [FModel](https://github.com/4sval/FModel) and [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) - follow their licences.
* If you are a rights holder and want something changed or removed, please open an issue.
