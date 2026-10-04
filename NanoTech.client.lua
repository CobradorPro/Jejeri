--[[
====================================================================
  NANOTECH SYSTEM  (LocalScript unico, Luau)
====================================================================
  ONDE COLOCAR:
    StarterPlayer > StarterCharacterScripts > NanoTech (LocalScript)
    -> O script cria sozinho o Tool "NanoTech" na Mochila (Backpack).
    (Alternativa: coloque este LocalScript dentro de um Tool em
     StarterPack; ele vai usar esse Tool. RequiresHandle e desligado
     automaticamente se nao houver Handle.)

  CONTROLES PC (com o Tool equipado):
    Segurar botao esquerdo ... Enxame segue o mouse
    H ........................ Nuvem (modo padrao)
    Z ........................ Nanotecnologia nos pes
    F ........................ Voo (WASD + camera, Espaco sobe,
                               Ctrl/Q desce, E = boost)
    C ........................ Clone de nanoblocos
    X ........................ Armadura
    V ........................ Escudo
    B ........................ Lamina no braco (clique = golpe)
    G ........................ Plataforma temporaria
    T ........................ Drones orbitais
    R ........................ Recall (recolher tudo)

  MOBILE:
    Botoes na tela (canto direito). "ENX" liga o modo enxame:
    toque/arraste na tela para guiar a formacao.
    Voo: analogico normal + botoes SOBE / DESCE / BOOST.

  LIMITACAO IMPORTANTE:
    Por ser um LocalScript unico, os efeitos (blocos, clone, escudo,
    plataforma) existem so no seu cliente. O voo replica porque o
    cliente e dono da fisica do proprio personagem. Cooldowns sao
    locais (sem validacao de servidor).

  DESEMPENHO:
    - Pool fixo de Parts ancoradas, sem colisao/query/touch.
    - Tudo movido com 1 chamada workspace:BulkMoveTo por frame.
    - Fisica de mola propria (sem fisica do Roblox nos blocos).
    - LOD por distancia da camera + qualidade adaptativa por FPS.
    - Blocos invisiveis "dormem" e nao sao processados.

  NOVAS HABILIDADES:
    Use registerOverlay({...}) (veja Armor/Shield como exemplo),
    adicione uma funcao em Actions e um botao em ABILITY_LIST.
====================================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

--==================================================================
-- CONFIGURACAO (edite aqui)
--==================================================================
local CONFIG = {
	ToolName = "NanoTech",

	Blocks = {
		Count = 280,             -- quantidade maxima de nanoblocos
		MinSize = 0.12,          -- tamanho minimo
		MaxSize = 0.38,          -- tamanho maximo
		ElongatedChance = 0.2,   -- chance de bloco alongado
		NeonRatio = 0.4,         -- fracao de blocos brilhantes
		TrailRatio = 0.08,       -- fracao dos neon com rastro
		Reflectance = 0.15,
	},

	Motion = {
		Stiffness = 38,          -- forca de atracao (mola)
		Damping = 7.5,           -- amortecimento
		MaxSpeed = 220,          -- velocidade maxima de um bloco
		NoiseSpeed = 1.4,
		SpinMin = 1,
		SpinMax = 6,
		BurstSpeed = 28,         -- explosao ao ativar
		AlphaSpeed = 7,          -- velocidade de fade
	},

	Colors = {
		Primary = Color3.fromRGB(0, 210, 255),
		Secondary = Color3.fromRGB(120, 90, 255),
		Accent = Color3.fromRGB(235, 255, 255),
		Dark = Color3.fromRGB(28, 34, 46),
	},

	Quality = {
		Mode = "Auto",           -- "Auto", "Low", "Medium", "High"
		Levels = { Low = 0.35, Medium = 0.65, High = 1 },
		TargetFPS = 50,
		MinScale = 0.3,
		MinBlocks = 60,
		LODNear = 35,            -- distancia da camera sem reducao
		LODFar = 140,            -- distancia com reducao maxima
		LODMinFactor = 0.35,
		Particles = true,
		Lights = true,
		Sparkles = true,
		ParticleRate = 1,        -- multiplicador de particulas
	},

	Cloud = { Radius = 4.2, Height = 0.6, VerticalSpread = 4.5, OrbitSpeed = 0.9, Noise = 0.45 },
	Feet = { Radius = 1.7, Thickness = 0.5, OffsetY = -0.1, OrbitSpeed = 2.4 },

	Swarm = {
		BlockShare = 0.75, Radius = 2.6, InnerRatio = 0.3, ShapeSpin = 1.2, Pulse = 0.08,
		FollowSmoothing = 9, MaxDistance = 90, DefaultDistance = 35, HoverHeight = 2.5,
	},

	Flight = {
		MaxSpeed = 60, BoostMultiplier = 1.9, Acceleration = 2.2, Deceleration = 3.2,
		VerticalSpeed = 30, TakeoffHeight = 7, TakeoffTime = 1.1, LandingSpeed = 10,
		LandingTimeout = 4, TiltAngle = 22, TurnResponsiveness = 16,
		HoverAmplitude = 0.6, HoverFrequency = 2, ReservedBlocks = 70,
		RingRadius = 0.9, ExhaustLength = 3.5, ExhaustSpeed = 1.6, BoostFOV = 14,
		UpKey = Enum.KeyCode.Space,
		DownKeys = { Enum.KeyCode.LeftControl, Enum.KeyCode.Q },
		BoostKey = Enum.KeyCode.E,
	},

	Clone = {
		BlockShare = 0.6, Delay = 0.3, Offset = Vector3.new(4.5, 0, 1.5), MaxDistance = 40,
		FormTime = 2.6, DissolveTime = 1.6, FollowStiffness = 3.2, ReorganizeChance = 0.35,
		BurstDistance = 0.9, Highlight = true, GhostTransparency = 0.97,
	},

	Armor = { BlockShare = 0.7, Duration = 14, FormTime = 1.4, DissolveTime = 0.9 },
	Shield = { BlockShare = 0.45, Duration = 8, FormTime = 0.5, DissolveTime = 0.5, Radius = 3, Distance = 3.2, Curvature = 0.7 },
	Blade = { BlockShare = 0.3, Duration = 16, FormTime = 0.7, DissolveTime = 0.6, Length = 4.5, Width = 0.55, GuardWidth = 1.3 },
	Platform = { BlockShare = 0.45, Duration = 8, FormTime = 0.6, DissolveTime = 0.9, Size = Vector3.new(8, 0.5, 8) },
	Drones = { Count = 6, Radius = 3.4, Height = 2.6, Speed = 1.3, Size = 0.5 },

	Cooldowns = { Feet = 0.4, Flight = 1, Clone = 6, Armor = 10, Shield = 6, Blade = 3, Platform = 5, Recall = 1.5, Drones = 1 },

	Keys = {
		Cloud = Enum.KeyCode.H, Feet = Enum.KeyCode.Z, Flight = Enum.KeyCode.F,
		Clone = Enum.KeyCode.C, Armor = Enum.KeyCode.X, Shield = Enum.KeyCode.V,
		Blade = Enum.KeyCode.B, Platform = Enum.KeyCode.G, Drones = Enum.KeyCode.T,
		Recall = Enum.KeyCode.R,
	},
}

local COLORS = CONFIG.Colors

--==================================================================
-- PERSONAGEM / TOOL
--==================================================================
local hostTool = script:FindFirstAncestorOfClass("Tool")
local character
if not hostTool and script.Parent and script.Parent:IsA("Model") then
	character = script.Parent
else
	character = player.Character or player.CharacterAdded:Wait()
end

local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local camera = Workspace.CurrentCamera
local baseFOV = camera.FieldOfView

local function getBodyPart(names)
	for _, n in ipairs(names) do
		local p = character:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local torso = getBodyPart({ "UpperTorso", "Torso" })
local leftFoot = getBodyPart({ "LeftFoot", "Left Leg" })
local rightFoot = getBodyPart({ "RightFoot", "Right Leg" })
local rightHand = getBodyPart({ "RightHand", "Right Arm" })

local tool = hostTool
if not tool then
	local backpack = player:WaitForChild("Backpack")
	local old = backpack:FindFirstChild(CONFIG.ToolName)
	if old then
		old:Destroy()
	end
	tool = Instance.new("Tool")
	tool.Name = CONFIG.ToolName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Nanotecnologia"
	tool.Parent = backpack
elseif not tool:FindFirstChild("Handle") then
	tool.RequiresHandle = false
end

local Controls = nil
task.spawn(function()
	local ok, pm = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
	end)
	if ok and pm then
		Controls = pm:GetControls()
	end
end)

--==================================================================
-- UTILITARIOS
--==================================================================
local connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local rng = Random.new()
local GOLDEN = math.pi * (3 - math.sqrt(5))
local TAU = math.pi * 2

local function clamp(x, a, b)
	return math.clamp(x, a, b)
end

local function smoothstep(x)
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function easeOutBack(x)
	x = clamp(x, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function fibSphere(i, n)
	local y = 1 - ((i - 0.5) / n) * 2
	local r = math.sqrt(math.max(0, 1 - y * y))
	local th = GOLDEN * i
	return Vector3.new(math.cos(th) * r, y, math.sin(th) * r)
end

local function fibDisc(i, n)
	local r = math.sqrt((i - 0.5) / n)
	local th = GOLDEN * i
	return math.cos(th) * r, math.sin(th) * r
end

local function randomUnit()
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 1, 0)
	end
	return v.Unit
end

local function footBottom(part)
	if not part then
		return root.Position - Vector3.new(0, 3, 0)
	end
	return part.Position - part.CFrame.UpVector * (part.Size.Y * 0.5)
end

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local clock = 0
local cooldownUntil = {}
local function cooldownReady(name)
	return (cooldownUntil[name] or 0) <= clock
end
local function setCooldown(name)
	cooldownUntil[name] = clock + (CONFIG.Cooldowns[name] or 0)
end
local function cooldownRemaining(name)
	return math.max(0, (cooldownUntil[name] or 0) - clock)
end

--==================================================================
-- CONTAINERS / RAYCAST
--==================================================================
local nanoFolder = Instance.new("Folder")
nanoFolder.Name = "NanoTech_" .. player.Name
nanoFolder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character, nanoFolder }
rayParams.IgnoreWater = true

