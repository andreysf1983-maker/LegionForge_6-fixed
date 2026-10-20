<#
.SYNOPSIS
    LEGIONFORGE - repair line endings / encodings / Mark of the Web.
.DESCRIPTION
    * .bat / .cmd  -> CRLF line endings, UTF-8 WITHOUT BOM.
      cmd.exe mis-parses LF-only batch files: lines are cut at random places and
      you get "'...' is not recognized as an internal or external command".
      A BOM would break the first line ("@echo off").
    * .ps1         -> CRLF + UTF-8 WITH BOM (Windows PowerShell 5.1 reads BOM-less
      files as ANSI and corrupts non-ASCII strings).
    * .conf/.sql untouched.
    * Unblock-File on everything (Zone.Identifier from ZIP downloads).
    ASCII-only on purpose.
#>
param([string]$Root = '', [switch]$Quiet)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$fixed = 0
$skipDirs = '\\(tools|build|core|\.git)\\'

function Convert-File([IO.FileInfo]$File, [bool]$WithBom) {
    $bytes = [IO.File]::ReadAllBytes($File.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = 0
    if ($hasBom) { $offset = 3 }
    $text = [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    $normalized = ($text -replace "`r`n", "`n") -replace "`r", "`n"
    $normalized = $normalized -replace "`n", "`r`n"
    $nonAscii = $false
    foreach ($b in $bytes) { if ($b -gt 0x7F) { $nonAscii = $true; break } }
    $wantBom = $WithBom -and $nonAscii
    if ($normalized -ceq $text -and ($hasBom -eq $wantBom)) { return $false }
    $enc = $utf8NoBom
    if ($wantBom) { $enc = $utf8Bom }
    [IO.File]::WriteAllText($File.FullName, $normalized, $enc)
    return $true
}

Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {}
    $rel = $_.FullName.Substring($Root.Length)
    if ($rel -match $skipDirs) { return }
    $ext = $_.Extension.ToLowerInvariant()
    $changed = $false
    if ($ext -eq '.bat' -or $ext -eq '.cmd') { $changed = Convert-File $_ $false }
    elseif ($ext -eq '.ps1') { $changed = Convert-File $_ $true }
    if ($changed) {
        $fixed++
        if (-not $Quiet) { Write-Host "  [fix] $rel" }
    }
}
if ($fixed -gt 0) { Write-Host "  [OK] Repaired line endings/encoding of $fixed file(s)." }
elseif (-not $Quiet) { Write-Host '  [OK] All scripts already have correct line endings.' }
exit 0
