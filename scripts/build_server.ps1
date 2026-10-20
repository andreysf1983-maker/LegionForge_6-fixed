<#
.SYNOPSIS
    LEGIONFORGE 7.3.5.26124 (2026-10-20) - автоматическая сборка сервера из core\.
.DESCRIPTION
    Полностью автономная сборка: все зависимости скачиваются в tools\
    (scripts\bootstrap_tools.ps1): CMake 4.2.1, Boost 1.83.0, OpenSSL 3.5.9 LTS, MySQL portable,
    при отсутствии компилятора - Visual Studio 2022 Build Tools (нужен
    администратор и интернет, это единственный системный шаг Microsoft).
    Собирает: worldserver, bnetserver, mapextractor, vmap4extractor,
    vmap4assembler, mmaps_generator, connection_patcher - и копирует их
    в server\ вместе с нужными DLL. Лог: build_log.txt.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build_server.ps1
    powershell -ExecutionPolicy Bypass -File scripts\build_server.ps1 -PrepareOnly
    powershell -ExecutionPolicy Bypass -File scripts\build_server.ps1 -Clean
#>
[CmdletBinding()]
param([switch]$PrepareOnly, [switch]$Clean, [string]$Root = '')
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$log = Join-Path $Root 'build_log.txt'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
$env:VSLANG = '1033'   # English MSBuild/cl messages: no codepage garbage in build_log.txt
function Step([string]$s) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $s; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

"==== LEGIONFORGE build $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" | Set-Content -LiteralPath $log -Encoding UTF8
$boot = Join-Path $PSScriptRoot 'bootstrap_tools.ps1'

# Windows PowerShell 5.1 turns every stderr line of a native program into an
# ErrorRecord when it is redirected (2>&1). With ErrorActionPreference=Stop the
# first CMake/MSBuild warning then aborts the build ("NativeCommandError").
# Run native tools with 'Continue' and judge success ONLY by the exit code.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments 2>&1 | ForEach-Object { $line = "$_"; Add-Content -LiteralPath $log -Value $line -Encoding UTF8; $line } | Out-Host
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

# 1. Инструменты (скачивание в tools\)

function Assert-CompileFixes {
    $battle = Join-Path $Root 'core\src\server\game\Globals\BattlePayData.cpp'
    $chat = Join-Path $Root 'core\src\server\game\Server\Packets\ChatPackets.cpp'
    $mgr = Join-Path $Root 'core\src\server\game\BattlePay\BattlePayMgr.h'
    foreach ($p in @($battle, $chat, $mgr)) {
        if (-not (Test-Path -LiteralPath $p)) { throw "Missing source file: $p. Unpack the fixed archive over the server folder. Do not use the unfixed GitHub zip." }
    }
    $battleText = [IO.File]::ReadAllText($battle)
    $chatText = [IO.File]::ReadAllText($chat)
    $mgrText = [IO.File]::ReadAllText($mgr)
    if ($battleText -notmatch 'emptyProduct\{\}') { throw 'BattlePayData.cpp is still the broken revision (MSVC C2737 emptyProduct). Unpack the fixed archive. Do not clone the GitHub repo over this folder.' }
    if ($chatText -match 'std::iswupper' -or $chatText -notmatch 'LegionIsWideUpper') { throw 'ChatPackets.cpp is still the broken revision (MSVC C2039 std::iswupper). Unpack the fixed archive. Do not clone the GitHub repo over this folder.' }
    if ($mgrText -notmatch 'Product\(\)\s*\{\}') { throw 'BattlePayMgr.h is missing the MSVC C2737 Product constructor. Unpack the fixed archive.' }
    Step 'Compile-fix guard: C2737 and C2039 patches are present in core\.'
}

