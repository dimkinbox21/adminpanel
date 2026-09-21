--=========================== АИМ НА КИЛЛЕРА ===========================
--[[
	Постоянный аим на убийцу по оси X (просьба пользователя): камера
	поворачивается за ближайшим ЖИВЫМ киллером по горизонтали, вертикаль
	остаётся под мышкой.

	ГЛАВНОЕ РЕШЕНИЕ: направление считается ПО ОСЯМ КАМЕРЫ, а не по
	WorldToViewportPoint. Проекция точки ЗА камерой зеркалится, и стрелка
	по ней показывала бы в противоположную сторону (та же причина, по
	которой 360-указатели считают по проекциям направления - см. ESP 360
	в заметках).

	Знак поворота (проверено): CFrame.Angles(0, theta, 0) с положительным
	theta крутит ВЛЕВО. atan2 по векторному произведению даёт именно его.

	BindToRenderStep на Camera.Value + 1 ОБЯЗАТЕЛЬНО, не RenderStepped:Connect:
	дефолтный контроллер камеры пишет CFrame на приоритете Camera (200), и
	запись из обычного RenderStepped он затирал бы - аим бы не работал.
]]

-- За весь do-блок наружу выходят только то, что нужно снаружи:
-- RUN (10_config/50_ui), autobrunStep (Stepped в 50_ui),
-- refreshRunStatus (50_ui). aimStep и runDecision используются ТОЛЬКО
-- внутри блока - не выносить. Объявление РЯДОМ с блоком авто-бега ниже.
-- aimStep объявляется внутри do-блока аима ниже (локальная функция блока).

do
	--[[
		Ближайший ЖИВОЙ киллер. СВОЙ цикл, а не nearestKiller из блока
		баннера: тот локальный внутри do-блока и наружу не выходит. Обход
		тот же: Players + teamNameOf, поэтому манекен "Killer Dummy" из
		Teams.Killer не игрок и не попадает. Мёртвые отфильтрованы:
		аим на труп хуже отсутствия аима.
	]]
	local function nearestAliveKiller(origin)
		local bestChar, bestRoot, bestDistance = nil, nil, nil
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local char = other.Character
				local root = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
				if root and teamNameOf(other, char) == KILLER_TEAM then
					local humanoidOther = char:FindFirstChildOfClass("Humanoid")
					-- Мёртвый киллер не угроза (в этом плейсе он бывает мёртв)
					if not (humanoidOther and humanoidOther.Health <= 0) then
						local d = (root.Position - origin).Magnitude
						if not bestDistance or d < bestDistance then
							bestChar, bestRoot, bestDistance = char, root, d
						end
					end
				end
			end
		end
		return bestChar, bestRoot, bestDistance
	end

	--[[
		ЧИСТЫЙ хелпер (тестируется без Roblox): на сколько надо довернуть
		камеру по горизонтали, чтобы взгляд (flatLook) совпал с направлением
		на киллера (flatDir). Оба вектора плоские (Y = 0).

		Знак: положительный результат = ВЛЕВО. Проверка: взгляд (0,0,-1)
		(в камере «вперёд»), киллер на +X (справа) -> crossY = (-1)*1 - 0 = -1,
		atan2(-1, 0) = -pi/2 -> доворот вправо. Верно.

		Локален внутри блока: наружу не выходит, тестируется вырезанием.
	]]
	local function computeYawDelta(flatLook, flatDir)
		local lookMag = flatLook.Magnitude
		local dirMag = flatDir.Magnitude
		--[[
			Unit нулевого вектора в Roblox НЕ бросает ошибку, а даёт NaN.
			Взгляд строго вверх/вниз или киллер ровно над головой - таких
			случаев здесь быть не должно, кадр просто пропускается.
		]]
		if lookMag < 1e-3 or dirMag < 1e-3 then
			return nil
		end

		local normalizedLook = flatLook / lookMag
		local normalizedDir = flatDir / dirMag

		local dot = normalizedLook:Dot(normalizedDir)
		local crossY = normalizedLook.Z * normalizedDir.X - normalizedLook.X * normalizedDir.Z

		local deltaYaw = math.atan2(crossY, dot)
		if math.abs(deltaYaw) < 1e-4 then
			return nil
		end
		return deltaYaw
	end

	function aimStep(deltaTime)
		if not state.aim then
			return
		end
		if not (rootPart and rootPart.Parent) then
			return
		end

		local killerChar, killerRoot = nearestAliveKiller(rootPart.Position)
		if not (killerChar and killerRoot) then
			return
		end

		-- Точка цели - в теле (тот же aimPointOf, что у трейсеров и стрелок):
		-- у кастомных моделей киллеров HRP лежит в ступнях.
		local aimTarget = aimPointOf(killerChar, killerRoot)
		if not aimTarget then
			return
		end

		local camera = getCamera()

		-- Плоские векторы: вертикаль не трогаем, она остаётся под мышкой
		local flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		local flatDir = Vector3.new(aimTarget.X - rootPart.Position.X, 0, aimTarget.Z - rootPart.Position.Z)

		local deltaYaw = computeYawDelta(flatLook, flatDir)
		if not deltaYaw then
			return
		end

		-- Кап шага: без него прицел дёргался бы рывком на весь угол
		local maxStep = math.rad(ESP.AimSpeed) * deltaTime
		if deltaYaw > maxStep then
			deltaYaw = maxStep
		elseif deltaYaw < -maxStep then
			deltaYaw = -maxStep
		end

		-- Аддитивный поворот поверх контроллера: pitch и roll сохраняются
		camera.CFrame = camera.CFrame * CFrame.Angles(0, deltaYaw, 0)
	end
