--=========================== КОНФИГ: ДОСТУП К ФАЙЛАМ ===========================

--[[
	LocalScript в обычном клиенте и в Studio НЕ умеет писать файлы на диск -
	такого API у Roblox нет. Функции readfile/writefile/isfile появляются
	только если скрипт запущен через executor (KRNL, Synapse, Delta и т.п.),
	который их инжектит в окружение.

	Поэтому здесь автодетект: если API есть - настройки пишутся в файл и
	переживают перезаход; если нет - живут только в текущей сессии, и меню
	честно пишет об этом строкой статуса.
]]

--[[
	ПРОФИЛИ КОНФИГА.

	Раньше был один файл config.json и запись «сама» после каждого клика.
	Теперь: имя профиля задаётся в меню, сохранение - ТОЛЬКО по кнопке
	(по просьбе пользователя).

	Что это меняет по сути: настройки в памяти и настройки на диске могут
	расходиться, поэтому появился флаг «есть несохранённые изменения» и
	кнопка, которая честно показывает это состояние. Автозаписи больше нет
	нигде - ни в тумблерах, ни в степперах, ни в автоподгонке зоны.

	Имя файла санируется: в него пускаются только буквы, цифры, дефис и
	подчёркивание. Иначе имя вида "../../something" писало бы файл куда
	угодно, а имя со слэшем просто не создалось бы.
]]
--[[
	ВСЯ РАБОТА С КОНФИГОМ ЗАВЁРНУТА В do-БЛОК.

	Причина техническая: Luau разрешает не больше 200 локальных переменных
	на верхнем уровне функции, и скрипт в этот лимит упёрся (ошибка
	"Out of local registers"). Внутренности конфига - самая изолированная
	часть файла: наружу нужны считанные имена, всё остальное живёт только
	внутри. Поэтому они объявлены ниже как forward-локальные, а тела
	спрятаны в блок.

	Не разворачивать обратно: лимит вернётся.
]]
local configName = "default"
local sanitizeConfigName, configPathFor, currentConfigPath
local loadConfig, saveConfig, markDirty, listProfiles
local configDirty, writeFailed = false, false
local hasFileApi, hasAnyStore, hasSessionStore = false, false, false
local configLoaded, configSource
local onConfigDirtyChanged = nil -- ставится после сборки меню
local DEFAULTS, BIND_IDS, keyCodeFromName
local RUN -- заполняет 40_auto; applyRunFromConfig должен видеть таблицу по ссылке

