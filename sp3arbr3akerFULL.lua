--[[
Guide (minimal)
ESP [Ctrl+E] — player outlines + nametags. Nearest = pink. Names scale by distance.
Br3ak3r [Ctrl+Enter + Ctrl+LMB] — hide a single part; Ctrl+Z undo (max 20 recent). Hover preview while Ctrl held.
AutoClick [Ctrl+K] — click only when cursor hits a non-local player; optional head-only via Headshot.
Headshot [Ctrl+H] — gate AutoClick to head hits only.
Auto-F [Ctrl+C] — taps F at ~28 CPS; no key hold needed.
Sky Mode [Ctrl+L] — toggle bright daytime sky (client-only).
Waypoints [Ctrl+MMB] — add/remove at cursor. Hebrew NATO names + unique colors. Persist after shutdown.
Sp3ar [Ctrl+F] — while ON, holding RMB + F drives mouse to nearest head (no smoothing).
Killswitch [Ctrl+6] — full cleanup (UI, outlines, indicators, sky, connections). Waypoints persist.
]]

-- Updates (1.12b)
-- - Sp3ar reworked: no smoothing; uses VirtualInputManager mouse movement toward target head.
-- - Restores prior MouseBehavior on release or killswitch. No other systems changed.

-- Sp3arBr3ak3r-1.12b (LocalScript)

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local hasVIM, VirtualInputManager = pcall(function() return game:GetService("VirtualInputManager") end)

-- Config / Defaults
local ESP_ENABLED = true
local CLICKBREAK_ENABLED = true      -- shown as "Br3ak3r" in UI
local AUTOCLICK_ENABLED = false
local HEADSHOT_ONLY = false
local AUTOF_ENABLED = false          -- ~28 CPS
local SKY_MODE_ENABLED = false
local SP3AR_ENABLED = false          -- Ctrl+F

local MAX_CPS = 7
local AUTOF_PERIOD = 1/28
local UNDO_LIMIT = 20

-- Sp3ar tuning
local SP3AR_MAX_RANGE = math.huge
local SP3AR_REQUIRE_LINE_OF_SIGHT = true

-- Visuals
local PINK  = Color3.fromRGB(255,105,180)
local RED   = Color3.fromRGB(255,0,0)
local GREEN = Color3.fromRGB(0,200,0)
local WHITE = Color3.fromRGB(255,255,255)
local GRAY  = Color3.fromRGB(200,200,200)

-- Name tag and indicator sizing
local NAME_BASE_W, NAME_BASE_H = 120, 28
local NAME_MIN_SCALE, NAME_MAX_SCALE = 0.45, 2.6
local NAME_DIST_REF = 120
local EDGE_MARGIN = 24
local INDICATOR_SIZE = Vector2.new(110, 22)

-- Waypoint Hebrew NATO names and colors
local HEBREW_NATO = {
	"אלפא","בראבו","צ'רלי","דלתא","אקו","פוקסטרוט","גולף","הוטל","אינדיה","ז'ולייט",
	"קילו","לימה","מייק","נובמבר","אוסקר","פאפא","קוויבק","רומיאו","סיירה","טנגו",
	"יוניפורם","ויקטור","וויסקי","אקס-ריי","יאנקי","זולו"
}
local NATO_COLORS = {
	Color3.fromRGB(255,99,132), Color3.fromRGB(54,162,235), Color3.fromRGB(255,206,86),
	Color3.fromRGB(75,192,192), Color3.fromRGB(153,102,255), Color3.fromRGB(255,159,64),
	Color3.fromRGB(233,30,99),  Color3.fromRGB(0,188,212),  Color3.fromRGB(205,220,57),
	Color3.fromRGB(124,179,66), Color3.fromRGB(255,87,34),  Color3.fromRGB(63,81,181),
	Color3.fromRGB(0,150,136),  Color3.fromRGB(244,67,54),  Color3.fromRGB(121,85,72),
	Color3.fromRGB(158,158,158),Color3.fromRGB(3,169,244),  Color3.fromRGB(139,195,74),
	Color3.fromRGB(156,39,176), Color3.fromRGB(255,193,7),  Color3.fromRGB(96,125,139),
	Color3.fromRGB(0,230,118),  Color3.fromRGB(186,104,200),Color3.fromRGB(255,112,67),
	Color3.fromRGB(33,150,243), Color3.fromRGB(255,235,59)
}

-- State
local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local created, binds = {}, {}
local perPlayer = {}   -- [Player] = {bill, text, hum, outline, indicator}
local brokenSet = {}   -- [BasePart] = true
local undoStack = {}   -- LIFO of {part, cc, ltm, t}
local nearestPlayerRef = nil
local screenGui
local dead = false

