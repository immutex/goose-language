// A recursive-descent expression evaluator. The cursor and input are locals
// of `eval`, the grammar rules are nested functions, and every syntax error
// leaves `eval` with `return ... from`. No Result type, no error parameter.
import std;

fn eval(text: u8[:]) -> f64, u8[] {
    var pos = 0;

    fn skip_ws() {
        while pos < text.len && (text[pos] == ' ' || text[pos] == '\t') { pos++; }
    }

    fn peek() -> u8 {
        skip_ws();
        return if pos < text.len { text[pos] } else { 0 };
    }

    fn number() -> f64 {
        skip_ws();
        let start = pos;
        while pos < text.len && ascii::is_digit(text[pos]) { pos++; }
        if pos < text.len && text[pos] == '.' {
            pos++;
            while pos < text.len && ascii::is_digit(text[pos]) { pos++; }
        }
        guard pos > start else { return 0.0, "expected a number" from eval; }
        let v, ok = parse_flt(text[start..pos]);
        guard ok else { return 0.0, "bad number" from eval; }
        return v;
    }

    recursive fn factor() -> f64 {
        if peek() == '(' {
            pos++;
            let v = expr();
            guard peek() == ')' else { return 0.0, "expected ')'" from eval; }
            pos++;
            return v;
        }
        if peek() == '-' {
            pos++;
            return -factor();
        }
        return number();
    }

    fn term() -> f64 {
        var v = factor();
        loop {
            let c = peek();
            if c == '*' { pos++; v *= factor(); }
            else if c == '/' {
                pos++;
                let d = factor();
                guard d != 0.0 else { return 0.0, "division by zero" from eval; }
                v /= d;
            }
            else { break; }
        }
        return v;
    }

    recursive fn expr() -> f64 {
        var v = term();
        loop {
            let c = peek();
            if c == '+' { pos++; v += term(); }
            else if c == '-' { pos++; v -= term(); }
            else { break; }
        }
        return v;
    }

    let value = expr();
    guard peek() == 0 else { return 0.0, str("trailing input at byte ", pos) from eval; }
    return value, "";
}

fn main() {
    let inputs = ["1 + 2 * 3", "(1 + 2) * 3", "-(4 - 1) / 1.5", "2 * (3 + 4", "1 / 0", "7 % 2"];
    for s in inputs {
        let v, err = eval(s);
        if err.len == 0 { print(s, " = ", v); }
        else { print(s, " -> error: ", err); }
    }
}
