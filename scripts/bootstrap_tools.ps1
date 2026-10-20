<#
.SYNOPSIS
    LEGIONFORGE 7.3.5.26124 (2026-10-20) - портативные инструменты в папке tools\.
.DESCRIPTION
    Сервер самодостаточен: ничего не нужно ставить в систему.
    Скачивает и распаковывает в tools\ (без установки в Windows):
      -SevenZip   7zr.exe (7-zip.org) - распаковка .7z базы и архивов
      -CMake      CMake 4.2.1 portable zip (GitHub Kitware)
      -MySQL      MySQL 8.0 noinstall zip (cdn.mysql.com), инициализация data,
                  запуск mysqld на 127.0.0.1:3306 (-StartMySQL)
      -Boost      Boost 1.83.0 prebuilt MSVC 14.3 (https://archives.boost.io).
                  ВАЖНО: ядро использует io_service/from_string/resolver::query,
                  которые удалены в Boost 1.87 - поэтому именно 1.83.
      -WorldDB    база world/hotfixes (Legion_Proyect-DB.7z, ~98 MB, SHA-256)
                  -> tools\downloads\LegionForge-DB.7z
      -OpenSSL    OpenSSL 3.5.9 LTS Full для разработки (slproweb, локально в tools\openssl)
      -Compiler   Visual Studio 2022 Build Tools (aka.ms) - только если компилятор
                  не найден; это единственный шаг, требующий администратора и
                  загрузки ~нескольких ГБ от Microsoft.
    Каждый шаг идемпотентен: уже скачанное повторно не загружается.
    Если официальный адрес недоступен - попробуйте зеркало вручную и положите
    архив в tools\downloads, скрипт подхватит его сам.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\bootstrap_tools.ps1 -MySQL -StartMySQL
    powershell -ExecutionPolicy Bypass -File scripts\bootstrap_tools.ps1 -All
#>
[CmdletBinding()]
param(
    [switch]$SevenZip, [switch]$CMake, [switch]$MySQL, [switch]$Boost,
    [switch]$OpenSSL, [switch]$Compiler, [switch]$StartMySQL, [switch]$All, [switch]$WorldDB,
    [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol } catch { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is 10-50x slower with the progress bar
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Tools = Join-Path $Root 'tools'
$Dl = Join-Path $Tools 'downloads'
New-Item -ItemType Directory -Force -Path $Tools, $Dl | Out-Null
if ($All) { $SevenZip = $CMake = $MySQL = $Boost = $OpenSSL = $Compiler = $true }

function Test-DownloadedFile([string]$Path, [string]$ExpectedName) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt 10KB) { return $false }
    if ($ExpectedName.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
        $stream = [IO.File]::OpenRead($Path)
        try { $sig = New-Object byte[] 4; $read = $stream.Read($sig, 0, 4) } finally { $stream.Dispose() }
        if ($read -ne 4 -or $sig[0] -ne 0x50 -or $sig[1] -ne 0x4B -or
            $sig[2] -notin @(0x03,0x05,0x07) -or $sig[3] -notin @(0x04,0x06,0x08)) { return $false }
    }
    return $true
}

function Get-File([string]$Name, [string[]]$Urls, [int64]$ExpectedSize = -1, [string]$ExpectedSha256 = "") {
    $dst = Join-Path $Dl $Name
    if (Test-DownloadedFile $dst $Name) {
        if ($ExpectedSize -le 0 -or (Get-Item -LiteralPath $dst).Length -eq $ExpectedSize) {
            if (-not $ExpectedSha256 -or ((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -eq $ExpectedSha256)) {
                Write-Host "  [OK] Уже скачано и проверено: $Name"; return $dst
            }
        }
        Write-Host "  [!] Повреждённый/устаревший файл будет скачан заново: $Name"
        Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    $agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) LegionForge/2026.10.18'
    foreach ($u in $Urls) {
        try {
            Write-Host "  [*] Скачиваю $Name`n      $u"
            $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($curl) {
                & $curl.Source --fail --location --retry 4 --retry-delay 3 --connect-timeout 60 --max-time 3600 --user-agent $agent --output $dst $u
                if ($LASTEXITCODE -ne 0) { throw "curl exit code $LASTEXITCODE" }
            } else {
                Invoke-WebRequest -Uri $u -OutFile $dst -UseBasicParsing -Headers @{ 'User-Agent'=$agent } -MaximumRedirection 10 -TimeoutSec 3600
            }
            if (Test-DownloadedFile $dst $Name) {
                if ($ExpectedSize -gt 0 -and (Get-Item -LiteralPath $dst).Length -ne $ExpectedSize) { throw ("Неверный размер: {0}, ожидалось {1}" -f (Get-Item -LiteralPath $dst).Length, $ExpectedSize) }
                if ($ExpectedSha256 -and ((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ne $ExpectedSha256)) { throw 'SHA-256 не совпадает (файл повреждён)' }
                Write-Host ("  [OK] Скачано и проверено: {0:N1} MB" -f ((Get-Item $dst).Length / 1MB)); return $dst
            }
            throw 'Ответ сервера не является ожидаемым архивом ZIP/EXE.'
        } catch {
            Write-Host "      [!] Не удалось: $($_.Exception.Message)"
            Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        }
    }
    throw "Не удалось скачать $Name по официальным адресам. Положите файл вручную в $Dl."
}

function Invoke-MySqlQuery([string]$Exe, [string]$User, [string]$Password, [string]$Sql) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = "--user=$User --password=$Password --host=127.0.0.1 --port=3306 --protocol=tcp --batch --skip-column-names"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Cannot start mysql.exe: $Exe" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($Sql)
    $process.StandardInput.Close()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdoutTask.Result.Trim(); Stderr = $stderrTask.Result.Trim() }
}

function Test-MySqlLogin([string]$Exe, [string]$User, [string]$Password) {
    try {
        $r = Invoke-MySqlQuery $Exe $User $Password "SELECT 1;"
        return $r.ExitCode -eq 0
    } catch { return $false }
}

function Ensure-MySqlAdministrator([string]$Exe) {
    $adminUser = 'admin@legionforge.ru'
    $adminPassword = 'legionforge'
    if (Test-MySqlLogin $Exe $adminUser $adminPassword) {
        Write-Host "  [OK] MySQL administrator: $adminUser"
        return $true
    }

    $bootstrapSql = @"
ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
CREATE USER IF NOT EXISTS '$adminUser'@'localhost' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
CREATE USER IF NOT EXISTS '$adminUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
CREATE USER IF NOT EXISTS '$adminUser'@'%' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
ALTER USER '$adminUser'@'localhost' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
ALTER USER '$adminUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
ALTER USER '$adminUser'@'%' IDENTIFIED WITH mysql_native_password BY '$adminPassword';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '$adminUser'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '$adminUser'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '$adminUser'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON auth.* TO '$adminUser'@'localhost';
GRANT ALL PRIVILEGES ON characters.* TO '$adminUser'@'localhost';
GRANT ALL PRIVILEGES ON world.* TO '$adminUser'@'localhost';
GRANT ALL PRIVILEGES ON hotfixes.* TO '$adminUser'@'localhost';
GRANT ALL PRIVILEGES ON auth.* TO '$adminUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON characters.* TO '$adminUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON world.* TO '$adminUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON hotfixes.* TO '$adminUser'@'127.0.0.1';
FLUSH PRIVILEGES;
"@

    foreach ($candidate in @(
        @{ User = 'root'; Password = '' },
        @{ User = 'root'; Password = $adminPassword }
    )) {
        if (-not (Test-MySqlLogin $Exe $candidate.User $candidate.Password)) { continue }
        $result = Invoke-MySqlQuery $Exe $candidate.User $candidate.Password $bootstrapSql
        if ($result.ExitCode -ne 0) {
            Write-Host "      [!] MySQL administrator setup via $($candidate.User) failed: $($result.Stderr)"
            continue
        }
        if (Test-MySqlLogin $Exe $adminUser $adminPassword) {
            Write-Host "  [OK] MySQL administrator configured: $adminUser (root password also set to legionforge)"
            return $true
        }
    }
    Write-Host '  [!] Could not create admin@legionforge.ru automatically; setup.bat will request the existing MySQL root password.'
    return $false
}

function Get-SevenZr {
    $zr = Join-Path $Tools '7zip\7zr.exe'
    if (Test-Path -LiteralPath $zr) { return $zr }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zr) | Out-Null
    $dl7 = Get-File '7zr.exe' @('https://www.7-zip.org/a/7zr.exe', 'https://github.com/ip7z/7zip/releases/download/25.01/7zr.exe')
    Copy-Item -LiteralPath $dl7 -Destination $zr -Force
    Write-Host "  [OK] 7-Zip (7zr.exe): $zr"
    return $zr
}

