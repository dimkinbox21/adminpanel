--=========================== ТУМБЛЕРЫ И БИНДЫ ===========================

local FEATURES = {
	{ id = "fly", label = "Fly", apply = applyFly },
	{ id = "noclip", label = "Noclip", apply = applyNoclip },
	{ id = "god", label = "Godmode", apply = applyGod },
	{ id = "stamina", label = "Бесконечная стамина", apply = applyStamina },
	{ id = "invisible", label = "Невидимость", apply = applyInvisible },
	{ id = "esp", label = "ESP", apply = applyEsp },
	{ id = "list", label = "Список игроков", apply = applyList },
	{ id = "autoblock", label = "Автоблок", apply = applyAutoblock },
	--[[
		Предупреждение не «чит»: оно только читает то, что сервер и так
		реплицирует. Но в списке тумблеров ему место - выключать его надо
		тем же способом, что и всё остальное.
	]]
	{
		id = "warning",
		label = "Предупреждение о киллере",
		apply = function()
			refreshWarningVisibility()
		end,
	},
	--[[
		Аим и авто-бег (40_auto): apply no-op, как у предупреждения -
		отпускание клавиши и остановка поворота делает сама step-функция
		в следующем кадре. Состояние ставит setFeature.
	]]
	{
		id = "aim",
		label = "Аим на киллера (X)",
		apply = function() end,
	},
	{
		id = "autobrun",
		label = "Авто-бег",
		apply = function() end,
	},
}

local FEATURE_BY_ID = {}
for _, feature in ipairs(FEATURES) do
	FEATURE_BY_ID[feature.id] = feature
end

local toggleButtons = {} -- [featureId] = TextButton
local bindButtons = {} -- [bindId] = TextButton
local captureBindId = nil -- какой бинд сейчас ждёт нажатия клавиши

-- Функции refresh кнопок настроек. Живут в замыканиях фабрик, поэтому
-- собираются здесь - иначе сбросу настроек нечего было бы обновлять.
local settingRefreshers = {}

local function refreshToggle(featureId)
	local button = toggleButtons[featureId]
	if not button then
		return
	end
	local enabled = state[featureId]

	--[[
		Автоблок и предупреждение у киллера выключены на весь раунд. Пишем
		это на самом тумблере: иначе он горел бы ON, а ничего не делал -
		ровно та ситуация, из-за которой раньше было непонятно, работает
		автоблок или нет.
	]]
	if (featureId == "autoblock" or featureId == "warning") and selfIsKiller then
		button.BackgroundColor3 = COLORS.Off
		button.TextColor3 = COLORS.Muted
		button.Text = FEATURE_BY_ID[featureId].label .. "  [ты киллер]"
		return
	end

	-- Автоблок и авто-бег без VirtualInputManager нажать некому: тумблер
	-- гасим, чтобы он не выглядел работающим.
	if (featureId == "autoblock" or featureId == "autobrun") and (not autoblockInputAvailable or autoblockInputBlocked) then
		button.BackgroundColor3 = COLORS.Off
		button.TextColor3 = COLORS.Muted
		button.Text = FEATURE_BY_ID[featureId].label .. "  [нет доступа к вводу]"
		return
	end

	button.TextColor3 = COLORS.Text
	button.BackgroundColor3 = enabled and COLORS.On or COLORS.Off
	button.Text = string.format("%s  [%s]", FEATURE_BY_ID[featureId].label, enabled and "ON" or "OFF")
end

local function setFeature(featureId, enabled)
	if state[featureId] == enabled then
		return
	end
	state[featureId] = enabled
	FEATURE_BY_ID[featureId].apply(enabled)
	refreshToggle(featureId)
end

local function toggleFeature(featureId)
	-- Включать автоблок и авто-бег, когда нажатия отправлять нечем,
	-- бессмысленно: тумблер бы горел ON, а ничего не происходило.
	if (featureId == "autoblock" or featureId == "autobrun") and not state[featureId] then
		if not autoblockInputAvailable or autoblockInputBlocked then
			refreshToggle(featureId)
			if featureId == "autoblock" then
				refreshAutoblockStatus()
			end
			return
		end
	end
	setFeature(featureId, not state[featureId])
end

local function refreshBind(bindId)
	local button = bindButtons[bindId]
	if not button then
		return
	end
	if captureBindId == bindId then
		button.Text = "..."
		button.BackgroundColor3 = COLORS.Capture
	else
		button.Text = BINDS[bindId].Name
		button.BackgroundColor3 = COLORS.Bind
	end
end

local function startCapture(bindId)
	local previous = captureBindId
	captureBindId = bindId
	if previous then
		refreshBind(previous)
	end
	refreshBind(bindId)
end

local function stopCapture()
	local bindId = captureBindId
	captureBindId = nil
	if bindId then
		refreshBind(bindId)
	end
end

local function refreshAllSettings()
	for _, refresh in ipairs(settingRefreshers) do
		refresh()
	end
	for _, bindId in ipairs(BIND_IDS) do
		refreshBind(bindId)
	end
end

local function bindIdUsingKey(keyCode, exceptBindId)
	for bindId, bound in pairs(BINDS) do
		if bindId ~= exceptBindId and bound == keyCode then
			return bindId
		end
	end
	return nil
end

local function flashReject(bindId)
	local button = bindButtons[bindId]
	if not button then
		return
	end
	button.Text = "занято"
	button.BackgroundColor3 = COLORS.Reject
	task.delay(0.8, function()
		if captureBindId ~= bindId then
			refreshBind(bindId)
		end
	end)
end

local function assignBind(bindId, keyCode)
	if keyCode == Enum.KeyCode.Escape then
		stopCapture()
		return
	end
	if keyCode == Enum.KeyCode.Unknown then
		return
	end

	local conflict = bindIdUsingKey(keyCode, bindId)
	captureBindId = nil

	if conflict then
		flashReject(bindId)
		return
	end

	BINDS[bindId] = keyCode
	refreshBind(bindId)
	markDirty()
end

local function makeBindButton(bindId, parent)
	local button = new("TextButton", {
		Name = "Bind_" .. bindId,
		Size = UDim2.fromOffset(64, 34),
		Position = UDim2.new(1, -64, 0, 0),
		BackgroundColor3 = COLORS.Bind,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.Gotham,
		Text = BINDS[bindId].Name,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = COLORS.Text,
		Parent = parent,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })

	button.MouseButton1Click:Connect(function()
		if captureBindId == bindId then
			stopCapture()
		else
			startCapture(bindId)
		end
	end)

	bindButtons[bindId] = button
	return button
end

local function makeFeatureRow(feature)
	local row = new("Frame", {
		Name = feature.label .. "Row",
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Parent = body,
	})

	local toggle = new("TextButton", {
		Name = feature.label,
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundColor3 = COLORS.Off,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = feature.label,
		TextSize = 13,
		TextColor3 = COLORS.Text,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = toggle })

	toggle.MouseButton1Click:Connect(function()
		toggleFeature(feature.id)
	end)

	toggleButtons[feature.id] = toggle
	makeBindButton(feature.id, row)
	refreshToggle(feature.id)
	return row
end

