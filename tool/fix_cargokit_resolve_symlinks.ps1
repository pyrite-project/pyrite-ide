<#
.SYNOPSIS
    Patches cargokit's resolve_symlinks.ps1 inside the pub cache.

.DESCRIPTION
    cargokit (shipped inside super_native_extensions / code_forge /
    irondash_engine_context) walks a path one segment at a time and calls
    `Get-Item` on each prefix. On Windows the pub cache lives under
    `%LOCALAPPDATA%\Pub\Cache`, and `AppData` carries the `Hidden` attribute.
    Windows PowerShell 5.1 (what CMake invokes as `powershell`) skips hidden
    items unless `-Force` is passed, so it throws:

        Get-Item : Could not find item C:\Users\<you>\AppData.

    The message ends at `AppData` because that is literally the prefix built so
    far - it is not a path truncation or an encoding problem.

    Adding `-Force` makes the lookup succeed. The error was cosmetic: the same
    script reads `$item.LinkTarget`, a property that does not exist in
    PowerShell 5.1 (the correct name is `Target`), so the symlink-resolution
    loop was already a no-op on Windows and the resolved path is unchanged.

.PARAMETER PubCacheRoot
    Optional override for the pub cache root. Defaults to the `PUB_CACHE`
    environment variable, falling back to `%LOCALAPPDATA%\Pub\Cache`.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tool\fix_cargokit_resolve_symlinks.ps1
#>
[CmdletBinding()]
param(
    [string] $PubCacheRoot
)

$ErrorActionPreference = 'Stop'

if (-not $PubCacheRoot) {
    $PubCacheRoot = if ($env:PUB_CACHE) { $env:PUB_CACHE }
                    else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
}

if (-not (Test-Path -LiteralPath $PubCacheRoot)) {
    Write-Host "Pub cache not found: $PubCacheRoot" -ForegroundColor Yellow
    exit 0
}

$scriptName = 'resolve_symlinks.ps1'
$brokenLine = '$item = Get-Item $realPath'
$fixedLine  = '$item = Get-Item $realPath -Force'

$copies = Get-ChildItem -LiteralPath $PubCacheRoot -Recurse -Force `
    -Filter $scriptName -File -ErrorAction SilentlyContinue

if (-not $copies) {
    Write-Host "No cargokit copies found under $PubCacheRoot" -ForegroundColor Yellow
    exit 0
}

$patched = 0
$alreadyOk = 0

foreach ($copy in $copies) {
    $text = [System.IO.File]::ReadAllText($copy.FullName)

    if ($text.Contains($fixedLine)) {
        Write-Host "  ok       $($copy.FullName)"
        $alreadyOk++
        continue
    }

    if (-not $text.Contains($brokenLine)) {
        Write-Host "  skipped  $($copy.FullName)  (unrecognised layout)" -ForegroundColor Yellow
        continue
    }

    [System.IO.File]::WriteAllText(
        $copy.FullName, $text.Replace($brokenLine, $fixedLine), [System.Text.Encoding]::UTF8)

    Write-Host "  patched  $($copy.FullName)" -ForegroundColor Green
    $patched++
}

Write-Host ''
Write-Host "cargokit resolve_symlinks: $patched patched, $alreadyOk already fixed, $($copies.Count) total."

if ($patched -gt 0) {
    Write-Host 'Re-run "flutter clean" if the error reappears after a rebuild.' -ForegroundColor DarkGray
}
