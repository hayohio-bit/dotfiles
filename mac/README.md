# dotfiles — macOS

새 Mac 개발환경 자동 구축 스크립트.
Windows 는 [`../windows/README.md`](../windows/README.md) 를 참고한다.

Windows 판은 권한 수준(관리형 PC / 개인 PC)에 따라 **Scoop(무권한) + winget(관리자)**
이중 구조로 나뉘지만, macOS 는 **Homebrew 하나**로 끝난다.
Homebrew 는 최초 설치 때만 관리자 암호를 요구하고 그 뒤로는 권한 없이 동작하므로
경로를 나눌 이유가 없다.

---

# 새 Mac 설치 절차

아래 1~6단계를 순서대로 따라간다. 총 소요 시간은 30분~1시간이다.
(Xcode Command Line Tools 와 mise 의 JDK 내려받기가 대부분의 시간을 차지한다.)

## 1단계. Xcode Command Line Tools

Homebrew 가 소스에서 패키지를 빌드할 때 필요한 컴파일러와 헤더를 제공한다.
Windows 판의 Visual Studio Build Tools 에 해당한다. git 도 여기에 포함되어 있다.

터미널을 열고 아래를 실행한다.

```bash
xcode-select --install
```

별도 창이 뜨면 **설치**를 누르고 끝날 때까지 기다린다 (10~20분).
이미 설치되어 있으면 `command line tools are already installed` 가 출력되며, 정상이다.

설치 확인:

```bash
xcode-select -p        # /Library/Developer/CommandLineTools
```

> `bootstrap.sh` 도 이 단계를 자동으로 수행하지만, GUI 설치 창이 뜨고 사람이 눌러야
> 진행되므로 먼저 끝내두는 편이 빠르다.

## 2단계. 리포지토리 가져오기

리포지토리가 **private** 이므로 인증이 필요하다.
Homebrew 와 GitHub CLI 를 먼저 설치한다. 이 둘은 `bootstrap.sh` 의 설치 대상이 아니라
**전제 조건**이며, `Brewfile` 에는 재실행 시 상태를 추적하기 위해 등재되어 있다.

Homebrew 를 설치한다.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

설치가 끝나면 **화면 마지막에 출력되는 `Next steps` 안내를 그대로 따라 실행한다.**
Apple Silicon 은 Homebrew 가 `/opt/homebrew` 에 설치되는데 이 경로가 기본 PATH 에 없어,
아래를 실행하지 않으면 `brew` 명령을 찾지 못한다.

