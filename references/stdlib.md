# Goose standard library

Import a module by name: `import std;`, `import dictionary;`. The compiler
finds the library in its own tree; `--stdlib <dir>` or `GOOSE_STDLIB`
selects another.

Library conventions:

- A function that reads or mutates elements in place takes `xs: T[:]`;
  every array kind coerces to a slice.
- A function that changes the length takes the whole array by reference
  (`xs: A&`) and instantiates for the array kind given.
- Non-fixed values are never taken by value. A function that needs its own
  copy calls `copy`.
- Fresh arrays come back as `T[>..]`, built in the caller's destination.
- "Maybe an element" is `T?`; a position is `i64` with `-1` for none; a
  two-outcome scalar returns a trailing `bool`.
- Blocks are the last argument: `xs.find() { it > 3 }`,
  `sort(xs) { a, b => a < b }`. A comparator means "a goes before b".
- UFCS applies: `xs.sort()`, `d.insert(k, v)`, `r.rand_int(6)`.
- Text output goes into a `u8[>..]&` builder; `str(...)` is the fresh form.

---

## std

`import std;` — global names (no namespace).

### Scalars and bits

```goose
fn min<T>(a: T, b: T) -> T          fn max<T>(a: T, b: T) -> T
fn clamp<T>(x: T, lo: T, hi: T) -> T
fn abs<T>(x: T) -> T                // integers, plus f32/f64 overloads
fn rem<T>(a: T, b: T) -> T          // integer remainder pairing with `/`
fn div_euclid<T>(a: T, b: T) -> T   // quotient pairing with `%`
fn sign<T>(x: T) -> T               // -1, 0, 1
fn lerp(a: f64, b: f64, t: f64) -> f64       // and f32
fn next_pow2(x: i64) -> i64
fn popcount(x: u64) -> i64
fn clz(x: u64) -> i64               // 64 for 0
fn ctz(x: u64) -> i64               // 64 for 0
fn swap<T>(a: T&, b: T&)
```

### Hashing

```goose
fn hash(x: i8) -> u64               // one overload per integer type
fn hash(x: bool) -> u64
fn hash(x: f32) -> u64
fn hash(x: f64) -> u64
fn hash(s: u8[:]) -> u64
fn hash_combine(seed: u64, h: u64) -> u64
```

Custom key: write a global `hash` overload. `dictionary` finds it.

```goose
struct Key { a: i64, b: i64 }
fn hash(k: Key) -> u64 { hash_combine(hash(k.a), hash(k.b)) }
```

### Random

```goose
struct rng { s: u64 }
fn rand_u64(r: rng&) -> u64
fn rand_int(r: rng&, n: i64) -> i64      // [0, n), unbiased
fn rand_flt(r: rng&) -> f64              // [0, 1)
fn shuffle<T>(xs: T[:], r: rng&)

var r = rng { os.random_seed() };
```

### Arrays: read and search

```goose
fn each_rev<T, F>(xs: T[:])
fn each_chunk<T, F>(xs: T[:], n: i64)          // F(chunk, i)
fn find<T, F>(xs: T[:]) -> T?                  // first matching element
fn find_index<T, F>(xs: T[:]) -> i64
fn position<T>(xs: T[:], v: T) -> i64
fn contains<T>(xs: T[:], v: T) -> bool
fn any<T, F>(xs: T[:]) -> bool
fn all<T, F>(xs: T[:]) -> bool
fn count<T, F>(xs: T[:]) -> i64
fn min<T>(xs: T[:]) -> T                       // asserts non-empty
fn max<T>(xs: T[:]) -> T
fn min_by<T, F>(xs: T[:]) -> i64               // index; -1 if empty
fn max_by<T, F>(xs: T[:]) -> i64
fn last<T>(xs: T[:]) -> T&
fn lower_bound<T, F>(xs: T[:]) -> i64
fn binary_search<T>(xs: T[:], v: T) -> i64, bool
fn find<T>(xs: T[:], sub: T[:]) -> i64         // subsequence; -1
fn rfind<T>(xs: T[:], sub: T[:]) -> i64
fn starts_with<T>(xs: T[:], p: T[:]) -> bool
fn ends_with<T>(xs: T[:], p: T[:]) -> bool
```

