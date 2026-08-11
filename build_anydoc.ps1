# sc_anydoc.dll 빌드 + 배포. 64/32 양쪽 지원.
#   .\build_anydoc.ps1                 # Win64
#   .\build_anydoc.ps1 -Platform Win32
#   .\build_anydoc.ps1 -Platform All   # 양쪽 순차 빌드
#
# 배포: 64비트 -> C:\Works\lib\dll\sc_anydoc.dll
#       32비트 -> C:\Works\lib\dll\win32\sc_anydoc.dll   (동일명, 접미어 없음)
#
# cargo 는 --target 별로 산출물 디렉터리를 자동 분리하므로(target\<triple>\release)
# CMake 처럼 build/build32 를 따로 둘 필요가 없다.
# CRT 정적 링크는 .cargo\config.toml 에 고정되어 있어 vcvars 를 부를 필요도 없다.
param(
  [ValidateSet('Win64', 'Win32', 'All')]
  [string]$Platform = 'Win64',
  [string]$DeployRoot = 'C:\Works\lib\dll',
  [switch]$SkipDeploy,
  [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Build-One([string]$plat) {
  $triple = if ($plat -eq 'Win32') { 'i686-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
  $deployDir = if ($plat -eq 'Win32') { Join-Path $DeployRoot 'win32' } else { $DeployRoot }

  Write-Host ''
  Write-Host "=== [$plat] cargo build --release --target $triple ===" -ForegroundColor Cyan

  Push-Location $root
  try {
    # 타깃 미설치 시 친절히 안내
    $installed = (rustup target list --installed) -split "`r?`n"
    if ($installed -notcontains $triple) {
      throw "타깃 미설치: $triple  →  rustup target add $triple"
    }

    cargo build --release --target $triple
    if ($LASTEXITCODE -ne 0) {
      throw "[$plat] 빌드 실패"
    }
  }
  finally {
    Pop-Location
  }

  $artifact = Join-Path $root "target\$triple\release\sc_anydoc.dll"
  if (-not (Test-Path $artifact)) {
    throw "산출물 없음: $artifact"
  }

  if (-not $SkipVerify) {
    Write-Host "=== [$plat] ABI 검증 ===" -ForegroundColor Cyan
    & (Join-Path $root 'verify_dll.ps1') -Platform $plat
    if ($LASTEXITCODE -ne 0) {
      throw "[$plat] 검증 실패 - 배포를 중단합니다"
    }
  }

  if ($SkipDeploy) {
    Write-Host "=== [$plat] 배포 생략 ===" -ForegroundColor Yellow
    Get-Item $artifact | Select-Object FullName, Length, LastWriteTime | Format-List
    return
  }

  if (-not (Test-Path $deployDir)) {
    New-Item -ItemType Directory -Force -Path $deployDir | Out-Null
  }

  $target = Join-Path $deployDir 'sc_anydoc.dll'
  Copy-Item $artifact $target -Force
  Write-Host "=== [$plat] 배포 완료 ===" -ForegroundColor Green
  Get-Item $target | Select-Object FullName, Length, LastWriteTime | Format-List
}

if ($Platform -eq 'All') {
  Build-One 'Win64'
  Build-One 'Win32'
}
else {
  Build-One $Platform
}
