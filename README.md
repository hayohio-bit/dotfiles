# dotfiles

새 PC 개발환경 자동 구축 스크립트.

권한 수준이 확정되지 않은 상황(관리형 PC / 개인 PC)에 대응하기 위해
**Scoop(무권한) + winget(관리자 권한)** 이중 구조로 구성되어 있다.

## 빠른 시작

```powershell
git clone https://github.com/hayohio-bit/dotfiles.git
cd dotfiles
.\bootstrap.ps1
```

`winget` 단계는 관리자 권한 PowerShell 에서 실행하는 것을 권장한다.

실제 설치 전에 실행 계획만 확인하려면:

```powershell
.\bootstrap.ps1 -DryRun
```

## 구조

```
dotfiles/
├── bootstrap.ps1            # 메인 진입점
├── install-manual-apps.ps1  # 패키지 매니저로 설치되지 않는 앱 안내
├── apps/
│   ├── scoop-apps.txt       # Scoop 설치 목록 (무권한)
│   └── winget-apps.json     # winget import 용 목록 (관리자 권한)
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
| 3 | `configs/` 의 설정 파일을 `$HOME` 에 복사 (기존 파일은 `.bak` 으로 백업) |
| 4 | `install-manual-apps.ps1` 실행 |
| 5 | 누적된 경고 요약 출력 |

개별 앱 설치 실패는 경고로 기록하고 다음 앱으로 계속 진행한다. 전체가 중단되지 않는다.

### 옵션

| 옵션 | 설명 |
|---|---|
| `-DryRun` | 실제 변경 없이 수행할 작업만 출력 |
| `-SkipScoop` | Scoop 단계 생략 |
| `-SkipWinget` | winget 단계 생략 |
| `-SkipConfigs` | 설정 파일 복사 생략 |
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

Chocolatey 는 제외했다. 대부분 관리자 권한을 요구해 권한 제한 환경에서 실패한다.

`nvm` / `pyenv` 는 `nodejs-lts` / `python` 과 shim 이 겹쳐 나중에 설치된 쪽이 PATH 우선권을 갖는다.
평소에는 최신 LTS 단일 버전을 쓰고, 프로젝트별 버전 요구가 생기면 아래로 전환한다.

```powershell
nvm install lts       ; nvm use lts
pyenv install 3.13.0  ; pyenv global 3.13.0
```

Scoop 단계는 어떤 PC에서도 실행되므로, 툴체인은 winget 목록에서 제외했다.
따라서 관리자 권한이 없는 PC에서도 개발은 바로 시작할 수 있다.

`java` 버킷처럼 기본 버킷이 아닌 곳의 패키지는 `java/temurin21-jdk` 형식으로 적으면
bootstrap 이 버킷을 자동으로 추가한다.

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

## PC 고유 git 설정

`configs/.gitconfig` 는 모든 PC 에 공통으로 적용되는 값만 담는다.
사내 git 서버 credential, `core.hooksPath`, `core.excludesFile` 처럼 PC 마다 달라지는 값은
`~/.gitconfig.local` 에 작성한다. `configs/.gitconfig` 마지막의 `[include]` 가 이를 읽어들이며,
같은 키를 다시 정의하면 로컬 값이 우선한다. 파일이 없으면 git 이 조용히 무시한다.

```ini
# ~/.gitconfig.local
[credential "https://git.example.co.kr:58021"]
	provider = generic
[core]
	excludesFile = C:/Users/<사용자>/bin/global-gitignore
	hooksPath = C:/Users/<사용자>/bin/.githooks
```

bootstrap 은 기존 `$HOME\.gitconfig` 를 `.gitconfig.bak` 으로 백업한 뒤 덮어쓴다.
이미 쓰던 PC 에서 실행했다면 백업본을 열어 PC 고유 설정을 `~/.gitconfig.local` 로 옮겨야 한다.

## 확정 스택

| 항목 | 값 |
|---|---|
| Java | 21 (`java/temurin21-jdk`) |
| Node.js | 최신 LTS (`main/nodejs-lts`) |
| Python | 최신 안정판 (`main/python`) |
| Git user.name | serena |
| Git user.email | 239265396+hayohio-bit@users.noreply.github.com |
| IDE | Antigravity (`Google.Antigravity`, `Google.AntigravityIDE`) |
| 에이전트 오케스트레이션 | Orca (`StablyAI.Orca`) |

## WSL 설정

`configs/.wslconfig` 는 저사양 PC 에서 Docker/WSL 이 호스트 자원을 과점하는 문제를 완화한다.

```ini
[wsl2]
memory=8GB
processors=4
swap=0
```

복사 후 아래 명령으로 적용한다.

```powershell
wsl --shutdown
```

메모리가 16GB 미만인 PC 는 `memory` 값을 4GB 로 낮추는 것을 검토한다.

Docker 속도 저하의 나머지 원인과 대응은 아래와 같다.

1. 바인드 마운트 I/O — 프로젝트를 Windows 경로(`C:\Users\...`) 대신
   WSL 내부 경로(`\\wsl$\Ubuntu\home\...`)에 두면 파일시스템 호환성 문제를 회피할 수 있다.
2. Vmmem 메모리 무제한 점유 — 위 `.wslconfig` 로 상한을 건다.
3. 그래도 해소되지 않으면 Podman 전환(`scoop install podman`, `podman machine init/start`)
   또는 컨테이너를 원격/클라우드 서버에서 실행하는 방식을 검토한다.
   Docker Desktop 은 상업적 사용 시 유료 라이선스가 필요하다는 점도 함께 고려한다.

## 새 PC 검증 절차

```powershell
.\bootstrap.ps1 -DryRun                                       # 계획 확인
.\bootstrap.ps1 -SkipScoop -SkipWinget -HomePath C:\temp\newpc # 설정 배치만 격리 확인
.\bootstrap.ps1                                               # 실제 실행 (관리자 권한 권장)

# 새 터미널에서
git --version
java -version
node -v
python --version
Get-Content $HOME\.gitconfig
Get-Content $HOME\.wslconfig
```

### 이미 쓰던 PC 에서 실행할 때 주의

Scoop 이 설치하는 `git` / `nodejs-lts` / `python` / `temurin21-jdk` 는
`~\scoop\shims` 를 통해 PATH 앞쪽에 놓이므로, winget 등으로 이미 설치한 같은 도구를 가린다.
새 PC 구축이 아니라 기존 PC 에서 시험만 할 목적이라면 `-DryRun` 또는 `-SkipScoop` 을 쓸 것.
