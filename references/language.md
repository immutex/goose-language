# Goose language reference

A working reference for writing Goose. For exact rules and the reason a
program was rejected, the upstream specification is
`docs/goose_spec.md` in the Goose repository.

## Contents

1. [Lexical structure](#1-lexical-structure)
2. [Declarations](#2-declarations)
3. [Types](#3-types)
4. [Scalars and arithmetic](#4-scalars-and-arithmetic)
5. [Arrays](#5-arrays)
6. [Strings and text](#6-strings-and-text)
7. [Slices](#7-slices)
8. [Structs](#8-structs)
9. [Enums](#9-enums)
10. [References and optionals](#10-references-and-optionals)
11. [Relative references](#11-relative-references)
12. [Control flow](#12-control-flow)
13. [Functions](#13-functions)
14. [Generics and function values](#14-generics-and-function-values)
15. [Recursion](#15-recursion)
16. [Errors](#16-errors)
17. [Program structure](#17-program-structure)
18. [Threads](#18-threads)
19. [Serialization](#19-serialization)
20. [C interop](#20-c-interop)
21. [Builtins](#21-builtins)
22. [Keywords and operators](#22-keywords-and-operators)

---

## 1. Lexical structure

- Source is UTF-8. Line endings are normalized.
- Comments: `//` to end of line; `/* ... */` nests.
- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`.
- Integer literals: decimal or `0x` hex; character literals are integer
  byte constants (`'a'` is 97).
- Float literals: `1.5`, `2.5e-3`, `1e9`, and C99 hex floats (`0x1.8p3`).
  `1..2` is a range, not a float.
- Strings: `"..."` with `\n \t \r \0 \\ \" \'` and `\xNN`.
- Raw strings: `"""..."""`, no escapes, closing indentation stripped.
- `true`, `false`, `null`, and `self` (only inside a literal being
  constructed).

Statements end in `;`, except a construct that ends in a block (`if`,
`match`, `block`, a loop, `guard ... else { }`, a nested `fn`, or a call
with a trailing block). Put such a construct in parentheses to use it as
an operand:

```goose
let v = (if a > 2 { 1 } else { 2 }) + 3;
```

Everything evaluates left to right. Trailing commas are accepted in every
bracketed, comma-separated list.

---

## 2. Declarations

```goose
let answer = 42;              // cannot be reassigned
var count: i32 = 0;           // can be reassigned
const limits = [10, 20];      // neither reassigned nor written into

let xs = [1, 2, 3];
xs[0] = 9;                    // legal: let stops `xs = ...`, not element writes

const ys = [1, 2, 3];
// ys[0] = 9;                 // error: const contents
```

A `let` without an initializer gets a value exactly once, on every path,
checked statically:

```goose
let n: i64;
if ready { n = 1; } else { n = 2; }
```

Locals must be initialized before use. Globals may be declared with only a
type and start at that type's default:

```goose
var log: u8[>..];             // empty
var selected: Unit;           // zeroed fields, declared defaults applied
```

Globals initialize before `main`, imported files first, then declaration
order. Their initializers may call functions.

**Named constants**: an untyped `let`/`const` global with a constant
initializer adapts like a literal and can size arrays.

```goose
let SIZE = 16;
let HALF = SIZE / 2;
var grid: u8[SIZE] = [0; SIZE];
let b: u8 = SIZE;              // adapts
```

**Type aliases**: `type Id = u32;` — the same type, not a new one.

---

## 3. Types

Postfix type syntax:

| Written | Meaning |
|---|---|
| `i8 i16 i32 i64`, `u8 u16 u32 u64`, `f32 f64`, `bool`, `varint` | scalars |
| `T[4]`, `T[]`, `T[varint]`, `T[..8]`, `T[..]`, `T[>..]`, `T[>..<]` | array family |
| `T[:]` | slice |
| `Point`, `Pair<i64>` | struct, generic struct |
| `Shape`, `Shape..`, `Shape.Circle` | enum fixed mode, variable mode, variant |
| `T&`, `T?` | reference, optional reference |
| `T&<u32>`, `T&<u32 in pool>`, `T&<u32>?` | relative references |
| `const T`, `const T&`, `const T[:]` | read-only contents |
| `u32 in a`, `u32 upto a` | index type, bound type |
| `fn(i64) -> bool` | function value shape (documentation only) |

`const` applies to the first reference or slice over the base type:
`const u8[:]` is a read-only view. For an outer reference, parenthesize:
`const (u8[:])&`. An array of an index type is `(u32 in a)[>..]`.

A type never contains itself by value; it may refer to itself through a
reference or slice:

```goose
enum List { Nil, Cons { v: i64, next: List? } }   // fine
```

---

## 4. Scalars and arithmetic

- `i64` is the conventional type for counts, sizes, and indices. `.len` and
  integer literals are `i64`. Narrower types are for compact data and
  kernels that need a width.
- **A literal has no type of its own.** It adapts to any integer type that
  holds it, and is `i64` where nothing constrains it. `let x: u8 = 256;` is
  an error.
- **Arithmetic runs at the operands' width.** `u8 + u8` is 8-bit.
  `u32 + i32` is an error, not a promotion to 64 bits.
- Unifying rules, in order: equal types; literal adapts to the other side;
  exactly one side widens implicitly; integer meets float and converts;
  otherwise a cast is required.
- Shifts: the result has the left operand's type; the count is masked.
- **`%` is Euclidean**, always in `[0, |b|)`, for every integer type.
  `-7 % 3 == 2`. Integer `/` truncates toward zero (`-7 / 3 == -2`).
  `std` supplies `rem(a, b)` (pairs with `/`) and `div_euclid(a, b)` (pairs
  with `%`).
- Unsigned arithmetic wraps in every build. Signed overflow aborts under
  `--debug` and wraps in release. Division by zero always aborts.
- `f32`/`f64` are IEEE. `f32` widens to `f64`, never the reverse. Integers
  convert to floats implicitly. Float literals adapt to their destination.
- `bool` is one byte. `&&` and `||` short-circuit. There is no
  integer-to-bool coercion.
- `varint` is a variable-length integer *storage* type for fields and
  elements. Reading gives `i64`; writing only happens at construction.

Conversions:

| Conversion | How |
|---|---|
| wider integer, same signedness | implicit |
| unsigned to strictly wider signed | implicit |
| `f32` to `f64`, any integer to a float | implicit |
| literal/constant into a type its value fits | implicit |
| narrowing, sign change, `f64` to `f32`, float to integer | `as` or `as!` |

`x as T` is range-checked in a debug build and truncates/wraps/rounds
silently in release. `x as! T` never checks. A cast that changes nothing
is a warning, which is useful feedback that the cast was unnecessary.

Memberwise arithmetic works on two values of the same struct or fixed-array
type whose leaves are all integers or all floats. `*` and `/` also
broadcast one scalar. This is how vector types work; there is no operator
overloading.

---

## 5. Arrays

Every array is `[metadata][elements...]`, inline and packed. There is never
a pointer to a separate element block.

| Type | Class | Size behaviour | Metadata |
|---|---|---|---|
| `T[k]` | fixed | compile-time count | none |
| `T[]` | variable | sized at construction, frozen | `u32` length |
| `T[u8]`, `T[u16]`, `T[u32]`, `T[u64]` | variable | same, narrower length | that length |
| `T[varint]` | variable | same, variable-length length | 1 byte usually |
| `T[..k]` | fixed | inline capacity `k` | smallest length type |
| `T[..]` | variable | capacity chosen at construction | length + capacity |
| `T[>..]` | resizable | grow-only | length |
| `T[>..<]` | resizable | grow and shrink | length |

Choosing:

- `T[>..]` is the default: arenas, builders, pools, tree storage, scratch.
  "Grow-only" is a guarantee that references stay valid, not a limit on
  operations; `pop`, `pop_n`, `resize`, and `clear` work where the compiler
  proves nothing points in.
- `T[>..<]` for stacks, queues, and heaps. References into it may live in
  variables only, never in storage, so the compiler can check a shrink.
- `T[..k]` / `T[..]` when the array must sit inline inside something else,
  such as a name field. `T[..k]` keeps the containing struct fixed-size.
- `T[]` / `T[varint]` for finished data built once and then read. A list
  initialized from a literal and never grown is `T[]`; use `T[>..]` if you
  will push to it later.
- `T[k]` for a fixed shape such as a matrix.

Rules:

- Only `T[>..]` and `T[>..<]` are resizable. At most one resizable value is
  live per data stack, so a struct may have one resizable field, last.
- Elements of `T[>..<]`, `T[..k]`, and `T[..]` must be fixed-size.
- Elements of `T[]` and `T[>..]` may be fixed or variable, never
  resizable.
- An array of variable-size elements is **sequential**: iterate it, do not
  index it, and it has no `pop`.
- A stored length must hold the actual count (`T[u8]` holds at most 255).
- `.len` is the count now; `.cap` exists only on `T[..k]` and `T[..]` and
  never changes. A resizable has no `.cap`; it grows until its data stack
  runs out. Pushing past a limited array's capacity aborts.
- Nothing is padded, so elements after a small length are unaligned, and
  Goose's loads allow for it.
- A resizable keeps its data stack until its owner's scope ends, even after
  you stop pushing. Copy it into a `T[]` to finish it:
  `let done: i64[] = copy(grow);`

Literals:

```goose
var fixed: i32[4] = [1, 2, 3, 4];
let zeros: f64[8] = [0.0; 8];        // fill form; v evaluated once
let frozen: i64[] = [7, 8, 9];
var small: u8[..8] = [];
var sized: i64[..] = [..16];         // capacity 16, length 0
var grow: i64[>..] = [];
var stack: i64[>..<] = [];
```

A literal with no destination type is `T[k]` (or `T[]` for variable-size
elements): `[1, 2, 3]` alone is `i64[3]`. `var out = [];` becomes `T[>..]`
whose `T` is fixed by the first `push`, `append`, `format`, or whole
assignment.

Members:

| Member | On | Meaning |
|---|---|---|
| `.len` | all arrays and slices | element count |
| `.cap` | `T[..k]`, `T[..]` | capacity |
| `.push(v)` | limited, grow-only, grow-shrink | append in place; returns `T&` |
| `.append(src)` | same | copy elements of an array, slice, or literal |
| `.move_from(src)` | slices of fixed-size elements | overlap-safe copy, equal lengths |
| `.pop()` | limited, grow-shrink; grow-only where allowed | remove last |
| `.pop_n(n)` | same | remove last `n` |
| `.resize(n, v)` / `.resize(n)` | same | grow with copies, or shrink |
| `.clear()` | same | empty |
| `.index_of(r)` | arrays of fixed-size elements | index of a reference into it |
| `.range_index(s, msg?)` | same | start of a contained slice |
| `.check_length(n, msg?)` | grow-only, grow-shrink | validate a count |

Growth always supplies values; there is no uninitialized slot. Equality is
structural, and arrays of different kinds compare as slices.

---

## 6. Strings and text

There is no string type. A string is a `u8` array:

| Type | Role |
|---|---|
| `u8[>..]` | builder |
| `u8[]`, `u8[varint]` | finished string stored inline |
| `u8[..k]` | small inline string in a struct |
| `u8[:]` | view; a literal is `const u8[:]` |

```goose
var s: u8[>..] = [];
s.append("hello");
s.push(',');
format(s, " world! ", 6 * 7);
let t: u8[] = "fixed";             // a writable copy
let v: const u8[:] = s[..5];       // a view
```

Three builtins render any values, with no format string:

- `print(a, b, ...)` — text plus newline, one write.
- `format(out, a, b, ...)` — append to a growable `u8` array.
- `str(a, b, ...)` — a fresh `u8[>..]`, built at its destination.

A `format` overload `fn format(out: u8[>..]&, v: T)` defines a type's text
form everywhere, including inside arrays. A generic overload over a struct
or variant pattern, such as `fn format<T>(out: u8[>..]&, b: Box<T>)`,
renders every instance of it; a non-generic overload for one instance wins.

`std` adds the string operations: `trim`, `find`, `split`, `words`,
`join`, `parse_int`, `parse_flt`, `format_int`, `compare`, `to_lower`,
`each_split`, `split_once`, `each_utf8`, and more. `split` returns slices
into its input; it copies nothing.

---

## 7. Slices

`T[:]` is a reference plus a count: the universal "process a range"
parameter. Every array kind converts to it without copying.

```goose
a[x..y]        // elements x up to y
a[..y]         // from the start
a[x..]         // to the end
a[^2..]        // last two (^k is len - k)
```

A slice is checked and cannot dangle. Its element type must match exactly:
an `i32[4]` does not pass as `i64[:]`; widen or copy first.

Slices of fixed-size elements index and iterate. Slices of variable-size
elements iterate only.

Slices make good keys because they copy nothing:
`dictionary<const u8[:], i32>` stores addresses and lengths into text you
already hold.

---

## 8. Structs

An ordinary struct is packed data in declaration order:

```goose
struct Unit { kind: i32, hp: i32 = 100, x: f32, y: f32, name: u8[] }

let scout = Unit { kind: 2, x: 1.5, .. };   // hp 100, y 0, name ""
let named = Unit { kind: 2, hp: 50, x: 0, y: 0, name: "scout" };
```

- Fields may declare defaults, evaluated per construction.
- A literal ending in `..` fills every omitted field with its default.
- A `var` global with only a type gets those defaults too.
- A literal may name fields or list them in order.
- `let f: T` marks a field never assigned after construction; `const f: T`
  makes its contents read-only. `pad n` inserts `n` unused bytes, and a
  bare `pad` aligns the next field to its scalar width for foreign layouts.
  Equality ignores pad bytes.

Variable-size fields (`u8[]`, `T[varint]`, `T[]`) sit inline and are frozen
once built. Fixed-size fields assign freely, and a limited array field
(`u8[..k]`) is a builder up to capacity. A field that stores a *view* must
be a `const` slice if the view may be read-only:

```goose
struct Row { name: u8[..24], view: const u8[:], count: i64 }
```

A plain `u8[:]` field accepts only writable views, so assigning
`trim(line)` or a string literal to it is a compile error.

**At most one resizable field, last.** It makes the struct resizable too,
so the struct lives in a local, global, parameter, result, or as a
non-element. For several independently growing fields, use `root struct`:

```goose
root struct Workspace<T> {
    items: T[>..] = [],
    scratch: i64[>..<] = [],
    calls: i64 = 0
}

fn add<T>(s: Workspace<T>&, value: T) -> T& {
    s.calls += 1;
    let result .= s.items.push(value);
    s.scratch.push(s.calls);
    s.scratch.clear();                 // does not invalidate result
    return result;
}
```

A root owner must be a local or global variable: not a field, element,
copy, temporary, or return value. Pass it as `Root&`.

Generic structs monomorphize:

```goose
struct Pair<T> { a: T, b: T }
let p = Pair { a: 0.5, b: 1.5 };      // Pair<f64>
```

Equality is memberwise, excluding pads. Reference and slice fields compare
by identity. Arithmetic is memberwise.

---

## 9. Enums

An enum is a tag plus one variant's payload. It is the only dynamic
polymorphism: no inheritance, traits, or vtables.

```goose
enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }
```

Two storage modes, chosen at each use site:

| | Fixed `Shape` | Variable `Shape..` |
|---|---|---|
| Size | tag + largest payload, every value | exactly its variant's size |
| Array | indexable | sequential; iterate only |
| Replace variant in place | yes | never |
| Reference into payload | no; `match` binds a copy | yes; `Rect &r =>` edits in place |
| Variable-size payload (string) | not allowed | allowed |

```goose
var shapes: Shape[>..] = [];
shapes.push(Shape.Circle { r: 1.0 });
shapes[0] = Shape.Rect { w: 1.0, h: 1.0 };     // fixed mode: replace

var packed: Shape..[>..] = [];
packed.push(Shape.Circle { r: 1.0 });
for s in packed {
    match s {
        Rect &r => { r.w += 1.0; },            // variable mode: edit inside
        _ => {},
    }
}
```

`match` arms:

```goose
fn name(s: Shape) -> u8[:] {
    match s {
        Circle c => "circle",
        Rect r => if r.w == r.h { "square" } else { "rectangle" },
        Dot => "dot",                          // or: Circle, Dot => "round"
    }
}
```

A match on an integer accepts literals, half-open ranges, and named
constants. `_` is the wildcard.

**Case functions** are one overload per variant and are checked for
exhaustiveness. They are the virtual-call idiom without a vtable:

```goose
fn area(s: Shape.Circle) -> f64 { 3.14159 * s.r * s.r }
fn area(s: Shape.Rect) -> f64   { s.w * s.h }
fn area(s: Shape.Dot) -> f64    { 0.0 }

for s in shapes { print(area(s)); }
```

An enum whose variants all have no payload is a C-like enum, one byte.
`const for <N, V> in variants<T>` expands over the variants at compile
time; `const for <F, A> in fields<T>` does the same over fields.

A generic enum names its type arguments at the literal:
`Opt<i64>.Some { v: 1 }`, `Opt<i64>.None`.

---

## 10. References and optionals

References are **transparent**: `r.field` reads through `r`; there is no
`*` or `->`. They are 8-byte addresses and never dangle.

- `&x` makes a reference to a local.
- `a[i]` and `push` return references.
- `var r .= xs[0];` binds a reference; `r .= xs[1];` retargets it. Plain
  `=` would copy or write through.
- `.==` and `.!=` compare identity.
- A reference to a fixed-size value returns a copy when read as a value.

```goose
var xs: i64[>..] = [1, 2, 3];
var r .= xs[0];
r = 100;                       // writes xs[0]
r .= xs[1];
print(r .== xs[1], " ", xs);   // true [100, 2, 3]
```

`T?` is a nullable reference (null is address 0, no extra space). Narrow it
with `if`, `while`, `guard`, or `assert` before use; inside the narrowed
region it is a `T&`.

```goose
let hit = xs.find() { it > 100 };
if hit { print(hit); }
guard hit else { return; }
```

There are no lifetime annotations, no aliasing rules, and no exclusivity
rules. The compiler infers each reference's **root**, the variable that
owns its target, and rejects a reference that could outlive it.

---

## 11. Relative references

A relative reference stores a link as a narrow offset instead of an
address:

- `T&<u32>` — self-relative: measured from the field to a target in the
  same enclosing array. Position-independent, so the structure can be
  relocated or written to a file as bytes.
- `T&<u32 in pool>` — pool-relative: measured from a named global array's
  base. Other arrays can hold links into the pool.
- Widths: `u8`, `u16`, `u32`, `u64`, or `varint`. `T&<u32>?` uses offset 0
  as null.

```goose
struct Node { key: i32, left: Node&<u32>?, right: Node&<u32>? }   // 12 bytes
```

A value holding self-relative links cannot be copied (the offsets would
point elsewhere). Build it in place with `push` and bind with `.=`.

`self` inside a literal means "the value being constructed", legal only as
the whole initializer of a relative-link field:

```goose
struct Node { val: i64, prev: Node&<u32 in pool.items>, next: Node&<u32 in pool.items> }
let head .= pool.alloc_with() { Node { val: 0, prev: self, next: self } };
```

---

## 12. Control flow

`if`, `match`, `block`, and a bare `{ ... }` are expressions; a block's
value is its trailing expression.

```goose
let kind = if hp > 50 { "healthy" } else { "hurt" };
let level = match hp { 0 => "dead", 1..50 => "low", _ => "fine" };
```

An `if` used as a value needs `else`. A literal branch adapts to the other
branch's type. Arrays and slices of one element type join as a slice.

`block` gives `break` a target without a loop:

```goose
let verdict = block {
    guard alive else { break "gone"; }
    guard hp > 0 else { break "dead"; }
    "standing"
};
```

`guard` states a condition the rest of the block relies on. Its `else`
must leave the block (with `return`, `break`, or `continue` if you want to
leave more). After a guard, the condition is known to hold, including
narrowing an optional.

`defer` runs at every exit from its block: fall-through, `break`,
`continue`, `return`, and `return ... from` passing through. In a loop it
runs once per iteration. It runs latest-first. A defer body cannot leave
the block, cannot use long-distance returns, and cannot name the function's
named result.

Loops:

```goose
for i in 3 { }              // 0, 1, 2
for i in 10..13 { }         // half-open
for i: i32 in 0..n { }      // bounds must be, or widen to, i32
for i: u8 in 0..256 { }     // every u8
for x in xs { }             // copies fixed-size elements; refs for variable
for &x in xs { x *= 2; }    // references: the mutation form
for x, i in xs { }          // value and i64 index
while cond { }
loop { if done { break; } }
```

A loop iterates in place; a resizable array's length is re-read before each
iteration, so a push extends the walk. `break` leaves the innermost loop or
`block`; there are no labels.

The binding rule matters for anything you store. A fixed-size element binds
by **copy**. If a field is an inline array (`u8[..24]`), a slice into it
views the copy and dies with the iteration; use `for &x in xs` when that
slice must outlive the loop. If the field is a `const u8[:]`, copying the
element copies only the header, and its target keeps its own lifetime. A
variable-size element binds by **reference**. In every case, the array being
iterated must outlive what you store from it.

`const for` is compile-time expansion over fields, variants, types, or
constants:

```goose
const for <N, A> in fields<T> { print(N, " = ", v.A); }
const for <V> in variants<T> { ... }
const for <U> in types<i8, u16, f32> { print(default<U>()); }
const for <C> in [1, 2, 4] { let a: u8[C] = [0; C]; }
```

`const if` selects a fragment at specialization time and generates only the
chosen branch. It stands where a `const for` does, chains with
`else const if`, and its condition must be a compile-time constant. Two
queries exist for it:

```goose
fn required<T>() {
    const for <N, A> in fields<T> {
        const if !has_default<A> { print("required: ", N); }
    }
}

fn describe<T>(v: T) {
    const if same<T, i64> { print("an integer ", v); }
    else const if same<T, Shape> { print("a shape"); }
    else { print("something else"); }
}
```

- `has_default<A>` — true when the field `A` declares a written `= ...`.
- `same<T1, T2>` — true when the two types are identical after
  substitution, `const` included.

This is how a generic function treats fields differently without every
branch having to typecheck for every instantiation: the branch not taken is
parsed but never checked. A runtime `if` on the same predicate could not do
that.

`abort(msg)` and `exit(code)` never return; the checker uses that when
inferring results.

---

## 13. Functions

Functions are free functions. There are no methods or `impl` blocks, but
`x.f(a)` calls `f(x, a)` for any function, and `x.f<T>(a)` calls
`f<T>(x, a)`.

```goose
fn name(a: i64, var b: f64, xs: i32[:]) -> i64 { ... }
fn generic<T>(a: T, b: T) -> T { ... }
fn also_generic(a, b) { ... }                 // untyped parameters are generic
fn scaled(a: i32, b: i32 = 0, c: f32 = 1.0) -> f32 { ... }
```

- A parameter is a `let` binding; `var b` makes a by-value parameter
  reassignable.
- A reference parameter `n: i64&` binds an lvalue without `&`.
- A slice parameter accepts every array kind.
- A by-value non-fixed parameter is constructed in the argument slot and
  owned by the callee.
- Trailing parameters may have defaults, evaluated at each call that omits
  them.

Results:

```goose
fn divide(a: i64, b: i64) -> i64, bool {
    if b == 0 { return 0, false; }
    return a / b, true;
}
let q, ok = divide(7, 2);
q, ok = divide(9, 3);          // assign to existing places
```

Several results are a calling convention, not a tuple. A call in a value
context yields the first. Only `return` and a call carry several values; a
branch cannot end in `a, b`.

A result type may be inferred from the first `return` or the trailing
expression. A non-fixed result is constructed directly in its destination.

Overload resolution: exact match, then generic exact, then coercion
(array to slice, literal fitting, widening). Ties are errors. A default
does not count as an argument. Integer-to-float conversion ranks last.
The expected result type never selects an overload.

Nested functions read and write the enclosing function's locals:

```goose
fn main() {
    var budget = 0;
    fn spend(e: Employee&) { budget += e.salary; }
    for &e in staff { spend(e); }
}
```

Qualifiers, in order after `export`/`extern`:

| Qualifier | Meaning |
|---|---|
| `recursive fn` | entry of a recursive cycle |
| `extern fn`, `extern fn ... = "sym"` | a C function |
| `export fn`, `export "sym" fn` | callable from C |
| `thread_fn` | worker entry point |
| `checkfree fn` | no bounds check may remain |
| `inline fn` | inline at every call |
| `simd fn` | build once per instruction-set level |

---

## 14. Generics and function values

An untyped parameter is generic. `<T>` says two parameters agree, or names
a type no argument carries. Everything is monomorphized and checked at each
concrete instantiation, with no trait bounds.

```goose
fn twice(x) { x + x }
fn span<T>(a: T, b: T) -> T { if a > b { a - b } else { b - a } }
fn zero<T>() -> T { default<T>() }

let half = zero<f64>() + 0.5;
print(twice(21), " ", span(3.5, 1.0));
```

Type arguments are inferred; write `f<i64>(x)` when no argument determines
one (`qget<Job>()`, `zero<f64>()`). A variant literal passed to a generic
binds the *variant* type, not the enum: annotate the argument when the body
needs the enum (`let s: Shape = Shape.Circle { r: 1 }; name(s)`).

Function values are compile-time entities passed as generic parameters.
They cannot be stored, returned, or put in data. Every call is direct and
inlinable; there is no closure object or function pointer.

```goose
fn each_pair<T, F>(xs: T[:]) {
    for i in 0..xs.len - 1 { F(xs[i], xs[i + 1]); }
}

each_pair(xs) { a, b => gaps.push(b - a); };    // `it` if one parameter
let evens = xs.filter() { it % 2 == 0 };
let total = fold(xs, 0) { acc, x => acc + x };
sort(people) { a, b => a.age < b.age };
```

A trailing block is the last argument. There is one trailing block per
call. A `return` inside a block returns from the **lexically enclosing
function**, not the higher-order function:

```goose
fn first_multiple_of_7(lo: i64, hi: i64) -> i64 {
    each_step(lo, hi, 3) { if it % 7 == 0 { return it; } };
    return -1;
}
```

Stored behaviour becomes an enum plus case functions, not a closure.

---

## 15. Recursion

Recursion is opt-in:

```goose
recursive fn in_order(n: Node&, out: i32[>..]&) {
    let l = n.left;
    if l { in_order(l, out); }
    out.push(n.key);
    let r = n.right;
    if r { in_order(r, out); }
}
```

- Mark the cycle's entry `recursive fn`.
- Every function in the cycle needs a written signature.
- No function in the cycle may hold growable data across a call back into
  the cycle. End the scratch's scope before the call, pass the pool in, or
  share one `[>..<]` stack and truncate back to a mark before returning.

For several tables used by recursive code, own them in a driver function
and pass a struct of references:

```goose
struct Ctx {
    nodes: Node[>..]&,
    text: u8[>..]&,
    scratch: i64[>..<]&,
}
```

---

## 16. Errors

There is no `Result`, no `?`, and no unwinding exceptions. Choose by
distance:

| Situation | Tool |
|---|---|
| Immediate two-way outcome | trailing `bool`: `-> T, bool` |
| Found or not | `T?`, a nullable reference |
| Fails deep, handled far up | `return E from f` |
| A bug or invariant | `assert`, `abort(msg)`, `exit(code)` |
| Typed error value | the `exception` module |

`return E from f` returns `E` as the result of the innermost active call
to `f`, however many frames up. In-between functions keep plain
signatures. It is checked statically: every path to the throw must be
inside an `f` call.

```goose
fn load(text: u8[:]) -> User[>..], u8[] {
    var users: User[>..] = [];
    // users.push(parse(line));
    return users, "";
}

fn parse(line: u8[:]) -> User {
    guard line.len > 0 else { return [], "empty line" from load; }
    return User { name: line, age: 0 };
}
```

The `exception` module packages the same mechanism with a named error type:

```goose
import exception;

fn load() { exception::throw(str("cannot load item ", 42)); }

exception::try<u8[]>(load) { error => print(error); };
```

`try<E, Body, Catch>()`, `try<E, Body>()`, and
`try<E, Body, Catch, Finally>()` are the forms. Errors may only carry
references to globals or static data; use owned `u8[]` for text produced
locally.

---

## 17. Program structure

- One root file holds `main` and declares imports.
- `import name;` imports a standard-library module.
- `import a.b.c;` imports `a/b/c.goose` from the package root, a declared package, or the standard library.
- `import .helper;` resolves relative to the importing file.
- `import name from "path";` imports a package from a directory.
- `import name from "owner/repo@v1";` imports a git package.
- `namespace image;` at the top of a file places its declarations in `image`; elsewhere they are `image::Pixel`, `image::brightness(p)`.
- `fn ::main()` declares `main` in the global namespace from a namespaced file.
- Declarations are order-independent at top level.
- `embed_file("path")` reads a file's bytes at compile time.

```goose
import std;
import json;

fn main() {
    print("hello, goose");
}
```

`main` takes no arguments. Program arguments come from `os::args()`
(`import os;`).

---

## 18. Threads

Threads share nothing. A `thread_fn` and everything it calls compile as a
separate program with its own data stacks and its own copies of globals.

Values cross through typed queues, one per type, and must be **flat**: no
references or slices at any depth. Variable-size parts are allowed, so a
job can carry a string or pixels, and crossing is one `memcpy`.

```goose
struct Job { n: i32 }
struct Result { n: i32, digits: i32 }

thread_fn worker() {
    loop {
        let job = qget<Job>();               // blocks
        guard job.n >= 0 else { break; }
        qput(Result { n: job.n, digits: count_digits(job.n) });
    }
}

fn main() {
    let n = max(1, hardware_threads());
    for i in 8 { qput(Job { n: (1 << (i * 3)) as i32 }); }
    for i in n { qput(Job { n: -1 }); }
    var ids: i64[>..] = [];
    for i in n { ids.push(thread_spawn(worker)); }
    var total = 0;
    for i in 8 { let r = qget<Result>(); total += r.digits; }
    for id in ids { thread_wait(id); }
}
```

- `qput(v)`, `qget<T>()` (blocking), `qpoll<T>()` (non-blocking),
  `qlimit<T>(n)`.
- `thread_spawn(worker, args...)`, `thread_spawn_contained(...)`,
  `thread_wait(id)`, `thread_wait(id, msg)`.
- A global incremented in a worker changes only the worker's copy.
- Threads must be built with `goose build`; TinyCC cannot place
  thread-local storage.
- Libraries with a main-thread rule (`gfx`, `ui`, `audio`, `physics`) are
  rejected inside a `thread_fn`.

---

## 19. Serialization

If links are self-relative, a structure means the same thing wherever it
is in memory, so saving it is writing its bytes.

```goose
struct Node { word: u8[..24], count: i32, left: Node&<u32>?, right: Node&<u32>? }

var index: Node[>..] = [];
// build the tree ...
var image: u8[>..] = index.to_bytes();
var loaded, ok = from_bytes<Node[>..]>(image);   // verified before use
```

- `to_bytes(a)` — a framed copy.
- `to_bytes(a, out)` — append into an existing builder.
- `bytes_of(a)` — a read-only view of the element region, no copy.
- `from_bytes<T[>..]>(b) -> T[>..], bool` — verifies framing, tags,
  lengths, and every link before the bytes become a value.

`from_bytes` checks safety, not integrity. A tampered data byte can still
describe a well-formed structure; use a checksum for authenticity.

---

## 20. C interop

```goose
extern fn hypot(x: f64, y: f64) -> f64;
extern fn cube_root(x: f64) -> f64 = "cbrt";
extern fn crc32_bytes(s: const u8[:]) -> u32;
extern fn stats_of(xs: i32[:], out: Stats&);
extern fn c_version(out: u8[>..]&);
```

Permitted types are those with a plain C shape: scalars and `bool`, flat
fixed-size structs and arrays (by value or through a reference), slices of
those (as `{ data, len }`), and a `u8[>..]&` builder. Anything else is
rejected at the declaration.

- A program's own C goes in a sidecar `foo.build` beside `foo.goose`:
  `c_sources = ["impl.c"];`
- `export fn` makes Goose callable from C. Generate a header with
  `goose --standalone --header hello.h -o hello.c hello.goose`.
- The C host calls `goose_init(argc, argv)` first and `goose_exit()` when
  done. A `const u8[:]` result comes back as a pointer plus an
  `int64_t *` length parameter. Generated functions are not thread-safe.

---

## 21. Builtins

| Builtin | Meaning |
|---|---|
| `print(a, b, ...)` | text and a newline, one write |
| `str(a, b, ...) -> u8[>..]` | fresh string, built at its destination |
| `format(out, a, b, ...)` | append text to a growable `u8` array |
| `assert(c)` | abort unless `c`; narrows an optional |
| `abort(msg)`, `exit(code)` | end the program; neither returns |
| `copy(x) -> T` | explicit O(n) copy |
| `default<T>() -> T` | the type's default value |
| `hardware_threads()` | usable worker count |
| `thread_spawn`, `thread_spawn_contained`, `thread_wait` | workers |
| `qput`, `qget<T>`, `qpoll<T>`, `qlimit<T>` | typed queues |
| `to_bytes`, `bytes_of`, `from_bytes<T>` | serialization |
| `embed_file(path)`, `embed_shader(...)` | compile-time data |

Array members are listed in [Arrays](#5-arrays).

---

## 22. Keywords and operators

**Keywords**: `import namespace struct enum type fn thread_fn export simd
recursive let var extern const pad reusable if else while for in loop
block guard defer match return break continue as true false null self bool
varint i8 i16 i32 i64 u8 u16 u32 u64 f32 f64`.

**Contextual**: `from`, `upto`, `inline`, `checkfree`, `fields`, `types`,
`variants`, and `has_default` and `same` in a `const if` condition.

**Precedence**, tightest first (Rust's):

| Level | Operators |
|---|---|
| postfix | call, `a[i]`, `a[x..y]`, `.field`, `as`, `as!` |
| unary | `- ! ~ &` |
| multiplicative | `* / %` |
| additive | `+ -` |
| shifts | `<< >>` |
| bitwise | `& ^ \|` |
| comparison | `< <= > >=` |
| equality | `== != .== .!=` |
| logical | `&& \|\|` |

Assignment statements: `=`, `.=`, and compound forms (`+=`, `<<=`, `&=`,
...); `++` and `--` on integer lvalues. A range `a..b` appears only in
slice brackets, `for` headers, and match arms.
