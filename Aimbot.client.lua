--[[
	АИМБОТ НА ИГРРОКОВ И NPC + ТРИГГЕР-БОТ (LocalScript)

	Куда положить: StarterPlayer -> StarterPlayerScripts, тип объекта LocalScript.
	Запуск через executor - то же самое: вставить содержимое файла и выполнить.
	Для игры с папкой модулей есть AdminMenuLoader (это отдельный скрипт,
	загрузчик для него не нужен).

	ФУНКЦИИ:
	  - аим на игроков И NPC: цель - любой персонаж с Humanoid и
	    HumanoidRootPart, неважно игрок это или модель с сервера;
	  - КРУГ ЗАХВАТА (FOV): цель берётся только внутри круга в центре экрана,
	    радиус правится в меню, радиус 0 = вся плоскость экрана;
	  - ВЫБОР ЦЕЛИ: БЛИЖАЙШАЯ К ПРИЦЕЛУ (экранное расстояние до центра,
	    не угол и не дистанция) - стреляешь мимо одного, аим не перетягивает;
	  - ПЛАВНОСТЬ (smoothness): камера доворачивается на часть угла за кадр;
	    1 = мгновенно, больше = мягче, регулируется;
	  - проверка стен (WallCheck): через raycast - цель за стеной не берётся,
	    тумблер, по умолчанию ВКЛ;
	  - проверка команды: в играх со штатными Team - союзников не берёт
	    (Player.Team). В плейсах без Team все считаются врагами;
	  - живые цели: Humanoid.Health > 0, мёртвых не берёт;
	  - графический круг FOV в центре экрана (включается с аимботом);
	  - ТРИГГЕР-БОТ: автовыстрел, когда прицел на цели. Райкаст из центра
	    экрана (WallCheck сам собой), тумблер в меню + бинд T (переключатель),
	    задержка перед выстрелом и кулдаун между выстрелами правятся.
	    Нужен executor (VirtualInputManager), без него тумблер не включается;
	  - ESP (перенесено из AdminMenu, do-блок ESP в 20_world): подсветка
	    сквозь стены (Highlight), метка имя/здоровье/дистанция (BillboardGui),
	    трейсеры снизу экрана в тело и стрелки 360 по краю для целей вне
	    кадра. Цели те же, что у аима - игроки И NPC. Цвет: враг красный,
	    союзник зелёный (штатный Player.Team), NPC жёлтый;
	  - БИНДЫ В TOGGLE (просьба пользователя: «переведи все кнопки в toggle»):
	    нажал - включилось, нажал ещё раз - выключилось. Режим бинда аима
	    правится тумблером «Бинд аима: toggle» (false = старое удержание);
	  - меню простое: экран-панель с тумблерами и степперами (Rayfield
	    не тащится - скрипт самодостаточный, как AdminMenu).

	Клавиши по умолчанию: RightMouse - аим (toggle), T - триггер-бот (toggle),
	RightCtrl - меню.
	В меню: Аимбот, Бинд аима: toggle, WallCheck, TeamCheck, Триггер-бот,
	степперы FOV (0-500, шаг 10), Плавность (1-20), Дистанция (0-5000),
	Задержка выстрела (0-1 с), Пауза между выстрелами (0.05-2 с), тумблеры
	ESP (подсветка/имена/здоровье/дистанция/трейсеры/стрелки 360) и степпер
	дистанции показа, бинды.

	Работает только на клиенте: аим крутит КАМЕРУ, а не выстрелы - сервер
	видит обычный ввод мыши. Это мягче хуков на ремоуты и не ловится
	серверной проверкой прицела, но анти-чит может засчитать странную
	скорость поворота камеры - см. ЗАМЕТКИ.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

--============================ НАСТРОЙКИ ============================

local SETTINGS = {
	Enabled = false, -- аим работает (бинд или тумблер)
	ToggleAim = true, -- бинд аима ПЕРЕКЛЮЧАТЕЛЬ, а не удержание (просьба
	-- пользователя: «переведи все кнопки в toggle»); false = удержание
	WallCheck = true, -- цели за стеной не брать
	TeamCheck = true, -- союзников (штатные Team) не брать
	TriggerBot = false, -- автовыстрел, когда прицел на цели внутри круга
	Fov = 120, -- радиус круга захвата, px (0 = весь экран)
	FovStep = 10,
	FovMin = 0,
	FovMax = 500,
	Smoothness = 3, -- 1 = мгновенно, больше = мягче
	SmoothMin = 1,
	SmoothMax = 20,
	MaxDistance = 2000, -- дальше этого цели не берутся, 0 = без лимита
	TriggerDelay = 0.1, -- задержка перед выстрелом, с (0 = сразу)
	TriggerCooldown = 0.15, -- пауза между выстрелами, с
	-- ESP (перенесено из AdminMenu)
	Esp = false, -- ESP целиком (подсветка/метки/трейсеры/стрелки)
	EspHighlight = true, -- подсветка сквозь стены (Highlight)
	EspNames = true, -- имя в метке над головой
	EspHealth = true, -- здоровье в метке
	EspDistance = true, -- дистанция в метке
	EspTracers = false, -- трейсеры снизу экрана в тело
	EspOffScreen = false, -- стрелки 360 по краю для целей вне кадра
	EspFillTransparency = 0.65, -- заливка подсветки (0 = сплошная)
	EspTracerThickness = 1,
	EspOffScreenSize = 34, -- размер стрелки 360, px
	EspOffScreenThickness = 3,
	EspOffScreenMargin = 30, -- отступ стрелки от края экрана, px
	EspMaxDistance = 0, -- 0 = без лимита (отдельно от лимита аима)
}

local BINDS = {
	menu = Enum.KeyCode.RightControl,
	aim = Enum.UserInputType.MouseButton2, -- переключатель (ToggleAim) или удержание
	trigger = Enum.KeyCode.T, -- тумблер триггер-бота
}

-- Цвет круга FOV и видимость панели
local FOV_COLOR = Color3.fromRGB(120, 200, 255)
local FOV_TRANSPARENCY = 0.35

-- Цвета ESP: враг красный, союзник зелёный, NPC жёлтый (в AdminMenu цвета
-- брались из команд иерархии DOD - здесь аимбот универсальный, проще).
local ESP_ENEMY_COLOR = Color3.fromRGB(255, 80, 80)
local ESP_ALLY_COLOR = Color3.fromRGB(90, 200, 120)
local ESP_NPC_COLOR = Color3.fromRGB(255, 200, 80)

-- Цели ищутся среди игроков и NPC. NPC = модели с Humanoid+HumanoidRootPart,
-- у которых НЕТ игрока (GetPlayerFromCharacter == nil) и которые лежат в
-- workspace. Модели в ReplicatedStorage/характеры других скриптов не берутся.
local NPC_MAX_SCAN = 300 -- предохранитель: NPC может быть сотни, сканируем не всё

--=========================== СОСТОЯНИЕ ============================

local character, humanoid, rootPart

-- Флаг «бинд аима зажат» (удержание). Объявлен ДО aimStep: aimStep читает
-- его замыканием, и объявление после было бы ссылкой на глобал nil.
local aimHeld = false

local camera = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera
end)

local function bindCharacter(char)
	character = char
	humanoid = char and char:WaitForChild("Humanoid", 10)
	rootPart = char and char:WaitForChild("HumanoidRootPart", 10)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

--=========================== ЦЕЛИ ============================

--[[
	БЛИЖАЙШАЯ К ПРИЦЕЛУ, А НЕ К СЕБЕ. Просьба «продвинутый аимбот» =
	аим не перетягивает на цель за спиной: угол между направлением камеры
	и направлением на цель считается на плоскости экрана (проекции на оси
	камеры), меньше угол - лучше цель. Дистанция вторична.

	Цель - точка в теле: Head, если есть, иначе центр габаритов модели
	(у кастомных моделей NPC начало координат в ступнях - HRP в них не
	годится, тот же приём, что aimPointOf в AdminMenu).
]]

local TORSO_NAMES = { "Head", "UpperTorso", "Torso" }

local function aimPointOf(char, root)
	for _, name in ipairs(TORSO_NAMES) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part.Position
		end
	end

	local ok, center = pcall(function()
		return char:GetBoundingBox().Position
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

local function isAlive(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function isEnemy(char)
	if char == character then
		return false
	end
	if not SETTINGS.TeamCheck then
		return true
	end
	-- Штатные команды: у игрока и цели Team должны различаться. В плейсах
	-- без Team оба nil/Neutral - считается врагом (аим работает).
	local other = Players:GetPlayerFromCharacter(char)
	if other and player.Team ~= nil and player.Team ~= other.Team then
		return true
	end
	if other and player.Team ~= nil and player.Team == other.Team then
		return false
	end
	return true
end

local function isVisible(targetPosition)
	if not SETTINGS.WallCheck then
		return true
	end
	if not (rootPart and camera) then
		return false
	end

	-- Луч от камеры (не от тела: стены между камерой и целью - это то,
	-- что видит игрок) к цели. IgnoreDescendants: свой персонаж луч не
	-- должен находить - он между камерой и всем миром.
	local direction = targetPosition - camera.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(camera.CFrame.Position, direction, params)
	-- Луч долетел до цели (или мимо её корпуса до фона) - видима. Упёрся в
	-- что-то раньше цели - стена.
	if not result then
		return true
	end
	local distanceToTarget = direction.Magnitude
	local distanceToHit = (result.Position - camera.CFrame.Position).Magnitude
	-- Запас на тонкие объекты и края хитбоксов: попал в 2 студах от цели -
	-- считаем видимым (это её собственный корпус, у NPC с кривым ригом
	-- точка прицела может быть чуть за геометрией).
	return distanceToHit >= distanceToTarget - 2
end

--[[
	УГОЛ НА ПЛОСКОСТИ ЭКРАНА удалён: выбор цели идёт по ЭКРАННОМУ
	расстоянию (px до центра), а не по углу. Проекция цели через
	WorldToViewportPoint корректна для точек ПЕРЕД камерой; за камерой
	цель отбрасывается раньше (onScreen-проверка).
]]

-- Все кандидаты: игроки + NPC. NPC - модели workspace с Humanoid+HRP без игрока.
local function forEachTarget(callback)
	-- Игроки
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local char = other.Character
			if char and char.Parent then
				callback(char)
			end
		end
	end

	-- NPC: обход children workspace, а в моделях-ПАПКАХ - спуск вглубь.
	-- Прямые дети workspace не покрывали плейсы, где NPC лежат в папках
	-- (баг-репорт: «авто айм на нпс не работает но на игроков работает
	-- а триггер бот и там и там работает» - райкаст триггера достаёт
	-- модель через FindFirstAncestorWhichIsA на любой глубине, обход -
	-- нет). Обход остаётся ограниченным: очередь с NPC_MAX_SCAN.
	-- Модель NPC = объект с Humanoid+HRP без игрока (GetPlayerFromCharacter).
	local queue = { Workspace:GetChildren() }
	local head = 1
	local scanned = 0
	while head <= #queue and scanned < NPC_MAX_SCAN do
		local obj = queue[head]
		head += 1
		scanned += 1
		if obj:IsA("Model") then
			if obj ~= character and Players:GetPlayerFromCharacter(obj) == nil then
				local root = obj:FindFirstChild("HumanoidRootPart")
				if root and isAlive(obj) then
					callback(obj)
					-- Внутрь модели не спускаемся: её дети - части и
					-- аксессуары самой цели, вложенных NPC там обычно нет.
				end
			end
		else
			-- Папка (Folder) или другая не-модель: её дети в очередь -
			-- там могут лежать NPC. Дешевле обхода тысяч объектов
			-- (GetDescendants) не будет, но лимит сканирования держит.
			for _, child in ipairs(obj:GetChildren()) do
				queue[#queue + 1] = child
			end
		end
	end
	-- Непросканированный хвост очереди (лимит) теряется - это цена
	-- NPC_MAX_SCAN, предохранителя от сотен NPC за кадр.
end

--=========================== ВЫБОР ЦЕЛИ ============================

local function findBestTarget()
	if not (camera and rootPart) then
		return nil
	end

	local camPos = camera.CFrame.Position
	local fovPx = SETTINGS.Fov
	local viewport = camera.ViewportSize
	local centerX, centerY = viewport.X / 2, viewport.Y / 2

	local bestChar, bestPoint, bestScore = nil, nil, math.huge

	forEachTarget(function(char)
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (root and root.Parent) then
			return
		end
		if not isAlive(char) or not isEnemy(char) then
			return
		end

		local point = aimPointOf(char, root)
		if not point then
			return
		end

		-- Дистанция (лимит). FOV сравнивается с ЭКРАННЫМ отклонением,
		-- проекция ниже.
		local distance = (point - camPos).Magnitude
		if SETTINGS.MaxDistance > 0 and distance > SETTINGS.MaxDistance then
			return
		end

		-- FOV: сравнивается с ЭКРАННЫМ отклонением (px), а не с углом:
		-- круг на экране соответствует конусу, но для цели по центру
		-- экрана точность важнее строгости. Экранное отклонение = угол /
		-- (половина FOV камеры) * половина ширины экрана. Проще: если цель
		-- проецируется в круг - берём. Проекция через WorldToViewportPoint
		-- для точек ПЕРЕД камерой корректна (зеркаление только за камерой).
		local ok, screenPoint, onScreen = pcall(function()
			local vpp = camera:WorldToViewportPoint(point)
			return vpp, vpp.Z > 0
		end)
		if not ok or not onScreen then
			return -- за камерой или проекция не удалась
		end

		if fovPx > 0 then
			local dx, dy = screenPoint.X - centerX, screenPoint.Y - centerY
			local screenDistance = math.sqrt(dx * dx + dy * dy)
			if screenDistance > fovPx then
				return -- вне круга захвата
			end
			-- Основной вес - экранное расстояние до центра (ближе к прицелу
			-- = лучше); угол добавлен как вторичный
			if screenDistance < bestScore then
				if not isVisible(point) then
					return
				end
				bestChar, bestPoint, bestScore = char, point, screenDistance
			end
		else
			-- fovPx = 0: вся плоскость экрана, вес - экранное расстояние
			local dx, dy = screenPoint.X - centerX, screenPoint.Y - centerY
			local sd = math.sqrt(dx * dx + dy * dy)
			if sd < bestScore then
				if not isVisible(point) then
					return
				end
				bestChar, bestPoint, bestScore = char, point, sd
			end
		end
	end)

	return bestChar, bestPoint
end

--=========================== ПОВОРОТ КАМЕРЫ ============================

--[[
	Знак поворота - из проверенных тестов AdminMenu (A1-A9):
	CFrame.Angles(0, theta, 0), положительный theta = ВЛЕВО.
	deltaYaw = atan2(crossY, dot), crossY = L.Z*D.X - L.X*D.Z.
	Плоские векторы: вертикаль тоже доводится (полный аим - это аимбот,
	а не «аим по X» из AdminMenu).
]]

local function aimStep(deltaTime)
	-- Аим работает при включённом тумблере ИЛИ зажатом бинде
	if not SETTINGS.Enabled and not aimHeld then
		return
	end
	if not (character and character.Parent and humanoid) or humanoid.Health <= 0 then
		return
	end
	if not (rootPart and rootPart.Parent and camera) then
		return
	end

	local bestChar, bestPoint = findBestTarget()
	if not (bestChar and bestPoint) then
		return
	end

	local camPos = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local dir = bestPoint - camPos

	local lookMag = look.Magnitude
	local dirMag = dir.Magnitude
	if lookMag < 1e-3 or dirMag < 1e-3 then
		return
	end

	local normalizedLook = look / lookMag
	local normalizedDir = dir / dirMag

	--[[
		Полный довод: и по горизонтали (yaw), и по вертикали (pitch).
		Строится поворот из текущего взгляда в направление на цель:
		axis = Look x Dir (ось поворота), angle = acos(dot). Поворот
		CFrame.fromAxisAngle - честный кратчайший поворот, знак оси даёт
		направление.
	]]
	local dot = math.clamp(normalizedLook:Dot(normalizedDir), -1, 1)
	if dot > 0.99999 then
		return -- уже наведено
	end

	local axis = normalizedLook:Cross(normalizedDir)
	local axisMag = axis.Magnitude
	if axisMag < 1e-6 then
		-- Взгляд ровно противоположен цели (dot ~ -1): кратчайшая ось
		-- не определена, доворачиваем вбок на произвольную ось
		if dot < -0.999 then
			axis = camera.CFrame.UpVector
			axisMag = 1
		else
			return
		end
	end

	local angle = math.acos(dot)
	axis = axis / axisMag

	-- Плавность: за кадр доводим 1/Smoothness часть угла. Smoothness = 1
	-- - мгновенно. DeltaTime-независимая часть (fraction за кадр, не за
	-- секунду): при разной FPS поворот слегка гуляет, для аимбота это
	-- допустимо (см. ЗАМЕТКИ).
	local fraction = 1 / SETTINGS.Smoothness
	local stepAngle = angle * fraction
	-- Кап на кадр: резкий рывок (телепорт цели, лаг) не дёргает камеру
	local maxStep = math.rad(720) * deltaTime
	if stepAngle > maxStep then
		stepAngle = maxStep
	end

	camera.CFrame = camera.CFrame * CFrame.fromAxisAngle(axis, stepAngle)
end

-- BindToRenderStep на Camera+1: дефолтный контроллер камеры пишет CFrame
-- на Camera (200), запись из обычного RenderStepped он затирал бы
-- (установленный приём из AdminMenu).
RunService:BindToRenderStep("AdminAimbotAim", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	aimStep(deltaTime)
end)

--=========================== БИНД АИМА ============================

--[[
	TOGGLE по умолчанию (просьба пользователя: «переведи все кнопки
	в toggle»): нажал бинд - аим включился, нажал ещё раз - выключился.
	SETTINGS.ToggleAim = false возвращает удержание (зажал - работает,
	отпустил - нет). Бинды бывают клавишами и кнопками мыши. aimHeld
	объявлён выше (в СОСТОЯНИИ) - aimStep читает его замыканием.
]]

local function isAimInput(input)
	local keyCode = input.KeyCode
	local inputType = input.UserInputType
	-- Бинд может быть клавишей (Enum.KeyCode) или кнопкой мыши
	-- (Enum.UserInputType)
	if typeof(BINDS.aim) == "EnumItem" then
		if keyCode == BINDS.aim or inputType == BINDS.aim then
			return true
		end
	end
	return false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if isAimInput(input) then
		if SETTINGS.ToggleAim then
			-- Переключатель: каждое нажатие меняет состояние
			aimHeld = not aimHeld
		else
			-- Удержание
			aimHeld = true
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- В toggle-режиме отпускание НЕ выключает: выключает следующее нажатие
	if not SETTINGS.ToggleAim and isAimInput(input) then
		aimHeld = false
	end
end)

--=========================== ESP ===========================
--[[
	Перенесено из AdminMenu (20_world.luau, do-блок ESP) по просьбе
	«добавь есп можешь из adminpanel спиздить». Отличия от оригинала:

	1. Цели - игроки И NPC: обход через forEachTarget, а не Players:GetPlayers
	   (универсальный аимбот, не только DOD).
	2. Цвет - не по командам иерархии DOD (TEAM_COLORS/GameAssets.Teams там),
	   а проще: враг красный, союзник зелёный (штатный Player.Team через
	   isEnemy), NPC жёлтый.
	3. Caretaker-логики нет (способность DOD, здесь не о чем).
	4. Каждый кадр создаётся временное множество виденных моделей -
	   исчезнувшие из обхода цели гасятся по нему (в AdminMenu цели
	   обходились только по Players, запись была постоянной).

	Ключи объектов создаются на МОДЕЛЬ (персонаж), а не на игрока: NPC
	игрока не имеют, а респавн игрока = новая модель. Смерть модели
	убирает запись из espEntries (вместе с GUI).
]]

-- Экспорт наружу для меню: форвард-локалы (приём AdminMenu), определены
-- внутри do-блока БЕЗ local.
local espVisualsOff, espAllOff

do
	local playerGui = player:WaitForChild("PlayerGui")

	-- Трейсеры и стрелки живут в ScreenGui. IgnoreGuiInset = true
	-- ОБЯЗАТЕЛЬНО (не косметика): WorldToViewportPoint не учитывает
	-- GUI-инсет, координаты совпадают только при IgnoreGuiInset.
	-- Билборды парентятся прямо в PlayerGui: BillboardGui сам
	-- LayerCollector, вкладывать его в ScreenGui нельзя.
	local tracerGui = Instance.new("ScreenGui")
	tracerGui.Name = "AimbotESP"
	tracerGui.ResetOnSpawn = false
	tracerGui.IgnoreGuiInset = true
	tracerGui.DisplayOrder = 90
	tracerGui.Parent = playerGui

	-- Стрелка 360 из ДВУХ Frame'ов: готового треугольника в Roblox нет,
	-- картинку-ассет тащить нельзя (самодостаточность скрипта).
	-- Центр полоски считается вручную: поворот GuiObject идёт вокруг
	-- собственной точки вращения, якорь в остриё разъезжался в крестик.
	-- Поворот всей стрелки задаётся у КОНТЕЙНЕРА (Rotation наследуется).
	local ARROW_LEG_ANGLE = 38 -- градусов от вертикали на каждую ногу

	local function createArrow(name)
		local size = SETTINGS.EspOffScreenSize

		local container = Instance.new("Frame")
		container.Name = name
		container.AnchorPoint = Vector2.new(0.5, 0.5)
		container.Size = UDim2.fromOffset(size, size)
		container.BackgroundTransparency = 1
		container.BorderSizePixel = 0
		container.Visible = false
		container.ZIndex = 2
		container.Parent = tracerGui

		local legLength = size * 0.62
		local angle = math.rad(ARROW_LEG_ANGLE)
		-- Остриё сдвинуто на полвысоты галочки: фигура вписана в центр
		local tipX = size * 0.5
		local tipY = size * 0.5 - legLength * math.cos(angle) * 0.5

		local bars = {}

		for index, sign in ipairs({ -1, 1 }) do
			local dirX = -sign * math.sin(angle)
			local dirY = math.cos(angle)

			local bar = Instance.new("Frame")
			bar.Name = "Bar" .. index
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromOffset(tipX + dirX * legLength * 0.5, tipY + dirY * legLength * 0.5)
			bar.Size = UDim2.fromOffset(SETTINGS.EspOffScreenThickness, legLength)
			bar.BorderSizePixel = 0
			bar.Rotation = sign * ARROW_LEG_ANGLE
			bar.Parent = container
			bars[index] = bar
		end

		return container, bars
	end

	-- Подпись к стрелке - отдельный объект, НЕ ребёнок стрелки: Rotation
	-- наследуется по иерархии, текст крутился бы вместе с остриём.
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
		label.TextColor3 = ESP_NPC_COLOR
		label.Text = ""
		label.Visible = false
		label.ZIndex = 2
		label.Parent = tracerGui
		return label
	end

	-- [модель] = { billboard, label, tracer, arrow, arrowBars, arrowLabel, highlight }
	local espEntries = {}

	local function hideEntry(entry)
		if entry.highlight then
			entry.highlight.Enabled = false
		end
		entry.billboard.Enabled = false
		entry.tracer.Visible = false
		entry.arrow.Visible = false
		entry.arrowLabel.Visible = false
	end

	local function removeEntry(char)
		local entry = espEntries[char]
		if not entry then
			return
		end
		if entry.highlight then
			entry.highlight:Destroy()
		end
		entry.billboard:Destroy()
		entry.tracer:Destroy()
		entry.arrow:Destroy() -- полоски уходят вместе с контейнером
		entry.arrowLabel:Destroy()
		espEntries[char] = nil
	end

	local function createEntry(char)
		local displayName = char.Name

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ESP_" .. displayName
		billboard.ResetOnSpawn = false
		billboard.Size = UDim2.fromOffset(220, 46)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Enabled = false
		billboard.Adornee = char:FindFirstChild("Head")
			or char:FindFirstChild("HumanoidRootPart")
		billboard.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = ESP_NPC_COLOR -- перекрасится в первом кадре
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextWrapped = false
		label.Text = ""
		label.Parent = billboard

		local tracer = Instance.new("Frame")
		tracer.Name = "Tracer_" .. displayName
		tracer.AnchorPoint = Vector2.new(0.5, 0.5)
		tracer.BorderSizePixel = 0
		tracer.BackgroundColor3 = ESP_NPC_COLOR
		tracer.Size = UDim2.fromOffset(SETTINGS.EspTracerThickness, 0)
		tracer.Visible = false
		tracer.ZIndex = 0
		tracer.Parent = tracerGui

		local arrow, arrowBars = createArrow("Arrow_" .. displayName)
		local arrowLabel = createArrowLabel("ArrowText_" .. displayName)

		local highlight = Instance.new("Highlight")
		highlight.Name = "AimbotESPHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = SETTINGS.EspFillTransparency
		highlight.OutlineTransparency = 0
		highlight.Adornee = char
		highlight.Enabled = false
		highlight.Parent = char

		local entry = {
			billboard = billboard,
			label = label,
			tracer = tracer,
			arrow = arrow,
			arrowBars = arrowBars,
			arrowLabel = arrowLabel,
			highlight = highlight,
		}
		espEntries[char] = entry
		return entry
	end

	-- Модель исчезла/умерла - убрать метку. AncestryChanged ловит и удаление
	-- из workspace, и смерть (у погибших персонаж часто просто Destroy).
	-- Самодельная слабая ссылка: держим модель в ключе таблицы - сборщик
	-- не тронет, пока запись жива, поэтому подписка на модель надёжна.
	local function watchRemoval(char)
		local conn
		conn = char.AncestryChanged:Connect(function()
			if not char:IsDescendantOf(game) then
				if conn then
					conn:Disconnect()
				end
				removeEntry(char)
			end
		end)
	end

	-- Цвет: NPC жёлтый, враг красный, союзник зелёный
	local function colorFor(char)
		local other = Players:GetPlayerFromCharacter(char)
		if not other then
			return ESP_NPC_COLOR
		end
		if isEnemy(char) then
			return ESP_ENEMY_COLOR
		end
		return ESP_ALLY_COLOR
	end

	-- Метка: имя (игрок - DisplayName, NPC - имя модели) + hp + дистанция
	local function buildEspText(char, humanoidOther, distance)
		local lines = {}

		if SETTINGS.EspNames then
			local other = Players:GetPlayerFromCharacter(char)
			local name
			if other then
				name = other.DisplayName ~= other.Name
						and (other.DisplayName .. " (@" .. other.Name .. ")")
					or other.Name
			else
				name = char.Name
			end
			table.insert(lines, name)
		end

		local details = {}
		if SETTINGS.EspHealth and humanoidOther then
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
		if SETTINGS.EspDistance then
			table.insert(details, string.format("%dm", math.floor(distance + 0.5)))
		end
		if #details > 0 then
			table.insert(lines, table.concat(details, "  "))
		end

		return table.concat(lines, "\n")
	end

	-- Трейсер: из низа экрана в проекцию ОПОРНОЙ ТОЧКИ (середина корпуса,
	-- не HRP - у кастомных моделей HRP в ступнях, линия приходила в ноги).
	local function updateTracer(entry, cameraNow, screenPoint, onScreen, color)
		if not SETTINGS.EspTracers or not (screenPoint and onScreen) then
			entry.tracer.Visible = false
			return
		end

		local viewport = cameraNow.ViewportSize
		local originX, originY = viewport.X * 0.5, viewport.Y
		local dx, dy = screenPoint.X - originX, screenPoint.Y - originY
		local length = math.sqrt(dx * dx + dy * dy)

		entry.tracer.Size = UDim2.fromOffset(SETTINGS.EspTracerThickness, length)
		entry.tracer.Position = UDim2.fromOffset(originX + dx * 0.5, originY + dy * 0.5)
		-- нулевой поворот направлен вниз по экрану, отсюда atan2(-dx, dy)
		entry.tracer.Rotation = math.deg(math.atan2(-dx, dy))
		entry.tracer.BackgroundColor3 = color
		entry.tracer.Visible = true
	end

	--[[
		Стрелка 360 для цели вне кадра. НАПРАВЛЕНИЕ СЧИТАЕТСЯ НЕ ПО
		WorldToViewportPoint: для точки ЗА камерой проекция зеркалится
		(цель сзади-справа дала бы стрелку влево - поворачиваться туда
		дольше). Берётся направление в системе камеры:
		    x = dir · RightVector, y = -dir · UpVector
		Без деления на глубину - без переворота за спиной.
		Строго за спиной x=y=0 - стрелка вниз («цель позади»).
		Точка на рамке: из центра по (x, y) до ПЕРВОЙ из двух границ
		(минимальный коэффициент), иначе стрелка вылезает за угол.
	]]
	local function updateOffScreen(entry, cameraNow, worldPosition, color, onScreen, char, distance)
		if not SETTINGS.EspOffScreen or onScreen then
			entry.arrow.Visible = false
			entry.arrowLabel.Visible = false
			return
		end

		local cameraFrame = cameraNow.CFrame
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

		local viewport = cameraNow.ViewportSize
		local centerX, centerY = viewport.X * 0.5, viewport.Y * 0.5
		local limitX = math.max(centerX - SETTINGS.EspOffScreenMargin, 1)
		local limitY = math.max(centerY - SETTINGS.EspOffScreenMargin, 1)

		local scaleX = math.abs(ux) > 1e-4 and (limitX / math.abs(ux)) or math.huge
		local scaleY = math.abs(uy) > 1e-4 and (limitY / math.abs(uy)) or math.huge
		local scale = math.min(scaleX, scaleY)

		local posX = centerX + ux * scale
		local posY = centerY + uy * scale

		entry.arrow.Position = UDim2.fromOffset(posX, posY)
		-- при Rotation = 0 остриё смотрит вверх, отсюда atan2(ux, -uy)
		entry.arrow.Rotation = math.deg(math.atan2(ux, -uy))
		for _, bar in ipairs(entry.arrowBars) do
			bar.BackgroundColor3 = color
		end
		entry.arrow.Visible = true

		-- Подпись НЕ ребёнок стрелки (Rotation наследуется); сдвигается
		-- к центру экрана, чтобы не уезжать за край вместе со стрелкой
		local labelText = ""
		if SETTINGS.EspNames then
			local name = char.Name
			if #name > 12 then
				name = string.sub(name, 1, 12) .. "…"
			end
			labelText = name
		end
		if SETTINGS.EspDistance then
			local distanceText = string.format("%dm", math.floor(distance + 0.5))
			labelText = labelText == "" and distanceText or (labelText .. " " .. distanceText)
		end

		if labelText == "" then
			entry.arrowLabel.Visible = false
			return
		end

		local labelOffset = SETTINGS.EspOffScreenSize * 0.9
		entry.arrowLabel.Position = UDim2.fromOffset(posX - ux * labelOffset, posY - uy * labelOffset)
		entry.arrowLabel.Text = labelText
		entry.arrowLabel.TextColor3 = color
		entry.arrowLabel.Visible = true
	end

	-- Быстрое гашение для тумблеров настроек (иначе объект исчезал бы
	-- только на следующем кадре обхода - выглядит как залипшая кнопка)
	local function hideEspVisuals(key)
		for _, entry in pairs(espEntries) do
			if key == "EspTracers" and not SETTINGS.EspTracers then
				entry.tracer.Visible = false
			end
			if key == "EspOffScreen" and not SETTINGS.EspOffScreen then
				entry.arrow.Visible = false
				entry.arrowLabel.Visible = false
			end
			if key == "EspHighlight" and not SETTINGS.EspHighlight and entry.highlight then
				entry.highlight.Enabled = false
			end
		end
	end

	-- Обход целей каждый кадр. seenModels - временное множество виденных
	-- моделей: цель, выпавшая из forEachTarget (умерла/исчезла), гасится.
	local function updateEsp()
		if not SETTINGS.Esp then
			return
		end
		if not camera then
			return
		end
		local cameraPosition = camera.CFrame.Position
		local seenModels = {}

		forEachTarget(function(char)
			if char == character then
				return
			end
			local entry = espEntries[char]
			if not entry then
				entry = createEntry(char)
				watchRemoval(char)
			end
			seenModels[char] = true

			local otherRoot = char:FindFirstChild("HumanoidRootPart")
			local otherHumanoid = char:FindFirstChildOfClass("Humanoid")

			local aimPoint = aimPointOf(char, otherRoot)
			if not aimPoint then
				hideEntry(entry)
				return
			end

			local distance = (aimPoint - cameraPosition).Magnitude
			if SETTINGS.EspMaxDistance > 0 and distance > SETTINGS.EspMaxDistance then
				hideEntry(entry)
				return
			end

			local color = colorFor(char)

			if entry.highlight then
				entry.highlight.Enabled = SETTINGS.EspHighlight
				entry.highlight.FillColor = color
				entry.highlight.OutlineColor = color
				entry.highlight.FillTransparency = SETTINGS.EspFillTransparency
			end

			local text = buildEspText(char, otherHumanoid, distance)
			if text ~= "" then
				entry.label.Text = text
				entry.label.TextColor3 = color
				entry.billboard.Enabled = true
			else
				entry.billboard.Enabled = false
			end

			-- Проекция считается ОДИН раз: нужна и трейсеру, и стрелке.
			local screenPoint, onScreen = nil, false
			if SETTINGS.EspTracers or SETTINGS.EspOffScreen then
				local ok, point, vis = pcall(function()
					local vpp = camera:WorldToViewportPoint(aimPoint)
					return vpp, vpp.Z > 0
				end)
				if ok then
					screenPoint, onScreen = point, vis
				end
			end

			updateTracer(entry, camera, screenPoint, onScreen, color)
			updateOffScreen(entry, camera, aimPoint, color, onScreen, char, distance)
		end)

		-- Не попавшие в обход - гасим (сам forEachTarget мёртвых не отдаёт,
		-- но модель могла выпасть из NPC_MAX_SCAN и из пределов списка)
		for char, entry in pairs(espEntries) do
			if not seenModels[char] then
				hideEntry(entry)
			end
		end
	end

	RunService.RenderStepped:Connect(function()
		if not SETTINGS.Esp then
			-- Полное выключение гасит всё разом, а не ждёт кадра обхода
			for _, entry in pairs(espEntries) do
				hideEntry(entry)
			end
			return
		end
		updateEsp()
	end)

	-- Полное выключение ESP тумблером Esp: убирает и GUI умерших целей
	-- (запись остаётся, вернётся с моделью). Отдельно от RenderStepped,
	-- чтобы гасить НАЖАТИЕМ, а не в кадре.
	-- Обе функции БЕЗ local: имена объявлены форвард-локалами перед do.
	function espVisualsOff(key)
		hideEspVisuals(key)
	end

	function espAllOff()
		for _, entry in pairs(espEntries) do
			hideEntry(entry)
		end
	end
end

--=========================== МЕНЮ ============================

local COLORS = {
	Text = Color3.fromRGB(240, 240, 240),
	Background = Color3.fromRGB(25, 25, 25),
	ElementBackground = Color3.fromRGB(35, 35, 35),
	ElementBackgroundHover = Color3.fromRGB(45, 45, 45),
	On = Color3.fromRGB(90, 170, 255),
	Off = Color3.fromRGB(70, 70, 70),
	Muted = Color3.fromRGB(160, 160, 165),
	Bind = Color3.fromRGB(50, 90, 140),
	Capture = Color3.fromRGB(70, 110, 170),
	Reject = Color3.fromRGB(160, 60, 60),
}

local function new(className, props)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	return inst
end

local menuGui = new("ScreenGui", {
	Name = "AimbotMenu",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 100,
	Parent = player:WaitForChild("PlayerGui"),
})

local main = new("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(340, 400), -- больше: 9 ESP-строк не лезли в 240
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COLORS.Background,
	BorderSizePixel = 0,
	Visible = false,
	Parent = menuGui,
})
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = main })