-- Кнопка-переключатель без бинда, работает с полем в таблице
local function makeOptionButton(label, container, key)
	local button = new("TextButton", {
		Name = "Opt_" .. tostring(key),
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = nextOrder(),
		BackgroundColor3 = container[key] and COLORS.On or COLORS.Off,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 12,
		TextColor3 = COLORS.Text,
		Parent = body,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })

	local function refresh()
		button.BackgroundColor3 = container[key] and COLORS.On or COLORS.Off
		button.Text = string.format("%s  [%s]", label, container[key] and "ON" or "OFF")
	end

	button.MouseButton1Click:Connect(function()
		container[key] = not container[key]
		refresh()
		markDirty()
		if container == AUTOBLOCK or container == HITBOX then
			-- Зона должна пропасть/появиться сразу, а не через ScanInterval
			updateZones()
			refreshAutoblockStatus()
			if container == HITBOX and not HITBOX.ShowHits then
				clearHitboxFlashes(true) -- убрать то, что уже висит
			end
			return
		end
		if container == LIST then
			if state.list then
				updateList() -- панель ждала бы до Interval, выглядит как залипание
			end
			return
		end
		if container == STAMINA then
			--[[
				Переподписываемся: слушатель Fatigue ставится только при
				включённом NoFatigue, и без этого галка начинала бы
				действовать лишь со следующего спавна.
			]]
			if state.stamina then
				applyStamina(true)
			end
			return
		end
		if not state.esp then
			return
		end
		if key == "Highlight" or key == "Tracers" or key == "OffScreen" then
			-- сразу прячем то, что выключили; включится в следующем кадре
			hideEspVisuals(key)
		end
	end)

	refresh()
	table.insert(settingRefreshers, refresh)
	return button
end

-- Строка "минус / значение / плюс"
local function makeStepperRow(labelText, container, key, step, minValue, maxValue, formatter)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Parent = body,
	})

	local label = new("TextLabel", {
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local function refresh()
		label.Text = string.format("%s: %s", labelText, formatter(container[key]))
	end

	local function makeStepButton(text, offsetX, delta)
		local button = new("TextButton", {
			Size = UDim2.fromOffset(30, 24),
			Position = UDim2.new(1, offsetX, 0, 2),
			BackgroundColor3 = COLORS.Off,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextSize = 15,
			TextColor3 = COLORS.Text,
			Parent = row,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })

		button.MouseButton1Click:Connect(function()
			container[key] = math.clamp(container[key] + delta, minValue, maxValue)
			refresh()
			markDirty()
			if container == AUTOBLOCK then
				updateZones() -- иначе граница едет с задержкой ScanInterval
				refreshAutoblockStatus()
			end
		end)
	end

	makeStepButton("-", -64, -step)
	makeStepButton("+", -30, step)
	refresh()
	table.insert(settingRefreshers, refresh)
	return row, refresh
end

--=========================== СБОРКА МЕНЮ ===========================

--[[
	Вкладки. Порядок - по частоте использования в бою: читы и автоблок
	первыми, конфиг последним.
]]
makeTab("cheats", "Читы", "движение, здоровье, стамина, невидимость")
makeTab("esp", "ESP", "подсветка игроков сквозь стены")
makeTab("list", "Игроки", "панель со списком и стаминой")
makeTab("block", "Автоблок", "зоны, хитбоксы, замеры")
makeTab("warning", "Опасность", "баннер о киллере сверху экрана")
makeTab("config", "Конфиг", "профили настроек, сохранение по кнопке")

setPage("cheats")
makeSection("ДВИЖЕНИЕ")
makeFeatureRow(FEATURE_BY_ID.fly)
makeStepperRow("Fly speed", FLY, "Speed", FLY.Step, FLY.Min, FLY.Max, function(value)
	return tostring(value)
end)
makeFeatureRow(FEATURE_BY_ID.noclip)

makeSection("ВЫЖИВАЕМОСТЬ")
makeFeatureRow(FEATURE_BY_ID.god)
makeNote("Godmode локальный: урон от серверных скриптов он не остановит.")
makeFeatureRow(FEATURE_BY_ID.stamina)
makeOptionButton("Снимать усталость (Fatigue)", STAMINA, "NoFatigue")
makeNote(
	"Стамина работает по-настоящему: меняется предел MaxStamina, а считает "
		.. "её клиентский код плейса. Скорость бега при этом не растёт."
)

makeSection("НЕВИДИМОСТЬ")
makeFeatureRow(FEATURE_BY_ID.invisible)
makeNote(
	"Приём с анимацией: персонаж уезжает из своей модели. Камера "
		.. "переезжает на HumanoidRootPart, коллизии снимаются. "
		.. "Зависит от анимационного ассета - может перестать работать "
		.. "после патча плейса."
)

makeSection("АИМ")
makeFeatureRow(FEATURE_BY_ID.aim)
makeStepperRow("Скорость аима", ESP, "AimSpeed", 60, 60, 1440, function(value)
	return value .. " град/с"
end)
makeNote(
	"Камера постоянно доворачивается за ближайшим живым киллером "
		.. "по горизонтали. Вертикаль остаётся под мышкой. В режиме паники "
		.. "авто-бега (киллер ближе 25 м) стамина не опускается ниже "
		.. "заданного пола (1-5)."
)

makeSection("БЕГ")
makeFeatureRow(FEATURE_BY_ID.autobrun)
makeOptionButton("Менеджмент стамины", RUN, "Managed")
makeStepperRow("Порог стамины", RUN, "Low", 5, 5, 90, function(value)
	return value .. "%"
end)
makeStepperRow("Запас возврата", RUN, "Resume", 5, 5, 40, function(value)
	return "+" .. value
end)
makeStepperRow("Дистанция паники", RUN, "PanicDistance", 5, 10, 100, function(value)
	return value .. " м"
end)
makeStepperRow("Пол стамины в панике", RUN, "PanicFloor", 1, 1, 5, function(value)
	return value
end)
local runStatusLabel
do
	local label = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = body,
	})
	runStatusLabel = label
end
refreshRunStatus(runStatusLabel)
makeNote(
	"Менеджмент: стамина ниже порога - спринт отпускается, при "
		.. "восстановлении зажимается снова. Киллер рядом (дистанция паники) - "
		.. "лимиты игнорируются, но стамина не спускается ниже пола. "
		.. "Клавиша справа - бинд спринта, переназначается."
)

makeSection("МЕНЮ")
do
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Parent = body,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "Открыть / закрыть",
		TextSize = 13,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	makeBindButton("menu", row)
end
makeNote(
	string.format(
		"Клавиша справа от тумблера - бинд. Нажми её и затем новую клавишу, "
			.. "Escape - отмена.\nПолёт: WASD, %s / %s",
		FLY_KEYS.Up.Name,
		FLY_KEYS.Down.Name
	)
)

setPage("esp")
makeSection("ESP")
makeFeatureRow(FEATURE_BY_ID.esp)
makeOptionButton("Подсветка", ESP, "Highlight")
makeOptionButton("Имена", ESP, "Names")
makeOptionButton("Здоровье", ESP, "Health")
makeOptionButton("Дистанция", ESP, "Distance")
makeOptionButton("Трейсеры", ESP, "Tracers")
makeOptionButton("Указатели 360 (кто вне экрана)", ESP, "OffScreen")
makeOptionButton("Скрывать союзников", ESP, "TeamCheck")
makeStepperRow("Радиус", ESP, "MaxDistance", ESP.DistanceStep, 0, ESP.DistanceLimit, function(value)
	return value == 0 and "без лимита" or (value .. "m")
end)
makeNote(
	"Цвет метки - цвет команды, тот же что в списке игроков: выжившие "
		.. "голубые, киллер красный, призраки серые. Трейсер и стрелка 360 "
		.. "целятся в середину корпуса."
)
makeNote(
	"Указатели 360 показывают стрелку у края экрана на тех, кого не видно "
		.. "в кадре - в том числе за спиной. Направление считается по камере, "
		.. "а не по экранной проекции: за спиной проекция зеркалится и стрелка "
		.. "врала бы сторону. Радиус и «Скрывать союзников» действуют и на них."
)

