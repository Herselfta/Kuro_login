$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    conda activate kuro_login
    python .\sms_send.py
    if ($LASTEXITCODE -ne 0) {
        throw "sms_send.py failed with exit code $LASTEXITCODE"
    }

    $loginDataPath = Join-Path $PSScriptRoot 'login_data.json'
    $yamlPath = 'D:\Qinglong\data\config\name.yaml'

    if (-not (Test-Path -LiteralPath $loginDataPath)) {
        throw "login_data.json not found at $loginDataPath"
    }
    if (-not (Test-Path -LiteralPath $yamlPath)) {
        throw "Target YAML not found at $yamlPath"
    }

    $loginData = Get-Content -LiteralPath $loginDataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($field in @('token', 'deviceCode', 'distinctId')) {
        if ([string]::IsNullOrWhiteSpace($loginData.$field)) {
            throw "Missing or empty '$field' in $loginDataPath"
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
            "$($Matches[1])devcode: $($loginData.deviceCode)"
        }
        elseif ($line -match '^(\s*)distinct_id:\s*.*$') {
            $updated.distinct_id = $true
            "$($Matches[1])distinct_id: $($loginData.distinctId)"
        }
        elseif ($line -match '^token:\s*.*$') {
            $updated.token = $true
            "token: $($loginData.token)"
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
