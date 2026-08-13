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

OS 와 무관하게 아래 버전으로 맞춘다.

| 항목 | 값 |
|---|---|
| Java | 21 (Eclipse Temurin) |
| Node.js | 최신 LTS |
| Python | 최신 안정판 |
| Rust | rustup 으로 관리 |
| DB 서버 | Docker 컨테이너로 실행 (로컬 설치 없음) |
| Git user.name | serena |
| Git user.email | 239265396+hayohio-bit@users.noreply.github.com |
