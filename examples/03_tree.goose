// A binary search tree in one grow-only array, with 4-byte self-relative
// links. The whole tree is position independent, so it saves and loads as
// bytes with no serializer.
import std;

struct Node { key: i32, count: i32 = 1, left: Node&<u32>?, right: Node&<u32>? }

fn insert(pool: Node[>..]&, key: i32) {
    if pool.len == 0 {
        pool.push(Node { key: key });
        return;
    }
    var cur .= pool[0];
    loop {
        if key == cur.key { cur.count += 1; return; }
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

fn find(pool: Node[>..]&, key: i32) -> Node? {
    if pool.len == 0 { return null; }
    var cur .= pool[0];
    loop {
        if key == cur.key { return cur; }
        let next = if key < cur.key { cur.left } else { cur.right };
        if !next { return null; }
        cur .= next;
    }
}

recursive fn walk(n: Node&, out: i32[>..]&) {
    let l = n.left;
    if l { walk(l, out); }
    out.push(n.key);
    let r = n.right;
    if r { walk(r, out); }
}

fn main() {
    var tree: Node[>..] = [];
    for k in [50, 30, 70, 20, 40, 60, 80, 30, 35, 65] { insert(tree, k as i32); }

    var ordered: i32[>..] = [];
    walk(tree[0], ordered);
    print(tree.len, " nodes: ", ordered);

    let hit = find(tree, 40);
    if hit { print("found ", hit.key, " count ", hit.count); }
    let miss = find(tree, 41);
    print("miss is null: ", miss == null);

    // Self-relative links mean the image is relocatable.
    var image: u8[>..] = tree.to_bytes();
    var loaded, ok = from_bytes<Node[>..]>(image);
    print("loaded ", ok, ", ", loaded.len, " nodes");

    // Tampering is rejected by the verifier, not turned into a wild link.
    image[image.len - 3] = 200;
    var bad, bok = from_bytes<Node[>..]>(image);
    print("accepted tampered image: ", bok, ", nodes ", bad.len);
}
