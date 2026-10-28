--====================================================================
--  LOGISTICS EMPIRE v5 — CLIENT
--  LocalScript -> StarterGui, имя "Client"
--  HUD + меню: 🚚 Гараж, 📋 Контракты, 🏭 Улучшения + туториал
--====================================================================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local upgradeRemote, stateRemote, readyRemote, eventRemote

local TIER_ICONS = { "🛵", "🚗", "🚐", "🚚", "🚛", "✈️" }

local BG = Color3.fromRGB(22, 26, 40)
local BG2 = Color3.fromRGB(34, 40, 62)
local GREEN = Color3.fromRGB(80, 215, 120)
local PURPLE = Color3.fromRGB(165, 90, 235)
local BLUE = Color3.fromRGB(70, 170, 255)
local GOLD = Color3.fromRGB(255, 190, 60)
local GRAY = Color3.fromRGB(70, 76, 98)
local DIM = Color3.fromRGB(175, 180, 200)
local WHITE = Color3.new(1, 1, 1)
local BUYGREEN = Color3.fromRGB(60, 190, 100)

local TUTORIAL = {
	{ "👋 Добро пожаловать!", "Ты владелец логистической компании. Город — в центре карты, а вокруг него 20 баз игроков. Твоя база — это твой склад и гараж." },
	{ "📦 Склад и доставка", "Товары копятся на складе. Транспорт сам возит их по городу в магазины, больницы и офисы — каждая доставка приносит деньги." },
	{ "🚚 Гараж", "Покупай транспорт по одной машине: от мопеда до самолёта. Каждую машину можно улучшить до следующего уровня или продать. Расширяй гараж, чтобы держать больше машин." },
	{ "📋 Контракты", "Контракты платят в 2–3 раза больше обычных рейсов. Бери до 3 контрактов — машины сами повезут груз. Успей до срока и получи бонус! Для редких грузов нужен транспорт получше." },
	{ "🏭 Улучшения", "Вместимость, скорость, тариф и размер склада усиливают весь автопарк сразу." },
	{ "♻ Перерождение", "Купил самолёт и накопил денег? Справа можно сделать перерождение: всё начнётся заново, но доход навсегда вырастет на 50%." },
	{ "🎁 Бонусы", "Забирай награду дня (серия до 7 дней), вводи промокоды и лови события: «Час пик» x2 и «Супер-доставка» x3. Лучшие игроки — на табло в углу карты." },
}

