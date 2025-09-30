#!/usr/bin/env bash

# Chrome DevTools MCP setup helper
# - Verifies Node.js >= 22 and presence of Chrome/Chromium
# - Warms up npx download for chrome-devtools-mcp@latest
# - Optionally installs Node via nvm (opt-in flag)
# - Optionally creates a wrapper at ~/.local/bin/chrome-devtools-mcp
# - Prints a ready-to-paste MCP config snippet for clients (e.g., GitHub Copilot)
#
# Usage:
#   bash Bash/setup_mcp_devtools.sh [--yes] [--install-node] [--make-wrapper] [--write-copilot-config] [--write-vscode-config]
#
# Flags:
#   --yes                 Non-interactive; accept defaults
#   --install-node        If Node <22 or missing, install via nvm (user-local)
#   --make-wrapper        Create ~/.local/bin/chrome-devtools-mcp wrapper
#   --write-copilot-config Attempt to write a generic MCP config file alongside printing snippet
#   --write-vscode-config  Write a VS Code/Copilot mcp.json at ~/.config/Code/User/mcp.json (backs up existing)
#
# Notes:
# - This script avoids sudo unless you explicitly install Chrome yourself.
# - "chrome-devtools-mcp" runs via npx, using @latest as recommended.

set -Eeuo pipefail
IFS=$'\n\t'

YES=false
INSTALL_NODE=false
MAKE_WRAPPER=false
WRITE_COPILOT_CONFIG=false
WRITE_VSCODE_CONFIG=false

for arg in "$@"; do
	case "$arg" in
		--yes|-y) YES=true ;;
		--install-node) INSTALL_NODE=true ;;
		--make-wrapper) MAKE_WRAPPER=true ;;
		--write-copilot-config) WRITE_COPILOT_CONFIG=true ;;
		--write-vscode-config) WRITE_VSCODE_CONFIG=true ;;
		*) echo "Unknown option: $arg" >&2; exit 2 ;;
	esac
done

log() { printf "[setup-mcp] %s\n" "$*"; }
warn() { printf "[setup-mcp][WARN] %s\n" "$*" >&2; }
err() { printf "[setup-mcp][ERROR] %s\n" "$*" >&2; }

need_cmd() {
	command -v "$1" >/dev/null 2>&1
}

readlink_f() {
	# portable readlink -f
	local target=$1 dir file
	if [ -d "$target" ]; then
		(cd "$target" && pwd -P)
	else
		dir=$(dirname -- "$target")
		file=$(basename -- "$target")
		(cd "$dir" && echo "$(pwd -P)/$file")
	fi
}

