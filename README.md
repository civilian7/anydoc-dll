# sc_anydoc

*[English README](README.en.md)*

[firecrawl/anydoc](https://github.com/firecrawl/anydoc) 을 **Windows DLL(C ABI)** 로 감싸고, Delphi 에서 바로 쓸 수 있게 만든 래퍼.

Word / PowerPoint / Excel / OpenDocument / RTF / EPUB / CSV / PDF 를 **GitHub Flavored Markdown** 으로 변환한다.

---

## anydoc 이란

Firecrawl 이 Rust 로 만든 문서 변환 라이브러리다. MIT 라이선스.

```
문서 바이트 → 포맷 감지 → 포맷별 파서 → 공용 문서 모델 → GFM 시리얼라이저 → 마크다운
```

포맷마다 파서가 따로 있지만 모두 **하나의 공용 문서 모델로 수렴**한 뒤 단일 시리얼라이저를 거친다. 그래서 어떤 포맷을 넣든 출력 마크다운의 스타일이 일관된다.

| 특징 | 내용 |
|---|---|
| 지원 포맷 | doc/docx/docm, ppt/pptx/pptm, xls/xlsx/xlsm/xlsb, odt/ods/odp, rtf, epub, csv, pdf |
| 포맷 감지 | **파일 내용의 시그니처**로 판별한다. 확장자에 의존하지 않아 확장자가 틀려도 올바르게 처리된다 |
| 보존 범위 | 제목, 굵게/기울임, 링크, 표, 각주, 목록 |
| 속도 | 업스트림 기준 문서당 변환 중앙값 5ms 미만 |
| 외부 의존 | 없음. 순수 Rust 크레이트만 사용한다 |

**Office 설치가 필요 없다.** COM 자동화도, 백그라운드 Word 프로세스도 없이 바이트를 직접 파싱한다.

---

## 왜 이 래퍼를 만들었나

anydoc 은 Node.js / Python / WebAssembly 바인딩은 제공하지만 **C ABI 바인딩이 없다.** Delphi 를 비롯한 네이티브 언어에서 부를 방법이 없다는 뜻이다. 이 프로젝트가 그 빈자리를 메운다.

Windows 데스크톱 앱에서 문서를 텍스트로 뽑아내려면 보통 이런 선택지가 있는데, 각각 문제가 있다.

| 방식 | 문제 |
|---|---|
| MS Office COM 자동화 | Office 라이선스와 설치가 필요하고, 서버/무인 환경에서 불안정하다. 프로세스가 남거나 모달 대화상자에 걸린다 |
| 외부 CLI 프로세스 호출 | 프로세스 생성 비용, 임시 파일 관리, 표준출력 인코딩 문제가 따라붙는다 |
| 포맷별 파서 직접 구현 | docx/xlsx/pptx/pdf 를 각각 감당해야 한다. 현실적이지 않다 |

anydoc 은 이미 이 문제를 잘 푼 라이브러리이고, **Rust 라 `cdylib` 로 빌드하면 그대로 DLL** 이 된다. 얇은 C ABI 계층만 얹으면 Delphi 에서 함수 호출 한 번으로 끝난다. 외부 프로세스도, 임시 파일도, Office 설치도 필요 없다.

### 설계할 때 지킨 것

**업스트림을 포크하지 않는다.** anydoc 은 활발히 업데이트되는 프로젝트다. 포크하거나 소스를 벤더링하면 업스트림을 따라가는 일이 곧 유지보수 부담이 된다. 그래서 crates.io 의 크레이트를 **의존성으로만** 참조한다. 새 버전 반영이 `cargo update` 한 줄로 끝난다.

**업스트림이 바뀌어도 래퍼가 깨지지 않게 한다.** 아래 네 가지를 미리 처리해 뒀다.

| 위험 | 대응 |
|---|---|
| 포맷 enum 에 항목 추가·순서 변경 | 포맷을 **서수가 아니라 문자열**로 주고받는다. 새 포맷이 자동으로 노출된다 |
| `ConvertError` 에 variant 추가 | 업스트림이 `#[non_exhaustive]` 로 선언했다. 와일드카드 arm 이 상태코드 **99** 로 흘려 컴파일이 깨지지 않게 한다. 메시지는 그대로 전달되어 정보 손실도 없다 |
| 포맷 해석 규칙 변경 | 업스트림 `to_markdown()` 과 같은 순서(내용 감지 → 확장자 폴백)를 따른다 |
| 어떤 코어가 들어있는지 모름 | `build.rs` 가 `Cargo.lock` 에서 읽어 DLL 에 새긴다. 런타임에 `CoreVersion` 으로 확인된다 |

**32비트도 같이 지원한다.** 확인해 보니 `extern "C"` export 이름에 32비트에서도 데코레이션이 붙지 않아, Delphi 선언 한 벌로 Win32/Win64 를 모두 커버할 수 있었다. `NativeUInt` 도 Rust `usize` 와 자동으로 폭이 맞는다.

---

## 요구 사항

| 도구 | 버전 | 비고 |
|---|---|---|
| Rust | **1.88 이상** | anydoc 코어 요구사항 (검증 환경: 1.97.1) |
| 타깃 | `x86_64-pc-windows-msvc`, `i686-pc-windows-msvc` | `rustup target add <triple>` |
| MSVC 빌드 도구 | Visual Studio Build Tools | 링커(`link.exe`) 용 |
| Delphi | **13 (Studio 37.0)** | 델파이 바인딩·데모를 쓸 때만 |

---

## DLL 빌드

```powershell
.\build_anydoc.ps1                  # Win64
.\build_anydoc.ps1 -Platform Win32
.\build_anydoc.ps1 -Platform All    # 양쪽 순차 빌드
```

**빌드 → ABI 검증 → 배포** 순으로 진행하며, 검증에 실패하면 기존 DLL 을 덮어쓰지 않고 멈춘다.

| 옵션 | 설명 |
|---|---|
| `-Platform Win64\|Win32\|All` | 대상 플랫폼 (기본 `Win64`) |
| `-DeployRoot <경로>` | 배포 루트 (기본 `C:\Works\lib\dll`) |
| `-SkipDeploy` | 빌드만 하고 배포하지 않음 |
| `-SkipVerify` | 검증 생략 |

### 배포 위치

```
64비트 : C:\Works\lib\dll\sc_anydoc.dll
32비트 : C:\Works\lib\dll\win32\sc_anydoc.dll     ← 동일명, 접미어 없음
```

32비트 프로세스는 64비트 DLL 을 로드할 수 없으므로 **폴더로 분리**한다. 이름이 같아 Delphi 선언을 플랫폼별로 나눌 필요가 없다.

### 빌드 결과

| | Win64 | Win32 |
|---|---|---|
| DLL 크기 | 7.7 MB | 6.3 MB |
| 의존 DLL | `kernel32` / `ntdll` / `bcryptprimitives` / `api-ms-win-core-synch` | 동일 |

**VC++ 재배포 패키지가 필요 없다.** `.cargo\config.toml` 에 CRT 정적 링크(`+crt-static`)를 고정해 두어 `VCRUNTIME140.dll` 과 UCRT 의존이 사라진다. DLL 파일 하나만 복사하면 끝이다.

### 검증만 따로 실행

```powershell
.\verify_dll.ps1 -Platform Win64
.\verify_dll.ps1 -Platform Win32   # 32비트 PowerShell 로 자동 재실행된다
```

포인터 폭, 포맷 감지, 한글 UTF-8 왕복, 확장자 힌트 폴백, 오류 경로, 반복 변환/해제 300회를 확인한다.

---

## 업스트림 반영

```powershell
.\update_upstream.ps1          # 최신 버전 확인만 (아무것도 바꾸지 않음)
.\update_upstream.ps1 -Apply   # cargo update + 32/64 재빌드 + 검증 + 배포
```

업스트림이 `0.2.x` 처럼 `Cargo.toml` 의 허용 범위를 벗어나면 자동 반영을 **거부하고 안내만** 출력한다. 이때는 [릴리스 노트](https://github.com/firecrawl/anydoc/releases)를 확인하고 `Cargo.toml` 의 버전을 직접 올린 뒤 다시 실행한다.

---

## Delphi 에서 사용

`delphi\src\SCAnydoc.pas` 를 프로젝트에 추가한다. DLL 은 실행 파일 옆에 두거나 배포 폴더를 PATH 에 넣는다.

```pascal
uses
  SCAnydoc;

// 1) 파일 변환 — 파일 읽기를 델파이가 담당하므로 유니코드 경로에 안전하다
var LMarkdown := TSCAnydoc.ToMarkdownFile('C:\docs\보고서.docx');

// 2) 메모리 변환 — CSV 는 시그니처가 없어 확장자 힌트가 필수
var LMarkdown := TSCAnydoc.ToMarkdown(LBytes, 'csv');

// 3) 포맷만 감지 ('docx', 'pdf', 'excel' ... 실패 시 빈 문자열)
var LFormat := TSCAnydoc.DetectFormat(LBytes);

// 4) DLL 가용성 확인 (예외를 던지지 않는다)
if not TSCAnydoc.IsAvailable then
begin
  ShowMessage('sc_anydoc.dll 을 찾을 수 없습니다.');
end;
```

### 오류 처리

실패는 `EAnydocError` 로 올라온다. `Status` 로 원인을 구분하고, `Detail` 에는 코어가 준 원본(영문) 메시지가 담긴다.

```pascal
try
  LMarkdown := TSCAnydoc.ToMarkdownFile(LFileName);
except
  on E: EAnydocError do
  begin
    if E.Status = asEncrypted then
    begin
      TSCLog.Instance.Warn('암호화 문서 건너뜀: ' + LFileName, 'DOC');
    end
    else
    begin
      TSCLog.Instance.Error(E.Message, 'DOC');
      raise;
    end;
  end;
end;
```

| 프로퍼티 | 내용 |
|---|---|
| `Status` | `asUnsupported` / `asMalformed` / `asEncrypted` / `asResourceLimit` / `asMissingPart` / `asIo` / `asInvalidArg` / `asPanic` / `asUnknown` |
| `Message` | 한글로 조립된 표시용 메시지 |
| `Detail` | 코어가 준 원본 메시지. 항상 영문이라 로케일에 의존하지 않는다 |

### 스레드

변환은 **동기 blocking** 이다. 큰 문서에서 UI 가 멈추므로, UI 프로젝트에서는 워커 스레드에서 호출하고 결과만 `TThread.Queue` 로 메인 스레드에 넘긴다.

```pascal
TThread.CreateAnonymousThread(
  procedure
  var
    LMarkdown: string;   // 익명 메서드가 캡처하므로 var 블록에 선언
  begin
    LMarkdown := TSCAnydoc.ToMarkdown(LBytes, LExt);
    TThread.Queue(nil,
      procedure
      begin
        memResult.Lines.Text := LMarkdown;
      end);
  end).Start;
```

DLL 은 전역 상태를 두지 않아 **여러 스레드에서 동시에 호출해도 안전**하다.

---

## VCL 데모

`delphi\demo\` 에 표준 VCL 샘플이 있다. UI 는 영문이다.

```powershell
cd delphi\demo
.\build_demo.ps1 -Run                  # Win64 빌드 후 실행
.\build_demo.ps1 -Platform Win32
```

`sc_anydoc.dll` 을 실행 파일 옆에 함께 복사하므로 PATH 설정 없이 실행된다. IDE 에서 열려면 `AnydocDemo.dpr` 을 **File > Open Project** 로 열면 `.dproj` 가 자동 생성된다.

데모가 보여주는 것:

- 문서 열기 / **창으로 드래그 앤 드롭**(`WM_DROPFILES`) / 실행 파일에 문서를 떨어뜨려 실행
- 변환을 **워커 스레드**에서 수행하고 UI 갱신만 `TThread.Queue` 로 위임
- `FormCloseQuery` 로 변환 중 종료 차단 — Queue 로 넘긴 코드가 해제된 폼을 건드리는 AV 방지
- `EAnydocError.Status` / `Detail` 로 실패 원인 표시
- 상태바에 포맷·소요 시간·코어 버전 표시, 결과를 UTF-8 `.md` 로 저장 (**UTF-8 BOM** 체크박스로 BOM 유무 선택, 기본은 BOM 없음)
- **Preview 탭**에서 `TEdgeBrowser`(WebView2) 로 마크다운 렌더링 — 아래 참조
- **PerMonitorV2** DPI 매니페스트 포함

### 마크다운 프리뷰

`Preview.pas` 가 `TEdgeBrowser` 를 프리뷰어로 운전한다. 마크다운 → HTML 변환은
[marked](https://github.com/markedjs/marked) 가 담당하며, `sc_anydoc.dll` 과 C ABI 는 이 기능에 관여하지 않는다.

- **셸 페이지는 한 번만 로드**한다. `preview.html` 에 `marked.min.js` 를 통째로 인라인해(둘 다 `RCDATA` 리소스) `NavigateToString` 으로 띄운 뒤, 이후 마크다운은 `PostWebMessageAsString` 으로 원문 그대로 넘긴다 — 재탐색도 JS 문자열 이스케이프도 없다
- **초기화는 Preview 탭을 처음 열 때까지 지연**된다. 프리뷰를 쓰지 않으면 WebView2 생성 비용을 전혀 치르지 않는다
- 소스가 바뀌면 dirty 로만 표시하고, 실제 렌더는 탭이 보일 때 한 번에 한다
- CSP 로 외부 리소스를 차단한다. 인라인 스크립트·스타일과 `https` 이미지만 허용
- 문서 안의 링크는 WebView 안에서 열지 않고 `ShellExecute` 로 기본 브라우저에 넘긴다
- **WebView2 런타임이 없으면** 프리뷰 탭에 사유를 표시하고 변환·저장 기능은 그대로 동작한다. 런타임은 시스템에 설치되는 구성요소이며 exe 옆에 복사하는 파일이 아니다

`build_demo.ps1` 은 `sc_anydoc.dll` 과 함께 아키텍처에 맞는 `WebView2Loader.dll`(`webview2\x64` / `webview2\x86`)을 실행 파일 옆에 복사한다. 다만 **Delphi 13 은 loader 를 실행 파일에 정적 링크하므로 데모가 이 DLL 을 실제로 로드하지는 않는다** — 배포 묶음의 완결성을 위해 함께 둘 뿐이다.

---

## C ABI

Delphi 외의 언어에서 쓸 때 참고. 모든 함수가 `cdecl`(`extern "C"`) 이며, **32비트에서도 export 이름에 데코레이션이 붙지 않아** Win32/Win64 선언이 동일하다.

| 함수 | 설명 |
|---|---|
| `uint32_t anydoc_abi_version()` | ABI 버전 (현재 1) |
| `const char* anydoc_core_version()` | 링크된 anydoc 코어 버전. **정적 문자열 — 해제 금지** |
| `const char* anydoc_wrapper_version()` | 래퍼 버전. **해제 금지** |
| `uint32_t anydoc_pointer_size()` | 4(Win32) 또는 8(Win64). 비트수 진단용 |
| `int32_t anydoc_detect_format(const uint8_t* data, size_t len, char** out_name, size_t* out_name_len)` | 내용 기반 포맷 감지 |
| `int32_t anydoc_to_markdown(const uint8_t* data, size_t len, const char* format_hint, char** out_text, size_t* out_text_len, char** out_err, size_t* out_err_len)` | 변환 |
| `void anydoc_free(char* p, size_t len)` | 위 두 함수가 채운 버퍼 해제 |

### 상태 코드

| 값 | 의미 | 값 | 의미 |
|---|---|---|---|
| 0 | 성공 | 5 | 필수 구성요소 누락 |
| 1 | 지원하지 않는 포맷 | 6 | 입출력 오류 |
| 2 | 손상된 문서 | 7 | 잘못된 인자 |
| 3 | 암호화된 문서 | 8 | 엔진 내부 패닉 |
| 4 | 리소스 한계 초과 | 99 | 업스트림 신규 오류 |

### 규약

- 출력 문자열은 **UTF-8**, 길이가 함께 반환된다. NUL 종단도 붙지만 길이 사용을 권장한다
- `anydoc_free` 에는 **함께 받은 길이를 그대로** 넘긴다. Rust 할당자가 해제하므로 호출 측에서 `free`/`FreeMem` 하면 안 된다
- 모든 진입점이 `catch_unwind` 로 감싸여 있어 Rust 패닉이 FFI 경계를 넘지 않는다
- `format_hint` 는 확장자 문자열(`"docx"`, `".pdf"`, `"csv"`). 점은 있어도 없어도 된다. 포맷은 **내용 감지를 먼저** 시도하고 실패 시 힌트로 폴백하므로, 시그니처가 없는 **CSV 는 힌트가 필수**다
- 파일 경로를 넘기는 API 는 일부러 두지 않았다. 호출 측이 바이트를 읽어 넘기면 Windows 유니코드 경로 인코딩 문제가 아예 발생하지 않는다

---

## 알려진 제약

- **PDF 는 문서 모델(`to_document`)을 지원하지 않는다** (업스트림 제약). 마크다운 변환만 가능하며, 스캔본/이미지 PDF 는 OCR 이 필요해 `Unsupported` 로 떨어진다. PDF 변환 품질은 업스트림이 쓰는 `pdf-inspector` 수준에 종속되므로, 실사용 샘플로 확인해 보는 것이 좋다
- **Win32 메모리 한계** — 문서 전체를 메모리에 올려 파싱한다. 32비트 프로세스의 주소 공간(기본 2GB) 안에서 수백 MB 급 문서는 실패할 수 있다. 해당 시나리오가 있으면 호출 측에서 입력 크기 상한을 두는 편이 안전하다
- 업스트림 `to_document`(문서 모델 트리)는 C ABI 로 노출하지 않았다. 필요하면 JSON 직렬화 형태로 추가할 수 있다

---

## 구성

```
Cargo.toml                crates.io 의 anydoc 을 의존성으로 참조 (포크·벤더링 없음)
.cargo\config.toml        타깃별 CRT 정적 링크 고정
build.rs                  Cargo.lock 의 코어 버전을 DLL 에 새김
src\lib.rs                C ABI 래퍼
build_anydoc.ps1          빌드 → 검증 → 배포
verify_dll.ps1            ABI 검증 (32비트는 자동 재실행)
update_upstream.ps1       업스트림 확인 및 반영
delphi\src\SCAnydoc.pas   Delphi 바인딩
delphi\demo\              VCL 데모 (dpr/pas/dfm/manifest/rc + build_demo.ps1)
  Preview.pas             TEdgeBrowser 를 운전하는 마크다운 프리뷰
  preview.html            프리뷰 셸 페이지 (RCDATA)
  marked.min.js           마크다운 렌더러 (RCDATA, MIT)
  webview2\x64|x86\       WebView2Loader.dll (빌드 시 exe 옆으로 복사)
```

## 라이선스

**MIT** — [LICENSE](LICENSE) 참조.

업스트림 [anydoc](https://github.com/firecrawl/anydoc) 크레이트도 MIT 다. 이 프로젝트가 만든 바이너리에 정적으로 링크되므로, 재배포할 때 해당 고지를 유지한다 — [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) 참조.
