---
name: goose
description: Write, read, review, debug, and port code in Goose, the memory-safe systems programming language by Wouter van Oortmerssen (source files end in .goose; the compiler is `goose`). Use this whenever a task involves Goose source, a .goose file, the Goose compiler or standard library, or translating C, C++, Rust, Go, or Zig into Goose, including when the user says only "Goose" and means the language rather than Block's AI agent. Covers the data-stack memory model, the array family, references and lifetimes, enums, pools, generics, threads, serialization, C interop, and the check/run/build workflow.
license: MIT
---

# Goose

Goose is a compiled systems language. It has no heap allocator, no garbage
collector, no reference counting, no destructors, and no lifetime
annotations. Memory is the native call stack plus a small number of
compiler-managed **data stacks**. Values nest inline, growth is a pointer
bump, and a scope exit is the free.

That single design decision explains almost every rule below. When code
will not compile, the cause is usually a heap-shaped assumption rather than
a syntax mistake.

## First, find the toolchain

```bash
goose version                 # compiler present?
goose check file.goose        # parse + typecheck only; silent on success
goose run file.goose          # JIT via bundled TinyCC; no C compiler needed
goose build file.goose        # native executable; required for threads
```

`goose check` is the fastest feedback loop: it runs no code and prints
nothing on success. Warnings (for example a redundant cast) still print but
do not fail the check. Use it after every edit. Use `goose run` when output
matters, and `goose build` for threads, timing, or a real executable.

If `goose` is not on PATH, look for a release unpacked under `~/.goose`, a
`build/` directory in a Goose checkout (`build/Release/goose.exe` on
Windows), or ask the user where it is. A release finds the standard library
beside the executable. A compiler built in a build tree **outside** the
source tree does not; point it at the checkout:

```bash
GOOSE_STDLIB=/path/to/goose/stdlib      # or --stdlib /path/to/goose/stdlib
```

`--stdlib` and `GOOSE_STDLIB` always override the search.

Run `goose version`. A version like `v2026.3-293-g335fddc1` or newer is
what this skill targets. The plain `v2026.3` release is older: it predates
`root struct` (which the standard-library pools use) and statement-form
`defer`. If `goose version` prints only `goose runtime <hash>`, expect
those features to fail and use syntax from the release's own docs.

## The mental model

1. **Every dynamic value is owned by a variable** — a local, a global, a
   by-value parameter, or a field/element of one. There is nowhere else for
   it to live.
2. **A scope exit frees everything that scope pushed**, in one pointer
   store. No destructors run, so external resources (files, GPU handles)
   are released explicitly.
3. **Nothing moves.** A resizable value is always the top of its data
   stack, so `push` never reallocates and references into a growing
   `T[>..]` stay valid forever.
4. **Values are inline and packed.** A string inside a struct inside an
   array is bytes inside bytes inside bytes, with no pointers between them.
5. **References carry an inferred root** — the variable that owns their
   target. They may not outlive it. You write no lifetimes, and there are
   no aliasing or exclusivity rules.

## Rules that prevent most failures

- **No heap vocabulary.** There is no `new`, `Box`, `Vec`, `String`,
  `HashMap`, `malloc`, or `Rc`. A growable array is `T[>..]`; a string is a
  `u8` array; a map is `dictionary<K, V>`.
- **Pick the array by what its size does**, not by habit:

  | Type | Size behaviour | Use for |
  |---|---|---|
  | `T[k]` | fixed at compile time | matrices, tables |
  | `T[]`, `T[varint]` | sized once, frozen | finished strings, records, nodes |
  | `T[..k]`, `T[..]` | inline capacity, grows within it | small buffers inside structs |
  | `T[>..]` | grow-only; references stay valid | the default: arenas, builders, pools |
  | `T[>..<]` | grow and shrink | stacks, queues, heaps |

- **An array of variable-size elements is sequential.** `u8[][>..]` and
  `Shape..[>..]` can be iterated, not indexed. Keep a second array of
  references to index them.