function Expand-With([string]$Zr, [string]$Archive, [string]$Dest) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    # Official 7zr.exe is the reduced build: it handles 7z/xz only, NOT zip.
    # CMake and MySQL ship .zip, so use Expand-Archive (built into PowerShell 5.1).
    if ([IO.Path]::GetExtension($Archive).Equals('.zip', [StringComparison]::OrdinalIgnoreCase)) {
        Expand-Archive -LiteralPath $Archive -DestinationPath $Dest -Force
        return
    }
    & $Zr x -y -bso0 -bsp0 "-o$Dest" $Archive | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Extraction failed: $Archive (exit $LASTEXITCODE)" }
}

if ($SevenZip -or $MySQL -or $Boost -or $WorldDB -or $CMake) { $zr = Get-SevenZr }

if ($CMake) {
    $exe = Join-Path $Tools 'cmake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        $zip = Get-File 'cmake-4.2.1-windows-x86_64.zip' @(
            'https://github.com/Kitware/CMake/releases/download/v4.2.1/cmake-4.2.1-windows-x86_64.zip') -ExpectedSize 50046734
        Expand-With $zr $zip (Join-Path $Tools 'cmake-tmp')
        $inner = Get-ChildItem (Join-Path $Tools 'cmake-tmp') -Directory | Select-Object -First 1
        Move-Item -LiteralPath $inner.FullName (Join-Path $Tools 'cmake') -Force
        Remove-Item (Join-Path $Tools 'cmake-tmp') -Recurse -Force
    }
    Write-Host "  [OK] CMake: $exe"
}

