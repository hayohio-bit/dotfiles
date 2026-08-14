#Requires -Version 5.1
<#
.SYNOPSIS
    새 PC 개발환경 자동 구축 스크립트.

.DESCRIPTION
    권한 수준이 확정되지 않은 PC(관리형 / 개인)에 대응하기 위해 이중 구조로 동작한다.

      - Scoop  : 관리자 권한 없이 설치 가능한 개발 툴체인 (apps/scoop-apps.txt)
      - winget : 관리자 권한이 필요한 GUI 앱 및 런타임      (apps/winget-apps.json)

    Scoop 단계는 항상 실행되고, winget 단계는 winget 이 있을 때만 실행된다.
    두 목록은 서로 중복되지 않는다. 개별 앱 설치 실패는 경고로 처리하고 전체를 중단하지 않는다.

    언어 런타임(Java, Node, Python, Bun)은 두 목록 어디에도 없다. 프로젝트마다 필요한
    버전이 달라서 패키지 매니저로 고정하면 안 되기 때문이다. 대신 Scoop 이 mise 를 깔고,
    3-1 단계가 configs/mise.toml 의 기본 버전을 설치한다.

    컨테이너 런타임도 Docker Desktop 을 쓰지 않는다. 4단계가 WSL2 배포판 안에
    Docker Engine 을 설치한다. 자세한 배경은 README.md 의 "Docker" 절을 볼 것.

    git 과 gh 는 이 저장소를 clone 하는 시점에 이미 있어야 하므로 README 1단계에서
    winget 으로 먼저 설치한다. Scoop 목록에는 넣지 않는다. winget 은 시스템 PATH 에,
    Scoop 은 사용자 PATH 에 등록되는데 Windows 는 시스템 PATH 를 먼저 탐색하므로,
    Scoop 으로 또 설치하면 쓰이지 않는 사본만 남는다.

    winget import 는 패키지별 --override 를 지원하지 않으므로, 설치 관리자에 인자를
    넘겨야 하는 패키지(Visual Studio Build Tools 등)는 apps/winget-overrides.json 에
    따로 두고 import 이후 개별 설치한다.

.PARAMETER Select
    설치 전에 체크박스 선택 화면을 띄워 설치할 항목만 고른다.
    이미 설치된 항목은 기본 해제 상태로 표시된다.
    입력이 리다이렉트된 환경에서는 화면을 건너뛰고 미설치 항목 전체를 선택한다.

.PARAMETER SkipScoop
    Scoop 설치 단계를 건너뛴다.

.PARAMETER SkipWinget
    winget 설치 단계를 건너뛴다.

.PARAMETER SkipConfigs
    설정 파일($HOME 복사) 단계를 건너뛴다.

.PARAMETER SkipMise
    mise 런타임 설치 단계(3-1)를 건너뛴다.

.PARAMETER SkipDocker
    WSL Docker Engine 설치 단계(4)를 건너뛴다.
    WSL 을 쓰지 않거나 컨테이너가 필요 없는 PC 에서 지정한다.

.PARAMETER WslDistro
    Docker Engine 을 설치할 WSL 배포판 이름. 기본값은 WSL 기본 배포판.

.PARAMETER UpgradeExisting
    winget 단계에서 이미 설치된 앱도 최신 버전으로 올린다.
    기본값은 건너뛰기(--no-upgrade)이므로 여러 번 실행해도 재설치가 일어나지 않는다.

.PARAMETER HomePath
    설정 파일을 복사할 대상 디렉터리. 기본값은 $HOME.
    빈 디렉터리를 지정하면 실제 홈을 건드리지 않고 새 PC 상황을 그대로 재현할 수 있다.

.PARAMETER DryRun
    실제 설치/복사 없이 수행할 작업만 출력한다. 새 PC 투입 전 검증용.

.EXAMPLE
    .\bootstrap.ps1
    전체 실행. winget 단계는 관리자 권한 PowerShell 을 권장한다.

.EXAMPLE
    .\bootstrap.ps1 -Select
    선택 화면에서 설치할 항목만 고른 뒤 진행한다.

.EXAMPLE
    .\bootstrap.ps1 -DryRun
    아무것도 설치하지 않고 실행 계획만 확인한다.

.EXAMPLE
    .\bootstrap.ps1 -SkipScoop -SkipWinget -HomePath C:\temp\newpc
    설정 파일 배치만 격리된 디렉터리에 재현해 결과를 확인한다.
#>
[CmdletBinding()]
param(
    [switch]$Select,
    [switch]$SkipScoop,
    [switch]$SkipWinget,
    [switch]$SkipConfigs,
    [switch]$SkipMise,
    [switch]$SkipDocker,
    [string]$WslDistro,
    [switch]$UpgradeExisting,
    [string]$HomePath = $HOME,
    [switch]$DryRun
)

# ---------------------------------------------------------------------------
# 0. 실행 정책 해제 및 차단 해제
# ---------------------------------------------------------------------------
# 그룹 정책이나 상위 스코프에서 실행 정책이 강제된 PC(관리형 PC 등)에서는
# CurrentUser 스코프 변경이 거부된다. 이미 스크립트가 실행 중이라는 것은
# 유효 정책이 충분하다는 뜻이므로, 실패해도 진행을 막지 않는다.
#
# -DryRun 에서는 건너뛴다. 실행 정책은 PC 설정이고, "실제 변경 없이 계획만 출력"이라는
# -DryRun 의 약속을 이 한 줄이 깨고 있었다. 계획만 볼 때는 이미 스크립트가 돌고 있으니
# 정책을 바꿀 이유도 없다.
if ($DryRun) {
    Write-Host "  [INFO] DRY RUN: 실행 정책을 바꾸지 않습니다 (현재 유효 정책: $(Get-ExecutionPolicy))." -ForegroundColor Gray
}
else {
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    }
    catch {
        Write-Host "  [INFO] 실행 정책 변경이 상위 정책에 의해 거부됨 (현재 유효 정책: $(Get-ExecutionPolicy)). 계속 진행합니다." -ForegroundColor Gray
    }
}