local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = Color3.fromRGB(34, 34, 34),
	BorderSizePixel = 0,
	Parent = main,
})
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = header })

new("TextLabel", {
	Size = UDim2.new(1, -60, 1, 0),
	Position = UDim2.new(0, 12, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "АИМБОТ",
	TextSize = 14,
	TextColor3 = COLORS.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

local closeButton = new("TextButton", {
	Size = UDim2.fromOffset(24, 24),
	Position = UDim2.new(1, -28, 0, 4),
	BackgroundColor3 = COLORS.ElementBackground,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "×",
	TextSize = 14,
	TextColor3 = COLORS.Text,
	Parent = header,
})
new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = closeButton })
closeButton.MouseButton1Click:Connect(function()
	main.Visible = false
end)

local content = new("ScrollingFrame", {
	Name = "Content",
	Size = UDim2.new(1, -16, 1, -44),
	Position = UDim2.new(0, 8, 0, 38),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = main,
})
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

-- Перетаскивание за шапку
do
	local dragging = false
	local dragStart, startPos
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	RunService.RenderStepped:Connect(function()
		if dragging and UserInputService:GetMouseLocation() and dragStart then
			local mouse = UserInputService:GetMouseLocation()
			main.Position = UDim2.new(
				0,
				startPos.X.Offset + (mouse.X - dragStart.X),
				0,
				startPos.Y.Offset + (mouse.Y - dragStart.Y)
			)
		end
	end)
end

local toggleButtons = {}
local bindButtons = {}
local captureBindId = nil

local function refreshToggle(id)
	local button = toggleButtons[id]
	if not button then
		return
	end
	local enabled = SETTINGS[id]
	button.TextColor3 = COLORS.Text
	button.BackgroundColor3 = enabled and COLORS.On or COLORS.Off
	button.Text = string.format("%s  [%s]", id, enabled and "ON" or "OFF")
end

local function setSetting(id, value)
	SETTINGS[id] = value
	refreshToggle(id)
	-- Точечное гашение ESP-визуалов: выключенный тумблер убирает свои
	-- объекты сразу, а не на следующем кадре обхода (приём AdminMenu,
	-- hideEspVisuals). espVisualsOff - форвард-локал из do-блока ESP.
	if espVisualsOff and (id == "EspTracers" or id == "EspOffScreen" or id == "EspHighlight") then
		espVisualsOff(id)
	elseif id == "Esp" and not value then
		espAllOff()
	end
end

local function makeToggle(label, id)
	local button = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = COLORS.Off,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = label,
		TextSize = 12,
		TextColor3 = COLORS.Text,
		AutoButtonColor = false,
		Parent = content,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })
	button.MouseButton1Click:Connect(function()
		setSetting(id, not SETTINGS[id])
	end)
	toggleButtons[id] = button
	refreshToggle(id)
	return button