end

-- Кам+1: запись должна прийти ПОСЛЕ записи дефолтного контроллера камеры
pcall(function()
	RunService:BindToRenderStep(
		"AdminMenuAim",
		Enum.RenderPriority.Camera.Value + 1,
		function(deltaTime)
			aimStep(deltaTime)
		end
	)
end)

--=========================== АВТО-БЕГ / МЕНЕДЖМЕНТ СТАМИНЫ ===========================
--[[
	Просьба пользователя: авто-бег (скрипт сам зажимает клавишу спринта)
	и авто-менеджмент стамины.

	МЕНЕДЖМЕНТ = пороги с гистерезисом: при стамине <= порога клавиша
	отпускается, при >= порога + запаса - зажимается снова. Стамина
	тратится по правилам игры.

	ПАНИКА (просьба пользователя: «если убийца очень рядом можно забить
	лимиты, но не спускать стамину до нуля, а оставлять 1-5 единиц»):
	когда киллер ближе RUN.PanicDistance, обычный порог игнорируется и
	порогом становится RUN.PanicFloor (1-5). То есть вблизи киллера бежим
	даже на низкой стамине, но не в ноль.

	Клавиша зажимается через VirtualInputManager - тем же способом, что и
	автоблок (pressBlockKey): метка syntheticKey ДО отправки, отпускание
	с копией клавиши. Свои флаги доступности НЕ заводим: состояние то же,
	что у автоблока.

	ЧТО НЕ ДЕЛАЕТ: скорость бега выше штатной. Если плейс режет спринт
	через DisableSprint или WalkSpeedModifier - стамина не поможет
	(ср. esp.txt «No Speed Debuffs», не сделано).

	ПОЧЕМУ КЛАВИША, А НЕ АТРИБУТ: спринт в игре включается зажатием
	(сказал пользователь), и клиентский код плейса читает ввод сам.
	Запись атрибута Sprinting ничего бы не дала - его перезаписывает
	клиент плейса каждый кадр.
]]

