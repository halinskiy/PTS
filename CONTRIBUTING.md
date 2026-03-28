# Contributing

## Development Setup

1. Build the project with `make`.
2. Run it with `make run` or `make debug`.
3. Before sending a change, run `make` again to confirm the package still compiles.

## Guidelines

- Keep behavior-preserving refactors separate from animation or gameplay changes.
- Prefer small pull requests with a clear reason for the change.
- Preserve the pixel-art look when editing sprite data or drawing code.
- Add concise comments only where the code would otherwise be hard to follow.

## Project Conventions

- Shared constants and sprite grids live under `Sources/PixelClaw/Support`.
- AppKit drawing code lives under `Sources/PixelClaw/Views`.
- Runtime behavior and state transitions live under `Sources/PixelClaw/App`.
