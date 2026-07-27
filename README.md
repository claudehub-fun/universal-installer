# ClaudeHub Installer

One-command setup for AI coding tools using your [ClaudeHub](https://claudehub.fun) API key.

Supports **Claude Code**, **Roo Code**, **Kilo Code**, **Cline**, **Codex CLI**, and **OpenRouter**.

## Install

**macOS / Linux**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/claudehub-fun/universal-installer/main/install.sh)
```

**Windows**
```powershell
irm https://raw.githubusercontent.com/claudehub-fun/universal-installer/main/install.ps1 | iex
```

The script will ask for your ClaudeHub API key, then let you pick which tool to install and configure it automatically.

## What it does

- Prompts for your API key (once)
- Asks which tool to install
- Installs and configures it to use ClaudeHub — no manual setup needed

## Run tests

**macOS / Linux**
```bash
bash test_install.sh
```

**Windows**
```powershell
pwsh -File test_install.ps1
```
