--=========================== ЗАГРУЗЧИК АДМИН-МЕНЮ ===========================
--[[
	Зачем: скрипт разделён на модули (AdminMenuModules/*.luau), загрузчик
	читает их readfile-ом, СКЛЕИВАЕТ в один чанк и запускает. Поведение
	в рантайме не меняется: лимит Luau на 200 локалов считается по-прежнему
	на весь чанк.

	Установка в игре: папка AdminMenuModules в рабочей папке executor'а,
	рядом - AdminMenuLoader.client.lua. Запускать именно загрузчик.

	В Studio readfile НЕ существует - загрузчик выйдет с warn. Для Studio
	используется собранный AdminMenu.client.lua (перегенерируется
	build_menu.py из тех же модулей, расхождение исключено).
]]

local FOLDER = "AdminMenuModules"
local ORDER = {
	"00_core", -- шапка + константы
	"10_config", -- конфиг: доступ к файлам
	"20_world", -- состояние, читы, невидимость, ESP, интерфейс, список, стамина
	"30_combat", -- баннер о киллере, автоблок, зоны, хитбоксы
	"40_auto", -- аим + авто-бег / менеджмент стамины
	"50_ui", -- тумблеры, бинды, сборка меню, циклы
}

-- Всё-или-ничем: частичный чанк ломает перекрёстные ссылки (teamNameOf,
-- markDirty, body...), поэтому недостающий файл - ПОЛНАЯ остановка,
-- а не запуск половины меню.
local parts = {}
local missing = {}
for _, name in ipairs(ORDER) do
	local ok, content = pcall(function()
		return readfile(FOLDER .. "/" .. name .. ".luau")
	end)
	if ok and content and #content > 0 then
		table.insert(parts, content)
	else
		table.insert(missing, name)
	end
end

if #missing > 0 then
	warn("[AdminMenu] не найдены файлы модулей: " .. table.concat(missing, ", "))
	warn(
		"[AdminMenu] положи папку "
			.. FOLDER
			.. " в рабочую папку executor'а (рядом с этим скриптом) и запусти заново. "
			.. "Для Studio используется собранный AdminMenu.client.lua."
	)
	return
end

local combined = table.concat(parts, "")

local chunk, compileErr = loadstring(combined, "AdminMenu")
if not chunk then
	warn("[AdminMenu] ошибка компиляции склеенного чанка: " .. tostring(compileErr))
	return
end

local ok, runErr = pcall(chunk)
if not ok then
	warn("[AdminMenu] ошибка выполнения: " .. tostring(runErr))
end