if ($MySQL) {
    $mysqld = Join-Path $Tools 'mysql\server\bin\mysqld.exe'
    if (-not (Test-Path -LiteralPath $mysqld)) {
        $zip = $null
        # Oracle removes old patch releases from the main CDN. These official URLs
        # were probed on 2026-10-20: 8.0.46/45/44 all return HTTP 200.
        foreach ($version in @('8.0.46', '8.0.45', '8.0.44')) {
            try {
                $file = "mysql-$version-winx64.zip"
                $zip = Get-File $file @("https://cdn.mysql.com/Downloads/MySQL-8.0/$file", "https://cdn.mysql.com/archives/mysql-8.0/$file", "https://downloads.mysql.com/archives/get/p/23/file/$file")
                if ($zip) { break }
            } catch { Write-Host "      [!] MySQL $version недоступен: $($_.Exception.Message)" }
        }
        if (-not $zip) { throw 'Официальные MySQL 8.0.46/45/44 Windows ZIP недоступны.' }
        Write-Host '  [*] Распаковка MySQL (это большой архив, несколько минут)...'
        Expand-With $zr $zip (Join-Path $Tools 'mysql-tmp')
        $inner = Get-ChildItem (Join-Path $Tools 'mysql-tmp') -Directory | Select-Object -First 1
        New-Item -ItemType Directory -Force -Path (Join-Path $Tools 'mysql') | Out-Null
        Move-Item -LiteralPath $inner.FullName (Join-Path $Tools 'mysql\server') -Force
        Remove-Item (Join-Path $Tools 'mysql-tmp') -Recurse -Force
    }
    $base = Join-Path $Tools 'mysql\server'
    $data = Join-Path $Tools 'mysql\data'
    $ini = Join-Path $Tools 'mysql\my.ini'
    if (-not (Test-Path -LiteralPath $ini)) {
        @"
[mysqld]
basedir=$($base -replace '\\','/')
datadir=$($data -replace '\\','/')
port=3306
bind-address=127.0.0.1
character-set-server=utf8mb4
max_allowed_packet=512M
innodb-buffer-pool-size=256M
skip-name-resolve=OFF
[client]
host=127.0.0.1
port=3306
"@ | Set-Content -LiteralPath $ini -Encoding ASCII
    }
    if (-not (Test-Path -LiteralPath (Join-Path $data 'mysql'))) {
        Write-Host '  [*] Инициализация каталога данных MySQL...'

        # A previous PowerShell 5.1 run could stop on mysqld's NORMAL stderr progress
        # (NativeCommandError) and leave mysqld/data half-created. First wait for that exact
        # portable mysqld process to finish, then preserve incomplete data as a backup.
        $running = @(Get-Process -Name mysqld -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($mysqld)) } catch { $false }
        })
        foreach ($proc in $running) {
            Write-Host ("      Найден незавершённый mysqld PID {0}; жду завершения инициализации..." -f $proc.Id)
            if (-not $proc.WaitForExit(180000)) {
                throw "mysqld PID $($proc.Id) не завершился за 180 секунд. Завершите процесс вручную и повторите setup.bat."
            }
        }

        # The system tables are the completion marker. Anything else is an incomplete
        # attempt; never delete it silently - rename it for diagnostics/recovery.
        if ((Test-Path -LiteralPath $data) -and (Get-ChildItem -LiteralPath $data -Force -ErrorAction SilentlyContinue)) {
            $backup = "$data.incomplete-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -LiteralPath $data -Destination $backup -Force
            Write-Host "      [!] Незавершённый datadir сохранён: $backup"
        }
        New-Item -ItemType Directory -Force -Path $data | Out-Null

        # Do NOT invoke mysqld with '& ... 2>&1' under ErrorActionPreference=Stop:
        # MySQL writes normal progress to stderr and Windows PowerShell 5.1 converts the
        # first line into a terminating NativeCommandError. Redirect with Process API,
        # wait for the real process exit code, and save both streams as a diagnostic log.
        $initLog = Join-Path $Tools 'mysql\initialize.log'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $mysqld
        $psi.Arguments = ('--defaults-file="{0}" --initialize-insecure --console' -f $ini)
        $psi.WorkingDirectory = Split-Path -Parent $mysqld
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        if (-not $process.Start()) { throw 'Не удалось запустить mysqld --initialize-insecure' }
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $outTask.Result
        $stderr = $errTask.Result
        [IO.File]::WriteAllText($initLog, ($stdout + $stderr), (New-Object System.Text.UTF8Encoding($false)))
        if ($stderr) {
            ($stderr -split "`r?`n") | Where-Object { $_ } | Select-Object -Last 12 | ForEach-Object { Write-Host ("      " + $_) }
        }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $data 'mysql'))) {
            throw "mysqld --initialize-insecure завершился с кодом $($process.ExitCode). Лог: $initLog"
        }
        Write-Host "  [OK] Каталог данных MySQL инициализирован. Лог: $initLog"
    }
    Write-Host "  [OK] MySQL portable: $base"
}