do
	local CONFIG_FOLDER = "AdminMenu"
	local CONFIG_VERSION = 1
	local DEFAULT_CONFIG_NAME = "default"
	local CONFIG_NAME_MAX = 32

	configName = DEFAULT_CONFIG_NAME

	function sanitizeConfigName(name)
		if type(name) ~= "string" then
			return nil
		end
		-- gsub возвращает две величины, лишняя сломала бы конкатенацию ниже
		local cleaned = name:gsub("[^%w%-_]", "")
		cleaned = cleaned:sub(1, CONFIG_NAME_MAX)
		if cleaned == "" then
			return nil
		end
		return cleaned
	end

	function configPathFor(name)
		return CONFIG_FOLDER .. "/" .. (sanitizeConfigName(name) or DEFAULT_CONFIG_NAME) .. ".json"
	end

	function currentConfigPath()
		return configPathFor(configName)
	end

	local function asFunction(value)
		return type(value) == "function" and value or nil
	end

	local FS_NAMES = {
		"readfile",
		"writefile",
		"isfile",
		"isfolder",
		"makefolder",
		"appendfile",
		"listfiles",
		"delfile",
	}

	--[[
		Где искать функции executor'а. Порядок важен.

		1. Окружение самого скрипта. Именно сюда executor'ы кладут свои глобалы,
		   и именно этот вариант работает почти всегда. Чтение несуществующего
		   глобала в Luau возвращает nil, ошибки не будет.
		2. getgenv() - общая таблица глобалов, если executor её предоставляет.
		3. _G - последняя попытка. У Roblox это ОТДЕЛЬНАЯ таблица, и функций
		   executor'а в ней обычно НЕТ; полагаться на неё одну нельзя.

		getfenv намеренно не используется: он отключает оптимизацию замыканий
		во всём скрипте, а ESP крутится каждый кадр.
	]]
	local function gatherSources()
		local sources = {}

		-- 1. прямое чтение глобалов окружения скрипта
		local okDirect, direct = pcall(function()
			return {
				readfile = readfile,
				writefile = writefile,
				isfile = isfile,
				isfolder = isfolder,
				makefolder = makefolder,
				appendfile = appendfile,
				listfiles = listfiles,
				delfile = delfile,
			}
		end)
		if okDirect and type(direct) == "table" then
			table.insert(sources, direct)
		end

		-- 2. getgenv(), сам getgenv тоже читается как обычный глобал
		local okEnv, env = pcall(function()
			local get = asFunction(getgenv)
			return get and get() or nil
		end)
		if okEnv and type(env) == "table" then
			table.insert(sources, env)
		end

		-- 3. _G
		if type(_G) == "table" then
			table.insert(sources, _G)
		end

		return sources
	end

	-- Индексирование обычное, а не rawget: часть executor'ов проксирует
	-- окружение метатаблицей, из которого rawget ничего не достанет.
	local function pickFunction(sources, name)
		for _, source in ipairs(sources) do
			local ok, value = pcall(function()
				return source[name]
			end)
			local fn = ok and asFunction(value) or nil
			if fn then
				return fn
			end
		end
		return nil
	end

	local fs = {}
	do
		local sources = gatherSources()
		for _, name in ipairs(FS_NAMES) do
			fs[name] = pickFunction(sources, name)
		end
	end

		-- Минимум для работы: прочитать и записать. isfile/isfolder/makefolder
		-- опциональны, обходные пути ниже.
		hasFileApi = (fs.readfile ~= nil) and (fs.writefile ~= nil)

	--[[
		ВТОРОЙ УРОВЕНЬ ПАМЯТИ: таблица getgenv().

		Файл переживает всё, но writefile есть не у каждого executor'а. Зато
		getgenv() живёт, пока открыт клиент Roblox: скрипт можно перезапустить,
		можно пережить смену раунда - таблица останется.

		Практический смысл: без файлового API настройки зон раньше терялись
		при каждом перезапуске скрипта. Теперь теряются только при выходе из
		игры.
	]]
	local SESSION_KEY = "__AdminMenuConfig"
	local SESSION_NAME_KEY = "__AdminMenuConfigName"
	local sessionStore = nil
	do
		local ok, env = pcall(function()
			local get = asFunction(getgenv)
			return get and get() or nil
		end)
		if ok and type(env) == "table" then
			sessionStore = env
		end
	end

		local hasAnyStoreLocal = hasFileApi or (sessionStore ~= nil)
		hasAnyStore = hasAnyStoreLocal
		hasSessionStore = sessionStore ~= nil

	local HttpService = game:GetService("HttpService")

	local function ensureConfigFolder()
		if not (fs.isfolder and fs.makefolder) then
			return -- многие executor'ы создают папку сами при writefile
		end
		local ok, exists = pcall(fs.isfolder, CONFIG_FOLDER)
		if ok and not exists then
			pcall(fs.makefolder, CONFIG_FOLDER)
		end
	end

	-- Возвращает содержимое конфига или nil. isfile есть не у всех, поэтому
	-- при его отсутствии просто пробуем прочитать: ошибка = файла нет.
	local function readConfigFile(path)
		if not hasFileApi then
			return nil
		end

		path = path or currentConfigPath()

		if fs.isfile then
			local okExists, exists = pcall(fs.isfile, path)
			if okExists and not exists then
				return nil
			end
		end

		local okRead, raw = pcall(fs.readfile, path)
		if not okRead or type(raw) ~= "string" then
			return nil
		end
		return raw
	end

	-- Тот же JSON, но из памяти клиента. Строка, а не таблица: одинаковый
	-- разбор для обоих источников, и случайная ссылка на живую таблицу
	-- настроек не утечёт в getgenv.
	local function readConfigSession()
		if not sessionStore then
			return nil
		end
		local ok, raw = pcall(function()
			return sessionStore[SESSION_KEY]
		end)
		if ok and type(raw) == "string" and raw ~= "" then
			return raw
		end
		return nil
	end

	--=========================== КОНФИГ: ДЕФОЛТЫ ===========================

	-- Снимок значений из таблиц выше. Снимается ДО применения файла, поэтому
	-- кнопка "Сброс настроек" возвращает именно то, что написано в коде.
	DEFAULTS = {
		binds = table.clone(BINDS),
		flySpeed = FLY.Speed,
		esp = {
			Highlight = ESP.Highlight,
			Names = ESP.Names,
			Health = ESP.Health,
			Distance = ESP.Distance,
			Tracers = ESP.Tracers,
			OffScreen = ESP.OffScreen,
			TeamCheck = ESP.TeamCheck,
			MarkCaretaker = ESP.MarkCaretaker,
			MaxDistance = ESP.MaxDistance,
			AimSpeed = ESP.AimSpeed,
		},
		list = {
			Distance = LIST.Distance,
			Stamina = LIST.Stamina,
			SortByDistance = LIST.SortByDistance,
			ShowSelf = LIST.ShowSelf,
		},
		autoblockRadius = AUTOBLOCK.Radius,
		autoblockReach = AUTOBLOCK.Reach,
		autoblockRanged = AUTOBLOCK.Ranged,
		autoblockShowZone = AUTOBLOCK.ShowZone,
		autoblockAutoTune = AUTOBLOCK.AutoTune,
		autoblockShowHits = HITBOX.ShowHits,
		staminaNoFatigue = STAMINA.NoFatigue,
		warningDistance = WARNING.Distance,
		run = {
			managed = false,
			low = 30,
			resume = 15,
			panicDistance = 25,
			panicFloor = 3,
		},
	}

	-- В файл попадает только то, что правится из меню. FLY.Step/Min/Max и
	-- ESP.DistanceStep/DistanceLimit/TracerThickness/FillTransparency/OffScreen*
	-- остаются константами кода: если их залочить в json, правки кода перестанут
	-- работать.
	local ESP_SAVED_FLAGS =
		{ "Highlight", "Names", "Health", "Distance", "Tracers", "OffScreen", "TeamCheck", "MarkCaretaker" }

	local ESP_JSON_KEYS = {
		Highlight = "highlight",
		Names = "names",
		Health = "health",
		Distance = "distance",
		Tracers = "tracers",
		OffScreen = "offScreen",
		TeamCheck = "teamCheck",
		MarkCaretaker = "markCaretaker",
	}

	local BIND_IDS_LOCAL = {
		"menu",
		"fly",
		"noclip",
		"god",
		"stamina",
		"invisible",
		"esp",
		"list",
		"autoblock",
		"warning",
		"aim",
		"autobrun",
	}
	BIND_IDS = BIND_IDS_LOCAL

	-- LIST.MaxRows/Interval/Width/Offset* тоже остаются константами кода:
	-- из меню правятся только четыре флага ниже.
	local LIST_SAVED_FLAGS = { "Distance", "Stamina", "SortByDistance", "ShowSelf" }

	local LIST_JSON_KEYS = {
		Distance = "distance",
		Stamina = "stamina",
		SortByDistance = "sortByDistance",
		ShowSelf = "showSelf",
	}

	--=========================== КОНФИГ: ЧТЕНИЕ ===========================

	-- Enum.KeyCode["мусор"] в Roblox не возвращает nil, а бросает ошибку,
	-- поэтому обязательно через pcall: иначе одна опечатка в json убивает скрипт.
	function keyCodeFromName(name)
		if type(name) ~= "string" or name == "" or name == "Unknown" then
			return nil
		end
		local ok, keyCode = pcall(function()
			return Enum.KeyCode[name]
		end)
		if ok and typeof(keyCode) == "EnumItem" then
			return keyCode
		end
		return nil
	end

	local function applyBindsFromConfig(binds)
		if type(binds) ~= "table" then
			return
		end

		local used = {} -- клавиша -> true, ловит дубли внутри файла
		for _, bindId in ipairs(BIND_IDS) do
			local keyCode = keyCodeFromName(binds[bindId])
			-- Дубль игнорируем: UI не допускает двух функций на одной клавише,
			-- нельзя грузить состояние, которое сам же считает недопустимым.
			if keyCode and not used[keyCode] then
				BINDS[bindId] = keyCode
			end
			used[BINDS[bindId]] = true
		end
	end

	local function applyFlyFromConfig(fly)
		if type(fly) ~= "table" then
			return
		end
		if type(fly.speed) == "number" and fly.speed == fly.speed then -- NaN отсекается
			FLY.Speed = math.clamp(math.floor(fly.speed), FLY.Min, FLY.Max)
		end
	end

	local function applyEspFromConfig(esp)
		if type(esp) ~= "table" then
			return
		end

		for _, key in ipairs(ESP_SAVED_FLAGS) do
			local value = esp[ESP_JSON_KEYS[key]]
			if type(value) == "boolean" then
				ESP[key] = value
			end
		end

		local maxDistance = esp.maxDistance
		if type(maxDistance) == "number" and maxDistance == maxDistance then
			ESP.MaxDistance = math.clamp(math.floor(maxDistance), 0, ESP.DistanceLimit)
		end

		-- Скорость аима (40_auto). Диапазон 60-1440: ниже 60 поворот заметно
		-- тупит, выше 1440 - мгновенный рывок на весь угол.
		local aimSpeed = esp.aimSpeed
		if type(aimSpeed) == "number" and aimSpeed == aimSpeed then
			ESP.AimSpeed = math.clamp(math.floor(aimSpeed), 60, 1440)
		end
	end

	-- Мутируем таблицы на месте: замыкания кнопок UI держат ссылки на них.
	local function applyListFromConfig(list)
		if type(list) ~= "table" then
			return
		end
		for _, key in ipairs(LIST_SAVED_FLAGS) do
			local value = list[LIST_JSON_KEYS[key]]
			if type(value) == "boolean" then
				LIST[key] = value
			end
		end
	end

	local function applyAutoblockFromConfig(autoblock)
		if type(autoblock) ~= "table" then
			return
		end
		local radius = autoblock.radius
		if type(radius) == "number" and radius == radius then
			AUTOBLOCK.Radius = math.clamp(math.floor(radius), AUTOBLOCK.RadiusMin, AUTOBLOCK.RadiusMax)
		end
		local reach = autoblock.reach
		if type(reach) == "number" and reach == reach then
			AUTOBLOCK.Reach = math.clamp(math.floor(reach), AUTOBLOCK.ReachMin, AUTOBLOCK.ReachMax)
		end
		if type(autoblock.ranged) == "boolean" then
			AUTOBLOCK.Ranged = autoblock.ranged
		end
		if type(autoblock.showZone) == "boolean" then
			AUTOBLOCK.ShowZone = autoblock.showZone
		end
		if type(autoblock.autoTune) == "boolean" then
			AUTOBLOCK.AutoTune = autoblock.autoTune
		end
		if type(autoblock.showHits) == "boolean" then
			HITBOX.ShowHits = autoblock.showHits
		end
	end

	local function applyStaminaFromConfig(stamina)
		if type(stamina) ~= "table" then
			return
		end
		if type(stamina.noFatigue) == "boolean" then
			STAMINA.NoFatigue = stamina.noFatigue
		end
	end

	local function applyWarningFromConfig(warning)
		if type(warning) ~= "table" then
			return
		end
		local distance = warning.distance
		if type(distance) == "number" and distance == distance then
			WARNING.Distance =
				math.clamp(math.floor(distance), WARNING.DistanceMin, WARNING.DistanceMax)
		end
	end

	-- Авто-бег / менеджмент стамины (40_auto). Секция появилась позже
	-- остальных: старые конфиги без неё просто пропускаются.
	-- RUN.MANAGED - тумблер: в конфиг пишется состояние, а не бинд.
	-- RUN объявлен ВЫШЕ (форвард-локал перед конфиг-блоком): applyRunFromConfig
	-- в замыкании task.defer должен захватить ТАБЛИЦУ, а не глобал. Таблицу
	-- заполняет 40_auto позже, замыкание видит её по ссылке.
	local function applyRunFromConfig(run)
		if type(run) ~= "table" or type(RUN) ~= "table" then
			return
		end
		if type(run.managed) == "boolean" then
			RUN.Managed = run.managed
		end
		if type(run.low) == "number" and run.low == run.low then
			RUN.Low = math.clamp(math.floor(run.low), 5, 90)
		end
		if type(run.resume) == "number" and run.resume == run.resume then
			RUN.Resume = math.clamp(math.floor(run.resume), 5, 40)
		end
		if type(run.panicDistance) == "number" and run.panicDistance == run.panicDistance then
			RUN.PanicDistance = math.clamp(math.floor(run.panicDistance), 10, 100)
		end
		if type(run.panicFloor) == "number" and run.panicFloor == run.panicFloor then
			RUN.PanicFloor = math.clamp(math.floor(run.panicFloor), 1, 5)
		end
	end

	-- Мутируем таблицы на месте: замыкания кнопок UI держат ссылки на них.
	local function applyConfigTable(data)
		applyBindsFromConfig(data.binds)
		applyFlyFromConfig(data.fly)
		applyEspFromConfig(data.esp)
		applyListFromConfig(data.list)
		applyAutoblockFromConfig(data.autoblock)
		applyStaminaFromConfig(data.stamina)
		applyWarningFromConfig(data.warning)
		applyRunFromConfig(data.run)
	end

	--[[
		Читает профиль и применяет его. Возвращает (успех, источник).

		Файл приоритетнее памяти: он новее по смыслу (в памяти может лежать
		снимок другого профиля, сделанный до переключения) и переживает
		перезапуск клиента.
	]]
		function loadConfig(name)
			local raw = readConfigFile(configPathFor(name or configName))
			local source = raw ~= nil and "file" or nil
			if raw == nil then
				raw = readConfigSession()
				source = raw ~= nil and "session" or nil
			end

			if raw == nil or raw == "" then
				return false, nil -- ничего не сохранено, нормальный первый запуск
			end

			local okDecode, data = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if not okDecode or type(data) ~= "table" then
				warn("[AdminMenu] конфиг повреждён, беру значения из кода: " .. currentConfigPath())
				return false, nil
			end

			applyConfigTable(data)
			return true, source
		end

	--=========================== КОНФИГ: ЗАПИСЬ ===========================

	local function buildConfigTable()
		local binds = {}
		for _, bindId in ipairs(BIND_IDS) do
			binds[bindId] = BINDS[bindId].Name -- Enum в JSON не кодируется, пишем имя
		end

		local esp = { maxDistance = ESP.MaxDistance, aimSpeed = ESP.AimSpeed }
		for _, key in ipairs(ESP_SAVED_FLAGS) do
			esp[ESP_JSON_KEYS[key]] = ESP[key]
		end

		local list = {}
		for _, key in ipairs(LIST_SAVED_FLAGS) do
			list[LIST_JSON_KEYS[key]] = LIST[key]
		end

		-- RUN может не существовать при стартовой загрузке (определяется в
		-- 40_auto, которое идёт позже): секция run тогда не пишется. Стартовая
		-- загрузка отложена через task.defer, поэтому на практике RUN живой.
		local runSection = nil
		if type(RUN) == "table" then
			runSection = {
				managed = RUN.Managed,
				low = RUN.Low,
				resume = RUN.Resume,
				panicDistance = RUN.PanicDistance,
				panicFloor = RUN.PanicFloor,
			}
		end

		return {
			version = CONFIG_VERSION,
			binds = binds,
			fly = { speed = FLY.Speed },
			esp = esp,
			list = list,
			autoblock = {
				radius = AUTOBLOCK.Radius,
				reach = AUTOBLOCK.Reach,
				ranged = AUTOBLOCK.Ranged,
				showZone = AUTOBLOCK.ShowZone,
				autoTune = AUTOBLOCK.AutoTune,
				showHits = HITBOX.ShowHits,
			},
			stamina = { noFatigue = STAMINA.NoFatigue },
			warning = { distance = WARNING.Distance },
			run = runSection,
		}
	end

	--[[
		РУЧНОЕ СОХРАНЕНИЕ.

		Автозаписи больше нет: пользователь попросил кнопку. Поэтому появился
		флаг configDirty - без него было бы невозможно отличить «настройки
		совпадают с файлом» от «забыл нажать сохранить», и кнопка выглядела бы
		мёртвой.

		markDirty() зовётся из каждого места, которое раньше вызывало
		автосохранение: тумблеры, степперы, сброс настроек, автоподгонка зоны.
	]]
	function markDirty()
		if configDirty then
			return
		end
		configDirty = true
		if onConfigDirtyChanged then
			onConfigDirtyChanged()
		end
	end

	-- Имя последнего профиля. Иначе после перезапуска скрипт всегда открывал
	-- бы "default", даже если работа шла в другом профиле.
	local CONFIG_LAST_PATH = CONFIG_FOLDER .. "/last.txt"

	local function writeLastProfile()
		if not hasFileApi then
			return
		end
		pcall(fs.writefile, CONFIG_LAST_PATH, configName)
	end

	local function readLastProfile()
		if not hasFileApi then
			return nil
		end
		if fs.isfile then
			local okExists, exists = pcall(fs.isfile, CONFIG_LAST_PATH)
			if okExists and not exists then
				return nil
			end
		end
		local okRead, raw = pcall(fs.readfile, CONFIG_LAST_PATH)
		if not okRead or type(raw) ~= "string" then
			return nil
		end
		return sanitizeConfigName((raw:gsub("%s", "")))
	end

	--[[
		Список существующих профилей - для подсказки в меню. listfiles есть
		не у всех executor'ов, поэтому при его отсутствии возвращается nil,
		и меню просто не показывает список (а не пустой, что читалось бы как
		«профилей нет»).
	]]
	function listProfiles()
		if not (hasFileApi and fs.listfiles) then
			return nil
		end
		local ok, files = pcall(fs.listfiles, CONFIG_FOLDER)
		if not ok or type(files) ~= "table" then
			return nil
		end
		local names = {}
		for _, entry in ipairs(files) do
			if type(entry) == "string" then
				-- listfiles возвращает путь целиком, разделитель зависит от executor'а
				local base = entry:match("([^/\\]+)$")
				local name = base and base:match("^(.+)%.json$")
				if name then
					table.insert(names, name)
				end
			end
		end
		table.sort(names)
		return names
	end

	--[[
		Запись в оба хранилища.

		Таблица сессии пишется ВСЕГДА и первой: она бесплатная и не может
		отказать, поэтому настройки переживут перезапуск скрипта даже без
		файлового API. Файл - когда он есть.
	]]
	function saveConfig()
		if not hasAnyStore then
			return false
		end

		local okEncode, encoded = pcall(function()
			return HttpService:JSONEncode(buildConfigTable())
		end)
		if not okEncode then
			warn("[AdminMenu] не удалось собрать конфиг")
			return false
		end

		if sessionStore then
			pcall(function()
				sessionStore[SESSION_KEY] = encoded
				sessionStore[SESSION_NAME_KEY] = configName
			end)
		end

		local function finish()
			configDirty = false
			if onConfigDirtyChanged then
				onConfigDirtyChanged()
			end
		end

		if not hasFileApi then
			finish()
			return true -- сессия сохранена, файла в этом executor'е нет
		end

		ensureConfigFolder()

		local okWrite, err = pcall(fs.writefile, currentConfigPath(), encoded)
		if not okWrite then
			writeFailed = true
			warn("[AdminMenu] не удалось записать конфиг: " .. tostring(err))
			return false
		end

		writeFailed = false
		writeLastProfile()
		finish()
		return true
	end

	--[[
		Стартовая загрузка. Имя профиля берётся из файла last.txt (или из
		памяти сессии, если файлов нет): без этого скрипт после перезапуска
		всегда открывал бы "default", даже если работа шла в другом профиле.

		Загрузка ОТЛОЖЕНА через task.defer: RUN (40_auto) определяется ПОЗЖЕ
		конфига в том же чанке, и синхронный вызов видел бы nil. Отложенный
		вызов стартует после выполнения всего чанка - к этому моменту RUN
		живой, и значения из конфига применяются полностью. Диагностика
		файлового API печатается вместе с ней.
	]]
	local remembered = readLastProfile()
	if not remembered and sessionStore then
		local okName, name = pcall(function()
			return sessionStore[SESSION_NAME_KEY]
		end)
		if okName then
			remembered = sanitizeConfigName(name)
		end
	end
	if remembered then
		configName = remembered
	end

	task.defer(function()
		configLoaded, configSource = loadConfig()

	--=========================== КОНФИГ: ДИАГНОСТИКА ===========================

	-- Печатает в консоль (F9), какие функции нашлись. Без этого при проблеме
	-- невозможно понять, чего именно не хватает.
	local found, missing = {}, {}
	for _, name in ipairs(FS_NAMES) do
		table.insert(fs[name] and found or missing, name)
	end

	-- Необязательная функция executor'ов, полезна в отчёте об ошибке
	local okName, executorName = pcall(function()
		local identify = asFunction(identifyexecutor)
		return identify and identify() or nil
	end)
	local label = (okName and type(executorName) == "string" and executorName ~= "")
			and executorName
		or "не определён"

	if hasFileApi then
		print(
			string.format(
				"[AdminMenu] файловое API найдено (executor: %s). Есть: %s. Нет: %s. Конфиг: %s",
				label,
				#found > 0 and table.concat(found, ", ") or "-",
				#missing > 0 and table.concat(missing, ", ") or "-",
				currentConfigPath()
			)
		)
	else
		warn(
			string.format(
				"[AdminMenu] файловое API не найдено (нет readfile/writefile), executor: %s. "
					.. "Настройки будут храниться в памяти клиента (getgenv) и переживут "
					.. "перезапуск скрипта, но не выход из игры. "
					.. "Файлы умеет писать только executor.",
				label
			)
		)
	end
	end)
end

