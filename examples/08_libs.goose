// The text and binary modules: JSON, regex, CSV, base64, and checked
// little-endian reads and writes.
import std;
import json;
import regex;
import csv;
import base64;
import binary;

fn main() {
    // --- JSON tree --------------------------------------------------------
    let text = "{\"name\": \"goose\", \"tags\": [1, 2, 3], \"ok\": true}";
    var doc:     json::Node[>..] = [];
    var decoded: u8[>..]         = [];
    let root, err = json::parse(text, doc, decoded);
    guard root else { abort(err); }

    let name, named = json::as_string(json::member(root, "name"));
    let ok, okk = json::as_bool(json::member(root, "ok"));
    print("name=", named, " ", name, " ok=", okk, " ", ok);
    let tags = json::member(root, "tags");
    if tags {
        var sum = 0.0;
        json::each(tags) { t => let v, _ = json::as_f64(t); sum += v; };
        print("tag sum ", sum);
    }

    // --- JSON writer ------------------------------------------------------
    var out: u8[>..] = [];
    out.push('{');
    json::format_key(out, "count");
    json::format_int(out, doc.len);
    out.push(',');
    json::format_key(out, "name");
    json::format_string(out, name);
    out.append("}");
    print(out);

    // --- regex ------------------------------------------------------------
    let re = regex::compile("(\\w+)@(\\w+)\\.com");
    let s, e = regex::find(re, "mail ada@example.com now");
    if s >= 0 { print("match: ", "mail ada@example.com now"[s..e]); }
    print("matches ", regex::matches(re, "x@y.com"));

    // --- CSV --------------------------------------------------------------
    let rows = "name,price\nbolt,1.5\nnut,0.25\n";
    var total = 0.0;
    let csv_ok = csv::each_record(rows) { f =>
        if f.len == 2 {
            let price, valid = parse_flt(f[1]);
            if valid { total += price; }
        }
    };
    print("csv ok ", csv_ok, " total ", total);

    // --- base64 -----------------------------------------------------------
    var enc: u8[>..] = [];
    base64::encode(enc, "goose");
    var dec: u8[>..] = [];
    let dok = base64::decode(dec, enc);
    print("base64 ", enc, " -> ", dok, " ", dec);

    // --- binary -----------------------------------------------------------
    var bin: u8[>..] = [];
    binary::write_u32be(bin, 0x89504E47);
    binary::write_u16le(bin, 3);
    let magic, mok = binary::read_u32be(bin, 0);
    let version, vok = binary::read_u16le(bin, 4);
    print("binary ", mok, " ", magic, " ", vok, " ", version);
}
