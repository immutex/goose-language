# Goose patterns

Complete, compiling programs live in `examples/`. This file is the short
form: the shape to reach for, and the rules that make it work.

## Build a result in place

Return a growable value by value. The callee writes directly into the
caller's destination, so there is no temporary and no copy.

```goose
fn squares(n: i64) -> i64[>..] {
    var out: i64[>..] = [];
    for i in n { out.push(i * i); }
    return out;                  // out is the caller's variable
}

let sq = squares(10);

var names: u8[][>..] = [];
names.push(str("item", i));      // formatted straight into the new element
```

Prefer this to an out-parameter. Both cost the same; the return value reads
better.

## Parse one record

Use a trailing `bool` for a two-way outcome, or `T?` for found/not-found.

```goose
struct User { name: u8[..16], age: i32 }

fn parse_user(line: u8[:]) -> User, bool {
    let comma = find(line, ",");
    if comma < 0 { return User { name: "", age: 0 }, false; }
    let age, ok = parse_int(trim(line[comma + 1..]));
    if !ok { return User { name: "", age: 0 }, false; }
    return User { name: trim(line[..comma]), age: age as i32 }, true;
}

let u, ok = parse_user("ada,36");
```

`trim` returns a slice into `line`; assigning it to the `u8[..16]` field
copies it into the record, because a limited-array assignment copies
contents.

## Fail deep, handle far up

`return E from f` leaves the innermost active `f` call. Every function in
between keeps a plain signature.

```goose
fn load(text: u8[:]) -> User[>..], u8[] {
    var users: User[>..] = [];
    var line_no = 0;
    each_split(text, '\n') {
        line_no++;
        if it.len > 0 { users.push(parse_record(it, line_no)); }
    };
    return users, "";
}

fn parse_record(line: u8[:], line_no: i64) -> User {
    let comma = find(line, ",");
    guard comma >= 0 else {
        return [], str("line ", line_no, ": expected name,age") from load;
    }
    let age, ok = parse_int(trim(line[comma + 1..]));
    guard ok else { return [], str("line ", line_no, ": bad age") from load; }
    return User { name: trim(line[..comma]), age: age as i32 };
}

let users, err = load(text);
if err.len > 0 { print("error: ", err); }
```

Use the `exception` module when the throw sites should not name the outer
function:

```goose
import exception;

fn load() { exception::throw(str("cannot load item ", 42)); }
exception::try<u8[]>(load) { error => print(error); };
```

## Records with no pointers

Variable-size fields sit inline. An array of such records is one
contiguous block; it can be iterated, not indexed.

```goose
struct Item  { sku: u8[varint], qty: varint, cents: varint }
struct Order { id: varint, customer: u8[varint], items: Item[varint] }

var book: Order[>..] = [];
book.push(Order { id: 1001, customer: "alice", items: parse_items("SKU-1:2:999") });

for o in book {                       // variable-size elements bind by reference
    var total = 0;
    for it in o.items { total += it.qty * it.cents; }
    print(o.customer, " owes ", total);
}
```

Need random access? Keep an index of references beside it:

```goose
var order_at: (Order&)[>..] = [];
for o in book { order_at.push(o); }
print(order_at[0].customer);
```

For fixed-size indexed records, use an inline string field:

```goose
struct Row { name: u8[..24], count: i64 }
var rows: Row[>..] = [];
rows.push(Row { name: "bolt", count: 3 });
print(rows[0].name);
```

## Tree, list, or graph in one array

Nodes live in a grow-only array; links are references. Because nothing
moves, a reference from `push` stays valid.

```goose
struct Node { key: i32, left: Node&<u32>?, right: Node&<u32>? }   // 12 bytes

fn insert(pool: Node[>..]&, key: i32) {
    if pool.len == 0 { pool.push(Node { key: key }); return; }
    var cur .= pool[0];
    loop {
        if key == cur.key { return; }
        if key < cur.key {
            let l = cur.left;
            if l { cur .= l; continue; }
            cur.left .= pool.push(Node { key: key });
            return;
        }
        let r = cur.right;
        if r { cur .= r; continue; }
        cur.right .= pool.push(Node { key: key });
        return;
    }
}
```

- `T&<u32>` is a 4-byte self-relative link; use it when the structure
  should serialize or move as a whole.
