# Goose diagnostics

The checker names both ends of a problem: the reference and where it was
bound, the holder and the line that stored into it, or the instantiation
and the call chain. Read the whole message before editing.

Run `goose check file.goose` for errors without executing anything.
`--diagnostics json` gives the same information as data.

## Contents

1. [A fast debugging loop](#1-a-fast-debugging-loop)
2. [Syntax and names](#2-syntax-and-names)
3. [Types and conversions](#3-types-and-conversions)
4. [Arrays and placement](#4-arrays-and-placement)
5. [References and lifetimes](#5-references-and-lifetimes)
6. [Enums](#6-enums)
7. [Functions, generics, recursion](#7-functions-generics-recursion)
8. [Pools and dictionaries](#8-pools-and-dictionaries)
9. [Threads](#9-threads)
10. [Runtime errors](#10-runtime-errors)
11. [Compiler and toolchain](#11-compiler-and-toolchain)
12. [Habit-to-error map](#12-habit-to-error-map)

---

## 1. A fast debugging loop

1. `goose check file.goose` — silent means it typechecks.
2. Fix the **first** error. Later errors are often consequences.
3. If a lifetime error is unclear, read the "related" note: it names the
   binding the compiler traced the reference to.
4. `goose run file.goose` for output.
5. `goose run --debug file.goose` for overflow, cast-range, and tag checks.
6. `goose build file.goose` for threads, timing, and a real executable.
7. `goose check --stats` or `--bce-lines` when performance is the issue.

## 2. Syntax and names

| Message | Cause | Fix |
|---|---|---|
| `';' expected after expression, found '!'` | macro syntax from another language, e.g. `println!("x")` | `print("x")` |
| `unknown type: Vec` | heap container from another language | `i64[>..]`, `u8[>..]`, `dictionary<K, V>` |
| `cannot find the module nosuch` | missing `import`, or wrong package name | add `import nosuch;`, or declare the package in the root file |
| `unknown function or member: push_str` | method from another language | `append` (`s.append("x")`) |
| `P has no field y` | field name typo | use a declared field |
| `duplicate initializer for field x` | field listed twice | list it once |
| `cannot assign to let x` | reassigning a `let` | declare with `var` |
| `expression expected, found 'type'` | `type` alias inside a function | move it to top level |
| `top-level declaration expected` | declaration after a statement, or an unsupported keyword | keep declarations at top level |
| `variable s may be used before it is assigned` | local `var s: T;` with no initializer | `var s: T = default<T>();` or `let s = T { .. };` |

A `let` binding still allows writes into its contents:

```goose
let xs = [1, 2, 3];
xs[0] = 9;             // fine
```

## 3. Types and conversions

| Message | Cause | Fix |
|---|---|---|
| `operands of + have no common type: u32 and i32` | no cross-width promotion | `a as i64 + b as i64` |
| `expected a value of type u8, got i64 (narrowing and sign changes require an explicit 'as')` | narrowing assignment | `x as u8`, or `x as! u8` to skip the check |
| `expected a value of type i64, got const u8[:]` | returning a string where a number is expected | parse it, or change the result type |
| `an integer is expected here, got f64` | float used as index/range bound | cast or use an integer |
| `condition must be bool or an optional, got i64` | `if n` on an integer | `if n != 0` |
| `operator + cannot be applied to i64? and i64` | optional used before narrowing | `guard x else { ... }` or `if x { ... }` |
| `no matching overload for call to f` | wrong argument count or types | read the candidates below the error; cast or fix the call |
| `redundant 'as i64'` (warning) | cast the type rules already allow | remove it |

Casts:

- `x as T` is range-checked under `--debug`, and truncates or wraps in
  release.
- `x as! T` never checks.
- A redundant cast is a warning, which is a hint that the compiler already
  converts.

## 4. Arrays and placement

| Message | Cause | Fix |
|---|---|---|
| `arrays of variable-size elements cannot be indexed, only iterated; for random access, keep your own array of references to them` | `u8[][>..]`, `Enum..[>..]`, `Record[>..]` | iterate; or keep `(T&)[>..]` beside it; or use fixed-size elements (`u8[..k]`) |
| `resizable field a of struct S must be the final field; use root struct for independently stored fields` | two resizable fields, or a resizable field before another | move it last, or use `root struct` |
| `no matching overload ... cannot pass i32[4] as i64[:]` | slice element types must match exactly | widen/copy to `i64[4]`, or change the parameter |
| `cannot write p: a by-value binding is a copy of the element; bind it by reference (&p) to write the element` | `for p in xs` over fixed-size elements | `for &p in xs` |
| `an integer is expected here, got const u8[:]` | indexing with a string | use an integer |
| `index N out of bounds` (runtime) | bad index | check `.len`, or use `%`, or fix the logic |

Placement reminders:

- A resizable value may be a local, a global, a by-value parameter, a
  result, or the last field of an ordinary struct. Never an array element.
- A root owner may only be a local or global.
- Elements of `[>..<]`, `[..k]`, and `[..]` must be fixed-size.

## 5. References and lifetimes

| Message | Cause | Fix |
|---|---|---|
| `storing a reference rooted at inner, which does not outlive the destination` | the target's owner is in an inner scope | move the owner up, return by value, or `copy` the value |
| `cannot pop xs while s is still used: it may hold a reference or slice into it` | live view across a shrink | finish with `s` first, or re-take it after |
| `storing a reference rooted at key, which does not outlive the destination` | a slice key taken from a by-value loop copy; sometimes followed by `while checking this standard library expression` | iterate with `for &r in records`, or key by inline `u8[..k]` |
| `cannot call insert, which shrinks d while r ... is still used` | reference into a resizable dictionary | use `update`, or finish with `r` |
| `.index_of needs a reference rooted at the array itself` | reference came from another array or a pool slot | use the pool's index (`alloc_index`), or `pool.free_ref(r)` |
| `cannot bind the payload of fixed-mode E by reference` | `&` binder on a fixed-mode enum | bind by value, or store as `E..` |
| `cannot assign through this path (const, or a read-only instantiation)` | writing through `const` | make the slot or view writable |
| `storing a read-only slice of type u8[:] ... in a slot of type u8[:]; declare the slot const` | a field/slot accepts only writable views | declare it `const u8[:]` (or copy into `u8[..k]`) |
| `copying a value ... which contains self-relative references, is not supported; construct it in place, or bind a reference to it with .=` | copied a node that holds `T&<uN>` links | `let n .= pool.push(...)`, or build it in the destination |

The checker looks at the last use, not the lexical scope. A view whose last
use is before the mutation needs no block around it.

```goose
var xs: i64[>..] = [1, 2, 3];
let s = xs[1..];
print(s);
xs.pop();              // fine: s's last use is behind the pop
```

## 6. Enums

| Message | Cause | Fix |
|---|---|---|
| `cannot bind the payload of fixed-mode E by reference` | fixed mode can be overwritten, so nothing may point in | bind by value, or use `E..` |
| `match does not cover variant X` | non-exhaustive match | add the arm or `_` |
| a variable-size payload rejected in fixed mode | a string cannot live in a fixed-size enum | store the enum as `E..` |
| `cannot assign ... variant` on a variable-mode value | packed neighbours forbid changing size | use fixed mode, or rebuild the container |

Storage choice:

- Fixed mode: indexable, replaceable, binds payloads by value, fixed-size
  payloads only.
- Variable mode: packed to each variant, never replaceable, permits
  references into payloads and variable-size payloads, sequential arrays.

## 7. Functions, generics, recursion

| Message | Cause | Fix |
|---|---|---|
| `recursive call cycle through walk, which is not declared 'recursive fn'` | recursion is opt-in | mark the cycle's entry `recursive fn` |
| `... calls into its recursive cycle while non-fixed-size local t ... is in scope: end its scope before the call` | growable data held across recursion | end the scope, pass a pool, or use a shared grow-shrink stack |
| `several values exist only in 'return a, b;' and in a call's results, so a block or branch cannot end in 'a, b'` | treating multiple results as a tuple | return from each branch |
| `no matching overload` with type-chain notes | generic instantiation failed | read the instantiation chain; the deepest note names the real mismatch |
| `checkfree fn f keeps a bounds check: nothing shows 1 < xs.len` | `checkfree fn` with an unproven index | add an `assert`, or drop `checkfree` |
| function value stored or returned | function values are compile-time | store an enum tag and dispatch, or pass the function down |

Recursion checklist:

1. Entry marked `recursive fn`.
2. Every function in the cycle has a written signature.
3. No growable local is live across a call back into the cycle.

## 8. Pools and dictionaries

| Message | Cause | Fix |
|---|---|---|
| `... while r ... is still used` after a dictionary mutation | reference into the slot array | use `update`, or finish with `r` |
| `free` index out of range (runtime) | bad slot index | keep the index returned by `alloc_index` |
| wrong-pool `free_ref` | reference does not trace to that pool | free by index |
| `slice_pool.free_slice: slice is not from this pool` (runtime) | slice from another pool or a stale run | track ownership; free the original run |
| `slot_pool` element rejected | elements must be fixed-size | use `slice_pool` for variable-size content |
| a root owner copied, returned, or nested | roots are local/global only | pass `Root&`, or make the fields ordinary locals |

Pool facts that surprise people:

- `free` releases no memory; it records an index for reuse.
- A freed slot stays initialized. A stale reference reads a later value.
- `items.len` is a high-water mark, including free slots.
- `realloc_slice` may move a run. Keep offsets, not slices, across it.

## 9. Threads

| Message | Cause | Fix |
|---|---|---|
| `goose run` refuses a threaded program | TinyCC cannot place thread-local storage | `goose build file.goose` |
| a job/result type rejected | values crossing threads must be flat | remove references and slices at every depth |
| a global does not change in `main` | each worker has its own copy | send a message back through a queue |
| `main-thread-only` package called from a worker | `gfx`, `ui`, `audio`, `physics` rule | keep those calls on the main thread |
| `thread_wait` loses a contained worker's message | the first wait takes it | wait once, with the message buffer |

## 10. Runtime errors

A failed check aborts with a message and the source line:

```
goose runtime error: index 5 out of bounds (length 3) (prog.goose:12)
goose runtime error: as conversion out of range (debug): 300 as u8 (prog.goose:1)
goose runtime error: assert failed (prog.goose:7)
```

`--debug` enables overflow, cast-range, and tag checks. These abort in
every build: division by zero, a limited array's capacity overflow,
shrinking below empty, a relative offset that does not fit its width, a
failed `assert`, and data-stack exhaustion.

A data-stack exhaustion message names `--stack-reserve`. Raise it if the
program legitimately needs more, but first check for accidental growth or
a runaway recursion.

## 11. Compiler and toolchain

| Message or symptom | Fix |
|---|---|
| `goose` not found | put the unpacked release on `PATH`; or use `build/Release/goose.exe` |
| standard library not found | set `GOOSE_STDLIB` or pass `--stdlib`; keep `stdlib/` beside the compiler; a build tree outside the source tree needs the checkout's `stdlib/` |
| no C compiler for `build` | `goose toolchain`; install MSVC/clang/gcc; or pass `--cc` |
| C compile or link failure | `goose build -v`; `goose build --dry-run`; read the log path in the error |
| package not fetched | `goose fetch file.goose`; check `git`; remove `--offline` |
| LSP reports a missing package | `goose fetch`; the LSP never fetches |
| `root struct` or `defer expr;` fails to parse | the compiler is the older `v2026.3` release | build Goose from main, or avoid those features |
| stale build after moving the compiler | `GOOSE_HOME` caches; delete it, or set a new one |

Exit codes: `run` returns the program's code (0, `exit(code)`, or 1 on
abort or compile error); `build`, `check`, and `fetch` return 0 or 1;
`format --check` returns 1 when a file needs formatting.

## 12. Habit-to-error map

| You wrote | Goose wants |
|---|---|
| `Vec<T>`, `std::vector<T>` | `T[>..]` (or `T[>..<]` if it pops) |
| `String`, `std::string` | `u8[>..]` builder, `u8[]` stored, `u8[..k]` inline |
| `&str`, `string_view` | `u8[:]` |
| `HashMap`, `unordered_map` | `dictionary<K, V>` |
| `std::map`, `std::set`, ordered iteration | `dictionary` plus an explicit `sort` of materialized entries |
| `std::cout << double`, `printf("%f")` | `print` gives shortest round-trip text; `format_flt(out, v, n)` for fixed decimals |
| `Box<T>`, `unique_ptr`, `new` | a local, or a node in `T[>..]` |
| `Rc`, `shared_ptr` | `slot_pool<T>` and explicit `free` |
| `Option<&T>`, `nullptr` | `T?`, narrowed by `if`/`guard` |
| `Result<T, E>`, `?` | trailing `bool`, `T?`, or `return E from f` |
| `throw`/`catch` | `return ... from`, or `exception::try` |
| `trait`, `interface`, virtual | `enum` + `match` or case functions |
| `impl`, methods | free functions; `x.f(a)` is `f(x, a)` |
| closure stored in a struct | an enum storing the captured data |
| `clone()` | `copy(x)` |
| `x.push_str(s)` | `x.append(s)` |
| `s.len()` | `s.len` |
| `for (auto& x : v)` | `for &x in xs` |
| `cond ? a : b` | `if cond { a } else { b }` |
| `i++` inside an expression | `++` is a statement |
| `-7 % 3 == -1` | `%` is Euclidean: `-7 % 3 == 2`; use `rem` for C behaviour |
| `float` | `f32` or `f64` |
| `nullptr` for "no value" | `null` for optionals; `-1` for positions by convention |
| `#include`, macros | `import`; builtins are functions, not macros |
| `main(argc, argv)` | `fn main()` and `os::args()` |

If a construct has no direct translation, the nearest Goose shape is
usually an array plus references, an enum plus dispatch, or a pool plus
indices. See `references/patterns.md` for each.