--------------------------------------------------------------------
-- ПОМОЩНИКИ
--------------------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(o, color, th)
	return new("UIStroke", { Color = color, Thickness = th or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function tween(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function fmt(n)
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while n >= 1000 and i < #units do
		n = n / 1000
		i += 1
	end
	if i == 1 then return tostring(math.floor(n)) end
	return tostring(math.floor(n * 100) / 100) .. units[i]
end
local function fmtTime(sec)
	sec = math.floor(sec)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	if h > 0 then return ("%dч %dм"):format(h, m) end
	return ("%d:%02d"):format(m, sec % 60)
end

local function pressable(b)
	local sc = new("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function() tween(sc, 0.1, { Scale = 1.04 }) end)
	b.MouseLeave:Connect(function() tween(sc, 0.1, { Scale = 1 }) end)
	b.MouseButton1Down:Connect(function() tween(sc, 0.06, { Scale = 0.95 }) end)
	b.MouseButton1Up:Connect(function() tween(sc, 0.1, { Scale = 1.04 }) end)
end

local function txt(parent, x, y, w, h, size, color, str, align)
	return new("TextLabel", {
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1,
		Text = str or "", TextColor3 = color or WHITE, Font = Enum.Font.GothamBold, TextSize = size,
		TextWrapped = true, TextXAlignment = align or Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	}, parent)
end

local function btn(parent, x, y, w, h, color, str, size)
	local b = new("TextButton", {
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = color,
		Text = str or "", TextColor3 = WHITE, Font = Enum.Font.GothamBlack, TextSize = size or 15,
		AutoButtonColor = false, TextWrapped = true,
	}, parent)
	corner(b, 10)
	pressable(b)
	return b
end

local function bar(parent, x, y, w, h, color)
	local bg = new("Frame", {
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Color3.fromRGB(15, 18, 28),
	}, parent)
	corner(bg, h / 2)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color }, bg)
	corner(fill, h / 2)
	return fill
end

local function setBtn(b, text, on, colorOn)
	b.Text = text
	b.BackgroundColor3 = on and colorOn or GRAY
end

-- список с повторным использованием строк (чтобы кнопки не «мигали»)
local function syncList(container, rows, items, keyOf, create, update)
	local seen = {}
	for i, item in ipairs(items) do
		local key = keyOf(item)
		seen[key] = true
		local row = rows[key]
		if not row then
			row = create(container)
			rows[key] = row
		end
		row.frame.LayoutOrder = i
		update(row, item)
	end
	for key, row in pairs(rows) do
		if not seen[key] then
			row.frame:Destroy()
			rows[key] = nil
		end
	end
end

local function makeScroll(parent, x, y, w, h)
	local s = new("ScrollingFrame", {
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	return s
end

--------------------------------------------------------------------
-- КОРНЕВОЙ UI (автоподгонка под экран, в т.ч. телефон)
--------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "LogisticsUI", ResetOnSpawn = false, DisplayOrder = 5 }, player:WaitForChild("PlayerGui"))
local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local uiScale = new("UIScale", { Scale = 1 }, root)

local cam = workspace.CurrentCamera
if not cam then
	workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
	cam = workspace.CurrentCamera
end
local function updateScale()
	local vp = cam.ViewportSize
	local s = math.clamp(math.min(vp.X / 1150, vp.Y / 680), 0.5, 1.2)
	uiScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end
updateScale()
cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

--------------------------------------------------------------------
-- ВСПЛЫВАЮЩИЕ ЭЛЕМЕНТЫ (выше всех окон)
--------------------------------------------------------------------
local function popup(text)
	local x = math.random(-60, 60)
	local l = new("TextLabel", {
		Size = UDim2.fromOffset(200, 30), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 92),
		BackgroundTransparency = 1, Text = text, TextColor3 = GREEN, Font = Enum.Font.GothamBlack, TextSize = 24,
		TextStrokeTransparency = 0.4, ZIndex = 20,
	}, root)
	tween(l, 1.1, { Position = UDim2.new(0.5, x, 0, 52), TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(1.2, function() l:Destroy() end)
end

local toast = new("TextLabel", {
	Size = UDim2.fromOffset(540, 64), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140),
	BackgroundColor3 = PURPLE, TextColor3 = WHITE, Font = Enum.Font.GothamBlack, TextSize = 21,
	TextWrapped = true, Visible = false, ZIndex = 30,
}, root)
corner(toast, 16)
local toastId = 0
local function showToast(text)
	toastId += 1
	local my = toastId
	toast.Text = text
	toast.BackgroundTransparency = 0
	toast.TextTransparency = 0
	toast.Visible = true
	task.delay(2.6, function()
		if my ~= toastId then return end
		tween(toast, 0.6, { BackgroundTransparency = 1, TextTransparency = 1 })
		task.wait(0.6)
		if my == toastId then toast.Visible = false end
	end)
end

--------------------------------------------------------------------
-- ВЕРХ: ДЕНЬГИ
--------------------------------------------------------------------
local moneyBar = new("Frame", {
	Size = UDim2.fromOffset(340, 74), AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12), BackgroundColor3 = BG,
}, root)
corner(moneyBar, 18)
stroke(moneyBar, GREEN, 2)
new("TextLabel", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(10, 9), BackgroundTransparency = 1, Text = "💵", TextSize = 40 }, moneyBar)
local moneyLbl = txt(moneyBar, 70, 6, 260, 40, 32, GREEN, "$0")
moneyLbl.Font = Enum.Font.GothamBlack
local ipsLbl = txt(moneyBar, 70, 46, 260, 20, 14, Color3.fromRGB(150, 200, 165), "+$0 / сек")

--------------------------------------------------------------------
-- ЛЕВО: КАРТОЧКА СКЛАДА + АКТИВНЫЕ КОНТРАКТЫ
--------------------------------------------------------------------
local compCard = new("Frame", { Size = UDim2.fromOffset(300, 122), Position = UDim2.fromOffset(16, 12), BackgroundColor3 = BG }, root)
corner(compCard, 18)
stroke(compCard, GOLD, 2)
txt(compCard, 12, 8, 276, 22, 17, WHITE, "🏭 Моя база-склад")
local stockLbl = txt(compCard, 12, 32, 276, 18, 13, DIM, "📦 Склад: 0/0")
local stockFill = bar(compCard, 12, 54, 276, 12, BLUE)
local fleetLbl = txt(compCard, 12, 74, 276, 18, 13, DIM, "🚚 Транспорт: 0/0 мест")
local doneLbl = txt(compCard, 12, 96, 276, 18, 13, DIM, "✅ Контрактов выполнено: 0")

