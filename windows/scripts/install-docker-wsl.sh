#!/usr/bin/env bash
#
# WSL2 의 Ubuntu 안에 Docker Engine(docker-ce)을 설치한다.
# Docker Desktop 을 쓰지 않고 컨테이너를 돌리기 위한 스크립트다.
#
# 이 스크립트는 WSL 안에서 실행된다. Windows 쪽 bootstrap.ps1 이
#   wsl -d <배포판> -- bash <이 파일의 WSL 경로>
# 형태로 호출하며, WSL 터미널에서 직접 실행해도 된다.
#
# 사용법:
#   ./install-docker-wsl.sh              설치한다
#   ./install-docker-wsl.sh --dry-run    실행할 명령만 출력한다
#
# 하는 일
#   1. Docker 공식 apt 저장소를 등록한다. (Ubuntu 기본 저장소의 docker.io 는 버전이 뒤처진다)
#   2. docker-ce / docker-ce-cli / containerd.io / buildx / compose 플러그인을 설치한다.
#   3. 현재 사용자를 docker 그룹에 넣어 sudo 없이 docker 를 쓸 수 있게 한다.
#   4. /etc/wsl.conf 에 systemd=true 를 넣어 dockerd 가 부팅과 함께 뜨게 한다.
#
# 4번이 핵심이다. WSL2 는 기본적으로 init 으로 systemd 를 쓰지 않아서, systemd 없이는
# `sudo service docker start` 를 매번 손으로 쳐야 한다. systemd 를 켜면 설치 과정에서
# 등록된 docker.service 가 배포판 시작 시 자동으로 실행된다.
# 이 설정은 WSL 재시작(Windows 에서 `wsl --shutdown`) 후에 적용된다.

set -uo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf '알 수 없는 옵션: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_GRAY=$'\033[90m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_GRAY=''; C_RESET=''
fi

WARNINGS=()
step() { printf '\n%s=== %s ===%s\n' "$C_CYAN" "$1" "$C_RESET"; }
ok()   { printf '  %s[OK]   %s%s\n' "$C_GREEN" "$1" "$C_RESET"; }
info() { printf '  %s[..]   %s%s\n' "$C_GRAY" "$1" "$C_RESET"; }
plan() { printf '  %s[계획] %s%s\n' "$C_GRAY" "$1" "$C_RESET"; }
fail() { printf '  %s[WARN] %s%s\n' "$C_YELLOW" "$1" "$C_RESET"; WARNINGS+=("$1"); }

# 진행에 지장이 없는 참고 경고. 종료 코드에 반영하지 않는다.
# fail 로 처리하면 네트워크가 잠깐 흔들린 사전 점검 하나 때문에 설치가 다 끝난
# 실행이 종료 코드 1 로 끝나고, bootstrap.ps1 이 이를 "설치 실패"로 보고한다.
notice() { printf '  %s[참고] %s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }

# ---------------------------------------------------------------------------
# 0. 실행 환경 확인
# ---------------------------------------------------------------------------
step "0. 실행 환경 확인"

# WSL 안에서만 의미가 있는 스크립트다. 일반 리눅스에서 잘못 실행하면
# /etc/wsl.conf 라는 쓸모없는 파일만 남기므로 미리 막는다.
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  printf '%s이 스크립트는 WSL 안에서 실행해야 합니다.%s\n' "$C_YELLOW" "$C_RESET" >&2
  printf '현재 커널: %s\n' "$(uname -r)" >&2
  exit 1
fi
ok "WSL 환경 확인 ($(uname -r))"

if ! command -v apt-get >/dev/null 2>&1; then
  printf '%sapt 기반 배포판이 아닙니다. 이 스크립트는 Ubuntu/Debian 전용입니다.%s\n' "$C_YELLOW" "$C_RESET" >&2
  exit 1
fi

# lsb_release 가 없는 최소 이미지가 있어 /etc/os-release 를 직접 읽는다.
# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="$ID"                      # ubuntu | debian
# UBUNTU_CODENAME 을 먼저 본다. Docker 공식 문서와 같은 우선순위다.
# Ubuntu 파생 배포판(Linux Mint, Pop!_OS 등)에서는 VERSION_CODENAME 이 파생판 고유
# 코드네임('vanessa' 등)이고 UBUNTU_CODENAME 이 기반 Ubuntu 코드네임('jammy')인데,
# Docker 저장소에는 Ubuntu 코드네임만 있으므로 순서를 뒤집으면 404 가 난다.
DISTRO_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [ -z "$DISTRO_CODENAME" ]; then
  printf '%s배포판 코드네임을 알 수 없어 저장소를 등록할 수 없습니다.%s\n' "$C_YELLOW" "$C_RESET" >&2
  exit 1
fi

# 저장소 경로도 같은 이유로 보정한다. ID 는 파생판에서 'linuxmint' 같은 값이 되는데
# download.docker.com 에는 ubuntu / debian 경로만 있다. ID_LIKE 로 기반을 찾는다.
case "$DISTRO_ID" in
  ubuntu|debian) ;;
  *)
    # ID_LIKE 는 없는 배포판도 있다. set -u 에 걸리지 않도록 기본값을 준다.
    for base in ${ID_LIKE:-}; do
      case "$base" in
        ubuntu|debian) DISTRO_ID="$base"; break ;;
      esac
    done
    if [ "$DISTRO_ID" != 'ubuntu' ] && [ "$DISTRO_ID" != 'debian' ]; then
      printf '%s지원하지 않는 배포판입니다: %s (Ubuntu/Debian 계열만 가능)%s\n' \
        "$C_YELLOW" "$DISTRO_ID" "$C_RESET" >&2
      exit 1
    fi
    info "파생 배포판을 감지해 기반 배포판 '$DISTRO_ID' 저장소를 씁니다."
    ;;