makeSection("CARETAKER")
makeOptionButton("Отмечать носителя Caretaker", ESP, "MarkCaretaker")
makeNote(
	"Выживший с этой способностью подсвечивается сиреневым и получает "
		.. "подпись [CARETAKER]. Определяется по предмету Vanities.CaretakerItem "
		.. "и держится ВЕСЬ РАУНД - в том числе после того, как способность "
		.. "израсходована. Показывается даже при включённом «Скрывать "
		.. "союзников» - иначе фильтр прятал бы ровно того, кого надо видеть."
)

setPage("list")
makeSection("СПИСОК ИГРОКОВ")
makeFeatureRow(FEATURE_BY_ID.list)
makeOptionButton("Дальность", LIST, "Distance")
makeOptionButton("Стамина", LIST, "Stamina")
makeOptionButton("Сортировка по дальности", LIST, "SortByDistance")
makeOptionButton("Показывать себя", LIST, "ShowSelf")
makeNote(
	"Стамина читается из атрибута StaminaServer - только его сервер "
		.. "репликует про чужих игроков. Максимум берётся по виду киллера."
)

setPage("block")
makeSection("АВТОБЛОК")
makeFeatureRow(FEATURE_BY_ID.autoblock)
makeOptionButton("Показывать зону", AUTOBLOCK, "ShowZone")
makeOptionButton("Подсвечивать удары", HITBOX, "ShowHits")
local _, refreshReachStepper = makeStepperRow(
	"Ближний бой",
	AUTOBLOCK,
	"Reach",
	AUTOBLOCK.ReachStep,
	AUTOBLOCK.ReachMin,
	AUTOBLOCK.ReachMax,
	function(value)
		return value .. "m"
	end
)
-- Автоподгонка меняет Reach сама, минуя кнопки: без этого степпер
-- показывал бы старое число до следующего клика.
onReachTuned = refreshReachStepper
makeOptionButton("Подгонять зону по ударам", AUTOBLOCK, "AutoTune")
makeOptionButton("Блокировать дальние атаки", AUTOBLOCK, "Ranged")
makeStepperRow(
	"Дальние атаки",
	AUTOBLOCK,
	"Radius",
	AUTOBLOCK.RadiusStep,
	AUTOBLOCK.RadiusMin,
	AUTOBLOCK.RadiusMax,
	function(value)
		return value .. "m"
	end
)
makeNote(
	"Блок держится 1 с, кулдаун 35 с: одно лишнее нажатие = полминуты без "
		.. "защиты. Поэтому дальние атаки выключены по умолчанию."
)

makeSection("СОСТОЯНИЕ")

-- Строка состояния автоблока: слот, клавиша, кулдаун или причина, почему
-- он не работает. Обновляется в основном цикле.
autoblockStatusLabel = new("TextLabel", {
	Name = "AutoblockStatus",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = nextOrder(),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextSize = 11,
	TextWrapped = true,
	TextColor3 = COLORS.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = body,
})

-- Вторая строка: замеры по хитбоксам. Отдельно от первой, потому что
-- первая про готовность, а эта про то, попадает ли автоблок.
autoblockMetricsLabel = new("TextLabel", {
	Name = "AutoblockMetrics",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = nextOrder(),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextSize = 11,
	TextWrapped = true,
	TextColor3 = COLORS.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = body,
})
refreshAutoblockStatus()

setPage("warning")
makeSection("ПРЕДУПРЕЖДЕНИЕ О КИЛЛЕРЕ")
makeFeatureRow(FEATURE_BY_ID.warning)
makeStepperRow(
	"Показывать до",
	WARNING,
	"Distance",
	WARNING.DistanceStep,
	WARNING.DistanceMin,
	WARNING.DistanceMax,
	function(value)
		return value .. "m"
	end
)
makeNote(
	"Баннер сверху экрана: дистанция до ближайшего киллера, его имя и стамина.\n"
		.. "КРАСНЫЙ - стамина падает: киллер тратит её, то есть бежит или атакует.\n"
		.. "ЗЕЛЁНЫЙ - стамина растёт или стоит на месте: он не в погоне.\n"
		.. "Цвет считается по скорости изменения, а не по величине: полная "
		.. "стамина у стоящего и у разгоняющегося выглядит одинаково."
)
makeNote(
	"Если ты сам киллер в этом раунде, баннер и автоблок выключаются "
		.. "автоматически - блока у киллера нет, а предупреждать его не о чем."
)

--=========================== ВКЛАДКА КОНФИГА ===========================
--[[
	Целиком в do-блок ради лимита Luau на 200 локалов: после добавления
	аима и авто-бега верхний уровень в упор (CompileError на
	configStatusText - на СЛУЧАЙНОЙ функции, которой не хватило регистра,
	а не на виновнике). Наружу выходит refreshConfigStatus: вкладка
	самодостаточна, но её статус печатается при открытии меню ПОСЛЕ end
	блока (вызов на стартовой вкладке ниже) - форвард-локал, определение
	внутри БЕЗ local. markDirty/onConfigDirtyChanged - уже форвард-локалы
	конфига (10_config).
]]
local refreshConfigStatus

do
setPage("config")
makeSection("ПРОФИЛЬ")

--[[
	Имя профиля вводится в TextBox. Файл получает имя <профиль>.json, так
	что разных наборов настроек может быть сколько угодно.

	Ввод санируется тем же sanitizeConfigName, что и чтение: имя вида
	"../secrets" писало бы файл вне папки executor'а, а имя со слэшем не
	создалось бы вообще.
]]
local configNameBox = nil
local configSaveButton = nil
local configStatusLabel = nil
local profilesLabel = nil

local function configStatusText()
	if writeFailed then
		return "Конфиг: ОШИБКА записи в " .. currentConfigPath() .. ". Подробности в консоли (F9)."
	end

	--[[
		Четыре состояния, а не два: без writefile настройки всё равно
		переживают перезапуск скрипта (лежат в памяти клиента, getgenv), и
		писать «только на эту сессию» было бы неправдой.
	]]
	if not hasFileApi then
		if hasSessionStore then
			local loadedFrom = configSource == "session" and " Текущие загружены из неё." or ""
			return "Нет writefile: сохранение идёт в память клиента. Переживёт перезапуск "
				.. "скрипта, но не выход из игры. Имя профиля при этом не используется."
				.. loadedFrom
		end
		return "Сохранять некуда: нет ни writefile, ни getgenv. Настройки живут только "
			.. "до перезапуска скрипта. Так и должно быть в Studio."
	end

	if configLoaded then
		return "Загружено из "
			.. (configSource == "session" and "памяти клиента" or currentConfigPath())
			.. ". Кнопка ниже перезапишет файл текущими настройками."
	end
	return "Файл " .. currentConfigPath() .. " ещё не создан - появится после сохранения."
end

local function refreshProfilesLabel()
	if not profilesLabel then
		return
	end
	local names = listProfiles()
	if not names then
		-- listfiles нет: молчим, а не пишем «профилей нет»
		profilesLabel.Text = ""
		profilesLabel.Visible = false
		return
	end
	profilesLabel.Visible = true
	if #names == 0 then
		profilesLabel.Text = "Сохранённых профилей пока нет."
		return
	end
	profilesLabel.Text = "Сохранённые профили: " .. table.concat(names, ", ")
