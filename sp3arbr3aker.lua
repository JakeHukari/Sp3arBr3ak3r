-- Sp3arBr3ak3r Lite - minimal client-only utilities
-- Features: Guide, ESP, Br3ak3r (hide part), AutoClick, Waypoints, Killswitch

local globalEnv = (getgenv and getgenv()) or _G
if globalEnv.SP3ARBR3AKER_ACTIVE then
	return
end
globalEnv.SP3ARBR3AKER_ACTIVE = true

local stepWait = (task and task.wait) or wait
local function stepSpawn(fn, ...)
	if task and task.spawn then
		return task.spawn(fn, ...)
	end
	local thread = coroutine.create(fn)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		warn("[Sp3arBr3ak3r] spawn error: " .. tostring(err))
	end
	return thread
end

local function releaseGlobalFlag()
	if globalEnv then
		globalEnv.SP3ARBR3AKER_ACTIVE = nil
	end
end

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local hasVIM, VirtualInputManager = pcall(function()
	return game:GetService("VirtualInputManager")
end)

-- State
local localPlayer = Players.LocalPlayer
if not localPlayer then
	repeat
		stepWait()
		localPlayer = Players.LocalPlayer
	until localPlayer
end

local camera = Workspace.CurrentCamera
if not camera then
	repeat
		stepWait()
		camera = Workspace.CurrentCamera
	until camera
end

local mouse = localPlayer:GetMouse()
local ESP_ENABLED = true
local BREAKER_ENABLED = true
local AUTOCLICK_ENABLED = false
local FULLBRIGHT_ENABLED = false
local ESP_MAX_RANGE = 2500 -- studs (max)

-- AutoClick rate (clicks per second)
local SP3AR_AUTOCLICK_HZ = 10
local UNDO_LIMIT = 20
local HEAVY_TARGET_HZ = 15 -- target heavy refresh per player per second
local HEAVY_STRIDE_MIN = 1
local HEAVY_STRIDE_MAX = 8

