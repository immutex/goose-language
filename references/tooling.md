# Goose tooling

One executable, `goose`, is the compiler, the in-process runner, the build
tool, the package fetcher, the formatter, and the language server.

## Commands

```bash
goose file.goose [options] [-- program args...]   # run in-process
goose run file.goose [-- args...]
goose build file.goose [-o exe]
goose check file.goose
goose fetch file.goose
goose format file.goose|dir...
goose toolchain
goose version
goose lsp
goose completion bash|zsh|fish|powershell
goose help [command]
```

Options may come before or after the file. Everything after `--` belongs
to the program.

| Command | Use |
|---|---|
| `run` | fastest feedback with output; JIT through bundled TinyCC |
| `check` | parse and typecheck only; silent on success |
| `build` | native executable; required for threads and timing |
| `fetch` | download packages for a later offline session |
| `format` | rewrite files in the standard layout |
| `lsp` | editor integration over stdio |

## Options for run, build, and check

| Option | Effect |
|---|---|
| `-O0`, `-O1`, `-O2` | how much the Goose compiler inlines (build defaults `-O2`, run `-O1`) |
| `--debug` | overflow, range, and tag checks; debug info in a build |
| `-D NAME[=VALUE]` | define a C macro in the generated program |
| `--stack-reserve size` | address space per data stack (default 2G) |
| `--stacks` | report data stacks used |
| `--bce-lines` | report bounds checks removed and kept per line |
| `--no-bce` | keep every bounds check |
| `--specs` | print every specialization after optimization |
| `--stats` | compile statistics, including bounds checks elided |
| `--color auto\|always\|never` | color control |
| `--diagnostics text\|json` | JSON diagnostics for tools |
| `--offline` | fetch nothing |
| `--update` | re-fetch tag/branch packages |
| `--stdlib dir` | alternate standard library |
| `--cc name\|path` | C compiler for builds |
| `-v` | print the commands that build C |

`--diagnostics json` prints an array of objects with `severity`, `message`,
`file`, `line`, `col`, `endLine`, `endCol`, `related`, and `text`.

## Build options

| Option | Effect |
|---|---|
| `-o exe` | executable path |
| `--debug` | checked build with debug information |
| `--cc name\|path` | `msvc`, `cl`, `clang-cl`, `clang`, `gcc`, `cc`, or a path |
| `--standalone` | compile the runtime into the program |
| `--dry-run` | print the commands and run none |

The C compiler is chosen from `--cc`, then `GOOSE_CC`, then `cc = "...";`
in `~/.goose/config`, then the first found on the machine. `goose toolchain`
reports the choice and why.

## Writing the C yourself

```bash
goose -o tour.c tour.goose                 # program C, does not run
goose --emit-runtime goose_runtime.c       # runtime C, build once
cc -O2 -c goose_runtime.c
cc -O2 tour.c goose_runtime.o -o tour -lm -pthread
```

- `--standalone` writes C that contains the whole runtime.
- `--header out.h` writes a header for a C host; the generated C then has
  no `main`. The host calls `goose_init(argc, argv)` once, then the exported
  functions, then `goose_exit()`.
- `--include header.h` splices a header into the generated C.
- `--jit` also runs the program.

## Formatting

```bash
goose format src/
goose format --check .
goose format < in.goose > out.goose
```

`goose format` changes indentation, token spacing, blank lines, and
trailing commas. Line breaks stay. A file that does not parse is left
alone. Exit status is 0 when formatted, 1 when `--check` finds an
unformatted file, 2 on a parse or I/O error.

## Language server

```bash
goose lsp
```

Diagnostics as files change, hover, go to definition, references, rename,
symbols, semantic highlighting, signature help, completion, inlay hints,
folding, code lenses, and formatting. It never fetches packages; run
`goose fetch` first.

## Packages

A package is a directory with `name.goose` as its entry, optionally other
modules and C.

Only the **root file** declares packages:

