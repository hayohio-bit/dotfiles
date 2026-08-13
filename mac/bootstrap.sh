#!/usr/bin/env bash
#
# 새 Mac 개발환경 자동 구축 스크립트.
#
# Windows 판(../windows/bootstrap.ps1)은 권한 수준에 따라 Scoop / winget 두 경로로
# 나뉘지만, macOS 는 Homebrew 하나로 끝난다. Homebrew 는 최초 설치 때만 sudo 를 요구하고
# 그 뒤로는 관리자 권한 없이 동작하므로 경로를 나눌 이유가 없다.
#
# 사용법:
#   ./bootstrap.sh                     전체 실행
#   ./bootstrap.sh --dry-run           아무것도 설치하지 않고 계획만 출력
#   ./bootstrap.sh --skip-brew         Homebrew 설치 단계 생략
#   ./bootstrap.sh --skip-configs      설정 파일 복사 생략
#   ./bootstrap.sh --upgrade-existing  이미 설치된 항목도 최신 버전으로 갱신
#   ./bootstrap.sh --home-path DIR     설정 파일 복사 대상 지정 (기본값 $HOME)
#
# macOS 기본 bash 는 3.2 이므로 연관 배열 등 4.x 문법은 쓰지 않는다.

# -e 를 켜지 않는다. 개별 앱 설치가 실패해도 나머지를 계속 진행하고
# 마지막에 실패 목록을 모아 보여주는 것이 이 스크립트의 동작이다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/Brewfile"
CONFIGS_DIR="$SCRIPT_DIR/configs"

DRY_RUN=0
SKIP_BREW=0
SKIP_CONFIGS=0
UPGRADE_EXISTING=0
HOME_PATH="$HOME"

WARNINGS=()

# ---------------------------------------------------------------------------
# 출력 헬퍼
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_GRAY=$'\033[90m'; C_MAGENTA=$'\033[35m'; C_RESET=$'\033[0m'
else
  C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_GRAY=''; C_MAGENTA=''; C_RESET=''
fi

step() { printf '\n%s=== %s ===%s\n' "$C_CYAN" "$1" "$C_RESET"; }
ok()   { printf '  %s[OK]   %s%s\n' "$C_GREEN" "$1" "$C_RESET"; }
info() { printf '  %s[..]   %s%s\n' "$C_GRAY" "$1" "$C_RESET"; }
fail() {
  printf '  %s[WARN] %s%s\n' "$C_YELLOW" "$1" "$C_RESET"
  WARNINGS+=("$1")
}
plan() { printf '  %s[계획] %s%s\n' "$C_MAGENTA" "$1" "$C_RESET"; }

usage() {
  sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# 인자 파싱
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)          DRY_RUN=1 ;;
    --skip-brew)        SKIP_BREW=1 ;;
    --skip-configs)     SKIP_CONFIGS=1 ;;
    --upgrade-existing) UPGRADE_EXISTING=1 ;;
    --home-path)
      if [ $# -lt 2 ]; then
        printf '%s--home-path 에 디렉터리를 지정해야 합니다.%s\n' "$C_YELLOW" "$C_RESET" >&2
        exit 2
      fi
      HOME_PATH="$2"; shift ;;
    --home-path=*)      HOME_PATH="${1#*=}" ;;
    -h|--help)          usage ;;
    *)
      printf '%s알 수 없는 옵션: %s%s\n' "$C_YELLOW" "$1" "$C_RESET" >&2
      printf '사용 가능한 옵션은 --help 로 확인하세요.\n' >&2
      exit 2 ;;
  esac
  shift
done

printf '\n개발환경 자동 구축 시작\n'
printf '  스크립트 위치 : %s\n' "$SCRIPT_DIR"
printf '  설정 대상     : %s\n' "$HOME_PATH"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '  실행 모드     : %sDRY RUN (실제 변경 없음)%s\n' "$C_MAGENTA" "$C_RESET"
fi

# ---------------------------------------------------------------------------
# 0. 실행 환경 확인
# ---------------------------------------------------------------------------
step "0. 실행 환경 확인"

if [ "$(uname -s)" != "Darwin" ]; then
  printf '  이 스크립트는 macOS 전용입니다. 현재 OS: %s\n' "$(uname -s)" >&2
  printf '  Windows 는 ../windows/bootstrap.ps1 을 사용하세요.\n' >&2
  exit 1
