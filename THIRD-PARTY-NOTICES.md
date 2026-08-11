# Third-Party Notices

The binaries produced by this project embed the following third-party code.
Keep these notices when redistributing.

- `sc_anydoc.dll` statically links **anydoc** and its Rust dependencies.
- The VCL demo (`AnydocDemo.exe`) additionally embeds **marked** as a resource
  for the Markdown preview, and ships **WebView2Loader.dll** alongside the
  executable.

---

## anydoc

*Embedded in: `sc_anydoc.dll`*

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

## marked

*Embedded in: `AnydocDemo.exe` (demo only — not part of `sc_anydoc.dll`)*

- Project: https://github.com/markedjs/marked
- Version: 15.0.12 (`delphi/demo/marked.min.js`)
- License: MIT

```
Copyright (c) 2011-2025, Christopher Jeffrey (https://github.com/chjj/)

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

## Microsoft Edge WebView2 SDK (WebView2Loader.dll)

*Shipped next to: `AnydocDemo.exe` (demo only — not part of `sc_anydoc.dll`)*

- Project: https://aka.ms/webview
- Package: `Microsoft.Web.WebView2` 1.0.4129.50 (NuGet)
- Files: `delphi/demo/webview2/x64/WebView2Loader.dll`, `delphi/demo/webview2/x86/WebView2Loader.dll`
- License: BSD-3-Clause style (see below)

Note: Delphi 13 statically links the WebView2 loader into the executable, so the
demo does not actually load this DLL. It is shipped for completeness of the
deployment set.

```
Copyright (C) Microsoft Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * The name of Microsoft Corporation, or the names of its contributors
may not be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