end

local function makeStepper(label, id, step, minValue, maxValue, suffix)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = #content:GetChildren(),
		Parent = content,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -64, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = label,
		TextSize = 12,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local label2 = new("TextButton", {
		Size = UDim2.fromOffset(30, 22),
		Position = UDim2.new(1, -64, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.ElementBackground,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = tostring(SETTINGS[id]) .. (suffix or ""),
		TextSize = 11,
		TextColor3 = COLORS.Text,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = label2 })

	local function refresh()
		label2.Text = tostring(SETTINGS[id]) .. (suffix or "")
	end

	local minus = new("TextButton", {
		Size = UDim2.fromOffset(30, 22),
		Position = UDim2.new(1, -30, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.ElementBackground,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = "-",
		TextSize = 13,
		TextColor3 = COLORS.Text,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = minus })
	minus.MouseButton1Click:Connect(function()
		SETTINGS[id] = math.clamp(SETTINGS[id] - step, minValue, maxValue)
		refresh()
	end)

	local plus = new("TextButton", {
		Size = UDim2.fromOffset(30, 22),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.ElementBackground,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = "+",
		TextSize = 13,
		TextColor3 = COLORS.Text,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = plus })
	plus.MouseButton1Click:Connect(function()
		SETTINGS[id] = math.clamp(SETTINGS[id] + step, minValue, maxValue)
		refresh()
	end)

	return row
end

local function makeBindRow(label, bindId)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = content,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = label,
		TextSize = 12,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local button = new("TextButton", {
		Name = "Bind_" .. bindId,
		Size = UDim2.fromOffset(64, 22),
		Position = UDim2.new(1, -64, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.Bind,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.Gotham,
		Text = tostring(BINDS[bindId].Name),
		TextSize = 10,
		TextColor3 = COLORS.Text,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })

	local function refresh()
		if captureBindId == bindId then
			button.Text = "..."
			button.BackgroundColor3 = COLORS.Capture
		else
			button.Text = tostring(BINDS[bindId].Name)
			button.BackgroundColor3 = COLORS.Bind
		end
	end

	button.MouseButton1Click:Connect(function()
		if captureBindId == bindId then
			captureBindId = nil
		else
			captureBindId = bindId
		end
		refresh()
	end)

	-- Захват: InputBegan выше (аим) уже подключён - сюда тоже, порядок не важен
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if captureBindId ~= bindId then
			return
		end
		-- Пропускаем служебные
		if input.KeyCode == Enum.KeyCode.Escape then
			captureBindId = nil
			refresh()
			return
		end
		local candidate = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
		if candidate == Enum.UserInputType.Keyboard or candidate == Enum.UserInputType.MouseMovement then
			return -- не ввод
		end
		BINDS[bindId] = candidate
		captureBindId = nil
		refresh()
	end)

	bindButtons[bindId] = button
	refresh()
	return row
end

--=========================== СБОРКА МЕНЮ ============================

makeToggle("Аимбот", "Enabled")
makeToggle("Бинд аима: toggle", "ToggleAim")
makeToggle("Проверка стен", "WallCheck")
makeToggle("Проверка команды", "TeamCheck")
makeToggle("Триггер-бот", "TriggerBot")
makeStepper("Круг захвата", "Fov", SETTINGS.FovStep, SETTINGS.FovMin, SETTINGS.FovMax, "px")
makeStepper("Плавность", "Smoothness", 1, SETTINGS.SmoothMin, SETTINGS.SmoothMax, "")
makeStepper("Дистанция", "MaxDistance", 250, 0, 5000, "m")
makeStepper("Задержка выстрела", "TriggerDelay", 0.05, 0, 1, "с")
makeStepper("Пауза между выстрелами", "TriggerCooldown", 0.05, 0.05, 2, "с")
-- ESP (перенесено из AdminMenu)
makeToggle("ESP", "Esp")
makeToggle("ESP: подсветка", "EspHighlight")
makeToggle("ESP: имена", "EspNames")
makeToggle("ESP: здоровье", "EspHealth")
makeToggle("ESP: дистанция", "EspDistance")
makeToggle("ESP: трейсеры", "EspTracers")
makeToggle("ESP: стрелки 360", "EspOffScreen")
makeStepper("ESP: дистанция показа", "EspMaxDistance", 250, 0, 5000, "m")
makeBindRow("Аим (toggle)", "aim")
makeBindRow("Триггер-бот (toggle)", "trigger")
makeBindRow("Меню", "menu")

--[[
	Триггер-бот: тумблер в меню (TriggerBot) и бинд T (переключатель) -
	два независимых состояния, работает ЛИБО то, ЛИБО другое включено.
	Тумблер «Бинд аима: toggle» выше - РЕЖИМ бинда аима: true = переключатель,
	false = удержание. Сам бинд переносится строкой «Аим (toggle)».
]]

-- Клавиша меню: RightCtrl по умолчанию, переназначается
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == BINDS.menu then
		main.Visible = not main.Visible
	end
end)

--=========================== КРУГ FOV ============================

local fovGui = new("ScreenGui", {
	Name = "AimbotFov",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 90,
	Parent = player:WaitForChild("PlayerGui"),
})

local fovFrame = new("Frame", {
	Name = "Circle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(SETTINGS.Fov * 2, SETTINGS.Fov * 2),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = fovGui,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fovFrame })
new("UIStroke", {
	Color = FOV_COLOR,
	Thickness = 1.5,
	Transparency = FOV_TRANSPARENCY,
	Parent = fovFrame,
})

-- Круг виден при включённом аимботе или зажатом бинде; радиус обновляется
RunService.RenderStepped:Connect(function()
	local show = SETTINGS.Enabled or aimHeld
	fovFrame.Visible = show and SETTINGS.Fov > 0
	if show then
		local size = SETTINGS.Fov * 2
		fovFrame.Size = UDim2.fromOffset(size, size)
	end
end)

--=========================== ТРИГГЕР-БОТ ===========================
--[[
	АВТОВЫСТРЕЛ, когда прицел на цели внутри круга (просьба пользователя).
	Клик отправляется VirtualInputManager - тем же способом, что нажатия
	AdminMenu: метка до отправки, отпускание через task.delay.
	Работает ТОЛЬКО при включённом триггер-боте (тумблер или бинд T);
	аимбот может быть выключен - триггер сам по себе полезен.

	Проверка «под прицелом»: РАЙКАСТ из центра экрана (не круг: круг для
	ЗАХВАТА аимбота, выстрел по краю круга промахивается). Луч упёрся в
	модель с живым Humanoid, которая враг (TeamCheck) - цель под прицелом.
	WallCheck получается сам собой: луч и есть проверка стен.

	Задержка TriggerDelay (0.1 с по умолчанию) перед выстрелом: мгновенный
	выстрел на пролетающей цели тратится впустую. Кулдаун TriggerCooldown
	между выстрелами (0.15 с): не спамить по одной цели.
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

local triggerInputAvailable = false
if VirtualInputManager then
	local okMember, member = pcall(function()
		return VirtualInputManager.SendMouseButtonEvent
	end)
	triggerInputAvailable = okMember and type(member) == "function"
end

local triggerInputBlocked = false
if not triggerInputAvailable then
	warn(
		"[Aimbot] триггер-бот недоступен: VirtualInputManager:SendMouseButtonEvent не читается. "
			.. "Нужен executor. Остальные функции работают."
	)
end

-- Тумблер триггер-бота (бинд T, переключатель)
local triggerEnabled = false

local lastTriggerTime = 0
local pendingShot = nil -- { time = os.clock(), key = ... } - отложенный выстрел

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == BINDS.trigger then
		triggerEnabled = not triggerEnabled
		if not triggerEnabled then
			pendingShot = nil -- отложенный выстрел отменяется при выключении
		end
	end
end)

-- Райкаст «под прицелом» - точка в центре экрана (или чуть вокруг): видим ли
-- кто-то живой под прицелом. Отдельно от findBestTarget: там поиск цели по
-- кругу, тут - проверка одной точки.
local function isTargetUnderCrosshair()
	if not (camera and character and character.Parent) then
		return false
	end

	-- Луч из центра экрана: цель под прицелом должна быть ВИДИМА (WallCheck)
	local viewport = camera.ViewportSize
	local unitRay = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local direction = unitRay.Direction * (SETTINGS.MaxDistance > 0 and SETTINGS.MaxDistance or 1000)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(unitRay.Origin, direction, params)
	if not result then
		return false
	end

	-- Упёрся в модель с Humanoid и живым Health - цель под прицелом
	local hit = result.Instance
	local model = hit and hit:FindFirstAncestorWhichIsA("Model")
	if not (model and model:FindFirstChildOfClass("Humanoid")) then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum.Health <= 0 then
		return false
	end
	if not isEnemy(model) then
		return false
	end
	return true
end

RunService.RenderStepped:Connect(function(deltaTime)
	-- Работает ЛИБО тумблер в меню (TriggerBot), ЛИБО бинд-тумблер (triggerEnabled)
	local activeTrigger = SETTINGS.TriggerBot or triggerEnabled
	if not (activeTrigger and triggerInputAvailable and not triggerInputBlocked) then
		return
	end

	-- Отложенный выстрел: время пришло - кликаем
	if pendingShot and os.clock() >= pendingShot.time then
		local shot = pendingShot
		pendingShot = nil
		-- Цель всё ещё под прицелом? Нет - выстрел отменён
		if not isTargetUnderCrosshair() then
			return
		end
		local ok = pcall(function()
			VirtualInputManager:SendMouseButtonEvent(shot.x, shot.y, 0, true, game, 0)
			VirtualInputManager:SendMouseButtonEvent(shot.x, shot.y, 0, false, game, 0)
		end)
		if not ok then
			triggerInputBlocked = true
			warn("[Aimbot] триггер-бот: VirtualInputManager отказал - тумблер погашен. Нужен executor.")
		end
		lastTriggerTime = os.clock()
		return
	end

	-- Кулдаун между выстрелами
	if os.clock() - lastTriggerTime < SETTINGS.TriggerCooldown then
		return
	end

	-- Прицел на цели? Запоминаем время - выстрел через TriggerDelay
	if isTargetUnderCrosshair() then
		if not pendingShot then
			pendingShot = {
				time = os.clock() + SETTINGS.TriggerDelay,
				x = camera.ViewportSize.X / 2,
				y = camera.ViewportSize.Y / 2,
			}
		end
	else
		pendingShot = nil -- прицел ушёл с цели - отложенный выстрел отменяется
	end
end)

--=========================== ЗАМЕТКИ ===========================

--[[
	ЗАМЕТКИ ПО ОГРАНИЧЕНИЯМ:

	1. Аим крутит КАМЕРУ, а не выстрелы. Сервер видит обычный ввод мыши -
	   это мягче хуков на ремоуты. Но анти-чит может засчитать странную
	   скорость поворота камеры (кап на кадр 720 град/с стоит, однако
	   строгий анти-чит смотрит и на неё). Плавностью это не лечится.
	2. Плавность НЕ DeltaTime-честная: fraction за кадр (1/Smoothness),
	   при разном FPS скорость доворота слегка гуляет. Для аимбота это
	   допустимо; честная формула - angle * (1 - exp(-dt * k)).
	3. Упреждение не сделано: нет модели скорости цели (Velocity репликует
	   только физика, у NPC часто нулевой). Если понадобится - считать
	   через разность позиций между кадрами.
	4. WallCheck лучит от КАМЕРЫ, а не от тела: то, что видит игрок.
	   Упёрся в 2 студах от цели - считается видимым (запас на края
	   хитбоксов и тонкие объекты).
	5. NPC берутся обходом children workspace с СПУСКОМ в папки (очередь):
	   модели, лежащие глубоко в папках, находятся. NPC_MAX_SCAN = 300 -
	   предохранитель: непросканированный хвост очереди теряется. Внутрь
	   модели-цели обход не спускается (вложенных NPC там обычно нет).
	6. TeamCheck работает только в играх со ШТАТНЫМИ Team (Player.Team).
	   В плейсах без Team все считаются врагами - аим берёт всех.
	7. Круг FOV - экранный (px), не угловой: при изменении FOV камеры
	   (зум) конус меняется, круг - нет. Для аимбота по центру экрана
	   этого достаточно.
	8. Бинд aim может быть клавишей ИЛИ кнопкой мыши (Enum.UserInputType).
	   Захват в меню берёт KeyCode, если он не Unknown, иначе
	   UserInputType - мышью забиндить можно.
	9. ТРИГГЕР-БОТ требует executor (VirtualInputManager). Проверка «под
	   прицелом» - райкаст из центра экрана, WallCheck сам собой. Клик
	   отправляется SendMouseButtonEvent в центре экрана (не в точку цели:
	   сервер видит клик по центру, как обычный ввод). Задержка 0.1 с и
	   кулдаун 0.15 с - против выстрелов по пролетающим целям. Отложенный
	   выстрел отменяется, если прицел ушёл с цели или триггер выключили.
	10. TOGGLE по умолчанию (просьба пользователя): нажал бинд - включилось,
	   нажал ещё раз - выключилось. Режим правится тумблером «Бинд аима:
	   toggle» (false = удержание). В toggle-режиме отпускание НЕ выключает.
	11. ESP (из AdminMenu): записи живут на МОДЕЛЬ персонажа, не на игрока -
	   NPC игрока не имеют. Смерть/удаление модели ловится AncestryChanged,
	   GUI уничтожается. Тумблеры EspHighlight/EspTracers/EspOffScreen гасят
	   свои объекты сразу (hideEspVisuals), тумблер Esp - всё разом.
	   Трейсер и стрелка 360 считают проекцию ОДИН раз на цель за кадр.
	   IgnoreGuiInset = true у ScreenGui обязателен: WorldToViewportPoint
	   не учитывает GUI-инсет, без него трейсеры съезжают на высоту инсета.
	   Цвет: враг красный, союзник зелёный (Player.Team), NPC жёлтый.
	   Подсветка Highlight ограничена 31 одновременным объектом (лимит
	   движка Roblox) - при большом числе целей лишние не отрисуются,
	   это ограничение движка, не скрипта.
	12. Компилировалось luau-compile --null (0.736), luau-analyze чистый.
	   В БОЮ НЕ ПРОВЕРЕНО.
]]