end

-- Статус пересчитывается при открытии меню: ошибка записи может появиться
-- уже после запуска, и молча показывать старый текст нельзя.
-- Без local: имя объявлено форвард-локалом выше (вызов после end блока).
function refreshConfigStatus()
	if configStatusLabel then
		configStatusLabel.Text = configStatusText()
		if writeFailed then
			configStatusLabel.TextColor3 = COLORS.Reject
		else
			configStatusLabel.TextColor3 = hasAnyStore and Color3.fromRGB(120, 190, 140)
				or COLORS.Muted
		end
	end
	refreshProfilesLabel()
end

do
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Parent = body,
	})

	new("TextLabel", {
		Size = UDim2.fromOffset(84, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Имя:",
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	configNameBox = new("TextBox", {
		Name = "ConfigName",
		Size = UDim2.new(1, -84, 0, 28),
		Position = UDim2.fromOffset(84, 2),
		BackgroundColor3 = COLORS.Bind,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = configName,
		PlaceholderText = "default",
		TextSize = 12,
		TextColor3 = COLORS.Text,
		ClearTextOnFocus = false,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = configNameBox })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = configNameBox,
	})

	--[[
		FocusLost, а не изменение текста: пока имя набирают, оно проходит
		через промежуточные состояния ("de", "def"...), и загружать профиль
		на каждый символ бессмысленно.

		Смена имени НЕ сохраняет и НЕ загружает автоматически - для этого
		есть отдельные кнопки. Иначе набранные настройки молча затирались бы
		содержимым другого профиля.
	]]
	configNameBox.FocusLost:Connect(function()
		local cleaned = sanitizeConfigName(configNameBox.Text)
		if not cleaned then
			configNameBox.Text = configName -- мусор откатываем
			return
		end
		if cleaned ~= configName then
			configName = cleaned
			markDirty() -- новый профиль ещё не записан
		end
		configNameBox.Text = configName
		refreshConfigStatus()
	end)
end

profilesLabel = new("TextLabel", {
	Name = "Profiles",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = nextOrder(),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextSize = 11,
	TextColor3 = COLORS.Muted,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = body,
})

makeSection("СОХРАНЕНИЕ")

do
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Parent = body,
	})

	configSaveButton = new("TextButton", {
		Name = "SaveConfig",
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = COLORS.Off,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = "Сохранить",
		TextSize = 12,
		TextColor3 = COLORS.Text,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = configSaveButton })

	local loadButton = new("TextButton", {
		Name = "LoadConfig",
		Size = UDim2.new(0.5, -4, 1, 0),
		Position = UDim2.new(0.5, 4, 0, 0),
		BackgroundColor3 = COLORS.Off,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = "Загрузить",
		TextSize = 12,
		TextColor3 = COLORS.Text,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = loadButton })

	--[[
		Кнопка сохранения показывает три состояния: «нечего сохранять»,
		«есть несохранённые изменения» и результат нажатия. Без этого при
		ручном сохранении невозможно понять, записаны настройки или нет -
		ровно та проблема, из-за которой автосохранение вообще существовало.
	]]
	local flashToken = 0

	local function refreshSaveButton()
		if not hasAnyStore then
			configSaveButton.Text = "Сохранять некуда"
			configSaveButton.BackgroundColor3 = COLORS.Off
			configSaveButton.TextColor3 = COLORS.Muted
			return
		end
		configSaveButton.TextColor3 = COLORS.Text
		if configDirty then
			configSaveButton.Text = "Сохранить •"
			configSaveButton.BackgroundColor3 = COLORS.Capture
		else
			configSaveButton.Text = "Сохранить"
			configSaveButton.BackgroundColor3 = COLORS.Off
		end
	end

	-- Форвард-локал из секции конфига: любое изменение настройки зажигает
	-- кнопку, включая автоподгонку зоны, которая правит Reach сама.
	onConfigDirtyChanged = refreshSaveButton

	local function flash(text, color)
		flashToken += 1
		local token = flashToken
		configSaveButton.Text = text
		configSaveButton.BackgroundColor3 = color
		task.delay(1.2, function()
			if flashToken == token then
				refreshSaveButton()
			end
		end)
	end

	configSaveButton.MouseButton1Click:Connect(function()
		if saveConfig() then
			flash("Сохранено", COLORS.On)
		else
			flash("Не удалось", COLORS.Reject)
		end
		refreshConfigStatus()
	end)

	loadButton.MouseButton1Click:Connect(function()
		local loaded, source = loadConfig()
		configLoaded, configSource = loaded, source
		if loaded then
			--[[
				После загрузки обязательно переприменить всё, что уже
				работает: кнопки показывают значения таблиц, а зоны, список
				и слушатель стамины были настроены под ПРЕДЫДУЩИЕ значения.
				refreshAllSettings обновляет и бинды тоже.
			]]
			refreshAllSettings()
			updateZones()
			if state.stamina then
				applyStamina(true)
			end
			if state.list then
				updateList()
			end
			refreshAutoblockStatus()
			configDirty = false
			refreshSaveButton()
			flash("Загружено", COLORS.On)
		else
			flash("Профиля нет", COLORS.Reject)
		end
		refreshConfigStatus()
	end)

	refreshSaveButton()
end

configStatusLabel = new("TextLabel", {
	Name = "ConfigStatus",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = nextOrder(),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextSize = 11,
	TextColor3 = COLORS.Muted,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = body,
})

makeNote(
	"Автосохранения нет: настройки записываются только по кнопке. Точка "
		.. "рядом с надписью «Сохранить» означает несохранённые изменения. "
		.. "Состояние читов не сохраняется намеренно - чит, включённый сам "
		.. "при спавне, сразу заявляет о себе анти-читу."
)
end -- do-блок вкладки конфига (лимит 200 локалов)

--=========================== СБРОС НАСТРОЕК ===========================

makeSection("СБРОС")

do
	local RESET_IDLE = "Сброс настроек"
	local RESET_CONFIRM = "Точно? Нажми ещё раз"
	local armed = false
	local armToken = 0

	local button = new("TextButton", {
		Name = "ResetSettings",
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = nextOrder(),
		BackgroundColor3 = COLORS.Off,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.Gotham,
		Text = RESET_IDLE,
		TextSize = 12,
		TextColor3 = COLORS.Text,
		Parent = body,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })

	local function disarm()
		armed = false
		button.Text = RESET_IDLE
		button.BackgroundColor3 = COLORS.Off
	end

	local function applyDefaults()
		for _, bindId in ipairs(BIND_IDS) do
			BINDS[bindId] = DEFAULTS.binds[bindId]
		end
		FLY.Speed = DEFAULTS.flySpeed
		for key, value in pairs(DEFAULTS.esp) do
			ESP[key] = value
		end
		for key, value in pairs(DEFAULTS.list) do
			LIST[key] = value
		end
		AUTOBLOCK.Radius = DEFAULTS.autoblockRadius
		AUTOBLOCK.Reach = DEFAULTS.autoblockReach
		AUTOBLOCK.Ranged = DEFAULTS.autoblockRanged
		AUTOBLOCK.ShowZone = DEFAULTS.autoblockShowZone
		AUTOBLOCK.AutoTune = DEFAULTS.autoblockAutoTune
		HITBOX.ShowHits = DEFAULTS.autoblockShowHits
		STAMINA.NoFatigue = DEFAULTS.staminaNoFatigue
		WARNING.Distance = DEFAULTS.warningDistance
		-- DEFAULTS.esp.AimSpeed восстанавливается pairs-циклом выше
		if type(DEFAULTS.run) == "table" and type(RUN) == "table" then
			RUN.Managed = DEFAULTS.run.managed
			RUN.Low = DEFAULTS.run.low
			RUN.Resume = DEFAULTS.run.resume
			RUN.PanicDistance = DEFAULTS.run.panicDistance
			RUN.PanicFloor = DEFAULTS.run.panicFloor
		end
		updateZones()
		-- Слушатель Fatigue зависит от NoFatigue, его надо переставить
		if state.stamina then
			applyStamina(true)
		end
	end

	button.MouseButton1Click:Connect(function()
		-- Два клика: десяток переназначенных биндов терять случайно неприятно.
		if not armed then
			armed = true
			armToken += 1
			local token = armToken
			button.Text = RESET_CONFIRM
			button.BackgroundColor3 = COLORS.Capture
			task.delay(2, function()
				if armed and armToken == token then
					disarm()
				end
			end)
			return
		end

		armToken += 1 -- отменяет отложенный disarm
		disarm()

		stopCapture()
		applyDefaults()
		refreshAllSettings() -- сюда же входит обновление биндов

		-- Сброс трогает только настройки, тумблеры читов не выключает.
		-- Гасим ESP-объекты: следующий кадр вернёт то, что должно быть видно.
		if state.esp then
			applyEsp(false)
		end

		if state.list then
			updateList()
		end

		-- Файл НЕ перезаписываем: сброс - это изменение как любое другое,
		-- сохранять его или нет, решает пользователь кнопкой.
		markDirty()
	end)