local created, binds = {}, {}
local function track(i)
	created[#created + 1] = i
	return i
end
local function bind(c)
	binds[#binds + 1] = c
	return c
end
local function disconnectAll()
	for _, c in ipairs(binds) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(binds)
end
local function destroyAll()
	for _, i in ipairs(created) do
		pcall(function()
			i:Destroy()
		end)
	end
	table.clear(created)
end

local dead = false
local ctrlDown = false
local uiReady = false
local minimized = false
local dragging = false
local dragStart
local frameStart
local expandedHeight = 120
local minimizedHeight = 30
local loadAnimNext = 0
local loadAnimStep = 0
local guideHidden = false
local devHUDEnabled = false
local devNextHUD = 0
local lastVisCount = 0

local function resolveGuiParent()
	if typeof(gethui) == "function" then
		local ok, ui = pcall(gethui)
		if ok and typeof(ui) == "Instance" and ui.Parent then
			return ui
		end
	end

	if localPlayer then
		local gui = localPlayer:FindFirstChildOfClass("PlayerGui")
		if gui then
			return gui
		end
		local ok, waited = pcall(function()
			return localPlayer:WaitForChild("PlayerGui", 2)
		end)
		if ok and waited then
			return waited
		end
	end

	local ok, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and core then
		return core
	end

	return nil
end

local function parentGui(gui)
	if not gui or gui.Parent then
		return
	end
	local target = resolveGuiParent()
	if target then
		if syn and syn.protect_gui then
			pcall(syn.protect_gui, gui)
		end
		gui.Parent = target
	else
		stepSpawn(function()
			stepWait(0.25)
			if gui and not gui.Parent then
				parentGui(gui)
			end
		end)
	end
end
-- UI roots
local screenGui
local guideFrame
local espFolder
local wpFolder
local togglesSection
local titleBar
local minimizeBtn
local loadingLabel
local devFrame
local devLabel

-- Guide toggles indicators
local setDotESP, setDotBR, setDotAC, setDotFB, setWpCount, setDotDEV

-- ESP cache
local perPlayer = {}   -- [Player] = {label=TextLabel, lastVis=false, lastText=nil, lastW=nil, lastBorder=nil, lastBucket=nil}
local enemyList = {}   -- array of tracked enemy players

-- Br3ak3r (hide part) state
local hoverBox
local hoverAdornee
local undoStack = {} -- { {part=BasePart, ltm=number} }
local brokenSet = {} -- [BasePart] = true

-- Waypoints state (pure client, UI-only)
local waypoints = {} -- { {pos=Vector3, name=string, color=Color3, label=TextLabel} }
local wpColors = {
	Color3.fromRGB(54, 162, 235),
	Color3.fromRGB(255, 99, 132),
	Color3.fromRGB(255, 206, 86),
	Color3.fromRGB(75, 192, 192),
	Color3.fromRGB(153, 102, 255),
}

-- Colors
local OUTLINE_RED = Color3.fromRGB(220, 60, 60)
local OUTLINE_GREEN = Color3.fromRGB(60, 200, 80)
local OUTLINE_PINK = Color3.fromRGB(255, 105, 180)

-- Utils
local rng = Random.new()
local function now()
    return os.clock()
end
local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	else
		return v
	end
end

local function safeSet(obj, prop, val)
    pcall(function()
        obj[prop] = val
    end)
end

local function safeGet(obj, prop)
    local ok, v = pcall(function()
        return obj[prop]
    end)
    if ok then
        return v
    end
    return nil
end

-- UI helpers
local function mkToggleRow(label, keybind)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 18)
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(10, 10)
	dot.Position = UDim2.new(0, 0, 0.5, -5)
	dot.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
	dot.BorderSizePixel = 0
	dot.Parent = row
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(1, 0)
	dc.Parent = dot
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.new(0, 16, 0, -2)
	txt.Size = UDim2.new(1, -16, 1, 0)
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.TextYAlignment = Enum.TextYAlignment.Top
	txt.Font = Enum.Font.Gotham
	txt.TextSize = 12
	txt.TextColor3 = Color3.fromRGB(210, 210, 210)
	txt.Text = label .. "  [" .. keybind .. "]"
	txt.Parent = row
	return row, function(active)
		dot.BackgroundColor3 = active and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(200, 0, 0)
	end
end

local function mkLabel(parent)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.fromOffset(120, 16)
    l.AnchorPoint = Vector2.new(0.5, 1)
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextColor3 = Color3.fromRGB(230, 230, 230)
    l.BorderSizePixel = 2
    l.BorderColor3 = OUTLINE_RED
    l.AutoLocalize = false
    l.Parent = parent
    return l
end

local function ensureUI()
    if guideFrame and guideFrame.Parent then
        return
    end
    screenGui = track(Instance.new("ScreenGui"))
    screenGui.Name = "SystemUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 1
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    parentGui(screenGui)

    bind(screenGui.AncestryChanged:Connect(function(_, parent)
        if not parent and not dead then
            parentGui(screenGui)
        end
    end))

    espFolder = track(Instance.new("Folder"))
    espFolder.Name = "Overlay"
    espFolder.Parent = screenGui

    wpFolder = track(Instance.new("Folder"))
    wpFolder.Name = "Waypoints"
    wpFolder.Parent = screenGui

    guideFrame = track(Instance.new("Frame"))
    guideFrame.Name = "Guide"
    guideFrame.AnchorPoint = Vector2.new(0, 0)
    local vp = camera and camera.ViewportSize or Vector2.new(800, 600)
    guideFrame.Position = UDim2.fromOffset(math.floor(vp.X * 0.012), math.floor(vp.Y * 0.4))
    guideFrame.Size = UDim2.fromOffset(230, 120)
    guideFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    guideFrame.BackgroundTransparency = 0.25
    guideFrame.BorderSizePixel = 0
    guideFrame.ZIndex = 10
    guideFrame.Parent = screenGui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = guideFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = guideFrame

    titleBar = track(Instance.new("Frame"))
    titleBar.Name = "TitleBar"
    titleBar.BackgroundTransparency = 1
    titleBar.Size = UDim2.new(1, 0, 0, 20)
    titleBar.Parent = guideFrame
    local title = track(Instance.new("TextLabel"))
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -28, 0, 18)
    title.Text = "Guide"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Top
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(220, 220, 220)
    title.ZIndex = 11
    title.Parent = titleBar
    minimizeBtn = track(Instance.new("TextButton"))
    minimizeBtn.Name = "Minimize"
    minimizeBtn.BackgroundTransparency = 1
    minimizeBtn.Text = "–"
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.TextSize = 16
    minimizeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
    minimizeBtn.Size = UDim2.fromOffset(20, 18)
    minimizeBtn.Position = UDim2.new(1, -22, 0, 0)
    minimizeBtn.ZIndex = 12
    minimizeBtn.Parent = titleBar

    togglesSection = track(Instance.new("Frame"))
    togglesSection.BackgroundTransparency = 1
    togglesSection.Position = UDim2.new(0, 0, 0, 22)
    togglesSection.Size = UDim2.new(1, 0, 1, -22)
    togglesSection.Parent = guideFrame

    local list = track(Instance.new("UIListLayout"))
    list.FillDirection = Enum.FillDirection.Vertical
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 2)
    list.Parent = togglesSection

    local r1, s1 = mkToggleRow("ESP", "Ctrl+E")
    r1.Parent = togglesSection
    setDotESP = s1

    local r2, s2 = mkToggleRow("Br3ak3r", "Ctrl+Enter / Ctrl+LMB")
    r2.Parent = togglesSection
    setDotBR = s2

    local r3, s3 = mkToggleRow("AutoClick", "Ctrl+K")
    r3.Parent = togglesSection
    setDotAC = s3

    local rFB, sFB = mkToggleRow("Fullbright", "Ctrl+L")
    rFB.Parent = togglesSection
    setDotFB = sFB

    local r4 = mkToggleRow("Waypoints: Ctrl+MMB", "count: 0")
    r4.Parent = togglesSection
    setWpCount = function(count)
        local lbl = r4:FindFirstChildOfClass("TextLabel")
        if lbl then
            lbl.Text = "Waypoints: Ctrl+MMB  [count: " .. tostring(count) .. "]"
        end
    end

    local r5 = mkToggleRow("Killswitch", "Ctrl+6")
    r5.Parent = togglesSection

    local rDev, sDev = mkToggleRow("Dev HUD", "Ctrl+J")
    rDev.Parent = togglesSection
    setDotDEV = sDev

    setDotESP(ESP_ENABLED)
    setDotBR(BREAKER_ENABLED)
    setDotAC(AUTOCLICK_ENABLED)
    setDotFB(FULLBRIGHT_ENABLED)
    setWpCount(0)
    setDotDEV(false)

    -- Loading label (shown until ready)
    loadingLabel = track(Instance.new("TextLabel"))
    loadingLabel.BackgroundTransparency = 1
    loadingLabel.Size = UDim2.fromOffset(80, 20)
    loadingLabel.AnchorPoint = Vector2.new(0, 0)
    loadingLabel.Position = UDim2.new(1, 8, 0, 0)
    loadingLabel.Font = Enum.Font.Gotham
    loadingLabel.TextSize = 12
    loadingLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    loadingLabel.TextXAlignment = Enum.TextXAlignment.Left
    loadingLabel.Text = "Loading"
    loadingLabel.Parent = guideFrame

    -- Dev HUD (hidden by default)
    devFrame = track(Instance.new("Frame"))
    devFrame.Name = "DevHUD"
    devFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    devFrame.BackgroundTransparency = 0.3
    devFrame.BorderSizePixel = 0
    devFrame.Size = UDim2.fromOffset(190, 76)
    devFrame.Position = UDim2.new(1, -198, 0, 22)
    devFrame.Visible = false
    devFrame.ZIndex = 20
    devFrame.Parent = guideFrame
    local devCorner = Instance.new("UICorner")
    devCorner.CornerRadius = UDim.new(0, 8)
    devCorner.Parent = devFrame
    devLabel = track(Instance.new("TextLabel"))
    devLabel.BackgroundTransparency = 1
    devLabel.Size = UDim2.fromScale(1, 1)
    devLabel.Position = UDim2.fromOffset(6, 4)
    devLabel.TextXAlignment = Enum.TextXAlignment.Left
    devLabel.TextYAlignment = Enum.TextYAlignment.Top
    devLabel.Font = Enum.Font.Code
    devLabel.TextSize = 12
    devLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
    devLabel.Text = ""
    devLabel.ZIndex = 21
    devLabel.Parent = devFrame
