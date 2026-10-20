[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$CnfPath = '',
    [string]$MysqlExe = ''
)

# LEGIONFORGE 7.3.5 - приводит схему auth в соответствие с ядром.
#
# ЗАЧЕМ. Ядро (core/src/server/database/Database/Implementation/LoginDatabase.cpp) создаёт и читает
# account.reg_mail, а в некоторых дампах auth.sql этой колонки нет:
#   mysql.exe : ERROR 1054 (42S22) ... Unknown column 'reg_mail' in 'field list'
# Скрипт идемпотентен: читает information_schema и добавляет только отсутствующие колонки.
# Уже существующие колонки и данные не трогаются.

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $CnfPath) { $CnfPath = Join-Path $Root 'tools\mysql.cnf' }
if (-not $MysqlExe) {
    $MysqlExe = & (Join-Path $PSScriptRoot 'find_mysql.ps1') -Port 3306 | Select-Object -First 1
    if ($MysqlExe) { $MysqlExe = "$MysqlExe".Trim() }
}
if (-not $MysqlExe -or -not (Test-Path -LiteralPath $MysqlExe)) {
    Write-Host '  [!] mysql.exe не найден.'
    exit 1
}
if (-not (Test-Path -LiteralPath $CnfPath)) {
    Write-Host "  [!] Не найден файл подключения к MySQL: $CnfPath"
    exit 1
}

function Invoke-AuthQuery([string]$Sql) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = @(& $MysqlExe "--defaults-extra-file=$CnfPath" '-N' '-B' 'auth' '-e' $Sql 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prev }
    if ($code -ne 0) {
        foreach ($line in $out) { Write-Host "  [!] $line" }
        Write-Host "  [!] Ошибка MySQL (код $code)."
        exit 1
    }
    # Предупреждения mysql (например, про пароль) отбрасываем - остаются только строки результата.
    return @($out | Where-Object { $_ -notmatch '^(mysql|mysqld):? ' -and $_ -notmatch '^ERROR' })
}

# Колонки, которые читает и пишет ядро. Тип - как в базовой схеме LEGIONFORGE (auth_database.sql).
# Порядок важен: AFTER ссылается только на колонку, уже существующую или добавленную выше.
$specs = @(
    @{ Table = 'account'; Column = 'email';             Definition = "varchar(255) NOT NULL DEFAULT ''";           After = 'sha_pass_hash' },
    @{ Table = 'account'; Column = 'reg_mail';          Definition = "varchar(255) NOT NULL DEFAULT ''";           After = 'email' },
    @{ Table = 'account'; Column = 'joindate';          Definition = 'timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP'; After = '' },
    @{ Table = 'account'; Column = 'last_ip';           Definition = "varchar(15) NOT NULL DEFAULT '127.0.0.1'";   After = '' },
    @{ Table = 'account'; Column = 'last_attempt_ip';   Definition = "varchar(15) NOT NULL DEFAULT '127.0.0.1'";   After = '' },
    @{ Table = 'account'; Column = 'failed_logins';     Definition = 'int unsigned NOT NULL DEFAULT 0';            After = '' },
    @{ Table = 'account'; Column = 'locked';            Definition = 'tinyint unsigned NOT NULL DEFAULT 0';        After = '' },
    @{ Table = 'account'; Column = 'lock_country';      Definition = "varchar(2) NOT NULL DEFAULT '00'";           After = '' },
    @{ Table = 'account'; Column = 'last_login';        Definition = 'timestamp NULL DEFAULT NULL';                After = '' },
    @{ Table = 'account'; Column = 'online';            Definition = 'tinyint unsigned NOT NULL DEFAULT 0';        After = '' },
    @{ Table = 'account'; Column = 'expansion';         Definition = 'tinyint unsigned NOT NULL DEFAULT 6';        After = '' },
    @{ Table = 'account'; Column = 'mutetime';          Definition = 'bigint NOT NULL DEFAULT 0';                  After = '' },
    @{ Table = 'account'; Column = 'mutereason';        Definition = "varchar(255) NOT NULL DEFAULT ''";           After = '' },
    @{ Table = 'account'; Column = 'muteby';            Definition = "varchar(50) NOT NULL DEFAULT ''";            After = '' },
    @{ Table = 'account'; Column = 'locale';            Definition = 'tinyint unsigned NOT NULL DEFAULT 0';        After = '' },
    @{ Table = 'account'; Column = 'os';                Definition = "varchar(4) NOT NULL DEFAULT ''";             After = '' },
    @{ Table = 'account'; Column = 'recruiter';         Definition = 'int unsigned NOT NULL DEFAULT 0';            After = '' },
    @{ Table = 'account'; Column = 'battlenet_account'; Definition = 'int unsigned NULL DEFAULT NULL';             After = '' },
    @{ Table = 'account'; Column = 'battlenet_index';   Definition = 'tinyint unsigned NULL DEFAULT NULL';         After = '' },

    @{ Table = 'battlenet_accounts'; Column = 'email';              Definition = "varchar(320) NOT NULL DEFAULT ''"; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'sha_pass_hash';      Definition = "varchar(64) NOT NULL DEFAULT ''";  After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'joindate';           Definition = 'timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP'; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'last_ip';            Definition = "varchar(15) NOT NULL DEFAULT '127.0.0.1'"; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'failed_logins';      Definition = 'int unsigned NOT NULL DEFAULT 0';  After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'locked';             Definition = 'tinyint unsigned NOT NULL DEFAULT 0'; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'lock_country';       Definition = "varchar(2) NOT NULL DEFAULT '00'"; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'last_login';         Definition = 'timestamp NULL DEFAULT NULL';      After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'online';             Definition = 'tinyint unsigned NOT NULL DEFAULT 0'; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'locale';             Definition = 'tinyint unsigned NOT NULL DEFAULT 0'; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'os';                 Definition = "varchar(4) NOT NULL DEFAULT ''";   After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'LastCharacterUndelete'; Definition = 'int unsigned NOT NULL DEFAULT 0'; After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'LoginTicket';        Definition = 'varchar(64) NULL DEFAULT NULL';    After = '' },
    @{ Table = 'battlenet_accounts'; Column = 'LoginTicketExpiry';  Definition = 'int unsigned NULL DEFAULT NULL';   After = '' }
)

