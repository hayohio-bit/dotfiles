# dotfiles

새 PC 개발환경 자동 구축 스크립트.

권한 수준이 확정되지 않은 상황(관리형 PC / 개인 PC)에 대응하기 위해
**Scoop(무권한) + winget(관리자 권한)** 이중 구조로 구성되어 있다.
Scoop 단계는 어떤 PC에서도 실행되므로, winget 단계가 통째로 실패해도 개발은 시작할 수 있다.

---

# 새 PC 설치 절차

아래 1~7단계를 순서대로 따라간다. 총 소요 시간은 30분~1시간이다.
(Visual Studio Build Tools, Docker Desktop, MySQL 이 대부분의 시간을 차지한다.)

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
또한 새 PC 에는 git 이 없는데 git 은 이 스크립트가 설치하는 대상이므로,
리포지토리를 받는 단계에서만 별도 수단이 필요하다.

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
cd dotfiles
```

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

마지막 4단계에서 Orca / Antigravity / Docker Desktop 중 winget 으로 설치되지 않은 것이 있으면
다운로드 페이지가 브라우저로 열린다. 열린 페이지에서 설치 파일을 받아 수동 설치한다.

## 4단계. 결과 확인

**PowerShell 을 새로 연다.** PATH 가 갱신되지 않으면 아래 명령이 전부 실패한다.

아래 6개가 모두 버전 문자열을 출력하면 정상이다.
(괄호는 2026-07 기준 Scoop 최신 버전으로, 설치 시점에 따라 달라진다.)

```powershell
git --version          # git version 2.55.x
node -v                # v24.x.x   (LTS)
python --version       # Python 3.14.x
java -version          # openjdk version "21.0.x"
gh --version
rg --version           # ripgrep
```

`명령을 찾을 수 없습니다` 가 나오면 PowerShell 을 새로 열지 않은 것이다.

설정 파일이 배치되었는지 확인한다.

```powershell
Get-Content $HOME\.gitconfig
Get-Content $HOME\.wslconfig
```

`java -version` 이 동작하면 `JAVA_HOME` 도 함께 설정된 상태다. 확인하려면:

```powershell
$env:JAVA_HOME
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

배포판이 하나도 없으면 설치한다. (Docker Desktop 만 쓸 거라면 생략 가능하다.)

```powershell
wsl --install -d Ubuntu
```

이제 `.wslconfig`(메모리 8GB / CPU 4코어 상한)를 적용한다.

```powershell
wsl --shutdown
```

이후 WSL 또는 Docker Desktop 을 다시 실행하면 제한값이 반영된다.
Docker Desktop 은 최초 실행 시 로그인과 추가 구성 요소 설치를 요구할 수 있다.

## 7단계. 마무리 점검

- [ ] `git --version` / `node -v` / `python --version` / `java -version` 모두 응답
- [ ] `rustc --version` 응답 (안 되면 `rustup default stable`)
- [ ] MSVC 워크로드 확인 — bootstrap 2-1 단계가 `구성 요소 확인 완료` 로 끝났는지
- [ ] `$HOME\.gitconfig`, `$HOME\.wslconfig` 존재
- [ ] 필요 시 `$HOME\.gitconfig.local` 작성 완료
- [ ] Antigravity 실행 및 Google 계정 로그인
- [ ] Orca 실행 및 에이전트(Claude Code 등) 연결 확인
- [ ] Docker Desktop 실행 후 `docker run hello-world` 성공
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
scoop install java/temurin21-jdk    # 버킷이 필요한 경우
```

### `node -v` 결과가 예상과 다름

`nvm` 이 `nodejs-lts` 와 PATH 가 겹쳐 나중에 설치된 쪽이 우선권을 갖는다.
평소에는 신경 쓸 필요가 없고, 버전을 고정하려면 아래로 전환한다.

```powershell
nvm install lts
nvm use lts
```

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

```
  설치할 항목을 선택하세요
  ↑↓ 이동   Space 선택/해제   A 전체   N 전체해제   Enter 확인   Esc 취소

  ── 런타임 ──────────────────────────────────
  > [x] git
    [x] nodejs-lts
    [x] python
    [x] temurin21-jdk
  ── 버전 관리자 ──────────────────────────────
    [ ] nvm
    [ ] pyenv
  ── winget (관리자 권한 필요) ─────────────────
    [ ] Google.Antigravity           이미 설치됨
    [x] Google.Chrome

  (1-20 / 42 행 표시 중)
  선택됨 12 / 38