esac

ok "배포판: $DISTRO_ID $DISTRO_CODENAME"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '  %s실행 모드: DRY RUN (실제 변경 없음)%s\n' "$C_GRAY" "$C_RESET"
fi

# sudo 가 비밀번호를 물으면 bootstrap.ps1 이 넘긴 비대화형 실행에서 멈춘다.
# 미리 한 번 물어 두어 이후 명령이 막히지 않게 한다.
if [ "$DRY_RUN" -eq 0 ] && ! sudo -n true 2>/dev/null; then
  info "sudo 권한이 필요합니다. 비밀번호를 입력하세요."
  sudo -v || { printf '%ssudo 인증에 실패했습니다.%s\n' "$C_YELLOW" "$C_RESET" >&2; exit 1; }
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "$*"
    return 0
  fi
  "$@"
}

# run 은 DRY RUN 에서 아무것도 하지 않고 0 을 돌려준다. 그래서 `if run ...; then ok ...`
# 를 그대로 두면 하지도 않은 일을 "완료"로 보고하게 된다. 완료 메시지는 이 함수로 낸다.
ok_done() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  ok "$1"
}

# ---------------------------------------------------------------------------
# 1. Docker 공식 apt 저장소 등록
# ---------------------------------------------------------------------------
step "1. Docker apt 저장소"

KEYRING=/etc/apt/keyrings/docker.asc
APT_LIST=/etc/apt/sources.list.d/docker.list

# dpkg 아키텍처를 그대로 쓴다. arm64 WSL(Windows on ARM)에서도 맞는 값이 나온다.
ARCH="$(dpkg --print-architecture)"
REPO_LINE="deb [arch=$ARCH signed-by=$KEYRING] https://download.docker.com/linux/$DISTRO_ID $DISTRO_CODENAME stable"

# 파일 존재만 보고 넘어가면 낡은 항목을 고칠 수 없다. WSL 안에서 배포판을 업그레이드하면
# docker.list 에는 이전 코드네임이 남아 apt-get update 가 매번 404 로 실패하는데,
# 그때도 "이미 등록되어 있습니다"라고 보고해 원인에서 멀어진다. 내용까지 대조한다.
if [ -f "$KEYRING" ] && [ -f "$APT_LIST" ] &&
   [ "$(cat "$APT_LIST" 2>/dev/null)" = "$REPO_LINE" ]; then
  ok "저장소가 이미 등록되어 있습니다."
