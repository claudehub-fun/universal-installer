# universal-installer

Installs and configures AI coding tools (Claude Code, Roo Code, Kilo Code, Cline, Codex CLI, OpenRouter) for a custom API endpoint.

## Quick start

**macOS / Linux**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/claudehub-fun/universal-installer/main/install.sh)
```

**Windows**
```powershell
irm https://raw.githubusercontent.com/claudehub-fun/universal-installer/main/install.ps1 | iex
```

The script will ask which tool to install, then configure it to use your API key and endpoint automatically.

> The template variables (`{{API_KEY}}`, `{{API_BASE_URL}}`) at the top of the script are replaced by the website before download. For manual use, edit them by hand.

## Run tests

**macOS / Linux**
```bash
bash test_install.sh
```

**Windows**
```powershell
pwsh -File test_install.ps1
```

Tests cover the pure functions (config validation, JSON writing, path helpers) without touching your system or installing anything.
