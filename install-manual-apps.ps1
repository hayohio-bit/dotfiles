#Requires -Version 5.1
<#
.SYNOPSIS
    패키지 매니저로 설치할 수 없거나, 무권한 PC 에서 winget 을 쓸 수 없을 때 필요한 앱을 안내한다.

.DESCRIPTION
    bootstrap.ps1 의 마지막 단계에서 호출되며 단독 실행도 가능하다.

    winget 이 있는 PC 에서는 apps/winget-apps.json 이 이미 해당 앱을 설치하므로,
    이 스크립트는 실제로 누락된 항목만 골라 다운로드 페이지를 연다.
    winget 이 없는 PC(무권한 환경)에서는 전체 목록의 페이지를 연다.

.PARAMETER Force
    설치 여부와 무관하게 모든 다운로드 페이지를 연다.

.PARAMETER ListOnly
    브라우저를 열지 않고 목록만 출력한다.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$ListOnly
)

# winget 이 없거나 등록되지 않은 경로로 받아야 하는 앱 목록.
# WingetId 가 있으면 winget 으로 설치 가능한지 먼저 확인한다.
$manualApps = @(
    [pscustomobject]@{
        Name     = 'Orca (AI 에이전트 오케스트레이션)'
        WingetId = 'StablyAI.Orca'
        Url      = 'https://github.com/stablyai/orca/releases/latest'
        Note     = 'winget 에 StablyAI.Orca 로 등록되어 있음. 무권한 PC 는 Releases 에서 직접 설치.'
    }
    [pscustomobject]@{
        Name     = 'Antigravity (IDE)'
        WingetId = 'Google.Antigravity'
        Url      = 'https://antigravity.google/download'
        Note     = 'winget: Google.Antigravity / Google.AntigravityIDE'
    }
    [pscustomobject]@{
        Name     = 'Docker Desktop'
        WingetId = 'Docker.DockerDesktop'
        Url      = 'https://www.docker.com/products/docker-desktop/'
        Note     = '관리자 권한 필수. 저사양 PC 는 configs/.wslconfig 적용 후 사용할 것.'
    }
)

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

function Test-WingetInstalled {
    param([string]$Id)
    if (-not $hasWinget -or -not $Id) { return $false }
    winget list --id $Id --exact --accept-source-agreements 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
}

Write-Host ""
Write-Host "  수동 설치 확인 대상" -ForegroundColor White

$pending = @()

foreach ($app in $manualApps) {
    if ($Force) {
        $pending += $app
        continue
    }
    if (Test-WingetInstalled -Id $app.WingetId) {
        Write-Host "    [OK]   $($app.Name) - 이미 설치됨" -ForegroundColor Green
    } else {
        $pending += $app
    }
}

if ($pending.Count -eq 0) {
    Write-Host "    모든 앱이 설치되어 있습니다. 추가 작업 없음." -ForegroundColor Green
    return
}

foreach ($app in $pending) {
    Write-Host "    [필요] $($app.Name)" -ForegroundColor Yellow
    Write-Host "           $($app.Url)"
    if ($app.Note) { Write-Host "           $($app.Note)" -ForegroundColor Gray }
}

if ($ListOnly) {
    Write-Host ""
    Write-Host "    -ListOnly 지정으로 브라우저를 열지 않았습니다." -ForegroundColor Gray
    return
}

Write-Host ""
Write-Host "    다운로드 페이지를 엽니다..." -ForegroundColor Gray
foreach ($app in $pending) {
    try {
        Start-Process $app.Url
    }
    catch {
        Write-Warning "페이지를 열지 못했습니다: $($app.Url) / $($_.Exception.Message)"
    }
}
