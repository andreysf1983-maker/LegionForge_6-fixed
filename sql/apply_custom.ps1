param([string]$Root = "", [string]$CnfPath = "", [string]$MysqlExe = "")
$ErrorActionPreference = "Continue"
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $CnfPath) { $CnfPath = Join-Path $Root "tools\mysql.cnf" }
$sqlDir = Join-Path $Root "sql\custom"

# =====================================================================================
#  LEGIONFORGE 7.3.5.26124 - кастомные патчи.
#
#  АУДИТ 2026: прежняя версия скрипта применяла ОДИН И ТОТ ЖЕ файл по 2-3 раза
#  (world + hotfixes + characters). Все эти файлы содержат внутри себя инструкции
#  `USE <база>`, поэтому они сами переключают базу и ДОЛЖНЫ выполняться РОВНО ОДИН РАЗ.
#  Повторный запуск приводил к бесконечным "SOFT-FAIL" в логе установки и к двойной
#  вставке данных. Ниже каждый файл выполняется один раз; колонка Db - это база,
#  с которой начинается соединение (для файлов без собственного USE).
#
#  Порядок важен:
#    10  - имя реалма (auth)
#    105 - клиентские расы: создаёт playercreateinfo_spell / race_unlock_requirement
#    48/49/111 - союзные расы и чистка несуществующих расовых слотов
#    40  - предметы (hotfixes + world)
#    43/44/45 - токены, лимиты улучшений, древнее знание (вендоры Даларана)
#    41/42 - мини-боссы и их лут (ссылаются на предметы из 40)
#    106/107 - свитки форм и демонические свитки
#    110 - финальная чистка логов worldserver
# =====================================================================================
$patches = @(
    @{ Db = "auth";     File = "10_legionforge_realm.sql" },
    @{ Db = "world";    File = "105_legionforge_client_races_real_ids.sql" },
    @{ Db = "world";    File = "48_legion_allied_races.sql" },
    @{ Db = "world";    File = "49_legion_allied_races_hotbar.sql" },
    @{ Db = "world";    File = "111_remove_wrong_race_slots.sql" },
    @{ Db = "world";    File = "40_legionforge_items.sql" },
    @{ Db = "world";    File = "43_legionforge_upgrade_tokens.sql" },
    @{ Db = "world";    File = "44_legionforge_upgrade_limits.sql" },
    @{ Db = "world";    File = "45_legionforge_ancient_knowledge.sql" },
    @{ Db = "world";    File = "41_legionforge_minibosses.sql" },
    @{ Db = "world";    File = "42_legionforge_miniboss_loot.sql" },
    @{ Db = "world";    File = "106_legionforge_form_scrolls.sql" },
    @{ Db = "world";    File = "107_legionforge_demon_scrolls_and_form_defaults.sql" },
    @{ Db = "world";    File = "110_legionforge_log_cleanup_26124.sql" },
    @{ Db = "world";    File = "112_legionforge_custom_client_content.sql" }
)

$fail = 0
$done = 0
foreach ($p in $patches) {
    $path = Join-Path $sqlDir $p.File
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "  [!] Нет файла $path"
        $fail++
        continue
    }
    Write-Host "  [*] $($p.File) -> $($p.Db)"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $MysqlExe
    $psi.Arguments = ('--defaults-extra-file="{0}" --default-character-set=utf8mb4 --max_allowed_packet=512M {1}' -f $CnfPath, $p.Db)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $bytes = [IO.File]::ReadAllBytes($path)
    try { $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length) } catch { }
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        Write-Host "  [ОШИБКА] $($p.File):"
        Write-Host ("      " + ($stderr -replace "`r?`n", "`r`n      "))
        $fail++
    } else {
        $done++
        if ($stdout -and $stdout.Trim().Length -gt 0) {
            # контрольные SELECT'ы патчей - выводим компактно
            foreach ($line in ($stdout -split "`r?`n")) {
                if ($line.Trim().Length -gt 0) { Write-Host ("      " + $line) }
            }
        }
    }
}

if ($fail -gt 0) {
    Write-Host "  [ОШИБКА] Патчей с ошибками: $fail (успешно: $done)"
    exit 1
}
Write-Host "  [OK] Все кастомные патчи применены ($done шт.)."
exit 0
