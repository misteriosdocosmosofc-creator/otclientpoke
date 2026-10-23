param(
    [string]$Adb,
    [string]$Package = 'com.github.otclient',
    [ValidateSet('off','summary','records','capture')][string]$Diagnostics = 'summary',
    [string[]]$Files = @('modules/gamelib/game.lua','modules/game_features/features.lua','modules/client_entergame/characterlist.lua'),
    [switch]$StartApp
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $Adb) {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($adbCommand) { $Adb = $adbCommand.Source }
    else { $Adb = Join-Path (Split-Path $repoRoot) 'android-toolchain/android-sdk/platform-tools/adb.exe' }
}
function Invoke-Adb {
    param([string[]]$Arguments)
    $result = & $Adb @Arguments
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')" }
    return $result
}
$null = Invoke-Adb -Arguments @('shell','run-as',$Package,'test','-f','files/game_data/init.lua')
$null = Invoke-Adb -Arguments @('shell','am','force-stop',$Package)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('otc-modules-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot
$diagnosticFile = Join-Path $tempRoot 'pka-debug.otml'
[IO.File]::WriteAllText($diagnosticFile, "level: $Diagnostics`n", [Text.UTF8Encoding]::new($false))
$fileMap = @{}
foreach ($relative in $Files) {
    if ($relative -notmatch '^(init\.lua|modules/.*\.(lua|otui|otmod)|data/(setup\.otml|styles/.*\.otui))$' -or $relative.Contains('..')) {
        throw "File outside the allowed module/config paths: $relative"
    }
    $fileMap[$relative] = Join-Path $repoRoot $relative
}
$fileMap['pka-debug.otml'] = $diagnosticFile
foreach ($relative in $fileMap.Keys) {
    $source = $fileMap[$relative]
    $stage = '/data/local/tmp/otc-dev/' + $relative
    $target = 'files/game_data/' + $relative
    $parent = $target.Substring(0, $target.LastIndexOf('/'))
    $stageParent = $stage.Substring(0, $stage.LastIndexOf('/'))
    $null = Invoke-Adb -Arguments @('shell','mkdir','-p',$stageParent)
    $null = Invoke-Adb -Arguments @('push',$source,$stage)
    $null = Invoke-Adb -Arguments @('shell','run-as',$Package,'mkdir','-p',$parent)
    $null = Invoke-Adb -Arguments @('shell','run-as',$Package,'cp',$stage,$target)
    $expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $remote = (Invoke-Adb -Arguments @('shell','run-as',$Package,'sha256sum',$target)) -join "`n"
    if (-not $remote.StartsWith($expected)) { throw "Hash mismatch for $relative" }
    Write-Output "$relative SHA256=$expected"
}
if ($StartApp) { $null = Invoke-Adb -Arguments @('shell','am','start','-n',"$Package/com.otclient.MainActivity") }
Write-Output 'Active game_data modules synchronized. Credentials and DAT/SPR were not copied.'
