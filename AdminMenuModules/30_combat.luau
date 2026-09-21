--=========================== ПРЕДУПРЕЖДЕНИЕ О КИЛЛЕРЕ ===========================

--[[
	Баннер по центру сверху: дистанция до ближайшего киллера и его стамина.
	Смысл цвета описан у таблицы WARNING; здесь - как он считается.

	Тренд берётся по РАЗНИЦЕ значений между опросами, делённой на реально
	прошедшее время. Просто «стало больше/меньше» не годится: StaminaServer
	реплицируется рывками, и на одном кадре разница нулевая даже когда
	киллер бежит.

	Всё завёрнуто в do-блок: наружу нужны только updateWarning и
	refreshWarningVisibility (лимит в 200 локалов на верхнем уровне уже
	однажды был превышен).
]]
local updateWarning, refreshWarningVisibility

do
	local warningGui = new("ScreenGui", {
		Name = "AdminKillerWarning",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 96, -- выше списка игроков, ниже меню
		Parent = playerGui,
	})

	local frame = new("Frame", {
		Name = "Warning",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, WARNING.OffsetY),
		Size = UDim2.fromOffset(WARNING.Width, WARNING.Height),
		BackgroundColor3 = COLORS.Background,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Visible = false,
		Parent = warningGui,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })

	-- Обводка тем же цветом, что и текст: цветную рамку видно краем глаза,
	-- не отрывая взгляд от игры. Ссылку держим, чтобы перекрашивать.
	local stroke = new("UIStroke", {
		Color = WARNING.SafeColor,
		Thickness = 2,
		Parent = frame,
	})

	local titleLabel = new("TextLabel", {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextSize = 14,
		TextColor3 = WARNING.SafeColor,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})

	local detailLabel = new("TextLabel", {
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 25),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 12,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})

	-- [модель киллера] = { value, time }. Слабые ключи: модели пересоздаются
	-- каждый раунд, иначе таблица держала бы мёртвые персонажи.
	local staminaHistory = setmetatable({}, { __mode = "k" })

	local accumulator = 0

	--[[
		Ближайший киллер + его стамина. Отдельно от nearestKillerDistance
		(та обслуживает зоны и возвращает только число): здесь нужна ещё и
		модель, чтобы вести историю стамины по конкретному киллеру.
	]]
	local function nearestKiller(origin)
		local bestChar, bestDistance, bestName = nil, nil, nil
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local char = other.Character
				local root = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
				if root and teamNameOf(other, char) == KILLER_TEAM then
					local humanoidOther = char:FindFirstChildOfClass("Humanoid")
					-- Мёртвый киллер не угроза, а в этом плейсе он бывает мёртв
					if not (humanoidOther and humanoidOther.Health <= 0) then
						local d = (root.Position - origin).Magnitude
						if not bestDistance or d < bestDistance then
							bestChar, bestDistance = char, d
							bestName = other.DisplayName ~= "" and other.DisplayName or other.Name
						end
					end
				end
			end
		end
		return bestChar, bestDistance, bestName
	end

	function refreshWarningVisibility()
		if not (state.warning and not selfIsKiller) then
			frame.Visible = false
		end
	end

	function updateWarning(delta)
		accumulator += delta
		if accumulator < WARNING.Interval then
			return
		end
		local elapsed = accumulator
		accumulator = 0

		-- У киллера баннер выключен на весь раунд: показывать ему «киллер
		-- рядом» бессмысленно, а блока у него нет вообще.
		if not state.warning or selfIsKiller then
			frame.Visible = false
			return
		end

		local origin = nil
		if rootPart and rootPart.Parent then
			origin = rootPart.Position
		else
			local camera = getCamera()
			origin = camera and camera.CFrame.Position or nil
		end
		if not origin then
			frame.Visible = false
			return
		end

		local killerChar, distance, killerName = nearestKiller(origin)
		if not killerChar or distance > WARNING.Distance then
			frame.Visible = false
			return
		end

		local current = readNumberAttribute(killerChar, STAMINA_KEYS)

		--[[
			Тренд. Три исхода:
			  падает   -> красный (тратит стамину: догоняет или атакует);
			  растёт   -> зелёный (восстанавливается, значит не бежит);
			  ровно    -> зелёный (по просьбе пользователя - как «растёт»).
			Первый замер тоже зелёный: одной точки для производной не хватает,
			а красный по умолчанию пугал бы на пустом месте.
		]]
		local falling = false
		local trendText = "стамина: —"
		if current then
			local previous = staminaHistory[killerChar]
			if previous and elapsed > 0 then
				local rate = (current - previous.value) / elapsed
				if rate < -WARNING.Epsilon then
					falling = true
					trendText = string.format("стамина %d ↓ тратит", math.floor(current + 0.5))
				elseif rate > WARNING.Epsilon then
					trendText = string.format("стамина %d ↑ отдыхает", math.floor(current + 0.5))
				else
					trendText = string.format("стамина %d — ровно", math.floor(current + 0.5))
				end
			else
				trendText = string.format("стамина %d", math.floor(current + 0.5))
			end
			staminaHistory[killerChar] = { value = current, time = os.clock() }
		end

		local color = falling and WARNING.DangerColor or WARNING.SafeColor

		titleLabel.Text = string.format("⚠ КИЛЛЕР %dm", math.floor(distance + 0.5))
		titleLabel.TextColor3 = color
		stroke.Color = color
		detailLabel.Text = (killerName and (killerName .. "  ·  ") or "") .. trendText
		detailLabel.TextColor3 = color
		frame.Visible = true
	end
