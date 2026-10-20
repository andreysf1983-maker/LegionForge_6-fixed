# Verify Windows script encodings and line endings before running setup.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$bad = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $Root -Recurse -File -Include *.bat,*.cmd | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bad.Add("BOM is not allowed: $($_.FullName)")
    }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Contains("`n") -and -not $text.Contains("`r`n")) {
        $bad.Add("LF-only line endings: $($_.FullName)")
    }
    if ([regex]::IsMatch($text, "(?<!`r)`n")) {
        $bad.Add("Bare LF found: $($_.FullName)")
    }
}
if ($bad.Count) {
    $bad | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'OK: every .bat/.cmd is UTF-8 without BOM and uses CRLF.'
exit 0
