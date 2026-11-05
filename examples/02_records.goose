// Records stay inline: one array of orders is one contiguous block with no
// pointers. Also shows a format overload, varint fields, and iteration over
// a sequential array.
import std;

struct Item { sku: u8[varint], qty: varint, cents: varint }
struct Order { id: varint, customer: u8[varint], items: Item[varint] }

struct Receipt { customer: u8[..16], total: i64 }
fn format(out: u8[>..]&, r: Receipt) {
    format(out, r.customer, ": ", r.total, " cents");
}

fn parse_items(field: u8[:]) -> Item[>..] {
    var items: Item[>..] = [];
    each_split(field, ';') {
        let p = split(it, ':');
        guard p.len == 3 else { abort(str("bad item: ", it)); }
        let qty, ok1 = parse_int(p[1]);
        let cents, ok2 = parse_int(p[2]);
        guard ok1 && ok2 else { abort(str("bad numbers: ", it)); }
        items.push(Item { sku: p[0], qty: qty, cents: cents });
    };
    return items;
}

fn order_total(o: Order&) -> i64 {
    var t = 0;
    for it in o.items { t += it.qty * it.cents; }
    return t;
}

fn main() {
    var book: Order[>..] = [];
    book.push(Order {
        id:       1001,
        customer: "alice",
        items:    parse_items("SKU-441:2:1999;SKU-7:1:500"),
    });
    book.push(Order {
        id:       1002,
        customer: "bob",
        items:    parse_items("SKU-900:1:12999"),
    });

    for o in book {
        print(o.customer, " (order ", o.id, ") owes ", order_total(o),
              " cents over ", o.items.len, " items");
    }

    // A sequential array can be walked but not indexed. Keep an index of
    // references beside it when random access is needed.
    var at: (Order&)[>..] = [];
    for o in book { at.push(o); }
    print("second customer: ", at[1].customer);

    // Rendering through the overload works inside aggregates too.
    var receipts: Receipt[>..] = [];
    for o in book { receipts.push(Receipt { customer: o.customer, total: order_total(o) }); }
    print(receipts);
}
