// Compile-time reflection: const for over fields, variants, types and
// constants, and const if choosing a branch per specialization. Both expand
// into ordinary code, so there is no runtime metadata and no reflection cost.
import std;

struct Item { name: u8[..8], price: i64, tax: i64 = 20, discount: i64 = 0 }
enum Shape { Circle { r: i64 }, Rect { w: i64, h: i64 }, Dot }

// Every field the type does not default, reported once per instantiation.
fn required<T>() {
    const for <N, A> in fields<T> {
        const if !has_default<A> { print("required: ", N); }
    }
}

// A copy of src with every defaulted field reset to its default.
fn reset_defaults<T>(src: T&) -> T {
    T { const for <N, A> in fields<T> { const if !has_default<A> { A: src.A, } }, .. }
}

// Branch on the concrete type, not on a runtime value.
fn describe<T>(v: T) {
    const if same<T, i64> { print("an integer ", v); }
    else const if same<T, Shape> { print("a shape"); }
    else { print("something else: ", v); }
}

// One body generated per variant, so a new variant cannot be forgotten.
// variants<T> needs the enum type itself, so pass a Shape, not a variant.
fn name<T>(v: T) -> u8[>..] {
    var out: u8[>..] = [];
    match v {
        const for <N, V> in variants<T> {
            V p => { out.append(N); },
        },
    }
    return out;
}

fn main() {
    required<Item>();

    var item = Item { name: "pen", price: 5, tax: 7, discount: 3 };
    print(reset_defaults(item));

    describe(1);
    describe(2.5);
    describe(Shape.Dot);

    // A variant literal passed to a generic binds the variant type, so
    // annotate when the enum type is what the body needs.
    let a: Shape = Shape.Circle { r: 1 };
    let b: Shape = Shape.Rect { w: 1, h: 2 };
    let c: Shape = Shape.Dot;
    print(name(a), " ", name(b), " ", name(c));

    // A const for over constants: the body is generated once per entry.
    const for <C> in [1, 2, 4] {
        const if C > 1 { print(C, " is wide"); } else { print(C, " is narrow"); }
    }

    // A const for over types.
    const for <U> in types<i8, u16, f32> { print("default ", default<U>()); }
}
