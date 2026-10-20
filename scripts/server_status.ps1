param(
    [string]$CnfPath = "",
    [string]$MysqlExe = ""
)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $CnfPath) { $CnfPath = Join-Path $root "tools\mysql.cnf" }
if (-not $MysqlExe) {
    $MysqlExe = & (Join-Path $root "find_mysql.ps1") -Port 3306
}

function Test-PortListen([int]$Port) {
    try {
        if (@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    } catch { }
    return [bool](netstat -ano 2>$null | Select-String ":$Port" | Select-String "LISTENING")
}

$bnetUp = Test-PortListen 1119
$worldUp = Test-PortListen 8085
$mysqlUp = Test-PortListen 3306
$bnetCount = "?"
$gameCount = "?"

if ((Test-Path $CnfPath) -and $MysqlExe -and (Test-Path $MysqlExe)) {
    try {
        $bnetCount = & $MysqlExe --defaults-extra-file="$CnfPath" auth -N -e "SELECT COUNT(*) FROM battlenet_accounts;" 2>$null
        $gameCount = & $MysqlExe --defaults-extra-file="$CnfPath" auth -N -e "SELECT COUNT(*) FROM account;" 2>$null
    } catch { }
}

Write-Host ""
Write-Host "  LegionForge server status"
Write-Host "  ------------------------"
Write-Host ("  MySQL 3306      : {0}" -f $(if ($mysqlUp) { "listening" } else { "DOWN" }))
Write-Host ("  bnet 1119       : {0}" -f $(if ($bnetUp) { "listening" } else { "DOWN (login will fail)" }))
Write-Host ("  world 8085      : {0}" -f $(if ($worldUp) { "listening" } else { "DOWN" }))
Write-Host ("  Battle.net accts: {0}" -f $bnetCount)
Write-Host ("  Game accts      : {0}" -f $gameCount)
if ($bnetCount -eq "0") {
    Write-Host ""
    Write-Host "  >> No login accounts. Run create_account.bat or play.bat option [2]."
    Write-Host "     Log in with Battle.net EMAIL + password (not game username)."
}
if (-not $bnetUp) {
    Write-Host ""
    Write-Host "  >> bnet is DOWN - login will fail until port 1119 is listening."
    Write-Host "     Start play.bat option [1] and wait for bnet on 1119."
}
if ($bnetUp -and $worldUp -and $bnetCount -ne "0" -and $bnetCount -ne "?") {
    Write-Host ""
    Write-Host "  >> Ready to log in. Use Battle.net email + password at the client."
}
Write-Host ""