# 이쪽은 -DryRun 에서도 실행한다. 저장소 안의 .ps1 에 붙은 다운로드 차단 표시를 떼는
# 것뿐이고, 아래에서 lib\Select-Packages.ps1 을 점 소싱하려면 먼저 풀려 있어야 한다.
# PC 설정이 아니라 이 저장소 파일에만 영향을 준다.
Get-ChildItem -Path $PSScriptRoot -Filter *.ps1 -Recurse | Unblock-File

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$script:Warnings = New-Object System.Collections.Generic.List[string]

function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "  [OK]   $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "  [..]   $Message" -ForegroundColor Gray }
function Write-Fail {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
    $script:Warnings.Add($Message)
}

function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin        = Test-Administrator
$appsDir        = Join-Path $PSScriptRoot 'apps'
$configsDir     = Join-Path $PSScriptRoot 'configs'
$scoopList      = Join-Path $appsDir 'scoop-apps.txt'
$wingetList     = Join-Path $appsDir 'winget-apps.json'
$overrideList   = Join-Path $appsDir 'winget-overrides.json'

# mise 는 설정과 데이터를 서로 다른 곳에 둔다. `mise doctor` 의 dirs 출력 기준이다.
#
#   config : ~\.config\mise\config.toml      (홈 아래. XDG_CONFIG_HOME 규칙을 그대로 씀)
#   data   : %LOCALAPPDATA%\mise             (Windows 만 XDG_DATA_HOME 이 여기로 매핑됨)
#   shims  : %LOCALAPPDATA%\mise\shims
#
# 설정만 홈 아래라는 점이 헷갈리기 쉽다. config 를 %LOCALAPPDATA% 에 두면 mise 가
# 읽지 않아 `mise install` 이 아무것도 설치하지 않고 조용히 성공한다.
$miseConfigFile = Join-Path $HomePath '.config\mise\config.toml'

# shim 경로는 실제 LOCALAPPDATA 를 따른다. -HomePath 로 가짜 홈을 지정한 검증 실행에서는
# 아래 3-1 단계가 PATH 등록 자체를 건너뛰므로 이 값이 쓰이지 않는다.
$miseShims      = Join-Path $env:LOCALAPPDATA 'mise\shims'

# lib 는 -Select 화면뿐 아니라 winget 개별 설치 단계에서도 쓰이므로 항상 읽어둔다.
$libLoaded    = $false
$pickerScript = Join-Path $PSScriptRoot 'lib\Select-Packages.ps1'
if (Test-Path $pickerScript) {
    . $pickerScript
    $libLoaded = $true
}

Write-Host ""
Write-Host "개발환경 자동 구축 시작" -ForegroundColor White
Write-Host "  스크립트 위치 : $PSScriptRoot"
Write-Host "  관리자 권한   : $(if ($isAdmin) { '있음' } else { '없음 (winget 단계가 실패할 수 있음)' })"
Write-Host "  설정 대상     : $HomePath"
if ($DryRun) { Write-Host "  실행 모드     : DRY RUN (실제 변경 없음)" -ForegroundColor Magenta }

# ---------------------------------------------------------------------------
# 0-1. 설치 항목 선택 (-Select)
# ---------------------------------------------------------------------------
# $null 이면 목록 파일 전체를 그대로 쓴다. 배열이면 선택된 항목만 설치한다.
$selectedScoop    = $null
$selectedWinget   = $null
$selectedOverride = $null

if ($Select) {
    Write-Step '0. 설치 항목 선택'

    if (-not $libLoaded) {
        Write-Fail "선택기 없음: $pickerScript / 목록 전체로 진행"
    }
    else {
        $candidates = @()
        if (-not $SkipScoop  -and (Test-Path $scoopList))    { $candidates += Read-ScoopAppList       -Path $scoopList }
        if (-not $SkipWinget -and (Test-Path $wingetList))   { $candidates += Read-WingetAppList      -Path $wingetList }
        if (-not $SkipWinget -and (Test-Path $overrideList)) { $candidates += Read-WingetOverrideList -Path $overrideList }

        if ($candidates.Count -eq 0) {
            Write-Fail '선택할 항목이 없음 / 목록 전체로 진행'
        }
        else {
            Write-Info '현재 설치 상태 확인 중... (winget export 때문에 20초 정도 걸릴 수 있음)'
            $installedScoop  = Get-InstalledScoopId
            $installedWinget = Get-InstalledWingetId

            foreach ($candidate in $candidates) {
                $isInstalled = switch ($candidate.Manager) {
                    'scoop'           { $installedScoop.Contains($candidate.Name) }
                    'winget-override' { Test-WingetOverrideInstalled -Item $candidate -InstalledWinget $installedWinget }
                    default           { $installedWinget.Contains($candidate.Id) }
                }
                $candidate | Add-Member -NotePropertyName Installed -NotePropertyValue $isInstalled -Force
            }

            $picked = Show-PackagePicker -Items $candidates
            if ($null -eq $picked) {
                Write-Host ""
                Write-Host "선택이 취소되었습니다. 아무것도 변경하지 않고 종료합니다." -ForegroundColor Yellow
                return
            }

            $selectedScoop    = @($picked | Where-Object { $_.Manager -eq 'scoop'  } | ForEach-Object { $_.Id })
            $selectedWinget   = @($picked | Where-Object { $_.Manager -eq 'winget' } | ForEach-Object { $_.Id })
            # 개별 설치 항목은 Override 문자열이 필요하므로 ID 가 아니라 객체를 그대로 넘긴다.
            $selectedOverride = @($picked | Where-Object { $_.Manager -eq 'winget-override' })
            Write-Ok "선택 완료: Scoop $($selectedScoop.Count) 개 / winget $($selectedWinget.Count) 개 / 개별 설치 $($selectedOverride.Count) 개"
        }
    }
}