`find` is the string search too: `find(line, "://")`.

### Byte sets

```goose
fn byte_set(members: bool[256]) -> ByteSet
fn byte_set(bytes: u8[:]) -> ByteSet
fn find_any(s: const u8[:], set: const ByteSet&) -> i64
fn find_pair(s: u8[:], a: const ByteSet&, d: i64, b: const ByteSet&) -> i64
```

Build a set once, outside the search loop.

### Transform

```goose
fn map<T, F>(xs: T[:])              // -> U[>..]
fn filter<T, F>(xs: T[:]) -> T[>..]
fn fold<T, A, F>(xs: T[:], acc: A) -> A
fn sum<T>(xs: T[:]) -> T
fn concat<T>(a: T[:], b: T[:]) -> T[>..]
```

### In place

```goose
fn fill<T>(xs: T[:], v: T)
fn copy_into<T>(dst: T[:], src: T[:])     // equal lengths
fn reverse<T>(xs: T[:])
fn sort<T>(xs: T[:])                      // by <, or by a block
fn stable_sort<T>(xs: T[:])
fn to_lower(s: u8[:])
fn to_upper(s: u8[:])
```

### Change the length

```goose
fn push_n<A, T>(xs: A&, v: T, n: i64)
fn insert_at<A, T>(xs: A&, i: i64, v: T)
fn remove_at<A>(xs: A&, i: i64) -> T
fn swap_remove<A>(xs: A&, i: i64) -> T
fn retain<A, F>(xs: A&)
fn dedup<A>(xs: A&)
fn heap_push<A, T>(xs: A&, v: T)
fn heap_pop<A>(xs: A&) -> T
fn make_heap<A>(xs: A&)
```

### Strings

```goose
fn format_int<B>(out: B&, v: i64, base: i64, width: i64, padc: u8)
fn format_uint<B>(out: B&, v: u64, base: i64, width: i64, padc: u8)
fn format_flt(out: u8[>..]&, v: f64, decimals: i64)
fn parse_int(s: u8[:], base: i64 = 10) -> i64, bool
fn parse_uint(s: u8[:], base: i64 = 10) -> u64, bool
fn parse_flt(s: u8[:]) -> f64, bool
fn format_uleb(out: u8[>..]&, v: i64)
fn parse_uleb(s: u8[:]) -> i64, i64
fn compare(a: const u8[:], b: const u8[:]) -> i64
fn trim(s: u8[:]) -> u8[:]
fn trim_start(s: u8[:]) -> u8[:]
fn trim_end(s: u8[:]) -> u8[:]
fn split(s: u8[:], sep: u8) -> const u8[:][>..]
fn split(s: u8[:], sep: u8[:]) -> const u8[:][>..]
fn each_split<F>(s: u8[:], sep: u8)
fn each_split<F>(s: u8[:], sep: u8[:])
fn split_once(s: u8[:], sep: u8) -> const u8[:], const u8[:], bool
fn words(s: u8[:]) -> const u8[:][>..]
fn each_word<F>(s: u8[:])
fn join<T>(out: u8[>..]&, parts: T[:], sep: u8[:])
fn format_replaced(out: u8[>..]&, s: u8[:], old: u8[:], with: u8[:])
fn each_utf8<F>(s: u8[:])                 // F(codepoint)
fn push_utf8(out: u8[>..]&, cp: i64)
fn ascii::is_digit(c: u8) -> bool
fn ascii::is_alpha(c: u8) -> bool
fn ascii::is_alnum(c: u8) -> bool
fn ascii::hex_value(c: u8) -> i64
```

