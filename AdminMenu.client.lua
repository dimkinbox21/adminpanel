--[[
	АДМИН-МЕНЮ (LocalScript)

	Куда положить: StarterPlayer -> StarterPlayerScripts, тип объекта LocalScript.

	Функции: Fly, Noclip, Godmode (локальный), бесконечная стамина,
	невидимость, ESP (метки цветом команды - как в списке игроков,
	отдельная метка Caretaker и указатели 360 на тех, кто вне экрана),
	список игроков, автоблок, предупреждение о киллере.

	Клавиши по умолчанию: RightCtrl - меню, F - Fly, N - Noclip, G - Godmode,
	H - бесконечная стамина, J - невидимость, E - ESP, T - список игроков,
	B - автоблок, K - предупреждение о киллере.
	Все бинды переназначаются в меню: жми кнопку с названием клавиши справа
	от тумблера и нажми новую клавишу (Escape - отмена).
	В полёте: WASD - движение, Space - вверх, LeftShift - вниз.

	Окно широкое, с вкладками слева: Читы, ESP, Игроки, Автоблок, Опасность,
	Конфиг. Каждая вкладка - свой скролл, поэтому позиция в одной не
	сбивается при переходе в другую.

	Автоблок сам ставит блок, когда киллер рядом начинает атаку. Работает
	только через executor: нажатие отправляется VirtualInputManager, а этому
	сервису нужны его права. Без них тумблер серый - см. заметку 9 в конце.
	Если в этом раунде ты САМ киллер, автоблок и предупреждение отключаются
	автоматически: блока у киллера нет, а предупреждать его не о чем.

	Настройки и бинды сохраняются ПО КНОПКЕ на вкладке «Конфиг» - в файл
	AdminMenu/<имя профиля>.json (нужен executor с writefile) и в память
	клиента через getgenv(). Второе работает почти всегда и переживает
	перезапуск скрипта и смену раунда, но не выход из игры. Имя профиля
	меняется там же, профилей можно держать сколько угодно. Автосохранения
	нет: точка на кнопке «Сохранить» означает несохранённые изменения.

	Всё работает только на клиенте. Проверки по UserId больше нет - меню
	откроется у любого, кто запустил файл. См. заметки в конце файла.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

--============================ НАСТРОЙКИ ============================

--[[
	Проверки UserId здесь БОЛЬШЕ НЕТ (убрана по просьбе пользователя).
	Меню открывается у любого, кто запустил скрипт.

	Что это меняет: раньше список ADMIN_USER_IDS отсекал случайного
	игрока, которому файл попал в руки. Защитой от читера он не был
	никогда - клиентскую проверку обходят правкой одной строки. Но
	«случайный игрок» теперь тоже получает полное меню, так что файлом не
	стоит делиться, если это не задумано.
]]

-- Бинды по умолчанию. В игре меняются через меню; сохраняются в конфиг,
-- если доступно файловое API (см. секцию КОНФИГ ниже).
local BINDS = {
	menu = Enum.KeyCode.RightControl,
	fly = Enum.KeyCode.F,
	noclip = Enum.KeyCode.N,
	god = Enum.KeyCode.G,
	stamina = Enum.KeyCode.H,
	invisible = Enum.KeyCode.J,
	esp = Enum.KeyCode.E,
	list = Enum.KeyCode.T,
	autoblock = Enum.KeyCode.B,
	warning = Enum.KeyCode.K,
}

local FLY_KEYS = {
	Up = Enum.KeyCode.Space,
	Down = Enum.KeyCode.LeftShift,
}

local FLY = {
	Speed = 60,
	Step = 20,
	Min = 10,
	Max = 400,
}

local ESP = {
	Highlight = true, -- подсветка модели сквозь стены
	Names = true,
	Health = true,
	Distance = true,
	Tracers = false, -- линии от низа экрана к игрокам
	OffScreen = true, -- 360: указатели по краям экрана на тех, кого не видно
	TeamCheck = true, -- союзников не показывать
	MarkCaretaker = true, -- выживший с Caretaker отдельным цветом
	MaxDistance = 1000, -- 0 = без ограничения
	DistanceStep = 250,
	DistanceLimit = 5000,
	TracerThickness = 1,
	FillTransparency = 0.7,
	-- Геометрия 360-указателей: константы кода, в json намеренно не идут.
	OffScreenMargin = 34, -- отступ рамки указателей от края экрана, px
	OffScreenSize = 26, -- размер стрелки, px
	OffScreenThickness = 3, -- толщина полосок, из которых собрана стрелка
}

--[[
	CARETAKER

	Способность выжившего. В esp.txt (строка 564) её наличие определяется
	не по атрибуту, а по ПРЕДМЕТУ в персонаже:
	    Character.Vanities.CaretakerItem  и  Transparency ~= 1

	Проверки Transparency здесь НЕТ (по просьбе пользователя: «чтобы
	Caretaker всегда светился, а не только когда использует способку»).
	Прозрачность 1 означает израсходованный предмет; с этой проверкой метка
	исчезала посреди раунда, а нужно видеть носителя постоянно.

	Атрибута с именем способности в дампах не нашлось, так что путь через
	Vanities - единственный известный признак. Если сборка плейса назовёт
	предмет иначе, метка просто не появится (молча, без ошибок).
]]
local CARETAKER = {
	Folder = "Vanities",
	Item = "CaretakerItem",
	Color = Color3.fromRGB(190, 120, 255), -- сиреневый: не путается с голубым/красным
}

--[[
	Список игроков в правом верхнем углу: дальность и стамина, разбитые
	по командам.

	Стамина в этом плейсе живёт в атрибутах персонажа, а не в Humanoid.
	Читается StaminaServer - именно это значение сервер репликует всем
	клиентам (найдено в esp2.txt). Локальные Stamina/CurrentStamina есть
	только у своего персонажа, для чужих они пустые.
]]
local LIST = {
	Distance = true,
	Stamina = true,
	SortByDistance = true, -- иначе по алфавиту
	ShowSelf = false,
	MaxRows = 24, -- лишние игроки сворачиваются в строку "+N ещё"
	Interval = 0.1, -- пересчёт 10 раз в секунду, а не каждый кадр
	Width = 268,
	ValueWidth = 124,
	OffsetX = 12,
	OffsetY = 44, -- ниже стандартного топбара Roblox
	RowHeight = 16,
	HeaderHeight = 20,
}

-- Порядок команд. Чего здесь нет - идёт после по алфавиту, "без команды" последней.
local TEAM_ORDER = { "Killer", "Survivor", "Ghost", "Lobby" }

local TEAM_COLORS = {
	Killer = Color3.fromRGB(255, 95, 95),
	Survivor = Color3.fromRGB(120, 200, 255),
	Ghost = Color3.fromRGB(180, 180, 195),
	Lobby = Color3.fromRGB(215, 215, 225),
}

-- Уже в верхнем регистре: string.upper в заголовке работает побайтово и
-- кириллицу не поднимает, поэтому имя пишется заглавными сразу.
local NO_TEAM = "БЕЗ КОМАНДЫ"

--[[
	Где искать команду. В этом плейсе персонажи лежат в
	workspace.GameAssets.Teams.<Команда>, а до начала раунда - в
	GameAssets.Other.LobbyPlayers (обе структуры видны в esp2.txt).
	Player.Team - запасной вариант для плейсов со штатными Teams.
]]
local TEAM_FOLDER_PARENT = "Teams"
local LOBBY_FOLDER = "LobbyPlayers"
local LOBBY_TEAM = "Lobby"

--[[
	Атрибуты со стаминой. Порядок важен: StaminaServer идёт первым, потому
	что это единственное значение, которое сервер репликует про ЧУЖИХ
	игроков. Stamina/CurrentStamina оставлены на случай другой сборки
	плейса и для своего персонажа.
]]
local STAMINA_KEYS = { "StaminaServer", "Stamina", "CurrentStamina" }
local MAX_STAMINA_KEYS = { "MaxStamina", "StaminaMax" }

--[[
	Атрибут с именем убийцы. В этом плейсе он называется KillerName
	(проверено живым дампом: KillerName = "Harken" на модели киллера).
	"Killer" оставлен вторым на случай другой сборки - раньше в коде стояло
	только оно, и таблица KILLER_MAX_STAMINA из-за этого не срабатывала
	никогда.
]]
local KILLER_NAME_KEYS = { "KillerName", "Killer" }

--[[
	Штатный максимум стамины зависит от того, кем играет персонаж
	(значения из esp.txt, функция GetLegitMaxStamina).

	Нужен потому, что атрибут MaxStamina чужих игроков клиенту не
	репликуется - без этой таблицы дробь было бы не из чего построить.
	У своего персонажа MaxStamina вдобавок мог быть задран до math.huge
	таким же читом, тогда он тоже бесполезен.
]]
local KILLER_MAX_STAMINA = {
	Pursuer = 110,
	Killdroid = 110,
	Badware = 110,
	Harken = 114,
}
local DEFAULT_MAX_STAMINA = 100

--[[
	БЕСКОНЕЧНАЯ СТАМИНА

	Способ взят из esp.txt (строки 202-209, 466-474): своему персонажу
	ставится атрибут MaxStamina = math.huge, и клиентский код плейса,
	который восстанавливает стамину, начинает считать её от бесконечности.

	Почему это работает без сервера: стамину тратит и восполняет КЛИЕНТСКИЙ
	код плейса, он же пишет StaminaServer. Мы не подделываем чужое значение,
	а меняем предел, от которого он считает.

	Ключевой момент - плейс переписывает MaxStamina обратно, поэтому
	недостаточно поставить атрибут один раз: нужен слушатель
	GetAttributeChangedSignal, который ставит его снова. Так сделано и в
	esp.txt.

	Что это НЕ даёт: бега без остановки, если плейс тормозит спринт другим
	атрибутом (Fatigue, DisableSprint, WalkSpeedModifier). Это отдельные
	читы, и они здесь не сделаны.
]]
local STAMINA = {
	--[[
		На что подменяется MaxStamina. В esp.txt стоит math.huge, поэтому и
		здесь по умолчанию он. Если плейс не переварит бесконечность
		(NaN в расчётах, сломанная полоска), сюда можно поставить 1e6.
	]]
	Value = math.huge,
	NoFatigue = true, -- заодно снимать атрибут Fatigue
}

--[[
	АВТОБЛОК

	Замеры по живому логу этого плейса (не менять на глаз):
	  - телеграф атаки: у модели киллера атрибут UsingAbility становится true
	    (вместе с ним прилетают UsedM1 и AbilitiesUsed++);
	  - обычный M1: от телеграфа до урона 280 мс;
	  - раскидывающий спецприём (там же WalkSpeedModifier = -6): 570 мс;
	  - UsingAbility гаснет через ~630 мс, то есть уже после урона;
	  - блок держится 1000 мс, перезарядка 35 с.
	Запас после эмуляции нажатия (105-180 мс) - около 100 мс, поэтому
	никаких задержек "для красоты" здесь нет: жмём сразу.

	WalkSpeedModifier киллера как триггер НЕ годится: при обычном M1 он
	остаётся ровно 0 (в block.txt из интернета ждут 7.5 - это неверно).

	Набор способностей рандомный каждый раунд, блок может быть в любом
	слоте или отсутствовать вовсе, поэтому слот ищется в атрибутах
	Ability1..AbilityN своего персонажа во время игры.
]]
local AUTOBLOCK = {
	--[[
		ЗОНА БЛИЖНЕГО БОЯ. Главное число автоблока: за её пределами обычный
		удар не реагирует вообще. В логе попадания пришли с 5.5 и 4.9
		студов, промахи - с 8.4 и 8.5. 14 взято с запасом на рывок и на
		разные виды киллеров, у них разный вылет удара.
		Зона рисуется в мире (ShowZone), так что её видно, а не приходится
		угадывать.
	]]
	Reach = 14,
	ReachStep = 2,
	ReachMin = 6,
	ReachMax = 30,

	--[[
		ДАЛЬНИЕ АТАКИ (снаряды). По умолчанию ВЫКЛЮЧЕНЫ: именно на них
		блок и уходил впустую - киллер стреляет через пол-карты, а мы
		тратим 35 с кулдауна. Включай осознанно, когда киллер реально
		стреляющий.
	]]
	Ranged = false,
	Radius = 24,
	RadiusStep = 4,
	RadiusMin = 10,
	RadiusMax = 80,

	--[[
		Насколько киллер должен смотреть на нас. Это косинус угла между его
		взглядом и направлением на нас, поэтому БОЛЬШЕ = строже.
		0.30 ~ 72 градуса: в ближнем бою замах задевает и сбоку, да и
		киллер доворачивается уже во время анимации.
		0.94 ~ 20 градусов: снаряд летит туда, куда он целится, и мимо
		этого конуса он в нас не попадёт.
	]]
	MeleeCone = 0.30,
	RangedCone = 0.94,

	HoldTime = 0.05, -- сколько держать клавишу нажатой

	--[[
		Один блок на атаку. UsingAbility висит около 630 мс, поэтому меньше
		нельзя - полетит десяток нажатий на одну атаку. Больше 1 с тоже
		нельзя: в логе между вторым и третьим M1 прошло 1.10 с, и слишком
		длинный дебаунс проглотил бы следующую атаку.

		Дебаунс ОБЩИЙ, а не по киллеру: блок один, и если в раунде два
		киллера, второе нажатие всё равно ушло бы в кулдаун.
	]]
	Debounce = 0.8,

	MaxSlots = 6, -- предохранитель на случай странного AbilityNum
	ScanInterval = 0.25, -- как часто заново искать слот и клавишу блока

	ShowZone = true, -- рисовать зоны в мире
	AutoTune = true, -- подгонять Reach по реально прилетевшим хитбоксам
}

--[[
	ЗОНЫ В МИРЕ.

	Рисуются адорнментами (CylinderHandleAdornment), а не деталями: у них
	нет физики и коллизий, они сами следуют за Adornee и их не видит ни
	сервер, ни другие игроки.

	Диски, а не сферы: зона проверяется по горизонтали, и плоский круг
	под ногами честно показывает то, что считает код.
]]
local ZONE = {
	Height = 0.3, -- толщина диска
	--[[
		Смещение вниз от HumanoidRootPart. У R15 рут сидит примерно в 3
		студах над полом (HipHeight ~2 плюс половина руста), поэтому -2.8
		кладёт диск почти на пол.
	]]
	Offset = -2.8,
	MeleeColor = Color3.fromRGB(80, 220, 130),
	RangedColor = Color3.fromRGB(240, 190, 70),
	HitboxColor = Color3.fromRGB(255, 90, 90),
	MeleeTransparency = 0.8,
	RangedTransparency = 0.88,
	AlertTransparency = 0.6, -- когда киллер вошёл в зону, диск заметнее
}

--[[
	ХИТБОКСЫ.

	Как ТРИГГЕР они бесполезны - измерено: объект "Hitbox" появляется в тот
	же кадр, что и урон, реагировать поздно. Но как ИЗМЕРИТЕЛЬ они
	незаменимы: по ним видно, с какой дистанции удар реально достаёт, и
	накрыл ли блок настоящую атаку или сгорел впустую.

	Отсюда автоподгонка Reach и счётчики в меню.
]]
local HITBOX = {
	NamePart = "hitbox", -- поиск по подстроке в нижнем регистре
	Margin = 1.5, -- персонаж не точка, рут даёт погрешность
	Window = 1.4, -- столько ждём хитбокс после нажатия блока
	Samples = 12, -- по скольким последним попаданиям считается Reach
	TuneMargin = 2, -- запас к измеренной дистанции
	MinSamples = 3, -- меньше этого не подгоняем
	ShowHits = true, -- подсвечивать прилетевшие хитбоксы
	FlashTime = 0.35,
}

local BLOCK_ABILITY_NAME = "Block"

--[[
	Своё состояние блока. Проверено логом №1 на своём персонаже:
	  BlockCooldown = 30.6 - тикает вниз шагом 0.1 до нуля;
	  Blocking = true - ровно 1.0 с после срабатывания.
	Оба атрибута ЛОКАЛЬНЫЕ, для чужих игроков их нет, но нам и нужен только
	свой. Именно они дают честный гейт: жать в кулдаун бессмысленно.
]]
local BLOCK_COOLDOWN_KEY = "BlockCooldown"
local BLOCKING_KEY = "Blocking"

-- Куда смотреть за телеграфом. Папка та же, что и у списка игроков.
local KILLER_TEAM = "Killer"

--[[
	Клавиши слотов на случай, если кнопку блока в интерфейсе найти не
	удалось. Основной источник - текст в
	RoundUI.PlayerUI.Abilities.Folder.Block.Input, эта таблица только
	запасная.
]]
local SLOT_KEYS = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.T, Enum.KeyCode.Y, Enum.KeyCode.U }

-- Текст кнопки способности может быть цифрой, а Enum.KeyCode["1"] не существует.
local DIGIT_KEY_NAMES = {
	["0"] = "Zero",
	["1"] = "One",
	["2"] = "Two",
	["3"] = "Three",
	["4"] = "Four",
	["5"] = "Five",
	["6"] = "Six",
	["7"] = "Seven",
	["8"] = "Eight",
	["9"] = "Nine",
}

--[[
	ПРЕДУПРЕЖДЕНИЕ О КИЛЛЕРЕ (баннер сверху экрана).

	Показывает дистанцию до ближайшего киллера и его стамину. Цвет - по
	ТРЕНДУ стамины, а не по её величине:
	  падает      -> красный. Киллер тратит стамину: бежит за кем-то или
	                 атакует. Это и есть опасность.
	  растёт      -> зелёный. Восстанавливается, то есть стоит или идёт
	                 шагом.
	  не меняется -> зелёный (по прямой просьбе пользователя: «тоже самое,
	                 если стамина не падает и не поднимается»).

	Почему тренд, а не значение: полная стамина у стоящего киллера и полная
	у него же в момент рывка выглядят одинаково. Разницу видно только в
	производной.

	Стамина читается из StaminaServer - единственного атрибута, который
	сервер репликует про ЧУЖИХ игроков (см. секцию про список игроков).
]]
local WARNING = {
	Distance = 90, -- дальше этого баннер не показывается
	DistanceStep = 15,
	DistanceMin = 30,
	DistanceMax = 300,
	--[[
		Мёртвая зона тренда. Стамина реплицируется рывками, и без порога
		цвет мигал бы на округлениях. 0.35 в секунду - заметно меньше
		реального расхода на спринте, но больше дрожания.
	]]
	Epsilon = 0.35,
	Interval = 0.1, -- как часто пересчитывать (стамина приходит не каждый кадр)
	Height = 54,
	OffsetY = 6,
	Width = 340,
	SafeColor = Color3.fromRGB(90, 200, 120),
	DangerColor = Color3.fromRGB(235, 80, 80),
}

--[[
	НЕВИДИМОСТЬ.

	Способ из esp.txt (строка 847): проигрывается специальная анимация,
	останавливается на кадре 2.2, и персонаж уезжает из своей видимой
	модели. Работает на клиенте и, поскольку анимации реплицируются,
	обычно виден и другим - но это НЕ гарантия, см. заметку в конце файла.

	Что нужно вместе с ней:
	  - камера привязывается к HumanoidRootPart, иначе она уедет вместе с
	    уехавшей моделью;
	  - коллизии снимаются со всего, кроме рута, иначе невидимое тело
	    продолжает цепляться за геометрию.
	Оба пункта - из того же esp.txt: без них способ выглядит сломанным.
]]
local INVISIBLE = {
	AnimationId = "rbxassetid://90444351114401",
	TimePosition = 2.2,
}

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

	-- Мутируем таблицы на месте: замыкания кнопок UI держат ссылки на них.
	local function applyConfigTable(data)
		applyBindsFromConfig(data.binds)
		applyFlyFromConfig(data.fly)
		applyEspFromConfig(data.esp)
		applyListFromConfig(data.list)
		applyAutoblockFromConfig(data.autoblock)
		applyStaminaFromConfig(data.stamina)
		applyWarningFromConfig(data.warning)
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

		local esp = { maxDistance = ESP.MaxDistance }
		for _, key in ipairs(ESP_SAVED_FLAGS) do
			esp[ESP_JSON_KEYS[key]] = ESP[key]
		end

		local list = {}
		for _, key in ipairs(LIST_SAVED_FLAGS) do
			list[LIST_JSON_KEYS[key]] = LIST[key]
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
end

--=========================== СОСТОЯНИЕ ===========================

local state = {
	fly = false,
	noclip = false,
	god = false,
	stamina = false,
	invisible = false,
	esp = false,
	list = false,
	autoblock = false,
	warning = true, -- предупреждение о киллере полезно сразу, без включения
}

local character, humanoid, rootPart
local flyForces = nil -- { velocity = BodyVelocity, gyro = BodyGyro }
local collisionCache = {} -- part -> исходное CanCollide
local originalMaxHealth = 100

local function getCamera()
	return workspace.CurrentCamera
end

--=========================== ФУНКЦИИ ЧИТОВ ===========================

local function applyFly(enabled)
	if enabled then
		if flyForces or not (rootPart and humanoid) then
			return
		end

		local velocity = Instance.new("BodyVelocity")
		velocity.Name = "AdminFlyVelocity"
		velocity.Velocity = Vector3.zero
		velocity.MaxForce = Vector3.one * math.huge
		velocity.P = 1250
		velocity.Parent = rootPart

		local gyro = Instance.new("BodyGyro")
		gyro.Name = "AdminFlyGyro"
		gyro.MaxTorque = Vector3.one * math.huge
		gyro.P = 9e4
		gyro.D = 500
		gyro.CFrame = getCamera().CFrame
		gyro.Parent = rootPart

		flyForces = { velocity = velocity, gyro = gyro }
		humanoid.PlatformStand = true
	else
		if flyForces then
			flyForces.velocity:Destroy()
			flyForces.gyro:Destroy()
			flyForces = nil
		end
		if humanoid then
			humanoid.PlatformStand = false
		end
	end
end

local function applyNoclip(enabled)
	-- Включение делается каждый кадр в основном цикле (Roblox сбрасывает CanCollide),
	-- здесь только возврат коллизий на место.
	if enabled then
		return
	end

	for part, canCollide in pairs(collisionCache) do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
	table.clear(collisionCache)
end

local GOD_HEALTH = 1e9 -- не math.huge: бесконечность ломает стандартный healthbar

local function applyGod(enabled)
	if not humanoid then
		return
	end

	if enabled then
		humanoid.BreakJointsOnDeath = false
		humanoid.MaxHealth = GOD_HEALTH
		humanoid.Health = GOD_HEALTH
	else
		humanoid.BreakJointsOnDeath = true
		humanoid.MaxHealth = originalMaxHealth
		humanoid.Health = originalMaxHealth
	end
end

--=========================== НЕВИДИМОСТЬ ===========================

--[[
	Способ из esp.txt (строка 847): проигрывается специальная анимация и
	останавливается на кадре 2.2. Персонаж физически уезжает из своей
	видимой модели - для остальных остаётся стоять пустая оболочка.

	Это НЕ LocalTransparencyModifier: тот прячет модель только у себя, для
	остальных ничего не меняется, и как чит бесполезен. Анимации, наоборот,
	реплицируются сервером, поэтому эффект видят все. Но зависит он от
	конкретного анимационного ассета, а не от гарантии Roblox - если плейс
	или ассет изменятся, способ отвалится молча. См. заметку в конце файла.

	Что нужно вместе с анимацией (тоже из esp.txt, без этого выглядит
	сломанным):
	  - камеру привязать к HumanoidRootPart, иначе она уедет вслед за
	    брошенной моделью и смотреть будет в пустоту;
	  - снять коллизии со всего, кроме рута: невидимое тело иначе цепляется
	    за геометрию, и это сразу видно со стороны.

	В do-блоке ради лимита Luau на 200 локалов верхнего уровня: наружу
	нужны только две функции.
]]
local applyInvisible, clearInvisibleCache

do
	local invisibleTrack = nil -- играющая анимация
	local invisibleConnections = {}
	local invisibleCollisionCache = {} -- отдельно от noclip: режимы независимы

	local function disconnectInvisible()
		for _, connection in ipairs(invisibleConnections) do
			connection:Disconnect()
		end
		table.clear(invisibleConnections)
	end

	local function restoreInvisibleCollisions()
		for part, canCollide in pairs(invisibleCollisionCache) do
			if part.Parent then
				part.CanCollide = canCollide
			end
		end
		table.clear(invisibleCollisionCache)
	end

	-- Новый персонаж: старые детали удалены, восстанавливать нечего
	function clearInvisibleCache()
		table.clear(invisibleCollisionCache)
	end

	local function stopInvisibleAnimation()
		if invisibleTrack then
			pcall(function()
				invisibleTrack:Stop(0)
				invisibleTrack:Destroy()
			end)
			invisibleTrack = nil
		end

		--[[
			Гасим и всё остальное, что играет: в esp.txt при выключении
			сбрасываются ВСЕ треки. Иначе застывшая поза остаётся, и персонаж
			стоит колом.
		]]
		if humanoid then
			pcall(function()
				for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
					track.Priority = Enum.AnimationPriority.Core
					track:AdjustSpeed(0)
					track:Stop(0)
				end
			end)
		end
	end

	function applyInvisible(enabled)
		if not enabled then
			disconnectInvisible()
			stopInvisibleAnimation()
			restoreInvisibleCollisions()
			-- Камеру вернуть обязательно, иначе она останется на руте и
			-- перестанет следить за анимациями персонажа
			pcall(function()
				if humanoid then
					getCamera().CameraSubject = humanoid
				end
			end)
			return
		end

		if not (character and humanoid and rootPart) then
			return
		end

		-- Коллизии: всё, кроме рута. Рут оставляем, иначе персонаж провалится.
		pcall(function()
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide and part ~= rootPart then
					if invisibleCollisionCache[part] == nil then
						invisibleCollisionCache[part] = true
					end
					part.CanCollide = false
				end
			end
			rootPart.CanCollide = true
		end)

		-- Камера на рут + слежение: плейс возвращает CameraSubject на Humanoid
		pcall(function()
			local camera = getCamera()
			camera.CameraSubject = rootPart
			table.insert(
				invisibleConnections,
				camera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
					if state.invisible and rootPart and rootPart.Parent then
						camera.CameraSubject = rootPart
					end
				end)
			)
		end)

		--[[
			Анимация грузится асинхронно, поэтому в отдельном потоке с
			ожиданием Length > 0. LoadAnimation на Humanoid устарел, но
			Animator:LoadAnimation есть не у всех сборок - берём Animator,
			если он есть, иначе Humanoid.
		]]
		task.spawn(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = INVISIBLE.AnimationId

			local okLoad, track = pcall(function()
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if animator then
					return animator:LoadAnimation(animation)
				end
				return humanoid:LoadAnimation(animation)
			end)
			if not okLoad or not track then
				warn(
					"[AdminMenu] невидимость: не удалось загрузить анимацию "
						.. INVISIBLE.AnimationId
				)
				return
			end

			track.Priority = Enum.AnimationPriority.Action4

			-- Ждём метаданные ассета. Таймаут обязателен: без сети Length
			-- останется нулевым, и цикл висел бы вечно.
			local deadline = os.clock() + 5
			while track.Length <= 0 and os.clock() < deadline do
				task.wait()
			end
			if track.Length <= 0 then
				warn("[AdminMenu] невидимость: анимация не загрузилась (нет ассета или нет сети)")
				track:Destroy()
				return
			end

			-- Тумблер могли успеть выключить, пока грузился ассет
			if not state.invisible then
				track:Destroy()
				return
			end

			track:Play()
			-- Останавливаем на нужном кадре: именно застывшая поза и уводит
			-- персонажа из модели
			track:AdjustSpeed(0)
			track.TimePosition = INVISIBLE.TimePosition
			invisibleTrack = track
		end)
	end
