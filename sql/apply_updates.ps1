<#
.SYNOPSIS
    LEGIONFORGE 7.3.5.26124 - применение sql\updates (один раз на файл).
.DESCRIPTION
    В ядре LegionCore нет встроенного DBUpdater (опции Updates.* в worldserver.conf
    ни на что не влияют), поэтому файлы sql\updates\<db>\*.sql применяются здесь.
    Каждый файл применяется ровно один раз: журнал хранится в таблице
    auth.legionforge_sql_history (имя базы, файл, SHA-256). Изменённый файл
    (другой SHA-256) применяется повторно.
    Ошибка отдельного файла - предупреждение (SOFT), установка не прерывается:
    часть upstream-обновлений уже содержится в дампе и может конфликтовать.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File sql\apply_updates.ps1 -Root D:\LegionForge -MysqlExe ... -CnfPath ...
#>
param([string]$Root = "", [string]$CnfPath = "", [string]$MysqlExe = "")
$ErrorActionPreference = "Continue"
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $CnfPath) { $CnfPath = Join-Path $Root "tools\mysql.cnf" }
if (-not $MysqlExe) { $MysqlExe = Join-Path $Root "tools\mysql\server\bin\mysql.exe" }
if (-not (Test-Path -LiteralPath $MysqlExe)) { Write-Host "  [ОШИБКА] mysql.exe не найден: $MysqlExe"; exit 1 }
if (-not (Test-Path -LiteralPath $CnfPath)) { Write-Host "  [ОШИБКА] Нет файла подключения: $CnfPath"; exit 1 }

function Invoke-Sql([string]$Db, [byte[]]$Bytes) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $MysqlExe
    $dbArg = ""
    if ($Db) { $dbArg = $Db }
    $psi.Arguments = ('--defaults-extra-file="{0}" --default-character-set=utf8mb4 --max_allowed_packet=512M --batch --skip-column-names {1}' -f $CnfPath, $dbArg)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    try { $proc.StandardInput.BaseStream.Write($Bytes, 0, $Bytes.Length) } catch { }
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    return [pscustomobject]@{ ExitCode = $proc.ExitCode; Out = $outTask.Result.Trim(); Err = $errTask.Result.Trim() }
}
function Invoke-SqlText([string]$Db, [string]$Text) {
    return Invoke-Sql $Db ([Text.Encoding]::UTF8.GetBytes($Text))
}

$init = Invoke-SqlText "auth" "CREATE TABLE IF NOT EXISTS legionforge_sql_history (db VARCHAR(32) NOT NULL, file VARCHAR(255) NOT NULL, sha256 CHAR(64) NOT NULL, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, ok TINYINT NOT NULL DEFAULT 1, PRIMARY KEY (db, file)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
if ($init.ExitCode -ne 0) { Write-Host "  [ОШИБКА] Не удалось создать журнал обновлений: $($init.Err)"; exit 1 }

$known = @{}
$hist = Invoke-SqlText "auth" "SELECT CONCAT(db, '|', file, '|', sha256) FROM legionforge_sql_history;"
foreach ($line in ($hist.Out -split "`r?`n")) { if ($line) { $known[$line] = $true } }

# папка в sql\updates -> база данных
$map = @(
    @{ Dir = "auth";         Db = "auth" },
    @{ Dir = "characters";   Db = "characters" },
    @{ Dir = "world";        Db = "world" },
    @{ Dir = "custom\world"; Db = "world" },
    @{ Dir = "hotfixes";     Db = "hotfixes" },
    @{ Dir = "hotfix";       Db = "hotfixes" }
)
$applied = 0; $skipped = 0; $soft = 0
foreach ($m in $map) {
    $dir = Join-Path $Root ("sql\updates\" + $m.Dir)
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $files = Get-ChildItem -LiteralPath $dir -Filter *.sql -File | Sort-Object Name
    foreach ($f in $files) {
        $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
        # MySQL string literal: escape backslash first, then the single quote.
        $rel = (($m.Dir + "\" + $f.Name).Replace('\', '\\')).Replace("'", "''")
        if ($known.ContainsKey("$($m.Db)|$($m.Dir)\$($f.Name)|$sha")) { $skipped++; continue }
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $r = Invoke-Sql $m.Db $bytes
        $ok = 1
        if ($r.ExitCode -ne 0) {
            $ok = 0; $soft++
            $msg = ($r.Err -split "`r?`n" | Where-Object { $_ -and $_ -notmatch 'Using a password' } | Select-Object -First 2) -join ' '
            Write-Host "  [!] SOFT $($m.Db) <- $($f.Name): $msg"
        } else {
            $applied++
            Write-Host "  [OK] $($m.Db) <- $($f.Name)"
        }
        [void](Invoke-SqlText "auth" ("REPLACE INTO legionforge_sql_history (db, file, sha256, ok) VALUES ('{0}', '{1}', '{2}', {3});" -f $m.Db, $rel, $sha, $ok))
    }
}
Write-Host ("  [OK] sql\updates: применено {0}, уже было {1}, с предупреждениями {2}." -f $applied, $skipped, $soft)
exit 0
