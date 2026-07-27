#!/usr/bin/env bash
# ClaudeHub installer — sets up AI coding tools with your ClaudeHub API key.
# Run with: bash <(curl -fsSL https://raw.githubusercontent.com/claudehub-fun/universal-installer/main/install.sh)
set -euo pipefail

API_KEY=""
API_BASE_URL="https://api.claudehub.fun"
PROVIDER_NAME="ClaudeHub"

require_config() {
  local tty="${INSTALLER_TTY:-/dev/tty}"
  if [[ -z "$API_KEY" ]]; then
    read -rp "Enter your ClaudeHub API key: " API_KEY <"$tty"
    [[ -z "$API_KEY" ]] && { echo "Error: API key cannot be empty." >&2; exit 1; }
  fi
}

# Lowercase alnum-only id, safe as a JSON object key / provider id.
slugify() {
  local s
  s="$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  [[ -z "$s" ]] && s="custom"
  echo "$s"
}

# Sets a dotted-path value inside a JSON file, creating/merging as needed.
# Values are passed as argv to node/python so no shell-side JSON escaping
# is needed (safe for keys/URLs containing quotes, backslashes, etc).
set_json_value() {
  local file="$1" path="$2" value="$3"
  mkdir -p "$(dirname "$file")"
  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const [, file, path, value] = process.argv;
      let cur = {};
      try { cur = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) {}
      const keys = path.split(".");
      let obj = cur;
      for (let i = 0; i < keys.length - 1; i++) {
        const k = keys[i];
        if (typeof obj[k] !== "object" || obj[k] === null || Array.isArray(obj[k])) obj[k] = {};
        obj = obj[k];
      }
      obj[keys[keys.length - 1]] = value;
      fs.writeFileSync(file, JSON.stringify(cur, null, 2) + "\n");
    ' "$file" "$path" "$value"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
file, path, value = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(file) as f:
        cur = json.load(f)
except Exception:
    cur = {}
keys = path.split(".")
obj = cur
for k in keys[:-1]:
    if not isinstance(obj.get(k), dict):
        obj[k] = {}
    obj = obj[k]
obj[keys[-1]] = value
with open(file, "w") as f:
    json.dump(cur, f, indent=2)
    f.write("\n")
' "$file" "$path" "$value"
  else
    echo "Error: this step needs node or python3 installed. Install one and re-run." >&2
    exit 1
  fi
}

vscode_user_settings_path() {
  case "$(uname -s)" in
    Darwin) echo "$HOME/Library/Application Support/Code/User/settings.json" ;;
    *) echo "$HOME/.config/Code/User/settings.json" ;;
  esac
}

shell_rc_file() {
  case "${SHELL:-}" in
    */zsh) echo "$HOME/.zshrc" ;;
    *) echo "$HOME/.bashrc" ;;
  esac
}

append_env_exports() {
  local rc; rc="$(shell_rc_file)"
  {
    echo ""
    echo "# Added by universal-installer on $(date '+%Y-%m-%d')"
    for pair in "$@"; do
      echo "export $pair"
    done
  } >> "$rc"
  echo "Environment variables appended to $rc (run 'source $rc' or open a new terminal)."
}

install_vscode_extension() {
  local ext_id="$1"
  if ! command -v code >/dev/null 2>&1; then
    echo "Error: VS Code 'code' CLI not found in PATH. Install VS Code and enable the 'code' command, then re-run." >&2
    exit 1
  fi
  code --install-extension "$ext_id" --force
}

# ---------------------------------------------------------------------
# 1) Claude Code
# ---------------------------------------------------------------------
install_claude_code() {
  echo "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash

  local settings="$HOME/.claude/settings.json"
  set_json_value "$settings" "env.ANTHROPIC_BASE_URL" "$API_BASE_URL"
  set_json_value "$settings" "env.ANTHROPIC_AUTH_TOKEN" "$API_KEY"

  echo ""
  echo "Claude Code installed and configured ($settings)."
  echo ""
  echo "How to connect / Как подключиться:"
  echo "  EN: Open a new terminal and run 'claude'. It will use $PROVIDER_NAME automatically."
  echo "  RU: Откройте новый терминал и запустите 'claude'. $PROVIDER_NAME подключится автоматически."
}