`split` and `words` return slices into their input: nothing is copied.
`split` keeps empty parts; `words` drops them. `print` and `format` write
the shortest text that reads back as the value: `2.0` prints as `2.0`, and
`1.0 / 3.0` prints 17 significant digits. C++'s `std::cout` and `printf`
default to six, so a port that prints floats will differ. Use
`format_flt(out, v, decimals)` to reproduce a fixed precision.

---

## dictionary

```goose
struct dictionary<K, V> { count: i64, slots: dictionary_slot<K, V>[>..<] }

fn get<K, V>(d: dictionary<K, V>&, key: K) -> V?
fn contains<K, V>(d: dictionary<K, V>&, key: K) -> bool
fn insert<K, V>(d: dictionary<K, V>&, key: K, val: V) -> bool
fn get_or_insert<K, V>(d: dictionary<K, V>&, key: K, v0: V) -> V&
fn update<K, V, F>(d: dictionary<K, V>&, key: K, v0: V)   // F(val&)
fn remove<K, V>(d: dictionary<K, V>&, key: K) -> bool
fn clear<K, V>(d: dictionary<K, V>&)
fn reserve<K, V>(d: dictionary<K, V>&, n: i64)
fn each<K, V, F>(d: dictionary<K, V>&)                    // F(key, val&)
```

Open addressing, power-of-two capacity, backward-shift deletion. Keys and
values are fixed-size; a key needs `hash` and `==`. A set is
`dictionary<K, bool>`. Strings key as `u8[:]` slices into text the caller
keeps (`const u8[:]` for literals), or as an inline `u8[..k]`, which needs
no `hash` overload. A slice key must root at something that outlives the
dictionary, so take it from a long-lived array, not a by-value loop copy:

```goose
for &r in records { counts.update(r.name, 0) { it += 1; }; }   // & is required
```

`each` visits slots in **hash order**, which is unspecified and changes
with capacity. For ordered output, copy the entries into an array and sort
it:

```goose
var rows: Entry[>..] = [];
d.each() { k, v => rows.push(Entry { key: k, value: v }); };
sort(rows) { a, b => compare(a.key, b.key) < 0 };
```

A reference from `get` or `get_or_insert` is into the slot array, so its
last use must precede the next `insert`, `update`, `remove`, or `clear`.
Use `update` to look up and change in one call.

```goose
var counts = dictionary<const u8[:], i32> {};
each_split(text, ' ') { counts.update(it, 0) { it += 1; }; };
counts.each() { w, n => print(w, " ", n); };
let n = counts.get("the");
if n { print(n); }
```

---

## slot_pool

```goose
import slot_pool;

root struct slot_pool<T> {
    items: T[>..] = [],
    free_slots: i64[>..<] = []
}

fn alloc_index<T>(pool: slot_pool<T>&, value: T) -> i64
fn alloc_ref<T>(pool: slot_pool<T>&, value: T) -> T&
fn alloc_with<T, F>(pool: slot_pool<T>&) -> T&
fn alloc_index_with<T, F>(pool: slot_pool<T>&) -> i64
fn free<T>(pool: slot_pool<T>&, i: i64)
fn free_ref<T>(pool: slot_pool<T>&, value: T&)
fn recycle_all<T>(pool: slot_pool<T>&)
```

Use for independently freed slots. Elements must be fixed-size.
`alloc_with` selects the slot first and constructs there, so `self` and
self-relative links work. `free` only records an index; the slot stays
initialized and may be reused. `items` is the backing array:
`pool.items[i]`, `pool.items.index_of(r)`, `for x in pool.items`.

```goose
var pool = slot_pool<Item> {};
let i = pool.alloc_index(Item { id: 1 });
let r .= pool.alloc_ref(Item { id: 2 });
pool.free(i);
pool.free_ref(r);
```

---

## slice_pool

