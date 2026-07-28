#Requires -Version 5.1
<#
.SYNOPSIS
    설치할 패키지를 콘솔에서 골라내는 체크박스 선택기.

.DESCRIPTION
    bootstrap.ps1 이 -Select 로 실행될 때 점 소싱(dot-source)해서 사용한다.
    외부 모듈에 의존하지 않고 [Console]::ReadKey 만 사용하므로
    Windows PowerShell 5.1 과 PowerShell 7 양쪽에서 동작한다.

    노출하는 함수:
      Get-InstalledScoopId    설치된 Scoop 패키지 이름 집합
      Get-InstalledWingetId   설치된 winget 패키지 ID 집합
      Read-ScoopAppList       apps/scoop-apps.txt 를 그룹 정보와 함께 읽는다
      Read-WingetAppList      apps/winget-apps.json 을 읽는다
      Show-PackagePicker      선택 화면을 띄우고 선택된 항목을 돌려준다
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
            $json = Get-Content $temp -Raw | ConvertFrom-Json
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
    return $items
}

function Read-WingetAppList {
    param([Parameter(Mandatory)][string]$Path)

    $items = @()
    $json  = Get-Content $Path -Raw | ConvertFrom-Json
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
    return $items
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
