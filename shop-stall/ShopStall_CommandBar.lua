--[[
	SHOP STALL + ANIMATED SHOPKEEPER - replaces your current shop with a
	blue/white striped market stall and an animated shopkeeper NPC.

	HOW TO USE:
	  1. In Studio, click your current shop model in the Explorer so it is
	     selected (or type its name into OLD_SHOP_NAME below).
	  2. View > Command Bar. Paste this whole file there, press Enter.
	  3. Check the Output window, then Save / Publish.

	What it does:
	  - Builds the new stall where the old shop stood (same spot, same
	    facing, sitting on the same ground) and gives it the old shop's name.
	  - Moves the old shop's ProximityPrompts / ClickDetectors onto the new
	    counter, so "press E to shop" keeps working.
	  - Keeps the old shop as a backup in ServerStorage (nothing deleted).
	  - Loads the NPC from NPC_ID and animates it: breathing, looking
	    around, waving + saying hi when a player walks up, leaning on the
	    counter and following the player with its head, wiping the counter
	    when nobody is around, and a nod + "what'll it be?" when the shop
	    prompt is used. The animation runs on each player's device, so it
	    is perfectly smooth.

	Run it again any time: it rebuilds the stall in place. Ctrl+Z undoes it.
	If the stall faces the wrong way, just rotate the model with the
	Rotate tool - everything inside moves with it.
]]

local NPC_ID = 11330911907 -- model / outfit / user ID for the shopkeeper
local SIGN_TEXT = "SHOP"
local OLD_SHOP_NAME = "" -- leave "" to use the selected model or auto-find

local Players = game:GetService("Players")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local TAG = "TapTopiaShopStall"