fi

ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
  BREW_PREFIX="/opt/homebrew"
  ok "Apple Silicon ($ARCH) — Homebrew 경로 $BREW_PREFIX"
else
  BREW_PREFIX="/usr/local"
  ok "Intel ($ARCH) — Homebrew 경로 $BREW_PREFIX"
fi

# Xcode Command Line Tools 는 Homebrew 가 소스에서 빌드할 때(=병에 담긴 바이너리가
# 없는 formula) 필요한 컴파일러와 헤더를 제공한다. Windows 판의 Visual Studio
# Build Tools 에 해당하며, git 도 여기에 포함되어 있다.
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools 설치됨 ($(xcode-select -p))"
elif [ "$DRY_RUN" -eq 1 ]; then
  plan "Xcode Command Line Tools 설치 (xcode-select --install)"
else
  info "Xcode Command Line Tools 설치를 시작합니다. 별도 창이 열리면 '설치' 를 누르세요."
  xcode-select --install >/dev/null 2>&1
  # xcode-select --install 은 GUI 설치 관리자를 띄우고 즉시 반환한다.
  # 설치가 끝나기 전에 다음 단계로 넘어가면 brew 가 소스 빌드에서 실패하므로 여기서 기다린다.
  # 사용자가 설치 창을 닫아버리면 영원히 끝나지 않으므로 상한을 둔다.
  XCODE_WAIT_SECONDS=1800   # 30분
  waited=0
  printf '  설치 창에서 완료될 때까지 기다리는 중 (최대 %d분, Ctrl+C 로 중단)' $((XCODE_WAIT_SECONDS / 60))
  while ! xcode-select -p >/dev/null 2>&1; do
    if [ "$waited" -ge "$XCODE_WAIT_SECONDS" ]; then
      printf '\n'
      fail "Xcode Command Line Tools 설치가 ${XCODE_WAIT_SECONDS}초 안에 끝나지 않았습니다. 설치 창을 확인한 뒤 다시 실행하세요."
      break
    fi
    printf '.'
    sleep 10
    waited=$((waited + 10))
  done
  if xcode-select -p >/dev/null 2>&1; then
    printf '\n'
    ok "Xcode Command Line Tools 설치 완료"
  fi
fi

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
step "1. Homebrew"

if [ "$SKIP_BREW" -eq 1 ]; then
  info "--skip-brew 지정으로 건너뜁니다."
else
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew 설치됨 ($(brew --version | head -1))"
  elif [ -x "$BREW_PREFIX/bin/brew" ]; then
    # 설치는 되어 있으나 현재 셸의 PATH 에 없는 경우다.
    eval "$("$BREW_PREFIX/bin/brew" shellenv)"
    ok "Homebrew 를 PATH 에 반영했습니다 ($BREW_PREFIX)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    plan "Homebrew 설치 (install.sh, sudo 암호 입력 필요)"
  else
    info "Homebrew 를 설치합니다. 관리자 암호를 요구할 수 있습니다."
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      eval "$("$BREW_PREFIX/bin/brew" shellenv)"
      ok "Homebrew 설치 완료"
    else
      fail "Homebrew 설치 실패. https://brew.sh 를 참고해 직접 설치한 뒤 다시 실행하세요."
    fi
  fi
fi

# 로그인 셸에서도 brew 를 찾도록 ~/.zprofile 에 shellenv 를 넣는다.
# macOS 기본 셸은 zsh 이고, 로그인 셸은 ~/.zprofile 을 읽는다.
# Intel(/usr/local/bin)은 기본 PATH 에 있지만 Apple Silicon(/opt/homebrew/bin)은 없다.
ZPROFILE="$HOME_PATH/.zprofile"
SHELLENV_LINE="eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
if [ "$SKIP_BREW" -eq 0 ]; then
  if [ -f "$ZPROFILE" ] && grep -qF "brew shellenv" "$ZPROFILE"; then
    ok "~/.zprofile 에 brew shellenv 가 이미 있습니다."
  elif [ "$DRY_RUN" -eq 1 ]; then
    plan "~/.zprofile 에 brew shellenv 추가"
  else
    {
      printf '\n# Homebrew (dotfiles/mac/bootstrap.sh 가 추가함)\n'
      printf '%s\n' "$SHELLENV_LINE"
    } >>"$ZPROFILE" && ok "~/.zprofile 에 brew shellenv 를 추가했습니다." \
      || fail "~/.zprofile 에 brew shellenv 를 추가하지 못했습니다."
  fi
