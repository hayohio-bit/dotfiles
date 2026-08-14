# dotfiles — Windows

새 Windows PC 개발환경 자동 구축 스크립트.
macOS 는 [`../mac/README.md`](../mac/README.md) 를 참고한다.

권한 수준이 확정되지 않은 상황(관리형 PC / 개인 PC)에 대응하기 위해
**Scoop(무권한) + winget(관리자 권한)** 이중 구조로 구성되어 있다.
Scoop 단계는 어떤 PC에서도 실행되므로, winget 단계가 통째로 실패해도 개발은 시작할 수 있다.

---

# 새 PC 설치 절차

아래 1~7단계를 순서대로 따라간다. 총 소요 시간은 30분~1시간이다.
(Visual Studio Build Tools, mise 의 JDK 내려받기, WSL Docker Engine 설치가
대부분의 시간을 차지한다.)

## 1단계. 권한 확인

PowerShell 을 열고 아래를 실행한다.

```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

관리자 권한으로 PowerShell 을 열려면 `Win + X` → **터미널(관리자)** 를 선택한다.

| 결과 | 진행할 경로 |
|---|---|
| `True` 로 열 수 있음 | 2단계 **경로 A** |
| 관리자로 열 수 없음 | 2단계 **경로 B** |

## 2단계. 리포지토리 가져오기

리포지토리가 **private** 이므로 인증이 필요하다.
또한 새 PC 에는 git 이 없는데 리포지토리를 받으려면 git 이 있어야 하므로,
이 단계에서 git 과 gh 를 먼저 설치한다. 두 도구는 `bootstrap.ps1` 의 설치 대상이 아니라
**전제 조건**이며, `apps/winget-apps.json` 에는 재실행 시 상태를 추적하기 위해 등재되어 있다.

### 경로 A — 관리자 권한 있음

관리자 PowerShell 에서 git 과 GitHub CLI 를 먼저 설치한다.

```powershell
winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements
```

**설치 후 PowerShell 을 새로 연다.** (PATH 가 갱신되어야 `git` / `gh` 명령을 찾는다.)

```powershell
gh auth login
```

- `GitHub.com` → `HTTPS` → `Login with a web browser` 순으로 선택한다.
- 화면에 표시된 8자리 코드를 브라우저에 입력해 인증한다.

인증이 끝나면 리포지토리를 받는다.

```powershell
cd $HOME\workspace          # 없으면: mkdir $HOME\workspace
gh repo clone hayohio-bit/dotfiles
cd dotfiles\windows
```

리포지토리는 OS 별로 디렉터리가 나뉘어 있다. 이후 명령은 모두 `windows\` 안에서 실행한다.

### 경로 B — 관리자 권한 없음

winget 으로 git 을 설치하는 것부터 막힐 수 있으므로 브라우저로 받는다.

1. 브라우저에서 GitHub 에 로그인한다.
2. https://github.com/hayohio-bit/dotfiles 접속
3. 초록색 **Code** 버튼 → **Download ZIP**
4. 받은 ZIP 을 `C:\Users\<사용자>\workspace\` 에 압축 해제한다.

압축 해제한 파일은 인터넷에서 받은 표시(Mark of the Web)가 붙어 실행이 차단되므로 해제한다.

```powershell
cd $HOME\workspace\dotfiles-main    # 폴더명은 압축 해제 결과에 맞춘다
Get-ChildItem -Recurse | Unblock-File
cd windows
```

## 3단계. bootstrap 실행

Windows 11 의 기본 실행 정책은 `Restricted` 라 `.\bootstrap.ps1` 이 바로 실행되지 않는다.
스크립트 안에 정책을 푸는 코드가 있지만 스크립트가 시작되어야 그 코드가 도는 구조이므로,
**첫 실행만 `-ExecutionPolicy Bypass` 로 우회한다.**

먼저 아무것도 설치하지 않고 계획만 확인한다.

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -DryRun
```

`설치 예정:` 목록과 `winget import 예정:` 이 출력되고 `경고 없이 종료되었습니다` 로 끝나면 정상이다.
`목록 파일 없음` 경고가 뜨면 `apps\` 폴더까지 제대로 받았는지 확인한다.

이상이 없으면 실제로 실행한다.

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

목록 전체가 아니라 **설치할 항목을 직접 고르고 싶으면** `-Select` 를 붙인다.

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Select
```

