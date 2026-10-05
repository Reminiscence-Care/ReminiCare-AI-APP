param([string]$WorkerUrl = 'https://reminicare-image-api.hding49.workers.dev')
$ErrorActionPreference = 'Stop'
$taskWorkerRoot = Split-Path $PSScriptRoot -Parent
$taskTokenPath = Join-Path $taskWorkerRoot '.app-token.xml'
$taskSecureToken = Import-Clixml -LiteralPath $taskTokenPath
$taskToken = [System.Net.NetworkCredential]::new('', $taskSecureToken).Password
$taskHeaders = @{ Authorization = "Bearer $taskToken" }
$taskOutput = Join-Path $taskWorkerRoot 'smoke-output'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskScenes = [ordered]@{
  'general-store' = 'A family buying loose candies from glass jars in a small Taiwanese corner grocery store in 1965, wooden shelves, traditional everyday Taiwanese clothing, warm faded documentary film, no modern objects, landscape composition.'
  'railway' = 'A Taiwanese family waiting beside an old diesel passenger train at a small Taiwan railway station in 1970, period clothing, authentic Taiwan station architecture, warm faded documentary film, no modern objects, landscape composition.'
  'opera' = 'Taiwanese elders watching traditional Taiwanese opera on a simple outdoor stage beside a village temple in 1968, authentic opera costumes, evening lantern lighting, candid documentary film photograph, no modern objects, landscape composition.'
  'rice-harvest' = 'A Taiwanese farming family harvesting rice by hand in a rural Taiwan paddy field in 1965, straw hats, traditional work clothing, water buffalo in background, warm faded documentary film, no modern buildings, landscape composition.'
}
$taskLastImage = $null
foreach ($taskScene in $taskScenes.GetEnumerator()) {
  $taskWatch = [System.Diagnostics.Stopwatch]::StartNew()
  $taskResponse = Invoke-RestMethod -Uri "$WorkerUrl/v1/images/generations" -Method Post -Headers $taskHeaders -ContentType 'application/json' -Body (@{ prompt = $taskScene.Value; width = 1024; height = 640 } | ConvertTo-Json) -TimeoutSec 180
  $taskBytes = [Convert]::FromBase64String($taskResponse.data[0].b64_json)
  $taskLastImage = Join-Path $taskOutput "$($taskScene.Key).jpg"
  [System.IO.File]::WriteAllBytes($taskLastImage, $taskBytes)
  Write-Output "$($taskScene.Key): $($taskWatch.ElapsedMilliseconds) ms, $($taskBytes.Length) bytes"
}
Add-Type -AssemblyName System.Drawing
foreach ($taskCorrection in @('Change the straw hats to dark cloth head coverings. Preserve the same people, faces, composition, rice field, camera angle and 1960s Taiwanese documentary style.', 'Make the sky lightly overcast. Preserve the same people, faces, head coverings, camera angle, rice field and historical Taiwanese setting.')) {
  $taskSource = [System.Drawing.Image]::FromFile($taskLastImage)
  $taskRatio = [Math]::Min(1.0, 504.0 / [Math]::Max($taskSource.Width, $taskSource.Height))
  $taskReference = [System.Drawing.Bitmap]::new([int]($taskSource.Width * $taskRatio), [int]($taskSource.Height * $taskRatio))
  $taskGraphics = [System.Drawing.Graphics]::FromImage($taskReference)
  $taskGraphics.DrawImage($taskSource, 0, 0, $taskReference.Width, $taskReference.Height)
  $taskStream = [System.IO.MemoryStream]::new()
  $taskReference.Save($taskStream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
  $taskGraphics.Dispose(); $taskSource.Dispose(); $taskReference.Dispose()
  $taskWatch = [System.Diagnostics.Stopwatch]::StartNew()
  $taskResponse = Invoke-RestMethod -Uri "$WorkerUrl/v1/images/edits" -Method Post -Headers $taskHeaders -ContentType 'application/json' -Body (@{ prompt = $taskCorrection; imageBase64 = [Convert]::ToBase64String($taskStream.ToArray()); imageMimeType = 'image/jpeg'; width = 1024; height = 640 } | ConvertTo-Json) -TimeoutSec 180
  $taskStream.Dispose()
  $taskLastImage = Join-Path $taskOutput "edit-$([DateTime]::UtcNow.Ticks).jpg"
  $taskBytes = [Convert]::FromBase64String($taskResponse.data[0].b64_json)
  [System.IO.File]::WriteAllBytes($taskLastImage, $taskBytes)
  Write-Output "edit: $($taskWatch.ElapsedMilliseconds) ms, $($taskBytes.Length) bytes"
}
$taskToken = $null