end

makeNote(
	"Сброс возвращает значения из кода и не выключает включённые читы. "
		.. "В файл он сам не пишется - нажми «Сохранить», если сброс нужен насовсем."
)

refreshConfigStatus()
showTab("cheats")

closeButton.MouseButton1Click:Connect(function()
	main.Visible = false
end)

-- Перетаскивание окна за шапку
do
	local dragging, dragStart, startPos = false, nil, nil

	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)
end

--=========================== ПЕРСОНАЖ ===========================

local function bindCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid", 10)
	rootPart = char:WaitForChild("HumanoidRootPart", 10)

	if not (humanoid and rootPart) then
		warn("[AdminMenu] персонаж загрузился без Humanoid/HumanoidRootPart")
		return
	end

	-- старые ссылки указывают на удалённые объекты
	flyForces = nil
	table.clear(collisionCache)
	clearInvisibleCache()

	--[[
		Роль пересчитываем сразу: новый персонаж = новый раунд, и от роли
		зависит, работают ли автоблок с предупреждением. Делать это только
		по таймеру нельзя - первые секунды раунда меню показывало бы
		состояние предыдущего.
	]]
	updateSelfRole()

	-- Способности выдаются заново каждый раунд, и модели киллеров тоже другие
	table.clear(autoblockTriggered)
	autoblockLastPress = 0
	pendingPress = nil
	--[[
		Выборка дистанций тоже сбрасывается: в новом раунде киллер другого
		вида, с другим вылетом удара, и подгонять зону по чужим замерам
		хуже, чем начать с нуля. Счётчики ударов НЕ сбрасываем - по ним
		удобно судить о настройке за всю сессию.
	]]
	table.clear(hitboxSamples)
	-- Зона висела на старом руте, её надо перевесить на новый
	destroyZones()
	resolveBlock()
	if state.autoblock then
		updateZones()
	end
	refreshAutoblockStatus()

	if humanoid.MaxHealth < GOD_HEALTH then
		originalMaxHealth = humanoid.MaxHealth
	end

	if state.god then
		applyGod(true)
	end
	if state.fly then
		applyFly(true)
	end
	--[[
		Стамину переустанавливаем обязательно: слушатель висел на СТАРОМ
		персонаже, а плейс выдаёт новому свой MaxStamina. Без этого чит
		переставал работать после первой же смерти или нового раунда - в
		esp.txt по той же причине висит CharacterAdded.
	]]
	if state.stamina then
		applyStamina(true)
	end
	--[[
		Невидимость тоже переустанавливаем: анимация играла на СТАРОМ
		Humanoid, а камера была привязана к старому руту. Без этого после
		смерти тумблер горел бы ON при полностью видимом персонаже.
	]]
	if state.invisible then
		applyInvisible(true)
	end
	-- Автоблок мог быть выключен ролью в прошлом раунде: перезапускаем его
	-- по фактическому состоянию тумблера
	if state.autoblock then
		applyAutoblock(true)
	end
	refreshToggle("autoblock")
	refreshToggle("warning")
	refreshWarningVisibility()
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

--=========================== ВВОД ===========================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	-- Своё же эмулированное нажатие блока: клавиша слота может совпасть
	-- с биндом меню (E - ESP, T - список), и тумблер щёлкал бы сам.
	if isSyntheticPress(input.KeyCode) then
		return
	end

	-- Захват бинда работает даже когда ввод съеден интерфейсом,
	-- иначе клик по кнопке бинда пришлось бы делать дважды.
	if captureBindId then
		assignBind(captureBindId, input.KeyCode)
		return
	end

	if gameProcessed then
		return
	end

	if input.KeyCode == BINDS.menu then
		main.Visible = not main.Visible
		if main.Visible then
			refreshConfigStatus()
			resolveBlock()
			refreshAutoblockStatus()
			refreshToggle("autoblock")
		end
		return
	end

	for _, feature in ipairs(FEATURES) do
		if input.KeyCode == BINDS[feature.id] then
			toggleFeature(feature.id)
			return
		end
	end
end)

--=========================== ОСНОВНОЙ ЦИКЛ ===========================

local function getFlyDirection()
	if UserInputService:GetFocusedTextBox() then
		return Vector3.zero
	end

	local cf = getCamera().CFrame
	local direction = Vector3.zero

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		direction += cf.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		direction -= cf.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		direction -= cf.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		direction += cf.RightVector
	end
	if UserInputService:IsKeyDown(FLY_KEYS.Up) then
		direction += Vector3.yAxis
	end
	if UserInputService:IsKeyDown(FLY_KEYS.Down) then
		direction -= Vector3.yAxis
	end

	if direction.Magnitude > 0 then
		direction = direction.Unit
	end
	return direction
end

RunService.Stepped:Connect(function()
	--[[
		Авто-бег идёт ДО раннего выхода по персонажу: на смерти/респавне
		персонажа нет, но зажатую клавишу надо отпустить, а не выйти с ней.
	]]
	autobrunStep()

	if not (character and character.Parent and humanoid and rootPart) then
		return
	end

	if state.noclip then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				if collisionCache[part] == nil then
					collisionCache[part] = true
				end
				part.CanCollide = false
			end
		end
	end

	if state.god then
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = humanoid.MaxHealth
		end
	end

	if state.fly then
		if not flyForces then
			applyFly(true)
		end
		if flyForces then
			flyForces.velocity.Velocity = getFlyDirection() * FLY.Speed
			flyForces.gyro.CFrame = getCamera().CFrame
			humanoid.PlatformStand = true
		end
	end

	-- Автоблок проверяется каждый кадр: на телеграф даётся 280 мс, и
	-- отдельный таймер здесь только съел бы часть запаса.
	if state.autoblock then
		autoblockStep()
	end
end)

-- ESP рисуется в RenderStepped, чтобы метки не дрожали относительно камеры
local listAccumulator = 0