# ---------------------------------------------------------------------------
# 1. Scoop 설치 (관리자 권한 불필요)
# ---------------------------------------------------------------------------
if (-not $SkipScoop) {
    Write-Step '1. Scoop'

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Ok 'Scoop 이미 설치됨'
    }
    elseif ($DryRun) {
        Write-Info 'Scoop 미설치 상태 -> 설치 예정 (get.scoop.sh)'
    }
    else {
        try {
            Write-Info 'Scoop 설치 중...'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
            $env:Path = "$env:USERPROFILE\scoop\shims;$env:Path"
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                Write-Ok 'Scoop 설치 완료'
            } else {
                Write-Fail 'Scoop 설치 후에도 scoop 명령을 찾을 수 없음'
            }
        }
        catch {
            Write-Fail "Scoop 설치 실패: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path $scoopList)) {
        Write-Fail "목록 파일 없음: $scoopList"
    }
    elseif (-not (Get-Command scoop -ErrorAction SilentlyContinue) -and -not $DryRun) {
        Write-Fail 'Scoop 을 사용할 수 없어 Scoop 앱 설치를 건너뜀'
    }
    else {
        # 선택 화면을 거쳤으면 고른 항목만, 아니면 목록 전체(주석/빈 줄 제거)를 쓴다.
        # '#>' 로 시작하는 그룹 머리글도 '#' 조건에 함께 걸러진다.
        $scoopEntries = @(
            if ($null -ne $selectedScoop) {
                $selectedScoop
            } else {
                Get-Content $scoopList -Encoding UTF8 |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -and -not $_.StartsWith('#') }
            }
        )

        if ($scoopEntries.Count -eq 0) { Write-Info '설치할 Scoop 항목이 없음' }

        # 'bucket/package' 형식에서 필요한 버킷을 추린다.
        $buckets = @(
            $scoopEntries |
                Where-Object { $_ -like '*/*' } |
                ForEach-Object { $_.Split('/')[0] } |
                Sort-Object -Unique
        )

        # scoop 설치 직후에는 shims 가 PATH 에 없을 수 있다.
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $shims = Join-Path $env:USERPROFILE 'scoop\shims'
            if ((Test-Path $shims) -and ($env:Path -notlike "*$shims*")) {
                $env:Path = "$shims;$env:Path"
            }
        }

        # scoop bucket add 는 내부에서 git clone 을 쓰므로 git 이 없으면
        # "Git is required for buckets" 로 실패한다. (main 버킷은 scoop 설치 시 함께
        # 등록되므로 git 없이도 설치할 수 있다.)
        #
        # 보통은 이 저장소를 clone 하는 시점에 winget 으로 git 을 설치했으므로 여기서
        # 할 일이 없다. 관리자 권한이 없어 ZIP 으로 저장소를 받은 경우에만 git 이 없을 수
        # 있고, 그때만 버킷 추가용으로 Scoop git 을 설치한다.
        # apps/scoop-apps.txt 에 git 을 넣지 않는 이유는 파일 머리말을 참고할 것.
        if ($buckets.Count -gt 0 -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
            if ($DryRun) {
                Write-Info '버킷 추가 전에 Scoop git 설치 예정 (git 이 없고 버킷 추가에 필요)'
            }
            else {
                try {
                    Write-Info '버킷 추가에 git 이 필요하나 찾을 수 없어 Scoop 으로 설치'
                    $global:LASTEXITCODE = 0
                    scoop install git
                    if ($LASTEXITCODE -ne 0) { throw "scoop 종료 코드 $LASTEXITCODE" }
                    $shims = Join-Path $env:USERPROFILE 'scoop\shims'
                    if ($env:Path -notlike "*$shims*") { $env:Path = "$shims;$env:Path" }
                    Write-Ok 'git (버킷 추가용)'
                }
                catch {
                    Write-Fail "git 설치 실패: $($_.Exception.Message) / 버킷 추가가 실패할 수 있음"
                }
            }
        }

        foreach ($bucket in $buckets) {
            if ($DryRun) { Write-Info "버킷 추가 예정: $bucket"; continue }
            try {
                $existing = (scoop bucket list 6>$null) | Out-String
                if ($existing -match "(?m)^\s*$([regex]::Escape($bucket))\s") {
                    Write-Ok "버킷 이미 등록됨: $bucket"
                } else {
                    scoop bucket add $bucket
                    # add_bucket 은 실패해도 예외를 던지지 않고 종료 코드로만 알린다.
                    if ($LASTEXITCODE -ne 0) { throw "scoop 종료 코드 $LASTEXITCODE" }
                    Write-Ok "버킷 추가: $bucket"
                }
            }
            catch {
                Write-Fail "버킷 추가 실패: $bucket / $($_.Exception.Message) / 이 버킷의 패키지는 설치되지 않음"
            }
        }

        foreach ($app in $scoopEntries) {
            if ($DryRun) { Write-Info "설치 예정: $app"; continue }
            try {
                Write-Info "설치: $app"
                # scoop 은 PATHEXT 에 따라 셸 심(scoop.ps1)으로 실행될 수 있고, 그때는
                # $LASTEXITCODE 가 갱신되지 않아 직전 네이티브 명령의 값이 그대로 남는다.
                # 미리 0 으로 두어 오탐을 막고, 실제 설치 여부는 아래에서 다시 대조한다.
                $global:LASTEXITCODE = 0
                scoop install $app
                if ($LASTEXITCODE -ne 0) {
                    throw "scoop 종료 코드 $LASTEXITCODE"
                }
                Write-Ok $app
            }
            catch {
                # 개별 실패는 흡수하고 다음 앱으로 계속 진행한다.
                Write-Fail "설치 실패: $app / $($_.Exception.Message) / 계속 진행"
            }
        }

        # 종료 코드만 믿으면 실패를 놓칠 수 있으므로 실제 설치 결과를 대조한다.
        # 버킷 추가가 실패해 목록 뒷부분이 통째로 빠지는 상황을 조용히 넘기지 않기 위한 것이다.
        if (-not $DryRun -and $libLoaded -and
            $scoopEntries.Count -gt 0 -and
            (Get-Command scoop -ErrorAction SilentlyContinue)) {

            $installedNow = Get-InstalledScoopId
            # 'bucket/package' 형식은 실제 패키지 이름으로만 조회된다.
            $missing = @($scoopEntries | Where-Object { -not $installedNow.Contains($_.Split('/')[-1]) })

            if ($missing.Count -eq 0) {
                Write-Ok "Scoop 항목 $($scoopEntries.Count) 개 모두 설치 확인"
            } else {
                Write-Fail "Scoop 설치 확인 실패 $($missing.Count) 개: $($missing -join ', ')"
            }
        }
    }
}
else {
    Write-Step '1. Scoop (건너뜀)'
}

