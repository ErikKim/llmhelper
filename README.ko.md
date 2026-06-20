# LLMHelper

[English](README.md) · **한국어**

선택한 텍스트를 **로컬 [Ollama](https://ollama.com) 모델**로 처리하는 작은 macOS 메뉴바 헬퍼. 번역 / 쉽게 설명 / 상세히 결과를 마우스 근처 작은 플로팅 창에 **스트리밍**으로 띄우고 복사할 수 있다. 전부 `localhost:11434` 직접 호출 — 인터넷·CORS·API 키 불필요.

## 기능

- **전역 단축키** — 텍스트 선택 후 `⌃⌥1`(번역) · `⌃⌥2`(쉽게 설명) · `⌃⌥3`(상세히). 선택 영역을 자동으로 집어온다.
- **메뉴바 방식(권한 불필요)** — 텍스트 `⌘C` 복사 후 메뉴바 ✨ 아이콘 → 모드 선택.
- **스트리밍 플로팅 창** — 커서 근처에 떠서 답을 실시간으로 작성, **복사** 버튼(및 `⌘C`), **포커스를 잃으면 자동으로 닫힘**.
- **모델 선택** — ✨ 메뉴에 설치된 Ollama 모델 목록이 뜸(임베딩 모델 제외). 고르면 즉시 적용.
- **설정 창** — Ollama 주소·모델·프롬프트 3개를 편집(`{text}` 자리에 선택 텍스트가 들어감). 기본값 복원 가능.

## 요구 사항

- macOS 12 이상
- 로컬에서 실행 중인 [Ollama](https://ollama.com) + 채팅 모델 1개 이상:
  ```bash
  ollama pull qwen3:8b      # 한/영 품질 좋음 (기본값)
  # 더 가볍고 빠른 모델:
  ollama pull qwen2.5:1.5b-instruct
  ```
- 빌드용 Xcode 커맨드라인 도구(`swiftc` / `codesign`)

## 빌드 & 설치

```bash
./build.sh                                   # → build/LLMHelper.app (universal)
cp -R build/LLMHelper.app /Applications/
xattr -cr /Applications/LLMHelper.app        # quarantine 제거
open /Applications/LLMHelper.app             # 메뉴바에 ✨ 아이콘 등장
```

`build.sh`는 찾을 수 있는 첫 번째 유효 코드서명 인증서(예: *Apple Development*)로 서명해 **빌드해도 권한이 풀리지 않게** 한다. 없으면 ad-hoc 서명으로 폴백. 서명된 `build/` 산출물은 커밋되지 않는다.

## 권한

**전역 단축키**는 선택 영역을 가져오려고 `⌘C`를 대신 눌러주므로 **손쉬운 사용(Accessibility)** 권한이 한 번 필요하다:

> 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ **손쉬운 사용** → **LLMHelper** 켜기

권한을 주기 싫으면 메뉴바 방식(`⌘C` 후 ✨ 클릭)을 쓰면 된다 — 권한 불필요.

## 사용법

| 동작 | 단축키 | 메뉴바 |
|---|---|---|
| 번역 (한↔영) | `⌃⌥1` | ✨ → 번역 |
| 쉽게 설명 | `⌃⌥2` | ✨ → 쉽게 설명 |
| 상세히 | `⌃⌥3` | ✨ → 상세히 |

## 설정

✨ ▸ **설정…** 에서 주소·모델·각 프롬프트를 바꾼다. 선택 텍스트가 들어갈 자리에 `{text}`를 쓴다. 저장하면 즉시 적용되고 `~/.config/llmhelper/config.json`에 기록된다.

## 기여

공개 프로젝트입니다 — 직접 푸시하지 말고 **Pull Request를 보내주세요.** [CONTRIBUTING.md](CONTRIBUTING.md) 참고.

## 메모

초기 버전은 우클릭 **서비스(Services)** 메뉴 방식이었으나 환경에 따라 안정적으로 노출되지 않아 메뉴바 + 전역 단축키 방식으로 교체했다.