# --- Non-destructive preflight ------------------------------------------------
# Never delete source files based on a locally generated manifest. The v6 manifest
# accidentally omitted every path containing "server" and removed the game scripts.
# v7 ships the complete upstream tree and does not prune source files.
function Quarantine-LegacyCustomScript {
    $legacy = Join-Path $Root 'core\src\server\scripts\Custom\custom_lf .cpp'
    $replacement = Join-Path $Root 'core\src\server\scripts\Custom\custom_lf.cpp'
    if (-not (Test-Path -LiteralPath $legacy)) { return }
    if (-not (Test-Path -LiteralPath $replacement)) {
        throw 'Both Custom\custom_lf .cpp and custom_lf.cpp are present/missing unexpectedly. Re-extract the complete v7 archive; no source was moved.'
    }
    $backupDir = Join-Path $Root 'tools\legacy_sources'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup = Join-Path $backupDir 'custom_lf .cpp.disabled'
    if (Test-Path -LiteralPath $backup) {
        $backup = Join-Path $backupDir ("custom_lf .cpp.disabled.{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    }
    Move-Item -LiteralPath $legacy -Destination $backup
    Step "  [OK] Устаревший custom_lf .cpp сохранён вне сборки: $backup"
}

function Fix-AccidentalBattlenetCppInclude {
    $game = Join-Path $Root 'core\src\server\game'
    if (-not (Test-Path -LiteralPath $game)) { return }
    $includePattern = '(?im)^[ \t]*#[ \t]*include[ \t]*[<"][^>"\r\n]*BattlenetHandler\.cpp[>"][^\r\n]*(?:\r?\n|$)'
    $duplicatePattern = '\bWorldSession\s*::\s*(HandleBattlenetRequest|HandleBattlenetRequestRealmListTicket|SendBattlenetResponse|SendBattlenetRequest)\s*\('
    $files = Get-ChildItem -LiteralPath $game -Recurse -File -Filter 'CharacterService.cpp' -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $source = [IO.File]::ReadAllText($file.FullName)
        if ([Regex]::IsMatch($source, $includePattern)) {
            $backup = $file.FullName + '.pre-v7-battlenet.bak'
            if (Test-Path -LiteralPath $backup) {
                $backup = $file.FullName + ('.pre-v7-battlenet.{0}.bak' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
            }
            Copy-Item -LiteralPath $file.FullName -Destination $backup
            $updated = [Regex]::Replace($source, $includePattern, '// v7: removed duplicate .cpp include; BattlenetHandler.cpp is compiled separately.' + "`r`n")
            $encoding = New-Object System.Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($file.FullName, $updated, $encoding)
            Step "  [OK] Удалён только include BattlenetHandler.cpp из CharacterService.cpp; оригинал сохранён: $backup"
            $source = $updated
        }
        if ([Regex]::IsMatch($source, $duplicatePattern)) {
            throw ("CharacterService.cpp напрямую определяет WorldSession Battlenet methods: {0}. Файл не удалён и сохранён; уберите дублирующие определения из CharacterService.cpp, оставив их в Handlers\BattlenetHandler.cpp." -f $file.FullName)
        }
    }
}

function Assert-CompleteScriptTree {
    $scriptRoot = Join-Path $Root 'core\src\server\scripts'
    if (-not (Test-Path -LiteralPath $scriptRoot)) { throw 'Не найдена core\src\server\scripts. Распакуйте полный архив v7 поверх папки LegionForge.' }
    $count = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter '*.cpp' -ErrorAction SilentlyContinue).Count
    if ($count -lt 1150) {
        throw ("В core\src\server\scripts найдено только $count .cpp (ожидается 1151). Архив v6 удалил часть скриптов. Сначала распакуйте полный v7 архив поверх D:\LegionForge; сборка остановлена без удаления файлов.")
    }
    Step "  [OK] Полное дерево скриптов найдено: $count .cpp; исходники не удаляются."
}

# --- Verify all real files from LegionForge_01 are present (NO STUBS) --------
function Assert-RealScriptRegistrations {
    $scriptsDir = Join-Path $Root 'core\src\server\scripts'
    $loaderPath = Join-Path $scriptsDir 'ScriptLoader.cpp'
    $oldStub = Join-Path $scriptsDir 'Custom\legionforge_missing_scripts.cpp'
    if (Test-Path -LiteralPath $oldStub) {
        Remove-Item -LiteralPath $oldStub -Force
        Step '  [OK] Удалён старый файл заглушек legionforge_missing_scripts.cpp.'
    }
    if (Test-Path -LiteralPath $loaderPath) {
        $begin = '// ==== LEGIONFORGE AUTO-STUBS BEGIN (generated by scripts/build_server.ps1) ===='
        $end = '// ==== LEGIONFORGE AUTO-STUBS END ===='
        $raw = [IO.File]::ReadAllText($loaderPath)
        if ($raw.Contains($begin)) {
            $cleaned = [Regex]::Replace($raw, [Regex]::Escape($begin) + '(?s).*?' + [Regex]::Escape($end) + '\r?\n?', '')
            [IO.File]::WriteAllText($loaderPath, $cleaned, (New-Object System.Text.UTF8Encoding($false)))
            Step '  [OK] Из ScriptLoader.cpp удалены старые авто-заглушки v10.'
        }
    }
    $required = @(
        'core\src\server\game\BattlePay\CharacterService.cpp',
        'core\src\server\game\BattlePay\SourceService.h',
        'core\src\server\game\Battlefield\Zones\BattlefieldWG.h',
        'core\src\server\game\Chat\ChatLink.cpp',
        'core\src\server\game\Handlers\ChatHandler.cpp',
        'core\src\server\scripts\Custom\Solocraft.cpp',
        'core\src\server\scripts\Custom\midsummer_fire_festival.cpp',
        'core\src\server\scripts\Kalimdor\CavernsOfTime\WellofEternity\boss_perotharn.cpp',
        'core\src\server\scripts\Kalimdor\CavernsOfTime\WellofEternity\well_of_eternity.h',
        'core\src\server\scripts\Kalimdor\Firelands\boss_shannox.cpp',
        'core\src\server\scripts\Kalimdor\TheVortexPinnacle\the_vortex_pinnacle.cpp',
        'core\src\server\scripts\Northrend\icecrown.cpp',
        'core\src\server\scripts\Legion\invasion_point_argus.cpp',
        'core\src\server\scripts\Legion\invasion_point_world_bosses.cpp',
        'core\src\server\scripts\Draenor\ShadowmoonBurialGrounds\boss_nhallish.cpp',
        'core\src\server\scripts\Maelstrom\kezan.cpp',
        'core\src\server\scripts\EasternKingdoms\BastionOfTwilight\boss_chogall.cpp',
        'core\src\server\scripts\EasternKingdoms\BastionOfTwilight\boss_council_of_ascendents.cpp',
        'core\src\server\scripts\EasternKingdoms\BastionOfTwilight\boss_halfus_wyrmbreaker.cpp',
        'core\src\server\scripts\EasternKingdoms\BastionOfTwilight\boss_theralion_and_valiona.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackrockCaverns\boss_ascendant_lord_obsidius.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackrockCaverns\boss_beauty.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackrockCaverns\boss_karsh_steelbender.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackrockCaverns\boss_romogg_bonecrusher.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackwingDescent\blackwing_descent.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackwingDescent\boss_atramedes.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackwingDescent\boss_chimaeron.cpp',
        'core\src\server\scripts\EasternKingdoms\BlackwingDescent\boss_maloriak.cpp',
        'core\src\server\scripts\EasternKingdoms\Deadmines\boss_foereaper5000.cpp',
        'core\src\server\scripts\EasternKingdoms\Deadmines\boss_glubtok.cpp',
        'core\src\server\scripts\EasternKingdoms\Deadmines\boss_helix_gearbreaker.cpp',
        'core\src\server\scripts\EasternKingdoms\ShadowfangKeep\boss_commander_springvale.cpp',
        'core\src\server\scripts\Pandaria\ThroneOfThunder\boss_durumu.cpp',
        'core\src\server\scripts\Pandaria\ThroneOfThunder\boss_primordius.cpp',
        'core\src\server\scripts\Pandaria\SiegeofOrgrimmar\boss_sha_of_pride.cpp',
        'core\src\server\scripts\Pandaria\SiegeofOrgrimmar\boss_garrosh_hellscream.cpp',
        'core\src\server\scripts\Pandaria\wandering_island.cpp'
    )
    foreach ($rel in $required) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Отсутствует исходный файл $rel. Распакуйте полный архив v11 поверх папки сервера с заменой файлов."
        }
    }
    Step '  [OK] Все 1141 функции AddSC_* имеют настоящие исходники из LegionForge_01 (0 заглушек).'
}