- **`for x in xs` copies fixed-size elements and binds variable-size ones by
  reference.** Use `for &x in xs` whenever you need a reference. A slice
  that views bytes *inside* the element points into the copy and dies with
  the iteration, so a dictionary key taken from it will not compile. A
  `const u8[:]` field is only a header: copying the element leaves its
  target alive, so that case works either way. The array being iterated
  must also outlive anything you store from it; bind a literal to a `let`
  first.
- **Only one resizable value per data stack, and one resizable field per
  ordinary struct**, as its last field. For several, use a `root struct`.
- **`let` stops reassignment, not mutation.** `let xs = [1,2,3]; xs[0] = 9;`
  is legal. `const T` makes the contents read-only.
- **Non-fixed values never copy implicitly.** `var b = a;` aliases `a`.
  Write `copy(a)` for an O(n) copy you can see.
- **References are transparent.** No `*` or `->`. Use `.=` to bind or
  retarget a reference, and `.==` to compare identity.
- **Arithmetic runs at the operands' width.** Nothing promotes to 64 bits.
  `u8 + u8` is an 8-bit add; `u32 + i32` is an error; narrowing needs
  `as` (checked in debug) or `as!` (unchecked). `%` is Euclidean.
- **Function values are compile-time only.** Pass a function or trailing
  block as a generic parameter; you cannot store, return, or put one in
  data. Dynamic behaviour is an enum plus `match` or case functions.
- **Recursion is opt-in.** Mark the cycle's entry `recursive fn`, write
  every signature in the cycle, and keep growable locals out of the
  recursive path.
- **`if` needs a `bool`.** `if n` with an integer is an error; write
  `if n != 0`.

## Syntax that differs from C-family habits

Most programs that use text, sorting, parsing, or collections start with
`import std;`, plus `import dictionary;`, `import slot_pool;`, or
`import slice_pool;` as needed.

```goose
let answer = 42;            // immutable binding
var count: i32 = 0;         // mutable variable
const limits = [1, 2, 3];   // contents read-only

fn total(xs: i64[:]) -> i64 { var t = 0; for x in xs { t += x; } return t; }

struct Point { x: f64, y: f64 = 0.0 }
let p = Point { x: 1.5 };              // y defaults to 0.0
let q = Point { x: 1.5, .. };          // every omitted field gets its default

enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }
let s = Shape.Circle { r: 2.0 };

fn area(s: Shape.Circle) -> f64 { 3.14159 * s.r * s.r }   // case function
fn area(s: Shape.Rect) -> f64 { s.w * s.h }

let kind = if p.x > 0 { "right" } else { "left" };         // if is an expression
let name = match count { 0 => "none", 1..9 => "few", _ => "many" };

guard count > 0 else { return; }        // the rest needs count > 0
let v = block { guard count > 0 else { break 0; }; count * 2 };
defer cleanup();                        // runs on every exit from this block

for i in 5 { }              // 0..4
for i in 10..13 { }         // 10, 11, 12
for x, i in xs { }          // value and index
for &x in xs { x *= 2; }    // mutate elements

var a: i64[>..] = [];
a.push(1);
a.append([2, 3]);
let first .= a[0];          // bind a reference
first += 10;                // writes a[0]
print(a.len, " ", a);       // print renders any value
```

Calls can use method syntax for any free function: `xs.sort()`,
`d.insert(k, v)`, `2.5.describe()`.

Multiple results are a calling convention, not a tuple:

```goose
fn divide(a: i64, b: i64) -> i64, bool {
    if b == 0 { return 0, false; }
    return a / b, true;
}
let q, ok = divide(7, 2);
```

## Idioms to reach for

**Build in place.** Returning a growable value writes it directly into the
caller's destination; out-parameters are rarely needed.

```goose
fn squares(n: i64) -> i64[>..] {
    var out: i64[>..] = [];
    for i in n { out.push(i * i); }
    return out;
}
```

**Records: one block, no pointers.**

