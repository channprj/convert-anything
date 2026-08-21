# Convert Anything

Convert Anything은 예측 가능한 로컬 미디어 변환을 위한 네이티브 Dock 없는 macOS 메뉴 막대 유틸리티입니다. 지원되는 파일을 상태 항목이나 팝오버에 놓으면 원본을 그대로 둔 채 효율적인 복사본을 같은 위치에 기록합니다.

[English](README.md)

이 저장소는 현재 로컬 MVP 빌드를 제공합니다. Developer ID로 서명되거나 notarize되지 않았고, 공개 배포 또는 자동 업데이트도 구성되어 있지 않습니다.

## 주요 기능

- 무손실 오디오를 M4A로, M4A를 MP3로, 일반 동영상을 WebM으로, WebM을 MP4로, 일반 이미지를 AVIF로, WebP를 JPG 또는 PNG로 변환하는 6개 기본 경로를 제공합니다.
- 모든 원본을 보존하고, 미디어 검사와 숨김 임시 파일 인코딩 및 결과 검증이 끝난 뒤에만 출력 파일을 게시합니다.
- 한 번에 하나의 작업을 처리하며 진행률, 취소, 재시도, Finder에서 보기, 큐 완료 요약을 제공합니다.
- 번들에 포함된 고정 버전 FFmpeg 도구로 로컬에서 실행되며 계정, 클라우드 업로드, 분석, 텔레메트리, 데이터베이스, 런타임 네트워크 기능이 없습니다.

## 요구 사항

- Apple Silicon Mac
- macOS 14 이상
- Swift 6.2 이상이 포함된 Xcode Command Line Tools
- 번들 미디어 도구 빌드에 필요한 CMake, Ninja, pkg-config

생성되는 앱은 arm64 전용입니다.

## 설치

소스에서 빌드해 `/Applications`에 설치합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/channprj/convert-anything/main/install.sh | zsh
```

설치 프로그램은 깨끗한 소스 아카이브를 내려받고, 고정 버전 미디어 도구 체인과 앱을 빌드하고, 번들을 ad-hoc 서명한 뒤 `/Applications/Convert Anything.app`을 교체하고 실행합니다. 최초 미디어 빌드는 몇 분 걸릴 수 있습니다.

사전 요구 사항, 로컬 체크아웃 설치, 개발 명령은 [사용법](USAGE.md#installation)을 참고하세요.

## 빠른 시작

1. **Convert Anything**을 실행합니다. 앱은 메뉴 막대에만 표시됩니다.
2. 지원되는 파일 하나 이상을 메뉴 막대 아이콘에 놓거나, 아이콘을 클릭하고 팝오버에 놓습니다.
3. 팝오버에서 진행 상황을 확인합니다. 필요에 따라 **Cancel**, **Retry**, **Show Output**, **Show Source**, **Clear**를 사용합니다.

**Settings…**를 열어 변환 규칙을 활성화·편집·추가·삭제하고 품질 프리셋을 선택할 수 있습니다.

## 자세한 문서

- [사용법](USAGE.md) - 설치, 기본 규칙, 명령, 설정, 예제, 검증, 문제 해결
- [아키텍처](ARCHITECTURE.md) - 구성 요소, 데이터 흐름, 디렉터리 구조, 설계 결정
- [서드파티 고지](THIRD_PARTY_NOTICES.md) - 번들 미디어 구성 요소의 라이선스

## 개인정보 보호

앱은 미디어 검사와 변환을 로컬에서 수행합니다. 계정, 클라우드 업로드, 분석, 텔레메트리, 데이터베이스, 런타임 네트워크 기능이 없습니다. 파일 경로는 셸 명령에 삽입되지 않고 인수 배열로 `Process`에 직접 전달됩니다. 빌드 스크립트는 고정된 업스트림 소스 아카이브를 내려받을 때만 네트워크를 사용합니다.

## 라이선스

현재 프로젝트 수준의 `LICENSE` 파일은 포함되어 있지 않습니다. 번들된 서드파티 구성 요소에는 각각의 라이선스가 적용됩니다. 자세한 내용은 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요.