fi

# ---------------------------------------------------------------------------
# 2. 패키지 설치 (Brewfile)
# ---------------------------------------------------------------------------
step "2. 패키지 설치 (Brewfile)"

if [ "$SKIP_BREW" -eq 1 ]; then
  info "--skip-brew 지정으로 건너뜁니다."
elif [ ! -f "$BREWFILE" ]; then
  fail "목록 파일 없음: $BREWFILE"
elif ! command -v brew >/dev/null 2>&1; then
  # 새 Mac 에서 --dry-run 을 돌리면 brew 가 아직 없는 것이 정상이다.
  # 이때 경고를 내면 "경고 없이 종료" 를 정상 신호로 삼는 검증 절차와 어긋나므로,
  # dry-run 에서는 계획만 알리고 실제 실행에서만 경고로 남긴다.
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "brew bundle install --file=$BREWFILE (1단계에서 Homebrew 를 설치한 뒤 실행됨)"
    info "brew 가 아직 없어 설치 예정 목록은 확인할 수 없습니다."
  else
    fail "brew 명령을 찾을 수 없어 패키지 설치를 건너뜁니다."
  fi
else
  # brew bundle 은 이미 설치된 항목을 건너뛴다. --no-upgrade 를 붙이면
  # 설치된 항목의 버전 갱신까지 막아 재실행이 빨라진다.
  BUNDLE_ARGS=(--file="$BREWFILE" --verbose)
  if [ "$UPGRADE_EXISTING" -eq 0 ]; then
    BUNDLE_ARGS+=(--no-upgrade)
  else
    info "--upgrade-existing 지정: 이미 설치된 항목도 최신 버전으로 갱신합니다."
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    # brew bundle check 는 설치가 필요한 항목만 보고하고 아무것도 변경하지 않는다.
    plan "brew bundle install --file=$BREWFILE"
    brew bundle check --file="$BREWFILE" --verbose || true
  else
    info "brew bundle 실행 중. 앱 수에 따라 20분 이상 걸릴 수 있습니다."
    if brew bundle install "${BUNDLE_ARGS[@]}"; then
      ok "Brewfile 의 모든 항목이 설치되었습니다."
    else
      # brew bundle 은 항목 하나가 실패해도 나머지를 계속 시도하고
      # 마지막에 0 이 아닌 코드로 끝난다. 어떤 항목이 실패했는지는 위 로그에 남는다.
      fail "일부 항목 설치 실패. 위 로그에서 'Installing ... has failed' 를 확인하세요."
      info "설치되지 않고 남은 항목은 아래 명령으로 다시 확인할 수 있습니다."
      info "  brew bundle check --file=$BREWFILE --verbose"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 2-1. keg-only 패키지 PATH 등록
# ---------------------------------------------------------------------------
# Homebrew 는 일부 formula 를 "keg-only" 로 설치한다. 설치는 되지만
# $BREW_PREFIX/bin 에 심볼릭 링크를 만들지 않아 명령이 PATH 에 잡히지 않는 상태다.
# 이 목록의 두 패키지가 그렇다.
#
#   node@24 : 버전이 붙은 formula 라 keg-only. 링크가 없으면 `node` 명령이 없다.
#   rustup  : `rust` formula 와 충돌해 keg-only. `rustup` 명령은 별도 링크가 생기지만
#             `rustc` / `cargo` 는 생기지 않는다.
#
# 그래서 각 패키지의 bin 디렉터리를 ~/.zprofile 의 PATH 앞쪽에 직접 붙인다.
step "2-1. keg-only 패키지 PATH 등록"

KEG_ONLY_FORMULAS="node@24 rustup"

if [ "$SKIP_BREW" -eq 1 ]; then
  info "--skip-brew 지정으로 건너뜁니다."
elif ! command -v brew >/dev/null 2>&1; then
  if [ "$DRY_RUN" -eq 1 ]; then
    for formula in $KEG_ONLY_FORMULAS; do
      plan "~/.zprofile 에 PATH 추가: $BREW_PREFIX/opt/$formula/bin"
    done
  else
    info "brew 명령이 없어 건너뜁니다."
  fi