```goose
struct Item  { sku: u8[varint], qty: varint, cents: varint }
struct Order { id: varint, customer: u8[varint], items: Item[varint] }
```

**Trees and graphs: nodes in an array, narrow links.**

```goose
struct Node { key: i32, left: Node&<u32>?, right: Node&<u32>? }

fn add(pool: Node[>..]&, key: i32) -> Node& {
    return pool.push(Node { key: key });   // stays valid across every later push
}

var tree: Node[>..] = [];
let root .= add(tree, 5);                  // .= binds the reference; = would copy
```

**Deep errors: `return E from f`.** The frames in between keep plain
signatures.

```goose
struct User { name: const u8[:], age: i32 }

fn load(text: u8[:]) -> User[>..], u8[] {
    var users: User[>..] = [];
    // ... users.push(parse(line)); ...
    return users, "";
}

fn parse(line: u8[:]) -> User {          // no Result, no error parameter
    guard line.len > 0 else { return [], "empty line" from load; }
    return User { name: line, age: 0 };
}
```

**Higher-order code: trailing blocks.** `filter`/`map` build directly in
the receiving variable, and `return` inside a block leaves the enclosing
function.

```goose
let evens = xs.filter() { it % 2 == 0 };
let total = fold(xs, 0) { acc, x => acc + x };
sort(items) { a, b => a.age < b.age };
```

**Lifetimes that do not nest: pools.**

```goose
import slot_pool;

struct Item { id: i32 }
var pool = slot_pool<Item> {};
let i = pool.alloc_index(Item { id: 1 });
let r .= pool.alloc_ref(Item { id: 2 });
pool.free(i);                       // freelist only; slots stay valid
```

## Error messages are precise — read all of them

The checker names both ends of a problem and the spec section. Examples:

| Message | Meaning | Fix |
|---|---|---|
| `arrays of variable-size elements cannot be indexed, only iterated` | element size varies | iterate, or keep an index array of references |
| `storing a reference rooted at inner, which does not outlive the destination` | reference outlives its owner | move the owner up, or copy into the destination |
| `cannot pop xs while s is still used` | a live view would be invalidated | finish with `s`, or re-take it after |
| `resizable field a ... must be the final field` | two resizable fields in a struct | reorder, or use `root struct` |
| `recursive call cycle through walk, which is not declared 'recursive fn'` | recursion is opt-in | add `recursive fn` and full signatures |
| `... while non-fixed-size local t ... is in scope` | growable held across a recursive call | end the scope, or pass a pool |
| `operands of + have no common type: u32 and i32` | no cross-width promotion | cast one side with `as` |
| `condition must be bool or an optional, got i64` | integer used as condition | write `if n != 0` |
| `cannot write p: a by-value binding is a copy of the element` | wrote to a `for x in xs` copy | use `for &x in xs` |
| `cannot bind the payload of fixed-mode E by reference` | `&` binder on fixed mode | bind by value, or store as `E..` |
| `storing a reference rooted at key, which does not outlive the destination` | a slice key came from a by-value loop copy | use `for &r in records`; see `references/diagnostics.md` |

`references/diagnostics.md` has the full table, including lifetime, pool,
placement, and package errors, plus the flags that explain them.

## What to read next

Load only what the task needs:

| File | Read it when |
|---|---|
| `references/language.md` | you need exact syntax or semantics for any feature |
| `references/memory.md` | ownership, lifetimes, growth, pools, recursion, or performance is the problem |
| `references/stdlib.md` | you need the signature of a standard-library function |
| `references/patterns.md` | you want a complete, compiling program for a common task |
| `references/tooling.md` | CLI flags, packages, C interop, the formatter, or the LSP |
| `references/diagnostics.md` | a compile or runtime error needs explaining |
| `examples/` | you want runnable reference programs to copy from |

## Before you answer

- Run `goose check` on every file you wrote or changed. Do not claim a
  program works without seeing either a clean check or its output.
- If you cannot run the compiler, say so and mark the code unverified.
- Prefer a smaller program that checks clean over a larger one that
  "should" work.
