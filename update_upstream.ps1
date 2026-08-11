# 업스트림(firecrawl/anydoc) 최신 버전 확인 및 반영.
#   .\update_upstream.ps1          # 확인만 (변경 없음)
#   .\update_upstream.ps1 -Apply   # cargo update + 양쪽 재빌드/검증/배포
#
# 이 프로젝트는 업스트림을 포크하거나 소스를 벤더링하지 않는다. crates.io 의
# anydoc 크레이트를 의존성으로만 참조하므로, 반영은 Cargo.lock 갱신이 전부다.
# Cargo.toml 의 범위(0.1.x) 안이면 -Apply 로 끝나고, 범위를 벗어나는 메이저/마이너
# 승격(0.2 등)이면 Cargo.toml 을 손봐야 하므로 안내만 하고 멈춘다.
param(
  [switch]$Apply,
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Get-LockedVersion {
  $lock = Join-Path $root 'Cargo.lock'
  if (-not (Test-Path $lock)) {
    return $null
  }

  $lines = Get-Content $lock
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq 'name = "anydoc"') {
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        $t = $lines[$j].Trim()
        if ($t -like 'version = "*"') {
          return $t.Substring(11).Trim('"')
        }

        if ($t.StartsWith('[[')) {
          break
        }
      }
    }
  }

  return $null
}

# Cargo.toml 이 허용하는 범위 (caret) 안인지 — 0.x 는 마이너가 메이저 역할을 한다
function Test-InRange([string]$current, [string]$latest) {
  $c = $current.Split('.')
  $l = $latest.Split('.')
  if ($c[0] -ne $l[0]) {
    return $false
  }

  if ($c[0] -eq '0') {
    return $c[1] -eq $l[1]
  }

  return $true
}

$locked = Get-LockedVersion
Write-Host ''
Write-Host '=== anydoc 업스트림 확인 ===' -ForegroundColor Cyan
Write-Host "  현재 고정 버전 : $locked  (Cargo.lock)"

$meta = Invoke-RestMethod -Uri 'https://crates.io/api/v1/crates/anydoc' -Headers @{ 'User-Agent' = 'sc_anydoc-updater' }
$latest = $meta.crate.max_stable_version
Write-Host "  crates.io 최신 : $latest"
Write-Host "  릴리스 노트    : https://github.com/firecrawl/anydoc/releases"

if ($locked -eq $latest) {
  Write-Host ''
  Write-Host '최신 버전입니다. 반영할 변경 없음.' -ForegroundColor Green
  exit 0
}

$inRange = Test-InRange $locked $latest
Write-Host ''

if (-not $inRange) {
  Write-Host "새 버전 $latest 는 Cargo.toml 의 허용 범위(anydoc = `"$locked`") 밖입니다." -ForegroundColor Yellow
  Write-Host '자동 반영하지 않습니다. 다음을 직접 확인하세요:'
  Write-Host "  1) https://github.com/firecrawl/anydoc/releases 에서 파괴적 변경 확인"
  Write-Host "  2) Cargo.toml 의 anydoc 버전을 `"$latest`" 로 수정"
  Write-Host "  3) .\update_upstream.ps1 -Apply 재실행"
  Write-Host "     (ConvertError 는 #[non_exhaustive] 라 variant 추가만으로는 깨지지 않습니다)"
  exit 2
}

Write-Host "새 버전 $latest 를 반영할 수 있습니다 (허용 범위 내)." -ForegroundColor Yellow

if (-not $Apply) {
  Write-Host '반영하려면 -Apply 를 붙여 다시 실행하세요.'
  exit 0
}

Write-Host ''
Write-Host '=== cargo update -p anydoc ===' -ForegroundColor Cyan
Push-Location $root
try {
  cargo update -p anydoc
  if ($LASTEXITCODE -ne 0) {
    throw 'cargo update 실패'
  }
}
finally {
  Pop-Location
}

$updated = Get-LockedVersion
Write-Host "  고정 버전 : $locked -> $updated"

# 재빌드 + 검증 + 배포. 검증에 실패하면 build_anydoc.ps1 이 배포 전에 멈춘다.
$buildArgs = @{ Platform = 'All' }
if ($SkipDeploy) {
  $buildArgs['SkipDeploy'] = $true
}

& (Join-Path $root 'build_anydoc.ps1') @buildArgs
if ($LASTEXITCODE -ne 0) {
  throw '재빌드/검증 실패 — Cargo.lock 을 되돌리려면: git checkout Cargo.lock (또는 수동 복원)'
}

Write-Host ''
Write-Host "=== anydoc $updated 반영 완료 ===" -ForegroundColor Green
