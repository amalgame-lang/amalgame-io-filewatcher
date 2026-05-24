# amalgame-io-filewatcher

File-watch facades for [Amalgame](https://github.com/amalgame-lang/Amalgame).

Two watcher classes on top of mtime polling:

- **`FileWatcher(path)`** — single file. `Exists()` / `Changed()` /
  `GetPath()` (v1, kept), plus `Poll()` returning a list of typed
  `WatchEvent` records (v2).
- **`DirectoryWatcher(path, recursive)`** — walks a directory (and
  optionally its subdirectories) on every `Poll()` and diffs the
  file-set / mtime snapshot to emit `Created` / `Modified` /
  `Deleted` events (v2).

Cross-platform via `stat()` / `_stat64()` + `opendir`/`readdir` on
POSIX and `FindFirstFileA`/`FindNextFileA` on Windows. No vendored
third-party code. Originally bundled in amc's
`src/stdlib/io_filewatcher.am`; extracted into this external
package as part of the framework split (post-v0.7.5).

## Install

```bash
amc package add io-filewatcher                  # via the curated index
amc package add github.com/amalgame-lang/amalgame-io-filewatcher@v0.2.0
```

Requires **amc 0.7.7+**.

## v1 surface — boolean `Changed()`

```amalgame
import Amalgame.IO.FileWatcher

class Program {
    public static void Main() {
        let w = new FileWatcher("/etc/myapp/config.toml")
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
(or creation/deletion); the next call after a `true` reading
returns `false` until the next change — same semantics as edge-
triggered notifications.

## v2 surface — typed `WatchEvent` records

```amalgame
import Amalgame.IO.FileWatcher

class Program {
    public static void Main() {
        let w = new FileWatcher("/etc/myapp/config.toml")
        while (true) {
            for ev in w.Poll() {
                if (ev.KindOf() == WatchEventKind.Modified()) {
                    Console.WriteLine("modified at ms=" +
                                      String_FromInt(ev.TimestampMs()))
                }
            }
            // sleep …
        }
    }
}
```

`WatchEvent` exposes `KindOf() → int`, `PathOf() → string`,
`RenamedToOf() → string`, `TimestampMs() → int`. `WatchEventKind`
ships four static-int methods: `Created()` / `Modified()` /
`Deleted()` / `Renamed()`. Polling backend never emits `Renamed`
(it surfaces as `Deleted` + `Created`) — the field is reserved
for the future inotify / FSEvents / RDCW backends.

## v2 surface — `DirectoryWatcher`

```amalgame
let w = new DirectoryWatcher("./src", true)  // recursive
while (true) {
    for ev in w.Poll() {
        Console.WriteLine(ev.PathOf() + " — kind " +
                          String_FromInt(ev.KindOf()))
    }
    // sleep …
}
```

Pass `recursive: false` to walk only the top-level directory.
Hidden files and `.git` are **not** pre-filtered — the caller
decides what to ignore.

## Tests

```bash
./tests/run_tests.sh /path/to/amc
```

18 cases: 7 v1 + 11 v2 (FileWatcher.Poll Created/Deleted/quiescent,
WatchEvent fields, DirectoryWatcher empty / Created / Deleted /
recursive / non-recursive).

## Roadmap

- **v0.2 (this release)** — typed `WatchEvent`, `FileWatcher.Poll()`,
  `DirectoryWatcher` (polling backend).
- **v0.3** — native backends: inotify (Linux), FSEvents (macOS),
  `ReadDirectoryChangesW` (Windows). The polling backend stays as
  the portable fallback and the canonical test target.

## License

Apache-2.0 — see `LICENSE`. No vendored third-party code.