- `T&<u32 in pool>` is measured from a global pool's base; use it when
  other arrays link in.
- Plain `T&` is an 8-byte address; simplest when size does not matter.

See `examples/03_tree.goose` for insertion, lookup, in-order traversal,
serialization, and tamper rejection.

## Recursive traversal

Mark the cycle's entry and write every signature. Keep growable locals out
of the recursive path.

```goose
recursive fn in_order(n: Node&, out: i32[>..]&) {
    let l = n.left;
    if l { in_order(l, out); }
    out.push(n.key);
    let r = n.right;
    if r { in_order(r, out); }
}

var ordered: i32[>..] = [];
in_order(tree[0], ordered);
```

For scratch that must exist during the call, share one grow-shrink stack
and truncate to a mark before returning, or put the scratch in a block
that ends before the recursive call.

## Count with a dictionary

Slices make allocation-free keys. The key's root must outlive the
dictionary, so take keys from an array you keep, not from a by-value loop
copy.

```goose
import dictionary;

struct Row { name: u8[..24], count: i64 }
var records: Row[>..] = [];        // filled at run time

var counts = dictionary<const u8[:], i64> {};
for &r in records {                // & matters: r.name must root at records
    counts.update(r.name, 0) { it += 1; };
}

var rows: Count[>..] = [];
counts.each() { w, n => rows.push(Count { word: w, n: n }); };
sort(rows) { a, b => if a.n != b.n { a.n > b.n } else { compare(a.word, b.word) < 0 } };
```

`for r in records` would copy each fixed-size element, and `r.name` would
be a slice into that dying copy; the dictionary outlives it, so the checker
rejects the store. `for &r` makes the slice root at `records`.

`dictionary` order is hash order, unspecified and dependent on capacity.
Materialize the entries and sort them whenever output order matters; do not
assume insertion or key order.

A fixed-size array is also a valid key: `dictionary<u8[..24], i64>` needs no
`hash` overload and sidesteps the lifetime question by copying the key.

`get` returns `V?`; narrow it before use. A reference from `get` is into
the table, so its last use must come before the next mutation. `update`
does both in one call.

## Pools for non-nested lifetimes

```goose
import slot_pool;
import slice_pool;

struct Doc { id: u64, title: u8[..24], text: u8[:] }

var docs = slot_pool<Doc> {};
var text = slice_pool<u8> {};

let idx = docs.alloc_index_with() {
    Doc { id: 1, title: "notes", text: text.alloc_copy("first version") }
};
let d .= docs.items[idx];
d.text = text.realloc_slice(d.text, 40);   // may move: keep offsets, not slices
text.free_slice(d.text);
docs.free(idx);
```

`free` only records a reusable index. The slot stays initialized and
correctly typed; a stale reference reads a different value, never garbage.

## Generic algorithms and blocks

An untyped parameter is generic. A block is the last argument and is
inlined; `it` is the implicit parameter.

```goose
fn each_pair<T, F>(xs: T[:]) {
    for i in 0..xs.len - 1 { F(xs[i], xs[i + 1]); }
}

fn first_gap(xs: i64[:]) -> i64 {
    each_pair(xs) { a, b => if b - a > 1 { return a; } };   // leaves first_gap
    return -1;
}

let evens = xs.filter() { it % 2 == 0 };
let total = fold(xs, 0) { acc, x => acc + x };
sort(people) { a, b => a.age < b.age };
```

A function value cannot be stored. Stored behaviour is an enum plus case
functions:

```goose
enum Action { Spawn { id: i32 }, Heal { amount: i32 }, Log }

fn run(a: Action.Spawn, w: World&) { ... }
fn run(a: Action.Heal, w: World&) { ... }
fn run(a: Action.Log, w: World&) { ... }

var on_tick: Action[>..] = [];
on_tick.push(Action.Heal { amount: 5 });
for a in on_tick { run(a, world); }
```

## Enum state machine

```goose
enum State { Idle, Running { since: f64 }, Done { code: i32 } }

fn step(s: State&, now: f64) -> State {
    match s {
        Idle => State.Running { since: now },
        Running r => if now - r.since > 1.0 { State.Done { code: 0 } } else { s },
        Done d => s,
    }
}
```

