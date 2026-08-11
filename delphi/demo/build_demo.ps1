# anydoc VCL 데모 빌드.
#   .\build_demo.ps1                  # Win64
#   .\build_demo.ps1 -Platform Win32
#
# sc_anydoc.dll 과 WebView2Loader.dll 을 실행 파일 옆에 함께 복사하므로
# PATH 설정 없이 바로 실행된다.
# IDE 에서 열려면 AnydocDemo.dpr 을 File > Open Project 로 열면 .dproj 가 자동 생성된다.
param(
  [ValidateSet('Win64', 'Win32')]
  [string]$Platform = 'Win64',
  [string]$Studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
  [string]$DeployRoot = 'C:\Works\lib\dll',
  [switch]$Run
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$dcc = if ($Platform -eq 'Win32') { 'dcc32.exe' } else { 'dcc64.exe' }
$dll = if ($Platform -eq 'Win32') { Join-Path $DeployRoot 'win32\sc_anydoc.dll' } else { Join-Path $DeployRoot 'sc_anydoc.dll' }
$outDir = Join-Path $root $Platform

# WebView2 loader. Delphi 13 은 loader 를 실행 파일에 정적 링크하므로 데모가 이 DLL 을
# 로드하지는 않는다. 배포 묶음의 완결성을 위해 아키텍처에 맞는 것을 함께 둔다.
$loaderArch = if ($Platform -eq 'Win32') { 'x86' } else { 'x64' }
$loader = Join-Path $root "webview2\$loaderArch\WebView2Loader.dll"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Push-Location $root
try {
  # 1) PerMonitorV2 매니페스트를 리소스로 컴파일
  Write-Host "=== [$Platform] 매니페스트 리소스 컴파일 ===" -ForegroundColor Cyan
  & (Join-Path $Studio 'bin\brcc32.exe') AnydocDemo.rc
  if ($LASTEXITCODE -ne 0) {
    throw '리소스 컴파일 실패'
  }

  # 2) 델파이 컴파일
  Write-Host "=== [$Platform] $dcc ===" -ForegroundColor Cyan
  & (Join-Path $Studio "bin\$dcc") -E"$outDir" -NU"$outDir" -N0"$outDir" -NH"$outDir" -Q AnydocDemo.dpr
  if ($LASTEXITCODE -ne 0) {
    throw '델파이 컴파일 실패'
  }
}
finally {
  Pop-Location
}

# 3) DLL 을 실행 파일 옆에 배치
if (-not (Test-Path $dll)) {
  throw "sc_anydoc.dll 없음: $dll  (먼저 ..\..\build_anydoc.ps1 -Platform $Platform 실행)"
}

Copy-Item $dll $outDir -Force

if (Test-Path $loader) {
  Copy-Item $loader $outDir -Force
}
else {
  Write-Warning "WebView2Loader.dll 없음: $loader  (프리뷰 동작에는 영향 없음)"
}

$exe = Join-Path $outDir 'AnydocDemo.exe'
Write-Host ''
Write-Host '=== 산출물 ===' -ForegroundColor Green
Get-ChildItem $outDir -Filter '*.exe' | Select-Object FullName, Length, LastWriteTime | Format-List
Get-ChildItem $outDir -Filter '*.dll' | Select-Object FullName, Length | Format-List

if ($Run) {
  Write-Host "실행: $exe"
  Start-Process $exe
}