end

--=========================== ESP ===========================

local playerGui = player:WaitForChild("PlayerGui")

--[[
	teamNameOf объявлен ЗДЕСЬ, а определён ниже, в секции списка игроков
	(там же, где остальная работа с командами). Форвард-локал нужен потому,
	что ESP красит метки ТЕМ ЖЕ цветом команды, что и панель игроков, а
	do-блок ESP идёт раньше. Число локалов верхнего уровня от этого
	не меняется (см. заметку про лимит 200).
]]
local teamNameOf

--[[
	Внутренности ESP спрятаны в do-блок ради лимита Luau на 200 локалов
	верхнего уровня. Наружу выходят три функции: обновление каждый кадр,
	выключение и точечное гашение подсветок/трейсеров для кнопок настроек.
]]
local updateEsp, applyEsp, hideEspVisuals

do
	--[[
		ЦВЕТ МЕТКИ БЕРЁТСЯ ИЗ TEAM_COLORS - ТЕХ ЖЕ, ЧТО В ПАНЕЛИ ИГРОКОВ
		(просьба пользователя: «выжившие подсвечивались голубым, как в табе»).
		Раньше здесь была своя пара Ally/Enemy по Player.Team, и она давала
		НЕ ТОТ результат: в этом плейсе Player.Team пустой, команда живёт
		в иерархии (GameAssets.Teams.<Команда>), поэтому isAlly почти всегда
		возвращал false и ВСЕ красились красным - и киллеры, и выжившие.
		Теперь Survivor голубой (120,200,255), Killer красный, Ghost и Lobby
		серые - ровно как в списке игроков, один источник цвета на весь скрипт.

		FALLBACK нужен: teamColor отдаёт COLORS.Text для незнакомой команды,
		а белым текстом метку на светлом фоне не видно. Для «без команды»
		берётся приглушённый серый.
	]]
	local NO_TEAM_COLOR = Color3.fromRGB(200, 200, 210)

	local function colorForTeam(teamName)
		if teamName == NO_TEAM then
			return NO_TEAM_COLOR
		end
		return TEAM_COLORS[teamName] or NO_TEAM_COLOR
	end

	--[[
		Есть ли у персонажа Caretaker.

		Признак взят из esp.txt (строка 564): предмет
		Character.Vanities.CaretakerItem внутри персонажа.

		ПРОЗРАЧНОСТЬ НЕ ПРОВЕРЯЕТСЯ (изменено по просьбе пользователя:
		«чтобы Caretaker всегда светился, а не только когда использует
		способку»). В esp.txt стояло ещё и Transparency ~= 1, и раньше стояло
		здесь: предмет становится прозрачным, когда способность израсходована.
		Но пользователю нужно видеть НОСИТЕЛЯ на весь раунд, а не момент
		применения - израсходованный Caretaker всё равно говорит, кто это был.
		Не возвращать проверку обратно: метка тогда снова начнёт исчезать
		посреди раунда.

		Атрибута с именем способности в дампах плейса не нашлось, так что
		предмет - единственный известный признак. Всё под pcall: у части
		сборок папки Vanities нет вообще.
	]]
	local function hasCaretaker(char)
		if not char then
			return false
		end
		local ok, result = pcall(function()
			local vanities = char:FindFirstChild(CARETAKER.Folder)
			if not vanities then
				return false
			end
			return vanities:FindFirstChild(CARETAKER.Item) ~= nil
		end)
		return ok and result == true
	end

	--[[
		Трейсеры живут в ScreenGui. Билборды парентятся прямо в PlayerGui:
		BillboardGui сам является LayerCollector, вкладывать его в ScreenGui нельзя.

		IgnoreGuiInset = TRUE ОБЯЗАТЕЛЬНО, это не косметика.
		Позиции целей приходят из Camera:WorldToViewportPoint, а он, по
		документации, НЕ учитывает GUI-инсет: координата отсчитывается от
		левого верхнего угла вьюпорта, и для размещения GUI годится только
		при IgnoreGuiInset. Тогда обе системы координат совпадают.
		Поставить false - и всё содержимое съедет ВНИЗ на высоту инсета
		(~36 px): трейсеры перестанут попадать в тело, а рамка 360-указателей
		уползёт, потому что она считается от camera.ViewportSize.
		Если когда-нибудь понадобится false, каждую позицию придётся
		уменьшать на GuiService:GetGuiInset() - в трёх местах (трейсер,
		указатель, подпись указателя). Проще не трогать.
	]]
	local tracerGui = Instance.new("ScreenGui")
	tracerGui.Name = "AdminESP"
	tracerGui.ResetOnSpawn = false
	tracerGui.IgnoreGuiInset = true
	tracerGui.DisplayOrder = 90
	tracerGui.Parent = playerGui

	--[[
		360: СТРЕЛКА ПО КРАЮ ЭКРАНА.

		Билборд виден только когда игрок попал в кадр - за спиной и по бокам
		ESP молчит. Указатель закрывает ровно эту дыру: пока цель вне
		видимой области, у края экрана горит стрелка в её сторону.

		Стрелка собирается из ДВУХ Frame'ов внутри контейнера: готового
		треугольника в Roblox нет, а тащить сюда картинку-ассет нельзя -
		скрипт обязан остаться самодостаточным (ассет ещё и не прогрузится
		у части игроков). Две повёрнутые полоски дают "галочку", которая
		читается как острие.

		ПОЧЕМУ ЦЕНТР ПОЛОСКИ СЧИТАЕТСЯ ВРУЧНУЮ, а не задаётся якорем
		в остриё: поворот GuiObject идёт вокруг его СОБСТВЕННОЙ точки
		вращения, а не вокруг края. При AnchorPoint (0.5, 0) обе полоски
		провернулись бы вокруг своей середины и разъехались в "крестик"
		вместо "галочки" - это уже было сделано и исправлено.
		Поэтому: направление ноги считается из угла, центр полоски ставится
		в середину этой ноги, якорь у полоски (0.5, 0.5). Тогда результат
		один и тот же независимо от того, вокруг центра или вокруг якоря
		Roblox крутит - точки совпадают.

		Поворот всей стрелки задаётся у КОНТЕЙНЕРА: Rotation накапливается
		по иерархии, поэтому полоски держат свои +-LEG_ANGLE, а направление
		меняется одним свойством снаружи.
	]]
	local ARROW_LEG_ANGLE = 38 -- градусов от вертикали на каждую ногу

	local function createArrow(name)
		local size = ESP.OffScreenSize

		local container = Instance.new("Frame")
		container.Name = name
		container.AnchorPoint = Vector2.new(0.5, 0.5)
		container.Size = UDim2.fromOffset(size, size)
		container.BackgroundTransparency = 1
		container.BorderSizePixel = 0
		container.Visible = false
		container.ZIndex = 2 -- выше трейсеров
		container.Parent = tracerGui

		local legLength = size * 0.62
		local angle = math.rad(ARROW_LEG_ANGLE)
		-- Остриё сдвинуто вверх ровно на половину высоты галочки: тогда
		-- фигура вписана в центр контейнера и не гуляет при повороте.
		local tipX = size * 0.5
		local tipY = size * 0.5 - legLength * math.cos(angle) * 0.5

		local bars = {}

		for index, sign in ipairs({ -1, 1 }) do
			--[[
				Ось полоски при Rotation = 0 направлена вниз по экрану.
				Поворот на sign * ARROW_LEG_ANGLE (в Roblox положительный -
				по часовой) переводит её в (-sign * sin, cos): одна нога
				уходит вниз-влево, вторая вниз-вправо.
			]]
			local dirX = -sign * math.sin(angle)
			local dirY = math.cos(angle)

			local bar = Instance.new("Frame")
			bar.Name = "Bar" .. index
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromOffset(tipX + dirX * legLength * 0.5, tipY + dirY * legLength * 0.5)
			bar.Size = UDim2.fromOffset(ESP.OffScreenThickness, legLength)
			bar.BorderSizePixel = 0
			bar.Rotation = sign * ARROW_LEG_ANGLE
			bar.Parent = container
			bars[index] = bar
		end

		return container, bars
	end

	-- Подпись к указателю: отдельный объект, НЕ ребёнок стрелки. Rotation
	-- в Roblox наследуется по иерархии, внутри контейнера текст крутился бы
	-- вместе с острием и читался бы вверх ногами.
	local function createArrowLabel(name)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromOffset(140, 16)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 12
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		-- стартовый цвет; на первом же кадре его перекрасит цвет команды
		label.TextColor3 = NO_TEAM_COLOR
		label.Text = ""
		label.Visible = false
		label.ZIndex = 2
		label.Parent = tracerGui
		return label
	end

	-- [Player] = { billboard, label, tracer, highlight, boundCharacter }
	local espEntries = {}

	local function destroyHighlight(entry)
		if entry.highlight then
			entry.highlight:Destroy()
			entry.highlight = nil
		end
	end

	local function hideEntry(entry)
		if entry.highlight then
			entry.highlight.Enabled = false
		end
		entry.billboard.Enabled = false
		entry.tracer.Visible = false
		entry.arrow.Visible = false
		entry.arrowLabel.Visible = false
	end

	local function createEntry(other)
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ESP_" .. other.Name
		billboard.ResetOnSpawn = false
		billboard.Size = UDim2.fromOffset(220, 46)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Enabled = false
		billboard.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = NO_TEAM_COLOR -- перекрасится цветом команды в первом кадре
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextWrapped = false
		label.Text = ""
		label.Parent = billboard

		local tracer = Instance.new("Frame")
		tracer.Name = "Tracer_" .. other.Name
		tracer.AnchorPoint = Vector2.new(0.5, 0.5)
		tracer.BorderSizePixel = 0
		tracer.BackgroundColor3 = NO_TEAM_COLOR
		tracer.Size = UDim2.fromOffset(ESP.TracerThickness, 0)
		tracer.Visible = false
		tracer.ZIndex = 0
		tracer.Parent = tracerGui

		local arrow, arrowBars = createArrow("Arrow_" .. other.Name)
		local arrowLabel = createArrowLabel("ArrowText_" .. other.Name)

		local entry = {
			billboard = billboard,
			label = label,
			tracer = tracer,
			arrow = arrow,
			arrowBars = arrowBars,
			arrowLabel = arrowLabel,
			highlight = nil,
			boundCharacter = nil,
		}
		espEntries[other] = entry
		return entry
	end

	local function removeEntry(other)
		local entry = espEntries[other]
		if not entry then
			return
		end
		destroyHighlight(entry)
		entry.billboard:Destroy()
		entry.tracer:Destroy()
		entry.arrow:Destroy() -- полоски внутри уходят вместе с контейнером
		entry.arrowLabel:Destroy()
		espEntries[other] = nil
	end

	local function bindEspCharacter(entry, char)
		entry.boundCharacter = char
		destroyHighlight(entry)

		if not char then
			entry.billboard.Adornee = nil
			return
		end

		entry.billboard.Adornee = char:FindFirstChild("Head")
			or char:FindFirstChild("HumanoidRootPart")

		local highlight = Instance.new("Highlight")
		highlight.Name = "AdminESPHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = ESP.FillTransparency
		highlight.OutlineTransparency = 0
		highlight.Adornee = char
		highlight.Enabled = false
		highlight.Parent = char
		entry.highlight = highlight
	end

	function applyEsp(enabled)
		if enabled then
			return
		end
		for _, entry in pairs(espEntries) do
			hideEntry(entry)
		end
	end

	--[[
		Точечное гашение для кнопок "Подсветка" и "Трейсеры". Нужно потому,
		что выключенный флаг иначе убирал бы объекты только на следующем
		кадре обхода - а выглядит это как залипшая настройка.
	]]
	function hideEspVisuals(key)
		for _, entry in pairs(espEntries) do
			if key == "Tracers" and not ESP.Tracers then
				entry.tracer.Visible = false
			end
			if key == "OffScreen" and not ESP.OffScreen then
				entry.arrow.Visible = false
				entry.arrowLabel.Visible = false
			end
			if key == "Highlight" and not ESP.Highlight and entry.highlight then
				entry.highlight.Enabled = false
			end
		end
	end

	Players.PlayerRemoving:Connect(removeEntry)

	--[[
		Свой ли это игрок для фильтра «Скрывать союзников».

		Сравниваются ИМЕНА КОМАНД из иерархии, а не Player.Team: в этом плейсе
		штатные Teams не используются, Player.Team пустой у всех, и прежняя
		проверка `other.Team == player.Team` практически никогда не давала
		true - фильтр молча не работал, а заодно все красились «врагом».
		NO_TEAM союзником не считается: если команду определить не удалось,
		лучше показать игрока, чем спрятать.
	]]
	local function isAlly(otherTeam)
		if otherTeam == NO_TEAM then
			return false
		end
		return otherTeam == teamNameOf(player, character)
	end

	--[[
		КУДА ЦЕЛИТСЯ ТРЕЙСЕР (и вместе с ним стрелка 360 и дистанция).

		Пользователь просил «чтобы конец трейсеров был в теле игрока».
		Геометрия самой линии тут не при чём: она проверена тестом, который
		реконструирует концы отрезка, и конец попадает ровно в проекцию
		заданной точки. Дело в том, КАКУЮ точку ей давали.

		Раньше это была HumanoidRootPart. В стандартном риге Roblox она
		внутри корпуса, и для выживших (R6 - имена частей видны в esp2.txt,
		строка 5157) всё было нормально. Но киллеры этого плейса - кастомные
		импортированные модели, а у импортированного меша начало координат
		почти всегда в СТУПНЯХ: HumanoidRootPart лежит на уровне земли, и
		линия приходила в ноги или под ноги, а не в тело.

		Порядок выбора:
		  1. UpperTorso (R15) или Torso (R6) - центр реальной части корпуса.
		     Для выживших срабатывает первый пункт, то есть для них ничего
		     не меняется (в R6 Torso и HumanoidRootPart совпадают).
		  2. ЦЕНТР ОГРАНИЧИВАЮЩЕГО ПАРАЛЛЕЛЕПИПЕДА модели (GetBoundingBox).
		     Работает для ЛЮБОГО рига, включая кастомный без узнаваемых имён
		     частей: центр габаритов модели физически лежит внутри неё.
		     Под pcall - GetBoundingBox есть у Model, а персонаж теоретически
		     может оказаться другим классом.
		  3. HumanoidRootPart как была - если и габариты не прочитались.
		  4. любая деталь модели: лучше, чем ничего.

		Точка ОДНА для трейсера, стрелки 360 и дистанции: иначе линия,
		указатель и подпись расходились бы между собой.

		ЦЕНА: функция зовётся каждый кадр на каждого игрока, как и остальные
		поиски в updateEsp (HumanoidRootPart, Humanoid, Vanities).
		FindFirstChild - хеш-поиск, это дёшево; GetBoundingBox обходит детали
		модели, но до него доходят только риги без Torso/UpperTorso, то есть
		считанные киллеры за кадр. Кешировать ссылку на найденный корпус можно
		(в entry, сбрасывая в bindEspCharacter), но габариты всё равно
		пришлось бы считать заново - модель движется. Если понадобится
		экономить, начинать с кеша корпуса, а не с отказа от габаритов.
	]]
	local TORSO_NAMES = { "UpperTorso", "Torso" }

	local function aimPointOf(char, root)
		for _, name in ipairs(TORSO_NAMES) do
			local part = char:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				return part.Position
			end
		end

		local ok, center = pcall(function()
			local boxCFrame = char:GetBoundingBox()
			return boxCFrame.Position
		end)
		if ok and center then
			return center
		end

		if root then
			return root.Position
		end

		local any = char:FindFirstChildWhichIsA("BasePart")
		return any and any.Position or nil
	end

	local function buildEspText(other, humanoidOther, distance, caretaker)
		local lines = {}

		if ESP.Names then
			local name = other.DisplayName ~= other.Name
					and (other.DisplayName .. " (@" .. other.Name .. ")")
				or other.Name
			-- Подпись, а не только цвет: цвет легко спутать при слабом
			-- освещении, а знать про Caretaker важно.
			if caretaker then
				name = name .. " [CARETAKER]"
			end
			table.insert(lines, name)
		end

		local details = {}
		if ESP.Health and humanoidOther then
			local maxHealth = humanoidOther.MaxHealth
			if maxHealth > 0 and maxHealth < math.huge then
				table.insert(
					details,
					string.format(
						"%d/%d hp",
						math.floor(humanoidOther.Health + 0.5),
						math.floor(maxHealth + 0.5)
					)
				)
			else
				table.insert(details, string.format("%d hp", math.floor(humanoidOther.Health + 0.5)))
			end
		end
		if ESP.Distance then
			table.insert(details, string.format("%dm", math.floor(distance + 0.5)))
		end
		if #details > 0 then
			table.insert(lines, table.concat(details, "  "))
		end

		return table.concat(lines, "\n")
	end

	--[[
		Проекция цели считается ОДИН раз на игрока в updateEsp и передаётся
		сюда: WorldToViewportPoint нужен и трейсеру, и 360-указателю, а зовётся
		он каждый кадр на каждого игрока. screenPoint приходит nil, когда обе
		настройки выключены и проекцию считать было незачем.
	]]
	local function updateTracer(entry, camera, screenPoint, onScreen, color)
		if not ESP.Tracers or not (screenPoint and onScreen) then
			entry.tracer.Visible = false
			return
		end

		local viewport = camera.ViewportSize
		local originX, originY = viewport.X * 0.5, viewport.Y
		local dx, dy = screenPoint.X - originX, screenPoint.Y - originY
		local length = math.sqrt(dx * dx + dy * dy)

		entry.tracer.Size = UDim2.fromOffset(ESP.TracerThickness, length)
		entry.tracer.Position = UDim2.fromOffset(originX + dx * 0.5, originY + dy * 0.5)
		-- нулевой поворот направлен вниз по экрану, отсюда atan2(-dx, dy)
		entry.tracer.Rotation = math.deg(math.atan2(-dx, dy))
		entry.tracer.BackgroundColor3 = color
		entry.tracer.Visible = true
	end

	--[[
		360: УКАЗАТЕЛЬ НА ЦЕЛЬ ВНЕ КАДРА.

		Зачем: билборд и подсветка существуют только для того, что попало
		в кадр. Киллер, заходящий со спины, для обычного ESP не существует
		вообще - а это ровно тот случай, когда информация нужна.

		НАПРАВЛЕНИЕ СЧИТАЕТСЯ НЕ ПО WorldToViewportPoint, и это важно.
		Для точки ЗА камерой проекция зеркалится: цель сзади-справа даёт
		экранную координату слева, и стрелка показывала бы в сторону, куда
		поворачиваться ДОЛЬШЕ. Поэтому берётся направление в системе
		координат камеры:
		    x = dir · RightVector, y = dir · UpVector
		и на экран кладётся (x, -y) - без деления на глубину, то есть без
		переворота за спиной. Цель сзади-справа честно даёт "вправо".

		Плата за это: цель на 90 и на 170 градусов вправо дают одинаковое
		направление стрелки. Для указателя по краю экрана иначе и не бывает
		- за расстоянием отвечает подпись, за точным углом сам поворот.

		Строго за спиной x и y обращаются в нуль (делить не на что) -
		тогда стрелка ставится вниз: "цель позади" читается однозначно.
	]]
	local function updateOffScreen(entry, camera, worldPosition, color, onScreen, other, distance)
		--[[
			onScreen от WorldToViewportPoint уже включает и выход за границы
			кадра, и нахождение за камерой. Пока цель видна, указатель
			молчит: над ней и так висит билборд.
		]]
		if not ESP.OffScreen or onScreen then
			entry.arrow.Visible = false
			entry.arrowLabel.Visible = false
			return
		end

		local cameraFrame = camera.CFrame
		local toTarget = worldPosition - cameraFrame.Position
		if toTarget.Magnitude <= 0 then
			entry.arrow.Visible = false
			entry.arrowLabel.Visible = false
			return
		end

		local direction = toTarget.Unit
		local ux = direction:Dot(cameraFrame.RightVector)
		local uy = -direction:Dot(cameraFrame.UpVector) -- экранная Y растёт вниз

		local length = math.sqrt(ux * ux + uy * uy)
		if length < 1e-4 then
			ux, uy, length = 0, 1, 1 -- строго за спиной: вниз
		else
			ux, uy = ux / length, uy / length
		end

		--[[
			Точка на рамке: идём из центра по (ux, uy) до первой из двух
			границ. Берётся МЕНЬШИЙ коэффициент - тот, который упирается
			раньше, иначе стрелка вылезала бы за угол экрана.
			Нулевую составляющую пропускаем: деления на ноль здесь быть
			не должно, а math.huge как "эта граница недостижима" корректен.
		]]
		local viewport = camera.ViewportSize
		local centerX, centerY = viewport.X * 0.5, viewport.Y * 0.5
		local limitX = math.max(centerX - ESP.OffScreenMargin, 1)
		local limitY = math.max(centerY - ESP.OffScreenMargin, 1)

		local scaleX = math.abs(ux) > 1e-4 and (limitX / math.abs(ux)) or math.huge
		local scaleY = math.abs(uy) > 1e-4 and (limitY / math.abs(uy)) or math.huge
		local scale = math.min(scaleX, scaleY)

		local posX = centerX + ux * scale
		local posY = centerY + uy * scale

		entry.arrow.Position = UDim2.fromOffset(posX, posY)
		-- при Rotation = 0 острие смотрит вверх, отсюда atan2(ux, -uy)
		entry.arrow.Rotation = math.deg(math.atan2(ux, -uy))
		for _, bar in ipairs(entry.arrowBars) do
			bar.BackgroundColor3 = color
		end
		entry.arrow.Visible = true

		-- Подпись НЕ ребёнок стрелки: Rotation наследуется, и текст
		-- заваливался бы вместе с острием. Сдвигается к центру экрана,
		-- чтобы не уезжать за край вместе со стрелкой.
		local labelText = ""
		if ESP.Names then
			local name = other.Name
			if #name > 12 then
				name = string.sub(name, 1, 12) .. "…"
			end
			labelText = name
		end
		if ESP.Distance then
			local distanceText = string.format("%dm", math.floor(distance + 0.5))
			labelText = labelText == "" and distanceText or (labelText .. " " .. distanceText)
		end

		if labelText == "" then
			entry.arrowLabel.Visible = false
			return
		end

		local labelOffset = ESP.OffScreenSize * 0.9
		entry.arrowLabel.Position = UDim2.fromOffset(posX - ux * labelOffset, posY - uy * labelOffset)
		entry.arrowLabel.Text = labelText
		entry.arrowLabel.TextColor3 = color
		entry.arrowLabel.Visible = true
	end

	function updateEsp()
		local camera = getCamera()
		if not camera then
			return
		end
		local cameraPosition = camera.CFrame.Position

		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local entry = espEntries[other] or createEntry(other)
				local char = other.Character

				if entry.boundCharacter ~= char then
					bindEspCharacter(entry, char)
				end

				local otherRoot = char and char:FindFirstChild("HumanoidRootPart")
				local otherHumanoid = char and char:FindFirstChildOfClass("Humanoid")

				if not (char and char.Parent and otherRoot) then
					hideEntry(entry)
					continue
				end

				if otherHumanoid and otherHumanoid.Health <= 0 then
					hideEntry(entry)
					continue
				end

				--[[
					Caretaker считаем ДО фильтра союзников: носитель этой
					способности - выживший, то есть чаще всего союзник, и
					«Скрывать союзников» спрятало бы ровно того, кого просили
					показать. Поэтому для него фильтр не действует.
				]]
				local caretaker = ESP.MarkCaretaker and hasCaretaker(char)

				-- Команда берётся из иерархии тем же способом, что и в панели
				-- игроков: Player.Team в этом плейсе пустой у всех.
				local teamName = teamNameOf(other, char)

				if ESP.TeamCheck and isAlly(teamName) and not caretaker then
					hideEntry(entry)
					continue
				end

				--[[
					ОПОРНАЯ ТОЧКА - середина корпуса, а не HumanoidRootPart:
					у кастомных моделей плейса та лежит у ступней, и трейсер
					приходил игроку в ноги. Подробно у aimPointOf.
					Она же используется и для дистанции: цифра в метке должна
					считаться до того места, куда указывает линия.
				]]
				local aimPoint = aimPointOf(char, otherRoot) or otherRoot.Position

				local distance = (aimPoint - cameraPosition).Magnitude
				if ESP.MaxDistance > 0 and distance > ESP.MaxDistance then
					hideEntry(entry)
					continue
				end

				-- Цвет команды, тот же что в списке игроков: Survivor голубой,
				-- Killer красный, Ghost/Lobby серые.
				local color = colorForTeam(teamName)

				-- Цвет способности важнее командного: команда и так видна по
				-- позиции в списке игроков, а Caretaker больше нигде не виден.
				if caretaker then
					color = CARETAKER.Color
				end

				if entry.highlight then
					entry.highlight.Enabled = ESP.Highlight
					entry.highlight.FillColor = color
					entry.highlight.OutlineColor = color
					entry.highlight.FillTransparency = ESP.FillTransparency
				end

				local text = buildEspText(other, otherHumanoid, distance, caretaker)
				if text ~= "" then
					entry.label.Text = text
					entry.label.TextColor3 = color
					entry.billboard.Enabled = true
				else
					entry.billboard.Enabled = false
				end

				--[[
					Проекция считается ЗДЕСЬ, один раз: она нужна и трейсеру,
					и 360-указателю, а WorldToViewportPoint зовётся каждый
					кадр на каждого игрока. Если обе настройки выключены -
					не считаем вовсе.
					Опорная точка одна и та же (aimPoint, середина корпуса),
					иначе трейсер и стрелка расходились бы.
				]]
				local screenPoint, onScreen = nil, false
				if ESP.Tracers or ESP.OffScreen then
					screenPoint, onScreen = camera:WorldToViewportPoint(aimPoint)
				end

				updateTracer(entry, camera, screenPoint, onScreen, color)
				updateOffScreen(entry, camera, aimPoint, color, onScreen, other, distance)
			end
		end
	end
