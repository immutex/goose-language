// The core language in one program: scalars, the array family, strings,
// slices, structs, enums, references, and control flow as expressions.
import std;

struct Point { x: f64, y: f64 }
struct Player { name: u8[..16], pos: Point, hp: i32 = 100, alive: bool = true }

enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }

fn area(s: Shape.Circle) -> f64 { 3.14159 * s.r * s.r }
fn area(s: Shape.Rect) -> f64 { s.w * s.h }
fn area(s: Shape.Dot) -> f64 { 0.0 }

fn total(xs: i64[:]) -> i64 {
    var t = 0;
    for x in xs { t += x; }
    return t;
}

fn main() {
    // Scalars run at their own width. Narrowing needs a cast.
    let byte: u8 = 255;
    print(byte, " wrapped: ", byte + 1, " widened: ", byte + 200);

    // Every array kind stores its elements inline.
    var fixed: i32[4] = [1, 2, 3, 4];
    let zeros: f64[8] = [0.0; 8];
    var grow: i64[>..] = [];
    for i in 5 { grow.push(i * i); }
    var stack: i64[>..<] = [];
    stack.push(1); stack.push(2); stack.push(3);
    var small: u8[..8] = [];
    small.push('h'); small.push('i');
    print(fixed, " ", zeros.len, " ", grow, " ", stack.pop(), " ", small);

    // Strings are u8 arrays: a builder, a finished value, and a view.
    var s: u8[>..] = [];
    s.append("hello");
    s.push(',');
    format(s, " world ", 6 * 7);
    let view: const u8[:] = s[..5];
    print(s, " | ", view, " | ", trim("  padded  "));

    // Slices view without copying.
    var wide: i64[4] = [1, 2, 3, 4];
    print(total(wide), " ", total(grow), " ", total(grow[1..4]), " ", total(grow[^2..]));

    // Structs may hold inline strings, and fields may have defaults.
    var p = Player { name: "gus", pos: Point { 1.0, 2.0 } };
    p.hp -= 30;
    p.pos = p.pos + Point { 0.5, 0.5 };
    print(p, " at ", p.pos.x, ",", p.pos.y);

    // Enums are the only dynamic dispatch.
    var shapes: Shape[>..] = [];
    shapes.push(Shape.Circle { r: 1.0 });
    shapes.push(Shape.Rect { w: 2.0, h: 3.0 });
    shapes.push(Shape.Dot);
    for sh in shapes { print(sh, " area ", area(sh)); }

    // References are transparent; .= binds and retargets.
    var r .= grow[0];
    r += 100;
    print(grow, " ", grow.index_of(r), " ", r .== grow[0]);

    // if / match / block are expressions; guard narrows and early-exits.
    let kind = if p.hp > 50 { "healthy" } else { "hurt" };
    let level = match p.hp { 0 => "dead", 1..50 => "low", _ => "fine" };
    let verdict = block {
        guard p.alive else { break "gone"; }
        guard p.hp > 0 else { break "dead"; }
        "standing"
    };
    print(kind, " ", level, " ", verdict);

    // Loops: ranges, arrays by value, arrays by reference.
    var acc = 0;
    for i in 3 { acc += i; }
    for x in fixed { acc += x; }
    for &x in fixed { x *= 2; }
    for x, i in grow { acc += x * i; }
    var n = 0;
    while n < 3 { n++; }
    loop { n--; if n == 0 { break; } }
    print(acc, " ", fixed, " ", n);
}