local trackerFrame = new("Frame", { Position = UDim2.fromOffset(16, 144), Size = UDim2.fromOffset(300, 200), BackgroundTransparency = 1 }, root)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, trackerFrame)
local trackerTitle = new("TextLabel", {
	Size = UDim2.fromOffset(300, 20), BackgroundTransparency = 1, Text = "", TextColor3 = WHITE,
	Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0,
}, trackerFrame)

local trackerRows, activeRows, offerRows = {}, {}, {}

local function createTrackRow(parent)
	local f = new("Frame", { Size = UDim2.fromOffset(300, 50), BackgroundColor3 = BG }, parent)
	corner(f, 12)
	stroke(f, GREEN, 1)
	local title = txt(f, 10, 5, 280, 18, 13, WHITE)
	local fill = bar(f, 10, 30, 150, 10, GREEN)
	local info = txt(f, 166, 26, 60, 18, 12, DIM)
	local timer = txt(f, 226, 26, 68, 18, 12, GOLD, "", Enum.TextXAlignment.Right)
	return { frame = f, title = title, fill = fill, info = info, timer = timer }
end

--------------------------------------------------------------------
-- ПРАВАЯ КОЛОНКА: перерождение, награда дня, промокод, x2
--------------------------------------------------------------------
local rightCol = new("Frame", {
	Size = UDim2.fromOffset(240, 360), AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 12), BackgroundTransparency = 1,
}, root)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, rightCol)

local function sideCard(h, order, strokeColor)
	local f = new("Frame", { Size = UDim2.fromOffset(240, h), BackgroundColor3 = BG, LayoutOrder = order }, rightCol)
	corner(f, 16)
	stroke(f, strokeColor, 2)
	return f
end

local rbCard = sideCard(132, 1, GOLD)
txt(rbCard, 10, 8, 220, 22, 17, WHITE, "♻ Перерождение")
local rbInfo = txt(rbCard, 10, 32, 220, 46, 12, DIM)
local rbBtn = btn(rbCard, 10, 84, 220, 38, GRAY)
rbBtn.MouseButton1Click:Connect(function()
	if upgradeRemote then upgradeRemote:FireServer("rebirth") end
end)

local dailyCard = sideCard(98, 2, Color3.fromRGB(255, 110, 150))
txt(dailyCard, 10, 8, 220, 22, 17, WHITE, "🎁 Награда дня")
local dailyInfo = txt(dailyCard, 10, 30, 220, 18, 12, DIM)
local dailyBtn = btn(dailyCard, 10, 52, 220, 36, GRAY)
dailyBtn.MouseButton1Click:Connect(function()
	if upgradeRemote then upgradeRemote:FireServer("daily") end
end)

local codeCard = sideCard(50, 3, Color3.fromRGB(120, 130, 255))
local codeBox = new("TextBox", {
	Size = UDim2.fromOffset(160, 34), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = BG2, Text = "",
	PlaceholderText = "Промокод", PlaceholderColor3 = Color3.fromRGB(130, 135, 155), TextColor3 = WHITE,
	Font = Enum.Font.GothamBold, TextSize = 15, ClearTextOnFocus = false,
}, codeCard)
corner(codeBox, 8)
local codeBtn = btn(codeCard, 176, 8, 56, 34, Color3.fromRGB(90, 110, 255), "OK")
local function submitCode()
	if upgradeRemote and codeBox.Text ~= "" then
		upgradeRemote:FireServer("code", codeBox.Text)
		codeBox.Text = ""
	end
end
codeBtn.MouseButton1Click:Connect(submitCode)
codeBox.FocusLost:Connect(function(enter)
	if enter then submitCode() end
end)

local passBtn = new("TextButton", {
	Size = UDim2.fromOffset(240, 44), BackgroundColor3 = Color3.fromRGB(60, 150, 255), Text = "💎 Доход x2 — купить",
	TextColor3 = WHITE, Font = Enum.Font.GothamBlack, TextSize = 16, LayoutOrder = 4, Visible = false, AutoButtonColor = false,
}, rightCol)
corner(passBtn, 12)
pressable(passBtn)
local passId = 0
passBtn.MouseButton1Click:Connect(function()
	if passId > 0 then MarketplaceService:PromptGamePassPurchase(player, passId) end
end)