```goose
import slice_pool;

fn alloc_slice<T>(pool: slice_pool<T>&, n: i64) -> T[:]
fn alloc_copy<T>(pool: slice_pool<T>&, src: T[:]) -> T[:]
fn free_slice<T>(pool: slice_pool<T>&, s: T[:])
fn realloc_slice<T>(pool: slice_pool<T>&, s: T[:], n: i64) -> T[:]
fn recycle_all<T>(pool: slice_pool<T>&)
```

Reusable contiguous runs with coalescing. `alloc_slice` defaults every
element; `alloc_copy` initializes from a source. `realloc_slice` may move
a run, so keep offsets rather than slices across a realloc. `items.len` is
a high-water mark.

```goose
var bytes = slice_pool<u8> {};
var s = bytes.alloc_copy("hello");
s = bytes.realloc_slice(s, 16);
bytes.free_slice(s);
```

---

## vec

```goose
struct vec2<T> { x: T, y: T }
struct vec3<T> { x: T, y: T, z: T }
struct vec4<T> { x: T, y: T, z: T, w: T }
type float2 = vec2<f32>     // float3, float4, double2..4, int2..4
fn dot<T>(a, b) -> T
fn cross<T>(a: vec3<T>, b: vec3<T>) -> vec3<T>
fn length_sq<T>(v) -> T
fn length<T>(v) -> T
fn normalize<T>(v) -> vec3<T>
fn distance<T>(a, b) -> T
fn lerp<T>(a, b, t) -> vec3<T>
fn xy<T>(v: vec3<T>) -> vec2<T>
```

Elementwise `+ - * /` and unary `-` are language features; `*` and `/`
broadcast a scalar. A scalar of another type needs an explicit cast.

---

## math

`math` wraps libm at both widths. A call picks the width from its argument;
an integer argument is ambiguous, so write `sqrt(n as f64)`.

```goose
sqrt sin cos tan asin acos atan atan2 exp log log2 log10 pow hypot cbrt
exp2 expm1 log1p sinh cosh tanh floor ceil round trunc copysign mul_add

let PI = 3.141592653589793;   let TAU = 6.283185307179586;
let E = 2.718281828459045;    let INF = 1.0 / 0.0;   let NAN = 0.0 / 0.0;

fn radians(deg: f64) -> f64          fn degrees(rad: f64) -> f64
fn is_nan(x: f64) -> bool            fn is_inf(x: f64) -> bool
fn is_finite(x: f64) -> bool
fn fract(x: f64) -> f64
fn inverse_lerp(a, b, v: f64) -> f64
fn smoothstep(edge0, edge1, x: f64) -> f64
fn wrap_angle(x: f64) -> f64
```

---

## os

```goose
fn read_file(path: const u8[:], out: u8[>..]&) -> bool
fn write_file(path: const u8[:], data: const u8[:]) -> bool
fn write_file_atomic(path: const u8[:], data: const u8[:]) -> bool
fn append_file(path: const u8[:], data: const u8[:]) -> bool
fn file_exists(path: const u8[:]) -> bool
fn delete_file(path: const u8[:]) -> bool
fn rename_file(from: const u8[:], to: const u8[:]) -> bool
fn make_dir(path: const u8[:]) -> bool
fn is_dir(path: const u8[:]) -> bool
fn delete_dir(path: const u8[:]) -> bool
fn list_dir(path: const u8[:], out: u8[>..]&) -> bool
fn read_line(out: u8[>..]&) -> bool
fn read_stdin(out: u8[>..]&)
fn read_stdin(out: u8[>..]&, max: i64) -> bool
fn write_stdout(s: const u8[:])
fn write_stderr(s: const u8[:])
fn flush_stdout()
fn arg_count() -> i64
fn arg(i: i64, out: u8[>..]&)
fn args() -> u8[:][>..]
fn env(name: const u8[:], out: u8[>..]&) -> bool
fn trim_memory() -> bool
fn resource_dir() -> u8[>..]
fn time() -> f64          fn clock() -> f64
fn time_ns() -> i64       fn clock_ns() -> i64
fn sleep(seconds: f64)    fn sleep_ms(ms: i64)
fn random_seed() -> u64
```

