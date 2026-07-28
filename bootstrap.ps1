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
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
}
catch {
    Write-Host "  [INFO] 실행 정책 변경이 상위 정책에 의해 거부됨 (현재 유효 정책: $(Get-ExecutionPolicy)). 계속 진행합니다." -ForegroundColor Gray
}

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

$isAdmin     = Test-Administrator
$appsDir     = Join-Path $PSScriptRoot 'apps'
$configsDir  = Join-Path $PSScriptRoot 'configs'
$scoopList   = Join-Path $appsDir 'scoop-apps.txt'
$wingetList  = Join-Path $appsDir 'winget-apps.json'

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
$selectedScoop  = $null
$selectedWinget = $null

if ($Select) {
    Write-Step '0. 설치 항목 선택'

    $pickerScript = Join-Path $PSScriptRoot 'lib\Select-Packages.ps1'
    if (-not (Test-Path $pickerScript)) {
        Write-Fail "선택기 없음: $pickerScript / 목록 전체로 진행"
    }
    else {
        . $pickerScript

        $candidates = @()
        if (-not $SkipScoop  -and (Test-Path $scoopList))  { $candidates += Read-ScoopAppList  -Path $scoopList }
        if (-not $SkipWinget -and (Test-Path $wingetList)) { $candidates += Read-WingetAppList -Path $wingetList }

        if ($candidates.Count -eq 0) {
            Write-Fail '선택할 항목이 없음 / 목록 전체로 진행'
        }
        else {
            Write-Info '현재 설치 상태 확인 중... (winget export 때문에 20초 정도 걸릴 수 있음)'
            $installedScoop  = Get-InstalledScoopId
            $installedWinget = Get-InstalledWingetId

            foreach ($candidate in $candidates) {
                $isInstalled = if ($candidate.Manager -eq 'scoop') {
                    $installedScoop.Contains($candidate.Name)
                } else {
                    $installedWinget.Contains($candidate.Id)
                }
                $candidate | Add-Member -NotePropertyName Installed -NotePropertyValue $isInstalled -Force
            }

            $picked = Show-PackagePicker -Items $candidates
            if ($null -eq $picked) {
                Write-Host ""
                Write-Host "선택이 취소되었습니다. 아무것도 변경하지 않고 종료합니다." -ForegroundColor Yellow
                return
            }

            $selectedScoop  = @($picked | Where-Object { $_.Manager -eq 'scoop'  } | ForEach-Object { $_.Id })
            $selectedWinget = @($picked | Where-Object { $_.Manager -eq 'winget' } | ForEach-Object { $_.Id })
            Write-Ok "선택 완료: Scoop $($selectedScoop.Count) 개 / winget $($selectedWinget.Count) 개"
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
        # "Git is required for buckets" 로 실패한다. 새 PC 에는 git 이 없을 수 있으니
        # 버킷을 추가하기 전에 git 을 먼저 설치한다. (main 버킷은 scoop 설치 시 함께 등록되어
        # 있으므로 git 없이도 설치할 수 있다.)
        $preInstalled = @()
        if ($buckets.Count -gt 0 -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
            $gitEntry = $scoopEntries | Where-Object { $_ -eq 'git' -or $_ -like '*/git' } | Select-Object -First 1

            if ($DryRun) {
                if ($gitEntry) { Write-Info "버킷 추가 전에 먼저 설치 예정: $gitEntry (버킷 추가에 git 필요)" }
                else           { Write-Info '경고 예정: git 이 없어 버킷 추가가 실패할 수 있음' }
            }
            elseif ($gitEntry) {
                try {
                    Write-Info "버킷 추가에 git 이 필요하므로 먼저 설치: $gitEntry"
                    scoop install $gitEntry
                    if ($LASTEXITCODE -ne 0) { throw "scoop 종료 코드 $LASTEXITCODE" }
                    $shims = Join-Path $env:USERPROFILE 'scoop\shims'
                    if ($env:Path -notlike "*$shims*") { $env:Path = "$shims;$env:Path" }
                    $preInstalled += $gitEntry
                    Write-Ok $gitEntry
                }
                catch {
                    Write-Fail "git 선행 설치 실패: $($_.Exception.Message) / 버킷 추가가 실패할 수 있음"
                }
            }
            else {
                Write-Fail 'git 이 없고 목록에도 없어 버킷 추가가 실패할 수 있음'
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
            if ($preInstalled -contains $app) { continue }
            if ($DryRun) { Write-Info "설치 예정: $app"; continue }
            try {
                Write-Info "설치: $app"
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
            (Get-Content $wingetList -Raw | ConvertFrom-Json).Sources[0].Packages.Count
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
            $source = (Get-Content $wingetList -Raw | ConvertFrom-Json).Sources[0]
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
            $subset | ConvertTo-Json -Depth 10 | Set-Content -Path $tempImport -Encoding UTF8
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
# 4. 패키지 매니저로 설치되지 않는 앱 안내
# ---------------------------------------------------------------------------
Write-Step '4. 수동 설치 안내'

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
# 5. 요약
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
Write-Host "  1) 새 터미널을 열어 PATH 를 갱신한다."
Write-Host "  2) git --version / java -version / node -v / python --version 으로 확인한다."
Write-Host "  3) wsl --shutdown 으로 .wslconfig 를 적용한다."
Write-Host ""
