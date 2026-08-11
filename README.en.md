# sc_anydoc

*[한국어 README](README.md)*

A **Windows DLL (C ABI)** wrapper around [firecrawl/anydoc](https://github.com/firecrawl/anydoc), with a ready-to-use Delphi binding.

Converts Word / PowerPoint / Excel / OpenDocument / RTF / EPUB / CSV / PDF into **GitHub Flavored Markdown**.

---

## What is anydoc

A document conversion library written in Rust by Firecrawl, MIT licensed.

```
document bytes → format detection → format parser → shared document model → GFM serializer → Markdown
```

Every format has its own parser, but they all **converge on one shared document model** before passing through a single serializer. That is why the Markdown output stays stylistically consistent no matter what goes in.

| Aspect | Detail |
|---|---|
| Formats | doc/docx/docm, ppt/pptx/pptm, xls/xlsx/xlsm/xlsb, odt/ods/odp, rtf, epub, csv, pdf |
| Detection | Based on the **content signature**, not the file extension — a mislabeled file still converts correctly |
| Preserved | Headings, bold/italic, links, tables, footnotes, lists |
| Speed | Upstream reports a median conversion time under 5 ms per document |
| Dependencies | None. Pure Rust crates only |

**No Office installation required.** It parses the bytes directly — no COM automation, no background Word process.

---

## Why this wrapper exists

anydoc ships bindings for Node.js, Python and WebAssembly, but **no C ABI binding**. That leaves native languages such as Delphi with no way to call it. This project fills that gap.

Extracting text from documents in a Windows desktop app usually comes down to these options, each with a catch:

| Approach | Problem |
|---|---|
| MS Office COM automation | Requires an Office license and installation; unreliable in server/unattended environments. Processes linger, modal dialogs block |
| Shelling out to a CLI | Process startup cost, temp file management, stdout encoding headaches |
| Writing parsers yourself | docx/xlsx/pptx/pdf each on your own. Not realistic |

anydoc already solves this well, and because it is Rust, **building it as a `cdylib` gives you a DLL directly**. A thin C ABI layer on top turns it into a single function call from Delphi — no external process, no temp files, no Office.

### Design decisions

**Do not fork upstream.** anydoc is actively developed. Forking or vendoring the source would turn "keeping up with upstream" into an ongoing maintenance burden. So this project depends on the crates.io crate **as a dependency only**, which makes adopting a new version a one-line `cargo update`.

**Stay unbroken when upstream changes.** Four risks are handled up front:

| Risk | Mitigation |
|---|---|
| Format enum gains variants or gets reordered | Formats are exchanged as **strings, not ordinals**. New formats surface automatically |
| `ConvertError` gains variants | Upstream marks it `#[non_exhaustive]`. A wildcard arm maps unknown variants to status **99** so compilation never breaks, and the message still passes through — no information lost |
| Format resolution rules change | Mirrors upstream `to_markdown()` exactly: content detection first, extension fallback |
| Not knowing which core is inside | `build.rs` reads it from `Cargo.lock` and bakes it into the DLL. Readable at runtime via `CoreVersion` |

**32-bit is supported too.** It turns out `extern "C"` exports carry no name decoration even on 32-bit, so a single set of Delphi declarations covers both Win32 and Win64. `NativeUInt` also matches Rust's `usize` width automatically.

---

## Requirements

| Tool | Version | Note |
|---|---|---|
| Rust | **1.88 or later** | Required by the anydoc core (verified on 1.97.1) |
| Targets | `x86_64-pc-windows-msvc`, `i686-pc-windows-msvc` | `rustup target add <triple>` |
| MSVC build tools | Visual Studio Build Tools | For the linker (`link.exe`) |
| Delphi | **13 (Studio 37.0)** | Only for the Delphi binding and demo |

---

## Building the DLL

```powershell
.\build_anydoc.ps1                  # Win64
.\build_anydoc.ps1 -Platform Win32
.\build_anydoc.ps1 -Platform All    # both, sequentially
```

The script runs **build → ABI verification → deploy**, and stops without overwriting the existing DLL if verification fails.

| Option | Description |
|---|---|
| `-Platform Win64\|Win32\|All` | Target platform (default `Win64`) |
| `-DeployRoot <path>` | Deploy root (default `C:\Works\lib\dll`) |
| `-SkipDeploy` | Build only, do not deploy |
| `-SkipVerify` | Skip verification |

### Deploy layout

```
64-bit : C:\Works\lib\dll\sc_anydoc.dll
32-bit : C:\Works\lib\dll\win32\sc_anydoc.dll     ← same name, no suffix
```

A 32-bit process cannot load a 64-bit DLL, so the two are **separated by folder**. Keeping the name identical means the Delphi declarations need no per-platform branching.

### Build output

| | Win64 | Win32 |
|---|---|---|
| DLL size | 7.7 MB | 6.3 MB |
| Dependencies | `kernel32` / `ntdll` / `bcryptprimitives` / `api-ms-win-core-synch` | same |

**No VC++ redistributable needed.** `.cargo\config.toml` pins static CRT linking (`+crt-static`), which removes the `VCRUNTIME140.dll` and UCRT dependencies. Copying the single DLL file is enough.

### Running verification alone

```powershell
.\verify_dll.ps1 -Platform Win64
.\verify_dll.ps1 -Platform Win32   # automatically relaunches under 32-bit PowerShell
```

Checks pointer width, format detection, UTF-8 round-trip with non-ASCII text, extension-hint fallback, the error path, and 300 repeated convert/free cycles.

---

## Tracking upstream

```powershell
.\update_upstream.ps1          # check only, changes nothing
.\update_upstream.ps1 -Apply   # cargo update + rebuild both + verify + deploy
```

If upstream moves outside the range allowed by `Cargo.toml` (e.g. `0.2.x`), the script **refuses to apply it** and prints guidance instead. Review the [release notes](https://github.com/firecrawl/anydoc/releases), bump the version in `Cargo.toml` yourself, then run it again.

---

## Using it from Delphi

Add `delphi\src\SCAnydoc.pas` to your project. Put the DLL next to the executable, or add its folder to `PATH`.

```pascal
uses
  SCAnydoc;

// 1) Convert a file — Delphi reads the bytes, so Unicode paths are safe
var LMarkdown := TSCAnydoc.ToMarkdownFile('C:\docs\report.docx');

// 2) Convert from memory — CSV has no signature, so the hint is required
var LMarkdown := TSCAnydoc.ToMarkdown(LBytes, 'csv');

// 3) Detect the format only ('docx', 'pdf', 'excel', ... empty string on failure)
var LFormat := TSCAnydoc.DetectFormat(LBytes);

// 4) Check DLL availability (never raises)
if not TSCAnydoc.IsAvailable then
begin
  ShowMessage('sc_anydoc.dll could not be loaded.');
end;
```

### Error handling

Failures surface as `EAnydocError`. Use `Status` to classify the cause; `Detail` carries the original message from the core.

```pascal
try
  LMarkdown := TSCAnydoc.ToMarkdownFile(LFileName);
except
  on E: EAnydocError do
  begin
    if E.Status = asEncrypted then
    begin
      LogWarn('Skipping encrypted document: ' + LFileName);
    end
    else
    begin
      LogError(E.Message);
      raise;
    end;
  end;
end;
```

| Property | Content |
|---|---|
| `Status` | `asUnsupported` / `asMalformed` / `asEncrypted` / `asResourceLimit` / `asMissingPart` / `asIo` / `asInvalidArg` / `asPanic` / `asUnknown` |
| `Message` | Display message assembled by the binding |
| `Detail` | The core's original message. Always English, so it is locale independent |

### Threading

Conversion is **synchronous and blocking**. It will freeze the UI on large documents, so call it from a worker thread and hand only the UI update back to the main thread via `TThread.Queue`.

```pascal
TThread.CreateAnonymousThread(
  procedure
  var
    LMarkdown: string;   // declared in a var block because the closure captures it
  begin
    LMarkdown := TSCAnydoc.ToMarkdown(LBytes, LExt);
    TThread.Queue(nil,
      procedure
      begin
        memResult.Lines.Text := LMarkdown;
      end);
  end).Start;
```

The DLL keeps no global state, so it is **safe to call concurrently from multiple threads**.

---

## VCL demo

A standard VCL sample lives in `delphi\demo\`.

```powershell
cd delphi\demo
.\build_demo.ps1 -Run                  # build for Win64 and launch
.\build_demo.ps1 -Platform Win32
```

`sc_anydoc.dll` is copied next to the executable, so it runs without any `PATH` setup. To open it in the IDE, use **File > Open Project** on `AnydocDemo.dpr` — the `.dproj` is generated automatically.

What the demo shows:

- Open a document / **drag and drop onto the window** (`WM_DROPFILES`) / drop a document onto the executable
- Conversion runs on a **worker thread**, with only the UI update delegated through `TThread.Queue`
- `FormCloseQuery` blocks closing mid-conversion, preventing the queued code from touching a destroyed form
- Failure cause shown via `EAnydocError.Status` / `Detail`
- Status bar with format, elapsed time and core version; saves the result as UTF-8 `.md`
- **PerMonitorV2** DPI manifest included

---

## C ABI

For use from languages other than Delphi. Every function is `cdecl` (`extern "C"`), and **export names carry no decoration even on 32-bit**, so Win32 and Win64 declarations are identical.

| Function | Description |
|---|---|
| `uint32_t anydoc_abi_version()` | ABI version (currently 1) |
| `const char* anydoc_core_version()` | Linked anydoc core version. **Static string — do not free** |
| `const char* anydoc_wrapper_version()` | Wrapper version. **Do not free** |
| `uint32_t anydoc_pointer_size()` | 4 (Win32) or 8 (Win64). For diagnosing bitness mismatches |
| `int32_t anydoc_detect_format(const uint8_t* data, size_t len, char** out_name, size_t* out_name_len)` | Content-based format detection |
| `int32_t anydoc_to_markdown(const uint8_t* data, size_t len, const char* format_hint, char** out_text, size_t* out_text_len, char** out_err, size_t* out_err_len)` | Conversion |
| `void anydoc_free(char* p, size_t len)` | Frees a buffer filled by the two functions above |

### Status codes

| Value | Meaning | Value | Meaning |
|---|---|---|---|
| 0 | Success | 5 | Missing required part |
| 1 | Unsupported format | 6 | I/O error |
| 2 | Malformed document | 7 | Invalid argument |
| 3 | Encrypted document | 8 | Engine panic |
| 4 | Resource limit exceeded | 99 | New upstream error |

### Contract

- Output strings are **UTF-8** and come with their length. A NUL terminator is appended too, but using the length is recommended
- Pass the **exact length you received** to `anydoc_free`. The Rust allocator owns the memory, so never call `free`/`FreeMem` on it from the caller side
- Every entry point is wrapped in `catch_unwind`, so a Rust panic never crosses the FFI boundary
- `format_hint` is an extension string (`"docx"`, `".pdf"`, `"csv"`), with or without the leading dot. Format resolution tries **content detection first** and falls back to the hint, so the signature-less **CSV format requires the hint**
- There is deliberately no path-taking API. Having the caller read the bytes sidesteps Windows Unicode path encoding issues entirely

---

## Known limitations

- **PDF does not support the document model (`to_document`)** — an upstream constraint. Only Markdown conversion is available, and scanned/image-only PDFs fail as `Unsupported` because they need OCR. PDF quality depends on the `pdf-inspector` crate upstream uses, so it is worth checking against your own samples
- **Win32 memory ceiling** — the whole document is held in memory while parsing. Within a 32-bit process's address space (2 GB by default), documents in the hundreds of megabytes can fail. If that is a real scenario for you, cap the input size on the caller side
- Upstream's `to_document` (the document model tree) is not exposed over the C ABI. It could be added as a JSON-serialized form if needed

---

## Layout

```
Cargo.toml                depends on the crates.io anydoc crate (no fork, no vendoring)
.cargo\config.toml        pins static CRT linking per target
build.rs                  bakes the Cargo.lock core version into the DLL
src\lib.rs                C ABI wrapper
build_anydoc.ps1          build → verify → deploy
verify_dll.ps1            ABI verification (relaunches itself for 32-bit)
update_upstream.ps1       check and adopt upstream releases
delphi\src\SCAnydoc.pas   Delphi binding
delphi\demo\              VCL demo (dpr/pas/dfm/manifest/rc + build_demo.ps1)
```

## License

MIT — see [LICENSE](LICENSE).

The upstream [anydoc](https://github.com/firecrawl/anydoc) crate is MIT licensed as well; the binary produced by this project embeds it, so keep its notice when redistributing.
