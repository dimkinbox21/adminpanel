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
	  - БИНДЫ В TOGGLE (просьба пользователя: «переведи все кнопки в toggle»):
	    нажал - включилось, нажал ещё раз - выключилось. Режим бинда аима
	    правится тумблером «Бинд аима: toggle» (false = старое удержание);
	  - меню простое: экран-панель с тумблерами и степперами (Rayfield
	    не тащится - скрипт самодостаточный, как AdminMenu).

	Клавиши по умолчанию: RightMouse - аим (toggle), T - триггер-бот (toggle),
	RightCtrl - меню.
	В меню: Аимбот, Бинд аима: toggle, WallCheck, TeamCheck, Триггер-бот,
	степперы FOV (0-500, шаг 10), Плавность (1-20), Дистанция (0-5000),
	Задержка выстрела (0-1 с), Пауза между выстрелами (0.05-2 с), бинды.

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
}

local BINDS = {
	menu = Enum.KeyCode.RightControl,
	aim = Enum.UserInputType.MouseButton2, -- переключатель (ToggleAim) или удержание
	trigger = Enum.KeyCode.T, -- тумблер триггер-бота
}

-- Цвет круга FOV и видимость панели
local FOV_COLOR = Color3.fromRGB(120, 200, 255)
local FOV_TRANSPARENCY = 0.35

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

	-- NPC: прямой обход детей workspace (не GetDescendants - модели могут
	-- лежать глубоко, но обходить тысячи объектов каждый кадр нельзя).
	-- Модель NPC = child workspace с FindFirstChildOfClass("Humanoid").
	local scanned = 0
	for _, obj in ipairs(Workspace:GetChildren()) do
		if scanned >= NPC_MAX_SCAN then
			break
		end
		scanned += 1
		if obj:IsA("Model") and obj ~= character then
			-- Цели-игроки уже обходились выше; их персонажи лежат в
			-- workspace корнем - пропускаем тех, у кого есть игрок
			if Players:GetPlayerFromCharacter(obj) == nil then
				local root = obj:FindFirstChild("HumanoidRootPart")
				if root and isAlive(obj) then
					callback(obj)
				end
			end
		end
	end
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
	Size = UDim2.fromOffset(300, 240),
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
	5. NPC берутся только из ПРЯМЫХ детей workspace: модели, лежащие
	   глубже (в папках), не находятся. NPC_MAX_SCAN = 300 - предохранитель.
	   Если в плейсе NPC лежат в папках - расширять обход на
	   Workspace:GetDescendants() с лимитом, но это дороже каждый кадр.
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
	11. Компилировалось luau-compile --null (0.736), luau-analyze чистый.
	   В БОЮ НЕ ПРОВЕРЕНО.
]]
