param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [Parameter(Mandatory = $true)]
    [string]$Email,
    [int]$GmLevel = 0,
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

if (-not $Email.Contains("@")) {
    Write-Host "  [!] Email must contain @ (Battle.net login uses email, not game username)."
    exit 1
}

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $CnfPath) { $CnfPath = Join-Path $root "tools\mysql.cnf" }
if (-not (Test-Path -LiteralPath $CnfPath)) {
    Write-Host "  [!] MySQL credentials not found: $CnfPath"
    Write-Host "      Run setup.bat first."
    exit 1
}

if (-not $MysqlExe) {
    $MysqlExe = & (Join-Path $root "find_mysql.ps1") -Port 3306
}
if (-not $MysqlExe -or -not (Test-Path -LiteralPath $MysqlExe)) {
    Write-Host "  [!] mysql.exe not found on PATH or port 3306."
    exit 1
}

$user = ConvertTo-UpperLatin $Username
$email = ConvertTo-UpperLatin $Email
$gameHash = Get-GameAccountShaPassHash $user $Password
$bnetHash = Get-BnetShaPassHash $email $Password

$sqlUser = Escape-Sql $user
$sqlEmail = Escape-Sql $email
$sqlGameHash = Escape-Sql $gameHash
$sqlBnetHash = Escape-Sql $bnetHash

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

# Схема auth должна содержать колонки, которые читает ядро (например reg_mail).
$ensureScript = Join-Path $root "ensure_auth_schema.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensureScript -Root $root -CnfPath $CnfPath -MysqlExe $MysqlExe
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [!] Схема базы auth не готова. Исправьте сообщения выше и повторите."
    exit 1
}

$existingGame = Invoke-AuthSql "SELECT id FROM account WHERE username = '$sqlUser' LIMIT 1;" "check game account" -Raw
$existingBnet = Invoke-AuthSql "SELECT id FROM battlenet_accounts WHERE email = '$sqlEmail' LIMIT 1;" "check bnet account" -Raw

if ($existingGame) {
    Write-Host "  [!] Game account '$user' already exists."
    exit 1
}
if ($existingBnet) {
    Write-Host "  [!] Battle.net account '$email' already exists."
    exit 1
}

Invoke-AuthSql @"
START TRANSACTION;
INSERT INTO battlenet_accounts (email, sha_pass_hash) VALUES ('$sqlEmail', '$sqlBnetHash');
SET @bnet_id = LAST_INSERT_ID();
INSERT INTO account (username, sha_pass_hash, email, reg_mail, battlenet_account, battlenet_index)
  VALUES ('$sqlUser', '$sqlGameHash', '$sqlEmail', '$sqlEmail', @bnet_id, 1);
COMMIT;
"@ "create account" | Out-Null

$verifyBnet = Invoke-AuthSql "SELECT id FROM battlenet_accounts WHERE email = '$sqlEmail' LIMIT 1;" "verify bnet account" -Raw
$verifyGame = Invoke-AuthSql "SELECT id FROM account WHERE username = '$sqlUser' LIMIT 1;" "verify game account" -Raw
if (-not $verifyBnet -or -not $verifyGame) {
    Write-Host "  [!] Account was not saved to the database. Check MySQL credentials in tools\mysql.cnf"
    exit 1
}

if ($GmLevel -gt 0) {
    Invoke-AuthSql @"
INSERT IGNORE INTO account_access (id, gmlevel, RealmID)
  SELECT id, $GmLevel, -1 FROM account WHERE username = '$sqlUser';
"@ "set gm level" | Out-Null
}

Write-Host "  [OK] Account created."
Write-Host "       Battle.net login : $email"
Write-Host "       Password         : (what you entered)"
Write-Host "       Game account     : $user"
Write-Host ""
Write-Host "  Log in with the Battle.net email and password at the client login screen."
Write-Host "  Portal must be 127.0.0.1:1119 (run setup.bat or patch_client.ps1 if needed)."

exit 0
