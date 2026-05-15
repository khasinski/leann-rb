# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Minimum Ruby bumped to 3.1 (3.0 is EOL).
- Builder output is now routed through `Leann.logger`; set `Leann.configuration.verbose = false` (or assign a custom logger) to silence progress messages.
- `Leann.build` now respects `Leann.configuration.index_directory` when resolving where to write the index.

### Removed
- Unused `Configuration#chunk_size` and `Configuration#chunk_overlap`. The library has never consumed them; add them back when a real chunker lands.
- Unused `hnswlib` runtime dependency. The pure-Ruby `Leann::Backend::LeannGraph` is the only backend.

### Fixed
- `method redefined; discarding old default_embedding_model=` warning when loading the library.
- Missing `require "set"` in the LEANN graph backend and the ActiveRecord storage backend (would raise on Ruby 3.0/3.1).
- Gemspec packaging warnings: duplicate `homepage_uri`/`source_code_uri` and open-ended dev dependency constraints.

## [0.1.0] - 2026-01-08

- Initial release.