-- За блок наружу: autobrunStep (Stepped в 50_ui) и refreshRunStatus
-- (50_ui). RUN объявлён форвард-локалом В КОНФИГЕ (10_config, выше по
-- файлу): applyRunFromConfig в замыкании task.defer должен видеть
-- ТАБЛИЦУ по ссылке, а не глобал. aimStep и runDecision используются
-- ТОЛЬКО внутри блока - не выносить.
local autobrunStep
local refreshRunStatus

RUN = {
	Managed = false, -- менеджмент стамины (без своего бинда: makeBindButton
	-- читал бы несуществующий BINDS["staminamgr"])
	Low = 30, -- порог: ниже - отпускаем спринт
	Resume = 15, -- запас: зажимаем снова при >= Low + Resume
	PanicDistance = 25, -- киллер ближе - режим паники
	PanicFloor = 3, -- в панике порог = 1-5 (шаг степпера 1)
	HoldKey = nil, -- клавиша спринта, берётся из BINDS.autobrun при каждом шаге
}

do
	-- Флаг «клавиша сейчас зажата скриптом». Переходы только по фронту:
	-- press/release отправляются по одному разу, не каждый кадр.
	local heldByScript = false

	-- Копия зажатой клавиши для отпускания: к моменту отпуска blockKey мог
	-- смениться раундом (тот же приём, что в pressBlockKey).
	local heldKey = nil

	--[[
		ЧИСТЫЙ хелпер (тестируется без Roblox). Решение по стамине:
		  "release" - отпустить (стамина <= порога);
		  "press"   - зажать (стамина >= порога + запаса);
		  nil       - ничего не делать (гистерезисная полоса).
	]]
	function runDecision(stamina, threshold, resumeBand, held)
		if stamina <= threshold then
			return held and "release" or nil
		end
		if stamina >= threshold + resumeBand then
			return not held and "press" or nil
		end
		return nil
	end

	-- Ближайший живой киллер для паники. Своего цикла здесь НЕ надо:
	-- nearestKillerDistance (секция ЗОНЫ АВТОБЛОКА) уже top-level и возвращает
	-- число до ближайшего киллера. Мёртвые в нём не фильтруются, но для паники
	-- это безопасно: мёртвый киллер не бьёт, а лишний спринт на труп - не беда.
	local function killerIsNear()
		if not rootPart then
			return false
		end
		local distance = nearestKillerDistance()
		return distance ~= nil and distance <= RUN.PanicDistance
	end

	function autobrunStep()
	-- 1) Оба тумблера выключены -> отпустить, если зажато нами
	if not (state.autobrun or RUN.Managed) then
		if heldByScript then
			heldByScript = false
			local releaseKey = heldKey
			heldKey = nil
			if releaseKey then
				pcall(function()
					syntheticKey = releaseKey
					syntheticUntil = os.clock() + 0.1
					VirtualInputManager:SendKeyEvent(false, releaseKey, false, game)
				end)
			end
		end
		return
	end

	-- 2) Нет доступа к вводу -> трогать нечем (тумблер серый, см. 50_ui)
	if not autoblockInputAvailable or autoblockInputBlocked then
		return
	end

	-- 3) ПОЛЁТ -> НЕ трогать клавишу: LeftShift в полёте это ВНИЗ (FLY_KEYS),
	--    авто-бег жёг бы спуск. Зажатое отпускаем.
	if state.fly then
		if heldByScript then
			heldByScript = false
			local releaseKey = heldKey
			heldKey = nil
			if releaseKey then
				pcall(function()
					syntheticKey = releaseKey
					syntheticUntil = os.clock() + 0.1
					VirtualInputManager:SendKeyEvent(false, releaseKey, false, game)
				end)
			end
		end
		return
	end

	-- 4) Нет персонажа или мёртв -> отпустить, выйти. Стоит ПОСЛЕ гейта
	--    на ввод: на смерти/респавне клавишу надо отпустить, а не выйти
	--    с зажатой.
	if not (character and character.Parent and humanoid) or humanoid.Health <= 0 then
		if heldByScript then
			heldByScript = false
			local releaseKey = heldKey
			heldKey = nil
			if releaseKey then
				pcall(function()
					syntheticKey = releaseKey
					syntheticUntil = os.clock() + 0.1
					VirtualInputManager:SendKeyEvent(false, releaseKey, false, game)
				end)
			end
		end
		return
	end

	-- 5) Стамина своего персонажа. Нет числа -> не гадать.
	local stamina = readNumberAttribute(character, STAMINA_KEYS)
	if stamina == nil then
		return
	end

	-- 6) Порог: паника игнорирует Low, но не спускает ниже PanicFloor
	local threshold = RUN.Low
	if RUN.Managed and killerIsNear() then
		threshold = RUN.PanicFloor
	end

	-- 7) Решение. При включённом только «Авто-бег» (без менеджмента)
	--    пороги не работают: бегаем всегда, гейт только по состоянию.
	local decision
	if not RUN.Managed then
		-- Чистый авто-бег: держим клавишу постоянно, пока тумблер включён
		decision = not heldByScript and "press" or nil
	else
		decision = runDecision(stamina, threshold, RUN.Resume, heldByScript)
	end

	if decision == "press" then
		heldByScript = true
		heldKey = BINDS.autobrun
		syntheticKey = heldKey
		syntheticUntil = os.clock() + 0.1
		local ok = pcall(function()
			VirtualInputManager:SendKeyEvent(true, heldKey, false, game)
		end)
		if not ok then
			heldByScript = false
			heldKey = nil
			autoblockInputBlocked = true
			warn("[AdminMenu] авто-бег: VirtualInputManager отказал - тумблер погашен. " .. "Нужен executor, у обычного LocalScript прав нет.")
		end
	elseif decision == "release" then
		heldByScript = false
		local releaseKey = heldKey
		heldKey = nil
		if releaseKey then
			-- Метка до отправки: событие ввода прилетает синхронно
			pcall(function()
				syntheticKey = releaseKey
				syntheticUntil = os.clock() + 0.1
				VirtualInputManager:SendKeyEvent(false, releaseKey, false, game)
			end)
		end
	end