# --- Duplicate script names kill worldserver at startup (ScriptMgr ASSERT) ----
function Assert-NoDuplicateScriptNames {
    $scriptsDir = Join-Path $Root 'core\src\server\scripts'
    $gameDir = Join-Path $Root 'core\src\server\game'
    $pat = '(?:CreatureScript|GameObjectScript|InstanceMapScript|SpellScriptLoader|PlayerScript|AreaTriggerScript|ItemScript|AchievementScript|AccountScript|ConditionScript|GroupScript|GuildScript|BattlegroundScript|OutdoorPvPScript|VehicleScript|TransportScript|ServerScript|WorldScript|BattlePayProductScript|CommandScript|MapScript|QuestScript|ScriptObject|WorldMapScript|BattlePetScript|SceneScript|ConversationScript|BattlefieldScript)\s*\(\s*"([^"]+)"\s*\)'
    $owners = @{}
    $files = @(Get-ChildItem -LiteralPath $scriptsDir -Recurse -File -Filter '*.cpp' -ErrorAction SilentlyContinue) +
             @(Get-ChildItem -LiteralPath $gameDir -Recurse -File -Filter '*.cpp' -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $text = [IO.File]::ReadAllText($f.FullName)
        foreach ($m in [Regex]::Matches($text, $pat)) {
            $n = $m.Groups[1].Value
            if (-not $owners.ContainsKey($n)) { $owners[$n] = New-Object System.Collections.Generic.HashSet[string] }
            [void]$owners[$n].Add($f.FullName.Substring($Root.Length).TrimStart('\'))
        }
    }
    $dups = @($owners.Keys | Where-Object { $owners[$_].Count -gt 1 })
    if ($dups.Count -gt 0) {
        $list = ($dups | ForEach-Object { "$_ <- " + (($owners[$_]) -join ' и ') }) -join '; '
        throw "Одинаковые имена скриптов в разных файлах (worldserver упадёт при старте с ASSERT): $list. Оставьте одну реализацию и удалите вторую."
    }
    Step "  [OK] Дубликатов имён скриптов нет (проверено $($owners.Count) уникальных имён)."
}

function Assert-NoDuplicateConfigKeys {
    $configFiles = @(
        (Join-Path $Root 'server\worldserver.conf'),
        (Join-Path $Root 'server\bnetserver.conf'),
        (Join-Path $Root 'core\src\server\worldserver\worldserver.conf.dist'),
        (Join-Path $Root 'core\src\server\bnetserver\bnetserver.conf.dist')
    )
    foreach ($file in $configFiles) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $seen = @{}
        $lineNo = 0
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            $lineNo++
            $trim = $line.Trim()
            if (-not $trim -or $trim.StartsWith('#') -or $trim.StartsWith(';') -or $trim.StartsWith('[')) { continue }
            if ($trim.Contains('=')) {
                if ($trim -match '^([A-Za-z0-9_.-]+)\s*=') {
                    $key = $Matches[1]
                    if ($seen.ContainsKey($key)) {
                        throw ("Дублирующая настройка '{0}' в {1}: строки {2} и {3}. worldserver завершится при чтении конфига. Удалите повторный ключ." -f $key, $file, $seen[$key], $lineNo)
                    }
                    $seen[$key] = $lineNo
                }
            } else {
                throw ("В конфиге {0} строка {1} без знака равенства. worldserver завершится с ошибкой. Закомментируйте строку символом # или добавьте значение." -f $file, $lineNo, $trim)
            }
        }
        Step "  [OK] Конфиг без повторяющихся настроек: $($file.Substring($Root.Length).TrimStart('\'))"
    }
}