RunService.RenderStepped:Connect(function(deltaTime)
	if state.esp then
		updateEsp()
	end

	-- Список - текст, ему хватает LIST.Interval. Каждый кадр гонять сортировку
	-- по всем игрокам незачем, а мигать цифры при 10 Гц не успевают.
	if state.list then
		listAccumulator += deltaTime
		if listAccumulator >= LIST.Interval then
			listAccumulator = 0
			updateList()
		end
	end

	--[[
		Слот блока и клавишу переискиваем по таймеру, а не по событию.
		Атрибуты Ability<N> появляются не одновременно с персонажем (в логе
		между спавном и выдачей набора проходило несколько секунд), а кнопка
		в RoundUI.PlayerUI.Abilities.Folder создаётся ещё позже. Слушать
		AttributeChanged на каждое имя пришлось бы вслепую, поэтому проще
		опрашивать четыре раза в секунду - это две проверки атрибутов.
		Заодно тут же обновляется таймер кулдауна в строке статуса.
	]]
	autoblockScanAccumulator += deltaTime
	if autoblockScanAccumulator >= AUTOBLOCK.ScanInterval then
		autoblockScanAccumulator = 0
		if character and character.Parent then
			resolveBlock()
		end
		--[[
			Здесь же пересчитывается своя роль. Персонаж при смене раунда
			не всегда создаётся заново (плейс переносит модель между
			папками Teams.<Команда>), поэтому одного CharacterAdded не
			хватает. Если роль изменилась - переприменяем автоблок: у
			киллера он должен погаснуть, у выжившего подняться.
		]]
		if updateSelfRole() then
			if state.autoblock then
				applyAutoblock(true)
			end
			refreshToggle("autoblock")
			refreshToggle("warning")
			refreshWarningVisibility()
		end
		if main.Visible then
			refreshAutoblockStatus()
			refreshToggle("autoblock")
			-- Статус авто-бега в темпе 4 Гц, рядом с автоблоковским
			if runStatusLabel and runStatusLabel.Parent then
				refreshRunStatus(runStatusLabel)
			end
		end
	end

	-- Баннер о киллере: свой шаг по времени, стамина приходит не каждый кадр
	updateWarning(deltaTime)

	--[[
		Зона и подсветки хитбоксов - в RenderStepped, а не в Stepped: это
		графика, и обновлять её надо в темпе кадров.
		Условие на state.autoblock снаружи, чтобы выключенный автоблок не
		стоил вообще ничего - но зона всё равно должна успеть исчезнуть,
		поэтому destroyZones вызывается из applyAutoblock.
	]]
	if state.autoblock then
		updateZones()
		clearHitboxFlashes(false)
		expirePendingPress()
	end
end)