$identity = @{
    'account'          = @('id', 'username', 'sha_pass_hash')
    'battlenet_accounts' = @('id')
}

$problems = 0
$added = 0
$tables = @('account', 'battlenet_accounts')
$existingByTable = @{}

foreach ($table in $tables) {
    $cols = @(Invoke-AuthQuery "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'auth' AND TABLE_NAME = '$table';")
    if ($cols.Count -eq 0) {
        Write-Host "  [!] В базе auth нет таблицы $table. Сначала импортируйте sql\base\auth.sql (setup.bat)."
        exit 1
    }
    foreach ($id in $identity[$table]) {
        if ($cols -notcontains $id) {
            Write-Host "  [!] В таблице auth.$table нет обязательной колонки $id. Дамп auth.sql повреждён или не от LegionForge 7.3.5."
            $problems++
        }
    }
    $existingByTable[$table] = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $cols) { $existingByTable[$table].Add($c) }
}

foreach ($spec in $specs) {
    $table = $spec.Table
    $existing = $existingByTable[$table]
    if ($existing -contains $spec.Column) { continue }

    $after = ''
    if ($spec.After -and ($existing -contains $spec.After)) {
        $after = " AFTER ``$($spec.After)``"
    }
    $sql = "ALTER TABLE ``$table`` ADD COLUMN ``$($spec.Column)`` $($spec.Definition)$after;"
    Write-Host ("  - auth.{0}: добавляю колонку {1}" -f $table, $spec.Column)
    $null = Invoke-AuthQuery $sql
    $existing.Add($spec.Column)
    $added++
}

# Проверка: после исправлений все нужные колонки должны существовать.
foreach ($spec in $specs) {
    if ($existingByTable[$spec.Table] -notcontains $spec.Column) {
        Write-Host ("  [!] Колонка {0}.{1} всё ещё отсутствует." -f $spec.Table, $spec.Column)
        $problems++
    }
}

if ($problems -gt 0) {
    Write-Host "  [!] Схема auth не соответствует ядру ($problems проблем(ы))."
    exit 1
}

if ($added -gt 0) {
    Write-Host ("  [OK] Схема auth дополнена: добавлено колонок {0}." -f $added)
} else {
    Write-Host '  [OK] Схема auth соответствует ядру (account, battlenet_accounts).'
}
exit 0