# ---------------------------------------------------------------------------
# 2. winget 설치 (관리자 권한 필요)
# ---------------------------------------------------------------------------
if (-not $SkipWinget) {
    Write-Step '2. winget'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail 'winget 을 찾을 수 없음. Microsoft Store 의 "앱 설치 관리자"를 먼저 설치할 것'
    }
    elseif (-not (Test-Path $wingetList)) {
        Write-Fail "목록 파일 없음: $wingetList"
    }
    elseif ($null -ne $selectedWinget -and $selectedWinget.Count -eq 0) {
        Write-Info '선택된 winget 항목이 없어 건너뜀'
    }
    elseif ($DryRun) {
        $count = if ($null -ne $selectedWinget) {
            $selectedWinget.Count
        } else {
            (Get-Content $wingetList -Raw -Encoding UTF8 | ConvertFrom-Json).Sources[0].Packages.Count
        }
        $mode = if ($UpgradeExisting) { '이미 설치된 앱도 최신 버전으로 갱신' } else { '이미 설치된 앱은 건너뜀' }
        Write-Info "winget import 예정: $count 개 패키지, $mode"
    }
    else {
        if (-not $isAdmin) {
            Write-Fail '관리자 권한이 아님. 일부 앱이 UAC 프롬프트를 띄우거나 실패할 수 있음'
        }

        # winget import 는 파일 단위로만 동작하므로, 선택 화면을 거친 경우
        # 고른 패키지만 담은 임시 목록 파일을 만들어 넘긴다.
        $importFile = $wingetList
        $tempImport = $null
        if ($null -ne $selectedWinget) {
            $source = (Get-Content $wingetList -Raw -Encoding UTF8 | ConvertFrom-Json).Sources[0]
            $subset = [ordered]@{
                '$schema'     = 'https://aka.ms/winget-packages.schema.2.0.json'
                CreationDate  = '2026-01-01T00:00:00.000-00:00'
                Sources       = @(
                    [ordered]@{
                        Packages      = @($selectedWinget | ForEach-Object { @{ PackageIdentifier = $_ } })
                        SourceDetails = $source.SourceDetails
                    }
                )
                WinGetVersion = '1.0.0'
            }
            $tempImport = Join-Path ([IO.Path]::GetTempPath()) ("winget-selected-{0}.json" -f [Guid]::NewGuid())
            # PowerShell 5.1 의 Set-Content -Encoding UTF8 은 BOM 을 붙인다.
            # winget 에 넘길 파일이므로 BOM 없는 UTF-8 로 쓴다.
            [IO.File]::WriteAllText(
                $tempImport,
                ($subset | ConvertTo-Json -Depth 10),
                (New-Object Text.UTF8Encoding $false)
            )
            $importFile = $tempImport
            Write-Info "선택된 $($selectedWinget.Count) 개 패키지로 import 진행"
        }

        # winget import 는 기본적으로 이미 설치된 앱도 다시 내려받아 재설치한다.
        # --no-upgrade 를 주면 설치된 버전이 있을 때 건너뛰므로 재실행이 안전해진다.
        # 목록의 앱을 최신으로 올리려면 -UpgradeExisting 을 지정한다.
        $importArgs = @(
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--ignore-unavailable'
            '--disable-interactivity'
        )
        if (-not $UpgradeExisting) { $importArgs += '--no-upgrade' }

        try {
            winget import -i $importFile @importArgs
            if ($LASTEXITCODE -eq 0) {
                Write-Ok 'winget import 완료'
            } else {
                Write-Fail "winget import 가 종료 코드 $LASTEXITCODE 로 끝남. 위 로그에서 실패한 패키지 확인 필요"
            }
        }
        catch {
            Write-Fail "winget import 실패: $($_.Exception.Message)"
        }
        finally {
            if ($tempImport) { Remove-Item $tempImport -Force -ErrorAction SilentlyContinue }
        }
    }
}
else {
    Write-Step '2. winget (건너뜀)'
}

