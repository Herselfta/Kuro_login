$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    $loginInfoPath = Join-Path $PSScriptRoot 'login_info.json'
    $yamlPath = 'D:\Qinglong\data\config\name.yaml'

    $prevWriteTime = if (Test-Path -LiteralPath $loginInfoPath) {
        (Get-Item -LiteralPath $loginInfoPath).LastWriteTimeUtc
    } else {
        $null
    }

    uv run .\auto_login.py
    if ($LASTEXITCODE -ne 0) {
        throw "auto_login.py failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path -LiteralPath $loginInfoPath)) {
        throw "login_info.json not found at $loginInfoPath (login may have failed)."
    }

    $newWriteTime = (Get-Item -LiteralPath $loginInfoPath).LastWriteTimeUtc
    if ($null -ne $prevWriteTime -and $newWriteTime -le $prevWriteTime) {
        throw "login_info.json was not updated during this run (login may have failed). Skipping name.yaml update."
    }

    if (-not (Test-Path -LiteralPath $yamlPath)) {
        throw "Target YAML not found at $yamlPath"
    }

    $loginInfo = Get-Content -LiteralPath $loginInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($field in @('token', 'device_id', 'distinct_id')) {
        if ([string]::IsNullOrWhiteSpace($loginInfo.$field)) {
            throw "Missing or empty '$field' in $loginInfoPath"
        }
    }

    $yamlRaw = [System.IO.File]::ReadAllText($yamlPath, [System.Text.UTF8Encoding]::new($false))
    $newline = if ($yamlRaw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $hasTrailingNewline = $yamlRaw.EndsWith($newline)

    $lines = $yamlRaw -split "\r?\n"
    if ($hasTrailingNewline -and $lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = $lines[0..($lines.Count - 2)]
    }

    $updated = @{
        token       = $false
        devcode     = $false
        distinct_id = $false
    }

    $newLines = foreach ($line in $lines) {
        if ($line -match '^(\s*)devcode:\s*.*$') {
            $updated.devcode = $true
            "$($Matches[1])devcode: $($loginInfo.device_id)"
        }
        elseif ($line -match '^(\s*)distinct_id:\s*.*$') {
            $updated.distinct_id = $true
            "$($Matches[1])distinct_id: $($loginInfo.distinct_id)"
        }
        elseif ($line -match '^token:\s*.*$') {
            $updated.token = $true
            "token: $($loginInfo.token)"
        }
        else {
            $line
        }
    }

    $missingKeys = $updated.Keys | Where-Object { -not $updated[$_] }
    if ($missingKeys) {
        throw "Failed to find key(s) in ${yamlPath}: $($missingKeys -join ', ')"
    }

    $result = ($newLines -join $newline) + $(if ($hasTrailingNewline) { $newline } else { '' })
    [System.IO.File]::WriteAllText($yamlPath, $result, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Updated $yamlPath (token, devcode, distinct_id)." -ForegroundColor Green
}
finally {
    Pop-Location
}