--------------------------------------------------------------------
-- ОКНА (Гараж, Контракты, Улучшения)
--------------------------------------------------------------------
local panels = {}
local function makePanel(name, title, w, h)
	local f = new("Frame", {
		Size = UDim2.fromOffset(w, h), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = BG, Visible = false, Active = true, ZIndex = 5,
	}, root)
	corner(f, 20)
	stroke(f, PURPLE, 3)
	local t = txt(f, 20, 12, w - 90, 36, 26, WHITE, title)
	t.Font = Enum.Font.GothamBlack
	local close = btn(f, w - 54, 10, 40, 40, Color3.fromRGB(200, 70, 80), "✕", 18)
	close.MouseButton1Click:Connect(function() f.Visible = false end)
	panels[name] = f
	return f
end
local function togglePanel(name)
	local target = panels[name]
	local show = not target.Visible
	for _, p in pairs(panels) do p.Visible = false end
	target.Visible = show
end

--------- ГАРАЖ ---------
local garage = makePanel("garage", "🚚 Гараж", 800, 500)
local garageSlotsLbl = txt(garage, 20, 56, 370, 22, 15, GOLD, "Мой транспорт")
txt(garage, 410, 56, 370, 22, 15, GOLD, "Магазин транспорта")
local vehList = makeScroll(garage, 16, 84, 376, 330)
local shopList = makeScroll(garage, 408, 84, 376, 330)
local slotBtn = btn(garage, 408, 430, 376, 46, GRAY, "", 16)
slotBtn.MouseButton1Click:Connect(function()
	if upgradeRemote then upgradeRemote:FireServer("slot") end
end)
txt(garage, 20, 436, 370, 40, 12, DIM, "Улучшение машины заменяет её на следующий уровень (платишь разницу с учётом 50% за старую). Продажа возвращает 50% цены.")

local vehRows, shopRows = {}, {}

local function createVehRow(parent)
	local f = new("Frame", { Size = UDim2.new(1, -10, 0, 66), BackgroundColor3 = BG2 }, parent)
	corner(f, 12)
	local icon = new("TextLabel", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 9), BackgroundTransparency = 1, TextSize = 34, Text = "" }, f)
	local name = txt(f, 62, 8, 150, 22, 15, WHITE)
	local stat = txt(f, 62, 32, 150, 28, 12, DIM)
	local up = btn(f, 214, 6, 148, 26, BUYGREEN, "", 13)
	local sell = btn(f, 214, 35, 148, 26, GRAY, "", 13)
	local row = { frame = f, icon = icon, name = name, stat = stat, up = up, sell = sell, id = 0 }
	up.MouseButton1Click:Connect(function() if upgradeRemote then upgradeRemote:FireServer("upg_veh", row.id) end end)
	sell.MouseButton1Click:Connect(function() if upgradeRemote then upgradeRemote:FireServer("sell", row.id) end end)
	return row
end

local function createShopRow(parent)
	local f = new("Frame", { Size = UDim2.new(1, -10, 0, 66), BackgroundColor3 = BG2 }, parent)
	corner(f, 12)
	local icon = new("TextLabel", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 9), BackgroundTransparency = 1, TextSize = 34, Text = "" }, f)
	local name = txt(f, 62, 8, 160, 22, 15, WHITE)
	local stat = txt(f, 62, 32, 160, 28, 12, DIM)
	local buy = btn(f, 228, 13, 134, 40, BUYGREEN, "", 15)
	local row = { frame = f, icon = icon, name = name, stat = stat, buy = buy, tier = 0 }
	buy.MouseButton1Click:Connect(function() if upgradeRemote then upgradeRemote:FireServer("buy", row.tier) end end)
	return row
end

--------- КОНТРАКТЫ ---------
local contracts = makePanel("contracts", "📋 Контракты на поставки", 840, 510)
local offersHeader = txt(contracts, 20, 56, 390, 22, 15, GOLD, "Предложения")
local activeHeader = txt(contracts, 430, 56, 390, 22, 15, GOLD, "Мои контракты")
local offerList = makeScroll(contracts, 16, 84, 396, 380)
local activeList = makeScroll(contracts, 428, 84, 396, 380)
txt(contracts, 20, 472, 800, 30, 12, DIM,
	"Контракт платит больше обычных рейсов, а за выполнение с запасом времени — ещё +25%. Машины сами берут груз со склада и везут его в город.")