if ($StartMySQL) {
    $up = Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue
    $mysqlExe = Join-Path $Tools 'mysql\server\bin\mysql.exe'
    if ($up) {
        Write-Host '  [OK] MySQL уже слушает 3306.'
        if (Test-Path -LiteralPath $mysqlExe) { [void](Ensure-MySqlAdministrator $mysqlExe) }
    }
    else {
        $mysqld = Join-Path $Tools 'mysql\server\bin\mysqld.exe'
        $ini = Join-Path $Tools 'mysql\my.ini'
        if (-not (Test-Path -LiteralPath $mysqld)) { throw 'Сначала выполните: bootstrap_tools.ps1 -MySQL' }
        Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$ini`"" -WorkingDirectory (Join-Path $Tools 'mysql\server\bin') -WindowStyle Minimized
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 2
            if (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue) { break }
        }
        if (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue) {
            Write-Host '  [OK] MySQL запущен (порт 3306).'
            [void](Ensure-MySqlAdministrator $mysqlExe)
        } else {
            $errFile = Get-ChildItem -LiteralPath (Join-Path $Tools 'mysql\data') -Filter '*.err' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($errFile) { Write-Host "      Последние строки $($errFile.FullName):"; Get-Content -LiteralPath $errFile.FullName -Tail 20 | ForEach-Object { Write-Host ("      " + $_) } }
            throw 'MySQL не поднялся за 60 секунд - смотрите лог выше и tools\mysql\data\*.err'
        }
    }
}

if ($Boost) {
    $boostRoot = Join-Path $Tools 'boost_1_83_0'
    $hdr = Join-Path $boostRoot 'boost\version.hpp'
    if (-not (Test-Path -LiteralPath $hdr)) {
        # archives.boost.io is the Boost project's current file host. Do NOT use
        # /download on SourceForge here: curl receives a 128 kB interstitial HTML page
        # with HTTP 200, which Start-Process then rejects as a corrupt executable.
        # Boost 1.83.0: the last line that still ships the deprecated Asio API the core
        # uses (io_service, address::from_string, resolver::query, null_buffers).
        # Boost 1.87 removed them and the core does not compile with it.
        $exe = Get-File 'boost_1_83_0-msvc-14.3-64.exe' @(
            'https://archives.boost.io/release/1.83.0/binaries/boost_1_83_0-msvc-14.3-64.exe',
            'https://sourceforge.net/projects/boost/files/boost-binaries/1.83.0/boost_1_83_0-msvc-14.3-64.exe/download') -ExpectedSize 205776491 -ExpectedSha256 '67975CE4A8799F17728DDBA8E64E9B450A6BDA7762643E829A96CCBBD1CA17D2'
        $stream = [IO.File]::OpenRead($exe)
        try { $head = New-Object byte[] 2; $null = $stream.Read($head, 0, 2) } finally { $stream.Dispose() }
        if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A) { throw "Загруженный Boost не является Windows EXE: $exe" }
        Write-Host '  [*] Boost 1.83.0 prebuilt MSVC 14.3 -> tools\boost_1_83_0 (unattended, local dir only)...'
        $p = Start-Process -FilePath $exe -ArgumentList @('/SP-', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$boostRoot`"") -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Boost installer exit code $($p.ExitCode)" }
        if (-not (Test-Path -LiteralPath $hdr)) { throw "Boost finished but $hdr is missing" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $boostRoot 'lib64-msvc-14.3'))) { throw "Boost libraries missing: $(Join-Path $boostRoot 'lib64-msvc-14.3')" }
    Write-Host "  [OK] Boost: $boostRoot"
}