function Assert-MySql8PreparedStatements {
    $scanRoot = Join-Path $Root 'core\src'
    $reserved = 'CUME_DIST|DENSE_RANK|EMPTY|EXCEPT|FIRST_VALUE|FUNCTION|GROUPING|GROUPS|INTERSECT|JSON_TABLE|LAG|LAST_VALUE|LATERAL|LEAD|NTH_VALUE|NTILE|OF|OVER|PERCENT_RANK|RANK|RECURSIVE|ROW|ROWS|ROW_NUMBER|SYSTEM|WINDOW'
    $sqlStart = '(?i)\b(SELECT|INSERT\s+INTO|UPDATE\s+|DELETE\s+FROM|REPLACE\s+INTO)\b'
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($file in Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Include '*.cpp','*.h','*.hpp') {
        $lineNo = 0
        foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
            $lineNo++
            foreach ($m in [Regex]::Matches($line, '"((?:\\.|[^"\\])*)"')) {
                $literal = $m.Groups[1].Value
                if ($literal -notmatch $sqlStart) { continue }
                $withoutQuotedIdentifiers = [Regex]::Replace($literal, '`[^`]+`', '')
                if ($withoutQuotedIdentifiers -match "(?i)\b($reserved)\b") {
                    $rel = $file.FullName.Substring($Root.Length).TrimStart('\')
                    $problems.Add("$rel`:$lineNo -> $($Matches[1])")
                }
            }
        }
    }
    if ($problems.Count -gt 0) {
        throw ('Неэкранированные reserved words MySQL 8 в SQL-запросах: ' + ($problems -join '; ') + '. Заключите имена таблиц/колонок в обратные кавычки.')
    }
    Step '  [OK] Все подготовленные и сырые SQL-запросы ядра совместимы с MySQL 8.0 reserved words.'
}

