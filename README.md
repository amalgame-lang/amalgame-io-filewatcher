# amalgame-io-filewatcher

File-watch facades for [Amalgame](https://github.com/amalgame-lang/Amalgame),
with two backends:

- **inotify** on Linux — events propagate within ms, no busy
  polling. `Poll()` drains the kernel queue.
- **polling** elsewhere (macOS, Windows, or when inotify_init
  fails) — walks the file/dir on every `Poll()` and diffs
  mtimes against the previous snapshot.

Same API and same `WatchEvent` shape across backends — user code
doesn't branch on platform. Probe the active backend at runtime
via `BackendName() → "inotify" | "polling"`.

Two watcher classes:

- **`FileWatcher(path)`** — single file. `Exists()` / `Changed()` /
  `GetPath()` (v1, kept), plus `Poll()` returning a list of typed
  `WatchEvent` records (v2).
- **`DirectoryWatcher(path, recursive)`** — watches a directory
  (and optionally its subdirectories). On inotify it installs a
  watch per subtree directory at init and grows the watch set
  when subdirs are created at runtime. On polling it walks +
  diffs on every `Poll()`.

Cross-platform via `stat()` / `_stat64` + `opendir/readdir` on
POSIX and `FindFirstFileA`/`FindNextFileA` on Windows. No vendored
third-party code. Originally bundled in amc's
`src/stdlib/io_filewatcher.am`; extracted into this external
package as part of the framework split (post-v0.7.5).

## Install

```bash
amc package add io-filewatcher                  # via the curated index
amc package add github.com/amalgame-lang/amalgame-io-filewatcher@v0.4.0
```

Requires **amc 0.8.47+** (cross-package enum variant dispatch).

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
triggered notifications. Always mtime-based regardless of backend.

## v2 surface — typed `WatchEvent` records

```amalgame
import Amalgame.IO.FileWatcher

class Program {
    public static void Main() {
        let w = new FileWatcher("/etc/myapp/config.toml")
        Console.WriteLine("backend: " + w.BackendName())  // "inotify" or "polling"
        while (true) {
            for ev in w.Poll() {
                if (ev.KindOf() == WatchEventKind.Modified) {
                    Console.WriteLine("modified at ms=" +
                                      String_FromInt(ev.TimestampMs()))
                }
            }
            // sleep …
        }
    }
}
```

`WatchEvent` exposes `KindOf() → WatchEventKind`, `PathOf() →
string`, `RenamedToOf() → string`, `TimestampMs() → int`.
`WatchEventKind` is an enum with four variants: `Created`,
`Modified`, `Deleted`, `Renamed`. Polling and v0.4 inotify backends
never emit `Renamed` (it surfaces as `Deleted` + `Created`) — the
variant is reserved for v0.5's `IN_MOVED_FROM`/`IN_MOVED_TO`
cookie pairing.

## v2 surface — `DirectoryWatcher`

```amalgame
let w = new DirectoryWatcher("./src", true)  // recursive
Console.WriteLine("backend: " + w.BackendName())
while (true) {
    for ev in w.Poll() {
        if (ev.KindOf() == WatchEventKind.Created) {
            Console.WriteLine("created: " + ev.PathOf())
        }
    }
    // sleep …
}
```

Pass `recursive: false` to watch only the top-level directory.
Hidden files and `.git` are **not** pre-filtered — the caller
decides what to ignore.

On inotify with `recursive: true`, watches are added on every
subtree directory at init. When a new subdirectory appears at
runtime, `Poll()` adds a watch on it AND walks the new tree to
emit synthetic `Created` events for any files already inside
(the race window between `mkdir` and our `inotify_add_watch`
where children would otherwise be missed).

## Atomic-rename pattern

Editors (vim, neovim, IDE auto-save) often replace a watched
file by writing to a temp file and `rename(2)`-ing over the
original. inotify sees this as `IN_DELETE_SELF` / `IN_MOVE_SELF`
on the old inode — the kernel then auto-removes the watch.
`FileWatcher.Poll()` handles this transparently: after the
sentinel, it re-stats the path, re-adds a watch on the new
inode, and emits a synthetic `Created` event so the caller
sees a `Deleted` + `Created` pair regardless of the underlying
mechanism.

## Tests

```bash
./tests/run_tests.sh /path/to/amc
```

22 cases: 7 v1 (`Exists`/`Changed`/`GetPath`) + 11 v2 (Poll
events, DirectoryWatcher empty/Created/Deleted/recursive/
non-recursive) + 4 v0.4 inotify-specific (backend probe,
real-time Modify, atomic-rename, recursive new-subdir pickup).
The v0.4 cases SKIP cleanly on non-Linux hosts.

## Roadmap

- **v0.2** — typed `WatchEvent`, `FileWatcher.Poll()`,
  `DirectoryWatcher` (polling backend).
- **v0.3** — `WatchEventKind` migrated from class-with-statics
  to a real `enum` (requires amc 0.8.47+).
- **v0.4 (this release)** — **inotify backend on Linux**:
  reactive watches, recursive subtree expansion, atomic-rename
  recovery. Polling stays the fallback.
- **v0.5** — rename pairing (`IN_MOVED_FROM`/`IN_MOVED_TO`
  cookies) → emit `Renamed` instead of `Deleted` + `Created`.
- **v0.6** — `FSEvents` (macOS), `ReadDirectoryChangesW`
  (Windows). Polling stays the fallback when inotify-equivalent
  isn't available.

## License

Apache-2.0 — see `LICENSE`. No vendored third-party code.
