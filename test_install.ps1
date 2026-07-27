# Tests for install.ps1 pure functions. Run: pwsh -File test_install.ps1
$ErrorActionPreference = "Stop"
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Pass = 0; $Fail = 0

function Assert-Eq {
    param([string]$Desc, $Got, $Want)
    if ($Got -eq $Want) {
        Write-Host "  PASS: $Desc"; $script:Pass++
    } else {
        Write-Host "  FAIL: $Desc — got='$Got' want='$Want'"; $script:Fail++
    }
}

# ── load pure functions without running Main ─────────────────────────────────
$src = Get-Content "$PSScriptRoot\install.ps1" -Raw
# Strip the final 'Main' call so we can dot-source safely
$src = $src -replace '(?m)^Main\s*$', ''
$ApiKey = "test-key"; $ApiBaseUrl = "https://api.example.com"; $ProviderName = "TestProvider"
Invoke-Expression $src

Write-Host "=== Get-Slug ==="
Assert-Eq "lowercase"           (Get-Slug "Hello World")  "helloworld"
Assert-Eq "strip special chars" (Get-Slug "Foo-Bar_99!")  "foobar99"
Assert-Eq "empty → custom"      (Get-Slug "")             "custom"
Assert-Eq "all non-alnum"       (Get-Slug "!@#`$%")       "custom"
Assert-Eq "already clean"       (Get-Slug "myprovider")   "myprovider"

Write-Host "=== Get-VSCodeUserSettingsPath ==="
$expected = Join-Path $env:APPDATA "Code\User\settings.json"
Assert-Eq "appdata path" (Get-VSCodeUserSettingsPath) $expected

Write-Host "=== Assert-Config ==="
$script:ApiKey = "sk-live-123"; $script:ApiBaseUrl = "https://x.com"; $script:ProviderName = "P"
Assert-Config
Assert-Eq "valid config passes" $true $true

$script:ApiKey = "{{API_KEY}}"; $script:ApiBaseUrl = "https://x.com"; $script:ProviderName = "P"
try { Assert-Config; Assert-Eq "template API_KEY fails" $false $true }
catch { Assert-Eq "template API_KEY fails" $true $true }

$script:ApiKey = "sk-live-123"; $script:ApiBaseUrl = "{{API_BASE_URL}}"; $script:ProviderName = "P"
try { Assert-Config; Assert-Eq "template API_BASE_URL fails" $false $true }
catch { Assert-Eq "template API_BASE_URL fails" $true $true }

$script:ApiKey = "sk-live-123"; $script:ApiBaseUrl = "https://x.com"; $script:ProviderName = "{{PROVIDER_NAME}}"
Assert-Config
Assert-Eq "template PROVIDER_NAME → ClaudeHub" $script:ProviderName "ClaudeHub"

Write-Host "=== Set-JsonValue / Read-JsonOrEmpty ==="
$tmp = [System.IO.Path]::GetTempFileName()
try {
    Set-JsonValue -Path $tmp -DottedKey "a.b.c" -Value "hello"
    $d = Read-JsonOrEmpty -Path $tmp
    Assert-Eq "nested write" $d.a.b.c "hello"

    Set-JsonValue -Path $tmp -DottedKey "a.b.d" -Value "world"
    $d = Read-JsonOrEmpty -Path $tmp
    Assert-Eq "sibling key preserved" $d.a.b.c "hello"
    Assert-Eq "new sibling written"   $d.a.b.d "world"

    Set-JsonValue -Path $tmp -DottedKey "a.b.c" -Value "updated"
    $d = Read-JsonOrEmpty -Path $tmp
    Assert-Eq "overwrite existing" $d.a.b.c "updated"
} finally {
    Remove-Item $tmp -Force
}

Write-Host "=== Set-Utf8NoBom (no BOM) ==="
$tmp2 = [System.IO.Path]::GetTempFileName()
try {
    Set-Utf8NoBom -Path $tmp2 -Content '{"x":1}'
    $bytes = [System.IO.File]::ReadAllBytes($tmp2)
    $noBom = -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-Eq "no BOM written" $noBom $true
} finally {
    Remove-Item $tmp2 -Force
}

# ── summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Results: $Pass passed, $Fail failed"
if ($Fail -gt 0) { exit 1 }
