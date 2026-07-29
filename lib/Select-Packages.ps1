#Requires -Version 5.1
<#
.SYNOPSIS
    설치할 패키지를 콘솔에서 골라내는 체크박스 선택기.

.DESCRIPTION
    bootstrap.ps1 이 -Select 로 실행될 때 점 소싱(dot-source)해서 사용한다.
    외부 모듈에 의존하지 않고 [Console]::ReadKey 만 사용하므로
    Windows PowerShell 5.1 과 PowerShell 7 양쪽에서 동작한다.

    노출하는 함수:
      Get-InstalledScoopId      설치된 Scoop 패키지 이름 집합
      Get-InstalledWingetId     설치된 winget 패키지 ID 집합
      Test-VsComponent          Visual Studio 구성 요소 설치 여부 (vswhere)
      Read-ScoopAppList         apps/scoop-apps.txt 를 그룹 정보와 함께 읽는다
      Read-WingetAppList        apps/winget-apps.json 을 읽는다
      Read-WingetOverrideList   apps/winget-overrides.json 을 읽는다
      Show-PackagePicker        선택 화면을 띄우고 선택된 항목을 돌려준다
#>

# ---------------------------------------------------------------------------
# 설치 상태 조회
# ---------------------------------------------------------------------------

function Get-InstalledScoopId {
    # 반환값 앞의 쉼표는 필수다. PowerShell 은 함수가 돌려주는 컬렉션을 자동으로 펼치므로,
    # 비어 있는 HashSet 을 그냥 return 하면 호출부에서 $null 이 된다.
    $result = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { return ,$result }
    try {
        # scoop list 는 Name 속성을 가진 객체를 반환한다.
        foreach ($entry in (scoop list 6>$null)) {
            if ($entry.Name) { [void]$result.Add([string]$entry.Name) }
        }
    }
    catch {
        Write-Verbose "scoop list 실패: $($_.Exception.Message)"
    }
    return ,$result
}

function Get-InstalledWingetId {
    $result = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return ,$result }

    # winget list 의 콘솔 출력은 폭에 따라 ID 가 잘리므로 export 결과(JSON)를 쓴다.
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("winget-installed-{0}.json" -f [Guid]::NewGuid())
    try {
        winget export -o $temp --accept-source-agreements 1>$null 2>$null
        if (Test-Path $temp) {
            # -Encoding UTF8 은 필수다. PowerShell 5.1 의 Get-Content 기본값은 ANSI(CP949)라
            # 한글이 섞인 JSON 을 읽으면 깨져서 ConvertFrom-Json 이 실패한다.
            $json = Get-Content $temp -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($source in $json.Sources) {
                foreach ($package in $source.Packages) {
                    if ($package.PackageIdentifier) { [void]$result.Add([string]$package.PackageIdentifier) }
                }
            }
        }
    }
    catch {
        Write-Verbose "winget export 실패: $($_.Exception.Message)"
    }
    finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }
    return ,$result
}

function Test-VsComponent {
    <#
    .SYNOPSIS
        Visual Studio(또는 Build Tools) 구성 요소가 실제로 설치되어 있는지 확인한다.

    .DESCRIPTION
        winget 은 Build Tools 를 '설치됨'으로 보고하지만, 그것은 설치 관리자만
        깔려 있어도 참이다. 컴파일러/링커가 실제로 있는지는 vswhere 로 확인해야 한다.
        vswhere 자체가 없으면(= Visual Studio 계열이 전혀 없음) 미설치로 본다.

    .PARAMETER ComponentId
        예: Microsoft.VisualStudio.Component.VC.Tools.x86.x64
    #>
    param([Parameter(Mandatory)][string]$ComponentId)

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }

    try {
        # -products * 를 줘야 Build Tools 처럼 IDE 가 아닌 제품도 검색 대상에 들어간다.
        $found = & $vswhere -products * -requires $ComponentId -property installationPath 2>$null
        return [bool](@($found | Where-Object { $_ -and $_.Trim() }).Count)
    }
    catch {
        Write-Verbose "vswhere 실행 실패: $($_.Exception.Message)"
        return $false
    }
}

function Get-VsInstallPath {
    <#
    .SYNOPSIS
        지정한 winget 패키지에 대응하는 Visual Studio 설치 경로를 돌려준다.
        이미 설치된 제품에 구성 요소만 추가할 때(vs_installer modify) 필요하다.
        찾지 못하면 $null.
    #>
    param([string]$ProductId = 'Microsoft.VisualStudio.Product.BuildTools')

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }

    try {
        $paths = & $vswhere -products $ProductId -property installationPath 2>$null
        return (@($paths | Where-Object { $_ -and $_.Trim() }) | Select-Object -First 1)
    }
    catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# 목록 파일 읽기