local ANIM_SOURCE = [==[
-- Shopkeeper animation. RunContext = Client, so every player animates the
-- NPC locally (smooth, no network lag) and the NPC reacts to THAT player.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local npc = script.Parent
local shop = npc.Parent
local player = Players.LocalPlayer
local humanoid = npc:WaitForChild("Humanoid")
local root = npc:WaitForChild("HumanoidRootPart")
local head = npc:WaitForChild("Head")

local GREET_RANGE = 16 -- studs: wave + say hi when a player gets this close
local FORGET_RANGE = 28 -- studs: walk this far away to get greeted again
local GREETINGS = { "Hey there, welcome!", "Howdy! Take a look around!", "Ooh, a customer!" }
local PROMPT_LINES = { "What'll it be?", "Great choice!", "Take your time!" }

local rng = Random.new()
local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

-- Joints -----------------------------------------------------------------
local function find(partName, jointName)
	local part = partName == "" and root or npc:WaitForChild(partName, 5)
	return part and part:WaitForChild(jointName, 5)
end

local J
if humanoid.RigType == Enum.HumanoidRigType.R6 then
	J = {
		neck = find("Torso", "Neck"),
		root = find("", "RootJoint"),
		rArm = find("Torso", "Right Shoulder"),
		lArm = find("Torso", "Left Shoulder"),
		rHip = find("Torso", "Right Hip"),
		lHip = find("Torso", "Left Hip"),
	}
else
	J = {
		neck = find("Head", "Neck"),
		root = find("LowerTorso", "Root"),
		waist = find("UpperTorso", "Waist"),
		rArm = find("RightUpperArm", "RightShoulder"),
		lArm = find("LeftUpperArm", "LeftShoulder"),
		rElbow = find("RightLowerArm", "RightElbow"),
		lElbow = find("LeftLowerArm", "LeftElbow"),
	}
end

-- Springs give every motion a soft start, a tiny overshoot and a settle.
local Spring = {}
Spring.__index = Spring
function Spring.new(freq, damp)
	return setmetatable({ p = 0, v = 0, t = 0, f = freq, d = damp }, Spring)
end
function Spring:step(dt)
	local f = self.f
	self.v += (f * f * (self.t - self.p) - 2 * self.d * f * self.v) * dt
	self.p += self.v * dt
end

local TUNING = {
	neck = { 11, 0.65 }, root = { 7, 0.8 }, waist = { 8, 0.7 },
	rArm = { 10, 0.55 }, lArm = { 10, 0.55 }, rElbow = { 12, 0.6 }, lElbow = { 12, 0.6 },
	rHip = { 7, 0.8 }, lHip = { 7, 0.8 },
}

local joints = {}
for key, motor in J do
	if motor and motor:IsA("Motor6D") then
		local f, d = TUNING[key][1], TUNING[key][2]
		joints[key] = {
			motor = motor,
			base = motor.C0,
			x = Spring.new(f, d), y = Spring.new(f, d), z = Spring.new(f, d), py = Spring.new(f, d),
		}
	end
end

-- R15 bends at the waist; R6 bends at the root and the hips counter it so
-- the legs stay planted.
local twistKey = joints.waist and "waist" or "root"
local hipCompensate = joints.waist == nil

local function target(key, a, py)
	local j = joints[key]
	if not j then return end
	j.x.t, j.y.t, j.z.t = a[1], a[2], a[3]
	if py then j.py.t = py end
end

local function kick(key, axis, amount)
	local j = joints[key]
	if j then j[axis].v += amount end
end

-- Speech bubble ------------------------------------------------------------
local bubbleGui, bubbleToken, talkUntil = nil, 0, 0

local function say(text)
	bubbleToken += 1
	local token = bubbleToken
	if bubbleGui then bubbleGui:Destroy() end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ShopkeeperBubble"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(280, 80)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	bubbleGui = gui

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -8)
	frame.Size = UDim2.fromOffset(0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
	local pad = Instance.new("UIPadding", frame)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
	local scale = Instance.new("UIScale", frame)
	scale.Scale = 0.4

	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, 8)
	tail.Size = UDim2.fromOffset(14, 14)
	tail.Rotation = 45
	tail.BorderSizePixel = 0
	tail.BackgroundColor3 = frame.BackgroundColor3
	tail.ZIndex = 0
	tail.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(40, 40, 48)
	label.Text = text
	label.MaxVisibleGraphemes = 0
	label.Parent = frame

	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.spawn(function()
		local n = utf8.len(text) or #text
		talkUntil = os.clock() + n * 0.03
		for i = 1, n do
			if token ~= bubbleToken then return end
			label.MaxVisibleGraphemes = i
			task.wait(0.03)
		end
		task.wait(2.6)
		if token ~= bubbleToken then return end
		local fade = TweenInfo.new(0.3)
		TweenService:Create(frame, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(tail, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(scale, fade, { Scale = 0.8 }):Play()
		task.wait(0.35)
		if token == bubbleToken then gui:Destroy() end
	end)
end

-- Behaviour ----------------------------------------------------------------
local mode, modeEnd = "idle", 0
local greeted = false
local nextWipe = os.clock() + rng:NextNumber(4, 8)
local nextGlance, glanceTarget = 0, nil

local function setMode(m, duration)
	mode, modeEnd = m, os.clock() + duration
end

local function onPrompt()
	setMode("present", 1.8)
	kick("neck", "x", -6)
	say(pick(PROMPT_LINES))
end

local function hook(d)
	if d:IsA("ProximityPrompt") then
		d.Triggered:Connect(onPrompt)
	elseif d:IsA("ClickDetector") then
		d.MouseClick:Connect(onPrompt)
	end
end
for _, d in shop:GetDescendants() do hook(d) end
shop.DescendantAdded:Connect(hook)

RunService.RenderStepped:Connect(function(dt)
	if not npc.Parent then return end
	local cam = workspace.CurrentCamera
	if (cam.CFrame.Position - root.Position).Magnitude > 150 then return end
	dt = math.min(dt, 0.1)
	local t = os.clock()

	local char = player.Character
	local pHead = char and char:FindFirstChild("Head")
	local dist = pHead and (pHead.Position - root.Position).Magnitude or math.huge

	if dist > FORGET_RANGE then greeted = false end
	if dist < GREET_RANGE and not greeted and mode ~= "present" then
		greeted = true
		setMode("wave", 2.6)
		kick("neck", "x", -4)
		say(pick(GREETINGS))
	end
	if t > modeEnd then
		if dist < FORGET_RANGE then
			mode = "lean"
		elseif t > nextWipe then
			setMode("wipe", rng:NextNumber(3.5, 5))
			nextWipe = t + rng:NextNumber(9, 15)
		else
			mode = "idle"
		end
	end

	-- Where to look: the player if they're around, otherwise glance about.
	local lookAt
	if pHead and dist < FORGET_RANGE then
		lookAt = pHead.Position
	else
		if t > nextGlance then
			nextGlance = t + rng:NextNumber(1.8, 4.5)
			glanceTarget = root.CFrame:PointToWorldSpace(
				Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-1.5, 2), -12))
		end
		lookAt = glanceTarget
	end
	local yaw, pitch = 0, 0
	if lookAt then
		local rel = root.CFrame:PointToObjectSpace(lookAt)
		yaw = math.atan2(-rel.X, -rel.Z)
		pitch = math.atan2(rel.Y - 1.5, math.sqrt(rel.X * rel.X + rel.Z * rel.Z))
		if math.abs(yaw) > 2.1 then yaw, pitch = 0, 0 end -- behind: no owl turns
		yaw = math.clamp(yaw, -1.3, 1.3)
		pitch = math.clamp(pitch, -0.6, 0.5)
	end

	-- Pose (angles in radians, in the torso's space: x = pitch, y = yaw, z = roll)
	local breath = math.sin(t * 2.1)
	local sway = math.sin(t * 0.55)
	local P = {
		neck = { pitch * 0.8 + breath * 0.015, yaw * 0.7, 0 },
		twist = { 0, yaw * 0.3, sway * 0.025 },
		rArm = { 0.06 + breath * 0.03, 0, 0.07 + breath * 0.02 },
		lArm = { 0.06 + breath * 0.03, 0, -0.07 - breath * 0.02 },
		rElbow = { 0.15, 0, 0 },
		lElbow = { 0.15, 0, 0 },
	}

	if mode == "lean" then -- hands on the counter, attentive, curious head tilt
		P.twist[1] = -0.14
		P.rArm = { 1.2 + breath * 0.02, 0, 0.12 }
		P.lArm = { 1.2 + breath * 0.02, 0, -0.12 }
		P.rElbow = { 0.6, 0, 0 }
		P.lElbow = { 0.6, 0, 0 }
		P.neck[3] = math.sin(t * 0.4) * 0.08
	elseif mode == "wave" then
		local w = math.sin(t * 12)
		P.rArm = { 0.25, 0, 2.55 + w * 0.35 }
		P.rElbow = { 0.5 + w * 0.25, 0, 0 }
		P.twist[2] = yaw * 0.35
		P.twist[3] = -0.05
		P.neck[3] = 0.12
	elseif mode == "wipe" then -- rag circles on the counter, eyes on the rag
		local c = t * 5.5
		P.twist = { -0.2, math.cos(c) * 0.06, sway * 0.025 }
		P.rArm = { 1.25 + math.sin(c) * 0.13, 0, 0.18 + math.cos(c) * 0.28 }
		P.lArm = { 1.15, 0, -0.15 }
		P.rElbow = { 0.5, 0, 0 }
		P.lElbow = { 0.5, 0, 0 }
		P.neck = { -0.45, -math.cos(c) * 0.12, 0 }
	elseif mode == "present" then -- open arms: "ta-da!"
		P.twist[1] = 0.05
		P.rArm = { 0.75, 0, 0.8 }
		P.lArm = { 0.75, 0, -0.8 }
		P.rElbow = { 0.7, 0, 0 }
		P.lElbow = { 0.7, 0, 0 }
	end
	if t < talkUntil then
		P.neck[1] += math.sin(t * 16) * 0.05
	end

	local rootPy = breath * 0.035
	target("neck", P.neck)
	target(twistKey, P.twist)
	if twistKey ~= "root" then
		target("root", { 0, 0, 0 }, rootPy)
	elseif joints.root then
		joints.root.py.t = rootPy
	end
	target("rArm", P.rArm)
	target("lArm", P.lArm)
	target("rElbow", P.rElbow)
	target("lElbow", P.lElbow)
	if hipCompensate then
		local c = { -P.twist[1], -P.twist[2], -P.twist[3] }
		target("rHip", c)
		target("lHip", c)
	end

	local steps = math.ceil(dt * 120)
	local h = dt / steps
	for _, j in joints do
		for _ = 1, steps do
			j.x:step(h)
			j.y:step(h)
			j.z:step(h)
			j.py:step(h)
		end
		j.motor.C0 = CFrame.new(j.base.Position + Vector3.new(0, j.py.p, 0))
			* CFrame.Angles(j.x.p, j.y.p, j.z.p)
			* j.base.Rotation
	end
end)
]==]