--[[
	ЗАМЕТКИ ПО ОГРАНИЧЕНИЯМ (важно понимать, что именно ты получил)

	1. Godmode здесь локальный. Клиент может менять Humanoid.Health у своего
	   персонажа, но на сервер это не репликуется. Если урон наносит серверный
	   скрипт (Kill Brick, оружие, ловушки), сервер всё равно тебя убьёт.
	   Настоящий godmode делается только на сервере.
	   Также он не спасает от падения ниже Workspace.FallenPartsDestroyHeight -
	   там части персонажа просто удаляются.

	2. Fly и Noclip работают по-настоящему, потому что физикой своего персонажа
	   владеет клиент. Сервер увидит новую позицию. Но если у тебя есть
	   анти-чит, он может засчитать это как нарушение - добавь себя в исключения.

	3. Проверки по UserId в скрипте НЕТ - она убрана по просьбе. Меню
	   откроется у любого, кто запустил файл. Раньше список ADMIN_USER_IDS
	   отсекал случайного игрока, которому файл попал в руки; защитой от
	   читера он не был никогда, потому что клиентскую проверку обходят
	   правкой одной строки. Практический вывод тот же, что и был: ничего
	   секретного в этот скрипт не добавляй, а сам файл не раздавай, если
	   это не задумано.

	4. ESP видит только тех игроков, чьи персонажи существуют на клиенте.
	   Если в плейсе включён Workspace.StreamingEnabled, далёкие модели могут
	   быть не загружены - такие игроки не отобразятся, и это не баг скрипта.
	   Highlight, BillboardGui и трейсеры создаются локально, другие игроки
	   и сервер их не видят.

	   УКАЗАТЕЛИ 360 («Указатели 360», вкладка ESP, по умолчанию включены)
	   закрывают главную дыру обычного ESP: подсветка и метка существуют
	   только для того, что попало в кадр, а киллер заходит со спины -
	   и для ESP его в этот момент нет вообще. Пока цель вне видимой
	   области, у края экрана горит стрелка в её сторону с именем
	   и дистанцией.
	   Направление считается ПО КАМЕРЕ (проекции направления на
	   RightVector/UpVector), а НЕ по экранной позиции: для точки за
	   камерой WorldToViewportPoint зеркалит координаты, и стрелка
	   показывала бы в сторону, куда поворачиваться дольше.
	   Цена такого способа: цель на 90 и на 170 градусов вправо дают
	   одинаковое направление стрелки - за расстоянием отвечает подпись.
	   Строго за спиной стрелка ставится вниз.
	   Фильтры общие с остальным ESP: радиус, «Скрывать союзников», мёртвые
	   и метка Caretaker действуют и на указатели.

	   МЕТКА CARETAKER (сиреневый цвет + подпись [CARETAKER]) определяется
	   по предмету Character.Vanities.CaretakerItem - как в esp.txt, но БЕЗ
	   проверки Transparency: метка держится весь раунд, включая время после
	   применения способности (в esp.txt и в прежней версии этого скрипта
	   проверка стояла, и метка исчезала в момент использования).
	   Атрибута с именем способности в плейсе нет, поэтому предмет -
	   единственный известный признак: если сборка переименует его, метка
	   просто не появится, молча.
	   Носитель Caretaker показывается даже при включённом «Скрывать
	   союзников»: он выживший, то есть чаще всего союзник, и фильтр прятал
	   бы ровно того, кого просили видеть.

	   ЦВЕТ МЕТОК - ЦВЕТ КОМАНДЫ из той же таблицы, что красит список
	   игроков: выжившие голубые, киллер красный, призраки и лобби серые.
	   Раньше у ESP была своя пара «союзник/враг» по Player.Team, а в этом
	   плейсе Player.Team пустой у всех - поэтому красным светились все
	   подряд. Команда берётся из иерархии (GameAssets.Teams.<Команда>),
	   и от неё же теперь зависит фильтр «Скрывать союзников», который
	   по той же причине раньше не работал вообще.

	   ТРЕЙСЕР И СТРЕЛКА целятся в СЕРЕДИНУ КОРПУСА: UpperTorso/Torso, а
	   если таких частей нет - центр габаритов модели. Не в HumanoidRootPart:
	   у кастомных моделей плейса она лежит у ступней, и линия приходила
	   в ноги. Дистанция в метке считается до той же точки.

	5. Бинды и настройки сохраняются ПО КНОПКЕ на вкладке «Конфиг» - в ДВА
	   места, и это разные уровни памяти.
	   Файл AdminMenu/<имя профиля>.json - его умеет писать только executor
	   (writefile/readfile). Таблица getgenv() - память клиента Roblox, она
	   есть почти у всех executor'ов и не может отказать.
	   Что это значит на практике: без writefile настройки всё равно
	   переживают перезапуск скрипта и смену раунда, теряются только при
	   выходе из игры. С writefile - переживают и это. При загрузке файл
	   имеет приоритет над памятью. Строка на вкладке «Конфиг» пишет, какой
	   случай у тебя сейчас; в Studio не бывает ни того, ни другого.

	   АВТОСОХРАНЕНИЯ НЕТ (тоже по просьбе). Любое изменение настройки
	   зажигает точку на кнопке «Сохранить» - это и есть признак
	   несохранённых изменений; закрытие меню или смена раунда их не
	   записывают. Кнопка «Загрузить» читает профиль с текущим именем и
	   заново применяет всё, что уже работает (зоны, список, слушатель
	   стамины) - иначе настройки в файле и поведение в игре расходились бы.
	   Имя профиля меняется в поле над кнопками, профилей можно держать
	   сколько угодно; имя санируется до букв, цифр, дефиса и подчёркивания,
	   так что "../что-нибудь" файл вне папки executor'а не создаст. Список
	   уже сохранённых профилей показывается, если у executor'а есть
	   listfiles; иначе строка просто пустая, а не «профилей нет».
	   Сброс настроек тоже сам в файл не пишется - он такое же изменение,
	   как любое другое.
	   Сам json лежит открытым текстом в папке executor'а: любой, у кого есть
	   доступ к машине, прочтёт и поправит его. Ничего чувствительного там
	   быть не должно - впрочем, как и в самом скрипте (см. п. 3).
	   Состояние читов намеренно НЕ сохраняется: восстановленный на спавне fly
	   или god - это мгновенная заявка о себе анти-читу.

	6. Меню рассчитано на ПК (клавиатура). Для мобильных нужны экранные кнопки
	   движения - можно добавить отдельно.

	7. Стамина в списке игроков читается из атрибута персонажа
	   StaminaServer - это не стандартное свойство Roblox, а особенность
	   конкретного плейса: в штатном API стамины нет вообще.
	   Именно StaminaServer, а не Stamina: сервер репликует всем клиентам
	   только его. Локальный Stamina есть лишь у своего персонажа, поэтому
	   у чужих игроков он читался бы как пустой.
	   Максимум стамины чужих игроков сервер не репликует вовсе, он берётся
	   из таблицы KILLER_MAX_STAMINA по атрибуту KillerName: 114 у Harken,
	   110 у Pursuer/Killdroid/Badware, иначе 100. Если у персонажа включена
	   бесконечная стамина, дробь не строится - печатается одно число или "∞".
	   Если сборка плейса назвала атрибут иначе, колонка покажет прочерки,
	   а в консоль (F9) уйдёт предупреждение со ПОЛНЫМ списком атрибутов
	   персонажа - нужное имя дописывается в STAMINA_KEYS в начале файла.

	   БЕСКОНЕЧНАЯ СТАМИНА (тумблер, по умолчанию H) устроена иначе, чем
	   godmode, и работает по-настоящему. Своему персонажу ставится атрибут
	   MaxStamina = math.huge, и клиентский код плейса - тот самый, который
	   тратит и восполняет стамину - начинает считать её от бесконечности.
	   Мы не подделываем чужое значение, а меняем предел у того, кто это
	   значение вычисляет, поэтому сервер видит ту же стамину, что и мы.
	   Держится на GetAttributeChangedSignal: плейс переписывает MaxStamina
	   сам, и одного присваивания не хватит. При новом персонаже слушатель
	   переустанавливается (иначе чит умирал бы после первой смерти).
	   Заодно снимается атрибут Fatigue - без этого спринт остаётся
	   запрещённым при полной полоске.
	   Чего это НЕ даёт: скорости бега выше штатной. Если плейс ограничит
	   спринт через DisableSprint или WalkSpeedModifier, стамина не поможет.

	8. Команда определяется по иерархии: workspace.GameAssets.Teams.<Команда>
	   во время раунда и GameAssets.Other.LobbyPlayers до его начала.
	   Штатные Player.Team в этом плейсе не используются, но остались
	   запасным вариантом. В плейсе с другой структурой все попадут
	   в группу "БЕЗ КОМАНДЫ" - поправь TEAM_FOLDER_PARENT, LOBBY_FOLDER
	   и TEAM_ORDER.

	9. Автоблок. Что он делает: видит на модели киллера атрибут
	   UsingAbility = true и сразу отправляет нажатие клавиши блока.
	   Замеры по живому логу этого плейса:
	     - обычный M1: телеграф -> урон 280 мс;
	     - спецприём с раскидыванием: 570 мс;
	     - эмуляция нажатия доходит за 105-180 мс;
	     - блок держится 1 с, перезарядка 35 с.
	   Запас около 100 мс. При лаге выше этого блок опоздает - это предел
	   способа, а не ошибка кода.

	   Требуется executor. Нажатие идёт через VirtualInputManager, обычному
	   LocalScript этот сервис недоступен: тумблер станет серым с надписью
	   "нет доступа к вводу", а причина уйдёт в консоль (F9). Ремоут
	   ReplicatedStorage.Events.RemoteFunctions.UseAbility существует, и
	   технически блок можно ставить им, но тогда сервер получает вызов,
	   которого не было в клиентском вводе - это заметно куда сильнее.

	   Способности в этом плейсе рандомные каждый раунд, блок может лежать
	   в любом слоте или не выпасть вовсе. Слот ищется в атрибутах
	   Ability1..AbilityN своего персонажа, клавиша - в тексте кнопки
	   RoundUI.PlayerUI.Abilities.Folder.Block.Input, и только если её нет -
	   по номеру слота из SLOT_KEYS. Если блока в раунде нет, строка статуса
	   так и напишет; ждать нечего, это раздача.

	   Триггер именно UsingAbility. WalkSpeedModifier киллера для этого
	   НЕ годится (в готовых скриптах из интернета ждут 7.5): при обычном
	   M1 он остаётся ровно 0. Ждать появления хитбокса тоже нельзя - он
	   создаётся в тот же кадр, что и урон.

	   САМОЕ ВАЖНОЕ - НА ЧТО ОН НЕ РЕАГИРУЕТ. Блок держится 1 с, а кулдаун
	   35 с: одно лишнее нажатие оставляет тебя без защиты на полминуты.
	   Поэтому проверяется и дистанция, и направление взгляда киллера:
	     - "Ближний бой" (14 м по умолчанию) - мягкий конус ~72 градуса.
	       В логе попадания были с 5.5 и 4.9 студов, промахи с 8.4 и 8.5,
	       но киллер доворачивается уже во время замаха, поэтому сектор
	       широкий. ЭТО И ЕСТЬ ЖЁСТКАЯ ГРАНИЦА: дальше неё автоблок не
	       срабатывает вообще;
	     - "Блокировать дальние атаки" - ВЫКЛЮЧЕНО по умолчанию. Это режим
	       для стреляющих киллеров: до "Дальние атаки" (24 м) и с жёстким
	       конусом ~20 градусов. Именно на дальних атаках блок и уходил
	       впустую, поэтому включать осознанно.
	   Плюс гейты по своим атрибутам: если Blocking уже true или
	   BlockCooldown больше нуля, нажатие не отправляется вообще.
	   При двух киллерах в раунде реагируем на ближнего.

	   ЗОНА ВИДНА В МИРЕ ("Показывать зону"). Зелёный диск под ногами -
	   ближний бой, жёлтый - дальние атаки, если режим включён. Рисуется
	   адорнментами: ни физики, ни коллизий, и кроме тебя её никто не
	   видит. Диск плоский потому, что зона и проверяется по горизонтали.

	   ХИТБОКСЫ ПРОВЕРЯЮТСЯ ПОСТОЯННО, но не как триггер - как измеритель.
	   Появление объекта с "hitbox" в имени ловится через
	   workspace.DescendantAdded, дальше считается расстояние от тебя до
	   ближней точки этой зоны. Если она тебя накрыла, удар пошёл в
	   статистику, а сама зона на мгновение подсвечивается красным.
	   Вторая строка в меню показывает: сколько ударов тебя накрыло,
	   сколько из них попало в СТОЯЩИЙ блок, сколько нажатий ушло впустую
	   (нажали - хитбокс не пришёл), и с какой дистанции реально бьют.
	   По этим числам и видно, работает автоблок или мажет.

	   "Подгонять зону по ударам" - зона ближнего боя сама подстраивается
	   под медиану последних попаданий плюс запас. Медиана, а не среднее:
	   один удар с рывка не должен задирать границу. Меняется по одному
	   шагу за раз, чтобы было видно, что происходит. Нужно потому, что
	   замерен был только Harken, а вылет удара у каждого вида свой.
	   Все настройки зон сохраняются (см. п. 5), поэтому подстроенная
	   граница не сбрасывается между раундами и перезапусками. Сбрасывается
	   только выборка последних замеров: новый раунд - другой киллер, и
	   подгонять зону по чужим числам хуже, чем начать заново.

	   Если блок всё равно уходит впустую - уменьшай "Ближний бой" или
	   выключи "Блокировать дальние атаки". Если не срабатывает на явный
	   удар - смотри "худший" в замерах и подними зону до него.

	   Клавиши слотов пересекаются с биндами меню: E - это и ESP, и второй
	   слот способностей. Своё эмулированное нажатие скрипт отличает от
	   настоящего и тумблер не переключает. Наоборот - не может: когда ты
	   сам жмёшь E, игра тратит способность. Если строка статуса написала
	   "КОНФЛИКТ", перевесь бинд меню на другую клавишу.

	   ЕСЛИ ТЫ САМ КИЛЛЕР, автоблок и предупреждение выключаются на весь
	   раунд: у киллера блока нет вообще, и нажатие уходило бы в чужую
	   способность, тратя её впустую. Тумблеры при этом остаются включёнными
	   и пишут "[ты киллер]" - в следующем раунде роль сменится, и всё
	   поднимется само, без повторного щелчка. Роль читается тем же
	   способом, что и список игроков (папка workspace.GameAssets.Teams),
	   и пересчитывается четыре раза в секунду плюс на каждом спавне: одного
	   CharacterAdded не хватает, потому что плейс иногда переносит ту же
	   модель между папками команд.

	10. ПРЕДУПРЕЖДЕНИЕ О КИЛЛЕРЕ (тумблер, по умолчанию K) - баннер сверху
	   экрана: дистанция до ближайшего живого киллера, его имя и стамина.
	   Цвет считается по СКОРОСТИ изменения стамины, а не по её величине:
	   падает -> красный (тратит, то есть бежит или атакует), растёт или
	   стоит на месте -> зелёный. Полная стамина у стоящего и у
	   разгоняющегося выглядит одинаково, поэтому величина здесь ничего не
	   говорит. Порог WARNING.Epsilon = 0.35 нужен потому, что StaminaServer
	   реплицируется рывками: без порога любой кадр без обновления читался
	   бы как «стамина стоит». Первый замер всегда зелёный - для производной
	   одной точки не хватает, а красный по умолчанию пугал бы на пустом
	   месте.
	   Это не чит: читается то, что сервер и так репликует всем клиентам.
	   Но и не гарантия: если StaminaServer в сборке назван иначе, вместо
	   числа будет прочерк, а цвет останется зелёным.

	11. НЕВИДИМОСТЬ (тумблер, по умолчанию J) - приём из esp.txt: играется
	   анимация rbxassetid://90444351114401, останавливается на кадре 2.2, и
	   персонаж физически уезжает из своей видимой модели. Для остальных на
	   месте остаётся пустая оболочка.
	   Почему не LocalTransparencyModifier: тот прячет модель только у тебя,
	   для других ничего не меняется, и как чит бесполезен. Анимации,
	   наоборот, реплицируются сервером, поэтому эффект видят все.
	   Вместе с анимацией камера привязывается к HumanoidRootPart (иначе она
	   уедет за брошенной моделью и будет смотреть в пустоту) и снимаются
	   коллизии со всего, кроме рута (иначе невидимое тело цепляется за
	   геометрию, и это заметно со стороны).
	   Главное ограничение: способ держится на конкретном анимационном
	   ассете, а не на гарантии Roblox. Патч плейса или удаление ассета
	   ломают его молча - в консоль (F9) уйдёт предупреждение, если анимация
	   не загрузилась. Из всего, что есть в этом файле, это самая хрупкая
	   функция, и в бою на неё лучше не полагаться. В комбате не проверялась.

	12. Окно меню широкое, с вкладками слева. Каждая вкладка - отдельный
	   ScrollingFrame, поэтому позиция прокрутки в одной не сбивается при
	   переходе в другую. Позиция самого окна между запусками не
	   сохраняется - только настройки.

	13. АИМ НА КИЛЛЕРА (40_auto). Камера доворачивается за ближайшим ЖИВЫМ
	   киллером по горизонтали, вертикаль остаётся под мышкой (просьба
	   пользователя). Направление считается ПО ОСЯМ КАМЕРЫ, а не по
	   WorldToViewportPoint: проекция точки за камерой зеркалится (та же
	   причина, по которой 360-указатели считают по проекциям направления).
	   Знак поворота: CFrame.Angles(0, theta, 0), положительный theta =
	   влево; atan2(crossY, dot) даёт именно его. BindToRenderStep на
	   Camera.Value + 1 ОБЯЗАТЕЛЬНО: дефолтный контроллер пишет CFrame на
	   Camera (200) и затёр бы запись из обычного RenderStepped.
	   Unit нулевого вектора в Roblox НЕ бросает, а даёт NaN - поэтому
	   Magnitude проверяется ДО нормировки, вырожденный кадр пропускается.
	   Точка цели - aimPointOf (экспортирован из блока ESP форвард-локалом,
	   тот же приём, что у teamNameOf). В бою НЕ ПРОВЕРЕНО.

	14. АВТО-БЕГ И МЕНЕДЖМЕНТ СТАМИНЫ (40_auto). Скрипт сам зажимает
	   клавишу спринта (BINDS.autobrun, по умолчанию LeftShift,
	   переназначается). Менеджмент = пороги с гистерезисом: стамина
	   <= Low (30) - отпускает, >= Low + Resume (15) - зажимает.
	   ПАНИКА: киллер ближе PanicDistance (25 м) - порог игнорируется,
	   становится PanicFloor (1-5): стамина не спускается до нуля
	   (просьба пользователя). Клавиша - через VirtualInputManager, тем
	   же паттерном, что автоблок (метка syntheticKey ДО отправки,
	   отпускание с копией клавиши, состояние то же). Гейты: полёт ->
	   НЕ трогать клавишу (LeftShift в полёте = ВНИЗ, FLY_KEYS), смерть/
	   респавн -> отпустить, нет ввода -> тумблер серый. runDecision -
	   чистая функция, тестируется вырезанием. Стамина читается через
	   STAMINA_KEYS (StaminaServer первым). ЧТО НЕ ДЕЛАЕТ: скорость бега
	   выше штатной (плейс режет спринт отдельными атрибутами - см.
	   esp.txt «No Speed Debuffs», не сделано). В бою НЕ ПРОВЕРЕНО.
]]