```bash
echo >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Intel Mac 은 경로가 `/usr/local` 이므로 위 두 줄의 `/opt/homebrew` 를 `/usr/local` 로 바꾼다.
자기 Mac 이 어느 쪽인지는 `uname -m` 이 `arm64` 면 Apple Silicon, `x86_64` 면 Intel 이다.

이제 GitHub CLI 를 설치하고 인증한다.

```bash
brew install gh
gh auth login
```

- `GitHub.com` → `HTTPS` → `Login with a web browser` 순으로 선택한다.
- 화면에 표시된 8자리 코드를 브라우저에 입력해 인증한다.

인증이 끝나면 리포지토리를 받는다.

```bash
mkdir -p ~/workspace && cd ~/workspace
gh repo clone hayohio-bit/dotfiles
cd dotfiles/mac
```

리포지토리는 OS 별로 디렉터리가 나뉘어 있다. 이후 명령은 모두 `mac/` 안에서 실행한다.

## 3단계. bootstrap 실행

먼저 아무것도 설치하지 않고 계획만 확인한다.

```bash
./bootstrap.sh --dry-run
```

`[계획]` 항목들과 `brew bundle check` 결과가 출력되고 `경고 없이 종료되었습니다` 로
끝나면 정상이다. `목록 파일 없음` 경고가 뜨면 `Brewfile` 까지 제대로 받았는지 확인한다.

> `Permission denied` 가 나면 실행 권한이 없는 것이다. `chmod +x bootstrap.sh install-manual-apps.sh`
> 로 붙이거나 `bash bootstrap.sh --dry-run` 처럼 실행한다.

이상이 없으면 실제로 실행한다.

```bash
./bootstrap.sh
```

cask 앱을 설치할 때 관리자 암호를 여러 번 물을 수 있다. 모두 입력한다.
개별 앱이 실패해도 `[WARN]` 으로 기록하고 다음 앱으로 넘어가며, 마지막에 경고가 모여 출력된다.

마지막 4단계에서 App Store 전용 앱이나 최초 로그인이 필요한 앱이 남아 있으면
안내 페이지가 브라우저로 열린다.

### Mac App Store 앱에 대한 주의

`Brewfile` 의 `mas` 항목(카카오톡, Bandizip)은 **App Store 앱에 미리 로그인해 두어야**
설치된다. 로그인하지 않았거나 그 계정으로 한 번도 받은 적 없는 앱이면 실패하므로,
그럴 때는 App Store 에서 직접 한 번 받은 뒤 `./bootstrap.sh` 를 다시 실행한다.

App Store 를 아예 쓰지 않겠다면 `Brewfile` 아래쪽의 `mas` 두 줄을 지우고,
압축 프로그램은 `cask "keka"` 주석을 푼다.

## 4단계. 결과 확인

**터미널을 새로 연다.** PATH 가 갱신되지 않으면 아래 명령이 전부 실패한다.

아래가 모두 버전 문자열을 출력하면 정상이다.

`node` / `python` / `java` / `bun` 은 mise shim 이 응답하므로,
출력되는 버전은 `configs/mise.toml` 에 적힌 기본값이다.

```bash
brew --version
git --version
gh --version
rg --version           # ripgrep
mise --version

node -v                # v24.x.x  (mise 기본값 = 최신 LTS)
python --version       # Python 3.13.x
java -version          # openjdk version "21.0.x"  (Temurin)
```

`command not found` 가 나오면 터미널을 새로 열지 않았거나, 2단계의 `shellenv` 를
`~/.zprofile` 에 넣지 않은 것이다.

어떤 런타임이 어느 설정 파일 때문에 잡혔는지는 `mise ls` 로 본다.

```bash
mise ls                # 설치된 버전과 그것을 지정한 설정 파일 경로
mise doctor            # activate·shim 구성 진단
```

설정 파일이 배치되었는지 확인한다.

```bash
cat ~/.gitconfig
cat ~/.config/mise/config.toml
```

## 5단계. 런타임 마무리

패키지 설치만으로는 끝나지 않고 한 번 더 손이 필요한 항목이다.

### Rust

Homebrew 의 `rustup` 은 기본 툴체인이 `stable` 로 미리 설정되어 있어
`rustup default stable` 을 실행할 필요가 없다. (Windows 판과 다른 점이다.)
`rustc` 와 `cargo` 는 shim 이라 처음 실행할 때 실제 툴체인을 내려받으므로 잠시 걸린다.

```bash
rustc --version
```

`rustc: command not found` 가 나오면 keg-only PATH 가 등록되지 않은 것이다.
bootstrap 2-1 단계가 `~/.zprofile` 에 아래 줄을 넣었는지 확인한다.

```bash
grep rustup ~/.zprofile
# export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
```

### Java / Node / Python / Bun

전부 mise 가 관리한다. bootstrap 이 끝난 시점에 이미 설치되어 있어야 하며,
따로 손댈 것은 없다. 자세한 사용법은 아래 [mise](#mise) 절을 참고한다.

`java: command not found` 가 나오면 bootstrap 2-2 단계가 `~/.zshrc` 에
활성화 줄을 넣었는지 확인한다.

```bash
grep mise ~/.zshrc
# eval "$(mise activate zsh)"
```

### 컨테이너

Docker Desktop 대신 Colima 를 쓴다. 설치는 되어 있지만 **VM 은 자동으로 뜨지 않는다.**
컨테이너를 쓰기 전에 한 번 띄운다.

```bash
colima start
docker run --rm hello-world
```

자세한 내용은 아래 [Docker](#docker) 절을 참고한다.

### 어느 것이 쓰이는지 확인

```bash
which -a node python java
```

mise 의 shim 경로(`~/.local/share/mise/shims/...`)가 먼저 나와야 한다.
Homebrew 경로나 `/usr/bin` 이 먼저 나오면 PATH 순서 문제다.
2단계의 `shellenv` 줄이 `~/.zprofile` 에, 2-2단계의 `mise activate` 줄이 `~/.zshrc` 에 있는지,
그리고 다른 PATH 설정과의 순서를 확인한다.

## 6단계. PC 고유 git 설정

`configs/.gitconfig` 는 모든 Mac 에 공통으로 적용되는 값만 담는다.
사내 git 서버 credential, `core.hooksPath`, `core.excludesFile` 처럼 PC 마다 달라지는 값은
`~/.gitconfig.local` 에 따로 작성한다. 필요 없으면 이 단계는 건너뛴다.

```bash
nano ~/.gitconfig.local
```

```ini
[credential "https://git.example.co.kr:58021"]
	provider = generic
