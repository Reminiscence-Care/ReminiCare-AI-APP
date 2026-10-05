$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskDir = Join-Path $taskRoot 'assets/topics'
New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
$taskEntries = @(
 @('grocery','柑仔店','File:Grocery store in Taiwan 1950s.jpg','以前去柑仔店最喜歡買什麼？','還記得店主或店裡的擺設嗎？',$false),
 @('railway','老火車','File:Alishan Taiwan Alishan-Forest-Railway-03b.jpg','以前看過哪些老火車？','那時候都搭火車去哪裡？',$true),
 @('opera','歌仔戲','File:Taiwanese Ke-Tse Opera at Mazu temple.jpg','以前在哪裡看歌仔戲？','最喜歡哪個角色或哪齣戲？',$true),
 @('harvest','割稻','File:Rice harvesting in Tamsui 1970.jpg','以前割稻時大家怎麼分工？','忙完後都吃什麼？',$false),
 @('market','菜市場','File:Taitung City Kaifeng Market01.jpg','以前去菜市場最常買什麼？','還記得熟悉的攤販嗎？',$true),
 @('school','校外教學','File:School children on graduation trip at the Taiwan Provincial Museum.jpg','以前上學有去過校外教學嗎？','還記得一起出遊的同學嗎？',$false),
 @('chess','下棋','File:Students of the Taihoku High School playing chess.jpg','以前有和朋友一起下棋嗎？','通常在哪裡下棋？',$false),
 @('newyear','辦年貨','File:2009-01-21 Taipei Lunar New Year Festival.jpg','以前過年前都去哪裡辦年貨？','家裡會準備哪些好吃的？',$true),
 @('dragonboat','龍舟','File:Dragon Boat Race Team Rowers aboarding Boat before Race 20170530fb.jpg','以前端午節有去看龍舟嗎？','當天還會做哪些事情？',$true),
 @('cake','鳳梨酥','File:Taiwanese Pineapple Cake 001.jpg','以前會在什麼時候吃鳳梨酥？','還記得喜歡的糕餅店嗎？',$true),
 @('street','老街','File:Fencihu Old Town 01.jpg','以前住的街上有哪些店？','有沒有最熟悉的鄰居？',$true),
 @('weaving','織布','File:Traditional Weaving Machine of the Aborigines in Taiwan.jpg','以前看過或學過織布嗎？','是誰教您的？',$true)
)
$taskCatalog = @()
$taskTitles = ($taskEntries | ForEach-Object { $_[2] }) -join '|'
$taskUri = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2&titles=' + [uri]::EscapeDataString($taskTitles) + '&prop=info%7Cimageinfo&inprop=url&iiprop=url%7Cextmetadata&iiurlwidth=800'
$taskPages = (Invoke-RestMethod $taskUri).query.pages
foreach ($taskEntry in $taskEntries) {
 $taskPage = $taskPages | Where-Object title -eq $taskEntry[2] | Select-Object -First 1
 $taskInfo = $taskPage.imageinfo[0]
 $taskMeta = $taskInfo.extmetadata
 $taskLicense = $taskMeta.LicenseShortName.value
 if ($taskLicense -notmatch '^(CC BY|CC0|Public domain)') { throw "Unapproved license: $taskLicense" }
 $taskUrl = $taskInfo.thumburl.Split('?')[0]
 $taskPath = Join-Path $taskDir "$($taskEntry[0]).jpg"
 if (-not (Test-Path -LiteralPath $taskPath)) { Invoke-WebRequest $taskUrl -OutFile $taskPath }
 $taskCreator = [System.Net.WebUtility]::HtmlDecode(($taskMeta.Artist.value -replace '<[^>]+>',''))
 $taskCatalog += [ordered]@{
  topicId=$taskEntry[0]; title=$taskEntry[1]; question=$taskEntry[3]; followUpQuestion=$taskEntry[4]
  imagePrompt="Historical Taiwanese scene involving $($taskEntry[1]), authentic people and everyday objects"
  assetPath="assets/topics/$($taskEntry[0]).jpg"; illustrative=$taskEntry[5]
  attribution=@{title=$taskEntry[2];creator=$taskCreator;source='Wikimedia Commons';license=$taskLicense;originalUrl=$taskPage.fullurl;licenseUrl=($taskMeta.LicenseUrl.value -replace '^http:','https:')}
 }
 Write-Output "$($taskEntry[0]): $taskLicense, $((Get-Item $taskPath).Length) bytes"
}
$taskCatalog | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $taskDir 'catalog.json') -Encoding utf8
