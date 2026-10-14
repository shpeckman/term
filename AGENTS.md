# AGENTS.md

Orientation for AI agents working on this repository.

## What this is

`term` is a Crystal shard for terminal applications built on the kitty family of protocols. Two layers:

- `Term` (src/term.cr, src/term/) — raw mode, input parsing, typed events on a channel, and methods for every kitty-family protocol (keyboard, mouse, graphics, clipboard, notifications, drag-and-drop, colors, pointer shapes).
- `Term::Render` (src/term/render/) — a rendering engine: styled cell planes, compositing with damage tracking and differential ANSI output, palettes and themes, grapheme-aware text layout. Plain classes, framework-agnostic. Decoupled so it can stand alone as a component or part of the shard.

Terminal modes, window sizes, process-group signals and pseudo-terminals come from the `tty` shard (`TTY`, `TTY::PTY`). Do not reimplement termios, ioctl or PTY code here, and do not define anything under the `TTY` namespace. `Term` swallows `TTY::Error` in its private `capture`, `measure`, `raw`, `cooked` and `signal_group` helpers so restore paths never raise. Never use `TTY.on_resize` or `TTY::Winsize.propagate` inside `Term`: they replace its `SIGWINCH` handler.

## Layout

- `src/term.cr` — entrypoint that requires `src/term/*`.
- `src/term/render.cr` — entrypoint that requires `src/term/render/*`, reopening `class Term` as a module target (`class Term; module Render; end`) so `Term::Render` is fully decoupled and can compile independently.
- `src/term/` — the `Term` class split by concern (`config.cr`, `wire.cr`, `session.cr`, `events.cr`, `parser.cr`, `engine.cr`, `color.cr`, `clipboard.cr`, `graphics.cr`, `notify.cr`, `dnd.cr`).
- `src/term/render/` — the render engine.
- `spec/term_spec.cr` — the protocol suite; drives `Term` over pipes and real PTYs opened and spawned with `TTY::PTY`.
- `spec/render/` — the render engine suite; drives `Term::Render` directly with a `ByteBuilder`, no application framework.
- `spec/run.sh` — thorough pre-release run (three builds, random orders, isolation).

## Commands

- `crystal spec` — run the suite once.
- `spec/run.sh` — full matrix before a release (`ONLY`, `REPEATS`, `SEEDS`, `LIMIT` variables).
- `crystal build --no-codegen src/term.cr` — fast compile check of the library.

## Code standards

- Compiler-friendly, performance-focused, idiomatic, data-driven.
- No comments, except every file starts with a comment containing its own path (e.g. `# src/term.cr`).
- Never edit the `version` field in shard.yml.
- Never use `out` as an identifier (reserved keyword).
- Keep the spec files free of top-level local variables (they leak into every example block).
- `Term::Render` must not depend on an application framework; inject callbacks/procs for output, timers and notifications.
