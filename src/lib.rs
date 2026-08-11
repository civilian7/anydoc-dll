//! sc_anydoc — anydoc 코어를 Windows DLL(C ABI)로 노출하는 얇은 래퍼.
//!
//! 업스트림(firecrawl/anydoc)은 crates.io 의존성으로만 참조한다. 포크도 벤더링도
//! 하지 않으므로 새 버전 반영은 `cargo update -p anydoc` 한 줄이면 끝난다.
//!
//! # 업스트림 변화에 깨지지 않기 위한 설계
//!
//! * **포맷을 enum 서수가 아니라 문자열로 주고받는다.** 업스트림에 포맷이 추가되거나
//!   순서가 바뀌어도 래퍼와 Delphi 선언을 고칠 일이 없다.
//! * **`ConvertError` 는 `#[non_exhaustive]`** 다. 신규 variant 는 상태코드 99 로 흘려
//!   컴파일이 깨지지 않게 한다.
//! * **포맷 해석 순서를 업스트림과 일치시킨다.** 내용 감지 우선, 확장자 폴백 —
//!   업스트림 `anydoc::to_markdown()` 과 동일한 의미를 갖는다.
//! * **파일 경로를 Rust 로 넘기지 않는다.** 호출 측이 바이트를 읽어 넘기므로
//!   Windows 유니코드 경로 인코딩 문제가 원천적으로 발생하지 않는다.

use std::ffi::{CStr, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

/// 이 DLL 이 구현하는 C ABI 버전. 시그니처가 바뀌면 올린다.
const ABI_VERSION: u32 = 1;

/// Cargo.lock 에서 build.rs 가 읽어 넣은 anydoc 코어 버전.
const CORE_VERSION: &str = concat!(env!("ANYDOC_CORE_VERSION"), "\0");
const WRAPPER_VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "\0");

const STATUS_OK: i32 = 0;
const STATUS_UNSUPPORTED: i32 = 1;
const STATUS_MALFORMED: i32 = 2;
const STATUS_ENCRYPTED: i32 = 3;
const STATUS_RESOURCE_LIMIT: i32 = 4;
const STATUS_MISSING_PART: i32 = 5;
const STATUS_IO: i32 = 6;
const STATUS_INVALID_ARG: i32 = 7;
const STATUS_PANIC: i32 = 8;
/// 업스트림이 추가한, 이 래퍼가 아직 모르는 오류.
const STATUS_UNKNOWN: i32 = 99;

fn status_of(error: &anydoc::ConvertError) -> i32 {
    match error {
        anydoc::ConvertError::Unsupported(_) => STATUS_UNSUPPORTED,
        anydoc::ConvertError::Malformed { .. } => STATUS_MALFORMED,
        anydoc::ConvertError::Encrypted => STATUS_ENCRYPTED,
        anydoc::ConvertError::ResourceLimit { .. } => STATUS_RESOURCE_LIMIT,
        anydoc::ConvertError::MissingPart { .. } => STATUS_MISSING_PART,
        anydoc::ConvertError::Io(_) => STATUS_IO,
        // ConvertError 는 #[non_exhaustive] — 업스트림 신규 variant 대비.
        // 메시지는 Display 로 그대로 전달되므로 정보 손실은 없다.
        _ => STATUS_UNKNOWN,
    }
}

/// 문자열을 호출 측에 넘길 버퍼로 옮긴다. NUL 을 덧붙여 C 문자열로도 읽히게 하되,
/// 길이를 함께 돌려주므로 본문에 NUL 이 섞여도 안전하다.
/// 반환된 포인터는 반드시 [`anydoc_free`] 로, 같은 길이와 함께 해제해야 한다.
fn alloc_out(text: String) -> (*mut c_char, usize) {
    let mut bytes = text.into_bytes();
    let len = bytes.len();
    bytes.push(0);

    // into_boxed_slice 는 capacity == len 을 보장 → 해제 시 길이만으로 복원 가능.
    let boxed = bytes.into_boxed_slice();
    (Box::into_raw(boxed) as *mut c_char, len)
}

/// 출력 파라미터에 문자열을 실어준다. 널 포인터는 조용히 무시한다.
fn write_out(text: String, out_ptr: *mut *mut c_char, out_len: *mut usize) {
    if out_ptr.is_null() {
        return;
    }

    let (ptr, len) = alloc_out(text);
    unsafe {
        *out_ptr = ptr;
        if !out_len.is_null() {
            *out_len = len;
        }
    }
}

/// `*const c_char` 를 Rust 문자열로. 널이거나 UTF-8 이 아니면 `None`.
fn hint_str<'a>(hint: *const c_char) -> Option<&'a str> {
    if hint.is_null() {
        return None;
    }

    let text = unsafe { CStr::from_ptr(hint) }.to_str().ok()?;
    if text.is_empty() {
        return None;
    }

    Some(text)
}

