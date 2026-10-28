--====================================================================
--  LOGISTICS EMPIRE v5 — SERVER
--  Script -> ServerScriptService, имя "Server"
--
--  • Город по центру (улицы, кварталы, 16 мест доставки)
--  • 20 баз-складов по периметру города (5 с каждой стороны)
--  • Транспорт покупается по одному, у каждой машины свой уровень
--  • Контракты на поставки, склад с запасом, перерождение и т.д.
--  Свои модели (необязательно): ServerStorage/Models -> Vehicle1..6, Warehouse
--====================================================================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")

--------------------------------------------------------------------
-- НАСТРОЙКИ
--------------------------------------------------------------------
local MAX_SLOTS = 20                  -- баз (и игроков) на сервере
local PASS_X2_ID = 0                  -- ID геймпасса "Доход x2" (0 = выключено)
local EVENT_MIN, EVENT_MAX = 240, 360 -- пауза между событиями, сек
local REBIRTH_BASE_COST = 4000000
local REBIRTH_BONUS = 0.5
local OFFLINE_RATE, OFFLINE_MAX = 0.25, 7200
local DAILY_COOLDOWN = 20 * 3600
local CODES = { WELCOME = 600, LOGISTICS = 1800, PLANE = 3600 }

local START_MONEY = 150
local START_SLOTS, MAX_VEHICLE_SLOTS = 3, 12
local MAX_ACTIVE_CONTRACTS, MAX_OFFERS = 3, 5
local AVG_DIST = 350                  -- средняя дальность для оценки дохода

local store = DataStoreService:GetDataStore("LogisticsEmpire_v5")

local function makeRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = RS
	return r
end
local upgradeRemote = makeRemote("Upgrade")
local stateRemote = makeRemote("State")
local readyRemote = makeRemote("Ready")
local eventRemote = makeRemote("Event")

--------------------------------------------------------------------
-- ТРАНСПОРТ (покупается по одному)
-- price — цена, cap — посылок за рейс, pay — цена посылки, speed — студов/сек
--------------------------------------------------------------------
local TIERS = {
	{ name = "Мопед",         price = 100,     cap = 4,   pay = 4,  speed = 30,  bike = true,
	  body = Vector3.new(3, 1.2, 1.2),  cab = Vector3.new(1, 1.8, 1),     color = Color3.fromRGB(200, 50, 50) },
	{ name = "Старая машина", price = 1500,    cap = 8,   pay = 6,  speed = 34,
	  body = Vector3.new(6, 2, 3.5),    cab = Vector3.new(3, 2.6, 3.2),   color = Color3.fromRGB(140, 90, 55) },
	{ name = "Фургон",        price = 12000,   cap = 16,  pay = 9,  speed = 40,
	  body = Vector3.new(7, 3, 4),      cab = Vector3.new(3, 3.2, 3.8),   color = Color3.fromRGB(235, 235, 235) },
	{ name = "Грузовик",      price = 80000,   cap = 30,  pay = 14, speed = 46,
	  body = Vector3.new(9, 3.5, 4),    cab = Vector3.new(3.5, 4, 3.8),   color = Color3.fromRGB(230, 130, 40) },
	{ name = "Фура",          price = 500000,  cap = 60,  pay = 22, speed = 52,
	  body = Vector3.new(14, 4, 4.5),   cab = Vector3.new(4, 4.5, 4.2),   color = Color3.fromRGB(50, 100, 210) },
	{ name = "Самолёт",       price = 3000000, cap = 120, pay = 40, speed = 110, fly = true, wing = 16,
	  body = Vector3.new(14, 3, 3),     cab = Vector3.new(3, 2.4, 2.4),   color = Color3.fromRGB(215, 220, 230) },
}

-- виды грузов для контрактов (minTier = какой транспорт нужен)
local CARGO = {
	{ name = "Обычные товары", icon = "📦", minTier = 1, mult = 1.0 },
	{ name = "Продукты",       icon = "🍎", minTier = 2, mult = 1.1 },
	{ name = "Хрупкий груз",   icon = "🧪", minTier = 3, mult = 1.2 },
	{ name = "Заморозка",      icon = "🧊", minTier = 4, mult = 1.3 },
	{ name = "Тяжёлый груз",   icon = "🏗", minTier = 5, mult = 1.4 },
	{ name = "Срочный груз",   icon = "⚡", minTier = 6, mult = 1.6 },
}

-- общие улучшения компании
local UPGRADES = {
	capacity  = { base = 300, growth = 1.6,  max = 20 }, -- +10% вместимости за ур.
	speed     = { base = 400, growth = 1.6,  max = 15 }, -- +8% скорости за ур.
	price     = { base = 500, growth = 1.65, max = 20 }, -- +10% к тарифу за ур.
	warehouse = { base = 300, growth = 1.8,  max = 15 }, -- x1.5 склад за ур.
}

local eventMult = 1
local currentEvent = nil

--------------------------------------------------------------------
-- ФОРМУЛЫ
--------------------------------------------------------------------
local function vehCap(d, tier)   return math.floor(TIERS[tier].cap * (1 + 0.1 * (d.lv.capacity - 1))) end
local function vehSpeed(d, tier) return TIERS[tier].speed * (1 + 0.08 * (d.lv.speed - 1)) end
local function vehPay(d, tier)   return TIERS[tier].pay * (1 + 0.1 * (d.lv.price - 1)) end
local function stockCap(d)       return math.floor(80 * 1.5 ^ (d.lv.warehouse - 1)) end
local function upgradeCost(kind, d)
	local u = UPGRADES[kind]
	return math.floor(u.base * u.growth ^ (d.lv[kind] - 1))
end
local function slotCost(d)       return math.floor(400 * 1.9 ^ (d.slots - START_SLOTS)) end
local function sellValue(tier)   return math.floor(TIERS[tier].price * 0.5) end
local function upgradeVehCost(tier) return TIERS[tier + 1].price - sellValue(tier) end
local function rebirthCost(d)    return REBIRTH_BASE_COST * 2 ^ d.rebirths end

local function permMult(session)
	local m = 1 + REBIRTH_BONUS * session.data.rebirths
	if session.x2 then m *= 2 end
	return m
end
local function totalMult(session) return permMult(session) * eventMult end

local function incomePerSec(session)
	local d = session.data
	local sum = 0
	for _, v in ipairs(session.vehicles) do
		sum += vehCap(d, v.tier) * vehPay(d, v.tier) * (1 + AVG_DIST / 600) / (2 * AVG_DIST / vehSpeed(d, v.tier) + 4.5)
	end
	return sum
end

local function fmtNum(n)
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while n >= 1000 and i < #units do
		n = n / 1000
		i += 1
	end
	if i == 1 then return tostring(math.floor(n)) end
	return tostring(math.floor(n * 100) / 100) .. units[i]
end

--------------------------------------------------------------------
-- МОДЕЛИ ИЗ TOOLBOX (ServerStorage/Models)
--------------------------------------------------------------------
local function norm(str)
	return (string.lower(str):gsub("[%s_%-]", ""))
