# 🎨 unslop

![unslop](unslop.webp)

**Stop sounding like a bot.** Most LLMs and agentic coding tools (like Claude, ChatGPT, and GitHub Copilot) default to "smart" typography. While it looks nice in a word processor, it creates a distinct "AI Fingerprint" in documentation, commit messages, and blog posts.

`unslop` is a lightning-fast CLI tool built in **Zig** that strips this "LLM accent," reverting fancy Unicode characters back to their clean, standard ASCII equivalents.

## 🧠 The "LLM Accent" Problem

AI models love:

* **Em-dashes (`—`)** for long, rambling asides.
* **Curly quotes (`“ ”`)** which can break certain compilers or shell scripts.
* **Ellipses (`…`)** for "thoughtful" pauses.

`unslop` detects these multi-byte UTF-8 sequences and replaces them with the standard characters a human would actually type on a QWERTY keyboard.

## ✨ Features

* **Humanize AI Text:** Instantly make AI-generated docs look like they were written in a standard text editor.
* **Recursively Sanitizes:** Clean an entire repository of AI-generated `.md` or `.txt` files in milliseconds.
* **Atomic Operations:** Safe file handling. `unslop` never leaves a file half-written.
* **Zero Dependencies:** One tiny, static binary. No runtimes required.
* **Universal Compatibility:** Native support for Windows, macOS, and Linux.

## 🚀 Installation

Grab the binary for your system from the [Releases](https://github.com/jere-mie/unslop/releases) page, or use one of the one-liners below to always get the latest version.

**Linux (x86_64):**
```bash
curl -Lo unslop https://github.com/jere-mie/unslop/releases/latest/download/unslop-linux-x86_64
chmod +x unslop && sudo mv unslop /usr/local/bin/
```

**Linux (aarch64 / ARM64):**
```bash
curl -Lo unslop https://github.com/jere-mie/unslop/releases/latest/download/unslop-linux-aarch64
chmod +x unslop && sudo mv unslop /usr/local/bin/
```

**macOS (Apple Silicon):**
```bash
curl -Lo unslop https://github.com/jere-mie/unslop/releases/latest/download/unslop-macos-aarch64
chmod +x unslop && sudo mv unslop /usr/local/bin/
```

**macOS (Intel):**
```bash
curl -Lo unslop https://github.com/jere-mie/unslop/releases/latest/download/unslop-macos-x86_64
chmod +x unslop && sudo mv unslop /usr/local/bin/
```

**Windows (PowerShell):**
```powershell
Invoke-WebRequest -Uri "https://github.com/jere-mie/unslop/releases/latest/download/unslop-windows-x86_64.exe" -OutFile "unslop.exe"
# Move to a directory on your PATH, e.g.:
Move-Item unslop.exe "$env:USERPROFILE\bin\unslop.exe"
```

**WASM/WASI (run with [wasmtime](https://wasmtime.dev/)):**
```bash
curl -Lo unslop.wasm https://github.com/jere-mie/unslop/releases/latest/download/unslop-wasm32-wasi.wasm
wasmtime --dir=. unslop.wasm myfile.txt
```

**Build from source:**

```bash
zig build -Doptimize=ReleaseFast
```

## 🛠 Mapping Table

| AI Fancy Character | Human "unslop" Equivalent | Byte Change |
| --- | --- | --- |
| `“` / `”` (Smart Quotes) | `"` (Standard Quote) | 3 bytes → 1 byte |
| `‘` / `’` (Single Smart) | `'` (Apostrophe) | 3 bytes → 1 byte |
| `—` (Em-dash) | `-` (Hyphen) | 3 bytes → 1 byte |
| `–` (En-dash) | `-` (Hyphen) | 3 bytes → 1 byte |
| `…` (Ellipsis) | `...` (Three dots) | 3 bytes → 3 bytes |

## 🏗 Why Zig?

We chose **Zig** because it treats UTF-8 as a first-class citizen and allows for incredibly efficient byte-level manipulation without the overhead of a virtual machine or a massive runtime. This makes `unslop` fast enough to process thousands of files in the blink of an eye.
