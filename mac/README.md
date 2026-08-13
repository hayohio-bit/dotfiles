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
(Xcode Command Line Tools 와 Docker Desktop 이 대부분의 시간을 차지한다.)

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

```bash
brew --version
git --version
node -v                # v24.x.x  (Active LTS)
python3 --version      # Python 3.14.x
java -version          # openjdk version "21.0.x"
gh --version
rg --version           # ripgrep
```

`command not found` 가 나오면 터미널을 새로 열지 않았거나, 2단계의 `shellenv` 를
`~/.zprofile` 에 넣지 않은 것이다.

설정 파일이 배치되었는지 확인한다.

```bash
cat ~/.gitconfig
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

### Java

`temurin@21` 은 cask 라 `/Library/Java/JavaVirtualMachines/` 에 설치된다.
macOS 의 `java` 래퍼가 자동으로 찾으므로 보통 그대로 동작하지만,
`JAVA_HOME` 이 필요한 도구(Gradle, Maven 등)를 쓴다면 셸 설정에 넣어둔다.

```bash
echo 'export JAVA_HOME=$(/usr/libexec/java_home -v 21)' >> ~/.zshrc
```

설치된 JDK 목록은 `/usr/libexec/java_home -V` 로 확인한다.

### Node

`node@24` 처럼 **버전이 붙은 formula 는 Homebrew 가 keg-only 로 설치한다.**
설치는 되지만 `/opt/homebrew/bin` 에 심볼릭 링크를 만들지 않아 `node` 명령이 잡히지 않는다.
bootstrap 2-1 단계가 `~/.zprofile` 에 PATH 를 넣어 이 문제를 해결하므로,
`node: command not found` 가 나오면 그 줄이 들어갔는지 확인한다.

```bash
grep node ~/.zprofile
# export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
```

`python` 은 버전 없는 이름이라 keg-only 가 아니며, `python3` 가 바로 잡힌다.

### 어느 것이 쓰이는지 확인

```bash
which -a node python3
```

Homebrew 경로(`/opt/homebrew/...`)가 아닌 것이 먼저 나오면 PATH 순서 문제다.
2단계의 `shellenv` 줄이 `~/.zprofile` 에 있는지, 그리고 다른 PATH 설정과의 순서를 확인한다.

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

- [ ] `git --version` / `node -v` / `python3 --version` / `java -version` 모두 응답
- [ ] `rustc --version` 응답 (안 되면 5단계의 keg-only PATH 확인)
- [ ] `~/.gitconfig` 존재, `git config user.email` 이 기대값
- [ ] 필요 시 `~/.gitconfig.local` 작성 완료
- [ ] Antigravity 실행 및 Google 계정 로그인
- [ ] Orca 실행 및 에이전트(Claude Code 등) 연결 확인
- [ ] Docker Desktop 실행 후 `docker run hello-world` 성공
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

이름이 바뀐 전례가 있는 항목: `docker` → `docker-desktop`,
`tailscale` → `tailscale-app`, `rustup-init` → `rustup`.

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
    │   └── .gitconfig           # -> ~/.gitconfig
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
| 2-1 | keg-only 패키지(`node@24`, `rustup`)의 bin 경로를 `~/.zprofile` 의 PATH 에 추가 |
| 3 | `configs/` 의 설정 파일을 `$HOME` 에 복사 (기존 파일은 `.bak` 으로 백업) |
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
- **`.wslconfig`.** WSL 은 Windows 전용이다. macOS 의 Docker Desktop 도 가상 머신을
  쓰지만 자원 제한은 앱 GUI(Settings → Resources)에서 설정하며 설정 파일이 아니다.

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
| `nodejs-lts` | `node@24` | 새 LTS 가 나오면 번호를 올린다. keg-only 라 PATH 등록 필요 |
| `python` | `python` | 양쪽 모두 최신 안정판을 따라가는 이름 |
| `java/temurin21-jdk` | `cask "temurin@21"` | macOS 에서는 formula 가 아니라 cask |
| `7zip` | `sevenzip` | |
| `sudo` | (불필요) | macOS 기본 내장 |
| `ripgrep` / `fzf` | 동일 | |
| `Rustlang.Rustup` | `rustup` | macOS 는 stable 이 기본 설정이라 `rustup default stable` 불필요. keg-only |
| `Docker.DockerDesktop` | `cask "docker-desktop"` | |
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
