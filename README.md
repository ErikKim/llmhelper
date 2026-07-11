# LLMHelper

**English** · [한국어](README.ko.md)

A tiny macOS menu-bar helper that runs your selected text through a **local [Ollama](https://ollama.com) model** — translate, explain simply, explain in detail, or summarize — and streams the result into a small floating window you can copy from. Everything is a direct call to `localhost:11434`: no internet, no CORS, no API keys.

## Features

- **Global hotkeys** — select text anywhere, then `⌃⌥1` (translate) · `⌃⌥2` (explain simply) · `⌃⌥3` (in detail) · `⌃⌥4` (summarize). The current selection is grabbed automatically.
- **Menu-bar fallback** — copy text (`⌘C`), then click the ✨ menu-bar icon → a mode. No special permission needed.
- **Streaming floating panel** — appears near the cursor, types the answer in live, has a **Copy** button (and `⌘C`), and **auto-closes when it loses focus**.
- **Model picker** — the ✨ menu lists your installed Ollama models (embedding models filtered out); pick one and it applies instantly.
- **Settings window** — edit the Ollama host, model, and the four prompts (the `{text}` placeholder is replaced by your selection). Reset to defaults anytime.
- **GMK keycap lookup** — select a set name (e.g. `GMK Botanical`) and hit `⌃⌥5` to see its base kit / novelties / child-kit renders in a floating panel, pulled from the community catalog at [matrixzj.github.io](https://matrixzj.github.io/docs/gmk-keycaps). No API key, no LLM involved.

## Requirements

- macOS 12 or later
- [Ollama](https://ollama.com) running locally with at least one chat model pulled, e.g.:
  ```bash
  ollama pull qwen3:8b      # good Korean/English quality (default)
  # or a lighter, faster one:
  ollama pull qwen2.5:1.5b-instruct
  ```
- Xcode command-line tools (for `swiftc` / `codesign`) to build

## Build & install

```bash
./build.sh                                   # → build/LLMHelper.app (universal)
cp -R build/LLMHelper.app /Applications/
xattr -cr /Applications/LLMHelper.app        # clear quarantine
open /Applications/LLMHelper.app             # the ✨ icon appears in the menu bar
```

`build.sh` signs with the first valid code-signing identity it finds (e.g. an *Apple Development* cert) so that macOS permissions survive rebuilds; if none is found it falls back to ad-hoc signing. The signed `build/` output is **not** committed.

## Permissions

The **global hotkeys** simulate `⌘C` to grab your selection, which needs the **Accessibility** permission once:

> System Settings ▸ Privacy & Security ▸ **Accessibility** → enable **LLMHelper**

If you'd rather not grant it, use the menu-bar path (`⌘C` then click ✨), which needs no permission.

## Usage

| Action | Hotkey | Menu bar |
|---|---|---|
| Translate (KO↔EN) | `⌃⌥1` | ✨ → 번역 |
| Explain simply | `⌃⌥2` | ✨ → 쉽게 설명 |
| Explain in detail | `⌃⌥3` | ✨ → 상세히 |
| Summarize | `⌃⌥4` | ✨ → 요약 |
| GMK keycap lookup | `⌃⌥5` | ✨ → GMK 검색 |

## Settings

✨ ▸ **설정…** opens a window to change the host, pick a model, and edit each prompt. Use `{text}` where the selected text should go. Saving applies immediately and writes `~/.config/llmhelper/config.json`.

## Contributing

This is a public project — **please open a Pull Request** rather than pushing directly. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Notes

The first version used the macOS right-click **Services** menu, but it didn't show reliably across environments, so it was replaced by the menu-bar + global-hotkey approach.