local function createOfferRow(parent)
	local f = new("Frame", { Size = UDim2.new(1, -10, 0, 120), BackgroundColor3 = BG2 }, parent)
	corner(f, 12)
	local title = txt(f, 12, 8, 360, 22, 16, WHITE)
	local detail = txt(f, 12, 32, 366, 34, 12, DIM)
	local reward = txt(f, 12, 72, 190, 28, 22, GREEN)
	local exp = txt(f, 12, 100, 200, 14, 10, DIM)
	local acc = btn(f, 214, 72, 164, 40, BUYGREEN, "Принять", 15)
	local row = { frame = f, title = title, detail = detail, reward = reward, exp = exp, acc = acc, id = 0 }
	acc.MouseButton1Click:Connect(function() if upgradeRemote then upgradeRemote:FireServer("contract_accept", row.id) end end)
	return row
end

local function createActiveRow(parent)
	local f = new("Frame", { Size = UDim2.new(1, -10, 0, 112), BackgroundColor3 = BG2 }, parent)
	corner(f, 12)
	stroke(f, GREEN, 1)
	local title = txt(f, 12, 8, 360, 22, 16, WHITE)
	local detail = txt(f, 12, 32, 366, 18, 12, DIM)
	local fill = bar(f, 12, 56, 370, 12, GREEN)
	local info = txt(f, 12, 72, 190, 18, 13, WHITE)
	local timer = txt(f, 214, 72, 168, 18, 13, GOLD, "", Enum.TextXAlignment.Right)
	local reward = txt(f, 12, 90, 190, 18, 13, GREEN)
	local cancel = btn(f, 274, 86, 108, 22, Color3.fromRGB(150, 60, 70), "Отказаться", 11)
	local row = { frame = f, title = title, detail = detail, fill = fill, info = info, timer = timer, reward = reward, id = 0 }
	cancel.MouseButton1Click:Connect(function() if upgradeRemote then upgradeRemote:FireServer("contract_cancel", row.id) end end)
	return row
end

--------- УЛУЧШЕНИЯ ---------
local upgrades = makePanel("upgrades", "🏭 Улучшения компании", 600, 440)
local upgStockLbl = txt(upgrades, 20, 54, 560, 22, 14, DIM, "")
local UPG_DEFS = {
	{ id = "capacity",  icon = "📦", title = "Вместимость", hint = "+10% посылок за рейс у всех машин",  color = GREEN },
	{ id = "speed",     icon = "⚡", title = "Скорость",    hint = "+8% скорости всех машин",           color = BLUE },
	{ id = "price",     icon = "💰", title = "Тариф",       hint = "+10% к оплате за посылку",          color = GOLD },
	{ id = "warehouse", icon = "🏭", title = "Склад",       hint = "Запас ×1.5 и быстрее пополнение",  color = Color3.fromRGB(255, 150, 50) },
}
local upgCards = {}
for i, def in ipairs(UPG_DEFS) do
	local col = (i - 1) % 2
	local rowI = math.floor((i - 1) / 2)
	local card = new("Frame", {
		Size = UDim2.fromOffset(270, 160), Position = UDim2.fromOffset(20 + col * 290, 90 + rowI * 176), BackgroundColor3 = BG2,
	}, upgrades)
	corner(card, 16)
	stroke(card, def.color, 2)
	new("TextLabel", { Size = UDim2.fromOffset(50, 44), Position = UDim2.fromOffset(10, 8), BackgroundTransparency = 1, Text = def.icon, TextSize = 34 }, card)
	txt(card, 64, 10, 196, 22, 17, WHITE, def.title)
	txt(card, 64, 34, 196, 30, 11, DIM, def.hint)
	local lvl = txt(card, 12, 72, 246, 18, 13, def.color)
	local fill = bar(card, 12, 94, 246, 10, def.color)
	local b = btn(card, 12, 112, 246, 38, GRAY, "", 16)
	b.MouseButton1Click:Connect(function() if upgradeRemote then upgradeRemote:FireServer("upgrade", def.id) end end)
	upgCards[def.id] = { lvl = lvl, fill = fill, btn = b, color = def.color }
end

--------------------------------------------------------------------
-- НИЖНЯЯ ПАНЕЛЬ МЕНЮ
--------------------------------------------------------------------
local menuBar = new("Frame", {
	Size = UDim2.fromOffset(480, 56), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	BackgroundTransparency = 1,
}, root)
local garageBtn = btn(menuBar, 0, 0, 150, 56, Color3.fromRGB(60, 120, 220), "🚚 Гараж", 17)
local contractsBtn = btn(menuBar, 165, 0, 150, 56, Color3.fromRGB(60, 170, 110), "📋 Контракты", 17)
local upgradesBtn = btn(menuBar, 330, 0, 150, 56, Color3.fromRGB(220, 140, 50), "🏭 Улучшения", 17)
garageBtn.MouseButton1Click:Connect(function() togglePanel("garage") end)
contractsBtn.MouseButton1Click:Connect(function() togglePanel("contracts") end)
upgradesBtn.MouseButton1Click:Connect(function() togglePanel("upgrades") end)