end

local function findModelsFolder()
	for _, c in ipairs(SS:GetChildren()) do
		if norm(c.Name) == "models" and not c:IsA("Model") then return c end
	end
	return nil
end

local function findObject(name)
	local want = norm(name)
	local places = {}
	local f = findModelsFolder()
	if f then table.insert(places, f) end
	table.insert(places, SS)
	for _, place in ipairs(places) do
		for _, c in ipairs(place:GetChildren()) do
			if norm(c.Name) == want then return c end
		end
	end
	return nil
end

local function getTemplate(name)
	local obj = findObject(name)
	if not obj then return nil end
	if obj:IsA("Model") then return obj end
	local m = Instance.new("Model")
	m.Name = name
	if obj:IsA("BasePart") then
		obj:Clone().Parent = m
	else
		for _, c in ipairs(obj:GetChildren()) do c:Clone().Parent = m end
	end
	if #m:GetDescendants() == 0 then
		m:Destroy()
		return nil
	end
	return m
end

local function cleanModel(m)
	for _, x in ipairs(m:GetDescendants()) do
		if x:IsA("LuaSourceContainer") then x:Destroy() end
	end
end

local function orientModel(m, targetLen, center, groundY, extraYaw)
	local yaw = (m:GetAttribute("Yaw") or 0) + (extraYaw or 0)
	local _, size = m:GetBoundingBox()
	local longest = math.max(size.X, size.Z)
	if longest > 0 then m:ScaleTo(m:GetScale() * targetLen / longest) end
	_, size = m:GetBoundingBox()
	local rot = yaw + (size.Z > size.X and 90 or 0)
	m:PivotTo(CFrame.new(center) * CFrame.Angles(0, math.rad(rot), 0))
	local bbCF, bbSize = m:GetBoundingBox()
	local wantY = groundY and (groundY + bbSize.Y / 2) or center.Y
	local want = Vector3.new(center.X, wantY, center.Z)
	m:PivotTo(m:GetPivot() + (want - bbCF.Position))
end

--------------------------------------------------------------------
-- ПРИМИТИВЫ
--------------------------------------------------------------------
local function mkPartCF(parent, size, cf, color, name)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function mkPart(parent, size, pos, color, name)
	return mkPartCF(parent, size, CFrame.new(pos), color, name)
end

local function label(part, text, offset, maxDist)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(280, 56)
	bb.StudsOffset = Vector3.new(0, offset, 0)
	bb.AlwaysOnTop = true
	if maxDist then bb.MaxDistance = maxDist end
	bb.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0
	t.Parent = bb
	return t
end

local function makeBoard(parent, pos, w, h, title, rowCount, rowSize)
	local baseY = 4
	local part = mkPart(parent, Vector3.new(w, h, 1), Vector3.new(pos.X, baseY + h / 2, pos.Z), Color3.fromRGB(25, 28, 40), "Board")
	for _, sx in ipairs({ -1, 1 }) do
		mkPart(parent, Vector3.new(1.2, baseY, 1.2), Vector3.new(pos.X + sx * (w / 2 - 3), baseY / 2, pos.Z), Color3.fromRGB(60, 60, 70), "BoardLeg")
	end
	local all = {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 30
		sg.Parent = part
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, 80)
		t.BackgroundTransparency = 1
		t.Text = title
		t.TextColor3 = Color3.fromRGB(255, 210, 90)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = 48
		t.Parent = sg
		for i = 1, rowCount do
			local r = Instance.new("TextLabel")
			r.Size = UDim2.new(1, -60, 0, rowSize)
			r.Position = UDim2.fromOffset(30, 80 + (i - 1) * rowSize)
			r.BackgroundTransparency = 1
			r.Text = ""
			r.TextColor3 = Color3.new(1, 1, 1)
			r.Font = Enum.Font.GothamBold
			r.TextSize = math.floor(rowSize * 0.62)
			r.TextXAlignment = Enum.TextXAlignment.Left
			r.TextWrapped = true
			r.Parent = sg
			table.insert(all, { label = r, index = i })
		end
	end
	return function(lines)
		for _, e in ipairs(all) do
			e.label.Text = lines[e.index] or ""
		end
	end
end

--------------------------------------------------------------------
-- ГОРОД: сетка улиц 6x6 кварталов, 16 мест доставки
--------------------------------------------------------------------
local N, P, RW = 6, 86, 16            -- кварталов, шаг улиц, ширина дороги
local HALF = N * P / 2                -- 258
local function u(k) return (k - N / 2) * P end

local DEST_TYPES = {
	{ "🏪", "Магазин «Свежесть»" }, { "🏥", "Больница №1" }, { "🏫", "Школа №5" }, { "🍔", "Бургерная «Топ»" },
	{ "🏬", "ТЦ «Галерея»" }, { "🏭", "Завод «Металл»" }, { "🏨", "Отель «Восход»" }, { "🏦", "Банк «Центр»" },
	{ "🏢", "Офис «Нова»" }, { "🎮", "Игры «Пиксель»" }, { "🍕", "Пиццерия «Рим»" }, { "💊", "Аптека «Здоровье»" },
	{ "📚", "Книжный «Страница»" }, { "⛽", "Заправка «Дорога»" }, { "🛒", "Супермаркет «Лента»" }, { "🧁", "Кондитерская «Сладость»" },
}
local DESTS = {}

