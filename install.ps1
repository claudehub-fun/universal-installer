# ClaudeHub installer — sets up AI coding tools with your ClaudeHub API key.
# Run with: irm https://raw.githubusercontent.com/claudehub-fun/universal-installer/main/install.ps1 | iex
$ErrorActionPreference = "Stop"
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ApiKey = ""
$ApiBaseUrl = "https://api.claudehub.fun"
$ProviderName = "ClaudeHub"

# Writes text as UTF-8 *without* a BOM. PowerShell 5.1's built-in
# "-Encoding utf8" always adds a BOM, which breaks tools whose JSON.parse
# doesn't strip it (this is what broke Roo Code's auto-import before).
function Set-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Assert-Config {
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $script:ApiKey = Read-Host "Enter your ClaudeHub API key"
        if ([string]::IsNullOrWhiteSpace($script:ApiKey)) { Write-Error "API key cannot be empty."; exit 1 }
    }
}

# Lowercase alnum-only id, safe as a JSON object key / provider id.
function Get-Slug {
    param([string]$Value)
    $s = ($Value.ToLower() -replace '[^a-z0-9]', '')
    if ([string]::IsNullOrEmpty($s)) { return "custom" }
    return $s
}

# Loads a JSON file as a PSCustomObject tree (works on PowerShell 5.1,
# unlike "ConvertFrom-Json -AsHashtable" which is 6.0+ only and was
# silently failing here -- swallowed by the catch below -- and wiping
# out the user's existing config on every run instead of merging into it).
function Read-JsonOrEmpty {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            $raw = Get-Content $Path -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) { return New-Object PSObject }
            $parsed = $raw | ConvertFrom-Json
            if ($null -eq $parsed) { return New-Object PSObject }
            return $parsed
        } catch {
            return New-Object PSObject
        }
    }
    return New-Object PSObject
}

# Walks/creates a dotted path of nested PSCustomObjects and sets the leaf.
function Set-JsonPath {
    param($Root, [string[]]$Keys, $Value)
    $node = $Root
    for ($i = 0; $i -lt $Keys.Length - 1; $i++) {
        $k = $Keys[$i]
        $prop = $node.PSObject.Properties[$k]
        if (-not $prop -or -not ($prop.Value -is [System.Management.Automation.PSCustomObject])) {
            $child = New-Object PSObject
            $node | Add-Member -MemberType NoteProperty -Name $k -Value $child -Force
            $node = $child
        } else {
            $node = $prop.Value
        }
    }
    $lastKey = $Keys[-1]
    $node | Add-Member -MemberType NoteProperty -Name $lastKey -Value $Value -Force
}

# Sets a dotted-path value inside a JSON file, creating/merging as needed.
function Set-JsonValue {
    param(
        [string]$Path,
        [string]$DottedKey,
        [string]$Value
    )
    $root = Read-JsonOrEmpty -Path $Path
    Set-JsonPath -Root $root -Keys ($DottedKey -split '\.') -Value $Value
    Set-Utf8NoBom -Path $Path -Content ($root | ConvertTo-Json -Depth 20)
}

# Merges a hashtable *object* value (not a plain string) at a dotted path,
# preserving whatever else already lives in the file.
function Merge-JsonObject {
    param(
        [string]$Path,
        [string]$DottedKey,
        [hashtable]$Value
    )
    $root = Read-JsonOrEmpty -Path $Path
    Set-JsonPath -Root $root -Keys ($DottedKey -split '\.') -Value $Value
    Set-Utf8NoBom -Path $Path -Content ($root | ConvertTo-Json -Depth 20)
}

function Get-VSCodeUserSettingsPath {
    return Join-Path $env:APPDATA "Code\User\settings.json"
}

function Install-VSCodeExtension {
    param([string]$ExtensionId)
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Error "VS Code 'code' CLI not found in PATH. Install VS Code (and 'code' command), then re-run."
        exit 1
    }
    & code --install-extension $ExtensionId --force
}

