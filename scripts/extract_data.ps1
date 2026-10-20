<#
.SYNOPSIS
    LEGIONFORGE 7.3.5.26124 - извлечение игровых данных из клиента WoW.
.DESCRIPTION
    Запускает в папке клиента собранные инструменты сервера:
      mapextractor.exe   -> dbc, maps, gt, cameras
      vmap4extractor.exe -> Buildings
      vmap4assembler.exe -> vmaps
      mmaps_generator.exe-> mmaps (долго: 1-4 часа; пропуск: -SkipMMaps)
    и переносит результат в server\data. Уже извлечённые части повторно не делаются.
#>
param([string]$Root = '', [string]$ClientDir = '', [switch]$SkipMMaps, [switch]$Auto)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$server = Join-Path $Root 'server'
$data = Join-Path $server 'data'

foreach ($exe in 'mapextractor.exe', 'vmap4extractor.exe', 'vmap4assembler.exe') {
    if (-not (Test-Path -LiteralPath (Join-Path $server $exe))) {
        Write-Host "  [ОШИБКА] Нет server\$exe - сначала соберите сервер (build_server.bat)."
        exit 1
    }
}

function Test-Client([string]$Dir) {
    return $Dir -and (Test-Path -LiteralPath (Join-Path $Dir 'Data')) -and
        ((Test-Path -LiteralPath (Join-Path $Dir 'WoW-64.exe')) -or (Test-Path -LiteralPath (Join-Path $Dir 'Wow.exe')) -or (Test-Path -LiteralPath (Join-Path $Dir '.build.info')))
}

if (-not (Test-Client $ClientDir)) {
    $ClientDir = ''
    $saved = Join-Path $Root 'client_path.txt'
    if (Test-Path -LiteralPath $saved) {
        $p = (Get-Content -LiteralPath $saved -TotalCount 1).Trim().Trim('"')
        if ($p) { $d = Split-Path -Parent $p; if (Test-Client $d) { $ClientDir = $d } }
    }
}
if (-not $ClientDir) {
    $candidates = @()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)) {
        foreach ($name in 'WoW', 'World of Warcraft', 'WoW 7.3.5', 'Legion', 'WoW_Legion', 'Games\WoW', 'Games\World of Warcraft', 'LegionForge\client', 'LegionForge\WoW') {
            $candidates += (Join-Path $drive $name)
        }
    }
    $candidates += (Join-Path $Root 'client'), (Join-Path (Split-Path -Parent $Root) 'WoW')
    foreach ($c in $candidates) { if (Test-Client $c) { $ClientDir = $c; break } }
}
while (-not (Test-Client $ClientDir)) {
    Write-Host '  Клиент WoW 7.3.5 (26124) не найден. Введите путь к папке клиента'
    Write-Host '  (где лежат WoW-64.exe и папка Data), пусто - отмена:'
    $ClientDir = (Read-Host '  Папка клиента').Trim().Trim('"')
    if (-not $ClientDir) { Write-Host '  [ОШИБКА] Отменено.'; exit 1 }
}
Write-Host "  [OK] Клиент: $ClientDir"
$wow64 = Join-Path $ClientDir 'WoW-64.exe'
if (Test-Path -LiteralPath $wow64) { Set-Content -LiteralPath (Join-Path $Root 'client_path.txt') -Value $wow64 -Encoding ASCII }

function Invoke-Tool([string]$Exe, [string[]]$Arguments) {
    $src = Join-Path $server $Exe
    $dst = Join-Path $ClientDir $Exe
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  [*] $Exe $($Arguments -join ' ')  (папка клиента)"
    $p = Start-Process -FilePath $dst -ArgumentList $Arguments -WorkingDirectory $ClientDir -NoNewWindow -Wait -PassThru
    Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { throw "$Exe завершился с кодом $($p.ExitCode)" }
}
function Move-Part([string]$Name) {
    $from = Join-Path $ClientDir $Name
    if (-not (Test-Path -LiteralPath $from)) { return }
    $to = Join-Path $data $Name
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Recurse -Force }
    Move-Item -LiteralPath $from -Destination $to -Force
    Write-Host "  [OK] server\data\$Name"
}

New-Item -ItemType Directory -Force -Path $data | Out-Null
$hasDbc = @(Get-ChildItem -LiteralPath (Join-Path $data 'dbc') -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'ChrRaces.db2') }).Count -gt 0
if (-not ($hasDbc -and (Test-Path -LiteralPath (Join-Path $data 'maps')))) {
    Invoke-Tool 'mapextractor.exe' @()
    foreach ($n in 'dbc', 'maps', 'gt', 'cameras') { Move-Part $n }
}
if (-not (Test-Path -LiteralPath (Join-Path $data 'vmaps'))) {
    Invoke-Tool 'vmap4extractor.exe' @()
    New-Item -ItemType Directory -Force -Path (Join-Path $ClientDir 'vmaps') | Out-Null
    Invoke-Tool 'vmap4assembler.exe' @('Buildings', 'vmaps')
    Move-Part 'vmaps'
    Remove-Item -LiteralPath (Join-Path $ClientDir 'Buildings') -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not $SkipMMaps -and -not (Test-Path -LiteralPath (Join-Path $data 'mmaps')) -and (Test-Path -LiteralPath (Join-Path $server 'mmaps_generator.exe'))) {
    Write-Host '  [*] mmaps_generator: построение навигационных сеток (1-4 часа)...'
    # mmaps_generator reads ./maps and ./vmaps from its working directory
    $gen = Join-Path $data 'mmaps_generator.exe'
    Copy-Item -LiteralPath (Join-Path $server 'mmaps_generator.exe') -Destination $gen -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $data 'mmaps') | Out-Null
    $p = Start-Process -FilePath $gen -WorkingDirectory $data -NoNewWindow -Wait -PassThru
    Remove-Item -LiteralPath $gen -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { Write-Host "  [!] mmaps_generator вернул код $($p.ExitCode): сервер работает и без mmaps (без поиска пути)." }
}
Write-Host '  [OK] Игровые данные готовы: server\data'
exit 0