```

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
├── bootstrap.ps1            # 메인 진입점
├── install-manual-apps.ps1  # 패키지 매니저로 설치되지 않는 앱 안내
├── lib/
│   └── Select-Packages.ps1  # -Select 선택 화면 (외부 모듈 의존 없음)
├── apps/
│   ├── scoop-apps.txt       # Scoop 설치 목록 (무권한)
│   ├── winget-apps.json     # winget import 용 목록 (관리자 권한)
│   └── winget-overrides.json # import 로 안 되는 개별 설치 목록
├── configs/
│   ├── .gitconfig           # -> $HOME\.gitconfig
│   └── .wslconfig           # -> $HOME\.wslconfig
└── README.md
```

## bootstrap.ps1 동작

| 단계 | 내용 |
|---|---|
| 0 | 실행 정책을 `RemoteSigned`(CurrentUser)로 설정하고 하위 `.ps1` 을 `Unblock-File` 처리 |
| 1 | Scoop 미설치 시 설치 → 필요한 버킷 추가 → `apps/scoop-apps.txt` 순차 설치 |
| 2 | `winget import`로 `apps/winget-apps.json` 일괄 설치 |
| 2-1 | `apps/winget-overrides.json` 의 패키지를 `--override` 를 붙여 개별 설치 |
| 3 | `configs/` 의 설정 파일을 `$HOME` 에 복사 (기존 파일은 `.bak` 으로 백업) |
| 4 | `install-manual-apps.ps1` 실행 |
| 5 | 누적된 경고 요약 출력 |

개별 앱 설치 실패는 경고로 기록하고 다음 앱으로 계속 진행한다. 전체가 중단되지 않는다.

### 옵션

| 옵션 | 설명 |
|---|---|
| `-Select` | 설치할 항목을 체크박스 화면에서 직접 선택 |
| `-DryRun` | 실제 변경 없이 수행할 작업만 출력 |
| `-SkipScoop` | Scoop 단계 생략 |
| `-SkipWinget` | winget 단계 생략 |
| `-SkipConfigs` | 설정 파일 복사 생략 |
| `-UpgradeExisting` | winget 단계에서 이미 설치된 앱도 최신 버전으로 갱신 |
| `-HomePath <경로>` | 설정 파일 복사 대상 지정 (기본값 `$HOME`) |

`-HomePath` 는 빈 디렉터리를 지정해 실제 홈을 건드리지 않고 배치 결과를 확인할 때 쓴다.

```powershell
.\bootstrap.ps1 -SkipScoop -SkipWinget -HomePath C:\temp\newpc
```

## 앱 목록 분담 원칙

두 목록은 **중복되지 않는다.**

- `scoop-apps.txt` — 관리자 권한 없이도 확보해야 하는 CLI 도구와 개발 런타임
  (런타임 `git` `nodejs-lts` `python` `java/temurin21-jdk`,
  버전 관리자 `nvm` `pyenv`, CLI `gh` `7zip` `sudo` `ripgrep` `fzf`)
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

`nvm` / `pyenv` 는 `nodejs-lts` / `python` 과 PATH 가 겹쳐 나중에 설치된 쪽이 우선권을 갖는다.
평소에는 최신 LTS 단일 버전을 쓰고, 프로젝트별 버전 요구가 생기면 아래로 전환한다.

```powershell
nvm install lts       ; nvm use lts
pyenv install 3.13.0  ; pyenv global 3.13.0
```

`java` 버킷처럼 기본 버킷이 아닌 곳의 패키지는 `java/temurin21-jdk` 형식으로 적으면
bootstrap 이 버킷을 자동으로 추가한다.
`temurin21-jdk` 는 설치 시 `JAVA_HOME` 을 함께 설정한다.

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
- Scoop 이 담당하는 툴체인 — `Git.Git`, `GitHub.cli`, `OpenJS.NodeJS`,
  `Python.Python.*`, `Python.Launcher`, `Microsoft.OpenJDK.*`