else
  if [ -f "$APT_LIST" ]; then
    info "기존 $APT_LIST 내용이 현재 배포판과 달라 다시 씁니다."
  fi
  # ca-certificates 와 curl 은 GPG 키를 받는 데 필요하고,
  # 최소 이미지에는 빠져 있을 수 있어 먼저 깐다.
  run sudo apt-get update -qq || fail "apt-get update 실패"
  run sudo apt-get install -y -qq ca-certificates curl || fail "ca-certificates/curl 설치 실패"

  run sudo install -m 0755 -d /etc/apt/keyrings || fail "/etc/apt/keyrings 생성 실패"

  if [ "$DRY_RUN" -eq 1 ]; then
    plan "GPG 키 내려받기 -> $KEYRING"
  else
    if sudo curl -fsSL "https://download.docker.com/linux/$DISTRO_ID/gpg" -o "$KEYRING"; then
      sudo chmod a+r "$KEYRING"
      ok "GPG 키 등록: $KEYRING"
    else
      fail "GPG 키를 내려받지 못했습니다. 네트워크나 프록시를 확인하세요."
    fi
  fi

  # Docker 는 배포판 릴리스별로 저장소를 따로 낸다. 갓 나온 Ubuntu 중간 릴리스는
  # 아직 없을 수 있고, 그러면 apt-get update 가 404 로 실패하면서 원인을 알기 어렵다.
  # 등록 전에 한 번 확인해 사람이 읽을 수 있는 메시지를 남긴다.
  RELEASE_URL="https://download.docker.com/linux/$DISTRO_ID/dists/$DISTRO_CODENAME/Release"
  if curl -fsSL -o /dev/null "$RELEASE_URL" 2>/dev/null; then
    ok "Docker 저장소가 $DISTRO_CODENAME 을 지원합니다."
  else
    notice "Docker 저장소에 $DISTRO_CODENAME 용 배포를 확인하지 못했습니다 ($RELEASE_URL). 네트워크 문제일 수도 있습니다. 아래 설치가 실패하면 https://download.docker.com/linux/$DISTRO_ID/dists/ 에서 가장 가까운 이전 릴리스 코드네임을 골라 $APT_LIST 를 직접 고치세요."
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    plan "$APT_LIST 에 기록: $REPO_LINE"
  else
    if printf '%s\n' "$REPO_LINE" | sudo tee "$APT_LIST" >/dev/null; then
      ok "저장소 등록: $APT_LIST"
    else
      fail "저장소 목록을 쓰지 못했습니다."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 2. Docker Engine 설치
# ---------------------------------------------------------------------------
step "2. Docker Engine"

# docker-compose-plugin 이 `docker compose`(하이픈 없음) 를 제공한다.
# 예전 `docker-compose`(하이픈) 는 별도 파이썬 프로그램이고 지금은 쓰지 않는다.
PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

# `command -v docker` 로 판정하면 안 된다. 아래 셋 다 이 조건을 통과하지만
# docker-ce 는 아니다.
#   - Ubuntu 기본 저장소의 docker.io (버전이 뒤처져 이 스크립트가 피하려는 대상)
#   - podman-docker 가 깔아 두는 docker 래퍼
#   - Docker Desktop 이 /mnt/c/Program Files/Docker/... 로 PATH 에 얹는 docker.exe
# 특히 마지막은 Docker Desktop 을 아직 지우지 않은 PC 에서 항상 걸린다. 그러면
# docker-ce 와 compose 플러그인이 설치되지 않은 채 "이미 설치됨"으로 넘어가고,
# 나중에 `docker compose` 가 없다는 오류를 만난다. 패키지로 직접 확인한다.
if [ "$DRY_RUN" -eq 0 ] && dpkg -s docker-ce >/dev/null 2>&1; then
  ok "docker-ce 가 이미 설치되어 있습니다 ($(dpkg-query -W -f='${Version}' docker-ce 2>/dev/null))"
else
  run sudo apt-get update -qq || fail "apt-get update 실패"
  if run sudo apt-get install -y -qq "${PACKAGES[@]}"; then
    ok_done "설치 완료: ${PACKAGES[*]}"
  else
    fail "Docker Engine 설치 실패. 위 apt 로그를 확인하세요."
  fi
fi

# ---------------------------------------------------------------------------
# 3. docker 그룹
# ---------------------------------------------------------------------------
step "3. docker 그룹"

# dockerd 는 /var/run/docker.sock 을 root:docker 소유로 만든다.
# 이 그룹에 들어가지 않으면 docker 명령마다 sudo 가 필요하다.
if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
  ok "$USER 는 이미 docker 그룹입니다."
else
  if run sudo usermod -aG docker "$USER"; then
    ok_done "$USER 를 docker 그룹에 추가했습니다."
    info "그룹 변경은 새 로그인 세션부터 적용됩니다. WSL 을 재시작하세요."
  else
    fail "docker 그룹 추가 실패. docker 명령에 sudo 가 필요할 수 있습니다."
  fi