-- Waypoints UI/State
local guideFrame, wpScroll, wpList
local wpRowMap = {}       -- [Part] = TextLabel
local wpIndicatorMap = {} -- [Part] = Frame
local wpNameIndex = 0
local indicatorFolder

-- Toggle UI setters
local setDotESP, setDotCB, setDotAC, setDotHS, setDotAF, setDotSKY, setDotSP3AR

-- Hover highlight (Br3ak3r)
local hoverHL

-- Sky backup/injected
local skyBackupFolder, skyInjected, atmosInjected

-- Helpers
local function track(i) created[#created+1] = i; return i end
local function bind(c) binds[#binds+1] = c; return c end
local function disconnectAll() for _,c in ipairs(binds) do pcall(function() c:Disconnect() end) end; table.clear(binds) end
local function destroyAll() for _,i in ipairs(created) do pcall(function() i:Destroy() end) end; table.clear(created) end
local function safeDestroy(x) if x then pcall(function() x:Destroy() end) end end
local function clamp(v, lo, hi) if v<lo then return lo elseif v>hi then return hi else return v end end

-- GUI root
do
	screenGui = track(Instance.new("ScreenGui"))
	screenGui.Name = "G"..HttpService:GenerateGUID(false):gsub("-","")
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 999999
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = (localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui"))

	indicatorFolder = track(Instance.new("Folder"))
	indicatorFolder.Name = "SB3_Indicators"
	indicatorFolder.Parent = screenGui
end

-- Guide UI
local function mkToggleRow(label, keybind)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1,0,0,16)
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(10,10)
	dot.Position = UDim2.new(0,0,0.5,-5)
	dot.BackgroundColor3 = Color3.fromRGB(200,0,0)
	dot.BorderSizePixel = 0
	dot.Parent = row
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1,0); dc.Parent = dot
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.new(0,16,0,-2)
	txt.Size = UDim2.new(1,-16,1,0)
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.TextYAlignment = Enum.TextYAlignment.Top
	txt.Font = Enum.Font.Gotham
	txt.TextSize = 12
	txt.TextColor3 = Color3.fromRGB(210,210,210)
	txt.Text = label.."  ["..keybind.."]"
	txt.Parent = row
	return row, function(active) dot.BackgroundColor3 = active and Color3.fromRGB(0,200,0) or Color3.fromRGB(200,0,0) end
end

local function ensureGuide()
	if guideFrame and guideFrame.Parent then return end
	guideFrame = track(Instance.new("Frame"))
	guideFrame.Name = "SB3_Guide"
	guideFrame.AnchorPoint = Vector2.new(0,0.5)
	guideFrame.Position = UDim2.fromScale(0.015, 0.5)
	guideFrame.Size = UDim2.fromOffset(290, 316)
	guideFrame.BackgroundColor3 = Color3.fromRGB(15,15,15)
	guideFrame.BackgroundTransparency = 0.25
	guideFrame.BorderSizePixel = 0
	guideFrame.ZIndex = 1000
	guideFrame.Parent = screenGui

	do
		local pad = Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0,8); pad.PaddingBottom=UDim.new(0,8); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.Parent=guideFrame
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = guideFrame

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromOffset(0,18)
		title.Text = "Sp3arBr3ak3r 1.12b"
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Top
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextColor3 = Color3.fromRGB(220,220,220)
		title.ZIndex = 1001
		title.Parent = guideFrame

		local togglesSection = track(Instance.new("Frame"))
		togglesSection.BackgroundTransparency = 1
		togglesSection.Position = UDim2.new(0,0,0,22)
		togglesSection.Size = UDim2.new(1,0,0,126)
		togglesSection.Parent = guideFrame

		local list = track(Instance.new("UIListLayout")); list.FillDirection=Enum.FillDirection.Vertical; list.SortOrder=Enum.SortOrder.LayoutOrder; list.Padding=UDim.new(0,2); list.Parent=togglesSection

		local r1, s1 = mkToggleRow("ESP","Ctrl+E"); r1.Parent = togglesSection; setDotESP = s1
		local r2, s2 = mkToggleRow("Br3ak3r","Ctrl+Enter"); r2.Parent = togglesSection; setDotCB = s2
		local r3, s3 = mkToggleRow("AutoClick","Ctrl+K"); r3.Parent = togglesSection; setDotAC = s3
		local r4, s4 = mkToggleRow("Headshot","Ctrl+H"); r4.Parent = togglesSection; setDotHS = s4
		local r5, s5 = mkToggleRow("Auto-F","Ctrl+C"); r5.Parent = togglesSection; setDotAF = s5
		local r6, s6 = mkToggleRow("Sky Mode","Ctrl+L"); r6.Parent = togglesSection; setDotSKY = s6
		local r7, s7 = mkToggleRow("Sp3ar","Ctrl+F"); r7.Parent = togglesSection; setDotSP3AR = s7

		local sep = track(Instance.new("Frame")); sep.Size=UDim2.new(1,0,0,1); sep.Position=UDim2.new(0,0,0,22+126+6); sep.BackgroundColor3=Color3.fromRGB(60,60,60); sep.BorderSizePixel=0; sep.Parent=guideFrame

		local listTitle = Instance.new("TextLabel")
		listTitle.BackgroundTransparency = 1
		listTitle.Position = UDim2.new(0,0,0,22+126+10)
		listTitle.Size = UDim2.new(1,0,0,16)
		listTitle.Text = "Waypoints:"
		listTitle.TextColor3 = Color3.fromRGB(200,200,200)
		listTitle.TextXAlignment = Enum.TextXAlignment.Left
		listTitle.Font = Enum.Font.GothamSemibold
		listTitle.TextSize = 12
		listTitle.ZIndex = 1001
		listTitle.Parent = guideFrame

		wpScroll = track(Instance.new("ScrollingFrame"))
		wpScroll.Name = "WPScroll"
		wpScroll.BackgroundTransparency = 1
		wpScroll.BorderSizePixel = 0
		wpScroll.Position = UDim2.new(0,0,0,22+126+28)
		wpScroll.Size = UDim2.new(1,0,1,-(22+126+36))
		wpScroll.ScrollBarThickness = 4
		wpScroll.CanvasSize = UDim2.new(0,0,0,0)
		wpScroll.ZIndex = 1001
		wpScroll.Parent = guideFrame

		wpList = track(Instance.new("UIListLayout")); wpList.FillDirection=Enum.FillDirection.Vertical; wpList.SortOrder=Enum.SortOrder.LayoutOrder; wpList.Padding=UDim.new(0,2); wpList.Parent=wpScroll
	end