# ---------------------------------------------------------------------------
# 2-1. winget 개별 설치 (설치 관리자에 인자를 넘겨야 하는 패키지)
# ---------------------------------------------------------------------------
# winget import 는 패키지별 --override 를 지원하지 않는다. Build Tools 를 import 로
# 설치하면 설치 관리자만 깔리고 컴파일러/링커가 빠진 채로 '설치됨'이 되어,
# 나중에 Rust 나 node-gyp 빌드가 link.exe 를 못 찾고 실패한다.
# 그래서 이런 패키지는 목록에서 분리해 여기서 구성 요소를 명시해 설치한다.
if (-not $SkipWinget) {
    Write-Step '2-1. winget 개별 설치'

    if (-not $libLoaded) {
        Write-Fail "lib 를 읽지 못해 개별 설치를 건너뜀: $pickerScript"
    }
    elseif (-not (Test-Path $overrideList)) {
        Write-Info "개별 설치 목록 없음: $overrideList / 건너뜀"
    }
    elseif (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail 'winget 을 찾을 수 없어 개별 설치를 건너뜀'
    }
    else {
        # 선택 화면을 거쳤으면 고른 것만, 아니면 목록 전체.
        $overrideEntries = @(
            if ($null -ne $selectedOverride) { $selectedOverride }
            else                             { Read-WingetOverrideList -Path $overrideList }
        )

        if ($overrideEntries.Count -eq 0) { Write-Info '개별 설치할 항목이 없음' }

        foreach ($package in $overrideEntries) {
            # 구분자로 em dash 를 쓰면 콘솔 코드페이지에 따라 '?' 로 깨진다.
            if ($package.Reason) { Write-Info "$($package.Id) : $($package.Reason)" }

            # winget 기준 '설치됨'이 아니라 구성 요소 존재 여부로 판정한다.
            $alreadyUsable = $false
            if ($package.RequiresComponent) {
                $alreadyUsable = Test-VsComponent -ComponentId $package.RequiresComponent
            }

            if ($alreadyUsable -and -not $UpgradeExisting) {
                Write-Ok "$($package.Id) 구성 요소 확인됨 ($($package.RequiresComponent))"
                continue
            }

            if ($DryRun) {
                if ($package.RequiresComponent -and -not $alreadyUsable) {
                    Write-Info "구성 요소 누락 확인 -> 설치 예정: $($package.Id)"
                } else {
                    Write-Info "설치 예정: $($package.Id)"
                }
                Write-Info "  override: $($package.Override)"
                continue
            }

            if (-not $isAdmin) {
                Write-Fail "$($package.Id) 설치에는 관리자 권한이 필요함. UAC 프롬프트가 뜨거나 실패할 수 있음"
            }

            try {
                # 제품이 이미 있고 구성 요소만 빠진 경우, winget install 은
                # 'already installed' 로 건너뛰므로 VS 설치 관리자로 직접 수정한다.
                $installPath = $null
                if ($package.Id -like 'Microsoft.VisualStudio.*.BuildTools') {
                    $installPath = Get-VsInstallPath
                }

                if ($installPath) {
                    $vsInstaller = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vs_installer.exe'
                    Write-Info "이미 설치된 제품에 구성 요소 추가: $installPath"
                    $modifyArgs = @(
                        'modify'
                        '--installPath', $installPath
                        '--add', 'Microsoft.VisualStudio.Workload.VCTools'
                        '--includeRecommended'
                        '--quiet', '--wait', '--norestart'
                    )
                    $proc = Start-Process -FilePath $vsInstaller -ArgumentList $modifyArgs -Wait -PassThru
                    # 3010 = 성공했으나 재부팅 필요
                    if ($proc.ExitCode -notin @(0, 3010)) { throw "vs_installer 종료 코드 $($proc.ExitCode)" }
                    if ($proc.ExitCode -eq 3010) { Write-Info '재부팅이 필요한 상태로 완료됨' }
                }
                else {
                    Write-Info "설치: $($package.Id)"
                    winget install --id $package.Id -e `
                        --accept-package-agreements --accept-source-agreements `
                        --disable-interactivity `
                        --override $package.Override
                    if ($LASTEXITCODE -ne 0) { throw "winget 종료 코드 $LASTEXITCODE" }
                }

                # 설치 후 실제로 구성 요소가 들어갔는지 재확인한다.
                if ($package.RequiresComponent) {
                    if (Test-VsComponent -ComponentId $package.RequiresComponent) {
                        Write-Ok "$($package.Id) (구성 요소 확인 완료)"
                    } else {
                        Write-Fail "$($package.Id) 설치는 끝났으나 구성 요소를 찾지 못함: $($package.RequiresComponent)"
                    }
                } else {
                    Write-Ok $package.Id
                }
            }
            catch {
                Write-Fail "개별 설치 실패: $($package.Id) / $($_.Exception.Message) / 계속 진행"
            }
        }
    }
}
else {
    Write-Step '2-1. winget 개별 설치 (건너뜀)'
}

# ---------------------------------------------------------------------------
# 3. 설정 파일 배치
# ---------------------------------------------------------------------------
if (-not $SkipConfigs) {
    Write-Step '3. 설정 파일'

    if (-not (Test-Path $HomePath)) {
        if ($DryRun) {
            Write-Info "대상 디렉터리 생성 예정: $HomePath"
        } else {
            New-Item -ItemType Directory -Path $HomePath -Force | Out-Null
            Write-Info "대상 디렉터리 생성: $HomePath"
        }
    }

    $configMap = @(
        @{ Source = '.gitconfig'; Target = (Join-Path $HomePath '.gitconfig') }
        @{ Source = '.wslconfig'; Target = (Join-Path $HomePath '.wslconfig') }
        @{ Source = 'mise.toml';  Target = $miseConfigFile }
    )

    foreach ($item in $configMap) {
        $source = Join-Path $configsDir $item.Source
        $target = $item.Target

        if (-not (Test-Path $source)) {
            Write-Fail "원본 없음: $source"
            continue
        }
        # 내용이 이미 같으면 백업본을 만들지 않고 넘어간다. (재실행 시 .bak 이 덮어써지는 것을 막는다)
        if ((Test-Path $target) -and
            ((Get-FileHash $source).Hash -eq (Get-FileHash $target).Hash)) {
            Write-Ok "$($item.Source) 이미 최신 상태"
            continue
        }
        if ($DryRun) {
            Write-Info "복사 예정: $source -> $target"
            continue
        }
        try {
            # mise 설정처럼 홈 바로 아래가 아닌 경로는 상위 디렉터리가 없을 수 있다.
            $targetDir = Split-Path -Parent $target
            if ($targetDir -and -not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                Write-Info "대상 디렉터리 생성: $targetDir"
            }
            if (Test-Path $target) {
                # 기존 설정을 덮어쓰기 전에 항상 백업본을 남긴다.
                $backup = "$target.bak"
                Copy-Item -Path $target -Destination $backup -Force
                Write-Info "기존 파일 백업: $backup"
                if ($item.Source -eq '.gitconfig') {
                    Write-Info '기존 .gitconfig 의 PC 고유 설정(사내 credential, core.hooksPath 등)은 백업본에서 ~/.gitconfig.local 로 옮길 것'
                }
            }
            Copy-Item -Path $source -Destination $target -Force
            Write-Ok "$($item.Source) -> $target"
        }
        catch {
            Write-Fail "복사 실패: $($item.Source) / $($_.Exception.Message)"
        }
    }

    if (-not $DryRun) {
        Write-Info 'WSL 에 .wslconfig 를 적용하려면 "wsl --shutdown" 후 재시작할 것'
    }
}
else {
    Write-Step '3. 설정 파일 (건너뜀)'
}

# ---------------------------------------------------------------------------
# 3-1. mise 런타임
# ---------------------------------------------------------------------------
# Java / Node / Python / Bun 은 Scoop 이나 winget 이 아니라 mise 가 관리한다.
# 여기서 하는 일은 세 가지다.
#
#   1) mise 의 shim 디렉터리를 사용자 PATH 에 영구 등록한다.
#      shim 은 진짜 실행 파일 대신 PATH 에 놓이는 중계 실행 파일이다. `java` 를 치면
#      shim 이 현재 디렉터리부터 위로 올라가며 mise.toml 을 찾아, 거기 적힌 버전의
#      실제 java.exe 로 넘긴다. PowerShell 을 거치지 않고 실행되는 IDE·cmd.exe 는
#      아래 2)의 훅을 받지 못하므로, 이 등록이 그쪽의 유일한 경로다.
#   2) PowerShell 프로필에 `mise activate pwsh` 를 넣는다.
#      shim 은 명령을 올바른 버전으로 넘겨줄 뿐 환경 변수는 건드리지 않는다.
#      activate 는 프롬프트 훅을 걸어 디렉터리를 옮길 때마다 `mise hook-env` 를 돌리고,
#      그래야 JAVA_HOME 이 프로젝트에 맞춰 갱신된다. Gradle 과 Maven 이 이 값을
#      먼저 보므로 훅이 없으면 디렉터리를 옮겨도 빌드에 쓰이는 JDK 가 그대로다.
#   3) configs/mise.toml 에 적힌 기본 버전을 실제로 내려받는다.
#
# -HomePath 로 가짜 홈을 지정한 검증 실행에서는 1)과 2)를 건너뛴다. 둘 다 실제 사용자
# 레지스트리와 실제 프로필을 건드리므로, 격리 검증이라는 -HomePath 의 목적과 어긋난다.
if (-not $SkipMise) {
    Write-Step '3-1. mise 런타임'

    $isRealHome = ($HomePath -eq $HOME)
    if (-not $isRealHome) {
        Write-Info "-HomePath 가 실제 홈이 아니므로 PATH 등록과 프로필 수정을 건너뜁니다."
    }

    # Scoop 설치 직후라 현재 세션 PATH 에 아직 없을 수 있으므로 shims 도 같이 본다.
    $miseCmd = $null
    if (Get-Command mise -ErrorAction SilentlyContinue) {
        $miseCmd = 'mise'
    } else {
        $scoopMise = Join-Path $env:USERPROFILE 'scoop\shims\mise.exe'
        if (Test-Path $scoopMise) { $miseCmd = $scoopMise }
    }

    if (-not $miseCmd -and -not $DryRun) {
        Write-Fail 'mise 를 찾을 수 없어 런타임 설치를 건너뜀. 1단계에서 Scoop 설치가 실패했는지 확인할 것'
    }
    else {
        # --- PATH 등록 -----------------------------------------------------
        # [Environment]::SetEnvironmentVariable(...,'User') 는 REG_EXPAND_SZ 인
        # 사용자 Path 를 REG_SZ 로 바꿔 버려, 기존 항목의 %USERPROFILE% 같은 변수가
        # 확장되지 않은 문자열로 굳는다. 레지스트리를 직접 다뤄 종류를 유지한다.
        if (-not $isRealHome) {
            # 격리 검증 중이다. 실제 레지스트리를 건드리지 않는다.
        }
        elseif ($DryRun) {
            Write-Info "사용자 PATH 에 추가 예정: $miseShims"
        }
        else {
            try {
                $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
                $userPath = $envKey.GetValue(
                    'Path', '',
                    [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                )
                $entries = @($userPath -split ';' | Where-Object { $_ })

                if ($entries -contains $miseShims) {
                    Write-Ok "사용자 PATH 에 이미 등록됨: $miseShims"
                }
                else {
                    # shim 이 다른 매니저의 런타임보다 먼저 잡히도록 앞에 붙인다.
                    $envKey.SetValue(
                        'Path',
                        (@($miseShims) + $entries -join ';'),
                        [Microsoft.Win32.RegistryValueKind]::ExpandString
                    )
                    Write-Ok "사용자 PATH 에 추가: $miseShims"
                    Write-Info '새 터미널부터 적용된다.'
                }
                $envKey.Close()

                # 아래 mise install 과 확인 단계에서 바로 쓰도록 현재 세션에도 반영한다.
                if ($env:Path -notlike "*$miseShims*") { $env:Path = "$miseShims;$env:Path" }
            }
            catch {
                Write-Fail "사용자 PATH 등록 실패: $($_.Exception.Message) / 수동으로 $miseShims 를 추가할 것"
            }
        }

        # --- PowerShell 프로필에 activate 등록 --------------------------------
        # `mise activate pwsh` 는 prompt 함수를 감싸는 훅을 걸고, 프롬프트가 그려질
        # 때마다 `mise hook-env` 를 돌려 PATH 와 환경 변수를 다시 계산한다.
        # 이것이 있어야 JAVA_HOME 이 디렉터리에 맞춰 바뀐다.
        #
        # 프로필 경로는 PowerShell 판마다 다르다 (5.1 은 WindowsPowerShell\,
        # 7 은 PowerShell\). $PROFILE.CurrentUserAllHosts 는 실행 중인 판의 것을
        # 가리키므로, 다른 판을 쓰게 되면 그쪽에는 따로 넣어야 한다.
        $miseHookLine = 'if (Get-Command mise -ErrorAction SilentlyContinue) { (& mise activate pwsh) | Out-String | Invoke-Expression }'
        $profilePath  = $PROFILE.CurrentUserAllHosts

        if (-not $isRealHome) {
            # 격리 검증 중이다. 실제 프로필을 건드리지 않는다.
        }
        elseif ($DryRun) {
            Write-Info "PowerShell 프로필에 mise activate 추가 예정: $profilePath"
        }
        elseif ((Test-Path $profilePath) -and
                (Select-String -Path $profilePath -SimpleMatch 'mise activate pwsh' -Quiet)) {
            Write-Ok "PowerShell 프로필에 mise activate 가 이미 있음"
        }
        else {
            try {
                $profileDir = Split-Path -Parent $profilePath
                if (-not (Test-Path $profileDir)) {
                    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                }
                # 덧붙이는 줄은 ASCII 로만 쓴다. 사용자의 기존 프로필이 BOM 없는
                # UTF-8 이면 PowerShell 5.1 이 파일 전체를 CP949 로 읽어, 여기 한글을
                # 넣었을 때 그 부분이 깨진 문자로 보인다. (주석이라 실행에는 지장이
                # 없지만 남의 파일을 더럽히지 않는다.)
                Add-Content -Path $profilePath -Encoding UTF8 -Value @(
                    ''
                    '# mise - added by dotfiles/windows/bootstrap.ps1'
                    $miseHookLine
                )
                Write-Ok "PowerShell 프로필에 mise activate 추가: $profilePath"
                Write-Info '새 터미널부터 적용된다.'
            }
            catch {
                Write-Fail "프로필 수정 실패: $($_.Exception.Message) / 수동으로 다음 줄을 $profilePath 에 추가할 것: $miseHookLine"
            }
        }

        # --- JAVA_HOME 확인 -------------------------------------------------
        # activate 훅은 mise 가 관리하는 값만 덮어쓴다. 예전 JDK 설치 관리자가 남긴
        # JAVA_HOME 이 사용자·시스템 범위에 있으면, 훅이 걸리지 않는 환경
        # (cmd.exe, IDE 가 직접 띄운 빌드 프로세스)에서는 그 값이 그대로 쓰인다.
        # 자동으로 지우지는 않는다. 다른 도구가 의존하고 있을 수 있어서다.
        foreach ($scope in @('User', 'Machine')) {
            $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', $scope)
            if ($javaHome) {
                Write-Fail "JAVA_HOME 이 $scope 범위에 고정되어 있음: $javaHome / PowerShell 밖(cmd.exe, IDE 빌드)에서 mise 의 Java 버전이 무시된다. README 의 'mise' 절 참고"
            }
        }

        # --- 런타임 설치 ----------------------------------------------------
        # 인자 없는 `mise install` 은 적용 중인 설정 파일에 적힌 도구를 전부 받는다.
        # 3단계가 방금 배치한 전역 config.toml 이 그 대상이다.
        if ($DryRun) {
            Write-Info 'mise install 예정 (configs/mise.toml 의 기본 버전 설치)'
        }
        else {
            try {
                Write-Info 'mise install 실행 중... (JDK 등을 내려받으므로 몇 분 걸릴 수 있음)'
                $global:LASTEXITCODE = 0
                & $miseCmd install --yes
                if ($LASTEXITCODE -ne 0) { throw "mise 종료 코드 $LASTEXITCODE" }
                Write-Ok 'mise 기본 런타임 설치 완료'

                # 새로 깐 런타임의 shim 이 실제로 만들어졌는지 확인한다.
                & $miseCmd reshim 2>$null | Out-Null
                $installed = (& $miseCmd ls --installed 2>$null) | Out-String
                if ($installed.Trim()) {
                    Write-Info "설치된 런타임:`n$($installed.TrimEnd())"
                }
            }
            catch {
                Write-Fail "mise 런타임 설치 실패: $($_.Exception.Message) / 나중에 'mise install' 을 직접 실행할 것"
            }
        }
    }
}
else {
    Write-Step '3-1. mise 런타임 (건너뜀)'
}