fi

# ---------------------------------------------------------------------------
# 4. systemd 활성화
# ---------------------------------------------------------------------------
step "4. systemd 활성화 (/etc/wsl.conf)"

# WSL2 는 기본 init 이 systemd 가 아니라서, 켜 주지 않으면 docker.service 가
# 배포판 시작 시 뜨지 않는다. WSL 0.67.6 이상에서 지원한다.
if [ -f /etc/wsl.conf ] && grep -qE '^\s*systemd\s*=\s*true' /etc/wsl.conf; then
  ok "systemd 가 이미 활성화되어 있습니다."
elif [ "$DRY_RUN" -eq 1 ]; then
  plan "/etc/wsl.conf 에 [boot] systemd=true 추가"
elif [ -f /etc/wsl.conf ] && grep -qE '^\s*systemd\s*=' /etc/wsl.conf; then
  # systemd 줄이 있는데 위 true 검사에 걸리지 않았다면 false 로 꺼 둔 상태다.
  # 여기서 새 줄을 끼워 넣으면 true 와 false 가 함께 남아 어느 쪽이 이길지 모호해진다.
  # 기존 줄 자체를 고친다.
  if sudo sed -i -E 's/^([[:space:]]*systemd[[:space:]]*=[[:space:]]*).*/\1true/' /etc/wsl.conf; then
    ok "기존 systemd 설정을 true 로 바꿨습니다."
  else
    fail "/etc/wsl.conf 수정 실패. 직접 [boot] 의 systemd 를 true 로 바꾸세요."
  fi
elif [ -f /etc/wsl.conf ] && grep -qE '^\s*\[boot\]' /etc/wsl.conf; then
  # [boot] 섹션은 있는데 systemd 줄만 없는 경우다. 섹션을 새로 만들면 중복되므로
  # 기존 섹션 바로 아래에 끼워 넣는다.
  if sudo sed -i '0,/^\s*\[boot\]/s//[boot]\nsystemd=true/' /etc/wsl.conf; then
    ok "기존 [boot] 섹션에 systemd=true 를 추가했습니다."
  else
    fail "/etc/wsl.conf 수정 실패. 직접 [boot] systemd=true 를 넣으세요."
  fi
else
  if printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null; then
    ok "/etc/wsl.conf 에 [boot] systemd=true 를 추가했습니다."
  else
    fail "/etc/wsl.conf 를 쓰지 못했습니다. 직접 [boot] systemd=true 를 넣으세요."
  fi
fi

# systemd 가 이미 돌고 있으면 지금 바로 서비스를 켜 둔다.
# 아직 아니면 WSL 재시작 후에 자동으로 뜬다.
if [ "$DRY_RUN" -eq 0 ] && [ -d /run/systemd/system ]; then
  run sudo systemctl enable --now docker >/dev/null 2>&1 \
    && ok "docker.service 를 활성화했습니다." \
    || fail "docker.service 활성화 실패. WSL 재시작 후 다시 확인하세요."
fi

# ---------------------------------------------------------------------------
# 5. 요약
# ---------------------------------------------------------------------------
step "5. 요약"

if [ ${#WARNINGS[@]} -eq 0 ]; then
  printf '  %s경고 없이 종료되었습니다.%s\n' "$C_GREEN" "$C_RESET"
else
  printf '  %s경고 %d건:%s\n' "$C_YELLOW" "${#WARNINGS[@]}" "$C_RESET"
  for w in "${WARNINGS[@]}"; do printf '    - %s\n' "$w"; done
fi

printf '\n'
if [ "$DRY_RUN" -eq 1 ]; then
  printf '  DRY RUN 이므로 실제로 변경된 것은 없습니다.\n\n'
  exit 0
fi

cat <<'EOF'
  다음 단계 (Windows PowerShell 에서):
    1) wsl --shutdown              systemd 와 docker 그룹 변경을 적용한다
    2) wsl                         배포판을 다시 연다
    3) docker run --rm hello-world 동작을 확인한다

  Windows 쪽 터미널(PowerShell)에서 docker 를 바로 쓰려면 windows/README.md 의
  "Docker" 절을 참고한다.
EOF
printf '\n'

[ ${#WARNINGS[@]} -eq 0 ] || exit 1