else
  for formula in $KEG_ONLY_FORMULAS; do
    keg_bin="$BREW_PREFIX/opt/$formula/bin"

    if [ ! -d "$keg_bin" ]; then
      # 2단계에서 설치에 실패했거나 Brewfile 에서 뺀 경우다. 경고는 이미 2단계가 남겼다.
      info "$formula 미설치 — PATH 등록을 건너뜁니다."
      continue
    fi

    if [ -f "$ZPROFILE" ] && grep -qF "$keg_bin" "$ZPROFILE"; then
      ok "$formula — ~/.zprofile 에 이미 등록되어 있습니다."
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      plan "~/.zprofile 에 PATH 추가: $keg_bin"
      continue
    fi

    {
      printf '\n# %s (keg-only, dotfiles/mac/bootstrap.sh 가 추가함)\n' "$formula"
      printf 'export PATH="%s:$PATH"\n' "$keg_bin"
    } >>"$ZPROFILE" && ok "$formula — PATH 에 $keg_bin 을 추가했습니다." \
      || fail "$formula 의 PATH 를 ~/.zprofile 에 추가하지 못했습니다."
  done
fi

# ---------------------------------------------------------------------------
# 3. 설정 파일 배치
# ---------------------------------------------------------------------------
step "3. 설정 파일 배치"

if [ "$SKIP_CONFIGS" -eq 1 ]; then
  info "--skip-configs 지정으로 건너뜁니다."
elif [ ! -d "$CONFIGS_DIR" ]; then
  fail "설정 디렉터리 없음: $CONFIGS_DIR"
else
  if [ ! -d "$HOME_PATH" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      plan "대상 디렉터리 생성: $HOME_PATH"
    else
      mkdir -p "$HOME_PATH" || fail "대상 디렉터리를 만들지 못했습니다: $HOME_PATH"
    fi
  fi

  # configs/ 안의 점 파일을 전부 복사한다. 현재는 .gitconfig 하나뿐이다.
  for src in "$CONFIGS_DIR"/.[!.]*; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    dest="$HOME_PATH/$name"

    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
      ok "$name — 내용이 같아 건너뜁니다."
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      if [ -f "$dest" ]; then
        plan "$name 복사 (기존 파일은 $name.bak 으로 백업)"
      else
        plan "$name 복사 -> $dest"
      fi
      continue
    fi

    if [ -f "$dest" ]; then
      if cp -p "$dest" "$dest.bak"; then
        info "기존 $name 을 $name.bak 으로 백업했습니다."
      else
        fail "$name 백업 실패. 덮어쓰지 않고 건너뜁니다."
        continue
      fi
    fi

    if cp "$src" "$dest"; then
      ok "$name -> $dest"
    else
      fail "$name 복사 실패."
    fi
  done
fi

# ---------------------------------------------------------------------------
# 4. 수동 설치 안내
# ---------------------------------------------------------------------------
step "4. 수동 설치 확인 대상"

if [ -x "$SCRIPT_DIR/install-manual-apps.sh" ]; then
  MANUAL_ARGS=()
  [ "$DRY_RUN" -eq 1 ] && MANUAL_ARGS+=(--list-only)
  "$SCRIPT_DIR/install-manual-apps.sh" "${MANUAL_ARGS[@]+"${MANUAL_ARGS[@]}"}" \
    || fail "install-manual-apps.sh 실행 중 오류가 발생했습니다."
else
  info "install-manual-apps.sh 가 없어 건너뜁니다."
fi

# ---------------------------------------------------------------------------
# 5. 요약
# ---------------------------------------------------------------------------
step "5. 요약"

if [ ${#WARNINGS[@]} -eq 0 ]; then
  printf '  %s경고 없이 종료되었습니다.%s\n' "$C_GREEN" "$C_RESET"
else
  printf '  %s경고 %d건:%s\n' "$C_YELLOW" "${#WARNINGS[@]}" "$C_RESET"
  for w in "${WARNINGS[@]}"; do
    printf '    - %s\n' "$w"
  done
fi

printf '\n'
if [ "$DRY_RUN" -eq 1 ]; then
  printf '  DRY RUN 이므로 실제로 변경된 것은 없습니다.\n'
else
  printf '  터미널을 새로 열어 PATH 를 갱신한 뒤 README 의 "결과 확인" 절을 진행하세요.\n'
fi
printf '\n'

# 경고가 있으면 0 이 아닌 코드로 끝내 자동화에서 실패를 감지할 수 있게 한다.
[ ${#WARNINGS[@]} -eq 0 ]