# ---------------------------------------------------------------------------
# 4. WSL Docker Engine
# ---------------------------------------------------------------------------
# Docker Desktop 대신 WSL2 배포판 안에 Docker Engine 을 직접 설치한다.
# 실제 작업은 scripts/install-docker-wsl.sh 가 WSL 안에서 수행하고,
# 여기서는 배포판을 고르고 그 스크립트를 넘기는 일만 한다.
if (-not $SkipDocker) {
    Write-Step '4. WSL Docker Engine'

    $dockerScript = Join-Path $PSScriptRoot 'scripts\install-docker-wsl.sh'

    if (-not (Test-Path $dockerScript)) {
        Write-Fail "스크립트 없음: $dockerScript"
    }
    elseif (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Fail 'wsl 명령을 찾을 수 없어 건너뜀. winget 단계의 Microsoft.WSL 설치 후 재부팅이 필요할 수 있음'
    }
    else {
        # 설치된 배포판을 확인한다. wsl.exe 는 출력을 UTF-16LE 로 내보내므로
        # 기본 인코딩으로 읽으면 글자 사이에 널 문자가 낀 문자열이 된다.
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.Encoding]::Unicode
            $distros = @(
                (wsl --list --quiet 2>$null) |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -and $_ -notlike 'docker-desktop*' }
            )
        }
        finally {
            [Console]::OutputEncoding = $prevEncoding
        }

        # -WslDistro 를 주면 그것을 쓰고, 아니면 기본 배포판(목록 첫 줄)을 쓴다.
        $targetDistro = if ($WslDistro) { $WslDistro } else { $distros | Select-Object -First 1 }

        if (-not $targetDistro) {
            Write-Fail 'WSL 배포판이 없어 건너뜀. "wsl --install -d Ubuntu" 로 배포판을 먼저 설치할 것'
        }
        elseif ($WslDistro -and ($distros -notcontains $WslDistro)) {
            Write-Fail "지정한 배포판을 찾을 수 없음: $WslDistro / 설치된 배포판: $($distros -join ', ')"
        }
        else {
            # \\wsl.localhost 경유로 Windows 경로를 읽는 것보다, wslpath 로 변환한
            # /mnt/c/... 경로를 쓰는 편이 배포판 설정에 덜 의존한다.
            #
            # 경로는 반드시 슬래시로 바꿔 넘긴다. 백슬래시가 든 인자를 wsl.exe 에 그대로
            # 주면 리눅스 쪽 argv 처리에서 이스케이프로 해석되어 전부 사라지고,
            # 'C:Users<사용자>...' 같은 문자열이 wslpath 에 전달된다.
            # wslpath 는 'C:/Users/...' 형식도 그대로 받아준다.
            $dockerScriptSlash = $dockerScript.Replace('\', '/')
            $wslPathOutput = @(wsl -d $targetDistro -- wslpath -a $dockerScriptSlash 2>$null)
            $wslScriptPath = ($wslPathOutput | Where-Object { $_ -like '/*' } | Select-Object -First 1)

            if (-not $wslScriptPath) {
                Write-Fail "WSL 안에서 스크립트 경로를 확인하지 못함 ($targetDistro). Windows 드라이브 마운트(automount)가 꺼져 있는지 확인할 것"
            }
            elseif ($DryRun) {
                Write-Info "배포판 '$targetDistro' 에서 실행 예정: bash $wslScriptPath"
                wsl -d $targetDistro -- bash $wslScriptPath --dry-run
            }
            else {
                Write-Info "배포판 '$targetDistro' 에 Docker Engine 설치 (sudo 비밀번호를 물을 수 있음)"
                try {
                    wsl -d $targetDistro -- bash $wslScriptPath
                    if ($LASTEXITCODE -ne 0) { throw "스크립트 종료 코드 $LASTEXITCODE" }
                    Write-Ok "Docker Engine 설치 완료 ($targetDistro)"
                    Write-Info 'systemd 와 docker 그룹을 적용하려면 "wsl --shutdown" 후 재시작할 것'
                }
                catch {
                    Write-Fail "Docker Engine 설치 실패: $($_.Exception.Message) / 위 WSL 로그 확인"
                }
            }
        }
    }

    # Docker Desktop 이 남아 있으면 두 개의 docker CLI 가 PATH 를 두고 다툰다.
    # 자동으로 제거하지는 않는다. 사용자가 직접 정리할 항목으로 알린다.
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget list --id Docker.DockerDesktop --exact --accept-source-agreements 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Fail 'Docker Desktop 이 설치되어 있음. WSL 의 docker CLI 와 PATH 가 충돌하므로 "winget uninstall Docker.DockerDesktop" 으로 제거를 검토할 것'
        }
    }
}
else {
    Write-Step '4. WSL Docker Engine (건너뜀)'
}

