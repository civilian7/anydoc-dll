//! Cargo.lock 에 고정된 anydoc 코어 버전을 컴파일 타임 상수로 굽는다.
//!
//! `cargo update -p anydoc` 로 코어를 올리면 Cargo.lock 이 바뀌고, 그 변화가
//! 자동으로 DLL 의 `anydoc_core_version()` 에 반영된다. 배포된 DLL 안에 어떤
//! 코어가 들어있는지 호출 측(Delphi)에서 그대로 확인할 수 있다.

use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=Cargo.lock");

    let version = locked_version("anydoc").unwrap_or_else(|| "unknown".to_string());
    println!("cargo:rustc-env=ANYDOC_CORE_VERSION={version}");
}

/// Cargo.lock 에서 지정한 패키지의 고정 버전을 읽는다.
fn locked_version(package: &str) -> Option<String> {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").ok()?;
    let text = std::fs::read_to_string(Path::new(&manifest_dir).join("Cargo.lock")).ok()?;

    let needle = format!("name = \"{package}\"");
    let mut lines = text.lines();
    while let Some(line) = lines.next() {
        if line.trim() != needle {
            continue;
        }

        // [[package]] 블록 안에서 name 다음 줄이 version 이다.
        for next in lines.by_ref() {
            let next = next.trim();
            if let Some(rest) = next.strip_prefix("version = \"") {
                return rest.strip_suffix('"').map(str::to_string);
            }

            // 다음 블록으로 넘어갔으면 이 항목엔 version 이 없다.
            if next.starts_with("[[") {
                break;
            }
        }
    }

    None
}
