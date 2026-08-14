# dotfiles

새 개발 PC 의 환경을 자동으로 구축하는 스크립트 모음이다.
OS 마다 패키지 매니저와 스크립트 언어가 다르므로 디렉터리를 나누어 두었다.

| OS | 디렉터리 | 패키지 매니저 | 진입점 |
|---|---|---|---|
| Windows | [`windows/`](windows/README.md) | Scoop + winget | `bootstrap.ps1` |
| macOS | [`mac/`](mac/README.md) | Homebrew | `bootstrap.sh` |

각 디렉터리의 README 에 설치 절차 전체가 들어 있다. 자기 OS 의 문서만 보면 된다.

---

## 리포지토리 구조

```
dotfiles/
├── README.md      # 이 파일
├── windows/       # PowerShell + Scoop/winget
└── mac/           # zsh + Homebrew
```

두 디렉터리는 서로를 참조하지 않는다. 스크립트도 설정 파일도 각자 완결되어 있으므로,
한쪽을 수정해도 다른 쪽이 깨지지 않는다.

### OS 별 디렉터리로 나눈 이유

브랜치로 나누면 README 나 공통 문서를 고칠 때마다 양쪽에 반영해야 하고,
한 번이라도 빠뜨리면 두 브랜치가 조용히 어긋난다.
파일 이름이 OS 마다 다르므로(`bootstrap.ps1` / `bootstrap.sh`,
`winget-apps.json` / `Brewfile`) 같은 브랜치에 두어도 충돌하지 않는다.

### 설정 파일을 공유하지 않는 이유

`.gitconfig` 는 양쪽이 거의 같지만 `core.autocrlf` 값이 다르다
(Windows 는 `true`, macOS 는 `input`). 값 하나 때문에 공유 디렉터리와
OS 별 오버레이를 만드는 것보다, 파일을 각자 두고 한쪽을 고칠 때 다른 쪽도 보는 편이
구조가 단순하다. 항목이 더 늘어나면 그때 분리를 다시 검토한다.

`mise.toml` 은 양쪽이 완전히 같지만 같은 이유로 각 디렉터리에 둔다.
배치되는 경로는 OS 마다 다르다
(Windows `%USERPROFILE%\.config\mise\config.toml`, macOS `~/.config/mise/config.toml`).
양쪽 다 홈 아래다. Windows 에서 `%LOCALAPPDATA%\mise` 는 설정이 아니라 **데이터**
(내려받은 런타임과 shim)가 들어가는 곳이라 헷갈리기 쉽다.

## 공통 규약

- **PC 고유 설정은 커밋하지 않는다.** 사내 git 서버 credential, `core.hooksPath`,
  `core.excludesFile` 처럼 PC 마다 달라지는 값은 `~/.gitconfig.local` 에 작성한다.
  양쪽 `.gitconfig` 모두 마지막에 `[include] path = ~/.gitconfig.local` 을 두어
  이 파일이 있으면 읽고 없으면 조용히 무시한다.
- **기존 설정 파일은 덮어쓰기 전에 `.bak` 으로 백업한다.**
- **개별 앱 설치가 실패해도 전체를 중단하지 않는다.** 경고로 기록하고 다음으로 넘어가며,
  마지막에 실패 항목을 모아 출력한다.
- **실제로 설치하기 전에 `--dry-run` 으로 계획을 먼저 확인한다.**
  (Windows 는 `-DryRun`, macOS 는 `--dry-run`)

## 확정 스택

OS 와 무관하게 아래로 맞춘다.

| 항목 | 값 | 관리 주체 |
|---|---|---|
| Java | 기본 Temurin 21 | mise |
| Node.js | 기본 최신 LTS | mise |
| Python | 기본 3.13 | mise |
| Bun | 최신 | mise |
| Rust | stable | rustup |
| 컨테이너 | Windows: WSL2 + Docker Engine / macOS: Colima | — |
| DB 서버 | MySQL 로컬 설치 + 필요 시 컨테이너 | winget / Homebrew |
| Git user.name | serena | — |
| Git user.email | 239265396+hayohio-bit@users.noreply.github.com | — |