# ---------------------------------------------------------------------------
# 5. 패키지 매니저로 설치되지 않는 앱 안내
# ---------------------------------------------------------------------------
Write-Step '5. 수동 설치 안내'

$manualScript = Join-Path $PSScriptRoot 'install-manual-apps.ps1'
if (Test-Path $manualScript) {
    if ($DryRun) {
        Write-Info "실행 예정: $manualScript"
    } else {
        & $manualScript
    }
} else {
    Write-Fail "스크립트 없음: $manualScript"
}

# ---------------------------------------------------------------------------
# 6. 요약
# ---------------------------------------------------------------------------
Write-Step '완료'

if ($script:Warnings.Count -eq 0) {
    Write-Host "  경고 없이 종료되었습니다." -ForegroundColor Green
} else {
    Write-Host "  경고 $($script:Warnings.Count) 건:" -ForegroundColor Yellow
    foreach ($warning in $script:Warnings) {
        Write-Host "    - $warning" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "다음 단계:" -ForegroundColor White
Write-Host "  1) 새 터미널을 열어 PATH 를 갱신한다. (mise shim 등록이 이때 반영된다)"
Write-Host "  2) git --version / java -version / node -v / python --version 으로 확인한다."
Write-Host "     java 와 node 는 mise shim 이 응답해야 한다. 'mise ls' 로 어떤 버전이 잡혔는지 본다."
Write-Host "  3) wsl --shutdown 후 wsl 을 다시 연다. (.wslconfig, systemd, docker 그룹이 이때 적용된다)"
Write-Host "  4) WSL 안에서 'docker run --rm hello-world' 로 컨테이너 동작을 확인한다."
Write-Host ""
