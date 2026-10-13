# AGENTS.md

Orientation for AI agents working on this repository.

## What this is

`term` is a Crystal shard for terminal applications built on the kitty family of protocols. Two layers:

- `Term` (src/term.cr) — raw mode, input parsing, typed events on a channel, and methods for every kitty-family protocol (keyboard, mouse, graphics, clipboard, notifications, drag-and-drop, colors, pointer shapes).
- `Term::Render` (src/term/render/) — a rendering engine: styled cell planes, compositing with damage tracking and differential ANSI output, palettes and themes, grapheme-aware text layout. Plain classes, framework-agnostic.

`TTY` (src/term/tty.cr) and `PTY` (src/term/pty.cr) are low-level POSIX helpers, top-level names.

## Layout

- `src/term.cr` — the `Term` class; requires everything. Render requires live at the bottom, after `class Term` is defined (`module Term::Render` must not precede it, or Crystal creates `Term` as a module).
- `src/term/render/` — the render engine. Load order is wired in `src/term.cr`.
- `spec/term_spec.cr` — the protocol suite; drives `Term` over pipes and real PTYs.
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