if ($OpenSSL) {
    $lib = Join-Path $Tools 'openssl\lib\VC\x64\MD\libssl.lib'
    if (-not (Test-Path -LiteralPath $lib)) {
        # Full 3.5 LTS, never Light: headers/import libraries are required for development.
        # Size/SHA-256 come from slproweb's official hash registry.
        $exe = Get-File 'Win64OpenSSL-3_5_9.exe' @('https://slproweb.com/download/Win64OpenSSL-3_5_9.exe') -ExpectedSize 297484663 -ExpectedSha256 '5FE338C81D62515DF7292F16542A0EEF2A29DB3EFC023CD5A8C08EC3C97027AE'
        Write-Host '  [*] Тихая установка OpenSSL в tools\openssl (без изменения системы)...'
        $p = Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$(Join-Path $Tools 'openssl')`"" -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Установщик OpenSSL вернул код $($p.ExitCode)" }
    }
    Write-Host "  [OK] OpenSSL: $(Join-Path $Tools 'openssl')"
}

if ($WorldDB) {
    # world/hotfixes dump for LegionForge 7.3.5.26124. The file is not in
    # the LegionForge repository (GitHub 100 MB limit), so it is fetched from the
    # the upstream mirror below; verified by exact size + SHA-256. URL kept as-is so the download keeps working.
    $dbTarget = Join-Path $Dl 'LegionForge-DB.7z'
    $local = @((Join-Path $Root 'sql\base\LegionForge-DB.7z'), (Join-Path $Root 'sql\base\Legion_Proyect-DB.7z')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($local -and -not (Test-Path -LiteralPath $dbTarget)) { Copy-Item -LiteralPath $local -Destination $dbTarget -Force; Write-Host "  [OK] Локальный архив базы: $local" }
    $db = Get-File 'LegionForge-DB.7z' @(
        'https://raw.githubusercontent.com/zitengzela/LegionCore-7.3.5V2/V2/sql/base/Legion_Proyect-DB.7z',
        'https://github.com/zitengzela/LegionCore-7.3.5V2/raw/V2/sql/base/Legion_Proyect-DB.7z') -ExpectedSize 102283762 -ExpectedSha256 '6BB034EC09E736DEB814D4F511B19D5910722318ED171DB5789C4934784A58A9'
    Write-Host "  [OK] База world/hotfixes: $db"
}

if ($Compiler) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $found = $false
    if (Test-Path -LiteralPath $vswhere) {
        $found = [bool](& $vswhere -latest -products * -version "[17.0,18.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null)
    }
    if (-not $found) {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) { throw 'Для установки Visual Studio Build Tools запустите PowerShell ОТ ИМЕНИ АДМИНИСТРАТОРА.' }
        $bt = Get-File 'vs_BuildTools.exe' @('https://aka.ms/vs/17/release/vs_BuildTools.exe')
        Write-Host '  [*] Установка Visual Studio 2022 Build Tools (нагрузка VCTools). Это долго и требует интернета...'
        $p = Start-Process -FilePath $bt -ArgumentList '--quiet', '--wait', '--norestart', '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended' -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "vs_BuildTools вернул код $($p.ExitCode)" }
    }
    Write-Host '  [OK] Компилятор MSVC доступен.'
}

Write-Host '  [OK] bootstrap_tools завершён.'
exit 0