방향키로 이동하고 Space 로 선택/해제한 뒤 Enter 로 확정한다.
이미 설치된 항목은 자동으로 해제 상태로 표시되므로, 그대로 Enter 를 누르면
빠진 것만 설치된다. 자세한 조작은 아래 [설치 항목 선택 화면](#설치-항목-선택-화면) 참고.

실행 중 UAC 창이 여러 번 뜰 수 있다. 모두 허용한다.
개별 앱이 실패해도 `[WARN]` 으로 기록하고 다음 앱으로 넘어가며, 마지막에 경고가 모여 출력된다.

3-1 단계는 PATH 와 PowerShell 프로필을 손보고 mise 로 기본 런타임(JDK, Node,
Python, Bun)을 내려받는다. 몇 분 걸린다.
4단계는 WSL 배포판 안에 Docker Engine 을 설치하며, 이때 WSL 의 sudo 비밀번호를 묻는다.

마지막 5단계에서 Orca / Antigravity 중 winget 으로 설치되지 않은 것이 있으면
다운로드 페이지가 브라우저로 열린다. 열린 페이지에서 설치 파일을 받아 수동 설치한다.

## 4단계. 결과 확인

**PowerShell 을 새로 연다.** PATH 가 갱신되지 않으면 아래 명령이 전부 실패한다.
mise 의 shim 디렉터리 등록도 이때 반영된다.

아래가 모두 버전 문자열을 출력하면 정상이다.
`node` / `python` / `java` / `bun` 은 mise shim 이 응답하므로,
출력되는 버전은 `configs/mise.toml` 에 적힌 기본값이다.

```powershell
git --version          # git version 2.55.x
gh --version
rg --version           # ripgrep
mise --version

node -v                # v24.x.x   (mise 기본값 = 최신 LTS)
python --version       # Python 3.13.x
java -version          # openjdk version "21.0.x"  (Temurin)
```

`명령을 찾을 수 없습니다` 가 나오면 PowerShell 을 새로 열지 않은 것이다.

어떤 런타임이 어느 설정 파일 때문에 잡혔는지는 `mise ls` 로 본다.

```powershell
mise ls                # 설치된 버전과 그것을 지정한 설정 파일 경로
mise doctor            # PATH·shim 구성이 올바른지 진단
```

설정 파일이 배치되었는지 확인한다.

```powershell
Get-Content $HOME\.gitconfig
Get-Content $HOME\.wslconfig
Get-Content $HOME\.config\mise\config.toml
```

## 5단계. PC 고유 git 설정

`configs/.gitconfig` 는 모든 PC 에 공통으로 적용되는 값만 담는다.
사내 git 서버 credential, `core.hooksPath`, `core.excludesFile` 처럼 PC 마다 달라지는 값은
`~/.gitconfig.local` 에 따로 작성한다. 필요 없으면 이 단계는 건너뛴다.

```powershell
notepad $HOME\.gitconfig.local
```

```ini
[credential "https://git.example.co.kr:58021"]
	provider = generic
[core]
	excludesFile = C:/Users/<사용자>/bin/global-gitignore
	hooksPath = C:/Users/<사용자>/bin/.githooks
```

`configs/.gitconfig` 마지막의 `[include]` 가 이 파일을 읽어들이며,
같은 키를 다시 정의하면 로컬 값이 우선한다. 파일이 없으면 git 이 조용히 무시한다.

적용 결과는 아래로 확인한다.

```powershell
git config --list --show-origin
```

## 6단계. WSL 및 Docker 마무리

먼저 WSL 이 동작하는지 확인한다.

```powershell
wsl --status
```

기본 배포판과 WSL 버전이 출력되면 정상이다.
오류가 나거나 설치되지 않았다는 메시지가 나오면 WSL 기능이 아직 활성화되지 않은 것이므로,
**재부팅한 뒤** 아래를 실행하고 다시 확인한다.

```powershell
wsl --install
```

배포판이 하나도 없으면 설치한다. Docker Engine 이 이 배포판 안에 들어가므로
컨테이너를 쓸 계획이면 반드시 필요하다.

```powershell
wsl --install -d Ubuntu
```

배포판을 새로 깔았다면 bootstrap 의 4단계만 다시 돌려 Docker Engine 을 넣는다.

```powershell
.\bootstrap.ps1 -SkipScoop -SkipWinget -SkipConfigs -SkipMise
```

이제 재시작해 `.wslconfig`(메모리 4GB / CPU 2코어 상한), systemd, docker 그룹을
한꺼번에 적용한다.

```powershell
wsl --shutdown
wsl
```

배포판 안에서 컨테이너가 도는지 확인한다.

```bash
docker run --rm hello-world
```

`permission denied ... /var/run/docker.sock` 이 나오면 docker 그룹 변경이 아직
반영되지 않은 것이다. `wsl --shutdown` 을 한 번 더 실행한다.

## 7단계. 마무리 점검

- [ ] `git --version` / `mise --version` / `rg --version` 응답
- [ ] `node -v` / `python --version` / `java -version` 모두 응답 (mise shim)
- [ ] `mise doctor` 가 오류 없이 끝남
- [ ] `rustc --version` 응답 (안 되면 `rustup default stable`)
- [ ] MSVC 워크로드 확인 — bootstrap 2-1 단계가 `구성 요소 확인 완료` 로 끝났는지
- [ ] `$HOME\.gitconfig`, `$HOME\.wslconfig`, `$HOME\.config\mise\config.toml` 존재
- [ ] 필요 시 `$HOME\.gitconfig.local` 작성 완료
- [ ] `JAVA_HOME` 이 비어 있는지 확인 (아래 "mise" 절 참고)
- [ ] Antigravity 실행 및 Google 계정 로그인
- [ ] Orca 실행 및 에이전트(Claude Code 등) 연결 확인
- [ ] WSL 안에서 `docker run --rm hello-world` 성공
- [ ] bootstrap 마지막에 출력된 `[WARN]` 항목 처리 (아래 문제 해결 참고)

---

# 문제 해결

### `이 시스템에서 스크립트를 실행할 수 없으므로`

실행 정책에 막힌 경우다. 3단계처럼 `-ExecutionPolicy Bypass` 를 붙여 실행한다.

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

### `[INFO] 실행 정책 변경이 상위 정책에 의해 거부됨`

관리형 PC 에서 그룹 정책으로 실행 정책이 강제된 경우다.
스크립트는 이미 실행 중이므로 **문제가 아니다.** 그대로 진행된다.

### `scoop` / `git` / `node` 명령을 찾을 수 없음

PATH 가 갱신되지 않았다. **PowerShell 을 새로 열고** 다시 시도한다.
그래도 안 되면 아래로 현재 세션에만 임시 반영한다.

```powershell
$env:Path = "$env:USERPROFILE\scoop\shims;$env:Path"
```

### `winget import 가 종료 코드 ...(으)로 끝남`

이미 설치된 앱이 목록에 있으면 winget 은 0 이 아닌 코드를 반환한다.
위쪽 로그에서 실제 실패한 앱만 확인하고, 필요하면 개별 설치한다.

```powershell
winget install --id <패키지ID> -e --accept-package-agreements --accept-source-agreements
```

### Rust 나 `npm install` 이 `link.exe not found` 로 실패

Visual Studio Build Tools 는 설치되었지만 **MSVC 워크로드가 빠진** 상태다.
아래로 실제 구성 요소가 있는지 확인한다.

```powershell
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
  -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
```

아무것도 출력되지 않으면 워크로드가 없는 것이다. bootstrap 의 2-1 단계를 다시 실행하거나,
관리자 PowerShell 에서 직접 추가한다.

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
  --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

Build Tools 가 이미 설치되어 있어 winget 이 `already installed` 로 건너뛴다면 구성 요소만 추가한다.

```powershell
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe" modify `
  --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" `
  --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --wait --norestart
```

### `rustc` 명령을 찾을 수 없음

`Rustlang.Rustup` 은 rustup 만 설치하고 툴체인은 별도로 받아야 할 수 있다.

```powershell
rustup default stable
rustc --version
```

### `winget 을 찾을 수 없음`

Microsoft Store 에서 **앱 설치 관리자(App Installer)** 를 설치한 뒤 다시 실행한다.
설치가 불가능한 환경이면 `-SkipWinget` 으로 Scoop 단계만 진행한다.

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -SkipWinget
```

### 특정 Scoop 앱만 설치 실패

전체는 계속 진행되므로 나중에 개별 설치하면 된다.

```powershell
scoop install <패키지명>
```

### 프로젝트가 다른 Java / Node / Python 버전을 요구함

이것이 mise 를 쓰는 이유다. 그 저장소 루트에서 `mise use` 를 실행하면 된다.

```powershell
cd C:\workspace\어떤-프로젝트
mise use java@temurin-17
mise use node@22
```

저장소 루트에 `mise.toml` 이 만들어지고 버전이 기록된다. 이 파일을 커밋하면
팀원과 CI 가 같은 버전을 쓴다. 커밋하지 않을 개인 오버라이드는 `mise.local.toml`
에 적는다. mise 가 그쪽을 먼저 읽는다.

이후 그 디렉터리 안에서는 `java -version` 이 17 을, 밖에서는 전역 기본값인 21 을
출력한다. 설치되지 않은 버전을 적었으면 `mise install` 로 받는다.

```powershell
mise ls-remote java     # 설치 가능한 버전 목록
mise install            # 현재 디렉터리 설정에 적힌 버전을 전부 받는다
mise ls                 # 지금 무엇이 잡혔고 어느 파일이 지정했는지
```

### `mise use` 를 했는데 Gradle 이 예전 Java 로 빌드함

`JAVA_HOME` 이 남아 있어서다. 아래 "mise" 절을 참고한다.

### `gh auth login` 이 안 되는 환경

브라우저 인증이 막힌 경우 Personal Access Token 방식을 쓴다.
GitHub → Settings → Developer settings → Personal access tokens 에서 `repo` 권한 토큰을 만들고,
`gh auth login` → `Paste an authentication token` 을 선택한다.

### 기존 PC 에서 실행해 `.gitconfig` 가 덮어써짐

bootstrap 은 덮어쓰기 전 `$HOME\.gitconfig.bak` 으로 백업한다.
백업본을 열어 PC 고유 설정을 `~/.gitconfig.local` 로 옮기면 된다.

---

# 참고 자료

## 설치 항목 선택 화면

`-Select` 를 붙이면 설치 전에 체크박스 화면이 뜬다.

**`[x]` 가 설치할 항목이고 `[ ]` 는 건너뛴다.** 각 줄 오른쪽에 처리 결과가 글자로도 표시된다.

```
  설치할 항목을 선택하세요
  [x] 설치함   [ ] 건너뜀   (이미 설치된 항목은 처음부터 해제되어 있습니다)
  ↑↓ 이동   Space 선택/해제   A 전체   N 전체해제   Enter 확인   Esc 취소

  ── 버전 관리자 ──────────────────────────────
  > [x] mise                                    -> 설치
  ── CLI 도구 ────────────────────────────────
    [x] 7zip                                    -> 설치
    [ ] ripgrep                                    건너뜀
  ── winget (관리자 권한 필요) ─────────────────
    [ ] Google.Antigravity                         이미 설치됨
    [x] Google.Chrome                           -> 설치

  (1-20 / 42 행 표시 중)
  전체 34 개 중 21 개를 설치합니다. (Enter 로 진행)
```

이미 설치된 항목이 기본 해제 상태인 것은 재실행 시 불필요한 재설치를 막기 위한 것이다.
최신 버전으로 올리려면 해당 항목을 다시 선택하거나 `-UpgradeExisting` 을 쓴다.

| 키 | 동작 |
|---|---|
| `↑` `↓` | 항목 이동 |
| `PageUp` `PageDown` | 한 화면씩 이동 |
| `Home` `End` | 처음 / 마지막 항목 |
| `Space` | 선택 / 해제 |
| `A` | 전체 선택 |
| `N` | 전체 해제 |
| `Enter` | 확정하고 설치 진행 |
| `Esc` 또는 `Q` | 취소 (아무것도 변경하지 않고 종료) |

화면을 띄우기 전에 현재 설치 상태를 조회한다(`scoop list` + `winget export`, 수 초 소요).
**이미 설치된 항목은 기본 해제 상태**로 표시되므로, 아무것도 건드리지 않고 Enter 만 눌러도
누락된 것만 설치된다.

`scoop-apps.txt` 의 `#>` 로 시작하는 줄이 그룹 구분선이 된다. 그룹을 바꾸려면 그 줄을 수정한다.

선택 결과는 Scoop 은 고른 패키지만 순차 설치하고,
winget 은 고른 패키지만 담은 임시 목록 파일을 만들어 `winget import` 에 넘긴 뒤 삭제한다.

입력이 리다이렉트된 환경(자동화, 파이프)에서는 화면을 띄우지 않고
경고를 남긴 뒤 미설치 항목 전체를 선택한다. 무인 실행이 멈추지 않도록 하기 위한 동작이다.

## 리포지토리 구조

```
dotfiles/
├── README.md                    # OS 선택 안내
├── mac/                         # macOS 용 (별도 문서)
└── windows/
    ├── bootstrap.ps1            # 메인 진입점
    ├── install-manual-apps.ps1  # 패키지 매니저로 설치되지 않는 앱 안내
    ├── lib/
    │   └── Select-Packages.ps1  # -Select 선택 화면 (외부 모듈 의존 없음)
    ├── scripts/
    │   └── install-docker-wsl.sh # WSL 안에서 실행되는 Docker Engine 설치 스크립트
    ├── apps/
    │   ├── scoop-apps.txt       # Scoop 설치 목록 (무권한)
    │   ├── winget-apps.json     # winget import 용 목록 (관리자 권한)
    │   └── winget-overrides.json # import 로 안 되는 개별 설치 목록
    ├── configs/
    │   ├── .gitconfig           # -> $HOME\.gitconfig
    │   ├── .wslconfig           # -> $HOME\.wslconfig
    │   └── mise.toml            # -> $HOME\.config\mise\config.toml
    └── README.md
```

`bootstrap.ps1` 은 자기 위치(`$PSScriptRoot`)를 기준으로 `apps\` `configs\` `lib\`
`scripts\` 를 찾으므로, 디렉터리째 옮겨도 경로 수정이 필요하지 않다.

## bootstrap.ps1 동작

| 단계 | 내용 |
|---|---|
| 0 | 실행 정책을 `RemoteSigned`(CurrentUser)로 설정하고 하위 `.ps1` 을 `Unblock-File` 처리 (`-DryRun` 이면 실행 정책은 건드리지 않는다) |
| 1 | Scoop 미설치 시 설치 → 필요한 버킷 추가 → `apps/scoop-apps.txt` 순차 설치 |
| 2 | `winget import`로 `apps/winget-apps.json` 일괄 설치 |
| 2-1 | `apps/winget-overrides.json` 의 패키지를 `--override` 를 붙여 개별 설치 |
| 3 | `configs/` 의 설정 파일을 배치 (기존 파일은 `.bak` 으로 백업) |
| 3-1 | mise shim 디렉터리를 사용자 PATH 에, `mise activate pwsh` 를 PowerShell 프로필에 등록한 뒤 `mise install` 로 기본 런타임 설치 |
| 4 | WSL 배포판 안에서 `scripts/install-docker-wsl.sh` 실행 (Docker Engine) |
| 5 | `install-manual-apps.ps1` 실행 |
| 6 | 누적된 경고 요약 출력 |

개별 앱 설치 실패는 경고로 기록하고 다음 앱으로 계속 진행한다. 전체가 중단되지 않는다.

### 옵션

| 옵션 | 설명 |
|---|---|
| `-Select` | 설치할 항목을 체크박스 화면에서 직접 선택 |
| `-DryRun` | 실제 변경 없이 수행할 작업만 출력 |
| `-SkipScoop` | Scoop 단계 생략 |
| `-SkipWinget` | winget 단계 생략 |
| `-SkipConfigs` | 설정 파일 복사 생략 |
| `-SkipMise` | 3-1 단계 생략 (PATH·프로필 등록과 런타임 설치를 함께 건너뛴다) |
| `-SkipDocker` | WSL Docker Engine 설치(4) 생략 |
| `-WslDistro <이름>` | Docker Engine 을 넣을 WSL 배포판 지정 (기본값: WSL 기본 배포판) |
| `-UpgradeExisting` | winget 단계에서 이미 설치된 앱도 최신 버전으로 갱신 |
| `-HomePath <경로>` | 설정 파일 복사 대상 지정 (기본값 `$HOME`). 기본값이 아니면 3-1 단계의 PATH·프로필 등록도 건너뛴다 |

`-HomePath` 는 빈 디렉터리를 지정해 실제 홈을 건드리지 않고 배치 결과를 확인할 때 쓴다.

```powershell
.\bootstrap.ps1 -SkipScoop -SkipWinget -HomePath C:\temp\newpc
```

## 앱 목록 분담 원칙

두 목록은 **중복되지 않는다.**

- `scoop-apps.txt` — 관리자 권한 없이도 확보해야 하는 CLI 도구와 버전 관리자
  (버전 관리자 `mise`, CLI `7zip` `sudo` `ripgrep` `fzf`)
  `git` 과 `gh` 는 2단계 전제 조건이라 여기에 없다. winget 쪽이 항상 우선 사용되므로
  Scoop 으로 또 설치하면 쓰이지 않는 사본만 남는다.
  언어 런타임도 여기에 없다. mise 가 받는다 (아래 "mise" 절).
- `winget-apps.json` — GUI 앱, 시스템 통합 앱, 관리자 권한이 필요한 항목
- `winget-overrides.json` — `winget import` 로는 온전히 설치되지 않아
  개별 설치가 필요한 항목 (아래 참고)

### winget-overrides.json 이 따로 있는 이유

`winget import` 는 **패키지별 `--override` 를 지원하지 않는다.** 설치 관리자에 인자를
넘겨야 구성 요소가 결정되는 패키지를 `winget-apps.json` 에 넣으면, 설치 관리자만 깔린 채로
winget 기준 '설치됨' 상태가 된다. 겉보기에는 성공이지만 실제 컴파일러는 없다.

Visual Studio Build Tools 가 이 경우에 해당한다. 워크로드를 지정하지 않으면 MSVC 컴파일러와
링커가 빠지고, 나중에 Rust 빌드나 `npm install`(네이티브 모듈)이 `link.exe not found` 로 실패한다.
그래서 이 패키지는 import 목록에서 제외하고 `winget-overrides.json` 에 두어
`--add Microsoft.VisualStudio.Workload.VCTools` 를 명시해 설치한다.

설치 완료 판정도 winget 이 아니라 `vswhere.exe` 로 실제 구성 요소 존재 여부를 확인한다.
제품은 이미 있고 구성 요소만 빠진 상태라면 `winget install` 이 `already installed` 로 건너뛰므로,
이 경우에는 `vs_installer.exe modify` 로 구성 요소만 추가한다.

같은 성격의 패키지가 생기면 `Packages` 배열에 항목을 추가한다.

| 필드 | 설명 |
|---|---|
| `PackageIdentifier` | winget 패키지 ID |
| `Override` | 설치 관리자에 그대로 전달할 인자 문자열 |
| `RequiresComponent` | (선택) 설치 완료 판정에 쓸 Visual Studio 구성 요소 ID |
| `Reason` | 왜 필요한지. 선택 화면과 로그에 표시된다 |

Scoop 단계는 어떤 PC에서도 실행되므로, 툴체인은 winget 목록에서 제외했다.
따라서 관리자 권한이 없는 PC에서도 개발은 바로 시작할 수 있다.

Chocolatey 는 제외했다. 대부분 관리자 권한을 요구해 권한 제한 환경에서 실패한다.

언어별 버전 관리자(`nvm`, `pyenv`, `jabba`)도 넣지 않았다. 서로 shim 이름이 겹쳐
나중에 설치된 쪽이 PATH 우선권을 가지고, 설정 파일도 도구마다 따로 놀기 때문이다.
`mise` 하나가 그 자리를 대신한다.

기본 버킷이 아닌 곳의 패키지는 `bucket/package` 형식으로 적으면 bootstrap 이
버킷을 자동으로 추가한다. 현재 목록에는 그런 항목이 없다.

## mise

언어 런타임은 Scoop 도 winget 도 아닌 [mise](https://mise.jdx.dev/) 가 관리한다.
프로젝트마다 필요한 버전이 달라서 패키지 매니저로 고정할 수 없기 때문이다.

### 어떻게 동작하는가

mise 는 **shim** 을 설치한다. shim 은 진짜 실행 파일 대신 PATH 에 놓이는 얇은 중계
실행 파일이다. `java` 를 치면 다음 순서로 일이 벌어진다.

1. PATH 앞쪽의 `%LOCALAPPDATA%\mise\shims\java.exe` 가 잡힌다.
2. shim 이 현재 작업 디렉터리에서 위로 올라가며 `mise.toml` 을 찾는다.
3. 찾으면 거기 적힌 버전, 없으면 전역 `%USERPROFILE%\.config\mise\config.toml` 의 기본값을 쓴다.
4. 해당 버전의 실제 `java.exe` 로 실행을 넘긴다.

그래서 디렉터리를 옮기는 것만으로 `java -version` 결과가 바뀐다.
bootstrap 3-1 단계가 이 shim 디렉터리를 사용자 PATH 앞쪽에 등록한다.

### 프로젝트별 버전 고정

```powershell
cd C:\workspace\어떤-프로젝트
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
| `mise doctor` | PATH·shim 구성 진단 |
| `mise x -- <명령>` | 환경 변수까지 갖춘 상태로 명령을 한 번 실행한다 |

### 셸 훅과 `JAVA_HOME`

shim 은 명령을 올바른 버전으로 넘겨줄 뿐 **환경 변수는 건드리지 않는다.**
`JAVA_HOME` 이 그래서 문제가 된다. Gradle 과 Maven 은 `JAVA_HOME` 이 있으면 그 값을
쓰고 없을 때만 PATH 의 `java` 를 보므로, shim 만으로는 디렉터리를 옮겨도 빌드에
쓰이는 JDK 가 그대로다.

이를 위해 bootstrap 3-1 단계가 PowerShell 프로필
(`$PROFILE.CurrentUserAllHosts`)에 아래 줄을 넣는다.

```powershell
if (Get-Command mise -ErrorAction SilentlyContinue) { (& mise activate pwsh) | Out-String | Invoke-Expression }
```

`mise activate pwsh` 는 `prompt` 함수를 감싸는 훅을 건다. 프롬프트가 그려질 때마다
`mise hook-env` 가 돌면서 현재 디렉터리 기준으로 PATH 와 환경 변수를 다시 계산하므로,
`JAVA_HOME` 이 프로젝트를 따라 바뀐다. 확인은 이렇게 한다.

```powershell
cd C:\workspace\java17-프로젝트
$env:JAVA_HOME          # 17 쪽 경로가 나와야 한다
```

**훅은 PowerShell 안에서만 동작한다.** 아래는 훅을 받지 못하므로 shim 이 유일한
경로가 되고, 거기서는 `JAVA_HOME` 이 갱신되지 않는다.

- `cmd.exe`
- IDE 가 직접 띄운 빌드 프로세스 (IntelliJ·Android Studio 는 프로젝트 SDK 를 IDE 안에서 지정한다)
- 로그인 셸을 거치지 않고 실행되는 서비스·스케줄 작업

따라서 **`JAVA_HOME` 을 시스템에 고정해 두지 않는 것**이 이 구성의 전제다.
값을 비워 두면 훅이 없는 환경에서도 Gradle 과 Maven 이 PATH 의 shim 으로 내려와
프로젝트 버전을 따라간다. bootstrap 3-1 단계는 `JAVA_HOME` 이 사용자·시스템 범위에
남아 있으면 경고한다.

PowerShell 7 을 따로 쓴다면 프로필 경로가 다르다는 점에 유의한다. 5.1 은
`WindowsPowerShell\`, 7 은 `PowerShell\` 아래이므로, bootstrap 을 돌린 판이 아닌
쪽에는 위 줄을 직접 넣어야 한다. `$PROFILE.CurrentUserAllHosts` 로 경로를 확인한다.

예전 JDK 설치 관리자가 남긴 값을 지우려면:

```powershell
# 현재 값 확인
[Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
[Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')

# 사용자 범위 삭제
[Environment]::SetEnvironmentVariable('JAVA_HOME', $null, 'User')

# 시스템 범위 삭제 (관리자 PowerShell 필요)
[Environment]::SetEnvironmentVariable('JAVA_HOME', $null, 'Machine')
```

`JAVA_HOME` 이 꼭 필요한 명령은 `mise x` 로 감싸면 그 실행에 한해 올바른 값이 들어간다.

```powershell
mise x -- ./gradlew build
```

### 이미 다른 방법으로 깐 런타임이 있다면

winget 이나 설치 관리자로 깐 JDK·Node·Python 이 남아 있으면 PATH 앞자리를 두고
shim 과 다툰다. mise 로 옮기기로 했다면 기존 설치를 제거하는 편이 낫다.

```powershell
winget uninstall Microsoft.OpenJDK.17
winget uninstall Microsoft.OpenJDK.21
winget uninstall OpenJS.NodeJS
winget uninstall Python.Python.3.13
```

제거 후 새 터미널에서 `mise doctor` 와 `where.exe java` 로 shim 이 앞에 오는지 확인한다.

## 목록 갱신

현재 PC 의 설치 상태를 winget 목록에 반영하려면:

```powershell
winget export -o apps\winget-apps.json
```

내보낸 뒤 아래 항목은 수동으로 제거한다.

- `Microsoft.Edge` — Windows 기본 내장이며 winget 소스 매칭에 실패한다
- MSIX 프레임워크 의존성 — `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`,
  `Microsoft.WindowsAppRuntime.*`, `Microsoft.DotNet.Native.Runtime`, `Microsoft.AppInstaller`
  (다른 앱 설치 시 자동으로 따라온다)
- mise 가 담당하는 런타임 — `OpenJS.NodeJS`, `Python.Python.*`,
  `Python.Launcher`, `Microsoft.OpenJDK.*`, `Oracle.Java*`
  (`Git.Git` 과 `GitHub.cli` 는 제거하지 않는다. 2단계 전제 조건이므로 winget 목록에 남긴다)
- `Docker.DockerDesktop` — 쓰지 않는다. 컨테이너는 WSL 의 Docker Engine 이 담당한다.
- `Rustlang.Rust.MSVC` — 단일 툴체인 고정이라 목록에는 `Rustlang.Rustup` 을 쓴다.
- `winget export` 실행 중 `not available from any source` 경고가 뜬 Windows 내장 구성요소 전반
- `Microsoft.VisualStudio.2022.BuildTools` — `winget-overrides.json` 이 담당한다.
  import 목록에 남겨두면 구성 요소 없이 설치되므로 반드시 제거한다.

`Oracle.MySQL` 은 목록에 있지만 주의가 필요하다. MSI 무인 설치는 파일만 풀고
인스턴스 구성(root 비밀번호, 포트, 서비스 등록)까지 하지는 않는다.
설치 후 시작 메뉴의 **MySQL Installer** 를 한 번 실행해 인스턴스를 구성해야
접속이 된다. 이 과정이 번거로우면 컨테이너로 띄우는 편이 빠르다.

```bash
docker run -d --name mysql -p 3306:3306 -e MYSQL_ROOT_PASSWORD=... mysql:8
```

Scoop 목록을 갱신하려면 `apps/scoop-apps.txt` 에 한 줄씩 추가한다.
기본 버킷(main) 외의 패키지는 `버킷명/패키지명` 형식으로 적는다.

## 확정 스택

| 항목 | 값 | 관리 주체 |
|---|---|---|
| Java | 기본 Temurin 21, 프로젝트별 전환 | mise |
| Node.js | 기본 최신 LTS, 프로젝트별 전환 | mise |
| Python | 기본 3.13, 프로젝트별 전환 | mise |
| Bun | 최신 | mise |
| Rust | stable (`Rustlang.Rustup`) | rustup |
| C/C++ 빌드 | VS 2022 Build Tools + VCTools 워크로드 | winget-overrides |
| 컨테이너 | WSL2 배포판 안의 Docker Engine (`docker-ce`) | `scripts/install-docker-wsl.sh` |
| DB 서버 | MySQL 8 (`Oracle.MySQL`) 또는 컨테이너 | winget |
| DB 클라이언트 | DBeaver (`DBeaver.DBeaver.Community`), MySQL Workbench | winget |
| Git user.name | serena | — |
| Git user.email | 239265396+hayohio-bit@users.noreply.github.com | — |
| IDE | Antigravity, Cursor, Zed, Android Studio | winget |
| 에이전트 오케스트레이션 | Orca (`StablyAI.Orca`) | winget |

런타임 버전이 표에 "기본"으로 적힌 이유는 위 [mise](#mise) 절을 참고한다.

## WSL 및 Docker 설정

`configs/.wslconfig` 는 저사양 PC 에서 Docker/WSL 이 호스트 자원을 과점하는 문제를 완화한다.

```ini
[wsl2]
memory=4GB
processors=2
swap=2GB
```

복사 후 `wsl --shutdown` 으로 적용한다.

값은 **보유한 PC 중 가장 사양이 낮은 것에 맞춰** 두었다. `.wslconfig` 는 `.gitconfig` 의
`[include]` 같은 분기 수단이 없어 PC 별로 나눌 수 없으므로, 여유가 있는 PC 에서는 복사한 뒤
`$HOME\.wslconfig` 를 직접 올려 쓴다. 조정 기준은 파일 머리말의 표를 참고한다.

`processors` 가 CPU 급등에 대한 직접적인 제동 장치다. 물리 코어 수보다 반드시 낮게 잡는다.

### 남는 부하

`.wslconfig` 는 **WSL VM(vmmem)에만** 적용된다. 그래도 부하가 남으면
바인드 마운트 I/O 를 먼저 본다. 프로젝트를 Windows 경로(`C:\Users\...`) 대신
WSL 내부 경로(`\\wsl$\Ubuntu\home\...`)에 두면 9p 파일시스템을 경유하지 않는다.
파일 감시(watch)가 걸린 프로젝트에서 특히 차이가 크다.

## Docker

Docker Desktop 을 쓰지 않는다. WSL2 배포판 안에 Docker Engine(`docker-ce`)을
직접 설치하며, bootstrap 4단계가 `scripts/install-docker-wsl.sh` 를 WSL 안에서
실행해 이를 처리한다.

### 왜 Desktop 을 쓰지 않는가

Windows 에는 리눅스 커널이 없어서 컨테이너를 그대로 돌릴 수 없다. 어느 방식이든
리눅스 VM 안에서 도커 데몬을 띄우고 CLI 가 그 데몬에 붙는 구조다.
Docker Desktop 은 그 VM 과 GUI 를 묶어 파는 상용 제품으로,
일정 규모 이상의 조직에서는 유상 구독이 필요하다.

이미 WSL2 배포판이 있으므로 VM 은 이미 하나 있다. 그 안에 데몬만 넣으면 된다.
Desktop 은 프로젝트용 배포판과 **별개의 WSL VM 을 하나 더** 띄우고, Windows 측
프로세스(`com.docker.backend`, Electron GUI, 자동 업데이트)도 함께 돈다.
이것들이 사라지므로 자원 사용도 줄어든다. 명령과 이미지는 완전히 동일하다.

Podman 도 검토했으나 Windows 에서 `podman machine` 역시 WSL2 VM 을 띄우므로
데몬이 없다는 점 외에는 구조가 같고, `docker-compose` 호환에서 걸리는 지점이 있다.

### 설치 스크립트가 하는 일

`scripts/install-docker-wsl.sh` 는 WSL 안에서 실행되며 네 가지를 한다.

1. Docker 공식 apt 저장소를 등록한다. Ubuntu 기본 저장소의 `docker.io` 는 버전이 뒤처진다.
2. `docker-ce`, `docker-ce-cli`, `containerd.io`, buildx·compose 플러그인을 설치한다.
3. 현재 사용자를 `docker` 그룹에 넣는다. 데몬이 만드는 `/var/run/docker.sock` 이
   `root:docker` 소유라, 이 그룹에 없으면 `docker` 명령마다 `sudo` 가 필요하다.
4. `/etc/wsl.conf` 에 `[boot] systemd=true` 를 넣는다.

4번이 핵심이다. WSL2 는 기본 init 이 systemd 가 아니라서, 켜 주지 않으면
배포판을 열 때마다 `sudo service docker start` 를 손으로 쳐야 한다.
systemd 를 켜면 설치 과정에서 등록된 `docker.service` 가 배포판 시작 시 자동으로 뜬다.

3번과 4번 모두 **WSL 재시작 후에** 적용된다.

```powershell
wsl --shutdown
wsl
```

### 쓰는 방법

WSL 배포판 안에서 평소처럼 쓴다.

```bash
docker run --rm hello-world
docker compose up -d          # 하이픈 없는 compose. 플러그인이 제공한다
```

### PowerShell 에서 바로 쓰려면

Windows 쪽 터미널에서 `docker` 를 치려면 CLI 를 따로 깔고 WSL 의 데몬을 가리키게 한다.
필수는 아니다. WSL 안에서만 쓸 거라면 이 절은 건너뛴다.

```powershell
scoop install docker           # CLI 만 설치된다. 데몬은 WSL 쪽 것을 쓴다
```

WSL 안에서 데몬이 TCP 를 열고 있지 않으면 Windows CLI 가 붙을 소켓이 없다.
가장 간단한 방법은 그냥 `wsl` 로 들어가서 작업하는 것이고, 굳이 Windows 쪽에서
쓰겠다면 WSL 의 `/etc/docker/daemon.json` 에 TCP 리스너를 여는 설정이 추가로 필요하다.
보안상 `localhost` 로 제한해야 하므로, 필요해질 때 검토한다.

### Docker Desktop 이 이미 깔려 있다면

두 개의 `docker` CLI 가 PATH 를 두고 다툰다. bootstrap 4단계가 이를 감지해 경고한다.

```powershell
winget uninstall Docker.DockerDesktop
```

제거 후 `wsl -l -v` 에서 `docker-desktop` 배포판이 사라졌는지 확인한다.

## 프로그램이 이미 설치된 PC 에서 실행할 때

깨끗한 새 PC 가 아니라 이미 일부 프로그램을 설치해둔 PC(테스트용 등)에서 돌릴 때
알고 있어야 할 항목은 아래 세 가지다.

### winget 으로 설치된 앱 — 안전

bootstrap 은 `winget import` 에 `--no-upgrade` 를 붙여 실행한다.
이미 설치된 앱은 `Package is already installed` 로 건너뛰고 다운로드조차 하지 않는다.
Antigravity, Obsidian, Chrome 등이 이미 있어도 그대로 유지된다.

이 옵션이 없으면 winget 은 **같은 버전이어도 전부 다시 내려받아 재설치한다.**
목록의 앱을 최신으로 올리고 싶을 때만 `-UpgradeExisting` 을 명시한다.

```powershell
.\bootstrap.ps1 -UpgradeExisting
```

### 기존 node / python / java — PATH 우선순위

어느 쪽이 쓰이는지는 **PATH 의 종류**로 갈린다.

- winget 이나 일반 설치 관리자로 깐 도구 → **시스템(Machine) PATH**
- Scoop 과 mise shim → **사용자(User) PATH**

Windows 는 프로세스 환경 변수를 만들 때 시스템 PATH 를 먼저 붙이고 사용자 PATH 를
이어붙인다. 따라서 양쪽에 같은 도구가 있으면 **기존 설치본이 계속 우선 사용되고
mise shim 은 쓰이지 않은 채 남는다.** git 과 gh 를 Scoop 목록에서 제외한 이유가 이것이다.

즉 winget 으로 깐 JDK·Node·Python 이 남아 있으면 `mise use` 를 해도 버전이 바뀌지
않는다. 어느 쪽이 쓰이는지 먼저 확인한다.

```powershell
Get-Command git, node, python, java | Select-Object Name, Source
```

`Source` 가 `...\mise\shims\...` 가 아니면 기존 설치본이 이기고 있는 것이다.
[mise](#mise) 절의 "이미 다른 방법으로 깐 런타임이 있다면" 을 따라 제거한다.

기존 도구를 그대로 쓰고 싶으면 Scoop 과 mise 단계를 건너뛴다.

```powershell
.\bootstrap.ps1 -SkipScoop -SkipMise
```

### `$HOME\.gitconfig` — 덮어써짐, 확인 필요

**덮어쓰기가 일어나는 유일한 항목이다.** 내용이 이미 같으면 건너뛰지만,
다르면 `.gitconfig.bak` 으로 백업한 뒤 이 리포지토리의 설정으로 교체한다.

이미 git 을 설정해둔 PC 라면 실행 전에 현재 설정을 확인해둔다.

```powershell
Get-Content $HOME\.gitconfig
```

`user.name` / `user.email` / `init.defaultBranch` / `core.autocrlf` 정도만 있다면
이 리포지토리의 `configs/.gitconfig` 가 모두 포함하므로 잃을 것이 없다.
사내 credential, `core.hooksPath`, `core.excludesFile` 등이 있다면
실행 후 `.gitconfig.bak` 에서 `~/.gitconfig.local` 로 옮긴다.

설정 파일만 건드리지 않으려면 `-SkipConfigs` 를 쓴다.

```powershell
.\bootstrap.ps1 -SkipConfigs
```

### 가장 안전한 시험 방법

무엇이 바뀔지 먼저 확인한다.

```powershell
.\bootstrap.ps1 -DryRun
```
