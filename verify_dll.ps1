# sc_anydoc.dll ABI 검증. 빌드 직후와 업스트림 갱신 후에 반드시 실행한다.
#   .\verify_dll.ps1 -Platform Win64
#   .\verify_dll.ps1 -Platform Win32
# Win32 DLL 은 32비트 프로세스에서만 로드되므로, 이 스크립트가 알아서
# SysWOW64 의 32비트 Windows PowerShell 로 자기 자신을 다시 띄운다.
param(
  [ValidateSet('Win64', 'Win32')]
  [string]$Platform = 'Win64',
  [string]$DllPath = '',
  [switch]$Relaunched
)

$ErrorActionPreference = 'Stop'

$triple = if ($Platform -eq 'Win32') { 'i686-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
if ($DllPath -eq '') {
  $DllPath = Join-Path $PSScriptRoot "target\$triple\release\sc_anydoc.dll"
}

if (-not (Test-Path $DllPath)) {
  throw "DLL 없음: $DllPath  (먼저 .\build_anydoc.ps1 -Platform $Platform 실행)"
}

# 32비트 DLL 은 32비트 호스트가 필요하다.
$needs32 = ($Platform -eq 'Win32')
$is32 = ([IntPtr]::Size -eq 4)
if ($needs32 -and -not $is32) {
  if ($Relaunched) {
    throw '32비트 PowerShell 재실행에 실패했습니다.'
  }

  $ps32 = "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
  if (-not (Test-Path $ps32)) {
    throw "32비트 PowerShell 없음: $ps32"
  }

  & $ps32 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
      -Platform $Platform -DllPath $DllPath -Relaunched
  exit $LASTEXITCODE
}

if (-not $needs32 -and $is32) {
  throw '64비트 DLL 은 64비트 PowerShell 에서 실행하세요.'
}

$src = @"
using System;
using System.Runtime.InteropServices;

public static class Anydoc {
    const string D = @"DLLPATH";

    [DllImport(D, CallingConvention = CallingConvention.Cdecl)]
    public static extern uint anydoc_abi_version();

    [DllImport(D, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr anydoc_core_version();

    [DllImport(D, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr anydoc_wrapper_version();

    [DllImport(D, CallingConvention = CallingConvention.Cdecl)]
    public static extern uint anydoc_pointer_size();

    [DllImport(D, CallingConvention = CallingConvention.Cdecl)]
    public static extern int anydoc_detect_format(byte[] data, UIntPtr len,
        out IntPtr name, out UIntPtr nameLen);

    [DllImport(D, CallingConvention = CallingConvention.Cdecl)]
    public static extern int anydoc_to_markdown(byte[] data, UIntPtr len, byte[] hint,
        out IntPtr text, out UIntPtr textLen, out IntPtr err, out UIntPtr errLen);

    [DllImport(D, CallingConvention = CallingConvention.Cdecl)]
    public static extern void anydoc_free(IntPtr p, UIntPtr len);

    public static byte[] Take(IntPtr p, UIntPtr len) {
        if (p == IntPtr.Zero) return new byte[0];
        byte[] buf = new byte[(int)len];
        Marshal.Copy(p, buf, 0, buf.Length);
        anydoc_free(p, len);
        return buf;
    }

    // 정적 문자열(버전) 전용 — 해제하지 않는다.
    public static string Static(IntPtr p) {
        int n = 0;
        while (Marshal.ReadByte(p, n) != 0) n++;
        byte[] buf = new byte[n];
        Marshal.Copy(p, buf, 0, n);
        return System.Text.Encoding.UTF8.GetString(buf);
    }
}
"@

Add-Type -TypeDefinition $src.Replace('DLLPATH', $DllPath)

function New-Len([int]$n) { return [UIntPtr]::new([uint64]$n) }
function To-Hint([string]$s) {
  if ($s -eq '') { return $null }
  return [System.Text.Encoding]::UTF8.GetBytes($s + "`0")
}

$failed = 0
function Check([string]$label, [bool]$ok, [string]$detail) {
  if ($ok) {
    Write-Host ("  [OK]   {0}  {1}" -f $label, $detail)
  }
  else {
    Write-Host ("  [FAIL] {0}  {1}" -f $label, $detail) -ForegroundColor Red
    $script:failed++
  }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host ""
Write-Host ("=== sc_anydoc 검증 [{0}] ===" -f $Platform)
Write-Host ("  DLL          : {0}" -f $DllPath)
Write-Host ("  호스트       : {0}-bit" -f ([IntPtr]::Size * 8))
Write-Host ("  ABI 버전     : {0}" -f [Anydoc]::anydoc_abi_version())
Write-Host ("  코어 버전    : anydoc {0}" -f [Anydoc]::Static([Anydoc]::anydoc_core_version()))
Write-Host ("  래퍼 버전    : sc_anydoc {0}" -f [Anydoc]::Static([Anydoc]::anydoc_wrapper_version()))
Write-Host ""

# 1) 비트수 일치
$expected = if ($Platform -eq 'Win32') { 4 } else { 8 }
$actual = [Anydoc]::anydoc_pointer_size()
Check '포인터 폭' ($actual -eq $expected) ("usize = $actual 바이트 (기대 $expected)")

# 2) 내용 기반 포맷 감지 + 한글 UTF-8 왕복 (RTF)
$bs = [string][char]92
$rtf = '{' + $bs + 'rtf1' + $bs + 'ansi{' + $bs + 'b Title}' + $bs + 'par Hello ' +
       $bs + 'i world' + $bs + 'i0 . ' +
       $bs + 'u54620?' + $bs + 'u44397?' + $bs + 'u50612?' + $bs + 'par}'
$rtfBytes = [System.Text.Encoding]::ASCII.GetBytes($rtf)

$name = [IntPtr]::Zero; $nameLen = [UIntPtr]::Zero
$rc = [Anydoc]::anydoc_detect_format($rtfBytes, (New-Len $rtfBytes.Length), [ref]$name, [ref]$nameLen)
$detected = [System.Text.Encoding]::UTF8.GetString([Anydoc]::Take($name, $nameLen))
Check '포맷 감지(RTF)' (($rc -eq 0) -and ($detected -eq 'rtf')) ("rc=$rc, name='$detected'")

$t = [IntPtr]::Zero; $tl = [UIntPtr]::Zero; $e = [IntPtr]::Zero; $el = [UIntPtr]::Zero
$rc = [Anydoc]::anydoc_to_markdown($rtfBytes, (New-Len $rtfBytes.Length), $null,
        [ref]$t, [ref]$tl, [ref]$e, [ref]$el)
$md = [System.Text.Encoding]::UTF8.GetString([Anydoc]::Take($t, $tl))
[void][Anydoc]::Take($e, $el)
Check 'RTF 변환' (($rc -eq 0) -and $md.Contains('**Title**')) ("rc=$rc, {0} 자" -f $md.Length)
$korean = [string][char]0xD55C + [string][char]0xAD6D + [string][char]0xC5B4
Check '한글 UTF-8 왕복' ($md.Contains($korean)) $md.Trim()

# 3) 확장자 힌트 폴백 (CSV 는 시그니처가 없어 힌트가 반드시 필요하다)
$csvBytes = [System.Text.Encoding]::UTF8.GetBytes("name,qty`n" + [char]0xC0AC + [char]0xACFC + ",3`n")
$t = [IntPtr]::Zero; $tl = [UIntPtr]::Zero; $e = [IntPtr]::Zero; $el = [UIntPtr]::Zero
$rc = [Anydoc]::anydoc_to_markdown($csvBytes, (New-Len $csvBytes.Length), (To-Hint '.csv'),
        [ref]$t, [ref]$tl, [ref]$e, [ref]$el)
$csvMd = [System.Text.Encoding]::UTF8.GetString([Anydoc]::Take($t, $tl))
[void][Anydoc]::Take($e, $el)
Check 'CSV 힌트 폴백' (($rc -eq 0) -and $csvMd.Contains('| name')) ("rc=$rc, " + $csvMd.Replace("`n", ' ').Trim())

# 4) 오류 경로 — 인식 불가 데이터는 상태코드 + 메시지를 준다
$junk = [byte[]](1..64 | ForEach-Object { [byte](($_ * 7) % 251) })
$t = [IntPtr]::Zero; $tl = [UIntPtr]::Zero; $e = [IntPtr]::Zero; $el = [UIntPtr]::Zero
$rc = [Anydoc]::anydoc_to_markdown($junk, (New-Len $junk.Length), $null,
        [ref]$t, [ref]$tl, [ref]$e, [ref]$el)
$msg = [System.Text.Encoding]::UTF8.GetString([Anydoc]::Take($e, $el))
[void][Anydoc]::Take($t, $tl)
Check '오류 경로' (($rc -eq 1) -and ($msg -ne '')) ("rc=$rc, msg='$msg'")

# 5) 해제 반복 — 누수/이중해제 없이 버틴다
for ($i = 0; $i -lt 300; $i++) {
  $t = [IntPtr]::Zero; $tl = [UIntPtr]::Zero; $e = [IntPtr]::Zero; $el = [UIntPtr]::Zero
  [void][Anydoc]::anydoc_to_markdown($rtfBytes, (New-Len $rtfBytes.Length), $null,
        [ref]$t, [ref]$tl, [ref]$e, [ref]$el)
  [void][Anydoc]::Take($t, $tl)
  [void][Anydoc]::Take($e, $el)
}
Check '반복 변환/해제 300회' $true '완료'

Write-Host ""
if ($failed -gt 0) {
  Write-Host ("=== 실패 {0}건 ===" -f $failed) -ForegroundColor Red
  exit 1
}

Write-Host '=== 전체 통과 ===' -ForegroundColor Green
exit 0