local modelsLbl = new("TextLabel", {
	Size = UDim2.fromOffset(300, 34), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -14),
	BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(200, 205, 225), Font = Enum.Font.GothamMedium,
	TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
	TextStrokeTransparency = 0.6,
}, root)

--------------------------------------------------------------------
-- БАННЕР СОБЫТИЯ
--------------------------------------------------------------------
local eventBanner = new("TextLabel", {
	Size = UDim2.fromOffset(400, 36), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
	BackgroundColor3 = Color3.fromRGB(255, 120, 40), TextColor3 = WHITE, Font = Enum.Font.GothamBlack,
	TextSize = 17, Visible = false, ZIndex = 20,
}, root)
corner(eventBanner, 12)
local eventEnd, eventName = 0, ""
local function setEvent(info)
	if info.ended then
		eventEnd = 0
		eventBanner.Visible = false
		return
	end
	eventName = info.name
	eventEnd = os.clock() + info.duration
	eventBanner.Visible = true
	showToast(info.name)
end

--------------------------------------------------------------------
-- ТУТОРИАЛ
--------------------------------------------------------------------
local overlay = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
	Visible = false, Active = true, ZIndex = 50,
}, root)
local tCard = new("Frame", {
	Size = UDim2.fromOffset(480, 290), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = BG2,
}, overlay)
corner(tCard, 22)
stroke(tCard, PURPLE, 3)
local tTitle = txt(tCard, 20, 18, 440, 44, 27, WHITE)
tTitle.Font = Enum.Font.GothamBlack
local tText = txt(tCard, 25, 70, 430, 120, 16, Color3.fromRGB(210, 214, 230))
tText.Font = Enum.Font.GothamMedium
local tDots = txt(tCard, 0, 196, 480, 20, 16, PURPLE, "", Enum.TextXAlignment.Center)
local tNext = btn(tCard, 270, 290 - 64, 190, 46, PURPLE, "", 18)
local tSkip = new("TextButton", {
	Size = UDim2.fromOffset(120, 46), Position = UDim2.fromOffset(20, 290 - 64), BackgroundTransparency = 1,
	Text = "Пропустить", TextColor3 = Color3.fromRGB(150, 155, 175), Font = Enum.Font.GothamBold, TextSize = 15,
}, tCard)

local step = 1
local function renderStep()
	local s = TUTORIAL[step]
	tTitle.Text = s[1]
	tText.Text = s[2]
	local dots = {}
	for i = 1, #TUTORIAL do dots[i] = (i == step) and "●" or "○" end
	tDots.Text = table.concat(dots, " ")
	tNext.Text = (step == #TUTORIAL) and "Поехали! 🚀" or "Далее ▶"
end
local function openTutorial()
	step = 1
	renderStep()
	overlay.Visible = true
end
tNext.MouseButton1Click:Connect(function()
	if step >= #TUTORIAL then
		overlay.Visible = false
	else
		step += 1
		renderStep()
	end
end)
tSkip.MouseButton1Click:Connect(function() overlay.Visible = false end)

local help = new("TextButton", {
	Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -14),
	BackgroundColor3 = BG, Text = "❓", TextSize = 26, AutoButtonColor = false,
}, root)
corner(help, 26)
stroke(help, PURPLE, 2)
pressable(help)
help.MouseButton1Click:Connect(openTutorial)

--------------------------------------------------------------------
-- ТАЙМЕРЫ (обновляются локально между пакетами данных)
--------------------------------------------------------------------
local function leftOf(row) return math.max(0, row.left - (os.clock() - row.at)) end
task.spawn(function()
	while true do
		task.wait(0.5)
		if eventBanner.Visible then
			local left = eventEnd - os.clock()
			if left <= 0 then
				eventBanner.Visible = false
			else
				eventBanner.Text = ("%s — %d с"):format(eventName, math.ceil(left))
			end
		end
		for _, set in ipairs({ trackerRows, activeRows }) do
			for _, row in pairs(set) do
				if row.left then row.timer.Text = "⏱ " .. fmtTime(leftOf(row)) end
			end
		end
		for _, row in pairs(offerRows) do
			if row.left then row.exp.Text = "предложение истечёт через " .. fmtTime(leftOf(row)) end
		end
	end
end)

