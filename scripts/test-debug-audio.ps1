[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Manifest,
    [Parameter(Mandatory = $true)][switch]$LiveServices
)
$ErrorActionPreference = 'Stop'
if (-not $LiveServices) { throw 'Use -LiveServices only for an authorized real-service acceptance run.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$rows = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($slot in @('introduction', 'answer', 'extension')) {
    if (-not $rows.$slot -or @($rows.$slot).Count -lt 1) { throw "Missing audio slot: $slot" }
}
$outputPath = Join-Path $projectRoot ('.codex-diagnostics/live-debug/' + [guid]::NewGuid().ToString())
$manifest64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifestPath))
$output64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($outputPath))
Write-Host 'Live acceptance uses the configured STT/TTS/LLM/image services and may consume quota.'
Push-Location -LiteralPath $projectRoot
try {
    & flutter test integration_test/debug_audio_flow_test.dart -d windows --reporter expanded `
        '--dart-define=REMINICARE_LIVE_SERVICES=true' `
        "--dart-define=REMINICARE_AUDIO_MANIFEST64=$manifest64" `
        "--dart-define=REMINICARE_TEST_OUTPUT64=$output64"
    $result = $LASTEXITCODE
    $reportPath = Join-Path $outputPath 'acceptance-report.json'
    if (Test-Path -LiteralPath $reportPath) {
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $report | Add-Member -NotePropertyName flowStatus -NotePropertyValue $report.status -Force
        $report | Add-Member -NotePropertyName cliExitCode -NotePropertyValue $result -Force
        if ($result -ne 0) { $report.status = 'failed' }
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    }
    Write-Host "Isolated acceptance output: $outputPath"
    if ($result -ne 0) { throw 'Live acceptance failed; no automatic retry was started.' }
} finally {
    Pop-Location
}