--==================================================================
-- EFEITOS
--==================================================================
local Effects = {}

local function makeFxPart(shape, color, size, cf)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = nanoFolder
	return p
end

function Effects.shockwave(position, normal, color, diameter, duration)
	local base
	if math.abs(normal.Y) > 0.99 then
		base = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	else
		base = CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local ring = makeFxPart(Enum.PartType.Cylinder, color or COLORS.Primary, Vector3.new(0.06, 0.4, 0.4), base)
	ring.Transparency = 0.35
	tween(ring, duration, { Size = Vector3.new(0.06, diameter, diameter), Transparency = 1 })
	Debris:AddItem(ring, duration + 0.1)
end

function Effects.pulse(position, color, diameter, duration)
	local ball = makeFxPart(Enum.PartType.Ball, color or COLORS.Accent, Vector3.new(0.3, 0.3, 0.3), CFrame.new(position))
	ball.Transparency = 0.3
	tween(ball, duration, { Size = Vector3.new(diameter, diameter, diameter), Transparency = 1 })
	Debris:AddItem(ball, duration + 0.1)
end

-- Aura (particulas + luz)
local auraAtt = Instance.new("Attachment")
auraAtt.Name = "NanoAura"
auraAtt.Parent = root

local auraEmitter = Instance.new("ParticleEmitter")
auraEmitter.Name = "NanoAuraParticles"
auraEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
auraEmitter.Rate = 0
auraEmitter.Lifetime = NumberRange.new(0.6, 1.2)
auraEmitter.Speed = NumberRange.new(0.5, 2)
auraEmitter.SpreadAngle = Vector2.new(180, 180)
auraEmitter.Drag = 2
auraEmitter.LightEmission = 1
auraEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
auraEmitter.Transparency = NumberSequence.new(0.2, 1)
auraEmitter.Color = ColorSequence.new(COLORS.Primary, COLORS.Secondary)
auraEmitter.Parent = auraAtt

local auraLight = Instance.new("PointLight")
auraLight.Name = "NanoAuraLight"
auraLight.Color = COLORS.Primary
auraLight.Range = 10
auraLight.Brightness = 1.2
auraLight.Shadows = false
auraLight.Enabled = false
auraLight.Parent = auraAtt

local footEmitters = {}
for _, foot in ipairs({ leftFoot, rightFoot }) do
	if foot then
		local att = Instance.new("Attachment")
		att.Name = "NanoFootAttachment"
		att.Position = Vector3.new(0, -foot.Size.Y * 0.5, 0)
		att.Parent = foot
		local em = Instance.new("ParticleEmitter")
		em.Name = "NanoThruster"
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Rate = 0
		em.EmissionDirection = Enum.NormalId.Bottom
		em.Lifetime = NumberRange.new(0.25, 0.5)
		em.Speed = NumberRange.new(6, 14)
		em.SpreadAngle = Vector2.new(18, 18)
		em.LightEmission = 1
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
		em.Transparency = NumberSequence.new(0.1, 1)
		em.Color = ColorSequence.new(COLORS.Accent, COLORS.Primary)
		em.Parent = att
		table.insert(footEmitters, em)
	end
end

-- Atacamento no Terrain para os feixes dos drones
local beamTargetAtt = Instance.new("Attachment")
beamTargetAtt.Name = "NanoBeamTarget"
beamTargetAtt.Parent = Workspace.Terrain

--==================================================================
-- POOL DE NANOBLOCOS (dados em arrays para desempenho)
--==================================================================
local TOTAL = CONFIG.Blocks.Count
local parts, pos, vel, target, prevTarget = {}, {}, {}, {}, {}
local rot, axis, spin, alignRot = {}, {}, {}, {}
local stiff, stiffVar, carry = {}, {}, {}
local seedA, seedB, seedC, phase, noiseSeed = {}, {}, {}, {}, {}
local alpha, alphaTarget, baseT, lastT = {}, {}, {}, {}
local hidden, trails, baseColor, isNeon = {}, {}, {}, {}
local aux, burstUntil, mark = {}, {}, {}

for i = 1, TOTAL do
	local p = Instance.new("Part")
	local sz = CONFIG.Blocks.MinSize + (CONFIG.Blocks.MaxSize - CONFIG.Blocks.MinSize) * (rng:NextNumber() ^ 2)
	if rng:NextNumber() < CONFIG.Blocks.ElongatedChance then
		p.Size = Vector3.new(sz, sz, sz * 1.9)
	else
		p.Size = Vector3.new(sz, sz, sz)
	end
	local neon = rng:NextNumber() < CONFIG.Blocks.NeonRatio
	isNeon[i] = neon
	p.Name = "NanoBlock"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if neon then
		p.Material = Enum.Material.Neon
		p.Color = (rng:NextNumber() < 0.7) and COLORS.Primary or COLORS.Secondary
		baseT[i] = 0.05
	else
		p.Material = Enum.Material.Metal
		p.Color = COLORS.Dark
		p.Reflectance = CONFIG.Blocks.Reflectance
		baseT[i] = 0
	end
	baseColor[i] = p.Color
	p.Transparency = 1
	p.CFrame = root.CFrame
	p.Parent = nanoFolder

	if neon and rng:NextNumber() < CONFIG.Blocks.TrailRatio / CONFIG.Blocks.NeonRatio * 0.5 then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, sz * 0.5, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -sz * 0.5, 0)
		a1.Parent = p
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = 0.2
		tr.LightEmission = 1
		tr.FaceCamera = true
		tr.Color = ColorSequence.new(COLORS.Primary)
		tr.Transparency = NumberSequence.new(0.3, 1)
		tr.Enabled = false
		tr.Parent = p
		trails[i] = tr
	end

	parts[i] = p
	pos[i] = root.Position
	vel[i] = Vector3.zero
	target[i] = root.Position
	prevTarget[i] = root.Position
	rot[i] = CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), rng:NextNumber(0, TAU))
	axis[i] = randomUnit()
	spin[i] = rng:NextNumber(CONFIG.Motion.SpinMin, CONFIG.Motion.SpinMax)
	stiff[i] = 1
	stiffVar[i] = 0.7 + rng:NextNumber() * 0.6
	carry[i] = 0
	seedA[i] = rng:NextNumber()
	seedB[i] = rng:NextNumber()
	seedC[i] = rng:NextNumber()
	phase[i] = rng:NextNumber(0, TAU)
	noiseSeed[i] = rng:NextNumber(0, 1000)
	alpha[i] = 0
	alphaTarget[i] = 0
	lastT[i] = 1
	hidden[i] = true
	aux[i] = 0
	burstUntil[i] = 0
	mark[i] = false
end

local function noiseVec(i, t, amp)
	local s = noiseSeed[i]
	local ts = t * CONFIG.Motion.NoiseSpeed
	return Vector3.new(math.noise(s, ts, 0.5), math.noise(ts, s + 17.3, 1.5), math.noise(2.5, ts, s + 41.7)) * amp
end

--==================================================================
-- CONTEXTO POR FRAME
--==================================================================
local ctx = {
	t = 0, dt = 0, rootPos = root.Position, rootCF = root.CFrame, torsoPos = root.Position,
	flatLook = Vector3.new(0, 0, -1), leftFoot = root.Position, rightFoot = root.Position,
	flightIntensity = 0, flightVelDir = Vector3.zero,
}

local function updateContext(dt)
	ctx.t = clock
	ctx.dt = dt
	ctx.rootCF = root.CFrame
	ctx.rootPos = root.Position
	ctx.torsoPos = torso and torso.Position or root.Position
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		local rl = root.CFrame.LookVector
		flat = Vector3.new(rl.X, 0, rl.Z)
	end
	ctx.flatLook = flat.Magnitude > 0 and flat.Unit or Vector3.new(0, 0, -1)
	ctx.leftFoot = footBottom(leftFoot)
	ctx.rightFoot = footBottom(rightFoot)
end