ensure_node_22() {
	if need_cmd node; then
		local ver major
		ver=$(node -v 2>/dev/null || echo "v0.0.0")
		major=$(printf "%s" "$ver" | sed -E 's/^v([0-9]+).*/\1/')
		if [ -n "$major" ] && [ "$major" -ge 22 ]; then
			log "Node.js $ver detected (OK)"
			return 0
		fi
		warn "Node.js $ver detected; >=22 required."
	else
		warn "Node.js is not installed. >=22 required."
	fi

	if [ "$INSTALL_NODE" = true ]; then
		log "Installing Node.js 22 via nvm (user-local)..."
		if ! need_cmd curl; then
			err "curl is required to install nvm automatically. Install curl and re-run or install Node manually."
			return 1
		fi
		# Install nvm (idempotent)
		export PROFILE="${HOME}/.bashrc"
		export NVM_DIR="${HOME}/.nvm"
		if [ ! -d "$NVM_DIR" ]; then
			curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
		fi
		# shellcheck disable=SC1090
		[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
		nvm install 22
		nvm use 22
		log "Node $(node -v) installed."
	else
		err "Node.js >=22 is required. Re-run with --install-node to install locally via nvm, or install Node 22+ manually."
		return 1
	fi
}

detect_chrome() {
	# Try common Chrome/Chromium paths/commands
	local candidates=(
		google-chrome-stable
		google-chrome
		chromium
		chromium-browser
		chrome
	)
	local bin
	for c in "${candidates[@]}"; do
		if command -v "$c" >/dev/null 2>&1; then
			bin=$(command -v "$c")
			echo "$bin"
			return 0
		fi
	done
	# Also check common paths
	for p in \
		"/usr/bin/google-chrome-stable" \
		"/usr/bin/google-chrome" \
		"/usr/bin/chromium" \
		"/snap/bin/chromium" \
		"/opt/google/chrome/google-chrome"; do
		if [ -x "$p" ]; then
			echo "$p"
			return 0
		fi
	done
	return 1
}

ensure_chrome() {
	if CHROME_BIN=$(detect_chrome); then
		log "Chrome detected: $CHROME_BIN"
		export CHROME_PATH="$CHROME_BIN" # harmless if unused by the server
		return 0
	fi

	warn "Chrome/Chromium not found on PATH. The MCP server requires Chrome (stable or newer)."
	if [ "$YES" = true ]; then
		return 0
	fi
	printf "\nInstall Chrome manually and press Enter to continue (or Ctrl+C to abort)...";
	# shellcheck disable=SC2034
	read -r _
}

warmup_npx() {
	if ! need_cmd npx; then
		err "npx not found (it comes with Node)."
		return 1
	fi
	log "Warming up npx cache for chrome-devtools-mcp@latest (this may take a moment)..."
	# Use -y to skip prompts; --help to avoid launching Chrome
	if ! NPX_OUT=$(npx -y chrome-devtools-mcp@latest --help 2>&1 | head -n 5); then
		warn "npx warmup finished with warnings. Continuing."
	fi
	log "npx warmup done."
}

make_wrapper() {
	local bin_dir="$HOME/.local/bin"
	local wrapper="$bin_dir/chrome-devtools-mcp"
	mkdir -p "$bin_dir"
	cat >"$wrapper" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
# Wrapper to run Chrome DevTools MCP via npx with @latest
# You can set the following environment variables to pass optional flags without editing MCP config:
#   CHROME_DEVTOOLS_BROWSER_URL   -> --browserUrl <value>
#   CHROME_DEVTOOLS_HEADLESS      -> --headless <true|false>
#   CHROME_DEVTOOLS_EXECUTABLE    -> --executablePath <path>
#   CHROME_DEVTOOLS_ISOLATED      -> --isolated <true|false>
#   CHROME_DEVTOOLS_CHANNEL       -> --channel <stable|canary|beta|dev>

	resolve_npx() {
		# 1) Respect NPX_BIN if provided
		if [[ -n "${NPX_BIN:-}" && -x "${NPX_BIN}" ]]; then
			echo "${NPX_BIN}"; return 0
		fi
		# 2) Try PATH
		if command -v npx >/dev/null 2>&1; then
			command -v npx; return 0
		fi
		# 3) Try loading nvm and re-check PATH
		local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
		if [[ -s "$nvm_dir/nvm.sh" ]]; then
			# shellcheck disable=SC1090
			. "$nvm_dir/nvm.sh"
			if command -v npx >/dev/null 2>&1; then
				command -v npx; return 0
			fi
		fi
		# 4) Probe typical nvm paths (pick highest version)
		if [[ -d "$nvm_dir/versions/node" ]]; then
			local probe
			probe=$(ls -1d "$nvm_dir"/versions/node/v*/bin/npx 2>/dev/null | sort -V | tail -n1 || true)
			if [[ -n "$probe" && -x "$probe" ]]; then
				echo "$probe"; return 0
			fi
		fi
		# 5) Fallback to common system locations
		for p in /usr/bin/npx /usr/local/bin/npx; do
			if [[ -x "$p" ]]; then echo "$p"; return 0; fi
		done
		return 1
	}

	NPX_BIN_PATH=""
	if NPX_BIN_PATH=$(resolve_npx); then
		:
	else
		echo "[chrome-devtools-mcp wrapper] ERROR: Could not locate 'npx'. Ensure Node.js/npm is installed and set NPX_BIN to an absolute npx path." >&2
		exit 127
	fi

	# Ensure the directory containing npx (and node) is on PATH so shebangs using /usr/bin/env node resolve.
	NPX_DIR=$(dirname -- "$NPX_BIN_PATH")
	export PATH="$NPX_DIR:$PATH"

	args=("$NPX_BIN_PATH" -y chrome-devtools-mcp@latest)

if [[ -n "${CHROME_DEVTOOLS_BROWSER_URL:-}" ]]; then
	args+=(--browserUrl "${CHROME_DEVTOOLS_BROWSER_URL}")
fi
if [[ -n "${CHROME_DEVTOOLS_HEADLESS:-}" ]]; then
	args+=(--headless "${CHROME_DEVTOOLS_HEADLESS}")
fi
if [[ -n "${CHROME_DEVTOOLS_EXECUTABLE:-}" ]]; then
	args+=(--executablePath "${CHROME_DEVTOOLS_EXECUTABLE}")
fi
if [[ -n "${CHROME_DEVTOOLS_ISOLATED:-}" ]]; then
	args+=(--isolated "${CHROME_DEVTOOLS_ISOLATED}")
fi
if [[ -n "${CHROME_DEVTOOLS_CHANNEL:-}" ]]; then
	args+=(--channel "${CHROME_DEVTOOLS_CHANNEL}")
fi

exec "${args[@]}" "$@"
WRAP
	chmod +x "$wrapper"
	log "Wrapper created at: $wrapper"
	if ! printf "%s" ":$PATH:" | grep -q ":$bin_dir:"; then
		warn "~/.local/bin is not on PATH. Add this line to your shell profile and re-open your terminal:"
		echo "  export PATH=\"$bin_dir:\$PATH\""
	fi
}

write_copilot_config() {
	# There is no single canonical path yet; write a generic JSON file the user can point Copilot to.
	local cfg_dir="$HOME/.config/mcp"
	local cfg_file="$cfg_dir/chrome-devtools.json"
	mkdir -p "$cfg_dir"
	cat >"$cfg_file" <<'CFG'
{
	"mcpServers": {
		"chrome-devtools": {
			"command": "npx",
			"args": ["chrome-devtools-mcp@latest"]
		}
	}
}
CFG
	log "Wrote a generic MCP config file to: $cfg_file"
}

write_vscode_config() {
    # Write a VS Code Copilot-compatible MCP config that uses the wrapper to avoid PATH issues.
    # If an existing file is present, back it up with a timestamp.
    local cfg_dir="$HOME/.config/Code/User"
    local cfg_file="$cfg_dir/mcp.json"
    mkdir -p "$cfg_dir"
    if [ -f "$cfg_file" ]; then
        cp -f "$cfg_file" "$cfg_file.bak.$(date +%Y%m%d%H%M%S)"
        warn "Existing VS Code mcp.json backed up."
    fi
    cat >"$cfg_file" <<'CFG'
{
	"servers": {
		"chromedevtools/chrome-devtools-mcp": {
			"type": "stdio",
			"command": "chrome-devtools-mcp",
			"gallery": "https://api.mcp.github.com/v0/servers/13749964-2447-4c31-bcab-32731cced504",
			"version": "0.0.1-seed"
		}
	},
	"inputs": [
		{
			"id": "browser_url",
			"type": "promptString",
			"description": "Optional: connect to an already-running Chrome (remote debugging / port-forward). Example: http://127.0.0.1:9222",
			"password": false
		},
		{
			"id": "headless",
			"type": "promptString",
			"description": "Run Chrome headless (true/false). Default: false",
			"password": false
		},
		{
			"id": "chrome_executable_path",
			"type": "promptString",
			"description": "Path to a specific Chrome/Chromium binary.",
			"password": false
		},
		{
			"id": "isolated",
			"type": "promptString",
			"description": "Use a temporary user-data-dir (true/false). Default: false",
			"password": false
		},
		{
			"id": "chrome_channel",
			"type": "promptString",
			"description": "Chrome channel: stable | canary | beta | dev (default: stable).",
			"password": false
		}
	]
}
CFG
	log "Wrote VS Code MCP config to: $cfg_file"
	warn "Config uses wrapper 'chrome-devtools-mcp' to avoid PATH issues. To pass flags, set wrapper env vars (see script output)."
}

print_snippet() {
	cat <<'JSON'

Add this MCP server entry to your AI tool's configuration (e.g., Copilot):

{
	"mcpServers": {
		"chrome-devtools": {
			"command": "npx",
			"args": ["chrome-devtools-mcp@latest"]
		}
	}
}

Alternatively, if you created the wrapper (recommended for stability), use:

{
	"mcpServers": {
		"chrome-devtools": {
			"command": "chrome-devtools-mcp"
		}
	}
}

Wrapper advanced usage (set env vars before starting your client):
	export CHROME_DEVTOOLS_BROWSER_URL="http://127.0.0.1:9222"
	export CHROME_DEVTOOLS_HEADLESS="false"
	export CHROME_DEVTOOLS_EXECUTABLE="/usr/bin/google-chrome"
	export CHROME_DEVTOOLS_ISOLATED="false"
	export CHROME_DEVTOOLS_CHANNEL="stable"
JSON
}

main() {
	log "Starting Chrome DevTools MCP setup..."
	ensure_node_22
	ensure_chrome || true
	warmup_npx
	if [ "$MAKE_WRAPPER" = true ]; then
		make_wrapper
	fi
	if [ "$WRITE_COPILOT_CONFIG" = true ]; then
		write_copilot_config
	fi
		if [ "$WRITE_VSCODE_CONFIG" = true ]; then
			write_vscode_config
		fi
	print_snippet
	log "Done."
}

main "$@"