end

--=========================== ИНТЕРФЕЙС ===========================

local COLORS = {
	Background = Color3.fromRGB(24, 24, 28),
	Header = Color3.fromRGB(34, 34, 40),
	Off = Color3.fromRGB(48, 48, 56),
	On = Color3.fromRGB(56, 142, 96),
	Bind = Color3.fromRGB(40, 40, 48),
	Capture = Color3.fromRGB(190, 140, 50),
	Reject = Color3.fromRGB(170, 60, 60),
	Text = Color3.fromRGB(235, 235, 240),
	Muted = Color3.fromRGB(145, 145, 158),
}

local function new(className, props)
	local inst = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

--[[
	ШИРОКОЕ ОКНО С ВКЛАДКАМИ.

	Раньше это была одна узкая колонка на 264 пикселя со всеми разделами
	подряд: настройки автоблока лежали в самом низу, и до них надо было
	доскроллить в бою. Теперь слева рейка вкладок, справа страница.

	Каждая вкладка - отдельный ScrollingFrame. Не один общий с прыжком по
	позиции: у страниц разная высота, и общий скролл каждый раз
	восстанавливался бы не там, где его оставили.

	Фабрики строк (makeSection/makeFeatureRow/...) парентят в переменную
	body, а не в конкретный фрейм. Перед сборкой раздела body переставляется
	на нужную страницу - поэтому сборка меню ниже читается почти как раньше.
]]
local screenGui = new("ScreenGui", {
	Name = "AdminMenu",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 100,
	Parent = playerGui,
})

