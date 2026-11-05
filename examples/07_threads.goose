// A worker pool. Threads share no memory: jobs and results cross through
// typed queues as flat values. Build with `goose build`; the JIT cannot place
// thread-local storage.
import std;

struct Job { n: i32 }
struct Result { n: i32, digits: i32 }

fn count_digits(n: i32) -> i32 {
    var v = n;
    var d: i32 = 1;
    while v >= 10 { v /= 10; d++; }
    return d;
}

thread_fn worker() {
    loop {
        let job = qget<Job>();
        guard job.n >= 0 else { break; }        // -1 is the stop job
        qput(Result { n: job.n, digits: count_digits(job.n) });
    }
}

fn main() {
    let workers = max(1, hardware_threads());
    let jobs = 16;

    for i in jobs { qput(Job { n: (1 << (i * 2)) as i32 }); }
    for i in workers { qput(Job { n: -1 }); }

    var ids: i64[>..] = [];
    for i in workers { ids.push(thread_spawn(worker)); }

    var total = 0;
    var seen: i32[..32] = [];
    for i in jobs {
        let r = qget<Result>();
        total += r.digits;
        seen.push(r.n);
    }
    for id in ids { thread_wait(id); }

    sort(seen);
    print(workers, " workers, ", jobs, " jobs, ", total, " digits");
    print("results: ", seen);
}