-- Helpers ----------------------------------------------------------------------

local function part(parent, name, size, cf, color, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do p[k] = v end
	end
	p.Parent = parent
	return p
end

local function bounds(inst)
	local minV, maxV
	local list = {}
	if inst:IsA("BasePart") then table.insert(list, inst) end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	for _, p in list do
		local cf, s = p.CFrame, p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = cf:PointToWorldSpace(Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
					minV = minV and minV:Min(w) or w
					maxV = maxV and maxV:Max(w) or w
				end
			end
		end
	end
	return minV, maxV
end

local function findOldShop()
	if OLD_SHOP_NAME ~= "" then
		local found = workspace:FindFirstChild(OLD_SHOP_NAME, true)
		if not found then error(("No '%s' found in Workspace."):format(OLD_SHOP_NAME)) end
		return found
	end
	local sel = Selection:Get()[1]
	if sel and sel:IsDescendantOf(workspace) then
		if sel:IsA("Model") or sel:IsA("Folder") then return sel end
		return sel:FindFirstAncestorWhichIsA("Model") or sel
	end
	local candidates = {}
	for _, d in workspace:GetDescendants() do
		if (d:IsA("Model") or d:IsA("Folder")) and not d:FindFirstChildWhichIsA("Humanoid") then
			local n = d.Name:lower()
			-- exact names only, so things like "UpgradeWorkshop" are never touched
			if d:GetAttribute(TAG) or n == "shop" or n == "stall" or n == "store" or n == "shopstall" then
				table.insert(candidates, d)
			end
		end
	end
	local top = {}
	for _, c in candidates do
		local nested = false
		for _, other in candidates do
			if other ~= c and c:IsDescendantOf(other) then nested = true break end
		end
		if not nested then table.insert(top, c) end
	end
	if #top > 1 then
		local names = {}
		for _, c in top do table.insert(names, c:GetFullName()) end
		error("Found several possible shops - select the one to replace and run again:\n  "
			.. table.concat(names, "\n  "))
	end
	return top[1]
end

local function makeDummy(desc)
	return Players:CreateHumanoidModelFromDescription(
		desc or Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
end

local function loadNpc()
	local ok, objs = pcall(function()
		return game:GetObjects("rbxassetid://" .. NPC_ID)
	end)
	if ok and objs and #objs > 0 then
		-- A character model?
		for _, o in objs do
			local hum = o:IsA("Model") and o:FindFirstChildWhichIsA("Humanoid", true)
			if hum then
				local model = hum.Parent
				model.Parent = nil
				for _, other in objs do
					if other ~= model then other:Destroy() end
				end
				return model, "model " .. NPC_ID
			end
		end
		-- Clothing / accessories: dress a default character with them.
		local dummy = makeDummy()
		local hum = dummy:FindFirstChildWhichIsA("Humanoid")
		local applied = 0
		for _, o in objs do
			if o:IsA("Accessory") then
				if pcall(hum.AddAccessory, hum, o) then applied += 1 end
			elseif o:IsA("Shirt") or o:IsA("Pants") or o:IsA("ShirtGraphic") or o:IsA("BodyColors") then
				local existing = dummy:FindFirstChildWhichIsA(o.ClassName)
				if existing then existing:Destroy() end
				o.Parent = dummy
				applied += 1
			else
				o:Destroy()
			end
		end
		if applied > 0 then return dummy, "default character wearing item " .. NPC_ID end
		dummy:Destroy()
	end
	local ok2, desc = pcall(Players.GetHumanoidDescriptionFromOutfitId, Players, NPC_ID)
	if ok2 and desc then return makeDummy(desc), "outfit " .. NPC_ID end
	local ok3, desc2 = pcall(Players.GetHumanoidDescriptionFromUserId, Players, NPC_ID)
	if ok3 and desc2 then return makeDummy(desc2), "avatar of user " .. NPC_ID end
	warn("[ShopStall] Couldn't load " .. NPC_ID .. " - using a default character instead.")
	return makeDummy(), "default character"
end

-- Build ------------------------------------------------------------------------

local function buildStall(name)
	local WOOD = Color3.fromRGB(96, 62, 42)
	local WALL = Color3.fromRGB(120, 78, 52)
	local DARK = Color3.fromRGB(78, 50, 34)
	local TOP = Color3.fromRGB(92, 92, 98)
	local BLUE = Color3.fromRGB(30, 136, 214)
	local WHITE = Color3.fromRGB(242, 242, 242)

	local stall = Instance.new("Model")
	stall.Name = name
	stall:SetAttribute(TAG, true)
	stall.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local base = part(stall, "Base", Vector3.new(12, 0.2, 8), CFrame.new(), DARK,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	stall.PrimaryPart = base

	-- Posts: front ones shorter so the roof slopes down toward customers.
	local frame = Instance.new("Model")
	frame.Name = "Frame"
	frame.Parent = stall
	for _, x in { -5.5, 5.5 } do
		part(frame, "FrontPost", Vector3.new(1, 8.5, 1), CFrame.new(x, 4.25, -3.5), WOOD)
		part(frame, "BackPost", Vector3.new(1, 10.5, 1), CFrame.new(x, 5.25, 3.5), WOOD)
	end
	part(frame, "FrontBeam", Vector3.new(12, 0.6, 0.6), CFrame.new(0, 8, -3.5), WOOD)
	part(frame, "BackBeam", Vector3.new(12, 0.6, 0.6), CFrame.new(0, 10, 3.5), WOOD)

	-- Striped roof.
	local theta = math.atan2(2, 7)
	local tilt = CFrame.Angles(-theta, 0, 0)
	local ROOF_W, STRIPES = 13, 9
	local roofLen = 9.6 / math.cos(theta)
	local roofCF = CFrame.new(0, 9.5, 0) * tilt * CFrame.new(0, 0.3, 0)
	for _, x in { -5.5, 5.5 } do
		part(frame, "Rafter", Vector3.new(0.6, 0.5, roofLen),
			CFrame.new(x, 9.5, 0) * tilt * CFrame.new(0, -0.25, 0), WOOD)
	end
	local roof = Instance.new("Model")
	roof.Name = "Roof"
	roof.Parent = stall
	local w = ROOF_W / STRIPES
	for i = 0, STRIPES - 1 do
		local x = -ROOF_W / 2 + w * (i + 0.5)
		local color = i % 2 == 0 and BLUE or WHITE
		part(roof, "Stripe", Vector3.new(w, 0.6, roofLen), roofCF * CFrame.new(x, 0, 0), color)
		local edge = (roofCF * CFrame.new(x, -0.3, -roofLen / 2)).Position
		part(roof, "Flap", Vector3.new(w - 0.12, 0.6, 0.15),
			CFrame.new(edge + Vector3.new(0, -0.3, 0.06)), color)
	end

	-- Counter.
	local counter = Instance.new("Model")
	counter.Name = "Counter"
	counter.Parent = stall
	part(counter, "Wall", Vector3.new(10, 2.6, 0.8), CFrame.new(0, 1.3, -3.5), WALL)
	part(counter, "BottomRail", Vector3.new(10.2, 0.4, 1), CFrame.new(0, 0.2, -3.5), DARK)
	for _, y in { 0.95, 1.75 } do
		part(counter, "PlankLine", Vector3.new(10.04, 0.12, 0.86), CFrame.new(0, y, -3.5), DARK)
	end
	local top = part(counter, "ShopCounter", Vector3.new(12.4, 0.35, 1.9), CFrame.new(0, 2.775, -3.35), TOP)

	-- Hanging sign.
	local sign = part(stall, "Sign", Vector3.new(4.4, 1.3, 0.25), CFrame.new(0, 7.05, -3.55),
		Color3.fromRGB(240, 222, 176))
	for _, x in { -1.6, 1.6 } do
		part(stall, "SignChain", Vector3.new(0.12, 0.3, 0.12), CFrame.new(x, 7.85, -3.55),
			Color3.fromRGB(60, 60, 64))
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.6
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(96, 56, 34)
	label.Text = SIGN_TEXT
	label.Parent = gui
	Instance.new("UIPadding", label).PaddingTop = UDim.new(0, 6)

	return stall, top
end

local function addShopkeeper(stall, placeCF)
	local npc, source = loadNpc()
	npc.Name = "Shopkeeper"

	for _, d in npc:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then d:Destroy() end
	end

	local hum = npc:FindFirstChildWhichIsA("Humanoid")
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if not hrp then error("The NPC has no HumanoidRootPart, so it can't be animated.") end
	for _, d in npc:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = d == hrp end
	end
	npc.PrimaryPart = hrp
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum.EvaluateStateMachine = false

	-- Stand behind the counter, facing customers, feet on the ground.
	npc:PivotTo(placeCF * CFrame.new(0, 3, -1.4))
	local bbCF, bbSize = npc:GetBoundingBox()
	local bottom = bbCF.Position.Y - bbSize.Y / 2
	npc:PivotTo(npc:GetPivot() + Vector3.new(0, placeCF.Position.Y - bottom, 0))
	npc.Parent = stall

	local anim = Instance.new("Script")
	anim.Name = "ShopkeeperAnimator"
	anim.RunContext = Enum.RunContext.Client
	anim.Source = ANIM_SOURCE
	anim.Parent = npc

	return source, hum.RigType.Name
end

-- Run --------------------------------------------------------------------------

local recording = ChangeHistoryService:TryBeginRecording("Shop Stall")

local ok, err = pcall(function()
	local old = findOldShop()
	local isOurs = old and old:GetAttribute(TAG)

	local placeCF
	if isOurs then
		placeCF = old:GetPivot()
	elseif old then
		local minV, maxV = bounds(old)
		if not minV then error(old:GetFullName() .. " has no parts to measure.") end
		local center = (minV + maxV) / 2
		local yaw = 0
		if old:IsA("PVInstance") then
			local lv = old:GetPivot().LookVector
			if Vector3.new(lv.X, 0, lv.Z).Magnitude > 0.01 then yaw = math.atan2(-lv.X, -lv.Z) end
		end
		placeCF = CFrame.new(center.X, minV.Y, center.Z) * CFrame.Angles(0, yaw, 0)
	else
		local cam = workspace.CurrentCamera
		local focus = cam.Focus.Position
		local hit = workspace:Raycast(focus + Vector3.new(0, 50, 0), Vector3.new(0, -500, 0))
		local lv = cam.CFrame.LookVector
		placeCF = CFrame.new(hit and hit.Position or focus) * CFrame.Angles(0, math.atan2(lv.X, lv.Z), 0)
		warn("[ShopStall] No old shop found - built the stall where the camera is looking.")
	end

	local stall, counterTop = buildStall(old and old.Name or "ShopStall")
	stall:PivotTo(placeCF)

	local moved, scripts = 0, {}
	if old and not isOurs then
		for _, d in old:GetDescendants() do
			if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
				d.Parent = counterTop
				moved += 1
			elseif d:IsA("BaseScript") then
				table.insert(scripts, d:GetFullName())
			end
		end
	end
	if not counterTop:FindFirstChildWhichIsA("ProximityPrompt") and not counterTop:FindFirstChildWhichIsA("ClickDetector") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Shop"
		prompt.ObjectText = "Shopkeeper"
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = counterTop
	end

	local source, rig = addShopkeeper(stall, placeCF)
	stall.Parent = old and old.Parent or workspace

	if old then
		if isOurs then
			old:Destroy()
		else
			old.Name ..= "_OldShopBackup"
			old.Parent = ServerStorage
		end
	end
	Selection:Set({ stall })

	print(("[ShopStall] Built '%s' with the shopkeeper (%s, %s rig)."):format(stall.Name, source, rig))
	if old and not isOurs then
		print(("[ShopStall] Old shop saved as ServerStorage.%s; moved %d prompt(s) onto the new counter.")
			:format(old.Name, moved))
		if #scripts > 0 then
			warn("[ShopStall] The old shop had scripts inside it (kept in the backup, not moved). "
				.. "If they ran your shop, move them into the new stall and fix their paths:\n  "
				.. table.concat(scripts, "\n  "))
		end
	end
end)

if recording then
	ChangeHistoryService:FinishRecording(recording,
		ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
end
if not ok then
	warn("[ShopStall] " .. tostring(err))
end
