# The Goose memory model

Most Goose compile errors come from carrying a heap assumption into a
language that has no heap. This file states the model and the rules that
follow from it, then maps the common failures to fixes.

## Contents

1. [Where values live](#1-where-values-live)
2. [Size classes and placement](#2-size-classes-and-placement)
3. [Ownership is scope](#3-ownership-is-scope)
4. [Nothing moves](#4-nothing-moves)
5. [Copies are visible](#5-copies-are-visible)
6. [References and roots](#6-references-and-roots)
7. [Growth and shrink](#7-growth-and-shrink)
8. [Pools for non-nested lifetimes](#8-pools-for-non-nested-lifetimes)
9. [Recursion](#9-recursion)
10. [Performance and bounds checks](#10-performance-and-bounds-checks)
11. [Failure patterns](#11-failure-patterns)

---

## 1. Where values live

A Goose program has:

- the native call stack,
- static data,
- **N data stacks**, where N is a small number the compiler computes.

A data stack is a large address-space reservation with a bump pointer. It
is committed page by page as it is used. There is no other memory system:
no `malloc`, no free list, no GC, no reference counting, no destructors.

Two rules make it work:

1. Values are pushed in lifetime order and popped **en masse** when the
   owning scope exits.
2. At most one **resizable** value is live per data stack, and it is the
   topmost thing on that stack for its entire lifetime. Growth is therefore
   a pointer bump with no capacity check, and the value never moves.

"One resizable per stack" is not "one per program": three simultaneously
live growable arrays get three stacks. A stack is reused as soon as a scope
frees it. N is the deepest point the program needs, computed once at
compile time. You never write any of this down; there is no syntax for
stacks.

```goose
for round in 3 {
    var scratch: u8[>..] = [];
    for i in 100000 { scratch.push((i % 256) as! u8); }
    print("round ", round, ": ", scratch.len, " bytes");
}   // "freeing" 100 KB: one store to the stack top
```

Implications:

- A fresh local per loop iteration is cheap, not wasteful.
- Freeing a million-element tree is one store, however deeply nested.
- Memory use is the high-water mark of simultaneous live values, not the
  total allocated over time.
- A runaway growth run aborts at the reservation gap rather than
  corrupting memory.

## 2. Size classes and placement

Every type is **fixed**, **variable**, or **resizable**:

| Class | Examples | Size known |
|---|---|---|
| fixed | scalars, `T[k]`, `T[..k]`, structs of fixed fields, references, slices, fixed-mode enums | at compile time |
| variable | `T[]`, `T[varint]`, `T[..]` | at construction |
| resizable | `T[>..]`, `T[>..<]` | changes |

Placement:

- **Fixed** values go anywhere: locals, globals, fields, elements,
  payloads, parameters, results.
- **Variable** values go in locals and globals, parameters and results,
  payloads, and array elements (which makes the array sequential), and at
  any field position. A field after a variable-size one is reached by
  computing its offset.
- **Resizable** values go in locals and globals, by-value parameters,
  results, and the **last field** of an ordinary struct. Never in an array
  element.
- **Root owners** go only in local or global declarations. Never in
  another struct, array, slice, enum payload, or by-value parameter or
  result.
- **Zero-size** values (`T[0]`, `T[..0]`, an empty variant) exist only as
  values of their own, never as fields or elements.

A struct with a resizable last field is itself resizable, so it inherits
the same placement rules. A `root struct` lifts this: each field has
independent storage and may grow separately, but the owner itself is
local/global only.

## 3. Ownership is scope

The owner of a value is the variable whose scope contains it:

- a local owns what it declares,
- a global owns until the program ends,
- a by-value non-fixed parameter owns its argument for the call,
- a struct or array owns its fields and elements.

When the owner's scope exits, everything it pushed is released at once.

What this means in practice:

- To make a value outlive a function, return it by value or push it into an
  array owned by a caller. Do not reach for an allocator.
- To share data without copying, pass a slice, a reference, or the array
  itself. Non-fixed values are already passed by reference.
- To keep data beyond a call whose scope would free it, move the owner up
  to a common ancestor scope.

Non-memory resources are different. Files and OS calls are whole-operation
(`read_file`, `write_file`), GPU and physics handles are released
explicitly, and there are no destructors to run. `defer` handles cleanup
in the same block; it does not run on `abort`, `exit`, or a failed check.

## 4. Nothing moves

Because a resizable value is always at the top of its stack, pushing never
relocates it. A reference into a `T[>..]` stays valid for the array's whole
lifetime:

```goose
struct Item { id: i32, weight: f32 }

var items: Item[>..] = [];
let first .= items.push(Item { 1, 0.5 });
for i in 2..1000001 { items.push(Item { i, 0.0 }); }
first.weight = 99.5;          // still valid after a million pushes
```

This is the property a `vector<T>` or `Vec<T>` cannot provide. It is why
Goose code can keep typed references where the equivalent Rust code keeps
`u32` indices into an arena.

`push` returns a reference to the new element, which is the idiomatic way
to link data while building it.

A grow-shrink array (`T[>..<]`) may move nothing either, but its tail can
be removed. References into it may live only in variables, never in
storage, so the compiler can prove at each shrink that none is live.

## 5. Copies are visible

Fixed-size values copy silently on assignment, like C: scalars, structs of
fixed fields, `T[k]`, `T[..k]`, references, and slices.

**Non-fixed values never copy implicitly**, because the copy is O(size).
Plain assignment binds by reference:

```goose
var a: i64[>..] = [1, 2, 3];
var b = a;           // b is another name for a
b.push(4);
print(a);            // [1, 2, 3, 4]

var c = copy(a);     // an explicit, visible O(n) copy
c.push(5);
print(a, " ", c);    // a unchanged
```

The same applies at calls: `f(xs)` passes a growable array by reference,
whether the parameter is `T[:]`, `T[>..]&`, or untyped. A function that
needs its own copy calls `copy`.

Returning a non-fixed local moves it into the caller's destination; no
copy occurs. Returning a *part* of a local or a temporary needs `copy(x)`,
because the rest dies with the call.

## 6. References and roots

Every reference and slice has a static **root**: the variable that bounds
its target's lifetime. The rule is one sentence:

> A reference must not outlive the variable that owns its target, and must
> never observe its target at a wrong type.

The compiler infers roots and specializes functions for them. There are no
lifetime annotations, no `unsafe`, no aliasing rules, and no exclusivity
rules. Two references to the same value are fine, because without shared
memory concurrency aliasing alone cannot break type safety.

```goose
fn longest(a: u8[:], b: u8[:]) -> u8[:] { if a.len >= b.len { a } else { b } }

var outer: u8[>..] = [];
var w = outer[..];
{
    var inner: u8[>..] = [];
    format(inner, "inner text");
    w = longest(outer, inner);   // error: reference rooted at inner does not
}                                //        outlive the destination
```

A reference read out of a container is rooted at the variables that could
hold its target (the "candidates"), which is why the error names the
container and the binding site. To satisfy the checker, make the owner
outlive the destination, copy the value, or shorten the reference's life.

Writability is inferred too. A string literal is read-only; `&x` of a
`var` is writable. A *slot* (field, element, global, annotated variable)
must say whether it can hold read-only data: `dictionary<const u8[:], i32>`
accepts literals and `split` results.

## 7. Growth and shrink

`T[>..]` is grow-only in the sense that matters: references into it stay
valid. It can still shrink at a `pop`, `pop_n`, `resize`, or `clear` **the
compiler can see**, provided nothing points into it at that point.

```goose
var xs: i64[>..] = [1, 2, 3];
let s = xs[1..];
xs.pop();             // error: cannot pop xs while s is still used
print(s);
```

Fix it by finishing with the view first:

```goose
var xs: i64[>..] = [1, 2, 3];
{
    let s = xs[1..];
    print(s);
}
xs.pop();             // fine: s's last use is behind the pop
```

The checker looks at liveness, not lexical scope. A reference whose last
use is before the mutation needs no extra block; a reference used after is
an error wherever it was declared.

Grow-shrink arrays (`T[>..<]`) may shrink while references exist, but only
references held in variables; none may be stored in a struct or array,
because the compiler could not track them all.

Assigning a whole array copies its contents (for compatible kinds); it
does not rebind. A limited array accepts a longer literal only within its
capacity.

## 8. Pools for non-nested lifetimes

Some data does not die in stack order: cache entries, graph nodes being
edited, documents closed arbitrarily, entities in a world. These need
storage that outlives a scope but is reused independently of scope.

Use `slot_pool<T>` for individual slots and `slice_pool<T>` for
contiguous runs. Both are root structs: declare the owner as a local or
global and pass it as `slot_pool<T>&`.

```goose
import slot_pool;

struct Item { id: i32, weight: f32 }
var pool = slot_pool<Item> {};

let s0 = pool.alloc_index(Item { 10, 1.0 });
let s1 = pool.alloc_index(Item { 11, 1.0 });
pool.free(s0);
let s2 = pool.alloc_index(Item { 12, 2.0 });   // reuses slot 0
```

**`free` releases no memory.** It pushes an index onto a freelist. Every
slot stays a live, correctly typed value. A stale reference to a reused
slot reads a *different* value of the correct type — a logic bug, never
memory corruption. That is the same class of bug as a stale index into a
vector.

- `alloc_index(value)` / `alloc_ref(value)` — take a free slot or append.
- `alloc_with() { value }` / `alloc_index_with() { value }` — construct in
  the chosen slot, so `self` and self-relative links work.
- `free(i)`, `free_ref(value)`, `recycle_all()`.
- `pool.items` is the backing array: index, slice, iterate, `index_of`.
- `items.len` is the high-water count, including freed slots.
- A global `var pool` allows compact links: `Node&<u32 in pool.items>`.
- Elements must be fixed-size.
- Never shrink or replace `items`, or edit the freelist directly.

`slice_pool<T>`:

```goose
import slice_pool;

var bytes = slice_pool<u8> {};
var run = bytes.alloc_slice(16);
run = bytes.realloc_slice(run, 32);   // may move: keep offsets, not slices
bytes.free_slice(run);
```

`alloc_slice` defaults every element. `alloc_copy` initializes from a
source. `realloc_slice` preserves the first `min(old, new)` elements and
may relocate the run. Free spans coalesce. `items.len` is a high-water
mark, not a live count.

The deprecated `reusable` and `reusable[]` language features still exist;
prefer the library pools.

## 9. Recursion

Every activation of a recursive function would need its own data stack if
it held growable data across the recursive call. The compiler therefore
forbids exactly that.

Recursion is opt-in:

```goose
recursive fn in_order(n: Node&, out: i32[>..]&) { ... }
```

- Mark the entry of the cycle `recursive fn`.
- Every function in the cycle needs an explicit signature.
- No function in the cycle may hold growable data across a call back into
  the cycle.

Three ways to comply:

1. **Pass the accumulator in** as `T[>..]&`, owned by a caller.
2. **End the scratch's scope before the call.**

   ```goose
   recursive fn show(n: Node&, depth: i64) {
       {
           var line: u8[>..] = [];
           for i in depth { line.append("  "); }
           line.append(str(n.key));
           print(line);
       }
       let l = n.left;
       if l { show(l, depth + 1); }
   }
   ```

3. **Share one grow-shrink stack** and truncate to a mark before returning.

   ```goose
   recursive fn walk(c: Ctx&, n: i64) -> i64 {
       let mark = c.scratch.len;
       c.scratch.push(n);
       // ... recurse ...
       c.scratch.resize(mark);
       return total;
   }
   ```

A parser follows the same shape: the input, cursor, and pools are locals
of a non-recursive driver, and the grammar rules are nested functions or
functions taking a `Ctx&`.

## 10. Performance and bounds checks

The memory model supplies most of the speed: no allocator, no teardown,
contiguous data, narrow links, and variant-sized enums.

Every index is bounds-checked. The compiler removes checks it can prove
unnecessary, and several language rules help it:

- a `T[>..]` shrinks only at a visible `pop`, `pop_n`, `resize`, or
  `clear`, so a bound established before a `push` still holds after;
- `%` is Euclidean, so a reduction is always in range;
- fixed sizes and capacities are constants;
- call sites record what they prove about their arguments.

The idiom that helps most is one `assert` of lengths at the top of a
kernel:

```goose
fn blur_row(above: u8[:], here: u8[:], below: u8[:], out: u8[:]) {
    assert(above.len == 8 && here.len == 8 && below.len == 8 && out.len == 8);
    for x in 1..7 {
        let sum = above[x - 1] as i64 + above[x] + above[x + 1] +
                  here[x - 1] + here[x] + here[x + 1] +
                  below[x - 1] + below[x] + below[x + 1];
        out[x] = (sum / 9) as! u8;
    }
}
```

With the assert, every index is the loop counter plus a constant, checked
against a known length, so all checks disappear and the loop vectorizes.
Without it, none do.

- `goose check --stats` prints `bce: elided N/M ...`.
- `--bce-lines` reports remaining checks per line.
- `--no-bce` keeps every check.
- `checkfree fn` makes a surviving check a compile error, for kernels that
  must stay check-free.

Index types move validation to where data enters:

```goose
type NodeId = u32 in nodes;
let id = raw as NodeId;      // checked once here
let n = nodes[id];           // no check
```

## 11. Failure patterns

| Symptom | Cause | Fix |
|---|---|---|
| reference outlives destination | owner is in an inner scope | move the owner up, return by value, or `copy` |
| `cannot pop ... while ... is still used` | live view into a shrinking array | finish with the view, or shorten its life |
| `cannot call insert ... while r ... is still used` | reference into a resizable dictionary | use `update`, or finish with the reference first |
| resizable field not last | ordinary struct with two resizable fields | reorder, or use `root struct` |
| cannot place a root owner | root used as field/element/return | own it in a local or global, pass `Root&` |
| "may be used before it is assigned" | local without an initializer | initialize it, or use `T { .. }` / `default<T>()` |
| array grows across a recursive call | growable local in a recursive cycle | scope it out, pass a pool, or use a shared stack |
| slices of different element types | `i32[:]` vs `i64[:]` | match the element type, or copy/widen first |
| variable-size elements cannot be indexed | `u8[][>..]` or `Enum..[>..]` | iterate, or keep an index array of references |
| fixed-mode payload cannot bind `&` | fixed enum can be overwritten | bind by value, or store as variable mode |

When in doubt, the error names both ends of the problem: the reference and
where it was bound, the holder and the line that stored into it, or the
instantiation and the call chain.
