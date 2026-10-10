# Stop hook (blocking): refuse to end a turn when addon/pipeline code changed but the
# doc spine (SPRINTS.md / FEATURES.md / CHANGELOG.md) did not. mtime-based because this
# repo may not be a git checkout. Guarded by stop_hook_active so it nags at most once.
$stdin = [Console]::In.ReadToEnd()
try { $payload = $stdin | ConvertFrom-Json } catch { exit 0 }
if ($null -ne $payload -and $payload.stop_hook_active) { exit 0 }

$root = Split-Path (Split-Path $PSScriptRoot)
$codeRoots = @((Join-Path $root "Foresight"), (Join-Path $root "pipeline"))
$spine = @("SPRINTS.md", "FEATURES.md", "CHANGELOG.md") | ForEach-Object { Join-Path $root $_ }

$codeNewest = Get-Date "2000-01-01"
foreach ($cr in $codeRoots) {
    if (Test-Path $cr) {
        $files = Get-ChildItem $cr -Recurse -File | Where-Object { $_.FullName -notmatch '\\cache\\' }
        foreach ($f in $files) { if ($f.LastWriteTime -gt $codeNewest) { $codeNewest = $f.LastWriteTime } }
    }
}
$spineNewest = Get-Date "2000-01-01"
foreach ($s in $spine) {
    if (Test-Path $s) { $t = (Get-Item $s).LastWriteTime; if ($t -gt $spineNewest) { $spineNewest = $t } }
}

# 90s grace: spine edits usually land just before the turn ends.
if ($codeNewest -gt $spineNewest.AddSeconds(90)) {
    [Console]::Error.WriteLine("Record loop incomplete: code under Foresight/ or pipeline/ is newer than the doc spine. Sync SPRINTS.md status, FEATURES.md inventory, and CHANGELOG.md (with *Features:* IDs) before ending the turn - or state why no spine change is needed.")
    exit 2
}
exit 0
