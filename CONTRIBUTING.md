# Contributing to LLMHelper

Thanks for your interest! Contributions go through **Pull Requests** — please don't push directly to `main`.

## Workflow

1. **Fork** this repository.
2. Create a branch off `main`:
   ```bash
   git checkout -b feature/my-change
   ```
3. Make your change and build/run it locally:
   ```bash
   ./build.sh
   cp -R build/LLMHelper.app /Applications/ && xattr -cr /Applications/LLMHelper.app
   open /Applications/LLMHelper.app
   ```
4. Commit with a clear message and **open a Pull Request** against `main`.

## Guidelines

- **Never commit `build/` or any signing material** (`*.p12`, `*.pem`, `signing/`). The build is signed with each contributor's own identity; committing it would leak that identity. These are already in `.gitignore`.
- Keep the app a single dependency-free Swift file where reasonable (`Sources/main.swift`).
- Update both `README.md` (English) and `README.ko.md` (Korean) when you change user-facing behavior.
- Describe in the PR what you changed and how you tested it (which macOS version, which Ollama model).

## Scope ideas

- New modes / prompt presets
- Better result-window UX (markdown rendering, resize memory)
- Response length / temperature controls in Settings
- Optional auto-copy without Accessibility (e.g. Services revival per-app)

Open an issue first if you're planning a large change, so we can align before you build it.
