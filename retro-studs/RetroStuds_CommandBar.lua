--[[
	RETRO STUDS - makes EVERYTHING in the place studded (parts, mesh parts,
	unions, the hub floors, AND terrain like grass, sand, rock, etc).

	HOW TO USE (do this once in EVERY place of your game):
	  1. Upload retro-studs/stud_texture.png as an Image/Decal
	     (Studio: View > Asset Manager > Bulk Import, or Creator Hub).
	  2. Right-click the uploaded image > Copy Asset ID, paste it below.
	  3. Studio: View > Command Bar. Paste this whole file there, press Enter.
	  4. Save / Publish the place. Done - it is saved into the place,
	     so parts spawned later in-game get studs automatically too.

	Run it again any time; it replaces its old setup. Ctrl+Z undoes it.
]]

local STUD_TEXTURE = "rbxassetid://PASTE_YOUR_ID_HERE"
local STUDS_PER_TILE = 2 -- the texture holds a 2x2 grid of studs

-- Materials that should keep their special look.
local SKIP = {
	[Enum.Material.Air] = true,
	[Enum.Material.Water] = true,
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.ForceField] = true,
}

local MaterialService = game:GetService("MaterialService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local recording = ChangeHistoryService:TryBeginRecording("Retro Studs")

-- Clear any previous run.
for _, child in MaterialService:GetChildren() do
	if child:IsA("MaterialVariant") and child.Name:match("^RetroStuds_") then
		child:Destroy()
	end
end

local hasTexture = not STUD_TEXTURE:find("PASTE")
local done, failed = 0, 0

if hasTexture then
	-- Override every base material with a studded version. This covers
	-- parts, MeshParts, unions AND terrain (grass, sand, rock...).
	for _, material in Enum.Material:GetEnumItems() do
		if not SKIP[material] then
			local ok = pcall(function()
				local variant = Instance.new("MaterialVariant")
				variant.Name = "RetroStuds_" .. material.Name
				variant.BaseMaterial = material
				variant.ColorMap = STUD_TEXTURE
				variant.StudsPerTile = STUDS_PER_TILE
				variant.Parent = MaterialService
				MaterialService:SetBaseMaterialOverride(material, variant.Name)
			end)
			if ok then done += 1 else failed += 1 end
		end
	end
	print(("[RetroStuds] Studded %d materials (%d skipped by Roblox). Terrain included."):format(done, failed))
else
	-- No texture yet: fall back to classic Roblox stud surfaces on plain
	-- Parts (terrain and MeshParts can't show these - add the texture!).
	for _, part in workspace:GetDescendants() do
		if part:IsA("Part") and part.Transparency < 1 and not SKIP[part.Material] then
			part.Material = Enum.Material.Plastic
			part.TopSurface = Enum.SurfaceType.Studs
			part.BottomSurface = Enum.SurfaceType.Inlet
			done += 1
		end
	end
	warn(("[RetroStuds] No texture ID set - used classic stud surfaces on %d parts. "
		.. "Paste your stud_texture.png asset ID for terrain + mesh studs."):format(done))
end

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