local function buildCity()
	local folder = Instance.new("Folder")
	folder.Name = "City"
	folder.Parent = workspace

	local span = N * P + RW
	mkPart(folder, Vector3.new(span, 1, span), Vector3.new(0, 0, 0), Color3.fromRGB(165, 165, 172), "CityGround")
	local roadColor = Color3.fromRGB(45, 45, 50)
	for k = 0, N do
		mkPart(folder, Vector3.new(span, 0.2, RW), Vector3.new(0, 0.6, u(k)), roadColor, "RoadH")
		mkPart(folder, Vector3.new(RW, 0.2, span), Vector3.new(u(k), 0.6, 0), roadColor, "RoadV")
	end

	local rng = Random.new(11)
	local blocks = {}
	for bi = 0, N - 1 do
		for bj = 0, N - 1 do table.insert(blocks, { bi, bj }) end
	end
	for i = #blocks, 2, -1 do
		local j = rng:NextInteger(1, i)
		blocks[i], blocks[j] = blocks[j], blocks[i]
	end
	local destAt, parkAt = {}, {}
	for i = 1, #DEST_TYPES do destAt[blocks[i][1] * 100 + blocks[i][2]] = i end
	for i = #DEST_TYPES + 1, #DEST_TYPES + 3 do parkAt[blocks[i][1] * 100 + blocks[i][2]] = true end

	local palette = {
		Color3.fromRGB(120, 130, 150), Color3.fromRGB(150, 140, 130), Color3.fromRGB(100, 115, 135),
		Color3.fromRGB(165, 160, 150), Color3.fromRGB(90, 100, 120),
	}

	for bi = 0, N - 1 do
		for bj = 0, N - 1 do
			local xc = (u(bi) + u(bi + 1)) / 2
			local zc = (u(bj) + u(bj + 1)) / 2
			local key = bi * 100 + bj
			local di = destAt[key]
			if di then
				local h = 20 + rng:NextInteger(0, 14)
				local col = Color3.fromHSV(di / #DEST_TYPES, 0.55, 0.9)
				local b = mkPart(folder, Vector3.new(46, h, 46), Vector3.new(xc, 0.5 + h / 2, zc), col, "Dest" .. di)
				mkPart(folder, Vector3.new(48, 1.5, 48), Vector3.new(xc, 0.5 + h + 0.75, zc), col:Lerp(Color3.new(0, 0, 0), 0.3), "Roof")
				local info = DEST_TYPES[di]
				label(b, info[1] .. " " .. info[2], h / 2 + 6, 450)
				local stop = Vector3.new(xc, 0.7, u(bj))
				local ring = mkPart(folder, Vector3.new(0.3, 12, 12), stop + Vector3.new(0, 0.15, 0), col, "Stop" .. di)
				ring.Shape = Enum.PartType.Cylinder
				ring.CFrame = CFrame.new(stop + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				ring.Material = Enum.Material.Neon
				ring.Transparency = 0.2
				ring.CanCollide = false
				DESTS[di] = { icon = info[1], name = info[2], stop = stop }
			elseif parkAt[key] then
				mkPart(folder, Vector3.new(66, 0.2, 66), Vector3.new(xc, 0.6, zc), Color3.fromRGB(80, 150, 75), "Park")
				for _, o in ipairs({ { -18, -18 }, { 18, -18 }, { -18, 18 }, { 18, 18 }, { 0, 0 } }) do
					mkPart(folder, Vector3.new(1.4, 7, 1.4), Vector3.new(xc + o[1], 4, zc + o[2]), Color3.fromRGB(110, 75, 40), "Trunk")
					local leaves = mkPart(folder, Vector3.new(9, 9, 9), Vector3.new(xc + o[1], 10, zc + o[2]), Color3.fromRGB(55, 135, 60), "Leaves")
					leaves.Shape = Enum.PartType.Ball
					leaves.CanCollide = false
				end
			else
				for _, o in ipairs({ { -17, -17 }, { 17, -17 }, { -17, 17 }, { 17, 17 } }) do
					if rng:NextInteger(1, 10) > 1 then
						local h = rng:NextInteger(12, 50)
						local b = mkPart(folder, Vector3.new(30, h, 30), Vector3.new(xc + o[1], 0.5 + h / 2, zc + o[2]),
							palette[rng:NextInteger(1, #palette)], "Building")
						b.Material = Enum.Material.Concrete
					end
				end
			end
		end
	end
end

local function nearestRoad(v)
	local best, bd = u(0), math.huge
	for k = 0, N do
		local d = math.abs(u(k) - v)
		if d < bd then
			bd = d
			best = u(k)
		end
	end
	return best
end

--------------------------------------------------------------------
-- БАЗЫ-СКЛАДЫ (20 штук вокруг города)
--------------------------------------------------------------------
local plots = {}
local usedSlots = {}
local sessions = {}

local function slotGeometry(slot)
	local side = math.floor(slot / 5)
	local k = slot % 5 + 1
	local line = u(k)
	local off = HALF + RW / 2 + 12 + 40
	if side == 0 then return Vector3.new(line, 0, -off), Vector3.new(0, 0, 1), side end
	if side == 1 then return Vector3.new(line, 0, off), Vector3.new(0, 0, -1), side end
	if side == 2 then return Vector3.new(-off, 0, line), Vector3.new(1, 0, 0), side end
	return Vector3.new(off, 0, line), Vector3.new(-1, 0, 0), side
end

local function basePoint(plot, r, f)
	return plot.origin + plot.right * r + plot.forward * f
end

local function buildBase(slot)
	local origin, forward, side = slotGeometry(slot)
	local baseCF = CFrame.lookAt(origin, origin + forward)
	local color = Color3.fromHSV((slot / MAX_SLOTS) % 1, 0.55, 0.95)

	local folder = Instance.new("Folder")
	folder.Name = "Base" .. slot
	folder.Parent = workspace
	local vfolder = Instance.new("Folder")
	vfolder.Name = "Vehicles"
	vfolder.Parent = folder

	local function L(r, y, f) return baseCF * CFrame.new(r, y, -f) end

	mkPartCF(folder, Vector3.new(80, 1, 80), L(0, 0, 0), Color3.fromRGB(105, 110, 118), "Lot")
	mkPartCF(folder, Vector3.new(72, 0.2, 42), L(0, 0.6, 16), Color3.fromRGB(48, 48, 54), "Parking")
	mkPartCF(folder, Vector3.new(RW, 0.2, 14), L(0, 0.6, 47), Color3.fromRGB(45, 45, 50), "Connector")

	-- склад
	local stockLabel
	local built = false
	local tpl = getTemplate("Warehouse")
	if tpl then
		local m = tpl:Clone()
		local ok, err = pcall(function()
			cleanModel(m)
			m.Parent = folder
			local c = L(0, 0, -26).Position
			orientModel(m, 58, Vector3.new(c.X, 0, c.Z), 0.5, side >= 2 and 90 or 0)
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then p.Anchored = true end
			end
			local _, sz = m:GetBoundingBox()
			local anchor = mkPartCF(folder, Vector3.new(1, 1, 1), CFrame.new(c.X, 0.5 + sz.Y, c.Z), color, "WarehouseLabel")
			anchor.Transparency = 1
			anchor.CanCollide = false
			stockLabel = label(anchor, "📦 СКЛАД", 3, 220)
		end)
		if ok then
			built = true
		else
			warn("[Logistics] не удалось использовать модель Warehouse: " .. tostring(err))
			m:Destroy()
		end
	end
	if not built then
		local wh = mkPartCF(folder, Vector3.new(62, 16, 26), L(0, 8.5, -26), Color3.fromRGB(200, 120, 40), "Warehouse")
		mkPartCF(folder, Vector3.new(64, 1, 28), L(0, 17, -26), color, "Roof")
		for _, r in ipairs({ -18, 0, 18 }) do
			mkPartCF(folder, Vector3.new(11, 9, 0.4), L(r, 5, -12.8), Color3.fromRGB(40, 40, 46), "Bay")
		end
		stockLabel = label(wh, "📦 СКЛАД", 11, 220)
	end

	-- забор и ворота
	mkPartCF(folder, Vector3.new(80, 3, 0.8), L(0, 2, -39.6), color, "FenceBack")
	mkPartCF(folder, Vector3.new(0.8, 3, 80), L(-39.6, 2, 0), color, "FenceL")
	mkPartCF(folder, Vector3.new(0.8, 3, 80), L(39.6, 2, 0), color, "FenceR")
	mkPartCF(folder, Vector3.new(28, 3, 0.8), L(-26, 2, 39.6), color, "FenceFL")
	mkPartCF(folder, Vector3.new(28, 3, 0.8), L(26, 2, 39.6), color, "FenceFR")
	mkPartCF(folder, Vector3.new(1.5, 9, 1.5), L(-12, 5, 39.6), color, "GateL")
	mkPartCF(folder, Vector3.new(1.5, 9, 1.5), L(12, 5, 39.6), color, "GateR")
	local beam = mkPartCF(folder, Vector3.new(26, 2.5, 1.5), L(0, 9.5, 39.6), color, "GateBeam")
	local sign = label(beam, "СВОБОДНО", 3, 350)

	-- площадка спавна
	local pad = mkPartCF(folder, Vector3.new(8, 0.2, 8), L(30, 0.6, -8), color, "SpawnPad")
	pad.Material = Enum.Material.Neon
	local sp = L(30, 3.5, -8).Position

	plots[slot] = {
		folder = folder, vfolder = vfolder, origin = origin, forward = forward, right = baseCF.RightVector,
		side = side, sign = sign, stockLabel = stockLabel,
		yaw = math.atan2(-forward.Z, forward.X),
		spawnCF = CFrame.lookAt(sp, sp + forward),
	}
end

--------------------------------------------------------------------
-- МАРШРУТЫ
--------------------------------------------------------------------
local SPOT_COLS = 6
local function spotRF(i)
	local col = (i - 1) % SPOT_COLS
	local row = math.floor((i - 1) / SPOT_COLS)
	return (col - 2.5) * 11, (row == 0) and 26 or 6
end

local function wheelDiameter(tier) return math.max(1.1, tier.body.Y * 0.9) end
local function vehicleY(tier)
	if tier.fly then return 0.7 + tier.body.Y / 2 + 0.6 end
	return 0.7 + wheelDiameter(tier) / 2 + tier.body.Y / 2
end

local function dedupe(pts)
	local out = {}
	for _, p in ipairs(pts) do
		local last = out[#out]
		if not last or (p - last).Magnitude > 0.1 then table.insert(out, p) end
	end
	return out
end

local function cityRoute(plot, dest)
	local T = dest.stop
	local g = basePoint(plot, 0, 46)
	local pts = { Vector3.new(g.X, 0.7, g.Z) }
	if plot.side <= 1 then
		table.insert(pts, Vector3.new(g.X, 0.7, T.Z))
	else
		local vx = nearestRoad(T.X)
		table.insert(pts, Vector3.new(vx, 0.7, g.Z))
		table.insert(pts, Vector3.new(vx, 0.7, T.Z))
	end
	table.insert(pts, T)
	return pts
end

local function pathTo(plot, v, dest)
	local tier = TIERS[v.tier]
	local y = vehicleY(tier)
	local r, f = spotRF(v.spot)
	local function G(p) return Vector3.new(p.X, y, p.Z) end
	local spotP = G(basePoint(plot, r, f))
	if tier.fly then
		local T = G(dest.stop)
		local a = spotP:Lerp(T, 0.2)
		local b = spotP:Lerp(T, 0.8)
		return { spotP, Vector3.new(a.X, 60, a.Z), Vector3.new(b.X, 60, b.Z), T }
	end
	local pts = { spotP, G(basePoint(plot, r, 37)), G(basePoint(plot, 0, 37)) }
	for _, p in ipairs(cityRoute(plot, dest)) do table.insert(pts, G(p)) end
	return dedupe(pts)
end

local function pathLength(pts)
	local len = 0
	for i = 1, #pts - 1 do len += (pts[i + 1] - pts[i]).Magnitude end
	return len
end

local function reversePath(pts)
	local out = {}
	for i = #pts, 1, -1 do table.insert(out, pts[i]) end
	return out
end

local function routeDist(plot, destIdx, fly)
	return pathLength(pathTo(plot, { tier = fly and #TIERS or 1, spot = 1 }, DESTS[destIdx]))
end

--------------------------------------------------------------------
-- ВНЕШНИЙ ВИД ТРАНСПОРТА
--------------------------------------------------------------------
local function buildVehicle(parent, tier, cf)
	local body = Instance.new("Part")
	body.Name = "Vehicle"
	body.Size = tier.body
	body.Color = tier.color
	body.Anchored = true
	body.CanCollide = false
	body.CFrame = cf
	body.Parent = parent

	local function attach(size, offset, color, rot, shape)
		local p = Instance.new("Part")
		if shape then p.Shape = shape end
		p.Size = size
		p.Color = color
		p.CanCollide = false
		p.Massless = true
		p.CFrame = cf * CFrame.new(offset) * (rot or CFrame.new())
		p.Parent = body
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = p
		w.Parent = p
	end

	local dark = tier.color:Lerp(Color3.new(0, 0, 0), 0.35)
	local cabY = (tier.cab.Y - tier.body.Y) / 2
	attach(tier.cab, Vector3.new(tier.body.X / 2 + tier.cab.X / 2, cabY, 0), dark)
	if not tier.bike then
		attach(Vector3.new(0.2, tier.cab.Y * 0.45, tier.cab.Z * 0.8),
			Vector3.new(tier.body.X / 2 + tier.cab.X + 0.05, cabY + tier.cab.Y * 0.15, 0),
			Color3.fromRGB(150, 210, 255))
	end

	if tier.fly then
		local wingColor = tier.color:Lerp(Color3.new(0, 0, 0), 0.2)
		attach(Vector3.new(4, 0.4, tier.wing), Vector3.new(0, 0, 0), wingColor)
		attach(Vector3.new(2.5, 4, 0.4), Vector3.new(-tier.body.X / 2 + 1, tier.body.Y / 2 + 1.5, 0), wingColor)
		attach(Vector3.new(2, 0.3, 6), Vector3.new(-tier.body.X / 2 + 1, tier.body.Y / 4, 0), wingColor)
	else
		local D = wheelDiameter(tier)
		local rot = CFrame.Angles(0, math.pi / 2, 0)
		local wheelColor = Color3.fromRGB(25, 25, 25)
		local cyl = Enum.PartType.Cylinder
		if tier.bike then
			for _, sx in ipairs({ -0.38, 0.38 }) do
				attach(Vector3.new(0.5, D, D), Vector3.new(tier.body.X * sx, -tier.body.Y / 2, 0), wheelColor, rot, cyl)
			end
		else
			for _, sx in ipairs({ -0.3, 0.3 }) do
				for _, sz in ipairs({ -1, 1 }) do
					attach(Vector3.new(0.9, D, D),
						Vector3.new(tier.body.X * sx, -tier.body.Y / 2, sz * tier.body.Z / 2),
						wheelColor, rot, cyl)
				end
			end
		end
	end
	return body
end

local function buildModelVehicle(parent, template, tier, cf)
	local m = template:Clone()
	cleanModel(m)
	local root = Instance.new("Part")
	root.Name = "Vehicle"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CFrame = CFrame.new(cf.Position)
	root.Parent = parent
	m.Parent = root
	local ok, err = pcall(function()
		orientModel(m, tier.body.X + tier.cab.X, cf.Position, (not tier.fly) and 0.7 or nil, 0)
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = false
				p.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = p
			end
		end
	end)
	if not ok then
		root:Destroy()
		error(err)
	end
	root.CFrame = cf
	return root
end

--------------------------------------------------------------------
-- КОНТРАКТЫ И ГРУЗЫ
--------------------------------------------------------------------
local function findActive(session, id)
	for _, c in ipairs(session.active) do
		if c.id == id then return c end
	end
	return nil
end

local function removeActive(session, id)
	for i, c in ipairs(session.active) do
		if c.id == id then
			table.remove(session.active, i)
			return
		end
	end
end

local function hasTier(session, minTier)
	for _, v in ipairs(session.vehicles) do
		if v.tier >= minTier then return true end
	end
	return false
end

local function returnJob(session, v)
	local job = v.job
	if not job then return end
	session.stock = math.min(stockCap(session.data), session.stock + job.load)
	if job.cid then
		local c = findActive(session, job.cid)
		if c then c.inTransit = math.max(0, c.inTransit - job.load) end
	end
	v.job = nil
end

local function takeJob(session, v)
	local d = session.data
	if session.stock < 1 then return nil end
	local load = math.min(vehCap(d, v.tier), math.floor(session.stock))
	local best
	for _, c in ipairs(session.active) do
		if c.minTier <= v.tier and (c.qty - c.delivered - c.inTransit) > 0 then
			if not best or c.deadline < best.deadline then best = c end
		end
	end
	local job
	if best then
		load = math.min(load, best.qty - best.delivered - best.inTransit)
		best.inTransit += load
		job = { cid = best.id, dest = best.dest, load = load }
	else
		job = { dest = math.random(#DESTS), load = load }
	end
	session.stock -= load
	v.job = job
	return job
end

local function deliverJob(session, v, job, dist)
	local d = session.data
	local c = job.cid and findActive(session, job.cid)
	local pay, bonus = 0, 0
	if c then
		c.inTransit = math.max(0, c.inTransit - job.load)
		c.delivered += job.load
		pay = math.floor(c.reward * job.load / c.qty * eventMult)
		if c.delivered >= c.qty then
			removeActive(session, c.id)
			d.done += 1
			if os.time() <= c.deadline - c.limit * 0.5 then
				bonus = math.floor(c.reward * 0.25 * eventMult)
			end
			session.notice = { text = "✅ Контракт выполнен: " .. DESTS[c.dest].name, amount = bonus > 0 and bonus or nil }
		end
	else
		pay = math.floor(job.load * vehPay(d, v.tier) * (1 + dist / 600) * totalMult(session))
	end
	local total = pay + bonus
	session.money.Value += total
	d.earned += total
	session.delivered.Value += job.load
	session.sendState()
end

local function genOffer(session)
	local d = session.data
	local plot = plots[session.slot]
	local cargoIdx = math.random(1, math.min(#CARGO, d.maxTier + 1))
	local cg = CARGO[cargoIdx]
	local destIdx = math.random(#DESTS)
	local dist = routeDist(plot, destIdx, cg.minTier >= #TIERS)
	local cap = vehCap(d, cg.minTier)
	local qty = math.max(10, math.floor(cap * math.random(3, 7) / 5 + 0.5) * 5)
	local rep = 1 + math.min(1, d.done * 0.02)
	local reward = math.floor(qty * TIERS[cg.minTier].pay * cg.mult * 2.5 * (1 + dist / 600) * rep * permMult(session))
	local speed = vehSpeed(d, cg.minTier)
	local trips = math.ceil(qty / cap)
	local limit = math.clamp(math.floor(trips * (2 * dist / speed + 4) * 1.6 + 60), 120, 900)
	session.nextId += 1
	return {
		id = session.nextId, dest = destIdx, cargo = cargoIdx, qty = qty, reward = reward,
		limit = limit, minTier = cg.minTier, expires = os.time() + 300,
	}
end

--------------------------------------------------------------------
-- ТРАНСПОРТ: создание, движение, удаление
--------------------------------------------------------------------
local function freeSpot(session)
	for i = 1, MAX_VEHICLE_SLOTS do
		if not session.spots[i] then
			session.spots[i] = true
			return i
		end
	end
	return 1
end

local function spawnVehicle(session, v)
	local plot = plots[session.slot]
	local tier = TIERS[v.tier]
	v.spot = freeSpot(session)
	local r, f = spotRF(v.spot)
	local p = basePoint(plot, r, f)
	v.yaw = plot.yaw
	v.parkCF = CFrame.new(p.X, vehicleY(tier), p.Z) * CFrame.Angles(0, plot.yaw, 0)

	local body
	local tpl = getTemplate("Vehicle" .. v.tier)
	if tpl then
		local ok, res = pcall(buildModelVehicle, session.folder, tpl, tier, v.parkCF)
		if ok then
			body = res
		else
			warn("[Logistics] не удалось использовать модель Vehicle" .. v.tier .. ": " .. tostring(res))
		end
	end
	if not body then body = buildVehicle(session.folder, tier, v.parkCF) end
	v.body = body
end

local function travel(v, pts, speed, alive)
	for i = 1, #pts - 1 do
		if not alive() then return false end
		local a, b = pts[i], pts[i + 1]
		local dv = b - a
		local flat = Vector3.new(dv.X, 0, dv.Z)
		if flat.Magnitude > 0.05 then
			local dir = flat.Unit
			v.yaw = math.atan2(-dir.Z, dir.X)
		end
		local rot = CFrame.Angles(0, v.yaw, 0)
		local dist = dv.Magnitude
		if dist > 0.05 then
			v.body.CFrame = CFrame.new(a) * rot
			local t = dist / speed
			TweenService:Create(v.body, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.new(b) * rot }):Play()
			task.wait(t)
		end
	end
	return alive()
end

local function runVehicle(player, session, v)
	local plot = plots[session.slot]
	local function alive() return session.alive and not v.dead and player.Parent ~= nil end
	task.spawn(function()
		task.wait(0.4 + v.spot * 0.3)
		while alive() do
			local job = takeJob(session, v)
			if not job then
				task.wait(1)
			else
				task.wait(1.5) -- погрузка
				if not alive() then break end
				local pts = pathTo(plot, v, DESTS[job.dest])
				local speed = vehSpeed(session.data, v.tier)
				if not travel(v, pts, speed, alive) then break end
				deliverJob(session, v, job, pathLength(pts))
				v.job = nil
				task.wait(1.2) -- разгрузка
				if not alive() then break end
				if not travel(v, reversePath(pts), speed, alive) then break end
				v.body.CFrame = v.parkCF
				v.yaw = plot.yaw
			end
		end
	end)
end

local function addVehicle(player, session, tierIdx)
	session.nextVehId += 1
	local v = { id = session.nextVehId, tier = tierIdx, dead = false }
	table.insert(session.vehicles, v)
	spawnVehicle(session, v)
	runVehicle(player, session, v)
	return v
end

local function removeVehicle(session, v)
	v.dead = true
	returnJob(session, v)
	session.spots[v.spot] = nil
	if v.body then v.body:Destroy() end
	for i, x in ipairs(session.vehicles) do
		if x == v then
			table.remove(session.vehicles, i)
			break
		end
	end
end

local function findVehicle(session, id)
	for _, v in ipairs(session.vehicles) do
		if v.id == id then return v end
	end
	return nil
end

--------------------------------------------------------------------
-- НАГРАДА ДНЯ
--------------------------------------------------------------------
local function dailyStatus(d)
	local wait = (d.lastDaily + DAILY_COOLDOWN) - os.time()
	return wait <= 0, math.max(0, wait)
end
local function dailyNextStreak(d)
	if d.lastDaily == 0 or os.time() - d.lastDaily > 48 * 3600 then return 1 end
	return math.min(7, d.streak + 1)
end
local function dailyReward(session, streak)
	return math.floor(incomePerSec(session) * totalMult(session) * 120 * streak) + 500 * streak
end

--------------------------------------------------------------------
-- СОХРАНЕНИЕ
--------------------------------------------------------------------
local function savePlayer(player)
	local session = sessions[player]
	if not session then return end
	local d = session.data
	local fleet = {}
	for _, v in ipairs(session.vehicles) do table.insert(fleet, v.tier) end
	pcall(function()
		store:SetAsync("p_" .. player.UserId, {
			money = session.money.Value,
			delivered = session.delivered.Value,
			fleet = fleet,
			lv = d.lv,
			slots = d.slots,
			maxTier = d.maxTier,
			rebirths = d.rebirths,
			earned = d.earned,
			done = d.done,
			lastDaily = d.lastDaily,
			streak = d.streak,
			codes = d.codes,
			ips = incomePerSec(session) * (1 + REBIRTH_BONUS * d.rebirths),
			last = os.time(),
		})
	end)
end

--------------------------------------------------------------------
-- ИГРОКИ
--------------------------------------------------------------------
local function claimSlot()
	for i = 0, MAX_SLOTS - 1 do
		if not usedSlots[i] then
			usedSlots[i] = true
			return i
		end
	end
	return nil
end

local function onPlayerAdded(player)
	local slot = claimSlot()
	if not slot then
		player:Kick("Сервер заполнен (максимум " .. MAX_SLOTS .. " игроков). Попробуй другой сервер.")
		return
	end
	local plot = plots[slot]
	plot.sign.Text = "🏢 " .. player.DisplayName

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player
	local money = Instance.new("NumberValue"); money.Name = "Деньги"; money.Parent = ls
	local delivered = Instance.new("NumberValue"); delivered.Name = "Посылки"; delivered.Parent = ls
	local rbValue = Instance.new("IntValue"); rbValue.Name = "Перерождения"; rbValue.Parent = ls

	local data = {
		lv = { capacity = 1, speed = 1, price = 1, warehouse = 1 },
		slots = START_SLOTS, maxTier = 1, rebirths = 0, earned = 0, done = 0,
		lastDaily = 0, streak = 0, codes = {},
	}
	local fleet = { 1 }
	local notice = nil
	money.Value = START_MONEY

	local ok, saved = pcall(function() return store:GetAsync("p_" .. player.UserId) end)
	if ok and saved then
		money.Value = saved.money or START_MONEY
		delivered.Value = saved.delivered or 0
		for k, v in pairs(saved.lv or {}) do
			if data.lv[k] then data.lv[k] = v end
		end
		data.slots = math.clamp(saved.slots or START_SLOTS, START_SLOTS, MAX_VEHICLE_SLOTS)
		data.maxTier = math.clamp(saved.maxTier or 1, 1, #TIERS)
		data.rebirths = saved.rebirths or 0
		data.earned = saved.earned or 0
		data.done = saved.done or 0
		data.lastDaily = saved.lastDaily or 0
		data.streak = saved.streak or 0
		data.codes = saved.codes or {}
		if saved.fleet and #saved.fleet > 0 then
			fleet = {}
			for _, t in ipairs(saved.fleet) do
				if type(t) == "number" and t >= 1 and t <= #TIERS and #fleet < data.slots then
					table.insert(fleet, math.floor(t))
				end
			end
			if #fleet == 0 then fleet = { 1 } end
		end
		if saved.last and saved.ips then
			local away = math.clamp(os.time() - saved.last, 0, OFFLINE_MAX)
			local reward = math.floor(saved.ips * away * OFFLINE_RATE)
			if reward >= 10 then
				money.Value += reward
				data.earned += reward
				notice = { text = "💤 Пока тебя не было", amount = reward }
			end
		end
	end
	rbValue.Value = data.rebirths

	local session = {
		data = data, folder = plot.vfolder, slot = slot,
		money = money, delivered = delivered, rbValue = rbValue,
		alive = true, vehicles = {}, spots = {}, active = {}, offers = {},
		stock = stockCap(data) * 0.6, nextId = 0, nextVehId = 0,
		x2 = false, notice = notice, lastSend = 0, pending = false, tickN = 0,
	}
	sessions[player] = session

	if PASS_X2_ID > 0 then
		local okp, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, PASS_X2_ID)
		end)
		if okp and owns then session.x2 = true end
	end

	function session.sendState(force)
		if not session.alive then return end
		local now = os.clock()
		if not force and now - session.lastSend < 0.7 then
			if not session.pending then
				session.pending = true
				task.delay(0.75 - (now - session.lastSend), function()
					session.pending = false
					session.sendState(true)
				end)
			end
			return
		end
		session.lastSend = now

		local nowT = os.time()
		local vehicles = {}
		for _, v in ipairs(session.vehicles) do
			table.insert(vehicles, {
				id = v.id, tier = v.tier, name = TIERS[v.tier].name,
				cap = vehCap(data, v.tier), speed = math.floor(vehSpeed(data, v.tier)),
				busy = v.job ~= nil,
				up = (v.tier < #TIERS) and upgradeVehCost(v.tier) or -1,
				sell = sellValue(v.tier),
			})
		end
		local shop = {}
		for t = 1, #TIERS do
			table.insert(shop, {
				tier = t, name = TIERS[t].name, price = TIERS[t].price,
				cap = vehCap(data, t), speed = math.floor(vehSpeed(data, t)),
				unlocked = t <= data.maxTier + 1,
			})
		end
		local upgrades = {}
		for kind, uDef in pairs(UPGRADES) do
			upgrades[kind] = {
				lv = data.lv[kind], max = uDef.max,
				cost = data.lv[kind] >= uDef.max and -1 or upgradeCost(kind, data),
			}
		end
		local offers = {}
		for _, o in ipairs(session.offers) do
			local cg = CARGO[o.cargo]
			table.insert(offers, {
				id = o.id, destName = DESTS[o.dest].name, destIcon = DESTS[o.dest].icon,
				cargoName = cg.name, cargoIcon = cg.icon, qty = o.qty, reward = o.reward,
				limit = o.limit, expiresIn = math.max(0, o.expires - nowT),
				minTier = o.minTier, minTierName = TIERS[o.minTier].name,
				ok = hasTier(session, o.minTier),
			})
		end
		local active = {}
		for _, c in ipairs(session.active) do
			local cg = CARGO[c.cargo]
			table.insert(active, {
				id = c.id, destName = DESTS[c.dest].name, destIcon = DESTS[c.dest].icon,
				cargoName = cg.name, cargoIcon = cg.icon, qty = c.qty, delivered = c.delivered,
				inTransit = c.inTransit, reward = c.reward, left = math.max(0, c.deadline - nowT),
				limit = c.limit, minTierName = TIERS[c.minTier].name,
			})
		end

		local ready, wait = dailyStatus(data)
		local mult = totalMult(session)
		local rbCost = rebirthCost(data)
		local found = {}
		for _, n in ipairs({ "Vehicle1", "Vehicle2", "Vehicle3", "Vehicle4", "Vehicle5", "Vehicle6", "Warehouse" }) do
			if findObject(n) then table.insert(found, n) end
		end

		stateRemote:FireClient(player, {
			money = money.Value,
			ips = math.floor(incomePerSec(session) * mult),
			mult = math.floor(mult * 100) / 100,
			vehicles = vehicles, shop = shop, upgrades = upgrades,
			slots = { used = #session.vehicles, total = data.slots,
				cost = data.slots < MAX_VEHICLE_SLOTS and slotCost(data) or -1 },
			stock = { cur = math.floor(session.stock), cap = stockCap(data) },
			contracts = { offers = offers, active = active, done = data.done, maxActive = MAX_ACTIVE_CONTRACTS },
			rebirth = {
				count = data.rebirths, bonus = REBIRTH_BONUS * 100, cost = rbCost,
				needName = TIERS[#TIERS].name,
				ready = data.maxTier >= #TIERS and money.Value >= rbCost,
			},
			daily = { ready = ready, wait = wait, streak = data.streak,
				reward = dailyReward(session, dailyNextStreak(data)) },
			passId = PASS_X2_ID,
			x2 = session.x2,
			notice = session.notice,
			models = { found = found },
		})
		session.notice = nil
	end

	-- стартовый автопарк и предложения
	for _, t in ipairs(fleet) do addVehicle(player, session, t) end
	for _ = 1, 4 do table.insert(session.offers, genOffer(session)) end

	local function teleport(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if hrp and session.alive then
			task.wait(0.1)
			char:PivotTo(plot.spawnCF)
		end
	end
	player.CharacterAdded:Connect(teleport)
	if player.Character then task.spawn(teleport, player.Character) end

	task.wait(1)
	session.sendState(true)
end

--------------------------------------------------------------------
-- ДЕЙСТВИЯ ИГРОКА
--------------------------------------------------------------------
local function note(session, text)
	session.notice = { text = text }
end

upgradeRemote.OnServerEvent:Connect(function(player, kind, arg)
	local session = sessions[player]
	if not session or type(kind) ~= "string" then return end
	local d = session.data
	local money = session.money

	if kind == "buy" then
		local t = math.floor(tonumber(arg) or 0)
		if t < 1 or t > #TIERS then return end
		if t > d.maxTier + 1 then note(session, "🔒 Сначала купи более простой транспорт")
		elseif #session.vehicles >= d.slots then note(session, "🅿 Нет места в гараже — расширь гараж")
		elseif money.Value < TIERS[t].price then note(session, "💸 Не хватает денег")
		else
			money.Value -= TIERS[t].price
			d.maxTier = math.max(d.maxTier, t)
			addVehicle(player, session, t)
			note(session, "🚚 Куплен: " .. TIERS[t].name)
		end
		session.sendState(true)
		return
	end

	if kind == "sell" then
		local v = findVehicle(session, math.floor(tonumber(arg) or -1))
		if not v then return end
		money.Value += sellValue(v.tier)
		note(session, "💰 Продано: " .. TIERS[v.tier].name)
		removeVehicle(session, v)
		session.sendState(true)
		return
	end

	if kind == "upg_veh" then
		local v = findVehicle(session, math.floor(tonumber(arg) or -1))
		if not v or v.tier >= #TIERS then return end
		local cost = upgradeVehCost(v.tier)
		if money.Value < cost then
			note(session, "💸 Не хватает денег")
		else
			money.Value -= cost
			local newTier = v.tier + 1
			removeVehicle(session, v)
			d.maxTier = math.max(d.maxTier, newTier)
			addVehicle(player, session, newTier)
			note(session, "⬆ Улучшено до: " .. TIERS[newTier].name)
		end
		session.sendState(true)
		return
	end

	if kind == "slot" then
		if d.slots >= MAX_VEHICLE_SLOTS then return end
		local cost = slotCost(d)
		if money.Value < cost then
			note(session, "💸 Не хватает денег")
		else
			money.Value -= cost
			d.slots += 1
		end
		session.sendState(true)
		return
	end

	if kind == "upgrade" then
		if type(arg) ~= "string" or not UPGRADES[arg] then return end
		if d.lv[arg] >= UPGRADES[arg].max then return end
		local cost = upgradeCost(arg, d)
		if money.Value < cost then
			note(session, "💸 Не хватает денег")
		else
			money.Value -= cost
			d.lv[arg] += 1
		end
		session.sendState(true)
		return
	end

	if kind == "contract_accept" then
		local id = math.floor(tonumber(arg) or -1)
		local idx
		for i, o in ipairs(session.offers) do
			if o.id == id then idx = i end
		end
		if not idx then return end
		local o = session.offers[idx]
		if #session.active >= MAX_ACTIVE_CONTRACTS then
			note(session, "📋 Уже взято максимум контрактов (" .. MAX_ACTIVE_CONTRACTS .. ")")
		elseif not hasTier(session, o.minTier) then
			note(session, "🚫 Нужен транспорт: " .. TIERS[o.minTier].name .. " или лучше")
		else
			table.remove(session.offers, idx)
			table.insert(session.active, {
				id = o.id, dest = o.dest, cargo = o.cargo, qty = o.qty, reward = o.reward, limit = o.limit,
				minTier = o.minTier, deadline = os.time() + o.limit, delivered = 0, inTransit = 0,
			})
			note(session, "📋 Контракт принят!")
		end
		session.sendState(true)
		return
	end

	if kind == "contract_cancel" then
		local id = math.floor(tonumber(arg) or -1)
		if findActive(session, id) then
			removeActive(session, id)
			note(session, "❌ Контракт отменён")
			session.sendState(true)
		end
		return
	end

	if kind == "rebirth" then
		if d.maxTier < #TIERS or money.Value < rebirthCost(d) then return end
		for i = #session.vehicles, 1, -1 do removeVehicle(session, session.vehicles[i]) end
		d.rebirths += 1
		session.rbValue.Value = d.rebirths
		d.lv = { capacity = 1, speed = 1, price = 1, warehouse = 1 }
		d.slots = START_SLOTS
		d.maxTier = 1
		session.active = {}
		session.offers = {}
		money.Value = START_MONEY
		session.stock = stockCap(d) * 0.6
		addVehicle(player, session, 1)
		for _ = 1, 4 do table.insert(session.offers, genOffer(session)) end
		note(session, "♻ Перерождение #" .. d.rebirths .. "! Бонус дохода: x" .. (1 + REBIRTH_BONUS * d.rebirths))
		session.sendState(true)
		return
	end

	if kind == "daily" then
		local ready = dailyStatus(d)
		if not ready then return end
		local streak = dailyNextStreak(d)
		local reward = dailyReward(session, streak)
		money.Value += reward
		d.earned += reward
		d.lastDaily = os.time()
		d.streak = streak
		session.notice = { text = "🎁 Награда дня (серия " .. streak .. "/7)", amount = reward }
		session.sendState(true)
		return
	end

	if kind == "code" then
		if type(arg) ~= "string" then return end
		local code = string.upper((arg:gsub("%s", "")))
		local secs = CODES[code]
		if not secs then
			note(session, "❌ Неверный промокод")
		elseif d.codes[code] then
			note(session, "⚠ Этот код уже использован")
		else
			d.codes[code] = true
			local reward = math.max(1000, math.floor(incomePerSec(session) * totalMult(session) * secs))
			money.Value += reward
			d.earned += reward
			session.notice = { text = "✅ Промокод принят!", amount = reward }
		end
		session.sendState(true)
		return
	end
end)

readyRemote.OnServerEvent:Connect(function(p)
	local ses = sessions[p]
	if ses and ses.sendState then ses.sendState(true) end
	if currentEvent then
		local remaining = currentEvent.endsAt - os.time()
		if remaining > 0 then
			eventRemote:FireClient(p, { name = currentEvent.name, mult = currentEvent.mult, duration = remaining })
		end
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local ses = sessions[player]
	if ses and purchased and PASS_X2_ID > 0 and passId == PASS_X2_ID then
		ses.x2 = true
		ses.sendState(true)
	end
end)

--------------------------------------------------------------------
-- ФОНОВЫЕ ЦИКЛЫ
--------------------------------------------------------------------
local EVENTS = {
	{ name = "🔥 Час пик! Доход x2", mult = 2, duration = 60 },
	{ name = "🚀 Супер-доставка! Доход x3", mult = 3, duration = 30 },
}

task.spawn(function()
	while true do
		task.wait(math.random(EVENT_MIN, EVENT_MAX))
		local ev = EVENTS[math.random(#EVENTS)]
		currentEvent = { name = ev.name, mult = ev.mult, endsAt = os.time() + ev.duration }
		eventMult = ev.mult
		eventRemote:FireAllClients({ name = ev.name, mult = ev.mult, duration = ev.duration })
		task.wait(ev.duration)
		currentEvent = nil
		eventMult = 1
		eventRemote:FireAllClients({ ended = true })
	end
end)

-- раз в секунду: пополнение склада, предложения и сроки контрактов
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.time()
		for player, session in pairs(sessions) do
			if session.alive then
				session.tickN += 1
				local d = session.data
				local cap = stockCap(d)
				session.stock = math.min(cap, session.stock + cap / 40)

				for i = #session.offers, 1, -1 do
					if session.offers[i].expires <= now then table.remove(session.offers, i) end
				end
				for i = #session.active, 1, -1 do
					local c = session.active[i]
					if c.deadline <= now then
						table.remove(session.active, i)
						session.notice = { text = "⌛ Контракт просрочен: " .. DESTS[c.dest].name }
					end
				end
				if #session.offers < MAX_OFFERS and math.random() < 0.25 then
					table.insert(session.offers, genOffer(session))
				end
				plots[session.slot].stockLabel.Text = ("📦 СКЛАД  %d/%d"):format(math.floor(session.stock), cap)
				if session.tickN % 2 == 0 then session.sendState() end
			end
		end
	end
end)

local setLeaderboard
task.spawn(function()
	while true do
		task.wait(3)
		if setLeaderboard then
			local list = {}
			for p, ses in pairs(sessions) do
				table.insert(list, { name = p.DisplayName, earned = ses.data.earned, rb = ses.data.rebirths, done = ses.data.done })
			end
			table.sort(list, function(a, b) return a.earned > b.earned end)
			local lines = {}
			for i = 1, math.min(10, #list) do
				local e = list[i]
				lines[i] = ("%d. %s   ♻%d  ✅%d   $%s"):format(i, e.name, e.rb, e.done, fmtNum(e.earned))
			end
			setLeaderboard(lines)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(120)
		for p in pairs(sessions) do savePlayer(p) end
	end
end)

--------------------------------------------------------------------
-- ЗАПУСК: город, базы, табло по углам
--------------------------------------------------------------------
Lighting.ClockTime = 14
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate and baseplate:IsA("BasePart") then baseplate.Color = Color3.fromRGB(95, 160, 85) end

buildCity()
for i = 0, MAX_SLOTS - 1 do buildBase(i) end

do
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = workspace

	local sp = Instance.new("SpawnLocation")
	sp.Size = Vector3.new(10, 1, 10)
	sp.Position = Vector3.new(-330, 1, -330)
	sp.Anchored = true
	sp.Neutral = true
	sp.Transparency = 0.6
	sp.Duration = 0
	sp.Parent = hub

	setLeaderboard = makeBoard(hub, Vector3.new(330, 0, 330), 40, 24, "🏆 ЛУЧШИЕ ПЕРЕВОЗЧИКИ", 10, 52)
	local setInfo = makeBoard(hub, Vector3.new(-330, 0, 330), 40, 24, "📖 КАК ИГРАТЬ", 10, 52)
	setInfo({
		"1. Твоя база — это склад: товары копятся на нём",
		"2. Транспорт возит их по городу и приносит $",
		"3. Покупай машины по одной в 🚚 Гараже",
		"4. Бери выгодные поставки в 📋 Контрактах",
		"5. Мопед → Машина → Фургон → Грузовик → Фура → Самолёт",
		"6. Дошёл до самолёта? Делай ♻ Перерождение: +50% навсегда",
		"7. 🎁 Заходи каждый день за наградой",
		"8. Промокоды: WELCOME, LOGISTICS, PLANE",
	})
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player]
	if not session then return end
	session.alive = false
	savePlayer(player)
	session.folder:ClearAllChildren()
	plots[session.slot].sign.Text = "СВОБОДНО"
	plots[session.slot].stockLabel.Text = "📦 СКЛАД"
	usedSlots[session.slot] = nil
	sessions[player] = nil
end)
game:BindToClose(function()
	for p in pairs(sessions) do savePlayer(p) end
end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