# ---------------------------------------------------------------------
# 1) Claude Code
# ---------------------------------------------------------------------
function Install-ClaudeCode {
    Write-Host "Installing Claude Code..."
    irm https://claude.ai/install.ps1 | iex

    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    Set-JsonValue -Path $settingsPath -DottedKey "env.ANTHROPIC_BASE_URL" -Value $ApiBaseUrl
    Set-JsonValue -Path $settingsPath -DottedKey "env.ANTHROPIC_AUTH_TOKEN" -Value $ApiKey

    Write-Host ""
    Write-Host "Claude Code installed and configured ($settingsPath)."
    Write-Host ""
    Write-Host "How to connect / Как подключиться:"
    Write-Host "  EN: Open a new terminal and run 'claude'. It will use $ProviderName automatically."
    Write-Host "  RU: Откройте новый терминал и запустите 'claude'. $ProviderName подключится автоматически."
}

# ---------------------------------------------------------------------
# 2) Roo Code
# ---------------------------------------------------------------------
$RooExtId = "RooVeterinaryInc.roo-cline"
$KiloExtId = "kilocode.kilo-code"
$ClineExtId = "saoudrizwan.claude-dev"

function Write-RooStyleConfig {
    param([string]$ImportFile, [string]$SettingKey, [string]$ProfileName)

    $configObj = [ordered]@{
        providerProfiles = [ordered]@{
            currentApiConfigName = $ProfileName
            apiConfigs = @{
                $ProfileName = [ordered]@{
                    apiProvider   = "openai"
                    openAiBaseUrl = $ApiBaseUrl
                    openAiApiKey  = $ApiKey
                    openAiModelId = "claude-opus-4-8"
                }
            }
        }
        globalSettings = @{}
    }
    Set-Utf8NoBom -Path $ImportFile -Content ($configObj | ConvertTo-Json -Depth 10)

    $vscodeSettings = Get-VSCodeUserSettingsPath
    Set-JsonValue -Path $vscodeSettings -DottedKey $SettingKey -Value $ImportFile
}

function Install-RooCode {
    Write-Host "Installing Roo Code..."
    Install-VSCodeExtension -ExtensionId $RooExtId
    $importFile = Join-Path $env:USERPROFILE ".roo-code\auto-import-settings.json"
    Write-RooStyleConfig -ImportFile $importFile -SettingKey "roo-cline.autoImportSettingsPath" -ProfileName $ProviderName
    Write-Host ""
    Write-Host "Roo Code installed. Config will auto-import on next VS Code launch."
    Write-Host ""
    Write-Host "How to connect / Как подключиться:"
    Write-Host "  EN: 1. Open VS Code. 2. Open the Roo Code panel. 3. Provider profile '$ProviderName' is already selected and ready to use."
    Write-Host "  RU: 1. Откройте VS Code. 2. Откройте панель Roo Code. 3. Профиль провайдера '$ProviderName' уже выбран и готов к работе."
}

# ---------------------------------------------------------------------
# 3) Kilo Code
# Kilo (7.x, opencode-based) does NOT use autoImportSettingsPath anymore
# -- it reads %USERPROFILE%\.config\kilo\kilo.jsonc directly on every
# launch, so we write the custom provider straight into that file.
# ---------------------------------------------------------------------
function Install-KiloCode {
    Write-Host "Installing Kilo Code..."
    Install-VSCodeExtension -ExtensionId $KiloExtId

    $slug = Get-Slug -Value $ProviderName
    $configPath = Join-Path $env:USERPROFILE ".config\kilo\kilo.jsonc"
    $providerObj = [ordered]@{
        name = $ProviderName
        npm  = "@ai-sdk/anthropic"
        options = [ordered]@{
            baseURL = $ApiBaseUrl
            apiKey  = $ApiKey
        }
    }
    Merge-JsonObject -Path $configPath -DottedKey "provider.$slug" -Value $providerObj

    Write-Host ""
    Write-Host "Kilo Code installed and configured ($configPath)."
    Write-Host ""
    Write-Host "How to connect / Как подключиться:"
    Write-Host "  EN: 1. Open VS Code. 2. Open the Kilo Code panel. 3. Pick '$ProviderName' as the provider (already added for you)."
    Write-Host "  RU: 1. Откройте VS Code. 2. Откройте панель Kilo Code. 3. Выберите провайдера '$ProviderName' (он уже добавлен)."
}

