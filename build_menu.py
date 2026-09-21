#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Склейка модулей AdminMenuModules/*.luau в единый AdminMenu.client.lua.

Зачем: рантайм-версия собирается загрузчиком из тех же файлов, а для Studio
нужен один LocalScript. Билд гарантирует, что собранный файл и склейка
загрузчика совпадают байт-в-байт — расхождение исключено.

Порядок модулей здесь и в AdminMenuLoader.client.lua ДОЛЖЕН совпадать
(константы -> конфиг -> мир -> боёвка -> фичи -> интерфейс).
"""

import hashlib
import os
import sys

FOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AdminMenuModules")
OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AdminMenu.client.lua")
ORDER = ["00_core", "10_config", "20_world", "30_combat", "40_auto", "50_ui"]


def main():
    parts = []
    missing = []
    for name in ORDER:
        path = os.path.join(FOLDER, name + ".luau")
        if not os.path.isfile(path):
            missing.append(name)
            continue
        with open(path, encoding="utf-8") as f:
            parts.append(f.read())

    if missing:
        print("ОШИБКА: нет файлов: " + ", ".join(missing))
        print("Сборка всё-или-ничем: частичный чанк ломает перекрёстные ссылки.")
        sys.exit(1)

    combined = "".join(parts)

    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(combined)

    digest = hashlib.md5(combined.encode("utf-8")).hexdigest()
    lines = combined.count("\n") + (0 if combined.endswith("\n") or not combined else 1)
    print("Собрано: " + OUTPUT)
    print("Строк: %d, md5: %s" % (lines, digest))


if __name__ == "__main__":
    main()