local MENU_WIDTH = 620
local MENU_HEIGHT = 470
local TAB_RAIL_WIDTH = 152
local HEADER_HEIGHT = 34

local main = new("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(MENU_WIDTH, MENU_HEIGHT),
	Position = UDim2.new(0, 24, 0.5, -MENU_HEIGHT // 2),
	BackgroundColor3 = COLORS.Background,
	BorderSizePixel = 0,
	Visible = false,
	Parent = screenGui,
})
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = main })
new("UIStroke", { Color = Color3.fromRGB(60, 60, 70), Thickness = 1, Parent = main })

local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
	BackgroundColor3 = COLORS.Header,
	BorderSizePixel = 0,
	Parent = main,
})
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = header })
new("Frame", { -- прячет скругление снизу шапки
	Size = UDim2.new(1, 0, 0, 8),
	Position = UDim2.new(0, 0, 1, -8),
	BackgroundColor3 = COLORS.Header,
	BorderSizePixel = 0,
	Parent = header,
})

new("TextLabel", {
	Size = UDim2.new(1, -40, 1, 0),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "ADMIN MENU",
	TextSize = 13,
	TextColor3 = COLORS.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

-- Заголовок вкладки в шапке: в широком окне видно сразу, где ты находишься
local headerHint = new("TextLabel", {
	Name = "HeaderHint",
	Size = UDim2.new(1, -180, 1, 0),
	Position = UDim2.fromOffset(140, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextSize = 12,
	TextColor3 = COLORS.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

local closeButton = new("TextButton", {
	Size = UDim2.fromOffset(26, 26),
	Position = UDim2.new(1, -30, 0, 4),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "X",
	TextSize = 13,
	TextColor3 = COLORS.Muted,
	AutoButtonColor = false,
	Parent = header,
})

-- Рейка вкладок слева
local tabRail = new("Frame", {
	Name = "Tabs",
	Size = UDim2.new(0, TAB_RAIL_WIDTH, 1, -HEADER_HEIGHT),
	Position = UDim2.fromOffset(0, HEADER_HEIGHT),
	BackgroundColor3 = Color3.fromRGB(20, 20, 24),
	BorderSizePixel = 0,
	Parent = main,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	Parent = tabRail,
})
new("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = tabRail,
})

local content = new("Frame", {
	Name = "Content",
	Size = UDim2.new(1, -TAB_RAIL_WIDTH, 1, -HEADER_HEIGHT),
	Position = UDim2.fromOffset(TAB_RAIL_WIDTH, HEADER_HEIGHT),
	BackgroundTransparency = 1,
	Parent = main,
})

local body = nil -- текущая цель сборки, переставляется setPage
local tabButtons = {} -- [pageId] = TextButton
local tabPages = {} -- [pageId] = ScrollingFrame
local tabHints = {} -- [pageId] = подсказка в шапке
local tabOrder = 0

local function showTab(pageId)
	if not tabPages[pageId] then
		return
	end
	for id, page in pairs(tabPages) do
		page.Visible = id == pageId
	end
	for id, button in pairs(tabButtons) do
		local on = id == pageId
		button.BackgroundColor3 = on and COLORS.Bind or Color3.fromRGB(20, 20, 24)
		button.TextColor3 = on and COLORS.Text or COLORS.Muted
	end
	headerHint.Text = tabHints[pageId] or ""
end

local function makeTab(pageId, label, hint)
	tabOrder += 1

	local page = new("ScrollingFrame", {
		Name = "Page_" .. pageId,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = COLORS.Muted,
		Visible = false,
		Parent = content,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = page,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = page,
	})

	local button = new("TextButton", {
		Name = "Tab_" .. pageId,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = tabOrder,
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = label,
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		Parent = tabRail,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })

	button.MouseButton1Click:Connect(function()
		showTab(pageId)
	end)

	tabPages[pageId] = page
	tabButtons[pageId] = button
	tabHints[pageId] = hint or ""
	return page
end

-- Переставляет цель сборки. Всё, что создаётся после вызова, ложится
-- на эту страницу.
local function setPage(pageId)
	body = tabPages[pageId]
end

local orderCounter = 0
local function nextOrder()
	orderCounter += 1
	return orderCounter
end

local function makeSection(text)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextSize = 11,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
end

-- Пояснение под заголовком раздела: в широком окне для него есть место,
-- и оно снимает половину вопросов "что эта галка делает".
local function makeNote(text)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = text,
		TextSize = 11,
		TextColor3 = COLORS.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = body,
	})
end

--=========================== СПИСОК ИГРОКОВ ===========================

--[[
	Панель в правом верхнем углу. Игроки сгруппированы по командам,
	в правой колонке дальность и стамина.

	Отдельный ScreenGui, а не часть меню: список должен быть виден, когда
	меню закрыто. Собственный DisplayOrder ниже меню, чтобы окно настроек
	перекрывало панель, а не наоборот.
]]

local listGui = new("ScreenGui", {
	Name = "AdminPlayerList",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 95,
	Parent = playerGui,
})

local listFrame = new("Frame", {
	Name = "List",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -LIST.OffsetX, 0, LIST.OffsetY),
	Size = UDim2.fromOffset(LIST.Width, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLORS.Background,
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Visible = false,
	Parent = listGui,
})
new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = listFrame })
new("UIStroke", { Color = Color3.fromRGB(60, 60, 70), Thickness = 1, Parent = listFrame })
new("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	Parent = listFrame,
})
new("UIListLayout", {
	Padding = UDim.new(0, 1),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = listFrame,
})

