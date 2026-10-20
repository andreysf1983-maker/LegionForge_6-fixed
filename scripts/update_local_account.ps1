param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [Parameter(Mandatory = $true)]
    [string]$Email,
    [int]$GmLevel = 3,
    [string]$CnfPath = "",
    [string]$MysqlExe = ""
)

$ErrorActionPreference = "Stop"

function ConvertTo-UpperLatin([string]$Value) {
    return $Value.ToUpperInvariant()
}

function Get-GameAccountShaPassHash([string]$Name, [string]$Pass) {
    $name = ConvertTo-UpperLatin $Name
    $pass = ConvertTo-UpperLatin $Pass
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes("${name}:${pass}")
        $hash = $sha1.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("X2") })
    }
    finally {
        $sha1.Dispose()
    }
}

function Get-BnetShaPassHash([string]$EmailAddress, [string]$Pass) {
    $email = ConvertTo-UpperLatin $EmailAddress
    $pass = ConvertTo-UpperLatin $Pass

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $emailHash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($email))
        $emailHex = -join ($emailHash | ForEach-Object { $_.ToString("X2") })
    }
    finally {
        $sha256.Dispose()
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $finalHash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes("${emailHex}:${pass}"))
        return -join ($finalHash[($finalHash.Length - 1)..0] | ForEach-Object { $_.ToString("X2") })
    }
    finally {
        $sha256.Dispose()
    }
}

function Escape-Sql([string]$Value) {
    return $Value.Replace("\", "\\").Replace("'", "''")
}

function Invoke-AuthSql([string]$Sql, [string]$Label, [switch]$Raw) {
    $mysqlArgs = @("--defaults-extra-file=$CnfPath", "auth")
    if ($Raw) { $mysqlArgs += "-N" }
    $mysqlArgs += @("-e", $Sql)
    $prevPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $MysqlExe @mysqlArgs 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevPreference
    }
    if ($code -ne 0) {
        foreach ($line in $output) { Write-Host "  [!] $line" }
        Write-Host "  [!] MySQL failed ($Label), exit code $code"
        exit 1
    }
    if ($Raw) {
        # Только строки-результаты (id). Предупреждения mysql в них не попадают.
        return @($output | Where-Object { $_ -match '^\d+$' })
    }
    return $output
}

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $CnfPath) { $CnfPath = Join-Path $root "tools\mysql.cnf" }
if (-not $MysqlExe) {
    $MysqlExe = & (Join-Path $root "find_mysql.ps1") -Port 3306
}

$user = ConvertTo-UpperLatin $Username
$email = ConvertTo-UpperLatin $Email
$sqlUser = Escape-Sql $user
$sqlEmail = Escape-Sql $email
$sqlGameHash = Escape-Sql (Get-GameAccountShaPassHash $user $Password)
$sqlBnetHash = Escape-Sql (Get-BnetShaPassHash $email $Password)

# Схема auth должна содержать колонки, которые читает ядро (например reg_mail).
$ensureScript = Join-Path $root "ensure_auth_schema.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensureScript -Root $root -CnfPath $CnfPath -MysqlExe $MysqlExe
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [!] Схема базы auth не готова. Исправьте сообщения выше и повторите."
    exit 1
}

$bnetId = Invoke-AuthSql "SELECT id FROM battlenet_accounts WHERE email = '$sqlEmail' LIMIT 1;" "find bnet account" -Raw
$gameId = Invoke-AuthSql "SELECT id FROM account WHERE username = '$sqlUser' LIMIT 1;" "find game account" -Raw

if (-not $bnetId -or -not $gameId) {
    Write-Host "  [!] Account not found. Create it first with create_account.bat"
    exit 1
}

Invoke-AuthSql "UPDATE battlenet_accounts SET sha_pass_hash = '$sqlBnetHash' WHERE email = '$sqlEmail';" "update bnet password" | Out-Null
Invoke-AuthSql "UPDATE account SET sha_pass_hash = '$sqlGameHash' WHERE username = '$sqlUser';" "update game password" | Out-Null
Invoke-AuthSql @"
DELETE FROM account_access WHERE id = $gameId;
INSERT INTO account_access (id, gmlevel, RealmID) VALUES ($gameId, $GmLevel, -1);
"@ "set gm level" | Out-Null

Write-Host "  [OK] Password updated for $email"
Write-Host "       Game account : $user"
Write-Host "       GM level     : $GmLevel"
Write-Host ""
Write-Host "  Log in with email $email and your new password."