[core]
	excludesFile = /Users/<사용자>/bin/global-gitignore
	hooksPath = /Users/<사용자>/bin/.githooks
```

`configs/.gitconfig` 마지막의 `[include]` 가 이 파일을 읽어들이며,
같은 키를 다시 정의하면 로컬 값이 우선한다. 파일이 없으면 git 이 조용히 무시한다.

적용 결과는 아래로 확인한다.

```bash
git config --list --show-origin
```

## 7단계. 마무리 점검

- [ ] `git --version` / `mise --version` / `rg --version` 응답
- [ ] `node -v` / `python --version` / `java -version` 모두 응답 (mise shim)
- [ ] `mise doctor` 가 오류 없이 끝남
- [ ] `rustc --version` 응답 (안 되면 5단계의 keg-only PATH 확인)
- [ ] `~/.gitconfig` 존재, `git config user.email` 이 기대값
- [ ] `~/.config/mise/config.toml` 존재
- [ ] 필요 시 `~/.gitconfig.local` 작성 완료
- [ ] Antigravity 실행 및 Google 계정 로그인
- [ ] Orca 실행 및 에이전트(Claude Code 등) 연결 확인
- [ ] `colima start` 후 `docker run --rm hello-world` 성공
- [ ] bootstrap 마지막에 출력된 `[WARN]` 항목 처리 (아래 문제 해결 참고)

---

# 문제 해결

### `brew: command not found`

Apple Silicon 에서 `shellenv` 를 셸 설정에 넣지 않은 경우다.

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"     # 현재 셸에만 임시 반영
```

영구 반영은 2단계의 `~/.zprofile` 추가를 다시 확인한다.

### `zsh: permission denied: ./bootstrap.sh`

실행 권한이 없다. git 이 실행 비트를 유지하지 못한 경우 발생한다.

```bash
chmod +x bootstrap.sh install-manual-apps.sh
```

### `bad interpreter: /usr/bin/env bash^M`

스크립트가 CRLF 줄바꿈으로 체크아웃된 경우다.
리포지토리 루트의 `.gitattributes` 가 `*.sh` 를 LF 로 고정하므로 정상적으로는 생기지 않지만,
ZIP 으로 받았거나 오래된 클론이면 발생할 수 있다.

```bash
cd ..                       # 리포지토리 루트
git rm --cached -r .
git reset --hard
```

### `Error: Cask 'xxx' is unavailable`

cask 이름이 바뀐 경우다. 정확한 이름을 검색해 `Brewfile` 을 고친다.

```bash
brew search xxx
```

이름이 바뀐 전례가 있는 항목: `tailscale` → `tailscale-app`,
`rustup-init` → `rustup`. `docker` 는 지금도 CLI 전용 formula 이고
GUI 앱 cask 는 `docker-desktop` 이다. 이 리포지토리는 CLI 쪽만 쓴다.

