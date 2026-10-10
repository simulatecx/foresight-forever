# UserPromptSubmit hook (advisory): on feature-build intent, remind to check the
# backlog first, then run feature-triage. Never blocks.
$stdin = [Console]::In.ReadToEnd()
try { $payload = $stdin | ConvertFrom-Json } catch { exit 0 }
$prompt = ""
if ($null -ne $payload -and $null -ne $payload.prompt) { $prompt = [string]$payload.prompt }
if ($prompt -match '(?i)\b(build|implement|add|create|ship)\b.*\b(feature|module|panel|advisor|hud|probe|pipeline|command)\b|new sprint') {
    Write-Output "Reminder (engineering-governance): check the SPRINTS.md backlog for an existing groomed story first; otherwise run the repo feature-triage skill (duplication gate vs FEATURES.md) before building."
}
exit 0
