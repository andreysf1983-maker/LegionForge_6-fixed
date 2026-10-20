# LegionForge 7.3.5.26124 — ядро сервера

Ядро проекта **LegionForge** (сборка 2026-10-20). World of Warcraft Legion 7.3.5,
билд клиента 26124. Сборка: CMake + Visual Studio 2022 (x64), исходники в `core\`,
готовые exe собирает `build_server.bat` в папку `server\`.

Все зависимости (CMake, Boost, OpenSSL, MySQL) скачиваются автоматически в `tools\`
скриптом `scripts\bootstrap_tools.ps1` — установка в систему не требуется.

---

## Требования к сборке

* Visual Studio 2022 Build Tools (x64), MSVC 19.4x
* Boost 1.83.0 (prebuilt msvc-14.3)
* OpenSSL 3.x
* MySQL 8.0
* CMake 3.16+

Версия клиента: 7.3.5 (26124).

## Состав

| Папка      | Назначение                               |
|------------|------------------------------------------|
| `core\`    | исходный код ядра LegionForge             |
| `server\`  | собранные exe, конфиги, сертификаты       |
| `sql\`     | базы и обновления                         |
| `scripts\` | PowerShell-скрипты установки и сборки     |
| `tools\`   | портативные зависимости (скачиваются)     |

## Лицензия

GNU GPL v2 — см. `core\COPYING`.
Происхождение кода и обязательные указания авторства — см. `AUTHORS.txt`.
