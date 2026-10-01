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
