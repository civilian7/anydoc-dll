# Third-Party Notices

The binary produced by this project (`sc_anydoc.dll`) statically links the
following third-party code. Keep these notices when redistributing.

---

## anydoc

- Project: https://github.com/firecrawl/anydoc
- Version: see `Cargo.lock` (also readable at runtime via `anydoc_core_version()`)
- License: MIT

```
MIT License

Copyright (c) 2025 Firecrawl

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Transitive dependencies

anydoc pulls in further Rust crates (`calamine`, `cfb`, `csv`, `encoding_rs`,
`flate2`, `log`, `pdf-inspector`, `quick-xml`, `zip` and their dependencies),
all under permissive licenses (MIT / Apache-2.0 / BSD-family / Zlib).

To produce a full, machine-generated list for a specific build:

```powershell
cargo install cargo-about
cargo about generate about.hbs > licenses.html
```