# ---------------------------------------------------------------------
# 4) Cline
# ---------------------------------------------------------------------
function Install-Cline {
    Write-Host "Installing Cline..."
    Install-VSCodeExtension -ExtensionId $ClineExtId
    Write-Host ""
    Write-Host "Cline installed."
    Write-Host ""
    Write-Host "How to connect / Как подключиться:"
    Write-Host "  EN: Cline stores API keys in VS Code's encrypted storage, so it can't be"
    Write-Host "      pre-filled by a script. Do this once:"
    Write-Host "        1. Open VS Code."
    Write-Host "        2. Open the Cline panel (icon in the sidebar)."
    Write-Host "        3. Click the settings (gear) icon."
    Write-Host "        4. API Provider: choose 'OpenAI Compatible'."
    Write-Host "        5. Base URL: $ApiBaseUrl"
    Write-Host "        6. API Key: $ApiKey"
    Write-Host "        7. Save."
    Write-Host "  RU: Cline хранит API-ключи в зашифрованном хранилище VS Code, поэтому"
    Write-Host "      скрипт не может подставить их автоматически. Сделайте один раз:"
    Write-Host "        1. Откройте VS Code."
    Write-Host "        2. Откройте панель Cline (иконка в боковой панели)."
    Write-Host "        3. Нажмите на значок настроек (шестерёнка)."
    Write-Host "        4. API Provider: выберите 'OpenAI Compatible'."
    Write-Host "        5. Base URL: $ApiBaseUrl"
    Write-Host "        6. API Key: $ApiKey"
    Write-Host "        7. Сохраните."
}

# ---------------------------------------------------------------------
# 5) OpenAI Codex CLI
# ---------------------------------------------------------------------
function Install-Codex {
    Write-Host "Installing Codex CLI..."
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Error "npm not found. Install Node.js (npm) and re-run."
        exit 1
    }
    npm install -g @openai/codex

    $codexHome = $env:CODEX_HOME
    if ([string]::IsNullOrWhiteSpace($codexHome)) { $codexHome = Join-Path $env:USERPROFILE ".codex" }
    if (-not (Test-Path $codexHome)) { New-Item -ItemType Directory -Path $codexHome -Force | Out-Null }

    $configPath = Join-Path $codexHome "config.toml"
    $toml = @"
model_provider = "custom"

[model_providers.custom]
name = "$ProviderName"
base_url = "$ApiBaseUrl"
experimental_bearer_token = "$ApiKey"
wire_api = "responses"
"@
    Set-Utf8NoBom -Path $configPath -Content $toml

    Write-Host ""
    Write-Host "Codex CLI installed and configured ($configPath)."
    Write-Host ""
    Write-Host "How to connect / Как подключиться:"
    Write-Host "  EN: Open a new terminal and run 'codex'. It will use $ProviderName automatically."
    Write-Host "  RU: Откройте новый терминал и запустите 'codex'. $ProviderName подключится автоматически."
}

# ---------------------------------------------------------------------
# 6) OpenRouter (env vars only, for any OpenAI-compatible CLI tool)
# ---------------------------------------------------------------------
function Setup-OpenRouter {
    Write-Host "Setting OpenRouter environment variables (User scope)..."
    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $ApiKey, "User")
    [Environment]::SetEnvironmentVariable("OPENAI_BASE_URL", $ApiBaseUrl, "User")
    [Environment]::SetEnvironmentVariable("OPENROUTER_API_KEY", $ApiKey, "User")
    Write-Host ""
    Write-Host "How to connect / Как подключиться:"
    Write-Host "  EN: Open a new terminal so the variables load, then point any"
    Write-Host "      OpenAI-compatible CLI tool at them."
    Write-Host "  RU: Откройте новый терминал, чтобы переменные подхватились,"
    Write-Host "      затем используйте их в любом OpenAI-совместимом CLI-инструменте."
}

function Main {
    Assert-Config
    Write-Host "Select what to install:"
    Write-Host "  1) Claude Code"
    Write-Host "  2) Roo Code"
    Write-Host "  3) Kilo Code"
    Write-Host "  4) Cline"
    Write-Host "  5) Codex CLI"
    Write-Host "  6) OpenRouter (env vars only)"
    $choice = Read-Host "Enter a number (1-6)"

    switch ($choice) {
        "1" { Install-ClaudeCode }
        "2" { Install-RooCode }
        "3" { Install-KiloCode }
        "4" { Install-Cline }
        "5" { Install-Codex }
        "6" { Setup-OpenRouter }
        default { Write-Error "Invalid choice, pick a number 1-6." }
    }
}

Main