`read_file` appends; nothing is appended on failure. `write_file_atomic`
never leaves a half-written file. `resource_dir()` is the source directory
in a JIT run and the executable directory in a built program. There are no
subprocesses or networking in v1.

---

## ffi

```goose
import ffi;
fn cstr(p: u64, out: u8[>..]&) -> bool
fn cstr(p: u64) -> u8[>..]
fn bytes(p: u64, n: i64, out: u8[>..]&) -> bool
fn bytes(p: u64, n: i64) -> u8[>..]
```

Copies memory a C library owns into Goose storage. A C `char *` returned
as `u64` is read with `ffi::cstr`.

---

## binary

```goose
import binary;

fn range_ok(data: const u8[:], at: i64, size: i64) -> bool
fn read_u8(data, at) -> u8, bool        // and read_i8
fn read_u16le(data, at) -> u16, bool    // and read_u16be, i16, u32, i32, u64, i64, f32, f64
fn read_bytes(data: const u8[:], at: i64, size: i64) -> const u8[:], bool
fn read_name(data: const u8[:], at: i64, width: i64) -> const u8[:], bool

struct Reader { data: const u8[:], pos: i64 }
fn reader(data: const u8[:]) -> Reader
fn read_u8(r: Reader&) -> u8, bool      // every read has a cursor form
fn read_bytes(r: Reader&, size: i64) -> const u8[:], bool
fn skip(r: Reader&, size: i64) -> bool
fn subreader(r: Reader&, size: i64) -> Reader, bool

fn write_u8(out: u8[>..]&, v: u8)
fn write_u16le(out: u8[>..]&, v: u16)   // and every width, le/be
```

Every read returns a trailing `bool`; a failed read leaves the cursor
alone. Reads work at unaligned offsets.

```goose
var r = binary::reader(data);
let magic, ok = binary::read_u32be(r);
if !ok || magic != 0x89504E47 { abort("not a PNG"); }
```

---

## base64

```goose
import base64;
fn encode(out: u8[>..]&, src: const u8[:])
fn decode(out: u8[>..]&, src: const u8[:]) -> bool
```

RFC 4648 standard alphabet and padding. Invalid input returns `false` and
leaves `out` unchanged.

---

## csv

```goose
import csv;
fn each_record<F>(text: const u8[:], sep: u8 = ',') -> bool
fn format_field(out: u8[>..]&, s: u8[:], sep: u8 = ',')
```

`each_record` passes each record's fields as slices of the text; nothing is
copied, and the field slice is reused for the next record. It returns
`false` at the first malformed record after delivering earlier ones.
`format_field` quotes only where needed.

```goose
let ok = csv::each_record(text) { fields =>
    let price, valid = parse_flt(fields[2]);
    if valid { total += price; }
};
```

---

## json

Three APIs in namespace `json`.

### Writer

```goose
fn format_string(out: u8[>..]&, s: u8[:])
fn format_key(out: u8[>..]&, key: u8[:])
fn format_number(out: u8[>..]&, v: f64)
fn format_int(out: u8[>..]&, v: i64)
fn format_bool(out: u8[>..]&, b: bool)
```

The caller writes brackets, braces, and commas.

### Document tree

```goose
struct Node { next: Node&<u32>?, first: Node&<u32>?, key: const u8[:], val: Value }
enum Value { Null, Bool { v: bool }, Int { v: i64 }, Num { v: f64 },
             Str { s: const u8[:] }, Arr { count: i64 }, Obj { count: i64 } }

fn parse(text: u8[:], doc: Node[>..]&, decoded: u8[>..]&) -> Node?, u8[>..]
fn member(n: Node?, key: u8[:]) -> Node?
fn each<F>(n: Node&)                       // F(child)
fn as_f64(n: Node?) -> f64, bool
fn as_i64(n: Node?) -> i64, bool
fn as_bool(n: Node?) -> bool, bool
fn as_string(n: Node?) -> const u8[:], bool
```

