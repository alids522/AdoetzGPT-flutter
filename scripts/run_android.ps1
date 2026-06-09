Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$flutter = 'C:\Users\abdur\flutter\bin\flutter.bat'

Set-Location $projectRoot
& $flutter run -d android
