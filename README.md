# goose-language

An agent skill for [Goose](https://github.com/aardappel/goose), the
memory-safe systems language with no heap allocator, no garbage collector,
and no lifetime annotations.

Goose is new enough that general models do not know it. Asked for a list,
they write `Vec<T>`; asked for a string, they write `String`; asked to
return an error, they reach for `Result`. None of those exist. This skill
gives an agent the mental model first, then exact syntax, then patterns
that compile, and it requires the agent to verify its work with
`goose check`.

```bash
npx skills add immutex/goose-language
```

[![skills.sh](https://skills.sh/b/immutex/goose-language)](https://skills.sh/immutex/goose-language)

## What the skill covers

| Area | What the agent learns |
|---|---|
| Memory | data stacks, scope as the free, why nothing moves, copies are explicit |
| Types | the array family, size classes, placement rules, slices, strings |
| Lifetimes | inferred roots, growth and shrink rules, pools for non-nested lifetimes |
| Data | inline records, `varint`, fixed and variable enums, relative references |
| Code | expressions, `guard`, `defer`, generics, function values, recursion |
| Systems | threads with typed queues, serialization, C interop |
| Tooling | `check` / `run` / `build`, packages, sidecars, formatter, LSP |
| Debugging | the exact compiler messages and the fix for each |

## Install

With the Skills CLI:

```bash
npx skills add immutex/goose-language
```

It works with any agent that reads `SKILL.md` files. To install by hand,
copy this repository to `.agents/skills/goose/` in your project, or to your
agent's global skills directory.

The skill loads only its frontmatter until a task mentions Goose, a
`.goose` file, the Goose compiler, or a port from another language. Then it
loads `SKILL.md`, and the reference files it points to as the task needs
them.

## Structure

```
SKILL.md                  the always-loaded core: model, rules, syntax, workflow
references/
  language.md             the language, topic by topic
  memory.md               ownership, lifetimes, growth, pools, recursion, performance
  stdlib.md               the standard library, module by module
  patterns.md             the shape to reach for, task by task
  tooling.md              CLI, packages, C interop, formatter, LSP
  diagnostics.md          compiler and runtime messages, with fixes
examples/                 nine complete programs, all compiler-checked
scripts/verify.py         re-check every example with a local compiler
```

The split is deliberate. A model does not need the whole language reference
to add a field to a struct, and loading it would waste context. The core
file carries what almost every task needs; the references carry depth.

## Examples

The examples are complete programs, not fragments:

| File | Shows |
|---|---|
| `examples/01_tour.goose` | scalars, arrays, strings, slices, structs, enums, references, control flow |
| `examples/02_records.goose` | inline records, `varint`, format overloads, indexing a sequential array |
| `examples/03_tree.goose` | a binary search tree in one array, relative links, recursion, serialization |
| `examples/04_pools.goose` | `slot_pool`, `slice_pool`, and a document store built from both |
| `examples/05_parser.goose` | recursive descent with nested functions and `return ... from` |
| `examples/06_wordcount.goose` | arguments, files, dictionary keys as slices, sorting |
| `examples/07_threads.goose` | a worker pool and typed queues |
| `examples/08_libs.goose` | JSON, regex, CSV, base64, and binary reads and writes |
| `examples/09_meta.goose` | compile-time reflection with `const for` and `const if` |

All nine pass `goose check`. Eight run under the in-process JIT; the
threads example needs `goose build`.

## Verification

The skill targets Goose `v2026.4` and the `main` branch after it. Every
example is checked against the `v2026.4` release and against a compiler
built from `main`; the snippets in `SKILL.md` and `references/patterns.md`
were compiled in a combined test program. Two fresh-agent trials (a
statistics program and a C++ inventory port) then ran with only the skill
for guidance. Their findings, including dictionary key lifetime, hash-order
iteration and float printing, are now covered.

```bash
python scripts/verify.py --goose /path/to/goose --run
```

If you change an example, run that script before committing.

**Compiler version matters.** `v2026.4` added `root struct`, statement-form
`defer` and `const if`, all of which the standard library and this skill
use. Older releases will fail to parse them. Use `v2026.4` or newer, or
build from `main`:

```bash
git clone https://github.com/aardappel/goose
cd goose
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

`goose version` prints the revision, so an agent can tell which it has. One
addition here is newer than `v2026.4`: `slice_pool.trim`, which the skill
lists with that note.

## What to ask it

The skill triggers on Goose work, including ports:

- "Write a Goose program that reads a CSV and prints the ten most common values."
- "Port this C++ octree to Goose. Keep it allocation-free."
- "This Goose code fails with 'storing a reference rooted at inner'. Fix it."
- "Add a worker pool to this Goose program."
- "Review my .goose file for lifetime mistakes."

## Design notes

- The core file starts with the memory model because syntax errors are
  cheap and model errors are not. An agent that understands data stacks
  stops writing pointers, destructors, and implicit copies.
- Every rule has its failure message nearby. The diagnostics reference maps
  the compiler's exact wording to a cause and a fix, including the spec
  section it cites.
- Examples are compiled, not illustrative. Several snippets in the
  reference were corrected against the compiler during writing, including
  the `u8[:]` field that needed `const`, and a node returned by reference
  that needed `.=` rather than `=`.
- The skill says when code is unverified. An agent without a Goose compiler
  should admit that rather than claim a clean build.

## License

MIT. The Goose language and its documentation are Apache-2.0, by Wouter
van Oortmerssen and contributors.