--------------------------------------------------------------------
-- ОБНОВЛЕНИЕ ДАННЫХ
--------------------------------------------------------------------
local lastMoney, tutorialShown = nil, false

local function updateGarage(s)
	garageSlotsLbl.Text = ("Мой транспорт (%d/%d мест)"):format(s.slots.used, s.slots.total)
	syncList(vehList, vehRows, s.vehicles, function(v) return v.id end, createVehRow, function(row, v)
		row.id = v.id
		row.icon.Text = TIER_ICONS[v.tier] or "🚚"
		row.name.Text = v.name .. (v.busy and "  • в рейсе" or "  • на базе")
		row.stat.Text = ("📦 %d за рейс   ⚡ %d"):format(v.cap, v.speed)
		if v.up >= 0 then
			setBtn(row.up, ("⬆ Улучшить  $%s"):format(fmt(v.up)), s.money >= v.up, BUYGREEN)
		else
			setBtn(row.up, "Макс. уровень", false, BUYGREEN)
		end
		setBtn(row.sell, ("Продать  +$%s"):format(fmt(v.sell)), true, Color3.fromRGB(190, 90, 70))
	end)
	syncList(shopList, shopRows, s.shop, function(t) return t.tier end, createShopRow, function(row, t)
		row.tier = t.tier
		row.icon.Text = TIER_ICONS[t.tier] or "🚚"
		row.name.Text = t.name
		row.stat.Text = ("📦 %d за рейс   ⚡ %d"):format(t.cap, t.speed)
		if t.unlocked then
			setBtn(row.buy, "Купить  $" .. fmt(t.price), s.money >= t.price and s.slots.used < s.slots.total, BUYGREEN)
		else
			setBtn(row.buy, "🔒 Закрыто", false, BUYGREEN)
		end
	end)
	if s.slots.cost >= 0 then
		setBtn(slotBtn, ("➕ Расширить гараж  $%s"):format(fmt(s.slots.cost)), s.money >= s.slots.cost, Color3.fromRGB(60, 120, 220))
	else
		setBtn(slotBtn, "Гараж расширен до максимума", false, GRAY)
	end
end