end

local function updateToggleDots()
	if setDotESP then setDotESP(ESP_ENABLED) end
	if setDotCB then setDotCB(CLICKBREAK_ENABLED) end
	if setDotAC then setDotAC(AUTOCLICK_ENABLED) end
	if setDotHS then setDotHS(HEADSHOT_ONLY) end
	if setDotAF then setDotAF(AUTOF_ENABLED) end
	if setDotSKY then setDotSKY(SKY_MODE_ENABLED) end
	if setDotSP3AR then setDotSP3AR(SP3AR_ENABLED) end
end

-- Rays
local function screenToRay(x,y)
	camera = Workspace.CurrentCamera
	if not camera then return end
	local inset = GuiService:GetGuiInset()
	local vx,vy = x - inset.X, y - inset.Y
	return camera:ScreenPointToRay(vx,vy,0)
end
local function getMouseRay()
	local loc = UserInputService:GetMouseLocation()
	local ray = screenToRay(loc.X, loc.Y)
	if not ray then return end
	return ray.Origin, ray.Direction*1000, loc.X, loc.Y
end
local function worldRaycast(origin, direction, ignoreLocalChar, extraIgnore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for part,_ in pairs(brokenSet) do if part and part:IsDescendantOf(Workspace) then table.insert(ignore, part) end end
	if ignoreLocalChar then
		local ch = localPlayer.Character
		if ch then table.insert(ignore, ch) end
	end
	if extraIgnore then
		for _,inst in ipairs(extraIgnore) do table.insert(ignore, inst) end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return Workspace:Raycast(origin, direction, params)
end
local function hitIsPlayer(hitInst)
	if not hitInst or not hitInst:IsA("BasePart") then return nil end
	local model = hitInst:FindFirstAncestorOfClass("Model")
	if not model then return nil end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local p = Players:GetPlayerFromCharacter(model)
	if not p or p == localPlayer then return nil end
	return p, model
end

-- Indicators helpers
local function ensureIndicator(parent, key)
	local frame = parent:FindFirstChild(key)
	if frame then return frame end
	frame = Instance.new("Frame")
	frame.Name = key
	frame.Size = UDim2.fromOffset(INDICATOR_SIZE.X, INDICATOR_SIZE.Y)
	frame.BackgroundTransparency = 0.2
	frame.BackgroundColor3 = Color3.fromRGB(20,20,20)
	frame.BorderSizePixel = 0
	frame.ZIndex = 1200
	frame.Parent = indicatorFolder
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = frame

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"; arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromOffset(18,18); arrow.Position = UDim2.fromOffset(2,2)
	arrow.Font = Enum.Font.GothamBlack; arrow.Text = "▲"; arrow.TextSize = 16
	arrow.TextColor3 = WHITE; arrow.ZIndex = 1201; arrow.Parent = frame

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Lbl"; lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(22,0); lbl.Size = UDim2.new(1,-24,1,0)
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 12; lbl.TextColor3 = WHITE
	lbl.Text = ""; lbl.ZIndex = 1201; lbl.Parent = frame

	return frame
end
local function placeIndicator(frame, color, nameText, screenPos, angleRad)
	if not frame then return end
	local arrow = frame:FindFirstChild("Arrow"); if arrow then arrow.TextColor3 = color; arrow.Rotation = math.deg(angleRad) - 90 end
	local lbl = frame:FindFirstChild("Lbl"); if lbl then lbl.Text = nameText; lbl.TextColor3 = color end
	frame.Position = UDim2.fromOffset(screenPos.X - INDICATOR_SIZE.X/2, screenPos.Y - INDICATOR_SIZE.Y/2)
	frame.Visible = true
end
local function hideIndicator(frame) if frame then frame.Visible = false end end
local function projectToEdge(worldPos)
	if not camera then return nil end
	local v, onScreen = camera:WorldToViewportPoint(worldPos)
	local viewport = camera.ViewportSize
	local center = Vector2.new(viewport.X/2, viewport.Y/2)
	local pt = Vector2.new(v.X, v.Y)
	local dir = pt - center
	if v.Z < 0 then dir = -dir end
	if dir.Magnitude < 1e-3 then dir = Vector2.new(0,-1) end
	local half = Vector2.new(viewport.X/2 - EDGE_MARGIN, viewport.Y/2 - EDGE_MARGIN)
	local sx = math.abs(dir.X) / half.X
	local sy = math.abs(dir.Y) / half.Y
	local t = math.max(sx, sy, 1e-6)
	local edge = center + dir / t
	edge = Vector2.new(clamp(edge.X, EDGE_MARGIN, viewport.X-EDGE_MARGIN),
	                   clamp(edge.Y, EDGE_MARGIN, viewport.Y-EDGE_MARGIN))
	local angle = math.atan2(dir.Y, dir.X)
	return onScreen and v.Z>0, Vector2.new(v.X, v.Y), edge, angle
end

-- Br3ak3r
local function markBroken(part)
	if not part or not part:IsA("BasePart") then return end
	brokenSet[part] = true
	table.insert(undoStack, {part=part, cc=part.CanCollide, ltm=part.LocalTransparencyModifier, t=part.Transparency})
	if #undoStack > UNDO_LIMIT then table.remove(undoStack, 1) end
	part.CanCollide = false; part.LocalTransparencyModifier = 1; part.Transparency = 1
end
local function unbreakLast()
	local e = table.remove(undoStack)
	if not e or not e.part or not e.part:IsDescendantOf(game) then return end
	brokenSet[e.part] = nil
	e.part.CanCollide = e.cc; e.part.LocalTransparencyModifier = e.ltm; e.part.Transparency = e.t
end
local sweepAccum = 0
local function sweepUndo(dt)
	sweepAccum += dt
	if sweepAccum < 2 then return end
	sweepAccum = 0
	local i = 1
	while i <= #undoStack do
		local e = undoStack[i]
		if not e.part or not e.part:IsDescendantOf(game) then table.remove(undoStack, i) else i += 1 end
	end
end

-- ESP
local function destroyPerPlayer(p)
	local pp = perPlayer[p]; if not pp then return end
	if pp.bill then safeDestroy(pp.bill) end
	if pp.outline then safeDestroy(pp.outline) end
	if pp.indicator then safeDestroy(pp.indicator) end
	perPlayer[p] = nil
end
local function setESPVisible(p, visible)
	local pp = perPlayer[p]; if not pp then return end
	if pp.bill then pp.bill.Enabled = visible end
	if pp.outline then pp.outline.Enabled = visible end
end
local function createOutlineForCharacter(character, enabled)
	local h = Instance.new("Highlight"); h.Name="SB3_PinkOutline"; h.Adornee=character
	h.FillTransparency=1; h.OutlineTransparency=0; h.OutlineColor=PINK
	h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Enabled=enabled; h.Parent=character
	return h
end
local function billboardFor(p, character)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid"); if not head or not hum then return end
	local bill = Instance.new("BillboardGui"); bill.Name="B"..HttpService:GenerateGUID(false):gsub("-","")
	bill.AlwaysOnTop=true; bill.MaxDistance=1e9; bill.Adornee=head; bill.Size=UDim2.fromOffset(NAME_BASE_W, NAME_BASE_H)
	bill.StudsOffset=Vector3.new(0,2,0); bill.Enabled=ESP_ENABLED; bill.Parent=head; track(bill)
	local t = Instance.new("TextLabel"); t.Name="T"; t.BackgroundTransparency=1; t.Size=UDim2.fromScale(1,1)
	t.Font=Enum.Font.GothamBold; t.TextScaled=false; t.TextSize=14; t.TextColor3=RED; t.TextStrokeTransparency=0; t.TextStrokeColor3=WHITE; t.Text=""; t.Parent=bill
	perPlayer[p] = perPlayer[p] or {}; perPlayer[p].bill=bill; perPlayer[p].text=t; perPlayer[p].hum=hum
end
local function rebuildForCharacter(p, character)
	destroyPerPlayer(p); if not character then return end
	local outline = createOutlineForCharacter(character, ESP_ENABLED); billboardFor(p, character)
	perPlayer[p].outline = outline; perPlayer[p].indicator = ensureIndicator(indicatorFolder, "PI_"..p.UserId)
end
local function updateNearestPlayer()
	local myChar = localPlayer.Character; local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then nearestPlayerRef=nil return end
	local best, bestDist=nil,1e9
	for _,p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then
			local ch=p.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart")
			if root then local d=(root.Position - myRoot.Position).Magnitude; if d<bestDist then best, bestDist=p,d end end
		end
	end
	nearestPlayerRef = best
end
local function updatePlayerVisuals(dt)
	for p,pp in pairs(perPlayer) do
		local ch=p.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart"); local bill=pp.bill; local indicator=pp.indicator
		if not ch or not root then if bill then bill.Enabled=false end; hideIndicator(indicator)
		else
			local onScreen, v2, edge, angle = projectToEdge(root.Position)
			if bill and pp.text then
				local dist=(camera.CFrame.Position - root.Position).Magnitude
				local scale=math.clamp(NAME_DIST_REF / math.max(dist,1), NAME_MIN_SCALE, NAME_MAX_SCALE)
				bill.Size=UDim2.fromOffset(NAME_BASE_W*scale, NAME_BASE_H*scale)
				local hp=pp.hum and math.floor((pp.hum.Health or 0)+0.5) or 0
				pp.text.Text=string.format("%s  •  %dm  •  %dhp", p.DisplayName or p.Name, math.floor(dist+0.5), hp)
				if p==nearestPlayerRef then pp.text.TextColor3=PINK; pp.text.ZIndex=10 else pp.text.TextColor3=AUTOCLICK_ENABLED and GREEN or RED; pp.text.ZIndex=1 end
			end
			if onScreen and ESP_ENABLED then if bill then bill.Enabled=true end; hideIndicator(indicator)
			else
				if bill then bill.Enabled=false end
				local dist=(camera.CFrame.Position - root.Position).Magnitude
				local color=(p==nearestPlayerRef) and PINK or (AUTOCLICK_ENABLED and GREEN or RED)
				local label=string.format("%s · %dm", p.DisplayName or p.Name, math.floor(dist+0.5))
				placeIndicator(indicator, color, label, edge, angle)
			end
			if pp.outline then pp.outline.Enabled = ESP_ENABLED end
		end
	end
end
local function createForPlayer(p)
	local function onSpawn(character) task.wait(0.1); rebuildForCharacter(p, character) end
	bind(p.CharacterAdded:Connect(onSpawn)); if p.Character then onSpawn(p.Character) end
end
for _,p in ipairs(Players:GetPlayers()) do if p ~= localPlayer then createForPlayer(p) end end
bind(Players.PlayerAdded:Connect(function(p) if p ~= localPlayer then createForPlayer(p) end end))
bind(Players.PlayerRemoving:Connect(function(p) destroyPerPlayer(p) end))

-- Waypoints
local function getWpContainer() return Workspace:FindFirstChild("SP_WP_CONTAINER") end
local function nextWpNameAndColor() wpNameIndex=(wpNameIndex % #HEBREW_NATO)+1; return HEBREW_NATO[wpNameIndex], NATO_COLORS[wpNameIndex] end
local function setWaypointAppearance(part, name, color)
	part.Name="SP_WP_"..name; part:SetAttribute("SB3_Name", name); part:SetAttribute("SB3_Color", color)
	local bb=part:FindFirstChild("BB") or Instance.new("BillboardGui"); bb.Name="BB"; bb.AlwaysOnTop=true; bb.Size=UDim2.fromOffset(100,26); bb.StudsOffset=Vector3.new(0,1.5,0); bb.Parent=part
	local t=bb:FindFirstChild("T") or Instance.new("TextLabel"); t.Name="T"; t.BackgroundTransparency=1; t.Size=UDim2.fromScale(1,1); t.Font=Enum.Font.GothamBold; t.TextScaled=true; t.Text=name; t.TextColor3=color; t.TextStrokeTransparency=0.2; t.TextStrokeColor3=WHITE; t.Parent=bb
end
local function refreshWaypointGuide()
	local container=getWpContainer(); local parts={}
	if container then for _,ch in ipairs(container:GetChildren()) do if ch:IsA("Part") then table.insert(parts,ch) end end end
	local myPos; local ch=localPlayer.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart"); if root then myPos=root.Position end
	local sorted={}
	for _,p in ipairs(parts) do local d=myPos and (p.Position-myPos).Magnitude or math.huge; table.insert(sorted,{part=p,dist=d}) end
	table.sort(sorted,function(a,b) return a.dist<b.dist end)
	for part,row in pairs(wpRowMap) do if not part.Parent or not part:IsDescendantOf(container or Workspace) then if row and row.Parent then row:Destroy() end; wpRowMap[part]=nil end end
	local canvas=0
	for idx,entry in ipairs(sorted) do
		local part=entry.part; local dist=entry.dist
		local row=wpRowMap[part]; local name=part:GetAttribute("SB3_Name") or "??"; local color=part:GetAttribute("SB3_Color") or GRAY
		if not row then row=Instance.new("TextLabel"); row.BackgroundTransparency=1; row.Size=UDim2.new(1,0,0,16); row.TextXAlignment=Enum.TextXAlignment.Left; row.Font=Enum.Font.Gotham; row.TextSize=12; row.TextColor3=color; row.ZIndex=1002; row.Parent=wpScroll; wpRowMap[part]=row; track(row) end
		row.LayoutOrder=idx; row.Text=string.format("%s  ·  %dm", name, math.floor(dist+0.5)); row.TextColor3=color; canvas=canvas+18
	end
	wpScroll.CanvasSize=UDim2.new(0,0,0,canvas)
end
local function ensureWpIndicator(part)
	local key="WI_"..part:GetDebugId(); local frame=wpIndicatorMap[part]
	if frame and frame.Parent then return frame end
	frame=ensureIndicator(indicatorFolder, key); wpIndicatorMap[part]=frame; return frame
end
local function updateWaypointIndicators()
	local container=getWpContainer()
	for part,frame in pairs(wpIndicatorMap) do if not part.Parent or not part:IsDescendantOf(container or Workspace) then hideIndicator(frame); wpIndicatorMap[part]=nil end end
	if not container then return end
	for _,part in ipairs(container:GetChildren()) do
		if part:IsA("Part") then
			local name=part:GetAttribute("SB3_Name") or "WP"; local color=part:GetAttribute("SB3_Color") or GRAY
			local onscreen, v2, edge, angle = projectToEdge(part.Position)
			local bb=part:FindFirstChild("BB")
			if onscreen then if bb then bb.Enabled=true end; local f=wpIndicatorMap[part]; if f then hideIndicator(f) end
			else if bb then bb.Enabled=false end; local f=ensureWpIndicator(part); local dist=(camera.CFrame.Position - part.Position).Magnitude; placeIndicator(f, color, string.format("%s · %dm", name, math.floor(dist+0.5)), edge, angle) end
		end
	end
end

-- Sky Mode
local function enableSkyMode()
	if not skyBackupFolder then skyBackupFolder=Instance.new("Folder"); skyBackupFolder.Name="SB3_SkyBackup"; skyBackupFolder.Parent=Lighting; for _,o in ipairs(Lighting:GetChildren()) do if o:IsA("Sky") then o.Parent=skyBackupFolder end end end
	if not skyInjected then skyInjected=Instance.new("Sky"); skyInjected.Name="SB3_Sky"; skyInjected.CelestialBodiesShown=true; skyInjected.Parent=Lighting end
	if not atmosInjected then atmosInjected=Instance.new("Atmosphere"); atmosInjected.Name="SB3_Atmosphere"; atmosInjected.Color=Color3.fromRGB(200,220,255); atmosInjected.Decay=Color3.fromRGB(255,255,255); atmosInjected.Density=0.15; atmosInjected.Offset=0.25; atmosInjected.Glare=0; atmosInjected.Haze=0.25; atmosInjected.Parent=Lighting end
end
local function disableSkyMode()
	if skyBackupFolder then for _,o in ipairs(skyBackupFolder:GetChildren()) do o.Parent=Lighting end; safeDestroy(skyBackupFolder); skyBackupFolder=nil end
	safeDestroy(skyInjected); skyInjected=nil; safeDestroy(atmosInjected); atmosInjected=nil
end

-- Hover highlight for Br3ak3r
hoverHL = track(Instance.new("Highlight"))
hoverHL.Name = "SB3_Hover"; hoverHL.FillColor=PINK; hoverHL.OutlineColor=WHITE; hoverHL.FillTransparency=0.6; hoverHL.OutlineTransparency=0.2
hoverHL.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hoverHL.Enabled=false; hoverHL.Parent=Workspace

-- Input
local CTRL_HELD = false
bind(UserInputService.InputBegan:Connect(function(input,gp)
	if gp or dead then return end
	if input.KeyCode == Enum.KeyCode.LeftControl then CTRL_HELD = true end

	-- Br3ak3r action
	if CTRL_HELD and input.UserInputType == Enum.UserInputType.MouseButton1 and CLICKBREAK_ENABLED then
		local o,d = getMouseRay(); if o and d then local hit=worldRaycast(o,d,true); if hit and hit.Instance and hit.Instance:IsA("BasePart") then markBroken(hit.Instance) end end
	end

	-- Waypoints add/remove
	if CTRL_HELD and input.UserInputType == Enum.UserInputType.MouseButton3 then
		local o,d = getMouseRay(); if o and d then local r=worldRaycast(o,d,true); if r and r.Position then
			local pos=r.Position; local existing=Workspace:FindFirstChild("SP_WP_CONTAINER")
			if existing then for _,p in ipairs(existing:GetChildren()) do if p:IsA("Part") and (p.Position - pos).Magnitude < 10 then p:Destroy(); return end end end
			local container=existing or Instance.new("Folder"); container.Name="SP_WP_CONTAINER"; container.Parent=Workspace
			local part=Instance.new("Part"); part.Anchored=true; part.CanCollide=false; part.Transparency=1; part.Size=Vector3.new(1,1,1); part.Position=pos+Vector3.new(0,2,0)
			local name,color=nextWpNameAndColor(); setWaypointAppearance(part, name, color); part.Parent=container
		end end
	end
end))
bind(UserInputService.InputEnded:Connect(function(input,gp) if input.KeyCode == Enum.KeyCode.LeftControl then CTRL_HELD = false end end))

-- Toggle keys (with Ctrl)
bind(UserInputService.InputBegan:Connect(function(input,gp)
	if gp or not CTRL_HELD or dead then return end
	if input.KeyCode == Enum.KeyCode.Return then CLICKBREAK_ENABLED = not CLICKBREAK_ENABLED
	elseif input.KeyCode == Enum.KeyCode.K then AUTOCLICK_ENABLED = not AUTOCLICK_ENABLED
	elseif input.KeyCode == Enum.KeyCode.H then HEADSHOT_ONLY = not HEADSHOT_ONLY
	elseif input.KeyCode == Enum.KeyCode.C then AUTOF_ENABLED = not AUTOF_ENABLED
	elseif input.KeyCode == Enum.KeyCode.L then SKY_MODE_ENABLED = not SKY_MODE_ENABLED; if SKY_MODE_ENABLED then enableSkyMode() else disableSkyMode() end
	elseif input.KeyCode == Enum.KeyCode.E then ESP_ENABLED = not ESP_ENABLED; for p,_ in pairs(perPlayer) do setESPVisible(p, ESP_ENABLED) end
	elseif input.KeyCode == Enum.KeyCode.F then SP3AR_ENABLED = not SP3AR_ENABLED
	elseif input.KeyCode == Enum.KeyCode.Z then unbreakLast()
	elseif input.KeyCode == Enum.KeyCode.Six then
		dead = true
		AUTOCLICK_ENABLED=false; HEADSHOT_ONLY=false; AUTOF_ENABLED=false; ESP_ENABLED=false; SKY_MODE_ENABLED=false; CLICKBREAK_ENABLED=false; SP3AR_ENABLED=false
		disableSkyMode()
		disconnectAll()
		for p,_ in pairs(perPlayer) do destroyPerPlayer(p) end
		perPlayer = {}
		hoverHL.Enabled=false; safeDestroy(hoverHL)
		if guideFrame then safeDestroy(guideFrame) end
		for _,f in pairs(wpIndicatorMap) do safeDestroy(f) end
		wpIndicatorMap={}
		for i=#indicatorFolder:GetChildren(),1,-1 do safeDestroy(indicatorFolder:GetChildren()[i]) end
		safeDestroy(indicatorFolder)
		destroyAll()
		-- restore mouse behavior if we changed it
		pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
	end
end))

-- Auto-F, AutoClick, Sp3ar, UI refresh
local lastF, lastClick, uiAccum = 0,0,0

local prevMouseBehavior = nil
local function beginSp3arMouse()
	if not prevMouseBehavior then prevMouseBehavior = UserInputService.MouseBehavior end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end
local function endSp3arMouse()
	if prevMouseBehavior then pcall(function() UserInputService.MouseBehavior = prevMouseBehavior end); prevMouseBehavior = nil end
end

local function isRMBHeld() return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
local function isFHeld() return UserInputService:IsKeyDown(Enum.KeyCode.F) end

local function sp3arUpdate()
	if not SP3AR_ENABLED or not hasVIM then endSp3arMouse(); return end
	if not (isRMBHeld() and isFHeld()) then endSp3arMouse(); return end

	local targetP = nearestPlayerRef; if not targetP then endSp3arMouse(); return end
	local ch = targetP.Character; if not ch then endSp3arMouse(); return end
	local head = ch:FindFirstChild("Head"); if not head then endSp3arMouse(); return end

	-- Range + LOS checks
	if SP3AR_MAX_RANGE ~= math.huge then
		local myPos = camera.CFrame.Position
		if (head.Position - myPos).Magnitude > SP3AR_MAX_RANGE then endSp3arMouse(); return end
	end
	if SP3AR_REQUIRE_LINE_OF_SIGHT then
		local origin = camera.CFrame.Position
		local dir = head.Position - origin
		local hit = worldRaycast(origin, dir, true, {ch})
		if hit and hit.Instance then
			local _, m = hitIsPlayer(hit.Instance)
			if m ~= ch then endSp3arMouse(); return end
		end
	end

	beginSp3arMouse()

	-- Move mouse toward the head's projected position. No smoothing.
	local v, onScreen = camera:WorldToViewportPoint(head.Position)
	local viewport = camera.ViewportSize
	local center = Vector2.new(viewport.X/2, viewport.Y/2)
	local target = Vector2.new(v.X, v.Y)

	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		-- Supply deltas relative to center
		local dx = target.X - center.X
		local dy = target.Y - center.Y
		VirtualInputManager:SendMouseMove(dx, dy)
	else
		-- Absolute move when not locked
		VirtualInputManager:SendMouseMove(target.X, target.Y)
	end
end

bind(RunService.Heartbeat:Connect(function(dt)
	if dead then return end
	ensureGuide()
	updateToggleDots()

	-- Hover preview for Br3ak3r
	if CTRL_HELD and CLICKBREAK_ENABLED then
		local o,d = getMouseRay(); if o and d then local r=worldRaycast(o,d,true); local part=r and r.Instance
			if part and part:IsA("BasePart") and not brokenSet[part] then hoverHL.Adornee=part; hoverHL.Enabled=true else hoverHL.Enabled=false end
		else hoverHL.Enabled=false end
	else hoverHL.Enabled=false end

	-- Nearest and visuals
	updateNearestPlayer()
	updatePlayerVisuals(dt)

	-- Throttled UI work
	uiAccum += dt
	if uiAccum >= 0.1 then uiAccum = 0; refreshWaypointGuide(); updateWaypointIndicators() end

	-- Br3ak3r sweeper
	sweepUndo(dt)

	-- Auto-F
	if AUTOF_ENABLED and hasVIM then
		lastF += dt
		while lastF >= AUTOF_PERIOD do lastF -= AUTOF_PERIOD; VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game); VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game) end
	else lastF = 0 end

	-- AutoClick: ONLY when mouse over a valid player
	if AUTOCLICK_ENABLED and hasVIM then
		local o,d,mouseX,mouseY = getMouseRay()
		if o and d then
			local result = worldRaycast(o,d,true)
			local p = result and hitIsPlayer(result.Instance) or nil
			if p then
				local inst = result.Instance
				if not HEADSHOT_ONLY or (inst and inst.Name=="Head") then
					lastClick += dt; local threshold = 0.1 / math.max(0.1, MAX_CPS)
					if lastClick >= threshold then lastClick -= threshold; VirtualInputManager:SendMouseButtonEvent(mouseX, mouseY, 0, true, game, 0); VirtualInputManager:SendMouseButtonEvent(mouseX, mouseY, 0, false, game, 0) end
				else lastClick = 0 end
			else lastClick = 0 end
		end
	else lastClick = 0 end

	-- Sp3ar
	sp3arUpdate()
end))

-- Initial ESP visibility state
for p,_ in pairs(perPlayer) do setESPVisible(p, ESP_ENABLED) end

-- Character respawn handling for local player
bind(localPlayer.CharacterAdded:Connect(function()
	if dead then return end
	if indicatorFolder and indicatorFolder.Parent ~= screenGui then indicatorFolder.Parent = screenGui end
	if SKY_MODE_ENABLED then task.defer(enableSkyMode) end
end))