```goose
var doc: json::Node[>..] = [];
var decoded: u8[>..] = [];
let root, err = json::parse(text, doc, decoded);
guard root else { abort(err); }
let name, named = json::as_string(json::member(root, "name"));
let items = json::member(root, "items");
if items { json::each(items) { item => print(item); }; }
```

Keys and strings are slices of `text` or `decoded`; nothing else is copied.

### Streaming reader

```goose
struct Reader { text: const u8[:], pos: i64, error: const u8[:], error_at: i64 }
fn reader(text: const u8[:]) -> Reader
fn each_member<F>(r: Reader&)
fn each_element<F>(r: Reader&)
fn read_number(r: Reader&) -> f64
fn read_int(r: Reader&) -> i64
fn read_bool(r: Reader&) -> bool
fn read_string(r: Reader&, scratch: u8[>..]&) -> const u8[:]
fn skip(r: Reader&)
fn peek(r: Reader&) -> u8
fn finish(r: Reader&) -> bool
fn message(r: Reader&) -> u8[>..]
```

Errors are sticky; check once with `finish`.

---

## regex

```goose
import regex;

fn compile(pattern: u8[:]) -> Regex
fn compile(pattern: u8[:], err: u8[>..]&) -> Regex
fn find(re: Regex&, text: u8[:]) -> i64, i64     // start, end; -1, -1
fn matches(re: Regex&, text: u8[:]) -> bool
fn count(re: Regex&, text: u8[:]) -> i64
fn each_match<F>(re: Regex&, text: u8[:])        // F(start, end)
fn each_captures<F>(re: Regex&, text: u8[:])     // F(caps: Captures)
fn format_replaced<F>(out: u8[>..]&, re: Regex&, text: u8[:])
struct Captures { text: const u8[:], slots: const i64[:] }
fn group(c: Captures, k: i64) -> const u8[:]
```

Rust `regex` syntax and matching rules, on bytes. ASCII classes and case
folding. No anchors, word boundaries, Unicode classes, or nested classes.
Compiling builds DFAs up front; do it once, outside a loop.

---

## exception

```goose
import exception;

fn try<E, Body, Catch>()           // Catch(error)
fn try<E, Body>()                  // discard the error
fn try<E, Body, Catch, Finally>()
fn throw(value)
```

Typed errors implemented with `return ... from`. `E` is the error type,
given explicitly: `u8[]`, an integer, or an application struct/enum. The
handler returns an empty `E[]` on success and a singleton on failure.
Errors may carry only references to globals or static data; use owned
`u8[]` for locally produced text. `abort` and `exit` are not catchable.

```goose
fn load() { exception::throw(str("cannot load item ", 42)); }
exception::try<u8[]>(load) { error => print(error); };
```

---

## gfx, audio, physics, ui

These are package modules with large APIs; the authoritative reference is
`docs/stdlib.md` in the Goose repository and the package repositories
(`goose_gfx`, `goose_physics`). Import names are `gfx`, `audio`,
`physics`, and `ui`. They use their own namespaces.

- `gfx` — SDL3 GPU: windows, buffers, textures, pipelines, compute,
  matrices.
- `audio` — procedural PCM playback through SDL3, no window required.
- `physics` — rigid bodies on Box3D: worlds, bodies, shapes, joints,
  queries, recording.
- `ui` — immediate-mode windows and widgets, fonts, text rendering, and
  game HUDs, drawn through `gfx`.

These modules have main-thread rules and are rejected inside a `thread_fn`.
Do not guess their signatures; read the reference for the version in use.
