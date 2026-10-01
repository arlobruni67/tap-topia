-- SHOP STALL + ANIMATED SHOPKEEPER - replaces your current shop with a
-- blue/white striped market stall and an animated shopkeeper NPC.
--
-- HOW TO USE:
-- 1. In Studio, click your current shop model in the Explorer so it is
-- selected (or type its name into OLD_SHOP_NAME below).
-- 2. View > Command Bar. Paste this whole file there, press Enter.
-- 3. Check the Output window, then Save / Publish.
--
-- What it does:
-- - Builds the new stall where the old shop stood (same spot, same
-- facing, sitting on the same ground) and gives it the old shop's name.
-- - Moves the old shop's ProximityPrompts / ClickDetectors onto the new
-- counter, so "press E to shop" keeps working.
-- - Keeps the old shop as a backup in ServerStorage (nothing deleted).
-- - Loads the NPC from NPC_ID and animates it: breathing, looking
-- around, waving + saying hi when a player walks up, leaning on the
-- counter and following the player with its head, wiping the counter
-- when nobody is around, and a nod + "what'll it be?" when the shop
-- prompt is used. The animation runs on each player's device, so it
-- is perfectly smooth.
--
-- Run it again any time: it rebuilds the stall in place. Ctrl+Z undoes it.
-- If the stall faces the wrong way, just rotate the model with the
-- Rotate tool - everything inside moves with it.

local NPC_ID = 11330911907 -- model / outfit / user ID for the shopkeeper
local SIGN_TEXT = "SHOP"
local OLD_SHOP_NAME = "" -- leave "" to use the selected model or auto-find

local Players = game:GetService("Players")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local TAG = "TapTopiaShopStall"