local function updateContracts(s)
	local c = s.contracts
	offersHeader.Text = ("Предложения (%d)"):format(#c.offers)
	activeHeader.Text = ("Мои контракты (%d/%d)"):format(#c.active, c.maxActive)
	local at = os.clock()

	syncList(offerList, offerRows, c.offers, function(o) return o.id end, createOfferRow, function(row, o)
		row.id = o.id
		row.left, row.at = o.expiresIn, at
		row.title.Text = ("%s %s  →  %s %s"):format(o.cargoIcon, o.cargoName, o.destIcon, o.destName)
		row.detail.Text = ("Количество: %d шт.   Срок: %s\nНужен транспорт: %s или лучше"):format(o.qty, fmtTime(o.limit), o.minTierName)
		row.reward.Text = "$" .. fmt(o.reward)
		if o.ok then
			setBtn(row.acc, "Принять", #c.active < c.maxActive, BUYGREEN)
		else
			setBtn(row.acc, "🚫 Нужен " .. o.minTierName, false, BUYGREEN)
		end
	end)

	syncList(activeList, activeRows, c.active, function(o) return o.id end, createActiveRow, function(row, o)
		row.id = o.id
		row.left, row.at = o.left, at
		row.title.Text = ("%s %s  →  %s %s"):format(o.cargoIcon, o.cargoName, o.destIcon, o.destName)
		row.detail.Text = ("Нужен транспорт: %s или лучше"):format(o.minTierName)
		tween(row.fill, 0.25, { Size = UDim2.fromScale(math.clamp(o.delivered / o.qty, 0, 1), 1) })
		row.info.Text = ("Доставлено %d/%d (в пути %d)"):format(o.delivered, o.qty, o.inTransit)
		row.reward.Text = "Награда: $" .. fmt(o.reward)
	end)

	-- мини-список на экране (до 3 контрактов)
	trackerTitle.Text = (#c.active > 0) and "📋 Активные контракты" or "📋 Нет активных контрактов — открой меню"
	syncList(trackerFrame, trackerRows, c.active, function(o) return o.id end, createTrackRow, function(row, o)
		row.left, row.at = o.left, at
		row.title.Text = ("%s %s %s"):format(o.cargoIcon, o.destIcon, o.destName)
		tween(row.fill, 0.25, { Size = UDim2.fromScale(math.clamp(o.delivered / o.qty, 0, 1), 1) })
		row.info.Text = ("%d/%d"):format(o.delivered, o.qty)
	end)
end

local function updateUpgrades(s)
	upgStockLbl.Text = ("📦 Склад сейчас: %d / %d     🚚 Транспорт: %d/%d мест"):format(s.stock.cur, s.stock.cap, s.slots.used, s.slots.total)
	for id, card in pairs(upgCards) do
		local u = s.upgrades[id]
		card.lvl.Text = ("Уровень %d / %d"):format(u.lv, u.max)
		tween(card.fill, 0.25, { Size = UDim2.fromScale(u.lv / u.max, 1) })
		if u.cost < 0 then
			setBtn(card.btn, "МАКС", false, card.color)
		else
			setBtn(card.btn, "Улучшить  $" .. fmt(u.cost), s.money >= u.cost, BUYGREEN)
		end
	end
end

local function onState(s)
	moneyLbl.Text = "$" .. fmt(s.money)
	ipsLbl.Text = "+$" .. fmt(s.ips) .. " / сек" .. (s.mult > 1 and ("  (x" .. s.mult .. ")") or "")

	stockLbl.Text = ("📦 Склад: %d / %d"):format(s.stock.cur, s.stock.cap)
	tween(stockFill, 0.3, { Size = UDim2.fromScale(math.clamp(s.stock.cur / math.max(1, s.stock.cap), 0, 1), 1) })
	fleetLbl.Text = ("🚚 Транспорт: %d/%d мест"):format(s.slots.used, s.slots.total)
	doneLbl.Text = ("✅ Контрактов выполнено: %d"):format(s.contracts.done)
	contractsBtn.Text = ("📋 Контракты (%d)"):format(#s.contracts.offers)

	updateGarage(s)
	updateContracts(s)
	updateUpgrades(s)

	-- перерождение
	local r = s.rebirth
	rbInfo.Text = ("Бонус сейчас: +%d%%  (перерождений: %d)\nНужно: %s в гараже и $%s"):format(
		math.floor(r.count * r.bonus), r.count, r.needName, fmt(r.cost))
	setBtn(rbBtn, r.ready and ("♻ Перерождение! (+%d%%)"):format(math.floor(r.bonus)) or "🔒 Пока недоступно", r.ready, GOLD)

	-- награда дня
	local dl = s.daily
	dailyInfo.Text = ("Серия: %d/7 дней"):format(dl.streak)
	if dl.ready then
		setBtn(dailyBtn, "Забрать $" .. fmt(dl.reward), true, BUYGREEN)
	else
		setBtn(dailyBtn, "Через " .. fmtTime(dl.wait), false, BUYGREEN)
	end

	passId = s.passId or 0
	passBtn.Visible = passId > 0 and not s.x2

	-- свои модели
	local found = s.models and s.models.found or {}
	modelsLbl.Text = (#found == 0) and "🧩 Свои модели (необязательно): не найдены"
		or ("🧩 Найдены свои модели: " .. table.concat(found, ", "))

	if lastMoney and s.money > lastMoney and not s.notice then popup("+$" .. fmt(s.money - lastMoney)) end
	lastMoney = s.money

	if s.notice then
		local t = s.notice.text
		if s.notice.amount then t = t .. ": +$" .. fmt(s.notice.amount) end
		showToast(t)
	end

	if not tutorialShown then
		tutorialShown = true
		openTutorial()
	end
end

--------------------------------------------------------------------
-- ПОДКЛЮЧЕНИЕ К СЕРВЕРУ
--------------------------------------------------------------------
moneyLbl.Text = "..."
ipsLbl.Text = "Подключение к серверу..."
upgradeRemote = RS:WaitForChild("Upgrade", 10)
stateRemote = RS:WaitForChild("State", 10)
readyRemote = RS:WaitForChild("Ready", 10)
eventRemote = RS:WaitForChild("Event", 10)
if not (upgradeRemote and stateRemote and readyRemote and eventRemote) then
	moneyLbl.Text = "Сервер не запущен!"
	ipsLbl.Text = "Скрипт Server должен быть Script в ServerScriptService"
	return
end
stateRemote.OnClientEvent:Connect(onState)
eventRemote.OnClientEvent:Connect(setEvent)
readyRemote:FireServer()