### 런타임 버전은 고정하지 않는다

위 표의 Java·Node·Python·Bun 값은 **기본값**이지 고정값이 아니다.
프로젝트마다 필요한 버전이 다르므로 런타임을 패키지 매니저로 깔지 않고
[mise](https://mise.jdx.dev/) 하나에 맡긴다.

mise 는 shim 을 설치한다. shim 은 진짜 실행 파일 대신 PATH 에 놓이는 얇은 중계
실행 파일로, `java` 를 호출하면 shim 이 현재 디렉터리에서 위로 올라가며 `mise.toml`
을 찾아 거기 적힌 버전의 실제 `java` 로 넘긴다. 그래서 디렉터리를 옮기는 것만으로
버전이 바뀐다.

기본값은 각 OS 의 `configs/mise.toml` 에 있다. 프로젝트에서 다른 버전을 쓰려면
그 저장소 루트에서 아래를 실행하고, 만들어진 `mise.toml` 을 커밋한다.

```
mise use java@temurin-17
mise use node@22
```

Rust 만 예외로 rustup 이 맡는다. rustup 이 이미 `rust-toolchain.toml` 을 읽어
프로젝트별 전환을 하므로, mise 까지 끼면 같은 일을 두 곳에서 관리하게 된다.

shim 은 명령을 올바른 버전으로 넘겨줄 뿐 **환경 변수는 건드리지 않는다.**
`JAVA_HOME` 이 그래서 문제가 되는데, Gradle 과 Maven 이 이 값을 `java` 명령보다
먼저 보기 때문이다. 이를 위해 양쪽 OS 모두 셸에 `mise activate` 훅을 건다.
훅은 프롬프트가 그려질 때마다 `mise hook-env` 를 돌려 환경 변수를 다시 계산한다.

| OS | 훅 | 넣는 곳 |
|---|---|---|
| Windows | `mise activate pwsh` | PowerShell 프로필 (`$PROFILE.CurrentUserAllHosts`) |
| macOS | `mise activate zsh` | `~/.zshrc` |

훅은 그 셸 안에서만 동작한다. cmd.exe 나 IDE 가 직접 띄운 빌드 프로세스는 훅을 받지
못하므로 shim 이 유일한 경로가 되고, 거기서는 `JAVA_HOME` 이 갱신되지 않는다.
그래서 `JAVA_HOME` 을 시스템에 고정해 두지 않는 것이 이 구성의 전제다.
자세한 내용은 [`windows/README.md`](windows/README.md) 의 "mise" 절에 있다.

### Docker Desktop 을 쓰지 않는다

macOS 와 Windows 에는 리눅스 커널이 없어서 컨테이너를 그대로 돌릴 수 없다.
어느 방식이든 리눅스 VM 안에서 도커 데몬을 띄우고 호스트의 CLI 가 그 데몬에 붙는
구조다. Docker Desktop 은 그 VM 과 GUI 를 묶어 파는 상용 제품이고, 일정 규모 이상의
조직에서는 유상 구독이 필요하다.

이 저장소는 같은 일을 하는 오픈소스 구성으로 대체한다.

| OS | 구성 | 설치 주체 |
|---|---|---|
| Windows | WSL2 배포판 안에 Docker Engine(`docker-ce`) | `windows/scripts/install-docker-wsl.sh` |
| macOS | Colima (Lima VM + 도커 데몬) + `docker` CLI | `mac/Brewfile` |

GUI 는 없어진다. 컨테이너 목록과 로그는 `docker ps` / `docker logs` 로 보거나,
GUI 가 필요하면 DBeaver 처럼 별도 클라이언트를 쓴다.
