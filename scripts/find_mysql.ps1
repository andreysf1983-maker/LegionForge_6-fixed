param(
    [int]$Port = 3306,
    [switch]$StartService,
    [switch]$EnsureRunning
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-PortListenerPid([int]$ListenPort) {
    $connection = Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($connection) { return [int]$connection.OwningProcess }
    return $null
}

function Get-MysqlClientFromProcess([int]$ProcessId) {
    if (-not $ProcessId) { return $null }
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process -or -not $process.Path) { return $null }
    $client = Join-Path (Split-Path $process.Path -Parent) 'mysql.exe'
    if (Test-Path -LiteralPath $client) { return $client }
    return $null
}

function Find-InstalledMysqlClient {
    $portableClient = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\mysql\server\bin\mysql.exe'
    $candidates = @(
        Get-ChildItem -Path 'C:\Program Files\MySQL\MySQL Server *\bin\mysql.exe' -ErrorAction SilentlyContinue
        Get-ChildItem -Path 'C:\Program Files (x86)\MySQL\MySQL Server *\bin\mysql.exe' -ErrorAction SilentlyContinue
        Get-ChildItem -Path 'C:\Program Files\MariaDB*\bin\mysql.exe' -ErrorAction SilentlyContinue
        Get-ChildItem -Path 'C:\Program Files (x86)\MariaDB*\bin\mysql.exe' -ErrorAction SilentlyContinue
    ) | Where-Object { $_ }
    if ($candidates -and $candidates.Count -gt 0) {
        return ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }
    if (Test-Path -LiteralPath $portableClient) { return $portableClient }
    $pathClient = Get-Command mysql.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathClient) { return $pathClient.Source }
    return $null
}

function Start-DatabaseServices {
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'MySQL*' -or
            $_.Name -like 'MariaDB*' -or
            $_.DisplayName -match 'MySQL|MariaDB'
        } |
        Where-Object { $_.Status -ne 'Running' } |
        ForEach-Object {
            try { Start-Service -Name $_.Name -ErrorAction Stop } catch { }
        }
}

function Start-PortableMysql {
    $root = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\mysql'
    $serverExe = Join-Path $root 'server\bin\mysqld.exe'
    $configFile = Join-Path $root 'my.ini'
    if (-not (Test-Path -LiteralPath $serverExe) -or -not (Test-Path -LiteralPath $configFile)) { return $false }

    $logs = Join-Path $root 'logs'
    if (-not (Test-Path -LiteralPath $logs)) { New-Item -ItemType Directory -Force -Path $logs | Out-Null }
    $stdout = Join-Path $logs 'mysqld-stdout.log'
    $stderr = Join-Path $logs 'mysqld-stderr.log'
    $arguments = "--defaults-file=`"$configFile`" --console"
    try {
        Start-Process -FilePath $serverExe -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr | Out-Null
        return $true
    }
    catch { return $false }
}

function Wait-ForPort([int]$ListenPort, [int]$Attempts, [int]$DelaySeconds) {
    for ($i = 0; $i -lt $Attempts; $i++) {
        if (Get-PortListenerPid $ListenPort) { return $true }
        Start-Sleep -Seconds $DelaySeconds
    }
    return [bool](Get-PortListenerPid $ListenPort)
}

$listenerPid = Get-PortListenerPid $Port

if (($StartService -or $EnsureRunning) -and -not $listenerPid) {
    Start-DatabaseServices
    $listenerPid = Get-PortListenerPid $Port
    if (-not $listenerPid) {
        Wait-ForPort -ListenPort $Port -Attempts 15 -DelaySeconds 2 | Out-Null
        $listenerPid = Get-PortListenerPid $Port
    }
    if (-not $listenerPid) {
        if (Start-PortableMysql) {
            Wait-ForPort -ListenPort $Port -Attempts 60 -DelaySeconds 1 | Out-Null
            $listenerPid = Get-PortListenerPid $Port
        }
    }
}

if ($EnsureRunning -and -not (Get-PortListenerPid $Port)) { exit 1 }

$client = $null
if ($listenerPid) { $client = Get-MysqlClientFromProcess $listenerPid }
if (-not $client) { $client = Find-InstalledMysqlClient }

if ($client -and (Test-Path -LiteralPath $client)) {
    Write-Output $client
    exit 0
}

exit 1