### `Error: Cask 'orca' is unavailable` / tap 실패

Orca 는 Homebrew 기본 저장소에 없어 `stablyai/orca` tap 에 의존한다.
tap 이 사라졌거나 이름이 바뀌면 실패하므로, 그때는
[공식 설치 문서](https://www.onorca.dev/docs/install)를 확인해 직접 받는다.
`Brewfile` 의 `tap` 줄과 `cask "orca"` 줄을 주석 처리하면 나머지는 정상 진행된다.

### `mas` 로 App Store 앱 설치 실패

App Store 앱에 로그인되어 있지 않거나, 그 계정으로 해당 앱을 한 번도 받은 적 없는 경우다.
App Store 를 열어 로그인하고 해당 앱을 한 번 직접 받은 뒤 다시 실행한다.
최신 macOS 에서는 `mas signin` 이 동작하지 않으므로 GUI 로그인이 유일한 방법이다.

### 특정 앱만 설치 실패

전체는 계속 진행되므로 나중에 개별 설치하면 된다.
어떤 항목이 빠졌는지는 아래로 확인한다.

```bash
brew bundle check --file=Brewfile --verbose
brew install <formula>
brew install --cask <cask>
```

### 이미 설치된 앱이 있는 Mac 에서 실행할 때

`bootstrap.sh` 는 `brew bundle` 에 `--no-upgrade` 를 붙여 실행한다.
이미 설치된 앱은 건너뛰고 다운로드조차 하지 않는다.

이 옵션이 없으면 `brew bundle` 은 **outdated 인 항목을 전부 업그레이드한다.**
목록의 앱을 최신으로 올리고 싶을 때만 명시한다.

```bash
./bootstrap.sh --upgrade-existing
```

Homebrew 가 아닌 방법으로(공식 dmg 등) 이미 설치한 앱이 있으면 cask 설치가
`It seems there is already an App at ...` 로 실패할 수 있다. 기존 앱을 지우고
다시 실행하거나, 그 항목만 `Brewfile` 에서 빼둔다.

### `~/.gitconfig` 가 덮어써짐

`bootstrap.sh` 는 덮어쓰기 전 `~/.gitconfig.bak` 으로 백업한다.
백업본을 열어 PC 고유 설정을 `~/.gitconfig.local` 로 옮기면 된다.

설정 파일만 건드리지 않으려면 `--skip-configs` 를 쓴다.

```bash
./bootstrap.sh --skip-configs
```

---

# 참고 자료

## 리포지토리 구조

```
dotfiles/
├── README.md                    # OS 선택 안내
├── windows/                     # Windows 용 (별도 문서)
└── mac/
    ├── bootstrap.sh             # 메인 진입점
    ├── install-manual-apps.sh   # 패키지 매니저로 설치되지 않는 앱 안내
    ├── Brewfile                 # Homebrew 설치 목록
    ├── configs/
    │   ├── .gitconfig           # -> ~/.gitconfig
    │   └── mise.toml            # -> ~/.config/mise/config.toml
    └── README.md
```

`bootstrap.sh` 는 자기 위치를 기준으로 `Brewfile` 과 `configs/` 를 찾으므로
어느 디렉터리에서 호출해도 동작한다.

## bootstrap.sh 동작

| 단계 | 내용 |
|---|---|
| 0 | macOS 확인, 아키텍처 판별(Apple Silicon / Intel), Xcode Command Line Tools 확인·설치 |
| 1 | Homebrew 미설치 시 설치 → `~/.zprofile` 에 `brew shellenv` 추가 |
| 2 | `brew bundle install --no-upgrade` 로 `Brewfile` 일괄 설치 |
| 2-1 | keg-only 패키지(`rustup`)의 bin 경로를 `~/.zprofile` 의 PATH 에 추가 |
| 2-2 | `~/.zshrc` 에 `eval "$(mise activate zsh)"` 추가 |
| 2-3 | `docker compose` 플러그인을 `~/.docker/cli-plugins` 에 심볼릭 링크 |
| 3 | `configs/` 의 설정 파일을 배치 (기존 파일은 `.bak` 으로 백업) |
| 3-1 | `mise install` 로 `configs/mise.toml` 의 기본 런타임 설치 |
| 4 | `install-manual-apps.sh` 실행 |
| 5 | 누적된 경고 요약 출력 |

개별 앱 설치 실패는 경고로 기록하고 다음 앱으로 계속 진행한다. 전체가 중단되지 않는다.
경고가 하나라도 있으면 종료 코드 1 로 끝나므로 자동화에서 실패를 감지할 수 있다.

### 옵션

| 옵션 | 설명 |
|---|---|
| `--dry-run` | 실제 변경 없이 수행할 작업만 출력 |
| `--skip-brew` | Homebrew 설치와 `brew bundle` 단계 생략 |
| `--skip-configs` | 설정 파일 복사 생략 |
| `--upgrade-existing` | 이미 설치된 앱도 최신 버전으로 갱신 |
| `--home-path <경로>` | 설정 파일 복사 대상 지정 (기본값 `$HOME`) |
| `--help` | 사용법 출력 |

`--home-path` 는 빈 디렉터리를 지정해 실제 홈을 건드리지 않고 배치 결과를 확인할 때 쓴다.

```bash
./bootstrap.sh --skip-brew --home-path /tmp/newmac
```

### Windows 판에 있고 여기에 없는 것

- **`-Select` 선택 화면.** Windows 판은 설치 항목을 고르는 체크박스 TUI 를 제공한다.
  macOS 는 `brew bundle` 이 이미 설치된 항목을 건너뛰므로 재실행이 저렴하고,
  일부만 설치하려면 `brew install <이름>` 을 직접 쓰는 편이 간단해서 만들지 않았다.
  설치 예정 목록만 보고 싶으면 `brew bundle check --file=Brewfile --verbose` 를 쓴다.
- **`winget-overrides.json` 상당물.** 설치 관리자에 인자를 넘겨야 구성 요소가 결정되는
  패키지(Visual Studio Build Tools)가 macOS 에는 없다. 컴파일러는 Xcode Command Line
  Tools 가 통째로 제공한다.
- **`.wslconfig`.** WSL 은 Windows 전용이다. macOS 에서 컨테이너용 VM 의 자원 제한은
  Colima 를 띄울 때 인자로 준다 (`colima start --cpu 4 --memory 8`).
- **Docker Engine 설치 스크립트.** Windows 는 WSL 배포판 안에 데몬을 직접 깔지만,
  macOS 는 Colima 가 VM 생성과 데몬 기동을 한 번에 처리하므로 별도 스크립트가 없다.

## mise

언어 런타임은 Homebrew 가 아니라 [mise](https://mise.jdx.dev/) 가 관리한다.
프로젝트마다 필요한 버전이 달라서 formula 로 고정할 수 없기 때문이다.

### 어떻게 동작하는가

mise 는 두 가지 방법으로 개입한다.

1. **shim** — 진짜 실행 파일 대신 PATH 에 놓이는 얇은 중계 실행 파일이다.
   `java` 를 치면 shim 이 현재 디렉터리에서 위로 올라가며 `mise.toml` 을 찾아,
   거기 적힌 버전의 실제 `java` 로 넘긴다.
2. **셸 훅** — `eval "$(mise activate zsh)"` 가 zsh 의 디렉터리 변경 훅에 mise 를 건다.
   디렉터리를 옮길 때마다 PATH 와 **환경 변수**를 다시 계산한다.

2번 덕분에 macOS 에서는 `JAVA_HOME` 도 디렉터리에 맞춰 자동으로 바뀐다.
Gradle 과 Maven 이 이 값을 먼저 보므로 중요한 차이다.
(Windows 도 `mise activate pwsh` 로 같은 훅을 건다. 넣는 곳이 PowerShell 프로필일
뿐이다. 자세한 내용은
[`../windows/README.md`](../windows/README.md) 의 "mise" 절에 정리되어 있다.)

bootstrap 2-2 단계가 이 훅을 `~/.zshrc` 에 넣는다. `~/.zprofile` 이 아닌 이유는
`.zprofile` 이 로그인 셸에서만 읽히기 때문이다. Terminal.app 은 매 창이 로그인 셸이라
문제가 없지만, VS Code 나 IntelliJ 의 내장 터미널은 보통 로그인 셸이 아니어서 훅이
걸리지 않는다. PATH 설정(`brew shellenv`, keg-only)은 로그인 시 한 번만 잡히면 되므로
그대로 `.zprofile` 에 둔다.

### 프로젝트별 버전 고정

```bash
cd ~/workspace/어떤-프로젝트
mise use java@temurin-17
mise use node@22
```

저장소 루트에 `mise.toml` 이 만들어진다. **이 파일은 커밋한다.** 팀원과 CI 가 같은
버전을 쓰게 된다. 커밋하지 않을 개인 오버라이드는 `mise.local.toml` 에 적는다.

| 명령 | 하는 일 |
|---|---|
| `mise ls` | 지금 무엇이 잡혔고 어느 설정 파일이 지정했는지 |
| `mise ls-remote java` | 설치 가능한 버전 목록 |
| `mise install` | 현재 디렉터리 설정에 적힌 버전을 전부 받는다 |
| `mise upgrade node` | `lts` 처럼 별칭으로 적은 도구를 최신으로 올린다 |
| `mise doctor` | activate·shim 구성 진단 |

`JAVA_HOME` 이 갱신되지 않으면 `cd .` 로 훅을 한 번 다시 돌린다.

### 이미 Homebrew 로 깐 런타임이 있다면

PATH 앞자리를 두고 shim 과 다툰다. mise 로 옮기기로 했다면 제거하는 편이 낫다.

```bash
brew uninstall node@24 python
brew uninstall --cask temurin@21
```

제거 후 새 터미널에서 `which -a java node python` 으로 shim 이 앞에 오는지 확인한다.

## Docker

Docker Desktop 을 쓰지 않는다. **Colima** 가 그 자리를 맡는다.
Windows 판이 WSL2 안에 Docker Engine 을 직접 까는 것과 같은 선택이다.

### 배경

macOS 에는 리눅스 커널이 없어서 컨테이너를 그대로 돌릴 수 없다. 어느 방식이든
리눅스 VM 안에서 도커 데몬을 띄우고 CLI 가 그 데몬에 붙는 구조다.
Docker Desktop 은 그 VM 과 GUI 를 묶어 파는 상용 제품으로, 일정 규모 이상의
조직에서는 유상 구독이 필요하다. Colima 는 같은 일을 하는 오픈소스 CLI 다
(Lima VM + 도커 데몬).

Brewfile 은 셋을 함께 설치한다. Colima 에 CLI 가 딸려 오지 않기 때문이다.

| 패키지 | 역할 |
|---|---|
| `colima` | 리눅스 VM 을 만들고 그 안에 도커 데몬을 띄운다 |
| `docker` | CLI 전용 formula. GUI 앱이 아니다 |
| `docker-compose` | `docker compose`(하이픈 없음) 하위 명령 |

`docker-compose` 는 formula 지만 실제로는 docker CLI 의 **플러그인**이다.
docker CLI 는 플러그인을 `~/.docker/cli-plugins` 에서 찾는데 Homebrew 는 자기 경로에만
설치하므로, 연결해 주지 않으면 `docker-compose`(하이픈)는 되지만
`docker compose`(하이픈 없음)가 `is not a docker command` 로 실패한다.
bootstrap 2-3 단계가 심볼릭 링크를 걸어 이를 처리한다.

```bash
ls -l ~/.docker/cli-plugins/docker-compose    # 링크 확인
docker compose version
```

링크가 없으면 직접 건다.

```bash
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix)/lib/docker/cli-plugins/docker-compose" \
        ~/.docker/cli-plugins/docker-compose
```

### 쓰는 방법

VM 은 자동으로 뜨지 않는다. 컨테이너를 쓰기 전에 시작한다.

```bash
colima start                        # 기본 자원으로 시작
colima start --cpu 4 --memory 8     # 자원을 지정해 시작
colima status
colima stop                         # 중지 (이미지와 볼륨은 남는다)
colima delete                       # VM 삭제
```

`colima start` 는 `docker` 컨텍스트를 자동으로 등록하므로, 이후에는 평소처럼 쓴다.

```bash
docker run --rm hello-world
docker compose up -d
```

로그인할 때마다 자동으로 띄우려면:

```bash
brew services start colima
```

### Docker Desktop 이 이미 깔려 있다면

두 개의 `docker` CLI 와 두 개의 컨텍스트가 다툰다. 제거하는 편이 낫다.

```bash
brew uninstall --cask docker-desktop
docker context ls        # colima 가 현재 컨텍스트인지 확인
```

## 목록 갱신

현재 Mac 의 설치 상태를 Brewfile 에 반영하려면:

```bash
brew bundle dump --file=Brewfile.new --describe
```

내보낸 뒤 필요한 항목만 골라 `Brewfile` 에 옮긴다.
`dump` 는 의존성으로 딸려온 formula 까지 전부 적으므로 그대로 덮어쓰지 않는다.

`brew bundle cleanup` 은 **Brewfile 에 없는 패키지를 제거하는 파괴적 명령이다.**
이 리포지토리의 스크립트는 쓰지 않으며, 직접 쓸 때도 `--force` 없이 먼저 목록만 확인한다.

## Windows 목록과의 대응

| Windows | macOS | 비고 |
|---|---|---|
| `mise` | `mise` | 양쪽 동일. Java·Node·Python·Bun 을 모두 담당한다 |
| (런타임 없음) | (런타임 없음) | 런타임은 어느 쪽도 패키지 매니저로 깔지 않는다 |
| `7zip` | `sevenzip` | |
| `sudo` | (불필요) | macOS 기본 내장 |
| `ripgrep` / `fzf` | 동일 | |
| `Rustlang.Rustup` | `rustup` | macOS 는 stable 이 기본 설정이라 `rustup default stable` 불필요. keg-only |
| WSL2 + `docker-ce` | `colima` + `docker` + `docker-compose` | 양쪽 모두 Docker Desktop 을 쓰지 않는다 |
| `Oracle.MySQL` | `mysql` | macOS 는 `brew services start mysql` 로 기동 |
| `Google.AndroidStudio` | `cask "android-studio"` | |
| `Microsoft.WindowsTerminal` | (불필요) | Terminal.app 내장. Warp 를 쓴다 |
| `Microsoft.WSL` | (불필요) | macOS 자체가 유닉스 |
| `Microsoft.VCRedist.*` | (불필요) | Windows 전용 |
| `Microsoft.VisualStudio.2022.BuildTools` | Xcode Command Line Tools | `xcode-select --install` |
| `SourceFoundry.HackFonts` | `cask "font-hack"` | |
| `Tailscale.Tailscale` | `cask "tailscale-app"` | `tailscale` 은 CLI 데몬이라 다른 것 |
| `voidtools.Everything.Lite` | (대응물 없음) | Spotlight 로 대체. Raycast/Alfred 는 성격이 다름 |
| `Bandisoft.Bandizip` | `mas` 또는 `cask "keka"` | macOS 판은 App Store 전용 |
| `Kakao.KakaoTalk` | `mas` | cask 없음, App Store 전용 |
| `ZhornSoftware.Stickies` | (불필요) | Stickies.app 기본 내장 |
| 그 외 GUI 앱 | 동명의 cask | Chrome, Obsidian, Notion, Cursor, Zed, DBeaver 등 |