-- Строка-заголовок панели. Не входит в пул: живёт всегда, LayoutOrder 0.
local listTitleName = new("TextLabel", {
	Name = "Title",
	Size = UDim2.new(1, -LIST.ValueWidth, 0, LIST.HeaderHeight),
	LayoutOrder = 0,
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "ИГРОКИ",
	TextSize = 12,
	TextColor3 = COLORS.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = listFrame,
})

-- Легенда парентится в сам заголовок, а не в панель: иначе UIListLayout
-- увёл бы её на отдельную строку. Position 1,0 ставит её сразу за
-- заголовком, ширина ValueWidth даёт правый край панели.
local listTitleLegend = new("TextLabel", {
	Name = "Legend",
	Size = UDim2.fromOffset(LIST.ValueWidth, LIST.HeaderHeight),
	Position = UDim2.new(1, 0, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextSize = 10,
	TextColor3 = COLORS.Muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = listTitleName,
})

-- Пул строк. Игроки появляются и уходят каждый раунд, пересоздавать
-- TextLabel'ы 10 раз в секунду - мусор для сборщика на ровном месте.
local listRows = {}

local function acquireRow(index)
	local row = listRows[index]
	if not row then
		local frame = new("Frame", {
			Name = "Row" .. index,
			Size = UDim2.new(1, 0, 0, LIST.RowHeight),
			BackgroundTransparency = 1,
			Parent = listFrame,
		})
		local nameLabel = new("TextLabel", {
			Size = UDim2.new(1, -LIST.ValueWidth, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = "",
			TextSize = 12,
			TextColor3 = COLORS.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		})
		local valueLabel = new("TextLabel", {
			Size = UDim2.new(0, LIST.ValueWidth, 1, 0),
			Position = UDim2.new(1, -LIST.ValueWidth, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Code, -- монофон: колонка не пляшет при смене цифр
			Text = "",
			TextSize = 12,
			TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})
		row = { frame = frame, name = nameLabel, value = valueLabel }
		listRows[index] = row
	end
	row.frame.LayoutOrder = index
	row.frame.Visible = true
	return row
end

local function writeTeamHeader(index, teamName, count, color)
	local row = acquireRow(index)
	row.frame.Size = UDim2.new(1, 0, 0, LIST.HeaderHeight)
	row.name.Font = Enum.Font.GothamBold
	row.name.TextSize = 11
	row.name.TextColor3 = color
	row.name.Text = string.upper(teamName)
	row.value.TextColor3 = color
	row.value.Text = tostring(count)
end

local function writePlayerRow(index, text, value, color)
	local row = acquireRow(index)
	row.frame.Size = UDim2.new(1, 0, 0, LIST.RowHeight)
	row.name.Font = Enum.Font.Gotham
	row.name.TextSize = 12
	row.name.TextColor3 = color
	row.name.Text = text
	row.value.TextColor3 = COLORS.Text
	row.value.Text = value
end

local function writeNoteRow(index, text)
	local row = acquireRow(index)
	row.frame.Size = UDim2.new(1, 0, 0, LIST.RowHeight)
	row.name.Font = Enum.Font.Gotham
	row.name.TextSize = 11
	row.name.TextColor3 = COLORS.Muted
	row.name.Text = text
	row.value.Text = ""
end

--[[
	Команда игрока.

	Сначала иерархия: в этом плейсе персонажи лежат в
	workspace.GameAssets.Teams.<Команда>.<Модель>, поэтому родитель модели -
	это и есть команда. Отдельно проверяется GameAssets.Other.LobbyPlayers -
	там персонажи до начала раунда.
	Player.Team здесь обычно пустой, но остаётся запасным вариантом для
	плейсов со штатными Teams.
]]
-- Без local: имя объявлено форвард-локалом в секции ESP, которой цвета
-- команд нужны раньше. С local здесь создалась бы вторая переменная,
-- и ESP остался бы с nil.
function teamNameOf(other, char)
	if char then
		local folder = char.Parent
		if folder then
			if folder.Name == LOBBY_FOLDER then
				return LOBBY_TEAM
			end
			if folder.Parent and folder.Parent.Name == TEAM_FOLDER_PARENT then
				return folder.Name
			end
		end
	end
	if other.Team then
		return other.Team.Name
	end
	return NO_TEAM
end

local TEAM_RANK = {}
for index, name in ipairs(TEAM_ORDER) do
	TEAM_RANK[name] = index
end

--[[
	СВОЯ РОЛЬ В РАУНДЕ.

	Если скрипт запущен у КИЛЛЕРА, автоблок и предупреждение отключаются
	на весь раунд (просьба пользователя). Причина не косметическая:
	  - блока у киллера нет вообще, значит автоблок просто жал бы клавишу
	    чужой способности и тратил её впустую;
	  - предупреждение «киллер рядом» у самого киллера показывало бы
	    ДРУГОГО киллера или ничего - и в обоих случаях мешало.

	Роль определяется тем же teamNameOf, что и список игроков: персонаж
	лежит в workspace.GameAssets.Teams.Killer. Пересчитывается по таймеру
	(раунды меняются, и роль вместе с ними), а не запоминается один раз.
]]
local selfIsKiller = false

local function updateSelfRole()
	local wasKiller = selfIsKiller
	if character and character.Parent then
		selfIsKiller = teamNameOf(player, character) == KILLER_TEAM
	else
		--[[
			Персонажа нет (смерть, наблюдение, загрузка). Роль НЕ сбрасываем:
			между смертью и респавном она не меняется, а мигание
			«киллер/не киллер» дёргало бы баннер и статус.
		]]
		selfIsKiller = wasKiller
	end
	return selfIsKiller ~= wasKiller
end

local function teamRank(name)
	if name == NO_TEAM then
		return #TEAM_ORDER + 2 -- всегда последняя
	end
	return TEAM_RANK[name] or (#TEAM_ORDER + 1)
end

-- Локальная: снаружи do-блока ESP она не нужна - метки красятся своим
-- colorForTeam по той же таблице TEAM_COLORS.
local function teamColor(name)
	return TEAM_COLORS[name] or COLORS.Text
end

-- Первое числовое значение из перечисленных атрибутов. GetAttribute на
-- несуществующем имени возвращает nil, но под pcall на случай, если
-- персонаж уже удаляется.
local function readNumberAttribute(char, keys)
	for _, key in ipairs(keys) do
		local ok, value = pcall(function()
			return char:GetAttribute(key)
		end)
		if ok and type(value) == "number" and value == value then
			return value, key
		end
	end
	return nil, nil
end

local staminaKeyReported = false
local staminaMissReported = false

--[[
	Максимум стамины персонажа.

	Атрибут MaxStamina чужих игроков клиенту НЕ репликуется, поэтому для
	них он почти всегда nil - максимум берётся из таблицы по атрибуту
	"Killer" (какой убийца), как в esp.txt.

	Значение из атрибута тоже отбрасывается, если оно бесконечное или
	абсурдно большое: это признак включённой Infinite Stamina, и дробь
	"73/inf" ничего не сообщает.
]]
local function maxStaminaOf(char)
	local fromAttribute = readNumberAttribute(char, MAX_STAMINA_KEYS)
	if fromAttribute and fromAttribute > 0 and fromAttribute < math.huge then
		return fromAttribute
	end

	for _, key in ipairs(KILLER_NAME_KEYS) do
		local okKiller, killer = pcall(function()
			return char:GetAttribute(key)
		end)
		if okKiller and type(killer) == "string" and killer ~= "" then
			return KILLER_MAX_STAMINA[killer] or DEFAULT_MAX_STAMINA
		end
	end
	return DEFAULT_MAX_STAMINA
end

-- Стамина в этом плейсе - атрибут персонажа, а не свойство Humanoid.
local function staminaTextOf(char)
	if not char then
		return nil, nil
	end
	local current, foundKey = readNumberAttribute(char, STAMINA_KEYS)
	if not current then
		return nil, nil
	end
	local maxStamina = maxStaminaOf(char)
	--[[
		Под бесконечной стаминой значение уходит выше штатного максимума
		(а то и в саму бесконечность). Обрезать его нельзя - это правда,
		но дробь "500/100" выглядит сломанной, поэтому печатается одно число.
	]]
	if current >= math.huge then
		return "∞", foundKey
	end
	if current > maxStamina then
		return string.format("%d", math.floor(current + 0.5)), foundKey
	end
	return string.format("%d/%d", math.floor(current + 0.5), math.floor(maxStamina + 0.5)), foundKey
end

--=========================== БЕСКОНЕЧНАЯ СТАМИНА ===========================

--[[
	Подмена предела стамины. О самом способе - в комментарии к таблице
	STAMINA в начале файла.

	Держится на слушателе, а не на одном присваивании: плейс переписывает
	MaxStamina сам (при спавне, при выдаче киллера, при своих пересчётах).
	Ровно так же сделано в esp.txt - там на MaxStamina тоже висит
	GetAttributeChangedSignal.
]]
local staminaConnections = {} -- соединения текущего персонажа
local staminaOriginalMax = nil -- что было до нас, чтобы вернуть при выключении

local function disconnectStaminaWatch()
	for _, connection in ipairs(staminaConnections) do
		connection:Disconnect()
	end
	table.clear(staminaConnections)
end

local function pushStamina()
	if not (character and character.Parent) then
		return
	end
	pcall(function()
		if character:GetAttribute("MaxStamina") ~= STAMINA.Value then
			character:SetAttribute("MaxStamina", STAMINA.Value)
		end
		--[[
			Fatigue - отдельный тормоз плейса: при 1 спринт запрещён
			независимо от стамины (в esp.txt это отдельный тумблер
			"No Fatigue"). Без него бесконечная стамина ощущалась бы
			сломанной: полоска полная, а бежать нельзя.
		]]
		if STAMINA.NoFatigue and character:GetAttribute("Fatigue") == 1 then
			character:SetAttribute("Fatigue", 0)
		end
	end)
end

local function applyStamina(enabled)
	disconnectStaminaWatch()

	if not (character and character.Parent) then
		return
	end

	if not enabled then
		--[[
			Возвращаем, что было. Если исходное значение неизвестно или само
			было бесконечным (скрипт перезапустили поверх включённого чита),
			берём штатный максимум по имени киллера - иначе персонаж остался
			бы с math.huge навсегда.
		]]
		pcall(function()
			local restore = staminaOriginalMax
			if type(restore) ~= "number" or restore ~= restore or restore >= math.huge then
				restore = nil
			end
			character:SetAttribute("MaxStamina", restore or maxStaminaOf(character))
		end)
		staminaOriginalMax = nil
		return
	end

	-- Запоминаем исходный максимум до первой подмены
	local okOriginal, original = pcall(function()
		return character:GetAttribute("MaxStamina")
	end)
	if okOriginal and type(original) == "number" and original < math.huge then
		staminaOriginalMax = original
	end

	pushStamina()

	local okSignal = pcall(function()
		table.insert(
			staminaConnections,
			character:GetAttributeChangedSignal("MaxStamina"):Connect(pushStamina)
		)
		if STAMINA.NoFatigue then
			table.insert(
				staminaConnections,
				character:GetAttributeChangedSignal("Fatigue"):Connect(pushStamina)
			)
		end
	end)
	if not okSignal then
		warn(
			"[AdminMenu] бесконечная стамина: не удалось подписаться на MaxStamina. "
				.. "Значение поставлено один раз, но плейс может вернуть своё."
		)
	end
end

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

	-- Автоблок без VirtualInputManager нажать некому: тумблер гасим, чтобы
	-- он не выглядел работающим.
	if featureId == "autoblock" and (not autoblockInputAvailable or autoblockInputBlocked) then
		button.BackgroundColor3 = COLORS.Off
		button.TextColor3 = COLORS.Muted
		button.Text = "Автоблок  [нет доступа к вводу]"
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
	-- Включать автоблок, когда нажатия отправлять нечем, бессмысленно:
	-- тумблер бы горел ON, а блок не ставился.
	if featureId == "autoblock" and not state.autoblock then
		if not autoblockInputAvailable or autoblockInputBlocked then
			refreshToggle("autoblock")
			refreshAutoblockStatus()
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
local function refreshConfigStatus()
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
]]
