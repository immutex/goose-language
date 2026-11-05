// Word frequency from a file: arguments, whole-file reads, dictionary keys
// that are slices into one buffer, and a sort by count then word.
import std;
import dictionary;
import os;

struct Count { word: const u8[:], n: i64 }

fn main() {
    let a = args();
    guard a.len > 1 else {
        print("usage: wordcount file...");
        exit(2);
    }

    var text: u8[>..] = [];
    for i in 1..a.len {
        guard read_file(a[i], text) else { abort(str("cannot read ", a[i])); };
        text.push('\n');
    }

    var counts = dictionary<const u8[:], i64> {};
    each_word(text) { counts.update(it, 0) { it += 1; }; };

    var rows: Count[>..] = [];
    counts.each() { w, n => rows.push(Count { word: w, n: n }); };
    sort(rows) { x, y => if x.n != y.n { x.n > y.n } else { compare(x.word, y.word) < 0 } };

    print(counts.count, " distinct words, ", text.len, " bytes");
    let top = min(10, rows.len);
    for i in top { print(rows[i].n, "\t", rows[i].word); }
}
