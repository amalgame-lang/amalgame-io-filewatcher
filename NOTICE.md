# NOTICE — amalgame-io-filewatcher

## Authorship

Copyright 2026 Bastien Mouget. The Amalgame facade code in this
repository is original work — see `facade.am` and the
`amalgame.toml` manifest.

This package is part of the Amalgame ecosystem
([github.com/amalgame-lang/Amalgame](https://github.com/amalgame-lang/Amalgame)).
It was extracted from amc's bundled `src/stdlib/io_filewatcher.am`
during the framework split (post-v0.7.5).

## License

Licensed under the Apache License, Version 2.0 — see `LICENSE`.

## Third-party content

None. The facade is 100% pure-Amalgame; a small `@c { … }` block
reaches the OS stat primitives (`stat()` POSIX, `_stat64()`
Windows) without vendoring code.
