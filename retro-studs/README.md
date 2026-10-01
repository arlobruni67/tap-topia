# Retro Studs

Gives the whole game the classic Roblox stud look — grass, terrain, floors,
hubs, every place.

**Files**
- `stud_texture.png` — tileable 2×2 stud texture (light gray, so each part's
  and terrain's own color tints it).
- `RetroStuds_CommandBar.lua` — paste into Studio's Command Bar.

**Steps (repeat in each place)**
1. Upload `stud_texture.png` to Roblox and copy its asset ID.
2. Put the ID into `STUD_TEXTURE` at the top of `RetroStuds_CommandBar.lua`.
3. Studio → View → Command Bar → paste the script → Enter.
4. Save/Publish.

It works through MaterialService material overrides, so it's saved in the
place and also applies to anything spawned at runtime. Neon, Glass,
ForceField and Water keep their normal look. Ctrl+Z undoes it; deleting the
`RetroStuds_*` MaterialVariants in MaterialService removes it.