/// 업스트림 `to_markdown()` 과 동일한 해석 순서 — 내용 감지 우선, 확장자 폴백.
/// 시그니처가 없는 CSV 는 확장자로만 지정되므로 폴백이 반드시 필요하다.
fn resolve_format(bytes: &[u8], hint: Option<&str>) -> Option<anydoc::Format> {
    anydoc::Format::from_bytes(bytes).or_else(|| {
        // ".docx" 처럼 점이 붙어 와도 받아준다 (Delphi TPath.GetExtension 대응).
        hint.and_then(|h| anydoc::Format::from_extension(h.trim_start_matches('.')))
    })
}

/// 포맷 이름. `Debug` 로 뽑아 소문자화하므로 업스트림이 포맷을 추가해도
/// 래퍼를 고칠 필요가 없다.
fn format_name(format: anydoc::Format) -> String {
    format!("{format:?}").to_ascii_lowercase()
}

/// 이 DLL 이 구현하는 C ABI 버전.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_abi_version() -> u32 {
    ABI_VERSION
}

/// DLL 에 링크된 anydoc 코어 버전 (예: `"0.1.8"`). 정적 문자열이므로 해제하지 않는다.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_core_version() -> *const c_char {
    CORE_VERSION.as_ptr() as *const c_char
}

/// 이 래퍼 자체의 버전. 정적 문자열이므로 해제하지 않는다.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_wrapper_version() -> *const c_char {
    WRAPPER_VERSION.as_ptr() as *const c_char
}

/// 포인터 폭(바이트). Win32 = 4, Win64 = 8. 비트수 불일치 진단용.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_pointer_size() -> u32 {
    size_of::<usize>() as u32
}

/// 내용만으로 포맷을 감지한다.
///
/// 성공하면 0 을 반환하고 `out_name` 에 소문자 포맷 이름(`"docx"`, `"pdf"` …)을 싣는다.
/// 시그니처가 없는 CSV 나 인식 불가 데이터는 1(Unsupported)을 반환하고 아무것도 싣지 않는다.
/// `out_name` 은 [`anydoc_free`] 로 해제해야 한다.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_detect_format(
    data: *const u8,
    len: usize,
    out_name: *mut *mut c_char,
    out_name_len: *mut usize,
) -> i32 {
    if data.is_null() || out_name.is_null() {
        return STATUS_INVALID_ARG;
    }

    unsafe {
        *out_name = ptr::null_mut();
        if !out_name_len.is_null() {
            *out_name_len = 0;
        }
    }

    let detected = catch_unwind(AssertUnwindSafe(|| {
        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        anydoc::Format::from_bytes(bytes)
    }));

    match detected {
        Ok(Some(format)) => {
            write_out(format_name(format), out_name, out_name_len);
            STATUS_OK
        }
        Ok(None) => STATUS_UNSUPPORTED,
        Err(_) => STATUS_PANIC,
    }
}

/// 메모리에 올린 문서를 GitHub Flavored Markdown 으로 변환한다.
///
/// `format_hint` 는 확장자 문자열(`"docx"`, `".pdf"`, `"csv"` …) 또는 널.
/// 포맷은 내용 감지를 먼저 시도하고, 실패하면 힌트로 폴백한다.
///
/// 성공 시 0 과 함께 `out_text`/`out_text_len` 이 채워지고, 실패 시 상태코드와 함께
/// `out_err`/`out_err_len` 에 사람이 읽을 오류 메시지가 실린다. 채워진 쪽은
/// [`anydoc_free`] 로 해제해야 한다. 전역 상태를 두지 않으므로 스레드 안전하다.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_to_markdown(
    data: *const u8,
    len: usize,
    format_hint: *const c_char,
    out_text: *mut *mut c_char,
    out_text_len: *mut usize,
    out_err: *mut *mut c_char,
    out_err_len: *mut usize,
) -> i32 {
    if data.is_null() || out_text.is_null() || out_err.is_null() {
        return STATUS_INVALID_ARG;
    }

    unsafe {
        *out_text = ptr::null_mut();
        *out_err = ptr::null_mut();
        if !out_text_len.is_null() {
            *out_text_len = 0;
        }

        if !out_err_len.is_null() {
            *out_err_len = 0;
        }
    }

    let converted = catch_unwind(AssertUnwindSafe(|| {
        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        let format = resolve_format(bytes, hint_str(format_hint));
        anydoc::to_markdown_bytes(bytes, format)
    }));

    match converted {
        Ok(Ok(markdown)) => {
            write_out(markdown, out_text, out_text_len);
            STATUS_OK
        }
        Ok(Err(error)) => {
            write_out(error.to_string(), out_err, out_err_len);
            status_of(&error)
        }
        Err(_) => {
            write_out("anydoc 코어에서 패닉이 발생했습니다".to_string(), out_err, out_err_len);
            STATUS_PANIC
        }
    }
}

/// 이 DLL 이 넘겨준 문자열을 해제한다. `len` 은 함께 받은 길이를 그대로 준다.
/// 널 포인터는 무시한다. 정적 문자열(`anydoc_core_version` 등)에는 쓰지 않는다.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_free(text: *mut c_char, len: usize) {
    if text.is_null() {
        return;
    }

    unsafe {
        // alloc_out 이 NUL 한 바이트를 덧붙였으므로 len + 1 로 복원한다.
        let slice = ptr::slice_from_raw_parts_mut(text as *mut u8, len + 1);
        drop(Box::from_raw(slice));
    }
}