Assign whole fixed-mode enum values to change variant. A variable-mode
value (`State..`) can never change variant.

## Threads

A worker is a separate program with its own globals and data stacks.
Values cross as flat messages through typed queues.

```goose
struct Job { n: i32 }
struct Result { n: i32, digits: i32 }

thread_fn worker() {
    loop {
        let job = qget<Job>();
        guard job.n >= 0 else { break; }
        qput(Result { n: job.n, digits: count_digits(job.n) });
    }
}

fn main() {
    let workers = max(1, hardware_threads());
    for i in 16 { qput(Job { n: i as i32 }); }
    for i in workers { qput(Job { n: -1 }); }
    var ids: i64[>..] = [];
    for i in workers { ids.push(thread_spawn(worker)); }
    for i in 16 { let r = qget<Result>(); print(r.n, " ", r.digits); }
    for id in ids { thread_wait(id); }
}
```

- Only flat values cross: no references or slices at any depth.
- A global written in a worker changes the worker's copy.
- Build with `goose build`; the JIT refuses threads.
- `thread_spawn_contained` isolates a worker's checks and `abort`; its
  message comes back through `thread_wait(id, msg)`.

## Save and load

```goose
var image: u8[>..] = tree.to_bytes();
write_file("tree.bin", image);

var bytes: u8[>..] = [];
if read_file("tree.bin", bytes) {
    var loaded, ok = from_bytes<Node[>..]>(bytes);
    if ok { print(loaded.len, " nodes"); }
}
```

Use self-relative links (`T&<u32>`) if the structure will be saved.
`bytes_of(a)` gives a read-only view without copying. `from_bytes` verifies
safety, not integrity; add a checksum for authenticity.

## Files and arguments

```goose
import os;

fn main() {
    let a = args();                       // a[0] is the program
    guard a.len > 1 else { print("usage: tool file"); exit(2); }

    var text: u8[>..] = [];
    guard read_file(a[1], text) else { abort(str("cannot read ", a[1])); };

    var out: u8[>..] = [];
    each_split(text, '\n') { if it.len > 0 { format(out, "> ", it, "\n"); } };
    guard write_file("out.txt", out) else { abort("cannot write"); };
}
```

`read_file` appends and leaves the buffer alone on failure.
`write_file_atomic` never leaves a half-written file.

## Call C

```goose
extern fn hypot(x: f64, y: f64) -> f64;
extern fn cube_root(x: f64) -> f64 = "cbrt";
extern fn crc32_bytes(s: const u8[:]) -> u32;

print(hypot(3.0, 4.0));
```

A program's own C goes in `foo.build` beside `foo.goose`:

```
c_sources = ["impl.c"];
```

Only plain C shapes cross: scalars, `bool`, flat fixed-size structs and
arrays, slices of those (as `{ data, len }`), and `u8[>..]&`.

## Make a kernel fast

One `assert` of the lengths lets the compiler remove every bounds check in
a loop over slices.

```goose
fn blur_row(above: u8[:], here: u8[:], below: u8[:], out: u8[:]) {
    let W = 512;
    assert(above.len == W && here.len == W && below.len == W && out.len == W);
    for x in 1..W - 1 {
        let sum = above[x - 1] as i64 + above[x] + above[x + 1] +
                  here[x - 1] + here[x] + here[x + 1] +
                  below[x - 1] + below[x] + below[x + 1];
        out[x] = (sum / 9) as! u8;
    }
}
```

Check with `goose check --stats` and `--bce-lines`. Use `checkfree fn` to
require that no check survives, and index types (`u32 in nodes`) to move
validation to where an id is created.

## Complete programs

| File | Shows |
|---|---|
| `examples/01_tour.goose` | every core feature in one linear program |
| `examples/02_records.goose` | inline records, varint, format overload, index array |
| `examples/03_tree.goose` | BST, relative links, recursion, serialization |
| `examples/04_pools.goose` | `slot_pool`, `slice_pool`, document store |
| `examples/05_parser.goose` | recursive descent, nested functions, `return ... from` |
| `examples/06_wordcount.goose` | args, files, dictionary, sort |
| `examples/07_threads.goose` | worker pool and typed queues |
| `examples/08_libs.goose` | JSON, regex, CSV, base64, binary |
