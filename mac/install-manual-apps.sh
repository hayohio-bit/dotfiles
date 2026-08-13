#!/usr/bin/env bash
#
# Homebrew 로 설치되지 않거나, 설치 후 사람이 한 번은 손을 대야 하는 앱을 안내한다.
# bootstrap.sh 의 4단계에서 호출되며 단독 실행도 가능하다.
#
# 사용법:
#   ./install-manual-apps.sh              누락된 것만 안내하고 다운로드 페이지를 연다
#   ./install-manual-apps.sh --list-only  브라우저를 열지 않고 목록만 출력
#   ./install-manual-apps.sh --force      설치 여부와 무관하게 전부 안내

set -uo pipefail

LIST_ONLY=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --list-only) LIST_ONLY=1 ;;
    --force)     FORCE=1 ;;
    -h|--help)   sed -n '3,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_GRAY=$'\033[90m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_GRAY=''; C_RESET=''
fi

# 항목 형식: "표시이름|설치확인용 .app 이름|안내 URL|비고"
# .app 이름이 비어 있으면 설치 여부를 판정하지 않고 항상 안내한다.
MANUAL_APPS=(
  "KakaoTalk|KakaoTalk.app|https://apps.apple.com/us/app/kakaotalk/id869223134|Mac App Store 전용. Brewfile 의 mas 항목이 처리하지만, App Store 에 먼저 로그인해야 한다."
  "Bandizip|Bandizip.app|https://apps.apple.com/us/app/bandizip-archiver/id1265704574|Mac App Store 전용. Homebrew cask 가 없다. Keka(cask \"keka\")로 대체해도 된다."
  "Docker Desktop|Docker.app|https://www.docker.com/products/docker-desktop/|cask 로 설치되지만 최초 실행 시 로그인과 권한 승인이 필요하다."
  "Orca|Orca.app|https://www.onorca.dev/docs/install|Homebrew core 에 없어 별도 tap 을 쓴다. tap 이 실패하면 이 페이지에서 직접 받는다."
  "Antigravity|Antigravity.app|https://antigravity.google/download|cask 로 설치되지만 최초 실행 시 Google 계정 로그인이 필요하다."
)

printf '\n  수동 설치 확인 대상\n'

PENDING=()

for entry in "${MANUAL_APPS[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  app="${rest%%|*}"

  if [ "$FORCE" -eq 0 ] && [ -n "$app" ]; then
    # 시스템 전체(/Applications)와 사용자별(~/Applications) 양쪽을 본다.
    if [ -d "/Applications/$app" ] || [ -d "$HOME/Applications/$app" ]; then
      printf '    %s[OK]   %s - 이미 설치됨%s\n' "$C_GREEN" "$name" "$C_RESET"
      continue
    fi
  fi
  PENDING+=("$entry")
done

if [ ${#PENDING[@]} -eq 0 ]; then
  printf '    %s모든 앱이 설치되어 있습니다. 추가 작업 없음.%s\n' "$C_GREEN" "$C_RESET"
  exit 0
fi

for entry in "${PENDING[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  rest="${rest#*|}"
  url="${rest%%|*}"
  note="${rest#*|}"

  printf '    %s[필요] %s%s\n' "$C_YELLOW" "$name" "$C_RESET"
  printf '           %s\n' "$url"
  [ -n "$note" ] && printf '           %s%s%s\n' "$C_GRAY" "$note" "$C_RESET"
done

if [ "$LIST_ONLY" -eq 1 ]; then
  printf '\n    %s--list-only 지정으로 브라우저를 열지 않았습니다.%s\n' "$C_GRAY" "$C_RESET"
  exit 0
fi

printf '\n    %s다운로드 페이지를 엽니다...%s\n' "$C_GRAY" "$C_RESET"
for entry in "${PENDING[@]}"; do
  rest="${entry#*|}"; rest="${rest#*|}"
  url="${rest%%|*}"
  open "$url" 2>/dev/null || printf '    페이지를 열지 못했습니다: %s\n' "$url" >&2
done