# ---------------------------------------------------------------------------

function Read-ScoopAppList {
    param([Parameter(Mandatory)][string]$Path)

    $items = @()
    $group = '기타'

    foreach ($raw in (Get-Content $Path -Encoding UTF8)) {
        $line = $raw.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith('#>')) { $group = $line.Substring(2).Trim(); continue }
        if ($line.StartsWith('#'))  { continue }

        $items += [pscustomobject]@{
            Manager = 'scoop'
            Id      = $line
            # 'bucket/package' 에서 실제 패키지 이름만 뽑아 설치 상태와 대조한다.
            Name    = $line.Split('/')[-1]
            Group   = $group
        }
    }
    return ,$items
}

function Read-WingetAppList {
    param([Parameter(Mandatory)][string]$Path)

    $items = @()
    $json  = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($source in $json.Sources) {
        foreach ($package in $source.Packages) {
            if (-not $package.PackageIdentifier) { continue }
            $items += [pscustomobject]@{
                Manager = 'winget'
                Id      = [string]$package.PackageIdentifier
                Name    = [string]$package.PackageIdentifier
                Group   = 'winget (관리자 권한 필요)'
            }
        }
    }
    return ,$items
}

function Read-WingetOverrideList {
    <#
    .SYNOPSIS
        apps/winget-overrides.json 을 읽는다. winget import 로는 제대로 설치되지 않아
        개별 install + --override 가 필요한 패키지 목록이다.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $items = @()
    $json  = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($package in $json.Packages) {
        if (-not $package.PackageIdentifier) { continue }
        $items += [pscustomobject]@{
            Manager           = 'winget-override'
            Id                = [string]$package.PackageIdentifier
            Name              = [string]$package.PackageIdentifier
            Group             = 'winget 개별 설치 (구성 요소 지정 필요)'
            Override          = [string]$package.Override
            RequiresComponent = [string]$package.RequiresComponent
            Reason            = [string]$package.Reason
        }
    }
    # 앞의 쉼표는 필수다. 항목이 하나뿐이면 PowerShell 이 배열을 스칼라로 펼쳐서
    # 호출부의 .Count 가 비게 된다. (override 목록은 보통 한 개다)
    return ,$items
}

function Test-WingetOverrideInstalled {
    <#
    .SYNOPSIS
        override 패키지가 '쓸 수 있는 상태로' 설치되었는지 판정한다.

    .DESCRIPTION
        RequiresComponent 가 지정된 패키지는 winget 이 설치됨으로 보고하더라도
        해당 구성 요소가 없으면 미설치로 본다. Build Tools 가 껍데기만 깔린 상태를
        걸러내기 위한 것으로, 이 판정이 이 스크립트의 핵심이다.
    #>
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$InstalledWinget
    )

    if ($Item.RequiresComponent) { return (Test-VsComponent -ComponentId $Item.RequiresComponent) }
    return $InstalledWinget.Contains($Item.Id)
}

# ---------------------------------------------------------------------------
# 선택 화면
# ---------------------------------------------------------------------------

function Write-PickerFrame {
    <#
    .SYNOPSIS
        선택 화면 한 프레임을 그린다. Show-PackagePicker 가 키 입력마다 호출한다.
        (단독으로 호출할 수 있도록 분리해 두어 렌더링만 따로 확인할 수 있다.)
    #>
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][int]$Cursor,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][int]$Viewport,
        [string]$Title = '설치할 항목을 선택하세요'
    )

    $labelWidth = 42
    $chosen = @($Rows | Where-Object { $_.Kind -eq 'item' -and $_.Selected }).Count
    $total  = @($Rows | Where-Object { $_.Kind -eq 'item' }).Count

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "  ↑↓ 이동   Space 선택/해제   A 전체   N 전체해제   Enter 확인   Esc 취소" -ForegroundColor DarkGray
    Write-Host ""

    $last = [Math]::Min($Rows.Count, $Offset + $Viewport)
    for ($i = $Offset; $i -lt $last; $i++) {
        $row = $Rows[$i]

        if ($row.Kind -eq 'header') {
            $bar = '─' * [Math]::Max(3, ($labelWidth + 2) - $row.Text.Length)
            Write-Host "  ── $($row.Text) $bar" -ForegroundColor Cyan
            continue
        }

        $isCursor = ($i -eq $Cursor)
        $marker   = if ($isCursor)     { '>' }   else { ' ' }
        $box      = if ($row.Selected) { '[x]' } else { '[ ]' }
        $color    = if ($isCursor)     { 'Yellow' } elseif ($row.Selected) { 'Green' } else { 'Gray' }

        # 긴 ID 가 줄바꿈되어 화면이 깨지지 않도록 잘라낸다.
        $label = [string]$row.Item.Name
        if ($label.Length -gt $labelWidth) { $label = $label.Substring(0, $labelWidth - 1) + '…' }

        Write-Host ("  {0} {1} {2}" -f $marker, $box, $label.PadRight($labelWidth)) -ForegroundColor $color -NoNewline
        if ($row.Item.Installed) {
            Write-Host "이미 설치됨" -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }
    }

    Write-Host ""
    if ($Offset -gt 0 -or $last -lt $Rows.Count) {
        Write-Host "  ($($Offset + 1)-$last / $($Rows.Count) 행 표시 중)" -ForegroundColor DarkGray
    }
    Write-Host "  선택됨 $chosen / $total" -ForegroundColor White
}