--==================================================================
-- MAPA DE SUPERFICIE (armadura / clone)
--==================================================================
local function buildSurfaceMap(model, count, rootPart)
	local entries, list, total = {}, {}, 0
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local s = d.Size
			local area = 2 * (s.X * s.Y + s.Y * s.Z + s.X * s.Z)
			if d.Name == "Head" then
				area *= 1.5
			end
			total += area
			table.insert(list, { part = d, area = area, size = s })
		end
	end
	if #list == 0 then
		return entries
	end
	local rootPos = rootPart and rootPart.Position or model:GetPivot().Position
	for _ = 1, count do
		local pick = rng:NextNumber() * total
		local chosen = list[#list]
		for _, item in ipairs(list) do
			pick -= item.area
			if pick <= 0 then
				chosen = item
				break
			end
		end
		local s = chosen.size
		local hx, hy, hz = s.X * 0.5, s.Y * 0.5, s.Z * 0.5
		local ax, ay, az = s.Y * s.Z, s.X * s.Z, s.X * s.Y
		local f = rng:NextNumber() * (ax + ay + az)
		local sign = rng:NextNumber() < 0.5 and -1 or 1
		local offset, normal
		if f < ax then
			normal = Vector3.new(sign, 0, 0)
			offset = Vector3.new(sign * hx, rng:NextNumber(-hy, hy), rng:NextNumber(-hz, hz))
		elseif f < ax + ay then
			normal = Vector3.new(0, sign, 0)
			offset = Vector3.new(rng:NextNumber(-hx, hx), sign * hy, rng:NextNumber(-hz, hz))
		else
			normal = Vector3.new(0, 0, sign)
			offset = Vector3.new(rng:NextNumber(-hx, hx), rng:NextNumber(-hy, hy), sign * hz)
		end
		offset += normal * 0.06
		local world = chosen.part.CFrame:PointToWorldSpace(offset)
		table.insert(entries, { part = chosen.part, offset = offset, normal = normal, relHeight = world.Y - rootPos.Y })
	end
	table.sort(entries, function(a, b)
		return a.relHeight < b.relHeight
	end)
	return entries
end

--==================================================================
-- SISTEMA DE OVERLAYS (habilidades que "pegam" parte dos blocos)
--==================================================================
local Overlays = {}

local function registerOverlay(def)
	def.state = "off"
	def.progress = 0
	def.activeTime = 0
	table.insert(Overlays, def)
	return def
end

local function overlayStart(def)
	if def.state ~= "off" then
		return false
	end
	if def.cooldown and not cooldownReady(def.cooldown) then
		return false
	end
	if def.onStart and def.onStart(def) == false then
		return false
	end
	if def.cooldown then
		setCooldown(def.cooldown)
	end
	def.state = "forming"
	def.activeTime = 0
	return true
end

local function overlayStop(def, fast)
	if def.state == "off" or def.state == "dissolving" then
		return
	end
	def.state = "dissolving"
	def.fastDissolve = fast
	if def.onStop then
		def.onStop(def)
	end
end

local function overlayToggle(def)
	if def.state == "off" then
		overlayStart(def)
	elseif def.state ~= "dissolving" then
		overlayStop(def)
	end
end

local function overlayActive(def)
	return def.state == "forming" or def.state == "active"
end

local function updateOverlays(dt)
	for _, def in ipairs(Overlays) do
		if def.state ~= "off" then
			if def.state == "forming" then
				def.progress = math.min(1, def.progress + dt / def.formTime)
				if def.progress >= 1 then
					def.state = "active"
					if def.onFormed then
						def.onFormed(def)
					end
				end
			elseif def.state == "active" then
				def.activeTime += dt
				if def.duration and def.activeTime >= def.duration then
					overlayStop(def)
				end
			elseif def.state == "dissolving" then
				local dtime = def.fastDissolve and 0.35 or def.dissolveTime
				def.progress = math.max(0, def.progress - dt / dtime)
				if def.progress <= 0 then
					def.state = "off"
					if def.onRemoved then
						def.onRemoved(def)
					end
				end
			end
			if def.state ~= "off" and def.update then
				def.update(def, dt, ctx)
			end
		end
	end
end

--==================================================================
-- MODO BASE (nuvem / pes / voo / recall / guardado)
--==================================================================
local Base = { mode = "stored", modeTime = 0, autoCloudAt = nil }
local Flight -- declarado depois

function Base.burst(origin)
	for i = 1, TOTAL do
		pos[i] = origin + randomUnit() * 0.3
		vel[i] = randomUnit() * CONFIG.Motion.BurstSpeed * (0.4 + seedA[i])
		prevTarget[i] = target[i]
		alpha[i] = 0
		hidden[i] = false
	end
	Effects.pulse(origin, COLORS.Accent, 6, 0.45)
	Effects.shockwave(ctx.rootPos - Vector3.new(0, 2.6, 0), Vector3.new(0, 1, 0), COLORS.Primary, 14, 0.6)
end

function Base.setMode(mode)
	if Base.mode == mode then
		return
	end
	local from = Base.mode
	Base.mode = mode
	Base.modeTime = 0
	Base.autoCloudAt = nil
	if from == "stored" and mode ~= "recall" then
		Base.burst(rightHand and rightHand.Position or ctx.torsoPos)
	end
	if mode == "recall" then
		Effects.pulse(ctx.torsoPos, COLORS.Primary, 4, 0.5)
	end
end

local BaseForm = {}

BaseForm.cloud = function(i, k, n, c)
	local cfg = CONFIG.Cloud
	local radius = cfg.Radius * (0.5 + 0.7 * seedA[i])
	local dirSign = seedC[i] > 0.5 and 1 or -1
	local ang = phase[i] + c.t * cfg.OrbitSpeed * (0.35 + seedB[i]) * dirSign
	local x, z = math.cos(ang) * radius, math.sin(ang) * radius
	local y = cfg.Height + (seedB[i] - 0.5) * cfg.VerticalSpread + math.sin(c.t * 1.2 + phase[i] * 2) * 0.35
	y += x * (seedC[i] - 0.5) * 0.6
	target[i] = c.rootPos + Vector3.new(x, y, z) + noiseVec(i, c.t, cfg.Noise)
	carry[i] = 0.9
end

BaseForm.feet = function(i, k, n, c)
	local cfg = CONFIG.Feet
	local foot = (k % 2 == 0) and c.leftFoot or c.rightFoot
	local ang = phase[i] + c.t * cfg.OrbitSpeed * (0.5 + seedB[i]) * (seedC[i] > 0.5 and 1 or -1)
	local r = cfg.Radius * (0.25 + 0.75 * math.sqrt(seedA[i]))
	local wave = math.sin(c.t * 2.5 + phase[i]) * 0.12
	local y = cfg.OffsetY + (seedC[i] - 0.5) * cfg.Thickness + wave
	target[i] = foot + Vector3.new(math.cos(ang) * r, y, math.sin(ang) * r) + noiseVec(i, c.t, 0.15)
	stiff[i] = 1.8
	carry[i] = 1
end

BaseForm.flight = function(i, k, n, c)
	local cfg = CONFIG.Flight
	local foot = (k % 2 == 0) and c.leftFoot or c.rightFoot
	local intensity = c.flightIntensity
	if k <= math.floor(n * 0.5) then
		-- anel propulsor / plataforma
		local ang = phase[i] + c.t * (3 + intensity * 4) * (seedB[i] > 0.5 and 1 or -1)
		local r = 0.35 + seedA[i] * cfg.RingRadius
		local y = -0.15 + (seedC[i] - 0.5) * 0.25 + math.sin(c.t * 6 + phase[i]) * 0.05
		target[i] = foot + Vector3.new(math.cos(ang) * r, y, math.sin(ang) * r)
		stiff[i] = 2.5
		carry[i] = 1
		alphaTarget[i] = 1
	else
		-- jato de nanoparticulas
		local life = (c.t * cfg.ExhaustSpeed * (0.6 + seedB[i]) + seedA[i]) % 1
		if life < aux[i] then
			pos[i] = foot + randomUnit() * 0.15
			vel[i] = Vector3.zero
		end
		aux[i] = life
		local length = cfg.ExhaustLength * (0.5 + intensity)
		local r = 0.15 + life * 0.6
		local ang = phase[i] + life * 6
		local back = -c.flightVelDir * life * length * 0.5
		target[i] = foot + Vector3.new(math.cos(ang) * r, -life * length, math.sin(ang) * r) + back
		stiff[i] = 3
		carry[i] = 1
		local a = 1 - life * life
		alpha[i] = a
		alphaTarget[i] = a
	end
end

BaseForm.recall = function(i, k, n, c)
	local ang = phase[i] + c.t * 8
	target[i] = c.torsoPos + Vector3.new(math.cos(ang) * 0.6, (seedB[i] - 0.5) * 1.2, math.sin(ang) * 0.6)
	stiff[i] = 3.5
	carry[i] = 1
	alphaTarget[i] = ((pos[i] - c.torsoPos).Magnitude < 1.6) and 0 or 1
end

BaseForm.stored = function(i, k, n, c)
	target[i] = c.torsoPos
	stiff[i] = 3
	carry[i] = 1
	alphaTarget[i] = 0
end

function Base.update(dt)
	Base.modeTime += dt
	if Base.mode == "recall" and Base.modeTime > 0.9 then
		Base.setMode("stored")
	end
	if Base.autoCloudAt and clock >= Base.autoCloudAt then
		Base.autoCloudAt = nil
		if Base.mode == "feet" then
			Base.setMode("cloud")
		end
	end
end

--==================================================================
-- HABILIDADE: ENXAME SEGUINDO MOUSE / DEDO
--==================================================================
local Swarm = registerOverlay({
	name = "Swarm",
	share = CONFIG.Swarm.BlockShare,
	formTime = 0.25,
	dissolveTime = 0.4,
	center = root.Position,
	inputMode = "mouse",
	screenPos = Vector2.zero,
	rotCF = CFrame.new(),
})

Swarm.onStart = function(self)
	self.center = ctx.torsoPos
end

Swarm.update = function(self, dt, c)
	local cfg = CONFIG.Swarm
	local ray
	if self.inputMode == "touch" then
		ray = camera:ScreenPointToRay(self.screenPos.X, self.screenPos.Y)
	else
		local m = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(m.X, m.Y)
	end
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local point
	if result then
		point = result.Position + result.Normal * cfg.HoverHeight
	else
		point = ray.Origin + ray.Direction * cfg.DefaultDistance
	end
	local offset = point - c.rootPos
	if offset.Magnitude > cfg.MaxDistance then
		point = c.rootPos + offset.Unit * cfg.MaxDistance
	end
	self.center = self.center:Lerp(point, 1 - math.exp(-cfg.FollowSmoothing * dt))
	self.rotCF = CFrame.Angles(c.t * 0.6, c.t * cfg.ShapeSpin, 0)
end

Swarm.formation = function(i, k, n, c, self)
	local cfg = CONFIG.Swarm
	local d = fibSphere(k, n)
	local shell = (seedA[i] < cfg.InnerRatio) and (0.35 + seedB[i] * 0.3) or 1
	local pulse = 1 + math.sin(c.t * 3 - k * 0.08) * cfg.Pulse
	local grow = smoothstep(self.progress)
	target[i] = self.center + self.rotCF:VectorToWorldSpace(d) * cfg.Radius * shell * pulse * (0.3 + 0.7 * grow)
		+ noiseVec(i, c.t, 0.25)
	stiff[i] = 0.6 + seedB[i] * 0.8
	carry[i] = 0
end

--==================================================================
-- HABILIDADE: CLONE DE NANOTECNOLOGIA
--==================================================================
local Clone = registerOverlay({
	name = "Clone",
	share = CONFIG.Clone.BlockShare,
	formTime = CONFIG.Clone.FormTime,
	dissolveTime = CONFIG.Clone.DissolveTime,
	cooldown = "Clone",
})

local function sampleHistory(hist, time)
	local n = #hist
	if n == 0 then
		return nil, nil
	end
	if time <= hist[1].time then
		return hist[1].cf, hist[1].h
	end
	for j = n, 1, -1 do
		local a = hist[j]
		if a.time <= time then
			local b = hist[j + 1]
			if not b then
				return a.cf, a.h
			end
			local t = (time - a.time) / math.max(b.time - a.time, 1e-4)
			local h = (a.h and b.h) and (a.h + (b.h - a.h) * t) or b.h
			return a.cf:Lerp(b.cf, t), h
		end
	end
	return hist[n].cf, hist[n].h
end

local function playerGroundHeight()
	local res = Workspace:Raycast(root.Position, Vector3.new(0, -60, 0), rayParams)
	if res then
		return root.Position.Y - res.Position.Y
	end
	return nil
end

Clone.onStart = function(self)
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, model = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not model then
		return false
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("ForceField") or d:IsA("Sound")
			or d:IsA("Decal") or d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("ParticleEmitter")
			or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light") or d:IsA("Constraint")
			or d:IsA("BillboardGui") or d:IsA("Highlight") or string.sub(d.Name, 1, 4) == "Nano" then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
			d.Anchored = false
			d.Transparency = 1
		end
	end

	local cRoot = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not cRoot or not hum then
		model:Destroy()
		return false
	end
	cRoot.Anchored = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	pcall(function()
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
		hum.EvaluateStateMachine = false
	end)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	model.Name = "NanoClone_" .. player.Name
	cRoot.CFrame = root.CFrame * CFrame.new(CONFIG.Clone.Offset)
	model.Parent = nanoFolder

	self.model = model
	self.root = cRoot
	self.animator = animator
	self.tracks = {}
	self.history = { { time = clock, cf = root.CFrame, h = playerGroundHeight() } }
	self.lastPos = cRoot.Position
	self.speedBoost = 0
	self.ghostParts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= cRoot then
			table.insert(self.ghostParts, d)
		end
	end
	self.map = buildSurfaceMap(model, math.ceil(TOTAL * self.share), cRoot)

	if CONFIG.Clone.Highlight then
		local hl = Instance.new("Highlight")
		hl.FillColor = COLORS.Primary
		hl.OutlineColor = COLORS.Accent
		hl.FillTransparency = 1
		hl.OutlineTransparency = 1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = model
		hl.Parent = model
		self.highlight = hl
	end

	for i = 1, TOTAL do
		mark[i] = false
	end
	Effects.pulse(ctx.torsoPos, COLORS.Primary, 5, 0.5)
	return true
end

Clone.onFormed = function(self)
	for _, p in ipairs(self.ghostParts or {}) do
		if p.Parent then
			p.Transparency = CONFIG.Clone.GhostTransparency
		end
	end
	if self.highlight then
		tween(self.highlight, 0.6, { FillTransparency = 0.85, OutlineTransparency = 0.35 })
	end
	if self.root then
		Effects.shockwave(self.root.Position - Vector3.new(0, 2.8, 0), Vector3.new(0, 1, 0), COLORS.Primary, 10, 0.6)
	end
end

Clone.onStop = function(self)
	if self.highlight then
		tween(self.highlight, 0.3, { FillTransparency = 1, OutlineTransparency = 1 })
	end
	for _, p in ipairs(self.ghostParts or {}) do
		if p.Parent then
			p.Transparency = 1
		end
	end
end

Clone.onRemoved = function(self)
	if self.tracks then
		for _, tr in pairs(self.tracks) do
			pcall(function()
				tr:Stop(0)
			end)
		end
	end
	if self.model then
		self.model:Destroy()
	end
	self.model, self.root, self.animator, self.tracks, self.map, self.highlight = nil, nil, nil, nil, nil, nil
end

local function syncCloneAnimations(self)
	local playerAnimator = humanoid:FindFirstChildOfClass("Animator")
	if not playerAnimator or not self.animator then
		return
	end
	local seen = {}
	for _, tr in ipairs(playerAnimator:GetPlayingAnimationTracks()) do
		local anim = tr.Animation
		if anim and anim.AnimationId ~= "" then
			local id = anim.AnimationId
			seen[id] = true
			local ct = self.tracks[id]
			if not ct then
				local ok, res = pcall(function()
					return self.animator:LoadAnimation(anim)
				end)
				if ok and res then
					ct = res
					ct.Priority = tr.Priority
					ct.Looped = tr.Looped
					self.tracks[id] = ct
				end
			end
			if ct then
				if not ct.IsPlaying then
					ct:Play(0.15, tr.WeightTarget, tr.Speed)
				end
				if math.abs(ct.Speed - tr.Speed) > 0.01 then
					ct:AdjustSpeed(tr.Speed)
				end
				if math.abs(ct.WeightTarget - tr.WeightTarget) > 0.01 then
					ct:AdjustWeight(tr.WeightTarget, 0.15)
				end
				if ct.Length > 0 and math.abs(ct.TimePosition - tr.TimePosition) > 0.15 then
					ct.TimePosition = tr.TimePosition
				end
			end
		end
	end
	for id, ct in pairs(self.tracks) do
		if not seen[id] and ct.IsPlaying then
			ct:Stop(0.2)
		end
	end
end

Clone.update = function(self, dt, c)
	if not self.model or not self.root or not self.root.Parent then
		if self.state ~= "dissolving" then
			overlayStop(self, true)
		end
		return
	end
	local cfg = CONFIG.Clone
	table.insert(self.history, { time = clock, cf = root.CFrame, h = playerGroundHeight() })
	while #self.history > 2 and self.history[2].time < clock - cfg.Delay - 0.25 do
		table.remove(self.history, 1)
	end
	local cf, h = sampleHistory(self.history, clock - cfg.Delay)
	if not cf then
		return
	end
	local targetCF = cf * CFrame.new(cfg.Offset)
	if h then
		local p = targetCF.Position
		local res = Workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -70, 0), rayParams)
		if res then
			targetCF += Vector3.new(0, (res.Position.Y + h) - p.Y, 0)
		end
	end
	self.root.CFrame = self.root.CFrame:Lerp(targetCF, 1 - math.exp(-22 * dt))

	local speed = (self.root.Position - self.lastPos).Magnitude / math.max(dt, 1e-3)
	self.lastPos = self.root.Position
	self.speedBoost = clamp(speed / 16, 0, 2)

	syncCloneAnimations(self)

	if (self.root.Position - c.rootPos).Magnitude > cfg.MaxDistance then
		overlayStop(self)
	end
