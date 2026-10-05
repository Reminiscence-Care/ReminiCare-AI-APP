param([switch]$CopyToClipboard)
$ErrorActionPreference = 'Stop'
$taskWorkerRoot = Split-Path $PSScriptRoot -Parent
$taskTokenPath = Join-Path $taskWorkerRoot '.app-token.xml'
if (Test-Path -LiteralPath $taskTokenPath) {
  $taskSecureToken = Import-Clixml -LiteralPath $taskTokenPath
} else {
  $taskBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
  $taskToken = [Convert]::ToHexString($taskBytes).ToLowerInvariant()
  $taskSecureToken = ConvertTo-SecureString $taskToken -AsPlainText -Force
  $taskSecureToken | Export-Clixml -LiteralPath $taskTokenPath
}
$taskToken = [System.Net.NetworkCredential]::new('', $taskSecureToken).Password
if ($CopyToClipboard) {
  Set-Clipboard -Value $taskToken
  Write-Output 'App Token copied to clipboard. Paste it into ReminiCare settings.'
  exit 0
}
Push-Location $taskWorkerRoot
try {
  $taskToken | & "$taskWorkerRoot/node_modules/.bin/wrangler.cmd" secret put APP_API_TOKEN
  if ($LASTEXITCODE -ne 0) { throw 'Worker secret upload failed.' }
  Write-Output 'App Token configured. Local copy is encrypted for this Windows user and excluded from Git.'
} finally {
  Pop-Location
  $taskToken = $null
}
