// Pools for lifetimes that do not nest: slot_pool for independently freed
// slots, slice_pool for contiguous runs that grow and shrink.
import std;
import slot_pool;
import slice_pool;

struct Doc { id: u64, title: u8[..24], text: u8[:] }

fn main() {
    // --- slot_pool: stable slots, explicit reuse -------------------------
    var pool = slot_pool<i64> {};
    let a = pool.alloc_index(10);
    let b = pool.alloc_index(20);
    let c = pool.alloc_index(30);
    print("slots ", a, " ", b, " ", c, " len ", pool.items.len);

    pool.free(b);
    let d = pool.alloc_index(40);          // reuses b
    print("reused ", d, " value ", pool.items[d]);
    print("all slots: ", pool.items);

    // --- slice_pool: runs of elements ------------------------------------
    var bytes = slice_pool<u8> {};
    var s = bytes.alloc_copy("hello");
    print("run: ", s, " len ", s.len);
    s = bytes.realloc_slice(s, 12);
    print("grown: ", s, " cap-ish items ", bytes.items.len);
    bytes.free_slice(s);

    // --- a document store: slot per document, pool per text --------------
    var docs = slot_pool<Doc> {};
    var text = slice_pool<u8> {};

    var id: u64 = 1;
    let idx = docs.alloc_index_with() {
        Doc { id: id, title: "notes", text: text.alloc_copy("first version") }
    };
    let slot .= docs.items[idx];
    print(slot.id, " ", slot.title, ": ", slot.text);
    slot.text = text.realloc_slice(slot.text, 40);
    print("after resize: ", slot.text.len, " bytes, first bytes '", slot.text[..5], "'");

    text.free_slice(slot.text);
    docs.free(idx);
    print("live documents are a logical concept; storage stays valid");
}