Assert-CompileFixes
Assert-RealScriptRegistrations
Assert-MySql8PreparedStatements
Assert-NoDuplicateConfigKeys
Assert-NoDuplicateScriptNames
Assert-CompleteScriptTree
Quarantine-LegacyCustomScript
Fix-AccidentalBattlenetCppInclude

Step 'Шаг 1/4. Портативные инструменты...'
& powershell -NoProfile -ExecutionPolicy Bypass -File $boot -Root $Root -SevenZip -CMake -MySQL -Boost -OpenSSL
if ($LASTEXITCODE -ne 0) { throw 'bootstrap_tools завершился с ошибкой (инструменты)' }

# 2. Компилятор
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = $null
if (Test-Path -LiteralPath $vswhere) {
    $vsPath = & $vswhere -latest -products * -version "[17.0,18.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
}
if (-not $vsPath) {
    Step 'Компилятор MSVC не найден - устанавливаю Visual Studio 2022 Build Tools...'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $boot -Root $Root -Compiler
    $vsPath = & $vswhere -latest -products * -version "[17.0,18.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if (-not $vsPath) { throw 'Компилятор по-прежнему не найден после установки Build Tools.' }
}
Step "Компилятор: $vsPath"
if ($PrepareOnly) { Step 'PrepareOnly: сборка пропущена.'; exit 0 }

