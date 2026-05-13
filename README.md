# amalgame-io-filewatcher

Pure-Amalgame file-watch facade for [Amalgame](https://github.com/amalgame-lang/Amalgame).
**Single-file mtime polling** with `Exists()` / `Changed()` /
`GetPath()`. Cross-platform via `stat()` on POSIX and `_stat64()`
on Windows.

Originally bundled in amc's `src/stdlib/io_filewatcher.am`;
extracted into this external package as part of the framework
split (post-v0.7.5).

## Install

```bash
amc package add io-filewatcher                  # via the curated index
amc package add github.com/amalgame-lang/amalgame-io-filewatcher@v0.1.0
```

Requires **amc 0.7.7+**.

## Surface

```amalgame
import Amalgame.IO.FileWatcher

class Program {
    public static void Main() {
        let w = new FileWatcher("/etc/myapp/config.toml")

        // Polling loop: react every time the file is touched, deleted,
        // or recreated.
        while (true) {
            if (w.Changed()) {
                Console.WriteLine("config changed — reloading")
                // … reload …
            }
            // sleep …
        }
    }
}
```

`Changed()` returns `true` once for each distinct mtime transition
(or creation/deletion). The next call after a `true` reading
returns `false` until the next change — same semantics as edge-
triggered notifications.

## Tests

```bash
./tests/run_tests.sh /path/to/amc
```

## License

Apache-2.0 — see `LICENSE`. No vendored third-party code.