end

Clone.formation = function(i, k, n, c, self)
	local map = self.map
	if not map or #map == 0 or not self.root then
		target[i] = c.torsoPos
		return
	end
	local cfg = CONFIG.Clone
	local entry = map[((k - 1) % #map) + 1]
	local threshold = (k - 0.5) / n
	local stage = clamp((self.progress - threshold * 0.75) / 0.25, 0, 1)
	local part = entry.part
	alphaTarget[i] = 1
	if stage >= 1 and part.Parent then
		local pcf = part.CFrame
		local world = pcf:PointToWorldSpace(entry.offset)
		if burstUntil[i] > c.t then
			world += pcf:VectorToWorldSpace(entry.normal) * cfg.BurstDistance
		end
		target[i] = world
		alignRot[i] = pcf.Rotation
		stiff[i] = cfg.FollowStiffness
		carry[i] = 1
		mark[i] = true
		if self.state == "active" and math.random() < cfg.ReorganizeChance * (1 + self.speedBoost) * c.dt then
			burstUntil[i] = c.t + 0.2 + math.random() * 0.25
		end
	elseif stage > 0 then
		if mark[i] then
			mark[i] = false
			vel[i] += randomUnit() * 10
		end
		local base = self.root.Position
		local ang = phase[i] + c.t * 5
		local rad = 2.2 * (1 - stage) + 0.4
		local y = -2.5 + (entry.relHeight + 2.5) * stage
		target[i] = base + Vector3.new(math.cos(ang) * rad, y, math.sin(ang) * rad)
		stiff[i] = 1.6
	else
		if mark[i] then
			mark[i] = false
			vel[i] += randomUnit() * 10
		end
		local ang = phase[i] + c.t * 3
		target[i] = c.torsoPos + Vector3.new(math.cos(ang) * 0.8, math.sin(c.t * 2 + phase[i]) * 0.6, math.sin(ang) * 0.8)
		stiff[i] = 2
		carry[i] = 1
	end
end

--==================================================================
-- HABILIDADE: ARMADURA
--==================================================================
local Armor = registerOverlay({
	name = "Armor",
	share = CONFIG.Armor.BlockShare,
	formTime = CONFIG.Armor.FormTime,
	dissolveTime = CONFIG.Armor.DissolveTime,
	duration = CONFIG.Armor.Duration,
	cooldown = "Armor",
})

Armor.onStart = function(self)
	self.map = buildSurfaceMap(character, math.ceil(TOTAL * self.share), root)
	if #self.map == 0 then
		return false
	end
	Effects.pulse(ctx.torsoPos, COLORS.Secondary, 6, 0.4)
end

Armor.onFormed = function()
	Effects.pulse(ctx.torsoPos, COLORS.Accent, 7, 0.35)
end

Armor.formation = function(i, k, n, c, self)
	local map = self.map
	local entry = map[((k - 1) % #map) + 1]
	local threshold = (k - 0.5) / n
	local stage = clamp((self.progress - threshold * 0.7) / 0.3, 0, 1)
	local part = entry.part
	alphaTarget[i] = 1
	if stage >= 1 and part.Parent then
		local pcf = part.CFrame
		local breath = math.sin(c.t * 3 + entry.relHeight * 2) * 0.03
		target[i] = pcf:PointToWorldSpace(entry.offset + entry.normal * breath)
		alignRot[i] = pcf.Rotation
		stiff[i] = 3.5
		carry[i] = 1
	else
		local ang = phase[i] + c.t * 6
		local rad = 1.2 + 1.8 * (1 - stage)
		target[i] = c.rootPos + Vector3.new(math.cos(ang) * rad, entry.relHeight, math.sin(ang) * rad)
		stiff[i] = 2
		carry[i] = 1
	end
end

--==================================================================
-- HABILIDADE: LAMINA NO BRACO
--==================================================================
local Blade = registerOverlay({
	name = "Blade",
	share = CONFIG.Blade.BlockShare,
	formTime = CONFIG.Blade.FormTime,
	dissolveTime = CONFIG.Blade.DissolveTime,
	duration = CONFIG.Blade.Duration,
	cooldown = "Blade",
	slashT = -10,
})

Blade.onStart = function()
	if not rightHand then
		return false
	end
end

function Blade.slash()
	if Blade.state ~= "active" then
		return
	end
	Blade.slashT = clock
	if rightHand then
		local tip = rightHand.Position - rightHand.CFrame.UpVector * CONFIG.Blade.Length
		Effects.shockwave(tip, ctx.flatLook, COLORS.Accent, 7, 0.3)
	end
end

Blade.formation = function(i, k, n, c, self)
	local cfg = CONFIG.Blade
	local hand = rightHand
	if not hand or not hand.Parent then
		target[i] = c.torsoPos
		return
	end
	local hcf = hand.CFrame
	local grip = hcf.Position - hcf.UpVector * (hand.Size.Y * 0.5)
	local dir = -hcf.UpVector
	local bladeCF = CFrame.lookAt(grip, grip + dir, hcf.LookVector)
	local since = c.t - self.slashT
	local lengthMul = 1 + 0.6 * math.exp(-since * 6)
	local L = cfg.Length * lengthMul * smoothstep(self.progress)
	local guardCount = math.max(1, math.floor(n * 0.12))
	local localP
	if k <= guardCount then
		local u = (k - 0.5) / guardCount
		localP = Vector3.new((u - 0.5) * cfg.GuardWidth, (seedB[i] - 0.5) * 0.15, -0.1)
	else
		local u = (k - guardCount - 0.5) / math.max(1, n - guardCount)
		local halfW = cfg.Width * 0.5 * (1 - u ^ 3) + 0.03
		local ripple = math.sin(c.t * 8 - u * 10) * 0.03
		localP = Vector3.new((seedA[i] * 2 - 1) * halfW + ripple, (seedC[i] - 0.5) * 0.12, -(0.2 + u * L))
	end
	target[i] = bladeCF:PointToWorldSpace(localP)
	alignRot[i] = bladeCF.Rotation
	stiff[i] = 3.2
	carry[i] = 1
	alphaTarget[i] = 1
end

--==================================================================
-- HABILIDADE: ESCUDO
--==================================================================
local Shield = registerOverlay({
	name = "Shield",
	share = CONFIG.Shield.BlockShare,
	formTime = CONFIG.Shield.FormTime,
	dissolveTime = CONFIG.Shield.DissolveTime,
	duration = CONFIG.Shield.Duration,
	cooldown = "Shield",
})

Shield.onStart = function(self)
	local core = Instance.new("Part")
	core.Name = "NanoShieldCore"
	core.Shape = Enum.PartType.Cylinder
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Material = Enum.Material.ForceField
	core.Color = COLORS.Primary
	core.Transparency = 0.2
	core.Size = Vector3.new(0.1, 0.1, 0.1)
	core.CFrame = root.CFrame
	core.Parent = nanoFolder
	self.core = core
end

Shield.onRemoved = function(self)
	if self.core then
		self.core:Destroy()
		self.core = nil
	end
end

Shield.update = function(self, dt, c)
	local cfg = CONFIG.Shield
	local center = c.rootPos + c.flatLook * cfg.Distance + Vector3.new(0, 0.4, 0)
	self.cf = CFrame.lookAt(center, center + c.flatLook)
	self.scale = easeOutBack(self.progress)
	if self.core then
		local d = cfg.Radius * 2 * math.max(self.scale, 0.01)
		self.core.Size = Vector3.new(0.12, d, d)
		self.core.CFrame = self.cf * CFrame.Angles(0, math.pi / 2, 0)
	end
end

Shield.formation = function(i, k, n, c, self)
	local cfg = CONFIG.Shield
	local cf = self.cf or c.rootCF
	local R = cfg.Radius * (self.scale or 0)
	local rimCount = math.max(1, math.floor(n * 0.22))
	local localP
	if k <= rimCount then
		local a = (k / rimCount) * TAU + c.t * 1.5
		localP = Vector3.new(math.cos(a) * R, math.sin(a) * R, 0)
	else
		local x, z = fibDisc(k - rimCount, math.max(1, n - rimCount))
		local r2 = x * x + z * z
		local bulge = (1 - r2) * cfg.Curvature
		local wave = math.sin(c.t * 4 - math.sqrt(r2) * 8) * 0.06
		localP = Vector3.new(x * R, z * R, -(bulge + wave))
	end
	target[i] = cf:PointToWorldSpace(localP)
	alignRot[i] = cf.Rotation
	stiff[i] = 2.5
	carry[i] = 1
	alphaTarget[i] = 1
end

--==================================================================
-- HABILIDADE: PLATAFORMA TEMPORARIA
--==================================================================
local Platform = registerOverlay({
	name = "Platform",
	share = CONFIG.Platform.BlockShare,
	formTime = CONFIG.Platform.FormTime,
	dissolveTime = CONFIG.Platform.DissolveTime,
	duration = CONFIG.Platform.Duration,
	cooldown = "Platform",
})

Platform.onStart = function(self)
	local size = CONFIG.Platform.Size
	local fy = math.min(ctx.leftFoot.Y, ctx.rightFoot.Y)
	local look = ctx.flatLook
	local center = Vector3.new(ctx.rootPos.X, fy - size.Y * 0.5 - 0.05, ctx.rootPos.Z)
	self.cf = CFrame.lookAt(center, center + look)
	local col = Instance.new("Part")
	col.Name = "NanoPlatform"
	col.Anchored = true
	col.CanCollide = true
	col.CanQuery = false
	col.CanTouch = false
	col.CastShadow = false
	col.Material = Enum.Material.ForceField
	col.Color = COLORS.Primary
	col.Transparency = 0.6
	col.Size = size
	col.CFrame = self.cf
	col.Parent = nanoFolder
	self.collider = col
	Effects.shockwave(center + Vector3.new(0, size.Y * 0.5, 0), Vector3.new(0, 1, 0), COLORS.Primary, 12, 0.5)
end

Platform.onStop = function(self)
	if self.collider then
		tween(self.collider, self.dissolveTime, { Transparency = 1 })
	end
end

Platform.onRemoved = function(self)
	if self.collider then
		self.collider:Destroy()
		self.collider = nil
	end
end

Platform.formation = function(i, k, n, c, self)
	local size = CONFIG.Platform.Size
	local side = math.max(2, math.ceil(math.sqrt(n)))
	local gx = (k - 1) % side
	local gz = math.floor((k - 1) / side)
	local u = gx / (side - 1) - 0.5
	local v = gz / (side - 1) - 0.5
	local dist = math.sqrt(u * u + v * v) / 0.7071
	local reveal = clamp((self.progress * 1.3 - dist) / 0.3, 0, 1)
	local y = size.Y * 0.5 + math.sin(c.t * 3 + dist * 6) * 0.05 - (1 - reveal) * 3
	local localP = Vector3.new(u * size.X * (0.4 + 0.6 * reveal), y, v * size.Z * (0.4 + 0.6 * reveal))
	target[i] = self.cf:PointToWorldSpace(localP)
	alignRot[i] = self.cf.Rotation
	stiff[i] = 2
	carry[i] = 0
	alphaTarget[i] = 1
end

-- Ordem importa: o Clone fica sempre no inicio do pool (indices estaveis).
-- (registerOverlay ja adicionou: Swarm, Clone, Armor, Blade, Shield, Platform)
table.sort(Overlays, function(a, b)
	local order = { Clone = 1, Armor = 2, Blade = 3, Shield = 4, Platform = 5, Swarm = 6 }
	return (order[a.name] or 99) < (order[b.name] or 99)
end)

--==================================================================
-- DRONES
--==================================================================
local Drones = { on = false, parts = {}, pos = {}, vel = {}, rot = {}, beams = {}, alpha = 0, lastT = 1 }

for j = 1, CONFIG.Drones.Count do
	local s = CONFIG.Drones.Size
	local d = Instance.new("Part")
	d.Name = "NanoDrone"
	d.Size = Vector3.new(s, s * 0.45, s)
	d.Anchored = true
	d.CanCollide = false
	d.CanQuery = false
	d.CanTouch = false
	d.CastShadow = false
	d.Material = Enum.Material.Neon
	d.Color = COLORS.Secondary
	d.Transparency = 1
	d.CFrame = root.CFrame
	d.Parent = nanoFolder
	local att = Instance.new("Attachment")
	att.Parent = d
	local light = Instance.new("PointLight")
	light.Color = COLORS.Secondary
	light.Range = 6
	light.Brightness = 1.5
	light.Enabled = false
	light.Parent = d
	local beam = Instance.new("Beam")
	beam.Attachment0 = att
	beam.Attachment1 = beamTargetAtt
	beam.Width0 = 0.08
	beam.Width1 = 0.02
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(COLORS.Secondary, COLORS.Primary)
	beam.Transparency = NumberSequence.new(0.3, 0.85)
	beam.Enabled = false
	beam.Parent = d
	Drones.parts[j] = d
	Drones.pos[j] = root.Position
	Drones.vel[j] = Vector3.zero
	Drones.rot[j] = CFrame.new()
	Drones.beams[j] = beam
	Drones.lights = Drones.lights or {}
	Drones.lights[j] = light
end

function Drones.toggle()
	if not Drones.on and not cooldownReady("Drones") then
		return
	end
	if not Drones.on then
		setCooldown("Drones")
		for j = 1, #Drones.parts do
			Drones.pos[j] = ctx.torsoPos
			Drones.vel[j] = randomUnit() * 15
		end
		Effects.pulse(ctx.torsoPos, COLORS.Secondary, 4, 0.35)
	end
	Drones.on = not Drones.on
end

--==================================================================
-- VOO
--==================================================================
Flight = { state = "off", vel = Vector3.zero, timer = 0, intensity = 0, velDir = Vector3.zero, boosting = false, mobileUp = false, mobileDown = false, mobileBoost = false }

local function getWorldMoveDir()
	if Controls then
		local ok, mv = pcall(function()
			return Controls:GetMoveVector()
		end)
		if ok and mv and mv.Magnitude > 0.01 then
			local cf = camera.CFrame
			local dir = cf.RightVector * mv.X + cf.LookVector * (-mv.Z)
			if dir.Magnitude > 1 then
				dir = dir.Unit
			end
			return dir
		end
		return Vector3.zero
	end
	return humanoid.MoveDirection
end

function Flight.start()
	if Flight.state ~= "off" or not cooldownReady("Flight") then
		return
	end
	setCooldown("Flight")
	local att = Instance.new("Attachment")
	att.Name = "NanoFlightAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "NanoFlightVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.max(root.AssemblyMass, 1) * Workspace.Gravity * 25
	lv.VectorVelocity = root.AssemblyLinearVelocity
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "NanoFlightOrientation"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.Responsiveness = CONFIG.Flight.TurnResponsiveness
	ao.MaxTorque = 1e7
	ao.RigidityEnabled = false
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root
	humanoid.AutoRotate = false
	Flight.att, Flight.lv, Flight.ao = att, lv, ao
	Flight.vel = root.AssemblyLinearVelocity
	Flight.state = "takeoff"
	Flight.timer = 0
	Base.setMode("flight")
	Effects.shockwave((ctx.leftFoot + ctx.rightFoot) * 0.5, Vector3.new(0, 1, 0), COLORS.Primary, 10, 0.5)
end

function Flight.stop()
	if Flight.state == "takeoff" or Flight.state == "flying" then
		Flight.state = "landing"
		Flight.timer = 0
	end
end

function Flight.release(landed)
	if Flight.lv then Flight.lv:Destroy() end
	if Flight.ao then Flight.ao:Destroy() end
	if Flight.att then Flight.att:Destroy() end
	Flight.lv, Flight.ao, Flight.att = nil, nil, nil
	if humanoid.Parent then
		humanoid.AutoRotate = true
	end
	Flight.state = "off"
	if Flight.boosting then
		Flight.boosting = false
		tween(camera, 0.5, { FieldOfView = baseFOV })
	end
	if landed then
		if Base.mode == "flight" then
			Base.setMode("feet")
			Base.autoCloudAt = clock + 1.2
		end
		Effects.shockwave((ctx.leftFoot + ctx.rightFoot) * 0.5, Vector3.new(0, 1, 0), COLORS.Primary, 8, 0.45)
	elseif Base.mode == "flight" then
		Base.setMode("cloud")
	end
end

local function anyKeyDown(keys)
	for _, k in ipairs(keys) do
		if UserInputService:IsKeyDown(k) then
			return true
		end
	end
	return false
end

function Flight.update(dt)
	local cfg = CONFIG.Flight
	if Flight.state == "off" then
		Flight.intensity += (0 - Flight.intensity) * math.min(1, dt * 4)
		ctx.flightIntensity = Flight.intensity
		return
	end
	if not Flight.lv or not Flight.lv.Parent then
		Flight.release(false)
		return
	end
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local up = (not typing and UserInputService:IsKeyDown(cfg.UpKey)) or Flight.mobileUp
	local down = (not typing and anyKeyDown(cfg.DownKeys)) or Flight.mobileDown
	local boost = ((not typing and UserInputService:IsKeyDown(cfg.BoostKey)) or Flight.mobileBoost) and Flight.state == "flying"
	local moveDir = getWorldMoveDir()
	local desired

	if Flight.state == "takeoff" then
		Flight.timer += dt
		local a = clamp(Flight.timer / cfg.TakeoffTime, 0, 1)
		local peak = cfg.TakeoffHeight * math.pi / (2 * cfg.TakeoffTime)
		desired = Vector3.new(0, math.sin(a * math.pi) * peak, 0) + moveDir * cfg.MaxSpeed * 0.25
		if a >= 1 then
			Flight.state = "flying"
		end
	elseif Flight.state == "flying" then
		local speed = cfg.MaxSpeed * (boost and cfg.BoostMultiplier or 1)
		local vertical = ((up and 1 or 0) - (down and 1 or 0)) * cfg.VerticalSpeed
		local hover = math.sin(clock * cfg.HoverFrequency) * cfg.HoverAmplitude
		desired = moveDir * speed + Vector3.new(0, vertical + hover, 0)
	else
		Flight.timer += dt
		desired = Vector3.new(0, -cfg.LandingSpeed, 0)
		local probe = humanoid.HipHeight + root.Size.Y * 0.5 + 1.5
		local res = Workspace:Raycast(root.Position, Vector3.new(0, -probe, 0), rayParams)
		if res or Flight.timer > cfg.LandingTimeout then
			Flight.release(true)
			return
		end
	end

	local accelerating = desired.Magnitude > Flight.vel.Magnitude
	local rate = (Flight.state == "takeoff") and 10 or (accelerating and cfg.Acceleration or cfg.Deceleration)
	Flight.vel = Flight.vel:Lerp(desired, 1 - math.exp(-rate * dt))
	Flight.lv.VectorVelocity = Flight.vel

	-- inclinacao natural
	local baseRot = CFrame.lookAt(Vector3.zero, ctx.flatLook)
	local localV = baseRot:VectorToObjectSpace(Vector3.new(Flight.vel.X, 0, Flight.vel.Z)) / cfg.MaxSpeed
	local tilt = math.rad(cfg.TiltAngle)
	Flight.ao.CFrame = baseRot * CFrame.Angles(clamp(localV.Z, -1.2, 1.2) * tilt, 0, clamp(-localV.X, -1, 1) * tilt * 0.7)

	-- boost (aceleracao) com FOV
	if boost and not Flight.boosting then
		Flight.boosting = true
		tween(camera, 0.4, { FieldOfView = baseFOV + cfg.BoostFOV })
		local back = Flight.vel.Magnitude > 1 and -Flight.vel.Unit or Vector3.new(0, -1, 0)
		Effects.shockwave(ctx.rootPos + back * 2, back, COLORS.Accent, 7, 0.4)
	elseif not boost and Flight.boosting then
		Flight.boosting = false
		tween(camera, 0.6, { FieldOfView = baseFOV })
	end

	local takeoffBoost = (Flight.state == "takeoff") and 0.8 or 0
	Flight.intensity = clamp(Flight.vel.Magnitude / cfg.MaxSpeed + takeoffBoost, 0, 1.6)
	Flight.velDir = Flight.vel.Magnitude > 1 and Flight.vel.Unit or Vector3.zero
	ctx.flightIntensity = Flight.intensity
	ctx.flightVelDir = Flight.velDir
end

--==================================================================
-- QUALIDADE / LOD
--==================================================================
local qualityScale = CONFIG.Quality.Levels[CONFIG.Quality.Mode] or 1
local activeCount = TOTAL
local fpsAcc, fpsFrames, lodTimer = 0, 0, 0

local function updateLOD(dt)
	fpsAcc += dt
	fpsFrames += 1
	lodTimer += dt
	if lodTimer < 0.5 then
		return
	end
	local q = CONFIG.Quality
	local fps = fpsFrames / math.max(fpsAcc, 1e-3)
	if q.Mode == "Auto" then
		if fps < q.TargetFPS - 5 then
			qualityScale = math.max(q.MinScale, qualityScale - 0.1)
		elseif fps > q.TargetFPS + 6 then
			qualityScale = math.min(1, qualityScale + 0.05)
		end
	end
	local dist = (camera.CFrame.Position - root.Position).Magnitude
	local df = 1 - clamp((dist - q.LODNear) / (q.LODFar - q.LODNear), 0, 1) * (1 - q.LODMinFactor)
	local newCount = clamp(math.floor(TOTAL * qualityScale * df), math.min(q.MinBlocks, TOTAL), TOTAL)
	if math.abs(newCount - activeCount) >= TOTAL * 0.08 or (newCount == TOTAL and activeCount ~= TOTAL) then
		activeCount = newCount
	end
	fpsAcc, fpsFrames, lodTimer = 0, 0, 0
end

--==================================================================
-- LOOP PRINCIPAL DOS BLOCOS
--==================================================================
local bulkParts, bulkCFs = {}, {}
local sparkles = {}
local sparkleTimer = 0

local function allocateAndForm()
	local n = activeCount
	local reserve = (Base.mode == "flight") and math.min(n, CONFIG.Flight.ReservedBlocks) or 0
	local remaining = n - reserve
	local start = 1
	for _, def in ipairs(Overlays) do
		if def.state ~= "off" and remaining > 0 then
			local count = math.min(remaining, math.floor(n * def.share + 0.5))
			if count > 0 then
				for k = 1, count do
					local i = start + k - 1
					stiff[i] = 1
					carry[i] = 0
					alignRot[i] = nil
					def.formation(i, k, count, ctx, def)
				end
				start += count
				remaining -= count
			end
		end
	end
	local baseCount = n - start + 1
	local fn = BaseForm[Base.mode] or BaseForm.cloud
	for k = 1, baseCount do
		local i = start + k - 1
		stiff[i] = 1
		carry[i] = 0
		alignRot[i] = nil
		alphaTarget[i] = 1
		fn(i, k, baseCount, ctx)
	end
	for i = n + 1, TOTAL do
		target[i] = ctx.torsoPos
		stiff[i] = 3
		carry[i] = 1
		alignRot[i] = nil
		alphaTarget[i] = 0
	end
end

local function stepBlocks(dt)
	local m = CONFIG.Motion
	local alphaRate = 1 - math.exp(-m.AlphaSpeed * dt)
	local rotRate = 1 - math.exp(-10 * dt)
	for i = 1, TOTAL do
		local part = parts[i]
		if hidden[i] then
			if alphaTarget[i] > 0 then
				hidden[i] = false
				pos[i] = ctx.torsoPos
				vel[i] = Vector3.zero
				prevTarget[i] = target[i]
				alpha[i] = 0
			end
		end
		if not hidden[i] then
			local tg = target[i]
			local p = pos[i]
			local d = tg - prevTarget[i]
			local cr = carry[i]
			if cr > 0 and d.Magnitude < 4 then
				p += d * cr
			end
			prevTarget[i] = tg
			local s = stiff[i] * stiffVar[i]
			local v = vel[i] + (tg - p) * (m.Stiffness * s * dt)
			v *= math.exp(-m.Damping * math.sqrt(s) * dt)
			local spd = v.Magnitude
			if spd > m.MaxSpeed then
				v *= m.MaxSpeed / spd
			end
			p += v * dt
			if (tg - p).Magnitude > 250 then
				p = tg
				v = Vector3.zero
			end
			pos[i] = p
			vel[i] = v

			local a = alpha[i] + (alphaTarget[i] - alpha[i]) * alphaRate
			alpha[i] = a

			local ar = alignRot[i]
			if ar then
				rot[i] = rot[i]:Lerp(ar, rotRate)
			else
				rot[i] = rot[i] * CFrame.fromAxisAngle(axis[i], spin[i] * dt)
			end

			local tr = 1 - a * (1 - baseT[i])
			if a < 0.01 and alphaTarget[i] <= 0 then
				tr = 1
				hidden[i] = true
			end
			if math.abs(tr - lastT[i]) > 0.03 or (tr == 1 and lastT[i] ~= 1) then
				part.Transparency = tr
				lastT[i] = tr
				local trail = trails[i]
				if trail then
					trail.Enabled = tr < 0.6
				end
			end
			if not hidden[i] then
				table.insert(bulkParts, part)
				table.insert(bulkCFs, CFrame.new(p) * rot[i])
			end
		end
	end
end

local function updateSparkles(dt)
	if not CONFIG.Quality.Sparkles then
		return
	end
	for j = #sparkles, 1, -1 do
		local s = sparkles[j]
		if clock >= s.untilT then
			parts[s.i].Color = baseColor[s.i]
			table.remove(sparkles, j)
		end
	end
	sparkleTimer += dt
	if sparkleTimer > 0.05 then
		sparkleTimer = 0
		local i = math.random(1, math.max(1, activeCount))
		if not hidden[i] and isNeon[i] then
			parts[i].Color = COLORS.Accent
			table.insert(sparkles, { i = i, untilT = clock + 0.15 })
		end
	end
end

local function updateDrones(dt)
	local cfg = CONFIG.Drones
	local targetAlpha = Drones.on and 1 or 0
	Drones.alpha += (targetAlpha - Drones.alpha) * math.min(1, dt * 6)
	local swarmOn = overlayActive(Swarm)
	beamTargetAtt.Position = Swarm.center
	if Drones.alpha < 0.01 and not Drones.on then
		if Drones.lastT < 1 then
			for j, d in ipairs(Drones.parts) do
				d.Transparency = 1
				Drones.beams[j].Enabled = false
				Drones.lights[j].Enabled = false
			end
			Drones.lastT = 1
		end
		return
	end
	local count = #Drones.parts
	local tr = 1 - Drones.alpha
	local writeT = math.abs(tr - Drones.lastT) > 0.03
	for j = 1, count do
		local tg
		if Drones.on then
			local ang = ctx.t * cfg.Speed + (j - 1) / count * TAU
			tg = ctx.rootPos + Vector3.new(math.cos(ang) * cfg.Radius, cfg.Height + math.sin(ctx.t * 2 + j) * 0.35, math.sin(ang) * cfg.Radius)
		else
			tg = ctx.torsoPos
		end
		local p, v = Drones.pos[j], Drones.vel[j]
		v += (tg - p) * (CONFIG.Motion.Stiffness * 2.5 * dt)
		v *= math.exp(-CONFIG.Motion.Damping * 1.58 * dt)
		p += v * dt
		Drones.pos[j], Drones.vel[j] = p, v
		if swarmOn then
			Drones.rot[j] = Drones.rot[j]:Lerp(CFrame.lookAt(p, Swarm.center).Rotation, math.min(1, dt * 10))
		else
			Drones.rot[j] = Drones.rot[j] * CFrame.Angles(0, dt * 3, 0)
		end
		table.insert(bulkParts, Drones.parts[j])
		table.insert(bulkCFs, CFrame.new(p) * Drones.rot[j])
		if writeT then
			Drones.parts[j].Transparency = tr
			Drones.lights[j].Enabled = CONFIG.Quality.Lights and tr < 0.5
		end
		local beamOn = swarmOn and Drones.on
		if Drones.beams[j].Enabled ~= beamOn then
			Drones.beams[j].Enabled = beamOn
		end
	end
	if writeT then
		Drones.lastT = tr
	end
end

--==================================================================
-- ESTADO DO TOOL / PARTICULAS
--==================================================================
local equipped = false

local function updateEmitters()
	local q = CONFIG.Quality
	local mult = q.Particles and (q.ParticleRate * qualityScale) or 0
	local auraRate = 0
	local footRate = 0
	if equipped or Base.mode ~= "stored" then
		if Base.mode == "cloud" then
			auraRate = 6
		elseif Base.mode == "feet" then
			auraRate = 4
			footRate = 8
		elseif Base.mode == "flight" then
			auraRate = 10
			footRate = 20 + 50 * Flight.intensity
		elseif Base.mode == "recall" then
			auraRate = 20
		end
	end
	auraRate *= mult
	footRate *= mult
	if math.abs(auraEmitter.Rate - auraRate) > 0.5 then
		auraEmitter.Rate = auraRate
	end
	for _, em in ipairs(footEmitters) do
		if math.abs(em.Rate - footRate) > 0.5 then
			em.Rate = footRate
		end
	end
	local lightOn = q.Lights and Base.mode ~= "stored"
	if auraLight.Enabled ~= lightOn then
		auraLight.Enabled = lightOn
	end
end

--==================================================================
-- ACOES
--==================================================================
local Actions = {}

Actions.Cloud = function()
	if Flight.state ~= "off" then
		return
	end
	Base.setMode("cloud")
end

Actions.Feet = function()
	if Flight.state ~= "off" or not cooldownReady("Feet") then
		return
	end
	setCooldown("Feet")
	Base.setMode(Base.mode == "feet" and "cloud" or "feet")
end

Actions.Flight = function()
	if Flight.state == "off" then
		Flight.start()
	else
		Flight.stop()
	end
end

Actions.Clone = function() overlayToggle(Clone) end
Actions.Armor = function() overlayToggle(Armor) end
Actions.Shield = function() overlayToggle(Shield) end
Actions.Blade = function() overlayToggle(Blade) end
Actions.Platform = function() overlayToggle(Platform) end
Actions.Drones = function() Drones.toggle() end

Actions.Recall = function()
	if not cooldownReady("Recall") then
		return
	end
	setCooldown("Recall")
	for _, def in ipairs(Overlays) do
		overlayStop(def, true)
	end
	if Flight.state ~= "off" then
		Flight.stop()
	end
	Drones.on = false
	Base.setMode("recall")
end

local mobileSwarmMode = false
Actions.Swarm = function()
	mobileSwarmMode = not mobileSwarmMode
	if not mobileSwarmMode then
		overlayStop(Swarm)
	end
end

local isActive = {
	Cloud = function() return Base.mode == "cloud" end,
	Feet = function() return Base.mode == "feet" end,
	Flight = function() return Flight.state ~= "off" end,
	Clone = function() return overlayActive(Clone) end,
	Armor = function() return overlayActive(Armor) end,
	Shield = function() return overlayActive(Shield) end,
	Blade = function() return overlayActive(Blade) end,
	Platform = function() return overlayActive(Platform) end,
	Drones = function() return Drones.on end,
	Recall = function() return Base.mode == "recall" or Base.mode == "stored" end,
	Swarm = function() return mobileSwarmMode end,
}

--==================================================================
-- INTERFACE (PC + MOBILE)
--==================================================================
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ABILITY_LIST = {
	{ id = "Cloud", label = "Nuvem", short = "NUV" },
	{ id = "Feet", label = "Pes", short = "PES" },
	{ id = "Flight", label = "Voo", short = "VOO" },
	{ id = "Clone", label = "Clone", short = "CLN" },
	{ id = "Armor", label = "Armadura", short = "ARM" },
	{ id = "Shield", label = "Escudo", short = "ESC" },
	{ id = "Blade", label = "Lamina", short = "LAM" },
	{ id = "Platform", label = "Plataf.", short = "PLT" },
	{ id = "Drones", label = "Drones", short = "DRN" },
	{ id = "Recall", label = "Recall", short = "REC" },
}
if isMobile then
	table.insert(ABILITY_LIST, 1, { id = "Swarm", label = "Enxame", short = "ENX" })
end

local gui = Instance.new("ScreenGui")
gui.Name = "NanoTechUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local BTN = isMobile and 54 or 52
local container = Instance.new("Frame")
container.Name = "Abilities"
container.BackgroundTransparency = 1
container.Parent = gui

if isMobile then
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -12, 1, -170)
	container.Size = UDim2.fromOffset(3 * (BTN + 6), 4 * (BTN + 6))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(BTN, BTN)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = container
else
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -80)
	container.Size = UDim2.fromOffset(#ABILITY_LIST * (BTN + 5), BTN)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 5)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = container
end

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamBold
status.TextSize = 13
status.TextColor3 = COLORS.Primary
status.TextStrokeTransparency = 0.6
status.Size = UDim2.fromOffset(320, 18)
status.AnchorPoint = container.AnchorPoint
if isMobile then
	status.Position = UDim2.new(1, -12, 1, -170 - 4 * (BTN + 6) - 4)
	status.TextXAlignment = Enum.TextXAlignment.Right
else
	status.Position = UDim2.new(0.5, 0, 1, -80 - BTN - 4)
end
status.Text = ""
status.Parent = gui

local function makeButton(parent, topText, bottomText, order)
	local b = Instance.new("TextButton")
	b.Name = bottomText
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(BTN, BTN)
	b.AutoButtonColor = true
	b.BackgroundColor3 = Color3.fromRGB(10, 16, 26)
	b.BackgroundTransparency = 0.15
	b.Text = ""
	b.ClipsDescendants = true
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = COLORS.Primary
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = b
	local cd = Instance.new("Frame")
	cd.Name = "Cooldown"
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.fromScale(0, 1)
	cd.Size = UDim2.fromScale(1, 0)
	cd.BackgroundColor3 = Color3.new(0, 0, 0)
	cd.BackgroundTransparency = 0.4
	cd.BorderSizePixel = 0
	cd.ZIndex = 2
	cd.Parent = b
	local top = Instance.new("TextLabel")
	top.BackgroundTransparency = 1
	top.Font = Enum.Font.GothamBlack
	top.TextSize = 16
	top.TextColor3 = COLORS.Primary
	top.Size = UDim2.fromScale(1, 0.5)
	top.Position = UDim2.fromScale(0, 0.06)
	top.Text = topText
	top.ZIndex = 3
	top.Parent = b
	local bottom = Instance.new("TextLabel")
	bottom.BackgroundTransparency = 1
	bottom.Font = Enum.Font.GothamBold
	bottom.TextSize = 10
	bottom.TextColor3 = Color3.new(1, 1, 1)
	bottom.Size = UDim2.fromScale(1, 0.4)
	bottom.Position = UDim2.fromScale(0, 0.55)
	bottom.Text = bottomText
	bottom.ZIndex = 3
	bottom.Parent = b
	local cdText = Instance.new("TextLabel")
	cdText.BackgroundTransparency = 1
	cdText.Font = Enum.Font.GothamBold
	cdText.TextSize = 14
	cdText.TextColor3 = Color3.new(1, 1, 1)
	cdText.Size = UDim2.fromScale(1, 1)
	cdText.Text = ""
	cdText.ZIndex = 4
	cdText.Parent = b
	return b, stroke, cd, cdText
end

local uiButtons = {}
for idx, info in ipairs(ABILITY_LIST) do
	local key = CONFIG.Keys[info.id]
	local topText = isMobile and info.short or (key and key.Name or "")
	local b, stroke, cd, cdText = makeButton(container, topText, info.label, idx)
	connect(b.Activated, function()
		if equipped and Actions[info.id] then
			Actions[info.id]()
		end
	end)
	table.insert(uiButtons, { id = info.id, button = b, stroke = stroke, cd = cd, cdText = cdText, lastText = "" })
end

-- Controles de voo mobile
local flyPad = Instance.new("Frame")
flyPad.Name = "FlightPad"
flyPad.BackgroundTransparency = 1
flyPad.AnchorPoint = Vector2.new(1, 0.5)
flyPad.Position = UDim2.new(1, -(3 * (BTN + 6) + 24), 0.55, 0)
flyPad.Size = UDim2.fromOffset(BTN + 6, 3 * (BTN + 8))
flyPad.Visible = false
flyPad.Parent = gui
local padList = Instance.new("UIListLayout")
padList.Padding = UDim.new(0, 8)
padList.SortOrder = Enum.SortOrder.LayoutOrder
padList.Parent = flyPad

local function holdButton(text, label, order, flagName)
	local b = makeButton(flyPad, text, label, order)
	connect(b.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			Flight[flagName] = true
		end
	end)
	connect(b.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			Flight[flagName] = false
		end
	end)
end
holdButton("UP", "Sobe", 1, "mobileUp")
holdButton("DN", "Desce", 2, "mobileDown")
holdButton(">>", "Boost", 3, "mobileBoost")

local function updateUI()
	if not gui.Enabled then
		return
	end
	for _, ub in ipairs(uiButtons) do
		local cdName = CONFIG.Cooldowns[ub.id] and ub.id or nil
		local rem = cdName and cooldownRemaining(cdName) or 0
		local total = cdName and CONFIG.Cooldowns[cdName] or 1
		local frac = (total > 0) and clamp(rem / total, 0, 1) or 0
		ub.cd.Size = UDim2.fromScale(1, frac)
		local txt = rem > 0.05 and string.format("%.1f", rem) or ""
		if txt ~= ub.lastText then
			ub.cdText.Text = txt
			ub.lastText = txt
		end
		local active = isActive[ub.id] and isActive[ub.id]()
		ub.stroke.Color = active and COLORS.Accent or COLORS.Primary
		ub.stroke.Transparency = active and 0 or 0.4
	end
	flyPad.Visible = isMobile and Flight.state ~= "off"
	status.Text = string.format("NANO // %d/%d blocos // qualidade %d%% // %s", activeCount, TOTAL, math.floor(qualityScale * 100), string.upper(Base.mode))
end

--==================================================================
-- INPUT
--==================================================================
local keyToAction = {}
for id, key in pairs(CONFIG.Keys) do
	keyToAction[key] = id
end

local activeTouch = nil

connect(UserInputService.InputBegan, function(input, gp)
	if not equipped then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if gp or UserInputService:GetFocusedTextBox() then
			return
		end
		local id = keyToAction[input.KeyCode]
		if id and Actions[id] then
			Actions[id]()
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if gp or not mobileSwarmMode or activeTouch then
			return
		end
		activeTouch = input
		Swarm.inputMode = "touch"
		Swarm.screenPos = Vector2.new(input.Position.X, input.Position.Y)
		overlayStart(Swarm)
	end
end)

connect(UserInputService.InputChanged, function(input)
	if input == activeTouch then
		Swarm.screenPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

connect(UserInputService.InputEnded, function(input)
	if input == activeTouch then
		activeTouch = nil
		overlayStop(Swarm)
	end
end)

connect(tool.Activated, function()
	if overlayActive(Blade) then
		Blade.slash()
		return
	end
	if isMobile then
		return
	end
	Swarm.inputMode = "mouse"
	overlayStart(Swarm)
end)

connect(tool.Deactivated, function()
	if Swarm.inputMode == "mouse" then
		overlayStop(Swarm)
	end
end)

connect(tool.Equipped, function()
	equipped = true
	gui.Enabled = true
	if Base.mode == "stored" or Base.mode == "recall" then
		Base.mode = "stored"
		Base.setMode("cloud")
	end
end)

connect(tool.Unequipped, function()
	equipped = false
	gui.Enabled = false
	mobileSwarmMode = false
	activeTouch = nil
	for _, def in ipairs(Overlays) do
		overlayStop(def, true)
	end
	if Flight.state ~= "off" then
		Flight.stop()
	end
	Flight.mobileUp, Flight.mobileDown, Flight.mobileBoost = false, false, false
	Drones.on = false
	Base.setMode("recall")
end)

--==================================================================
-- FRAME LOOP
--==================================================================
local RENDER_NAME = "NanoTechUpdate_" .. tostring(math.random(1, 1e6))
local cleaned = false

local function onRender(dt)
	if cleaned or not root.Parent then
		return
	end
	dt = math.min(dt, 1 / 20)
	clock += dt
	updateLOD(dt)
	updateContext(dt)
	Flight.update(dt)
	updateOverlays(dt)
	Base.update(dt)

	table.clear(bulkParts)
	table.clear(bulkCFs)
	allocateAndForm()
	stepBlocks(dt)
	updateDrones(dt)
	if #bulkParts > 0 then
		Workspace:BulkMoveTo(bulkParts, bulkCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	updateSparkles(dt)
	updateEmitters()
	updateUI()

	if Clone.model then
		rayParams.FilterDescendantsInstances = { character, nanoFolder }
	end
end

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)

--==================================================================
-- LIMPEZA
--==================================================================
local function cleanup()
	if cleaned then
		return
	end
	cleaned = true
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	pcall(Flight.release, false)
	for _, def in ipairs(Overlays) do
		if def.state ~= "off" and def.onRemoved then
			pcall(def.onRemoved, def)
		end
	end
	camera.FieldOfView = baseFOV
	if nanoFolder then nanoFolder:Destroy() end
	if beamTargetAtt then beamTargetAtt:Destroy() end
	if auraAtt then auraAtt:Destroy() end
	if gui then gui:Destroy() end
	if not hostTool and tool then tool:Destroy() end
end

humanoid.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)
character.AncestryChanged:Connect(function(_, parent)
	if not parent then
		cleanup()
	end
end)
