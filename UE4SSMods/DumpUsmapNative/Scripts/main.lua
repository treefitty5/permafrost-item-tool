-- DumpUsmapNative: press F9 in the game to write Mappings.usmap with native types only (DumpUSMAP(false)).
-- Why: the full dump (Ctrl+Numpad6, includes Blueprint types) crashes UE4SS.dll on this game. To undo: delete this folder and its line in mods.txt.
RegisterKeyBind(Key.F9, function()
    print("[DumpUsmapNative] F9 pressed - dumping native types only...\n")
    DumpUSMAP(false)
    print("[DumpUsmapNative] DumpUSMAP(false) returned\n")
end)
print("[DumpUsmapNative] loaded - press F9 in game to dump mappings (native types only)\n")