```goose
import mylib from "joe/mylib@v2";                  // GitHub tag
import mylib from "github.com/joe/mylib@3f2c1a9";  // any host, commit
import mylib from "https://git.example.com/x/mylib.git@main";
import mylib from "../mylib";                      // local directory
```

Other files import by name only (`import mylib;`, `import mylib.extra;`).

`goose fetch program.goose` downloads what the root declares. `--offline`
forbids fetching. A missing tool is named in the error: `git`, `cmake`, or
a C compiler.

## A program's own C

Put `foo.build` beside `foo.goose`:

```
c_sources = ["impl.c", "vendor/stb_impl.c"];
c_include = ["vendor"];
c_defines = ["IMPL_FAST=1"];
c_flags_cc = ["-mavx2"];
c_libs = ["m"];
c_libs_windows = ["user32"];
dylibs_linux = ["SDL2=libSDL2-2.0.so.0"];
output = "foo";
```

Keys accept `_windows`, `_linux`, and `_macos` suffixes. Then:

```goose
extern fn impl_sum(a: i32, b: i32) -> i32;
```

A package's sidecar may instead name `cmake_target`, `c_headers`, or
`main_thread_only = true;`.

`extern "name" { ... }` loads functions from a shared library by name at
program start; no C is compiled.

## Environment

| Variable | Effect |
|---|---|
| `GOOSE_HOME` | packages, build intermediates, settings (default `~/.goose`) |
| `GOOSE_CC` | C compiler when `--cc` is absent |
| `GOOSE_STDLIB` | standard library directory |
| `GOOSE_PROGRESS` | `plain` or `live` progress output |
| `NO_COLOR` | disable color |
| `CLICOLOR_FORCE` | force color |
| `GOOSE_TCCLIB` | TinyCC headers for a relocated compiler |

## Exit status

| Command | Status |
|---|---|
| `run` | the program's: 0 on return, `exit(code)`, 1 on abort or compile error |
| `build`, `check`, `fetch`, `-o` | 0 on success, 1 on an error |
| `format` | 0 clean, 1 unformatted under `--check`, 2 parse/IO error |
| `toolchain` | 1 when no C compiler |

## Installing

Prebuilt compilers for Windows x64, Linux x64, macOS arm64, and macOS x64
are on the Goose releases page. Unpack anywhere and put the directory on
`PATH`. The compiler finds the standard library, TinyCC's runtime, and
packages beside itself, and keeps builds under `~/.goose`.

Running in-process needs nothing else on Windows; on Linux it needs libc
headers, and on macOS the Xcode command-line tools SDK. `goose build` needs
a C compiler (MSVC or clang on Windows, gcc or clang elsewhere).

From source: CMake 3.27+, a C++20 compiler, and Python 3.

```bash
git clone https://github.com/aardappel/goose
cd goose
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGOOSE_BUILTIN_LIBS=all
cmake --build build --config Release
build/goose samples/01_tour.goose
```

## When something is wrong

| Symptom | Check |
|---|---|
| `goose` not found | release unpacked and on `PATH`; or `build/Release/goose.exe` |
| "cannot find the standard library" | `GOOSE_STDLIB` or `--stdlib`; releases keep `stdlib/` beside the exe |
| threads fail to run | use `goose build`, not `goose run` |
| build fails at the C step | `goose toolchain`; install or select a C compiler with `--cc` |
| package will not fetch | `git` present; network; `--offline` not set |
| program runs out of data stack | `--stack-reserve 16G`; `--stacks`; find accidental growth |
| a kernel is slower than expected | `--bce-lines`; add one `assert` on lengths |

## Testing a Goose program

The compiler's own suite is Python-driven (`test/run_tests.py`), and the
samples have `samples/run_samples.py`. For application code, the practical
pattern is a `test/` directory of root files, each with a `main` that
asserts and prints, run by a small script:

```bash
for f in test/*.goose; do goose run "$f" || exit 1; done
```

`assert` aborts with a message and the source line, which makes a failed
test obvious in CI.