# ---------------------------------------------------------------------
# 2) Roo Code
# ---------------------------------------------------------------------
ROO_EXT_ID="RooVeterinaryInc.roo-cline"
KILO_EXT_ID="kilocode.kilo-code"
CLINE_EXT_ID="saoudrizwan.claude-dev"

write_roo_style_config() {
  # $1 = import file path, $2 = vscode setting key for autoImportSettingsPath, $3 = profile display name
  local import_file="$1" setting_key="$2" profile_name="$3"
  mkdir -p "$(dirname "$import_file")"
  # No BOM, no trailing CRLF quirks: printf avoids the encoding issues that
  # broke Roo's JSON.parse before.
  printf '%s' "{
  \"providerProfiles\": {
    \"currentApiConfigName\": \"$profile_name\",
    \"apiConfigs\": {
      \"$profile_name\": {
        \"apiProvider\": \"openai\",
        \"openAiBaseUrl\": \"$API_BASE_URL\",
        \"openAiApiKey\": \"$API_KEY\",
        \"openAiModelId\": \"claude-opus-4-8\"
      }
    }
  },
  \"globalSettings\": {}
}
" > "$import_file"
  local vscode_settings; vscode_settings="$(vscode_user_settings_path)"
  set_json_value "$vscode_settings" "$setting_key" "$import_file"
}

install_roo_code() {
  echo "Installing Roo Code..."
  install_vscode_extension "$ROO_EXT_ID"
  write_roo_style_config "$HOME/.roo-code/auto-import-settings.json" "roo-cline.autoImportSettingsPath" "$PROVIDER_NAME"
  echo ""
  echo "Roo Code installed. Config will auto-import on next VS Code launch."
  echo ""
  echo "How to connect / Как подключиться:"
  echo "  EN: 1. Open VS Code. 2. Open the Roo Code panel. 3. Provider profile '$PROVIDER_NAME' is already selected and ready to use."
  echo "  RU: 1. Откройте VS Code. 2. Откройте панель Roo Code. 3. Профиль провайдера '$PROVIDER_NAME' уже выбран и готов к работе."
}

# ---------------------------------------------------------------------
# 3) Kilo Code
# Kilo (7.x, opencode-based) does NOT use autoImportSettingsPath anymore
# -- it reads ~/.config/kilo/kilo.jsonc directly on every launch, so we
# write the custom provider straight into that file.
# ---------------------------------------------------------------------
merge_json_object() {
  # Merges a JSON *object* value (not a plain string) at a dotted path.
  local file="$1" path="$2" json_value="$3"
  mkdir -p "$(dirname "$file")"
  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const [, file, path, jsonValue] = process.argv;
      let cur = {};
      try { cur = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) {}
      const value = JSON.parse(jsonValue);
      const keys = path.split(".");
      let obj = cur;
      for (let i = 0; i < keys.length - 1; i++) {
        const k = keys[i];
        if (typeof obj[k] !== "object" || obj[k] === null || Array.isArray(obj[k])) obj[k] = {};
        obj = obj[k];
      }
      obj[keys[keys.length - 1]] = value;
      fs.writeFileSync(file, JSON.stringify(cur, null, 2) + "\n");
    ' "$file" "$path" "$json_value"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
file, path, json_value = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(file) as f:
        cur = json.load(f)
except Exception:
    cur = {}
value = json.loads(json_value)
keys = path.split(".")
obj = cur
for k in keys[:-1]:
    if not isinstance(obj.get(k), dict):
        obj[k] = {}
    obj = obj[k]
obj[keys[-1]] = value
with open(file, "w") as f:
    json.dump(cur, f, indent=2)
    f.write("\n")
' "$file" "$path" "$json_value"
  else
    echo "Error: this step needs node or python3 installed. Install one and re-run." >&2
    exit 1
  fi
}

install_kilo_code() {
  echo "Installing Kilo Code..."
  install_vscode_extension "$KILO_EXT_ID"

  local slug; slug="$(slugify "$PROVIDER_NAME")"
  local config_path="$HOME/.config/kilo/kilo.jsonc"
  local provider_json="{\"name\":\"$PROVIDER_NAME\",\"npm\":\"@ai-sdk/anthropic\",\"options\":{\"baseURL\":\"$API_BASE_URL\",\"apiKey\":\"$API_KEY\"}}"
  merge_json_object "$config_path" "provider.$slug" "$provider_json"

  echo ""
  echo "Kilo Code installed and configured ($config_path)."
  echo ""
  echo "How to connect / Как подключиться:"
  echo "  EN: 1. Open VS Code. 2. Open the Kilo Code panel. 3. Pick '$PROVIDER_NAME' as the provider (already added for you)."
  echo "  RU: 1. Откройте VS Code. 2. Откройте панель Kilo Code. 3. Выберите провайдера '$PROVIDER_NAME' (он уже добавлен)."
}