function Show-PackagePicker {
    <#
    .SYNOPSIS
        체크박스 선택 화면을 띄우고 선택된 항목만 돌려준다.

    .PARAMETER Items
        Manager / Id / Name / Group / Installed 속성을 가진 객체 배열.

    .OUTPUTS
        선택된 항목 배열. 사용자가 Esc 로 취소하면 $null.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [string]$Title = '설치할 항목을 선택하세요'
    )

    # 입력이 리다이렉트된 환경(자동화, 파이프)에서는 화면을 띄우지 않는다.
    if ([Console]::IsInputRedirected) {
        Write-Warning '대화형 입력을 쓸 수 없어 선택 화면을 건너뜁니다. 미설치 항목 전체를 선택합니다.'
        return @($Items | Where-Object { -not $_.Installed })
    }

    # 그룹 머리글과 항목을 한 줄씩 차지하는 평면 목록으로 만든다.
    $rows      = @()
    $lastGroup = $null
    foreach ($item in $Items) {
        if ($item.Group -ne $lastGroup) {
            $rows += [pscustomobject]@{ Kind = 'header'; Text = $item.Group; Item = $null }
            $lastGroup = $item.Group
        }
        # 이미 설치된 항목은 기본 해제 상태로 둔다.
        $rows += [pscustomobject]@{
            Kind     = 'item'
            Text     = $null
            Item     = $item
            Selected = (-not $item.Installed)
        }
    }

    $selectable = @(0..($rows.Count - 1) | Where-Object { $rows[$_].Kind -eq 'item' })
    if ($selectable.Count -eq 0) { return @() }

    $cursor = $selectable[0]
    $offset = 0

    while ($true) {
        $windowHeight = 25
        try { $windowHeight = $Host.UI.RawUI.WindowSize.Height } catch { }
        $viewport = [Math]::Max(5, $windowHeight - 8)

        if ($cursor -lt $offset)             { $offset = $cursor }
        if ($cursor -ge $offset + $viewport) { $offset = $cursor - $viewport + 1 }
        $maxOffset = [Math]::Max(0, $rows.Count - $viewport)
        if ($offset -gt $maxOffset) { $offset = $maxOffset }

        Clear-Host
        Write-PickerFrame -Rows $rows -Cursor $cursor -Offset $offset -Viewport $viewport -Title $Title

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'UpArrow' {
                $position = $selectable.IndexOf($cursor)
                if ($position -gt 0) { $cursor = $selectable[$position - 1] }
            }
            'DownArrow' {
                $position = $selectable.IndexOf($cursor)
                if ($position -lt $selectable.Count - 1) { $cursor = $selectable[$position + 1] }
            }
            'Home'   { $cursor = $selectable[0] }
            'End'    { $cursor = $selectable[-1] }
            'PageUp' {
                $position = [Math]::Max(0, $selectable.IndexOf($cursor) - $viewport)
                $cursor = $selectable[$position]
            }
            'PageDown' {
                $position = [Math]::Min($selectable.Count - 1, $selectable.IndexOf($cursor) + $viewport)
                $cursor = $selectable[$position]
            }
            'Spacebar' { $rows[$cursor].Selected = -not $rows[$cursor].Selected }
            'Enter'  {
                Clear-Host
                return @($rows | Where-Object { $_.Kind -eq 'item' -and $_.Selected } | ForEach-Object { $_.Item })
            }
            'Escape' { Clear-Host; return $null }
            default {
                switch ("$($key.KeyChar)".ToUpperInvariant()) {
                    'A' { foreach ($row in $rows) { if ($row.Kind -eq 'item') { $row.Selected = $true  } } }
                    'N' { foreach ($row in $rows) { if ($row.Kind -eq 'item') { $row.Selected = $false } } }
                    'Q' { Clear-Host; return $null }
                }
            }
        }
    }
}
