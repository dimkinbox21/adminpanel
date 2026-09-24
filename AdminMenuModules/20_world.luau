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
	aim = false, -- аим на киллера по горизонтали (40_auto)
	autobrun = false, -- авто-бег (40_auto)
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
		-- Гейт игры: невидимость - DOD (анимация плейса), вне DOD пусто
		if not isDodGame then
			return
		end
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
	Плюс aimPointOf - точка прицела в теле, её читает аим (40_auto).
	Тот же форвард-локальный приём, что у teamNameOf выше: определена
	внутри блока БЕЗ local.
]]
local updateEsp, applyEsp, hideEspVisuals
local aimPointOf

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

	-- Без local: имя объявлено форвард-локалом выше, его читает аим (40_auto).
	function aimPointOf(char, root)
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

	НЕ в do-блоке: updateList/applyList (30_combat) читают почти все
	локалы секции (listRows, write*, teamRank/teamColor, GUI-объекты,
	флаги отчёта стамины), и вынесенного форвард-списка вышло бы больше,
	чем экономия. Экономия локалов сделана в do-блоке ИНТЕРФЕЙСА ниже.

	ГЕЙТ ИГРЫ: список - DOD (команды плейса), вне DOD панель не строится.
	Обёрнуто if'ом, а не удалено: код нужен в DOD.
	Имена, нужные снаружи (30_combat: updateList/applyList; блок стамины;
	40_auto), объявлены форвард-локалами ДО if - локалы if-блока наружу не
	выходят (п.28). teamNameOf - уже форвард-локал ESP выше.
]]
local readNumberAttribute, updateSelfRole, selfIsKiller, maxStaminaOf
local listGui, listFrame, listTitleName, listTitleLegend
local listRows, acquireRow
local writeTeamHeader, writePlayerRow, writeNoteRow
local teamRank, teamColor, staminaTextOf
selfIsKiller = false

if isDodGame then
listGui = new("ScreenGui", {
	Name = "AdminPlayerList",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 95,
	Parent = playerGui,
})

listFrame = new("Frame", {
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
listTitleName = new("TextLabel", {
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
listTitleLegend = new("TextLabel", {
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
listRows = {}

function acquireRow(index)
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

function writeTeamHeader(index, teamName, count, color)
	local row = acquireRow(index)
	row.frame.Size = UDim2.new(1, 0, 0, LIST.HeaderHeight)
	row.name.Font = Enum.Font.GothamBold
	row.name.TextSize = 11
	row.name.TextColor3 = color
	row.name.Text = string.upper(teamName)
	row.value.TextColor3 = color
	row.value.Text = tostring(count)
end

function writePlayerRow(index, text, value, color)
	local row = acquireRow(index)
	row.frame.Size = UDim2.new(1, 0, 0, LIST.RowHeight)
	row.name.Font = Enum.Font.Gotham
	row.name.TextSize = 12
	row.name.TextColor3 = color
	row.name.Text = text
	row.value.TextColor3 = COLORS.Text
	row.value.Text = value
end

function writeNoteRow(index, text)
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

TEAM_RANK = {}
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

function updateSelfRole()
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

function teamRank(name)
	if name == NO_TEAM then
		return #TEAM_ORDER + 2 -- всегда последняя
	end
	return TEAM_RANK[name] or (#TEAM_ORDER + 1)
end

-- Локальная: снаружи do-блока ESP она не нужна - метки красятся своим
-- colorForTeam по той же таблице TEAM_COLORS.
function teamColor(name)
	return TEAM_COLORS[name] or COLORS.Text
end

-- Первое числовое значение из перечисленных атрибутов. GetAttribute на
-- несуществующем имени возвращает nil, но под pcall на случай, если
-- персонаж уже удаляется.
function readNumberAttribute(char, keys)
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

staminaKeyReported = false
staminaMissReported = false

--[[
	Максимум стамины персонажа.

	Атрибут MaxStamina чужих игроков клиенту НЕ репликуется, поэтому для
	них он почти всегда nil - максимум берётся из таблицы по атрибуту
	"Killer" (какой убийца), как в esp.txt.

	Значение из атрибута тоже отбрасывается, если оно бесконечное или
	абсурдно большое: это признак включённой Infinite Stamina, и дробь
	"73/inf" ничего не сообщает.
]]
function maxStaminaOf(char)
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
function staminaTextOf(char)
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
end -- isDodGame (список игроков - DOD)

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
	-- Гейт игры: стамина - DOD (атрибуты плейса), вне DOD пусто
	if not isDodGame then
		return
	end
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