# ---------------------------------------------------------------------
# 4) Cline
# ---------------------------------------------------------------------
install_cline() {
  echo "Installing Cline..."
  install_vscode_extension "$CLINE_EXT_ID"
  echo ""
  echo "Cline installed."
  echo ""
  echo "How to connect / Как подключиться:"
  echo "  EN: Cline stores API keys in VS Code's encrypted storage, so it can't be"
  echo "      pre-filled by a script. Do this once:"
  echo "        1. Open VS Code."
  echo "        2. Open the Cline panel (icon in the sidebar)."
  echo "        3. Click the settings (gear) icon."
  echo "        4. API Provider: choose 'OpenAI Compatible'."
  echo "        5. Base URL: $API_BASE_URL"
  echo "        6. API Key: $API_KEY"
  echo "        7. Save."
  echo "  RU: Cline хранит API-ключи в зашифрованном хранилище VS Code, поэтому"
  echo "      скрипт не может подставить их автоматически. Сделайте один раз:"
  echo "        1. Откройте VS Code."
  echo "        2. Откройте панель Cline (иконка в боковой панели)."
  echo "        3. Нажмите на значок настроек (шестерёнка)."
  echo "        4. API Provider: выберите 'OpenAI Compatible'."
  echo "        5. Base URL: $API_BASE_URL"
  echo "        6. API Key: $API_KEY"
  echo "        7. Сохраните."
}

# ---------------------------------------------------------------------
# 5) OpenAI Codex CLI
# ---------------------------------------------------------------------
install_codex() {
  echo "Installing Codex CLI..."
  if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm not found. Install Node.js (npm) and re-run." >&2
    exit 1
  fi
  npm install -g @openai/codex

  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  mkdir -p "$codex_home"
  cat > "$codex_home/config.toml" <<EOF
model_provider = "custom"

[model_providers.custom]
name = "$PROVIDER_NAME"
base_url = "$API_BASE_URL"
experimental_bearer_token = "$API_KEY"
wire_api = "responses"
EOF

  echo ""
  echo "Codex CLI installed and configured ($codex_home/config.toml)."
  echo ""
  echo "How to connect / Как подключиться:"
  echo "  EN: Open a new terminal and run 'codex'. It will use $PROVIDER_NAME automatically."
  echo "  RU: Откройте новый терминал и запустите 'codex'. $PROVIDER_NAME подключится автоматически."
}

# ---------------------------------------------------------------------
# 6) OpenRouter (env vars only, for any OpenAI-compatible CLI tool)
# ---------------------------------------------------------------------
setup_openrouter() {
  echo "Setting OpenRouter environment variables..."
  append_env_exports \
    "OPENAI_API_KEY=$API_KEY" \
    "OPENAI_BASE_URL=$API_BASE_URL" \
    "OPENROUTER_API_KEY=$API_KEY"
  echo ""
  echo "How to connect / Как подключиться:"
  echo "  EN: Open a new terminal (or run 'source ~/.bashrc' / '~/.zshrc') so the"
  echo "      variables load, then point any OpenAI-compatible CLI tool at them."
  echo "  RU: Откройте новый терминал (или выполните 'source ~/.bashrc' / '~/.zshrc'),"
  echo "      чтобы переменные подхватились, затем используйте их в любом"
  echo "      OpenAI-совместимом CLI-инструменте."
}

main() {
  require_config
  local tty="${INSTALLER_TTY:-/dev/tty}"
  echo "Select what to install:"
  select choice in "Claude Code" "Roo Code" "Kilo Code" "Cline" "Codex CLI" "OpenRouter (env vars only)"; do
    case "$choice" in
      "Claude Code") install_claude_code; break ;;
      "Roo Code") install_roo_code; break ;;
      "Kilo Code") install_kilo_code; break ;;
      "Cline") install_cline; break ;;
      "Codex CLI") install_codex; break ;;
      "OpenRouter (env vars only)") setup_openrouter; break ;;
      *) echo "Invalid choice, pick a number 1-6." ;;
    esac
  done <"$tty"
}

main "$@"