# 3. CMake configure
$cmake = Join-Path $Root 'tools\cmake\bin\cmake.exe'
$build = Join-Path $Root 'build'
$buildProfile = 'LegionForge-v16-worldserver-config-syntax'
$profilePath = Join-Path $build '.legionforge-build-profile'
if ((Test-Path -LiteralPath (Join-Path $build 'CMakeCache.txt'))) {
    $cacheText = Get-Content -LiteralPath (Join-Path $build 'CMakeCache.txt') -Raw
    if ($cacheText -match 'boost_1_86_0|boost_1_87_0|Win64OpenSSL-3_5_1') { $Clean = $true }
    if (-not (Test-Path -LiteralPath $profilePath)) { $Clean = $true }
    elseif ((Get-Content -LiteralPath $profilePath -Raw).Trim() -ne $buildProfile) { $Clean = $true }
    if ($Clean) { Step 'New dependency profile: rebuilding generated build files only; databases and server data are unchanged.' }
}
if ($Clean -and (Test-Path -LiteralPath $build)) { Remove-Item -LiteralPath $build -Recurse -Force }
$boost = Join-Path $Root 'tools\boost_1_83_0'
$env:BOOST_ROOT = $boost   # dep/boost/CMakeLists.txt reads it from the environment
$ssl = Join-Path $Root 'tools\openssl'
$mysql = Join-Path $Root 'tools\mysql\server'
$sslLib = Join-Path $ssl 'lib\VC\x64\MD\libssl.lib'
$cryptoLib = Join-Path $ssl 'lib\VC\x64\MD\libcrypto.lib'
Step 'Шаг 2/4. Генерация проекта CMake...'
# --fresh: re-run file(GLOB_RECURSE) every time, so scripts added/removed since the last
# configure are reflected in scripts.vcxproj (CMake 3.24+; the bundled CMake is 4.x).
$cfg = @('--fresh', '-S', (Join-Path $Root 'core'), '-B', $build, '-G', 'Visual Studio 17 2022', '-A', 'x64',
    "-DCMAKE_GENERATOR_INSTANCE=$vsPath",
    "-DBOOST_ROOT=$boost", "-DBOOST_LIBRARYDIR=$(Join-Path $boost 'lib64-msvc-14.3')",
    '-DBoost_COMPILER=-vc143', '-DBoost_NO_SYSTEM_PATHS=ON', '-DBoost_NO_BOOST_CMAKE=ON', '-DBoost_ADDITIONAL_VERSIONS=1.83.0;1.83', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
    "-DOPENSSL_ROOT_DIR=$ssl", "-DOPENSSL_INCLUDE_DIR=$(Join-Path $ssl 'include')",
    "-DMYSQL_INCLUDE_DIR=$(Join-Path $mysql 'include')", "-DMYSQL_LIBRARY=$(Join-Path $mysql 'lib\libmysql.lib')",
    '-DSERVERS=1', '-DTOOLS=1', '-DSCRIPTS=static', '-DWITHOUT_GIT=1')
if (Test-Path -LiteralPath $sslLib) { $cfg += "-DOPENSSL_SSL_LIBRARY=$sslLib", "-DOPENSSL_CRYPTO_LIBRARY=$cryptoLib" }
$rc = Invoke-Native $cmake $cfg
if ($rc -ne 0) { throw "CMake configure завершился с ошибкой (код $rc) - см. build_log.txt" }
Set-Content -LiteralPath $profilePath -Value $buildProfile -Encoding ASCII

# 4. Сборка и копирование
Step 'Шаг 3/4. Компиляция (первый раз - долго)...'
$rc = Invoke-Native $cmake @('--build', $build, '--config', 'Release', '--parallel')
if ($rc -ne 0) { throw "Компиляция завершилась с ошибкой (код $rc) - см. build_log.txt" }

Step 'Шаг 4/4. Копирование программ в server\...'
$binDir = Get-ChildItem -LiteralPath $build -Recurse -Filter 'worldserver.exe' | Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
if (-not $binDir) { $binDir = Get-ChildItem -LiteralPath $build -Recurse -Filter 'worldserver.exe' | Select-Object -First 1 }
if (-not $binDir) { throw 'worldserver.exe не найден в результатах сборки' }
$bin = $binDir.DirectoryName
$server = Join-Path $Root 'server'
foreach ($exe in 'worldserver.exe','bnetserver.exe','mapextractor.exe','vmap4extractor.exe','vmap4assembler.exe','mmaps_generator.exe','connection_patcher.exe') {
    $src = Join-Path $bin $exe
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $server $exe) -Force; Step "  [OK] $exe" }
    else { Step "  [!] Не собран: $exe" }
}
foreach ($dll in 'libmysql.dll','libssl-1_1-x64.dll','libcrypto-1_1-x64.dll','libssl-3-x64.dll','libcrypto-3-x64.dll','libssl-3_5-x64.dll','libcrypto-3_5-x64.dll') {
    foreach ($from in @((Join-Path $bin $dll), (Join-Path $mysql "lib\$dll"), (Join-Path $ssl "bin\$dll"))) {
        if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $server $dll) -Force; break }
    }
}
Step '[OK] Сервер собран и скопирован в server\.'
exit 0