local ANIM_SOURCE = table.concat({
	"-- Shopkeeper animation. RunContext = Client, so every player animates the",
	"-- NPC locally (smooth, no network lag) and the NPC reacts to THAT player.",
	"local Players = game:GetService(\"Players\")",
	"local RunService = game:GetService(\"RunService\")",
	"local TweenService = game:GetService(\"TweenService\")",
	"",
	"local npc = script.Parent",
	"local shop = npc.Parent",
	"local player = Players.LocalPlayer",
	"local humanoid = npc:WaitForChild(\"Humanoid\")",
	"local root = npc:WaitForChild(\"HumanoidRootPart\")",
	"local head = npc:WaitForChild(\"Head\")",
	"",
	"local GREET_RANGE = 16 -- studs: wave + say hi when a player gets this close",
	"local FORGET_RANGE = 28 -- studs: walk this far away to get greeted again",
	"local GREETINGS = { \"Hey there, welcome!\", \"Howdy! Take a look around!\", \"Ooh, a customer!\" }",
	"local PROMPT_LINES = { \"What'll it be?\", \"Great choice!\", \"Take your time!\" }",
	"",
	"local rng = Random.new()",
	"local function pick(list)",
	"\treturn list[rng:NextInteger(1, #list)]",
	"end",
	"",
	"-- Joints -----------------------------------------------------------------",
	"local function find(partName, jointName)",
	"\tlocal part = partName == \"\" and root or npc:WaitForChild(partName, 5)",
	"\treturn part and part:WaitForChild(jointName, 5)",
	"end",
	"",
	"local J",
	"if humanoid.RigType == Enum.HumanoidRigType.R6 then",
	"\tJ = {",
	"\t\tneck = find(\"Torso\", \"Neck\"),",
	"\t\troot = find(\"\", \"RootJoint\"),",
	"\t\trArm = find(\"Torso\", \"Right Shoulder\"),",
	"\t\tlArm = find(\"Torso\", \"Left Shoulder\"),",
	"\t\trHip = find(\"Torso\", \"Right Hip\"),",
	"\t\tlHip = find(\"Torso\", \"Left Hip\"),",
	"\t}",
	"else",
	"\tJ = {",
	"\t\tneck = find(\"Head\", \"Neck\"),",
	"\t\troot = find(\"LowerTorso\", \"Root\"),",
	"\t\twaist = find(\"UpperTorso\", \"Waist\"),",
	"\t\trArm = find(\"RightUpperArm\", \"RightShoulder\"),",
	"\t\tlArm = find(\"LeftUpperArm\", \"LeftShoulder\"),",
	"\t\trElbow = find(\"RightLowerArm\", \"RightElbow\"),",
	"\t\tlElbow = find(\"LeftLowerArm\", \"LeftElbow\"),",
	"\t}",
	"end",
	"",
	"-- Springs give every motion a soft start, a tiny overshoot and a settle.",
	"local Spring = {}",
	"Spring.__index = Spring",
	"function Spring.new(freq, damp)",
	"\treturn setmetatable({ p = 0, v = 0, t = 0, f = freq, d = damp }, Spring)",
	"end",
	"function Spring:step(dt)",
	"\tlocal f = self.f",
	"\tself.v += (f * f * (self.t - self.p) - 2 * self.d * f * self.v) * dt",
	"\tself.p += self.v * dt",
	"end",
	"",
	"local TUNING = {",
	"\tneck = { 11, 0.65 }, root = { 7, 0.8 }, waist = { 8, 0.7 },",
	"\trArm = { 10, 0.55 }, lArm = { 10, 0.55 }, rElbow = { 12, 0.6 }, lElbow = { 12, 0.6 },",
	"\trHip = { 7, 0.8 }, lHip = { 7, 0.8 },",
	"}",
	"",
	"local joints = {}",
	"for key, motor in J do",
	"\tif motor and motor:IsA(\"Motor6D\") then",
	"\t\tlocal f, d = TUNING[key][1], TUNING[key][2]",
	"\t\tjoints[key] = {",
	"\t\t\tmotor = motor,",
	"\t\t\tbase = motor.C0,",
	"\t\t\tx = Spring.new(f, d), y = Spring.new(f, d), z = Spring.new(f, d), py = Spring.new(f, d),",
	"\t\t}",
	"\tend",
	"end",
	"",
	"-- R15 bends at the waist; R6 bends at the root and the hips counter it so",
	"-- the legs stay planted.",
	"local twistKey = joints.waist and \"waist\" or \"root\"",
	"local hipCompensate = joints.waist == nil",
	"",
	"local function target(key, a, py)",
	"\tlocal j = joints[key]",
	"\tif not j then return end",
	"\tj.x.t, j.y.t, j.z.t = a[1], a[2], a[3]",
	"\tif py then j.py.t = py end",
	"end",
	"",
	"local function kick(key, axis, amount)",
	"\tlocal j = joints[key]",
	"\tif j then j[axis].v += amount end",
	"end",
	"",
	"-- Speech bubble ------------------------------------------------------------",
	"local bubbleGui, bubbleToken, talkUntil = nil, 0, 0",
	"",
	"local function say(text)",
	"\tbubbleToken += 1",
	"\tlocal token = bubbleToken",
	"\tif bubbleGui then bubbleGui:Destroy() end",
	"",
	"\tlocal gui = Instance.new(\"BillboardGui\")",
	"\tgui.Name = \"ShopkeeperBubble\"",
	"\tgui.Adornee = head",
	"\tgui.Size = UDim2.fromOffset(280, 80)",
	"\tgui.StudsOffset = Vector3.new(0, 2.7, 0)",
	"\tgui.MaxDistance = 70",
	"\tgui.LightInfluence = 0",
	"\tgui.ResetOnSpawn = false",
	"\tbubbleGui = gui",
	"",
	"\tlocal frame = Instance.new(\"Frame\")",
	"\tframe.AnchorPoint = Vector2.new(0.5, 1)",
	"\tframe.Position = UDim2.new(0.5, 0, 1, -8)",
	"\tframe.Size = UDim2.fromOffset(0, 0)",
	"\tframe.AutomaticSize = Enum.AutomaticSize.XY",
	"\tframe.BackgroundColor3 = Color3.new(1, 1, 1)",
	"\tframe.Parent = gui",
	"\tInstance.new(\"UICorner\", frame).CornerRadius = UDim.new(0, 14)",
	"\tlocal pad = Instance.new(\"UIPadding\", frame)",
	"\tpad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)",
	"\tpad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)",
	"\tlocal scale = Instance.new(\"UIScale\", frame)",
	"\tscale.Scale = 0.4",
	"",
	"\tlocal tail = Instance.new(\"Frame\")",
	"\ttail.AnchorPoint = Vector2.new(0.5, 0.5)",
	"\ttail.Position = UDim2.new(0.5, 0, 1, 8)",
	"\ttail.Size = UDim2.fromOffset(14, 14)",
	"\ttail.Rotation = 45",
	"\ttail.BorderSizePixel = 0",
	"\ttail.BackgroundColor3 = frame.BackgroundColor3",
	"\ttail.ZIndex = 0",
	"\ttail.Parent = frame",
	"",
	"\tlocal label = Instance.new(\"TextLabel\")",
	"\tlabel.BackgroundTransparency = 1",
	"\tlabel.Size = UDim2.fromOffset(0, 0)",
	"\tlabel.AutomaticSize = Enum.AutomaticSize.XY",
	"\tlabel.Font = Enum.Font.FredokaOne",
	"\tlabel.TextSize = 22",
	"\tlabel.TextColor3 = Color3.fromRGB(40, 40, 48)",
	"\tlabel.Text = text",
	"\tlabel.MaxVisibleGraphemes = 0",
	"\tlabel.Parent = frame",
	"",
	"\tgui.Parent = player:WaitForChild(\"PlayerGui\")",
	"\tTweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()",
	"",
	"\ttask.spawn(function()",
	"\t\tlocal n = utf8.len(text) or #text",
	"\t\ttalkUntil = os.clock() + n * 0.03",
	"\t\tfor i = 1, n do",
	"\t\t\tif token ~= bubbleToken then return end",
	"\t\t\tlabel.MaxVisibleGraphemes = i",
	"\t\t\ttask.wait(0.03)",
	"\t\tend",
	"\t\ttask.wait(2.6)",
	"\t\tif token ~= bubbleToken then return end",
	"\t\tlocal fade = TweenInfo.new(0.3)",
	"\t\tTweenService:Create(frame, fade, { BackgroundTransparency = 1 }):Play()",
	"\t\tTweenService:Create(tail, fade, { BackgroundTransparency = 1 }):Play()",
	"\t\tTweenService:Create(label, fade, { TextTransparency = 1 }):Play()",
	"\t\tTweenService:Create(scale, fade, { Scale = 0.8 }):Play()",
	"\t\ttask.wait(0.35)",
	"\t\tif token == bubbleToken then gui:Destroy() end",
	"\tend)",
	"end",
	"",
	"-- Behaviour ----------------------------------------------------------------",
	"local mode, modeEnd = \"idle\", 0",
	"local greeted = false",
	"local nextWipe = os.clock() + rng:NextNumber(4, 8)",
	"local nextGlance, glanceTarget = 0, nil",
	"",
	"local function setMode(m, duration)",
	"\tmode, modeEnd = m, os.clock() + duration",
	"end",
	"",
	"local function onPrompt()",
	"\tsetMode(\"present\", 1.8)",
	"\tkick(\"neck\", \"x\", -6)",
	"\tsay(pick(PROMPT_LINES))",
	"end",
	"",
	"local function hook(d)",
	"\tif d:IsA(\"ProximityPrompt\") then",
	"\t\td.Triggered:Connect(onPrompt)",
	"\telseif d:IsA(\"ClickDetector\") then",
	"\t\td.MouseClick:Connect(onPrompt)",
	"\tend",
	"end",
	"for _, d in shop:GetDescendants() do hook(d) end",
	"shop.DescendantAdded:Connect(hook)",
	"",
	"RunService.RenderStepped:Connect(function(dt)",
	"\tif not npc.Parent then return end",
	"\tlocal cam = workspace.CurrentCamera",
	"\tif (cam.CFrame.Position - root.Position).Magnitude > 150 then return end",
	"\tdt = math.min(dt, 0.1)",
	"\tlocal t = os.clock()",
	"",
	"\tlocal char = player.Character",
	"\tlocal pHead = char and char:FindFirstChild(\"Head\")",
	"\tlocal dist = pHead and (pHead.Position - root.Position).Magnitude or math.huge",
	"",
	"\tif dist > FORGET_RANGE then greeted = false end",
	"\tif dist < GREET_RANGE and not greeted and mode ~= \"present\" then",
	"\t\tgreeted = true",
	"\t\tsetMode(\"wave\", 2.6)",
	"\t\tkick(\"neck\", \"x\", -4)",
	"\t\tsay(pick(GREETINGS))",
	"\tend",
	"\tif t > modeEnd then",
	"\t\tif dist < FORGET_RANGE then",
	"\t\t\tmode = \"lean\"",
	"\t\telseif t > nextWipe then",
	"\t\t\tsetMode(\"wipe\", rng:NextNumber(3.5, 5))",
	"\t\t\tnextWipe = t + rng:NextNumber(9, 15)",
	"\t\telse",
	"\t\t\tmode = \"idle\"",
	"\t\tend",
	"\tend",
	"",
	"\t-- Where to look: the player if they're around, otherwise glance about.",
	"\tlocal lookAt",
	"\tif pHead and dist < FORGET_RANGE then",
	"\t\tlookAt = pHead.Position",
	"\telse",
	"\t\tif t > nextGlance then",
	"\t\t\tnextGlance = t + rng:NextNumber(1.8, 4.5)",
	"\t\t\tglanceTarget = root.CFrame:PointToWorldSpace(",
	"\t\t\t\tVector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-1.5, 2), -12))",
	"\t\tend",
	"\t\tlookAt = glanceTarget",
	"\tend",
	"\tlocal yaw, pitch = 0, 0",
	"\tif lookAt then",
	"\t\tlocal rel = root.CFrame:PointToObjectSpace(lookAt)",
	"\t\tyaw = math.atan2(-rel.X, -rel.Z)",
	"\t\tpitch = math.atan2(rel.Y - 1.5, math.sqrt(rel.X * rel.X + rel.Z * rel.Z))",
	"\t\tif math.abs(yaw) > 2.1 then yaw, pitch = 0, 0 end -- behind: no owl turns",
	"\t\tyaw = math.clamp(yaw, -1.3, 1.3)",
	"\t\tpitch = math.clamp(pitch, -0.6, 0.5)",
	"\tend",
	"",
	"\t-- Pose (angles in radians, in the torso's space: x = pitch, y = yaw, z = roll)",
	"\tlocal breath = math.sin(t * 2.1)",
	"\tlocal sway = math.sin(t * 0.55)",
	"\tlocal P = {",
	"\t\tneck = { pitch * 0.8 + breath * 0.015, yaw * 0.7, 0 },",
	"\t\ttwist = { 0, yaw * 0.3, sway * 0.025 },",
	"\t\trArm = { 0.06 + breath * 0.03, 0, 0.07 + breath * 0.02 },",
	"\t\tlArm = { 0.06 + breath * 0.03, 0, -0.07 - breath * 0.02 },",
	"\t\trElbow = { 0.15, 0, 0 },",
	"\t\tlElbow = { 0.15, 0, 0 },",
	"\t}",
	"",
	"\tif mode == \"lean\" then -- hands on the counter, attentive, curious head tilt",
	"\t\tP.twist[1] = -0.14",
	"\t\tP.rArm = { 1.2 + breath * 0.02, 0, 0.12 }",
	"\t\tP.lArm = { 1.2 + breath * 0.02, 0, -0.12 }",
	"\t\tP.rElbow = { 0.6, 0, 0 }",
	"\t\tP.lElbow = { 0.6, 0, 0 }",
	"\t\tP.neck[3] = math.sin(t * 0.4) * 0.08",
	"\telseif mode == \"wave\" then",
	"\t\tlocal w = math.sin(t * 12)",
	"\t\tP.rArm = { 0.25, 0, 2.55 + w * 0.35 }",
	"\t\tP.rElbow = { 0.5 + w * 0.25, 0, 0 }",
	"\t\tP.twist[2] = yaw * 0.35",
	"\t\tP.twist[3] = -0.05",
	"\t\tP.neck[3] = 0.12",
	"\telseif mode == \"wipe\" then -- rag circles on the counter, eyes on the rag",
	"\t\tlocal c = t * 5.5",
	"\t\tP.twist = { -0.2, math.cos(c) * 0.06, sway * 0.025 }",
	"\t\tP.rArm = { 1.25 + math.sin(c) * 0.13, 0, 0.18 + math.cos(c) * 0.28 }",
	"\t\tP.lArm = { 1.15, 0, -0.15 }",
	"\t\tP.rElbow = { 0.5, 0, 0 }",
	"\t\tP.lElbow = { 0.5, 0, 0 }",
	"\t\tP.neck = { -0.45, -math.cos(c) * 0.12, 0 }",
	"\telseif mode == \"present\" then -- open arms: \"ta-da!\"",
	"\t\tP.twist[1] = 0.05",
	"\t\tP.rArm = { 0.75, 0, 0.8 }",
	"\t\tP.lArm = { 0.75, 0, -0.8 }",
	"\t\tP.rElbow = { 0.7, 0, 0 }",
	"\t\tP.lElbow = { 0.7, 0, 0 }",
	"\tend",
	"\tif t < talkUntil then",
	"\t\tP.neck[1] += math.sin(t * 16) * 0.05",
	"\tend",
	"",
	"\tlocal rootPy = breath * 0.035",
	"\ttarget(\"neck\", P.neck)",
	"\ttarget(twistKey, P.twist)",
	"\tif twistKey ~= \"root\" then",
	"\t\ttarget(\"root\", { 0, 0, 0 }, rootPy)",
	"\telseif joints.root then",
	"\t\tjoints.root.py.t = rootPy",
	"\tend",
	"\ttarget(\"rArm\", P.rArm)",
	"\ttarget(\"lArm\", P.lArm)",
	"\ttarget(\"rElbow\", P.rElbow)",
	"\ttarget(\"lElbow\", P.lElbow)",
	"\tif hipCompensate then",
	"\t\tlocal c = { -P.twist[1], -P.twist[2], -P.twist[3] }",
	"\t\ttarget(\"rHip\", c)",
	"\t\ttarget(\"lHip\", c)",
	"\tend",
	"",
	"\tlocal steps = math.ceil(dt * 120)",
	"\tlocal h = dt / steps",
	"\tfor _, j in joints do",
	"\t\tfor _ = 1, steps do",
	"\t\t\tj.x:step(h)",
	"\t\t\tj.y:step(h)",
	"\t\t\tj.z:step(h)",
	"\t\t\tj.py:step(h)",
	"\t\tend",
	"\t\tj.motor.C0 = CFrame.new(j.base.Position + Vector3.new(0, j.py.p, 0))",
	"\t\t\t* CFrame.Angles(j.x.p, j.y.p, j.z.p)",
	"\t\t\t* j.base.Rotation",
	"\tend",
	"end)",
}, "\n")

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