- `winget export` 실행 중 `not available from any source` 경고가 뜬 Windows 내장 구성요소 전반
- `Microsoft.VisualStudio.2022.BuildTools` — `winget-overrides.json` 이 담당한다.
  import 목록에 남겨두면 구성 요소 없이 설치되므로 반드시 제거한다.

Scoop 목록을 갱신하려면 `apps/scoop-apps.txt` 에 한 줄씩 추가한다.
기본 버킷(main) 외의 패키지는 `버킷명/패키지명` 형식으로 적는다.

## 확정 스택

| 항목 | 값 |
|---|---|
| Java | 21 (`java/temurin21-jdk`) |
| Node.js | 최신 LTS (`nodejs-lts`) |
| Python | 최신 안정판 (`python`) |
| Rust | rustup 으로 관리 (`Rustlang.Rustup`) |
| C/C++ 빌드 | VS 2022 Build Tools + VCTools 워크로드 |
| Git user.name | serena |
| Git user.email | 239265396+hayohio-bit@users.noreply.github.com |
| IDE | Antigravity (`Google.Antigravity`, `Google.AntigravityIDE`) |
| 에이전트 오케스트레이션 | Orca (`StablyAI.Orca`) |

## WSL 및 Docker 설정

`configs/.wslconfig` 는 저사양 PC 에서 Docker/WSL 이 호스트 자원을 과점하는 문제를 완화한다.

```ini
[wsl2]
memory=8GB
processors=4
swap=0
```

복사 후 `wsl --shutdown` 으로 적용한다.
메모리가 16GB 미만인 PC 는 `memory` 값을 4GB 로 낮추는 것을 검토한다.

Docker 속도 저하의 나머지 원인과 대응은 아래와 같다.

1. 바인드 마운트 I/O — 프로젝트를 Windows 경로(`C:\Users\...`) 대신
   WSL 내부 경로(`\\wsl$\Ubuntu\home\...`)에 두면 파일시스템 호환성 문제를 회피할 수 있다.
2. Vmmem 메모리 무제한 점유 — 위 `.wslconfig` 로 상한을 건다.
3. 그래도 해소되지 않으면 Podman 전환(`scoop install podman`, `podman machine init/start`)
   또는 컨테이너를 원격/클라우드 서버에서 실행하는 방식을 검토한다.
   Docker Desktop 은 상업적 사용 시 유료 라이선스가 필요하다는 점도 함께 고려한다.

## 프로그램이 이미 설치된 PC 에서 실행할 때

깨끗한 새 PC 가 아니라 이미 일부 프로그램을 설치해둔 PC(테스트용 등)에서 돌릴 때
알고 있어야 할 항목은 아래 세 가지다.

### winget 으로 설치된 앱 — 안전

bootstrap 은 `winget import` 에 `--no-upgrade` 를 붙여 실행한다.
이미 설치된 앱은 `Package is already installed` 로 건너뛰고 다운로드조차 하지 않는다.
Antigravity, Obsidian, Docker Desktop 등이 이미 있어도 그대로 유지된다.

이 옵션이 없으면 winget 은 **같은 버전이어도 전부 다시 내려받아 재설치한다.**
목록의 앱을 최신으로 올리고 싶을 때만 `-UpgradeExisting` 을 명시한다.

```powershell
.\bootstrap.ps1 -UpgradeExisting
```

### 기존 git / node / python — PATH 우선순위가 바뀜

Scoop 은 이미 설치된 도구를 인식하지 못하고 자기 버전을 별도로 설치한다.
`~\scoop\shims` 가 PATH 앞쪽에 놓이므로, 설치 후에는 **Scoop 쪽이 우선 사용된다.**
기존 설치본이 사라지는 것은 아니고 가려질 뿐이다.

어느 쪽이 쓰이는지는 아래로 확인한다.

```powershell
Get-Command git, node, python | Select-Object Name, Source
```

기존 도구를 그대로 쓰고 싶으면 Scoop 단계를 건너뛴다.

```powershell
.\bootstrap.ps1 -SkipScoop
```

### `$HOME\.gitconfig` — 덮어써짐, 확인 필요

**세 가지 중 실제로 주의할 항목이다.** 내용이 이미 같으면 건너뛰지만,
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