end

-- ESP
local function trackPlayer(plr)
	ensureUI()
	if plr == localPlayer then
		return
	end
	local rec = perPlayer[plr]
	if rec then
		if rec.label and not rec.label.Parent and espFolder then
			rec.label.Parent = espFolder
		end
		return
	end
	if not espFolder then
		return
	end
	local l = mkLabel(espFolder)
	local hue = rng:NextNumber()
	local nameColor = Color3.fromHSV(hue, 0.85, 1)
	l.TextColor3 = nameColor
	perPlayer[plr] = { label = l, lastVis = false, lastText = nil, lastW = nil, color = nameColor, lastBorder = nil, lastBucket = nil }
	enemyList[#enemyList + 1] = plr
end

local function untrackPlayer(plr)
	local rec = perPlayer[plr]
	if rec then
		perPlayer[plr] = nil
		pcall(function()
			rec.label:Destroy()
		end)
	end
	for i = #enemyList, 1, -1 do
		if enemyList[i] == plr then
			table.remove(enemyList, i)
			break
		end
	end
end

bind(Players.PlayerAdded:Connect(trackPlayer))
bind(Players.PlayerRemoving:Connect(untrackPlayer))

do
	for _, plr in ipairs(Players:GetPlayers()) do
		trackPlayer(plr)
	end
end

-- Br3ak3r (local hide) helpers
local function previewPart(part)
	if not part then
		if hoverBox then
			hoverAdornee = nil
			hoverBox.Adornee = nil
			hoverBox.Visible = false
		end
		return
	end
	if not hoverBox then
		hoverBox = track(Instance.new("SelectionBox"))
		hoverBox.LineThickness = 0.02
		hoverBox.SurfaceColor3 = Color3.fromRGB(120, 200, 120)
		hoverBox.SurfaceTransparency = 0.85
		hoverBox.Color3 = Color3.fromRGB(120, 200, 120)
		hoverBox.Parent = Workspace
	end
	if hoverAdornee ~= part then
		hoverAdornee = part
		hoverBox.Adornee = part
	end
	hoverBox.Visible = true
end

local function setLocalHidden(part, hidden)
	if not part or not part:IsA("BasePart") then
		return
	end
	if hidden then
		if not brokenSet[part] then
			brokenSet[part] = true
			local prev = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
			undoStack[#undoStack + 1] = { part = part, ltm = prev }
			if #undoStack > UNDO_LIMIT then
				table.remove(undoStack, 1)
			end
		else
			local prev = part.LocalTransparencyModifier
			if prev < 1 then
				part.LocalTransparencyModifier = 1
				undoStack[#undoStack + 1] = { part = part, ltm = prev }
			end
		end
	else
		if brokenSet[part] then
			brokenSet[part] = nil
		end
		pcall(function()
			part.LocalTransparencyModifier = 0
		end)
	end
end

local function undoLast()
	local rec = table.remove(undoStack)
	if not rec then
		return
	end
	pcall(function()
		if rec.part then
			rec.part.LocalTransparencyModifier = rec.ltm or 0
			if rec.ltm == 0 then
				brokenSet[rec.part] = nil
			end
		end
	end)
end

-- Waypoints
local function addWaypoint(worldPos)
	local idx = #waypoints + 1
	local label = mkLabel(wpFolder)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	local w = {
		pos = worldPos,
		name = ("WP-%d"):format(idx),
		color = wpColors[(idx - 1) % #wpColors + 1],
		label = label,
	}
	label.TextColor3 = w.color
	waypoints[idx] = w
	setWpCount(#waypoints)
	return w
end

local function removeNearestWaypoint(worldPos, maxDist)
	local bestI, bestD
	for i, w in ipairs(waypoints) do
		local d = (w.pos - worldPos).Magnitude
		if not bestD or d < bestD then
			bestD = d
			bestI = i
		end
	end
	if bestI and bestD and bestD <= (maxDist or 3) then
		local w = table.remove(waypoints, bestI)
		pcall(function()
			w.label:Destroy()
		end)
		setWpCount(#waypoints)
		return true
	end
	return false
end

-- Core update loop
local nextClickAt = 0
local nextFBEnforce = 0

-- Fullbright helpers
local lightBackup = nil
local atmosBackups = {}    -- [Atmosphere] = { prop = val }
local function relaxAtmosphere()
    for _, ch in ipairs(game:GetService("Lighting"):GetChildren()) do
        if ch:IsA("Atmosphere") then
            if not atmosBackups[ch] then
                atmosBackups[ch] = {
                    Density = safeGet(ch, "Density"),
                    Offset = safeGet(ch, "Offset"),
                    Color = safeGet(ch, "Color"),
                    Decay = safeGet(ch, "Decay"),
                    Glare = safeGet(ch, "Glare"),
                    Haze = safeGet(ch, "Haze"),
                }
            end
            local curDensity = safeGet(ch, "Density") or 0
            local curHaze = safeGet(ch, "Haze") or 0
            safeSet(ch, "Density", math.min(curDensity, 0.1))
            safeSet(ch, "Haze", math.min(curHaze, 0.2))
            safeSet(ch, "Glare", 0)
        end
    end
end

local function enableFullbright()
    if lightBackup then
        return
    end
    local L = game:GetService("Lighting")
    lightBackup = {
        ClockTime = safeGet(L, "ClockTime"),
        Brightness = safeGet(L, "Brightness"),
        Ambient = safeGet(L, "Ambient"),
        OutdoorAmbient = safeGet(L, "OutdoorAmbient"),
        GlobalShadows = safeGet(L, "GlobalShadows"),
        FogStart = safeGet(L, "FogStart"),
        FogEnd = safeGet(L, "FogEnd"),
        FogColor = safeGet(L, "FogColor"),
        EnvironmentDiffuseScale = safeGet(L, "EnvironmentDiffuseScale"),
        EnvironmentSpecularScale = safeGet(L, "EnvironmentSpecularScale"),
        ExposureCompensation = safeGet(L, "ExposureCompensation"),
        ShadowSoftness = safeGet(L, "ShadowSoftness"),
    }

    safeSet(L, "ClockTime", 13)
    safeSet(L, "Brightness", 2)
    safeSet(L, "FogStart", 0)
    safeSet(L, "FogEnd", 100000)
    relaxAtmosphere()
end

local function disableFullbright()
    local L = game:GetService("Lighting")
    if lightBackup then
        for k, v in pairs(lightBackup) do
            if v ~= nil then
                safeSet(L, k, v)
            end
        end
    end
    for atm, b in pairs(atmosBackups) do
        if atm and atm.Parent == L then
            for k, v in pairs(b) do
                if v ~= nil then
                    safeSet(atm, k, v)
                end
            end
        end
    end
    lightBackup = nil
    table.clear(atmosBackups)
end

local function enforceFullbright()
    if not FULLBRIGHT_ENABLED then
        return
    end
    if not lightBackup then
        enableFullbright()
        return
    end
    local L = game:GetService("Lighting")
    -- Reassert daytime look in case the server changes them
    safeSet(L, "ClockTime", 13)
    safeSet(L, "FogStart", 0)
    safeSet(L, "FogEnd", 100000)
    safeSet(L, "Brightness", 2)
    relaxAtmosphere()
end

local prevNearestPlr = nil
local lastACState = AUTOCLICK_ENABLED
local frameRound = 0
local dtAvg = 1/60
local dynamicStride = 4

local function update(dt)
    -- Loading animation gate
    if not uiReady then
        if loadingLabel then
            local t = now()
            if t >= loadAnimNext then
                loadAnimStep = (loadAnimStep + 1) % 3
                local dots = string.rep(".", loadAnimStep + 1)
                loadingLabel.Text = "Loading" .. dots
                loadAnimNext = t + 0.25
            end
        end
        return
    end
    -- Update FPS EMA and dynamic stride
    if dt and dt > 0 then
        dtAvg = dtAvg * 0.9 + dt * 0.1
    end
    local fps = dtAvg > 0 and (1 / dtAvg) or 60
    dynamicStride = clamp(math.floor((fps / HEAVY_TARGET_HZ) + 0.5), HEAVY_STRIDE_MIN, HEAVY_STRIDE_MAX)

    -- ESP
    if ESP_ENABLED then
        local camPos = camera.CFrame.Position
        local camLook = camera.CFrame.LookVector
        local cosThresh = math.cos(math.rad((camera.FieldOfView * 0.5) + 8))
        local nearestPlr = nil
        local nearestDist = math.huge
        local baseOutline = AUTOCLICK_ENABLED and OUTLINE_GREEN or OUTLINE_RED
        frameRound = (frameRound % dynamicStride) + 1
        local visIndex = 0
        for i = 1, #enemyList do
            local plr = enemyList[i]
            local rec = perPlayer[plr]
            local label = rec and rec.label
            if label then
                local char = plr.Character
                local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
                if head then
                    local headPos = head.Position
                    local dir = headPos - camPos
                    local dist = dir.Magnitude
                    if dist <= ESP_MAX_RANGE then
                        local unitDir = dir.Unit
                        local cosAng = unitDir:Dot(camLook)
                        if cosAng > cosThresh then
                            local v3, onScreen = camera:WorldToViewportPoint(headPos)
                            if onScreen and v3.Z > 0 then
                                label.Position = UDim2.fromOffset(v3.X, v3.Y - 18)
                                local dBucket = math.floor(dist / 5)
                                visIndex = visIndex + 1
                                local doHeavy = (((visIndex - frameRound) % dynamicStride) == 0) or (rec.lastBucket ~= dBucket) or (not rec.lastVis)
                                if doHeavy then
                                    local wantText = plr.Name .. " [" .. (dBucket * 5) .. "]"
                                    if rec.lastText ~= wantText then
                                        label.Text = wantText
                                        rec.lastText = wantText
                                    end
                                    local w = clamp(80 + dist * -0.1, 70, 120)
                                    if rec.lastW ~= w then
                                        label.Size = UDim2.fromOffset(w, 16)
                                        rec.lastW = w
                                    end
                                    rec.lastBucket = dBucket
                                end
                                if not rec.lastVis then
                                    label.Visible = true
                                    rec.lastVis = true
                                    -- set base outline immediately; nearest will override below
                                    if rec.lastBorder ~= baseOutline then
                                        label.BorderColor3 = baseOutline
                                        rec.lastBorder = baseOutline
                                    end
                                end
                                if dist < nearestDist then
                                    nearestDist = dist
                                    nearestPlr = plr
                                end
                            else
                                if rec.lastVis then
                                    label.Visible = false
                                    rec.lastVis = false
                                end
                            end
                            end
                        else
                            if rec.lastVis then
                                label.Visible = false
                                rec.lastVis = false
                            end
                        end
				else
					if rec and rec.lastVis then
						label.Visible = false
						rec.lastVis = false
					end
				end
			end
		end
		end

        -- Border updates minimized
        if lastACState ~= AUTOCLICK_ENABLED then
            lastACState = AUTOCLICK_ENABLED
            local newBase = AUTOCLICK_ENABLED and OUTLINE_GREEN or OUTLINE_RED
            for _, rec in pairs(perPlayer) do
                if rec.lastVis then
                    rec.label.BorderColor3 = newBase
                    rec.lastBorder = newBase
                end
            end
        end

        lastVisCount = visIndex

        if prevNearestPlr ~= nearestPlr then
            if prevNearestPlr then
                local prevRec = perPlayer[prevNearestPlr]
                if prevRec and prevRec.lastVis then
                    local want = AUTOCLICK_ENABLED and OUTLINE_GREEN or OUTLINE_RED
                    if prevRec.lastBorder ~= want then
                        prevRec.label.BorderColor3 = want
                        prevRec.lastBorder = want
                    end
                end
            end
            prevNearestPlr = nearestPlr
        end
        if nearestPlr then
            local nRec = perPlayer[nearestPlr]
            if nRec and nRec.lastVis and nRec.lastBorder ~= OUTLINE_PINK then
                nRec.label.BorderColor3 = OUTLINE_PINK
                nRec.lastBorder = OUTLINE_PINK
            end
        end
    else
        for _, rec in pairs(perPlayer) do
            if rec.lastVis then
                rec.label.Visible = false
                rec.lastVis = false
            end
        end
    end

	-- Waypoints draw
	for i = 1, #waypoints do
		local w = waypoints[i]
		local v3, onScreen = camera:WorldToViewportPoint(w.pos)
		if onScreen and v3.Z > 0 then
			if not w.label.Visible then
				w.label.Visible = true
				w.label.Text = w.name
			end
			w.label.Position = UDim2.fromOffset(v3.X, v3.Y)
		else
			if w.label.Visible then
				w.label.Visible = false
			end
		end
	end

	-- Br3ak3r preview
	if BREAKER_ENABLED and ctrlDown then
		local t = mouse.Target
		if t and t:IsA("BasePart") then
			previewPart(t)
		else
			previewPart(nil)
		end
	else
		if hoverAdornee then
			previewPart(nil)
		end
	end

	-- AutoClick
	if AUTOCLICK_ENABLED and hasVIM then
		local t = mouse.Target
		local ok = false
		if t and t:IsA("BasePart") then
			local model = t:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChild("Humanoid") then
				local owner = Players:GetPlayerFromCharacter(model)
				ok = (owner and owner ~= localPlayer) and true or false
			end
		end
		local nowT = now()
		if ok and nowT >= nextClickAt and not UserInputService:GetFocusedTextBox() then
			local ml = UserInputService:GetMouseLocation()
			VirtualInputManager:SendMouseButtonEvent(ml.X, ml.Y, 0, true, game, 0)
			VirtualInputManager:SendMouseButtonEvent(ml.X, ml.Y, 0, false, game, 0)
			nextClickAt = nowT + (1 / SP3AR_AUTOCLICK_HZ)
		end
	end

    -- Fullbright enforcement (throttled)
    if FULLBRIGHT_ENABLED then
        local t = now()
        if t >= nextFBEnforce then
                enforceFullbright()
                nextFBEnforce = t + 1.5
            end
        end

    -- Dev HUD (throttled)
    if devHUDEnabled and devLabel then
        local t = now()
        if t >= devNextHUD then
            local fps = dtAvg > 0 and (1 / dtAvg) or 60
            local tracked = #enemyList
            local txt = string.format(
                "fps: %.1f\nvis: %d / %d\nstride: %d  targetHz: %d\nrange: %d\nflags: ESP:%s AC:%s FB:%s BR:%s",
                fps,
                lastVisCount,
                tracked,
                dynamicStride,
                HEAVY_TARGET_HZ,
                ESP_MAX_RANGE,
                ESP_ENABLED and "on" or "off",
                AUTOCLICK_ENABLED and "on" or "off",
                FULLBRIGHT_ENABLED and "on" or "off",
                BREAKER_ENABLED and "on" or "off"
            )
            devLabel.Text = txt
            devNextHUD = t + 0.5
        end
    end
end

-- Input handling
local function onInputBegan(input, gp)
	if dead then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		ctrlDown = true
	end
	if gp then
		return
	end
    if ctrlDown then
        if input.KeyCode == Enum.KeyCode.E then
            ESP_ENABLED = not ESP_ENABLED
            if setDotESP then
                setDotESP(ESP_ENABLED)
            end
        elseif input.KeyCode == Enum.KeyCode.Return then
            BREAKER_ENABLED = not BREAKER_ENABLED
            if setDotBR then
                setDotBR(BREAKER_ENABLED)
            end
        elseif input.KeyCode == Enum.KeyCode.K then
            AUTOCLICK_ENABLED = not AUTOCLICK_ENABLED
            if setDotAC then
                setDotAC(AUTOCLICK_ENABLED)
            end
        elseif input.KeyCode == Enum.KeyCode.U then
            guideHidden = not guideHidden
            if guideFrame then guideFrame.Visible = not guideHidden end
        elseif input.KeyCode == Enum.KeyCode.J then
            devHUDEnabled = not devHUDEnabled
            if setDotDEV then setDotDEV(devHUDEnabled) end
            if devFrame then devFrame.Visible = devHUDEnabled end
        elseif input.KeyCode == Enum.KeyCode.L then
            FULLBRIGHT_ENABLED = not FULLBRIGHT_ENABLED
            if setDotFB then
                setDotFB(FULLBRIGHT_ENABLED)
            end
			if FULLBRIGHT_ENABLED then
				enableFullbright()
			else
				disableFullbright()
			end
		elseif input.KeyCode == Enum.KeyCode.Z then
			undoLast()
		elseif input.KeyCode == Enum.KeyCode.Six then
			dead = true
			disconnectAll()
			for p in pairs(brokenSet) do
				pcall(function()
					p.LocalTransparencyModifier = 0
				end)
			end
			if FULLBRIGHT_ENABLED then
				FULLBRIGHT_ENABLED = false
				disableFullbright()
			end
			perPlayer = {}
			enemyList = {}
			waypoints = {}
			undoStack = {}
			brokenSet = {}
			releaseGlobalFlag()
			destroyAll()
			return
		end
	end

	-- Br3ak3r action: Ctrl + LMB
	if BREAKER_ENABLED and ctrlDown and input.UserInputType == Enum.UserInputType.MouseButton1 then
		local t = mouse.Target
		if t and t:IsA("BasePart") then
			setLocalHidden(t, true)
		end
	end

	-- Waypoint toggle: Ctrl + MMB
	if ctrlDown and input.UserInputType == Enum.UserInputType.MouseButton3 then
		local pos = mouse.Hit and mouse.Hit.p or (camera.CFrame.Position + camera.CFrame.LookVector * 100)
		if not removeNearestWaypoint(pos, 3) then
			addWaypoint(pos)
		end
	end
end

local function onInputEnded(input, _)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		ctrlDown = false
	end
end

-- Init
ensureUI()

-- Minimize/drag handlers
local function setMinimized(min)
    minimized = min and true or false
    if togglesSection then
        togglesSection.Visible = not minimized
    end
    if guideFrame then
        guideFrame.Size = UDim2.fromOffset(230, minimized and minimizedHeight or expandedHeight)
    end
end

if minimizeBtn then
    bind(minimizeBtn.MouseButton1Click:Connect(function()
        setMinimized(not minimized)
    end))
end

if titleBar then
    bind(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = Vector2.new(input.Position.X, input.Position.Y)
            frameStart = Vector2.new(guideFrame.Position.X.Offset, guideFrame.Position.Y.Offset)
        end
    end))
end

bind(UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local cur = Vector2.new(input.Position.X, input.Position.Y)
        local delta = cur - dragStart
        guideFrame.Position = UDim2.fromOffset(frameStart.X + delta.X, frameStart.Y + delta.Y)
    end
end))

bind(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end))

-- Slow, staged init to avoid spikes
if togglesSection then togglesSection.Visible = false end
setMinimized(true)

stepSpawn(function()
    -- Stage 1: prewarm tracking
    local list = Players:GetPlayers()
    for i = 1, #list do
        local plr = list[i]
        trackPlayer(plr)
        if i % 5 == 0 then stepWait() end
    end
    stepWait(0.1)
    -- Stage 2: reveal UI
    if togglesSection then togglesSection.Visible = true end
    if loadingLabel then loadingLabel.Visible = false end
    uiReady = true
end)

bind(UserInputService.InputBegan:Connect(onInputBegan))
bind(UserInputService.InputEnded:Connect(onInputEnded))

bind(RunService.RenderStepped:Connect(function(dt)
    if not dead then
        update(dt)
    end
end))