end

local function listValueText(info)
	if info.dead then
		return "мёртв"
	end
	local parts = {}
	if LIST.Distance then
		table.insert(parts, info.distance and string.format("%dm", math.floor(info.distance + 0.5)) or "-")
	end
	if LIST.Stamina then
		table.insert(parts, info.stamina or "-")
	end
	return table.concat(parts, "  ")
end

local function listLegendText()
	local parts = {}
	if LIST.Distance then
		table.insert(parts, "дальн.")
	end
	if LIST.Stamina then
		table.insert(parts, "стамина")
	end
	return table.concat(parts, " · ")
end

local function updateList()
	-- Дальность считается от своего персонажа. Если его нет (наблюдение,
	-- смерть) - от камеры, иначе колонка молча схлопнулась бы в прочерки.
	local origin = nil
	if rootPart and rootPart.Parent then
		origin = rootPart.Position
	else
		local camera = getCamera()
		origin = camera and camera.CFrame.Position or nil
	end

	local groups, teamNames = {}, {}
	local total = 0
	local sampleCharacter = nil
	local staminaKey = nil

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player or LIST.ShowSelf then
			local char = other.Character
			local otherRoot = char and char:FindFirstChild("HumanoidRootPart")
			local otherHumanoid = char and char:FindFirstChildOfClass("Humanoid")
			if char and not sampleCharacter then
				sampleCharacter = char
			end

			local stamina, foundKey = staminaTextOf(char)
			if foundKey then
				staminaKey = foundKey
			end

			local teamName = teamNameOf(other, char)
			local group = groups[teamName]
			if not group then
				group = {}
				groups[teamName] = group
				table.insert(teamNames, teamName)
			end

			table.insert(group, {
				label = other.DisplayName ~= other.Name and (other.DisplayName .. " (@" .. other.Name .. ")") or other.Name,
				sortKey = string.lower(other.Name),
				distance = (otherRoot and origin) and (otherRoot.Position - origin).Magnitude or nil,
				stamina = stamina,
				dead = otherHumanoid ~= nil and otherHumanoid.Health <= 0,
			})
			total += 1
		end
	end

	table.sort(teamNames, function(a, b)
		local rankA, rankB = teamRank(a), teamRank(b)
		if rankA ~= rankB then
			return rankA < rankB
		end
		return a < b
	end)

	for _, teamName in ipairs(teamNames) do
		table.sort(groups[teamName], function(a, b)
			if LIST.SortByDistance and a.distance ~= b.distance then
				-- те, у кого дальность неизвестна, уходят в конец группы
				if a.distance == nil then
					return false
				end
				if b.distance == nil then
					return true
				end
				return a.distance < b.distance
			end
			return a.sortKey < b.sortKey
		end)
	end

	listTitleName.Text = "ИГРОКИ  " .. total
	listTitleLegend.Text = listLegendText()

	local rowIndex = 0
	local hidden = 0

	for _, teamName in ipairs(teamNames) do
		local group = groups[teamName]
		local color = teamColor(teamName)
		rowIndex += 1
		writeTeamHeader(rowIndex, teamName, #group, color)
		for _, info in ipairs(group) do
			-- MaxRows - мягкий предел: заголовки команд считаются, но не
			-- отбрасываются, иначе группа осталась бы без подписи.
			if rowIndex >= LIST.MaxRows then
				hidden += 1
			else
				rowIndex += 1
				writePlayerRow(rowIndex, info.label, listValueText(info), info.dead and COLORS.Muted or color)
			end
		end
	end

	if hidden > 0 then
		rowIndex += 1
		writeNoteRow(rowIndex, "+" .. hidden .. " ещё")
	end

	if rowIndex == 0 then
		rowIndex += 1
		writeNoteRow(rowIndex, "других игроков нет")
	end

	for index = rowIndex + 1, #listRows do
		listRows[index].frame.Visible = false
	end

	-- Диагностика один раз. Если атрибут не нашёлся, печатается ПОЛНЫЙ список
	-- атрибутов персонажа: без него остаётся только гадать, как сборка плейса
	-- назвала стамину.
	if staminaKey and not staminaKeyReported then
		staminaKeyReported = true
		print("[AdminMenu] стамина читается из атрибута персонажа: " .. staminaKey)
	elseif not staminaKey and sampleCharacter and not staminaMissReported then
		staminaMissReported = true

		local available = {}
		local okAttributes = pcall(function()
			for name, value in pairs(sampleCharacter:GetAttributes()) do
				table.insert(available, name .. "=" .. tostring(value))
			end
		end)
		table.sort(available)

		warn(string.format(
			"[AdminMenu] атрибут со стаминой не найден (пробовал: %s). "
				.. "Атрибуты персонажа %s: %s. "
				.. "Впиши подходящее имя в STAMINA_KEYS в начале скрипта.",
			table.concat(STAMINA_KEYS, ", "),
			sampleCharacter.Name,
			(okAttributes and #available > 0) and table.concat(available, ", ") or "не читаются"
		))
	end
end

local function applyList(enabled)
	listFrame.Visible = enabled
	if enabled then
		updateList() -- иначе панель до 0.1 с висит пустой
	end
end

--=========================== АВТОБЛОК ===========================

--[[
	Ставит блок, когда киллер рядом начинает атаку.

	Телеграф - атрибут UsingAbility = true на модели киллера. Проверено
	живым логом: он приходит за 280 мс до урона при обычном M1 и за 570 мс
	при спецприёме с раскидыванием. Ждать хитбокс бессмысленно: он
	появляется в тот же кадр, что и урон.

	Нажатие эмулируется через VirtualInputManager:SendKeyEvent. Это
	защищённый сервис: у обычного LocalScript прав на него нет, поэтому
	первый же неудачный вызов гасит тумблер и пишет причину в консоль (F9)
	и в строку статуса меню.
]]

local VirtualInputManager = nil
do
	local ok, service = pcall(function()
		return game:GetService("VirtualInputManager")
	end)
	if ok then
		VirtualInputManager = service
	end
end

-- Даже чтение члена защищённого сервиса может бросить ошибку, поэтому
-- проверка под pcall, а не просто через type(...).
local autoblockInputAvailable = false
if VirtualInputManager then
	local okMember, member = pcall(function()
		return VirtualInputManager.SendKeyEvent
	end)
	autoblockInputAvailable = okMember and type(member) == "function"
end

local autoblockInputBlocked = false -- вызов был, но прав не хватило

-- Печатается один раз при запуске, как и отчёт по файловому API: иначе
-- серый тумблер выглядит поломкой скрипта без объяснения причины.
if not autoblockInputAvailable then
	warn(
		"[AdminMenu] автоблок недоступен: VirtualInputManager:SendKeyEvent не читается. "
			.. "Этот сервис защищённый, обычному LocalScript его не дают - нужен executor. "
			.. "Остальные функции меню работают как обычно."
	)
end

local blockSlot = nil -- номер слота 1..N, если блок выдан в этом раунде
local blockKey = nil -- какую клавишу жать
local blockKeySource = nil -- "gui" (текст кнопки) или "slot" (таблица SLOT_KEYS)
local blockButton = nil -- ImageButton блока в RoundUI, из него читается кулдаун
local autoblockLastPress = 0 -- os.clock() последнего нажатия
-- Слабые ключи: модели киллеров меняются каждый раунд, иначе таблица
-- держала бы удалённые персонажи от сборки мусора.
local autoblockTriggered = setmetatable({}, { __mode = "k" }) -- [модель] = os.clock() реакции
local autoblockStatusLabel = nil -- создаётся ниже, при сборке меню
local autoblockMetricsLabel = nil -- вторая строка: замеры по хитбоксам
local autoblockScanAccumulator = 0

--[[
	Клавиша блока запросто совпадает с биндом меню: по умолчанию ESP сидит
	на E, а список игроков на T - обе есть в SLOT_KEYS. Эмулированное
	нажатие приходит в наш же InputBegan, и без этой отметки автоблок
	переключал бы чужой тумблер на каждой атаке.

	Отметка узкая - пара кадров: она обязана съесть только своё нажатие,
	а не настоящее, сделанное игроком сразу после.
]]
local syntheticKey = nil
local syntheticUntil = 0

local function isSyntheticPress(keyCode)
	return syntheticKey ~= nil and keyCode == syntheticKey and os.clock() < syntheticUntil
end

-- Сколько по замерам длится перезарядка блока. Нужна только для текста
-- статуса: реального атрибута кулдауна плейс клиенту не отдаёт.
local BLOCK_COOLDOWN = 35

--=========================== ЗОНЫ АВТОБЛОКА ===========================

--[[
	Видимые зоны срабатывания. Пользователь: «убийца бьёт за 9999 стадов и
	блок просирается» - без картинки невозможно понять, где на самом деле
	граница, поэтому она рисуется.

	CylinderHandleAdornment, а не Part: адорнменты не участвуют в физике,
	не имеют коллизий и рисуются поверх геометрии. Родитель - тот же
	tracerGui? Нет: адорнменты нельзя парентить в ScreenGui, они живут
	в самом персонаже (Adornee = HumanoidRootPart) и уезжают вместе с ним.
]]
local zoneParts = nil -- { melee = CylinderHandleAdornment, ranged = ... }

local function destroyZones()
	if not zoneParts then
		return
	end
	for _, adornment in pairs(zoneParts) do
		adornment:Destroy()
	end
	zoneParts = nil
end

local function ensureZones()
	if not rootPart then
		destroyZones()
		return nil
	end

	-- Персонаж мог сменился: старые адорнменты висят на удалённом руте
	if zoneParts and zoneParts.melee.Adornee ~= rootPart then
		destroyZones()
	end

	if zoneParts then
		return zoneParts
	end

	local function makeDisk(color, transparency, order)
		local adornment = Instance.new("CylinderHandleAdornment")
		adornment.Name = "AutoblockZone"
		adornment.Adornee = rootPart
		--[[
			AlwaysOnTop обязателен. Диск лежит на уровне пола, и без него
			он либо утонет в геометрии, либо начнёт мерцать от z-fighting -
			то есть зону как раз и не будет видно.
		]]
		adornment.AlwaysOnTop = true
		adornment.ZIndex = order
		adornment.Height = ZONE.Height
		adornment.Color3 = color
		adornment.Transparency = transparency
		-- Цилиндр рисуется вдоль своей оси Z, поэтому кладём его набок,
		-- чтобы получился плоский диск под ногами. fromEulerAnglesXYZ, а не
		-- CFrame.Angles: второе - легаси-псевдоним, лучше не полагаться.
		adornment.CFrame = CFrame.new(0, ZONE.Offset, 0) * CFrame.fromEulerAnglesXYZ(math.rad(90), 0, 0)
		adornment.Parent = rootPart
		return adornment
	end

	zoneParts = {
		melee = makeDisk(ZONE.MeleeColor, ZONE.MeleeTransparency, 1),
		ranged = makeDisk(ZONE.RangedColor, ZONE.RangedTransparency, 0),
	}
	return zoneParts
end

--[[
	Дистанция до ближайшего киллера. Нужна зоне для подкраски: когда он
	внутри, диск краснеет, и сразу видно, что автоблок сейчас взведён.
	Именно этого не хватало, чтобы понять, почему блок срабатывает не тогда,
	когда ожидаешь.
]]
local function nearestKillerDistance()
	if not rootPart then
		return nil
	end
	local closest = nil
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local char = other.Character
			local otherRoot = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
			if otherRoot and teamNameOf(other, char) == KILLER_TEAM then
				local d = (otherRoot.Position - rootPart.Position).Magnitude
				if not closest or d < closest then
					closest = d
				end
			end
		end
	end
	return closest
end

local function updateZones()
	-- selfIsKiller: у киллера автоблок отключён на раунд, зоны без него
	-- показывали бы границу, которая ни на что не влияет
	if not (AUTOBLOCK.ShowZone and state.autoblock) or selfIsKiller then
		destroyZones()
		return
	end

	local zones = ensureZones()
	if not zones then
		return
	end

	local nearest = nearestKillerDistance()

	zones.melee.Radius = AUTOBLOCK.Reach
	zones.melee.Visible = true
	-- Красный = киллер в зоне ближнего боя, на его замах отреагируем
	local inMelee = nearest ~= nil and nearest <= AUTOBLOCK.Reach
	zones.melee.Color3 = inMelee and ZONE.HitboxColor or ZONE.MeleeColor
	zones.melee.Transparency = inMelee and ZONE.AlertTransparency or ZONE.MeleeTransparency

	-- Дальний диск показывается только когда режим включён И реально
	-- больше ближнего: иначе он был бы просто вторым контуром на том же месте
	local showRanged = AUTOBLOCK.Ranged and AUTOBLOCK.Radius > AUTOBLOCK.Reach
	zones.ranged.Radius = math.max(AUTOBLOCK.Radius, AUTOBLOCK.Reach + 0.1)
	zones.ranged.Visible = showRanged
end

--=========================== ХИТБОКСЫ ===========================

--[[
	Постоянная проверка хитбоксов.

	Зачем, если как триггер они бесполезны (появляются в кадр урона):
	  1. измеряют РЕАЛЬНУЮ дистанцию удара - по ней подгоняется Reach,
	     вместо угаданных 14 студов;
	  2. показывают, накрыл ли блок настоящую атаку или сгорел впустую -
	     это то, на что пользователь и жалуется;
	  3. подсвечивают зону удара, когда она реально появилась.

	Слушаем workspace.DescendantAdded, а не сканируем дерево: сканирование
	каждый кадр по всему workspace - это тысячи объектов, а появление
	хитбокса и так событие.
]]
local hitboxStats = {
	hits = 0, -- хитбоксов, накрывших нас
	blocked = 0, -- из них пришедших, пока блок стоял
	wasted = 0, -- нажатий, после которых хитбокс так и не пришёл
	lastDistance = nil, -- дистанция последнего попадания
	maxDistance = nil, -- худший случай за сессию
}

local hitboxSamples = {} -- последние дистанции попаданий, для автоподгонки
local pendingPress = nil -- { time, expires } - ждём подтверждения хитбоксом
local hitboxFlashes = {} -- [adornment] = когда убрать
local hitboxConnection = nil

local function isHitboxName(name)
	return type(name) == "string" and string.find(string.lower(name), HITBOX.NamePart, 1, true) ~= nil
end

-- Медиана, а не среднее: один удар с рывка не должен задирать зону.
local function medianOf(values)
	local sorted = table.clone(values)
	table.sort(sorted)
	local count = #sorted
	if count == 0 then
		return nil
	end
	if count % 2 == 1 then
		return sorted[(count + 1) // 2]
	end
	return (sorted[count // 2] + sorted[count // 2 + 1]) / 2
end

--[[
	Подгонка зоны ближнего боя по факту.

	Берётся медиана последних попаданий плюс запас. Это честнее любых
	угаданных чисел: у каждого вида киллера свой вылет удара, а замерен
	был только Harken.
]]
--[[
	Ставится после сборки меню. Нужен потому, что подгонка меняет
	AUTOBLOCK.Reach за спиной у интерфейса: без этого степпер "Ближний бой"
	показывал бы старое число до следующего клика, и было бы не понять,
	подстроилась зона или нет.
]]
local onReachTuned = nil

local function autoTuneReach()
	if not AUTOBLOCK.AutoTune or #hitboxSamples < HITBOX.MinSamples then
		return
	end

	local median = medianOf(hitboxSamples)
	if not median then
		return
	end

	local target = math.clamp(
		math.ceil(median + HITBOX.TuneMargin),
		AUTOBLOCK.ReachMin,
		AUTOBLOCK.ReachMax
	)

	-- Шаг за раз: резкие прыжки зоны выглядят как баг и мешают понять,
	-- на что автоблок реагирует.
	local before = AUTOBLOCK.Reach
	if target > AUTOBLOCK.Reach then
		AUTOBLOCK.Reach = math.min(AUTOBLOCK.Reach + AUTOBLOCK.ReachStep, target)
	elseif target < AUTOBLOCK.Reach then
		AUTOBLOCK.Reach = math.max(AUTOBLOCK.Reach - AUTOBLOCK.ReachStep, target)
	end

	if AUTOBLOCK.Reach == before then
		return
	end

	--[[
		Подстроенную зону помечаем как несохранённое изменение. Автозаписи
		больше нет (сохранение по кнопке), поэтому подгонка сама файл не
		пишет - но кнопка сохранения загорается, и видно, что значение
		изменилось.
	]]
	markDirty()
	if onReachTuned then
		onReachTuned()
	end
end

local function flashHitbox(part)
	if not (HITBOX.ShowHits and state.autoblock) then
		return
	end

	local ok, adornment = pcall(function()
		local box = Instance.new("SelectionBox")
		box.Name = "AutoblockHitbox"
		box.Adornee = part
		box.Color3 = ZONE.HitboxColor
		box.LineThickness = 0.05
		box.SurfaceTransparency = 0.85
		box.SurfaceColor3 = ZONE.HitboxColor
		-- Парентится в сам хитбокс: он живёт ~1 с и уносит подсветку с
		-- собой, даже если наш таймер до неё не дойдёт.
		box.Parent = part
		return box
	end)
	if ok and adornment then
		hitboxFlashes[adornment] = os.clock() + HITBOX.FlashTime
	end
end

local function clearHitboxFlashes(force)
	local now = os.clock()
	for adornment, expires in pairs(hitboxFlashes) do
		if force or now >= expires or not adornment.Parent then
			adornment:Destroy()
			hitboxFlashes[adornment] = nil
		end
	end
end

-- Расстояние от нас до ближней точки хитбокса. От ближней, а не от центра:
-- зона удара крупная (в логе 5x7x7), от центра вышло бы завышение на
-- несколько студов, и подгонка зоны поехала бы вверх.
local function hitboxDistanceToMe(part)
	if not rootPart then
		return nil
	end
	local ok, distance = pcall(function()
		local localPoint = part.CFrame:PointToObjectSpace(rootPart.Position)
		local half = part.Size / 2
		local clamped = Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		)
		return (localPoint - clamped).Magnitude
	end)
	if not ok then
		return nil
	end
	return distance
end

local registerHitboxHit -- объявлена заранее: measureHitbox её вызывает

--[[
	Замер хитбокса.

	Ловушка: DescendantAdded срабатывает на момент присваивания Parent, а
	CFrame и Size объект нередко получает СТРОЧКОЙ ПОЗЖЕ. Тогда первый замер
	видит деталь в нуле координат и решает, что удар не по нам.
	Поэтому промах перепроверяется один раз на следующем кадре - к тому
	моменту зона уже расставлена.
]]
local function measureHitbox(part, allowRetry)
	if not (state.autoblock and rootPart and part.Parent) then
		return
	end

	local distance = hitboxDistanceToMe(part)
	if not distance then
		return
	end

	if distance > HITBOX.Margin then
		if allowRetry then
			task.defer(function()
				pcall(measureHitbox, part, false)
			end)
		end
		return
	end

	registerHitboxHit(part)
end

-- Хитбокс появился и накрыл нас. Обновляем статистику и подгонку.
function registerHitboxHit(part)
	--[[
		Дистанция до владельца удара - именно её сравнивает автоблок,
		поэтому по ней и подгоняется зона.

		Ищем среди КИЛЛЕРОВ, а не среди всех игроков: рядом почти всегда
		стоит другой выживший, и он оказался бы «ближайшим», занизив замер.
	]]
	local reach = nearestKillerDistance()

	hitboxStats.hits += 1
	flashHitbox(part)

	if reach then
		hitboxStats.lastDistance = reach
		if not hitboxStats.maxDistance or reach > hitboxStats.maxDistance then
			hitboxStats.maxDistance = reach
		end
		table.insert(hitboxSamples, reach)
		while #hitboxSamples > HITBOX.Samples do
			table.remove(hitboxSamples, 1)
		end
		autoTuneReach()
	end

	-- Блок стоял в момент удара - значит нажатие было не впустую
	local okBlocking, blocking = pcall(function()
		return character and character:GetAttribute(BLOCKING_KEY)
	end)
	if okBlocking and blocking == true then
		hitboxStats.blocked += 1
	end

	if pendingPress then
		pendingPress = nil -- подтверждено, впустую не считаем
	end
end

local function startHitboxWatch()
	if hitboxConnection then
		return
	end
	hitboxConnection = workspace.DescendantAdded:Connect(function(descendant)
		-- pcall: объект может умереть в тот же кадр, а ошибка в обработчике
		-- события молча оборвала бы всю дальнейшую слежку
		pcall(function()
			if descendant:IsA("BasePart") and isHitboxName(descendant.Name) then
				measureHitbox(descendant, true)
			end
		end)
	end)
end

local function stopHitboxWatch()
	if hitboxConnection then
		hitboxConnection:Disconnect()
		hitboxConnection = nil
	end
	clearHitboxFlashes(true)
	pendingPress = nil
end

-- Нажали блок, но хитбокс так и не пришёл - значит потратили зря.
local function expirePendingPress()
	if pendingPress and os.clock() >= pendingPress.expires then
		hitboxStats.wasted += 1
		pendingPress = nil
	end
end

local function keyCodeFromInputText(text)
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = text:match("^%s*(.-)%s*$")
	if trimmed == "" then
		return nil
	end
	-- Кнопка способности может показывать цифру, а Enum.KeyCode["1"] нет
	local name = DIGIT_KEY_NAMES[trimmed] or trimmed:upper()
	return keyCodeFromName(name)
end

--[[
	Кнопка блока в интерфейсе раунда.

	Это главный источник: кнопка существует только если блок реально выдан,
	и в её Input написана та клавиша, которую видит игрок. Возвращает саму
	кнопку - из неё же читается кулдаун.
]]
local function blockButtonFromGui()
	local mainGui = playerGui:FindFirstChild("MainGui")
	if not mainGui then
		return nil
	end
	local roundUi = mainGui:FindFirstChild("RoundUI")
	local playerUi = roundUi and roundUi:FindFirstChild("PlayerUI")
	local abilities = playerUi and playerUi:FindFirstChild("Abilities")
	local folder = abilities and abilities:FindFirstChild("Folder")
	-- До начала раунда Folder пустая - это нормальное состояние, не ошибка
	return folder and folder:FindFirstChild(BLOCK_ABILITY_NAME) or nil
end

local function blockKeyFromButton(button)
	local input = button and button:FindFirstChild("Input")
	if input and input:IsA("TextLabel") then
		return keyCodeFromInputText(input.Text)
	end
	return nil
end

-- Слот блока читается из атрибутов Ability1..AbilityN своего персонажа:
-- набор способностей в этом плейсе рандомный каждый раунд.
local function findBlockSlot(char)
	if not char then
		return nil
	end

	local count = AUTOBLOCK.MaxSlots
	local okNum, declared = pcall(function()
		return char:GetAttribute("AbilityNum")
	end)
	if okNum and type(declared) == "number" and declared > 0 then
		count = math.min(math.floor(declared), AUTOBLOCK.MaxSlots)
	end

	for index = 1, count do
		local okName, name = pcall(function()
			return char:GetAttribute("Ability" .. index)
		end)
		if okName and name == BLOCK_ABILITY_NAME then
			return index
		end
	end
	return nil
end

--[[
	Находит блок и клавишу к нему. Вызывается по таймеру, потому что и
	атрибуты, и кнопка появляются позже персонажа.

	Порядок источников: кнопка интерфейса, затем атрибуты. Кнопки достаточно
	самой по себе - если она есть, блок выдан, даже когда атрибуты Ability<N>
	ещё не доехали.
]]
local function resolveBlock()
	blockButton = blockButtonFromGui()
	blockSlot = findBlockSlot(character)

	local fromGui = blockKeyFromButton(blockButton)
	if fromGui then
		blockKey = fromGui
		blockKeySource = "gui"
		return
	end

	if blockSlot then
		blockKey = SLOT_KEYS[blockSlot]
		blockKeySource = blockKey and "slot" or nil
		return
	end

	blockKey = nil
	blockKeySource = nil
end

local function pressBlockKey()
	if not (autoblockInputAvailable and blockKey) then
		return false
	end

	-- Метка ставится ДО отправки: событие ввода прилетает синхронно
	syntheticKey = blockKey
	syntheticUntil = os.clock() + 0.1

	local ok, err = pcall(function()
		VirtualInputManager:SendKeyEvent(true, blockKey, false, game)
	end)
	if not ok then
		syntheticKey = nil
		autoblockInputBlocked = true
		warn(string.format(
			"[AdminMenu] автоблок: VirtualInputManager отказал (%s). "
				.. "Этому сервису нужны права executor'а - у обычного LocalScript их нет. "
				.. "Запусти скрипт через executor или блокируйся вручную.",
			tostring(err)
		))
		return false
	end

	-- Отпускание держит ту же клавишу, поэтому в замыкание она берётся
	-- копией: к моменту task.delay blockKey уже мог смениться раундом.
	local pressedKey = blockKey
	task.delay(AUTOBLOCK.HoldTime, function()
		syntheticKey = pressedKey
		syntheticUntil = os.clock() + 0.1
		pcall(function()
			VirtualInputManager:SendKeyEvent(false, pressedKey, false, game)
		end)
	end)
	return true
end

--[[
	Остаток кулдауна, по порядку надёжности:
	  1. атрибут BlockCooldown своего персонажа - он тикает вниз шагом 0.1
	     и это ровно то, чем считает кулдаун сам плейс;
	  2. текст CooldownLabel/Cooldown у кнопки способности;
	  3. свой таймер по замеренным 35 с - если ни того, ни другого нет.
	Первые два точные, третий печатается с «~».
]]
local function blockCooldownRemaining()
	if character then
		local okAttr, value = pcall(function()
			return character:GetAttribute(BLOCK_COOLDOWN_KEY)
		end)
		if okAttr and type(value) == "number" and value == value and value > 0 then
			return value, true
		end
	end

	if blockButton then
		for _, name in ipairs({ "CooldownLabel", "Cooldown" }) do
			local child = blockButton:FindFirstChild(name)
			if child and child:IsA("TextLabel") then
				local seconds = tonumber(child.Text:match("%d+%.?%d*"))
				if seconds and seconds > 0 then
					return seconds, true
				end
			end
		end
	end

	if autoblockLastPress > 0 then
		local left = BLOCK_COOLDOWN - (os.clock() - autoblockLastPress)
		if left > 0 then
			return left, false
		end
	end
	return nil, false
end

-- Блок уже стоит. Атрибут держится ровно 1 с после срабатывания, и всё
-- это время повторное нажатие - чистая трата.
local function isBlocking()
	if not character then
		return false
	end
	local okAttr, value = pcall(function()
		return character:GetAttribute(BLOCKING_KEY)
	end)
	return okAttr and value == true
end

local function autoblockStatusText()
	--[[
		Своя роль проверяется первой: у киллера блока нет, и любое другое
		сообщение здесь вводило бы в заблуждение («готов», хотя жать нечего).
	]]
	if selfIsKiller then
		return "Автоблок: ты киллер в этом раунде - автоблок и предупреждение отключены."
	end
	if not autoblockInputAvailable then
		return "Автоблок: нет доступа к вводу (VirtualInputManager отсутствует)."
	end
	if autoblockInputBlocked then
		return "Автоблок: ввод запрещён. Нужен executor - подробности в консоли (F9)."
	end
	if not blockKey then
		return "Автоблок: блока нет в этом раунде (способности рандомные)."
	end

	local slotText = blockSlot and string.format("слот %d, ", blockSlot) or ""
	local source = blockKeySource == "gui" and "из интерфейса" or "по номеру слота"

	--[[
		Обратная сторона конфликта клавиш. Своё нажатие мы отфильтровываем,
		а вот когда игрок сам жмёт E (по умолчанию ESP), плейс на ту же
		клавишу тратит способность. Это поведение игры, а не скрипта, но
		молчать о нём нельзя - выглядит как случайный расход блока.

		BINDS перебирается здесь напрямую: bindIdUsingKey объявлена ниже,
		и ссылка на неё отсюда ушла бы в несуществующий глобал.
	]]
	local conflict = false
	for _, bound in pairs(BINDS) do
		if bound == blockKey then
			conflict = true
			break
		end
	end
	local warning = conflict and " КОНФЛИКТ: эта же клавиша на бинде меню, перевесь его." or ""

	local left, exact = blockCooldownRemaining()
	if left then
		return string.format(
			"Автоблок: %sклавиша %s (%s). Кулдаун %s%dс.%s",
			slotText,
			blockKey.Name,
			source,
			exact and "" or "~",
			math.ceil(left),
			warning
		)
	end
	if isBlocking() then
		return string.format("Автоблок: %sклавиша %s (%s). БЛОК СТОИТ.%s", slotText, blockKey.Name, source, warning)
	end
	return string.format(
		"Автоблок: %sклавиша %s (%s), готов.%s",
		slotText,
		blockKey.Name,
		source,
		warning
	)
end

--[[
	Вторая строка статуса: что автоблок НАМЕРЯЛ по хитбоксам.

	Ровно то, чего не хватало, чтобы понять жалобу «блок просирается»:
	видно, сколько ударов накрыло, сколько из них попало в стоящий блок,
	сколько нажатий ушло в пустоту, и с какой дистанции реально бьют.
]]
local function autoblockMetricsText()
	local reach = string.format("зона %dm", AUTOBLOCK.Reach)
	if AUTOBLOCK.Ranged and AUTOBLOCK.Radius > AUTOBLOCK.Reach then
		reach = reach .. string.format(" + дальние %dm", AUTOBLOCK.Radius)
	end

	if hitboxStats.hits == 0 and hitboxStats.wasted == 0 then
		return reach .. ". Удары: пока ни одного. Зона подстроится сама."
	end

	local distances = ""
	if hitboxStats.lastDistance then
		distances = string.format(
			" Дистанция удара: последний %.1f, худший %.1f.",
			hitboxStats.lastDistance,
			hitboxStats.maxDistance or hitboxStats.lastDistance
		)
	end

	return string.format(
		"%s. Ударов по мне %d, из них в блок %d. Впустую нажатий: %d.%s",
		reach,
		hitboxStats.hits,
		hitboxStats.blocked,
		hitboxStats.wasted,
		distances
	)
end

local function refreshAutoblockStatus()
	if autoblockStatusLabel then
		autoblockStatusLabel.Text = autoblockStatusText()
	end
	if autoblockMetricsLabel then
		autoblockMetricsLabel.Text = autoblockMetricsText()
	end
end

-- Модели киллеров этого раунда. Берём через игроков, чтобы переиспользовать
-- ту же логику команд, что и список: манекен в лобби не игрок и в выборку
-- не попадёт.
local function forEachKillerCharacter(callback)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local char = other.Character
			if char and char.Parent and teamNameOf(other, char) == KILLER_TEAM then
				callback(char)
			end
		end
	end
end

--[[
	Стоит ли реагировать на этот замах.

	Причина существования этой функции: блок держится 1 с, а кулдаун 35 с,
	то есть ОДНО лишнее нажатие = 35 секунд без защиты. Раньше условием
	была одна дистанция, и блок сгорал на любом замахе киллера рядом -
	в том числе на удар по другому выжившему или в пустоту.

	Два режима, потому что атаки в плейсе двух родов:
	  - ближний бой: киллер должен быть в пределах Reach. Замеры лога:
	    попадания с 5.5 и 4.9 студов, промахи с 8.4 и 8.5. Конус мягкий,
	    киллер доворачивается уже во время анимации. Зона видна в мире;
	  - стреляющие атаки: до Radius, конус жёсткий, и режим ВЫКЛЮЧЕН по
	    умолчанию. Именно на них блок и уходил впустую: киллер стреляет
	    через пол-карты, а 35 с кулдауна тратим мы.

	Возвращает false для всего остального - это и есть экономия кулдауна.
]]
local function shouldBlockAttack(char, root, myPosition)
	local toMe = myPosition - root.Position
	local distance = toMe.Magnitude

	-- Жёсткая внешняя граница. Когда дальний режим выключен, ей становится
	-- зона ближнего боя, и удар «за 9999 студов» отсекается здесь же.
	local limit = (AUTOBLOCK.Ranged and AUTOBLOCK.Radius > AUTOBLOCK.Reach)
		and AUTOBLOCK.Radius
		or AUTOBLOCK.Reach
	if distance > limit then
		return false
	end

	-- Вырожденный случай: киллер стоит ровно в нас, направление не считается
	if distance < 0.1 then
		return true
	end

	--[[
		Взгляд берётся с ГОЛОВЫ/торса, а не с HumanoidRootPart: у рагдольнутых
		и анимированных моделей рут крутит как попало, а LookVector торса
		совпадает с тем, куда киллер целится.
	]]
	local aimPart = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or root
	local facing = aimPart.CFrame.LookVector

	-- Сравниваем только по горизонтали: разница по высоте (лестницы,
	-- склоны) не означает, что киллер бьёт не в нас.
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local flatToMe = Vector3.new(toMe.X, 0, toMe.Z)
	if flatFacing.Magnitude < 0.01 or flatToMe.Magnitude < 0.01 then
		return distance <= AUTOBLOCK.Reach
	end

	local alignment = flatFacing.Unit:Dot(flatToMe.Unit)

	if distance <= AUTOBLOCK.Reach then
		return alignment >= AUTOBLOCK.MeleeCone
	end
	return alignment >= AUTOBLOCK.RangedCone
end

local function autoblockStep()
	if not (character and character.Parent and rootPart) then
		return
	end
	-- Сам киллер: блокировать нечем, нажатие ушло бы в чужую способность
	if selfIsKiller then
		return
	end
	if not (blockKey and autoblockInputAvailable and not autoblockInputBlocked) then
		return
	end

	--[[
		Гейты состояния. Раньше их не было, и автоблок жал клавишу в
		кулдаун: нажатие уходило в пустоту, а дебаунс считал, что атака
		отработана.
	]]
	if isBlocking() then
		return -- блок уже стоит, он держится 1 с
	end
	if blockCooldownRemaining() then
		return -- перезарядка, жать бессмысленно
	end

	local now = os.clock()

	-- Дебаунс ОБЩИЙ: блок один, и на второго киллера нажатие всё равно
	-- ушло бы в только что начавшийся кулдаун.
	if now - autoblockLastPress < AUTOBLOCK.Debounce then
		return
	end

	local myPosition = rootPart.Position

	--[[
		Кандидаты собираются и сортируются по дистанции: при двух киллерах
		в раунде реагировать надо на ближнего. Нажатие всё равно одно, но
		от того, кто ближе, удар прилетит раньше.
	]]
	local attackers = {}
	forEachKillerCharacter(function(char)
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local okAttr, using = pcall(function()
			return char:GetAttribute("UsingAbility")
		end)
		if not (okAttr and using == true) then
			return
		end

		if not shouldBlockAttack(char, root, myPosition) then
			return
		end

		table.insert(attackers, {
			char = char,
			distance = (root.Position - myPosition).Magnitude,
		})
	end)

	if #attackers == 0 then
		return
	end

	table.sort(attackers, function(a, b)
		return a.distance < b.distance
	end)

	-- Отметка по модели остаётся: она не даёт реагировать на ОДИН и тот же
	-- висящий UsingAbility второй раз, даже если общий дебаунс уже истёк.
	local target = attackers[1]
	local last = autoblockTriggered[target.char]
	if last and (now - last) < AUTOBLOCK.Debounce then
		return
	end
	autoblockTriggered[target.char] = now

	if pressBlockKey() then
		autoblockLastPress = now
		-- Ждём подтверждения хитбоксом: если он не придёт, нажатие пойдёт
		-- в счётчик «впустую» и станет видно в меню.
		pendingPress = { time = now, expires = now + HITBOX.Window }
		refreshAutoblockStatus()
	end
end

local function applyAutoblock(enabled)
	if not enabled then
		destroyZones()
		stopHitboxWatch()
		return
	end

	--[[
		У киллера автоблок не запускается совсем: ни зон, ни слежения за
		хитбоксами. Тумблер при этом остаётся включённым - роль сменится в
		следующем раунде, и всё поднимется само, без повторного щелчка.
	]]
	if selfIsKiller then
		destroyZones()
		stopHitboxWatch()
		refreshAutoblockStatus()
		return
	end

	table.clear(autoblockTriggered)
	resolveBlock()
	startHitboxWatch()
	updateZones()
	refreshAutoblockStatus()
end