end

--[[
	Статус на вкладке «БЕГ» (50_ui). Ставится после сборки меню: фабрика
	строк возвращает label, ему присваивается эта функция. Вызывается из
	4-Гц блока RenderStepped при открытом меню.
]]
function refreshRunStatus(statusLabel)
	if not statusLabel then
		return
	end
	if not (state.autobrun or RUN.Managed) then
		statusLabel.Text = "Авто-бег выключен."
		statusLabel.TextColor3 = COLORS.Muted
		return
	end
	if not autoblockInputAvailable or autoblockInputBlocked then
		statusLabel.Text = "Авто-бег: нет доступа к вводу (VirtualInputManager отсутствует)."
		statusLabel.TextColor3 = COLORS.Danger
		return
	end
	if not (character and character.Parent and humanoid) or humanoid.Health <= 0 then
		statusLabel.Text = "Авто-бег: персонажа нет."
		statusLabel.TextColor3 = COLORS.Muted
		return
	end

	local stamina = readNumberAttribute(character, STAMINA_KEYS)
	local staminaText = stamina ~= nil and math.floor(stamina) .. "%" or "нет данных"

	local killerText = ""
	if RUN.Managed and killerIsNear() then
		killerText = " · ПАНИКА (киллер ближе " .. RUN.PanicDistance .. " м)"
	end

	if heldByScript then
		statusLabel.Text = "Стамина " .. staminaText .. " · спринт зажат скриптом" .. killerText
		statusLabel.TextColor3 = COLORS.On
	else
		statusLabel.Text = "Стамина " .. staminaText .. " · спринт отпущен (порог " .. (RUN.Managed and RUN.PanicFloor or RUN.Low) .. ")" .. killerText
		statusLabel.TextColor3 = COLORS.Muted
	end
end
end -- do-блок авто-бега (лимит 200 локалов)
