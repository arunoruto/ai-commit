#!/usr/bin/env bash
#
# AI-Powered Git Commit Message Generator
#
# This script uses AI to generate conventional commit messages based on staged git changes.
# It supports multiple AI providers (Ollama, OpenCode, Copilot, Gemini) and
# offers a user-friendly interface for selecting providers and models.
#
# Website: https://github.com/mar-mot/ai-commits
#
# Usage: ./ai-commit.sh [options]
#

set -eo pipefail

# ==========================================
# 0. CONFIGURATION & DEFAULTS
# ==========================================

# -- Behavior Settings --
BRIEF_MODE="false"
EMOJI_MODE="false"
DIFF_LIMIT=0
VERBOSE="false"

# -- Files to Ignore (can be overridden by config) --
IGNORED_PATTERNS=(
	"*.lock"
	"**/package-lock.json"
	"**/yarn.lock"
	"**/pnpm-lock.yaml"
	"**/go.sum"
	"**/devenv.lock"
	"**/devenv.yaml"
	"*.svg"
	"*.min.js"
	"*.map"
)

# -- Defaults (can be overridden by config) --
DEFAULT_PROVIDER=""
DEFAULT_OLLAMA_MODEL="llama3"
DEFAULT_OPENCODE_MODEL=""

# -- Globals --
CLI_PROVIDER=""
CLI_MODEL=""
DIFF_CONTENT=""
STAGED_FILES_CONTENT=""
COMMIT_MSG=""
OUTPUT_FILE="/dev/stdout"
NON_INTERACTIVE_MODE="false"
LIST_PROVIDERS_MODE="false"
LIST_MODELS_PROVIDER=""

# ==========================================
# 1. HELPER FUNCTIONS
# ==========================================

debug_log() {
	if [ "$VERBOSE" = "true" ]; then
		# Use >&2 to send debug messages to stderr
		echo -e "\033[0;33m[DEBUG] $1\033[0m" >&2
	fi
}

usage() {
	cat <<EOF
Usage: $0 [options]

AI-Powered Git Commit Message Generator

Options:
  -p, --provider <name>   Specify provider (ollama, opencode, copilot, gemini)
  -m, --model <name>      Specify model name (e.g., llama3, gpt-4)
  -o, --output <file>     Save message to a file instead of stdout
  -l, --limit <num>       Set diff character limit (default: 0 for unlimited)
  -b, --brief             Force short 1-sentence summary
  -e, --emoji             Enable GitMoji style
  -v, --verbose           Enable debug logs
  --non-interactive       Disable interactive menus for provider/model selection
  --list-providers      List detected AI provider CLIs and exit
  --list-models <prov>  List available models for a provider and exit
  -h, --help              Show this help message
EOF
	exit 0
}

find_available_providers() {
	local tools=()
	for tool in ollama opencode copilot gemini; do
		if command -v "$tool" &>/dev/null; then
			tools+=("$tool")
		fi
	done
	printf "%s\n" "${tools[@]}"
}

list_models_for_provider() {
	local provider="$1"
	case $provider in
	"ollama")
		if command -v ollama &>/dev/null; then
			ollama list | tail -n +2 | awk '{print $1}'
		fi
		;;
	"opencode")
		if command -v opencode &>/dev/null; then
			opencode models
		fi
		;;
	*)
		# For providers like copilot/gemini that don't have model lists, output a default.
		echo "(default)"
		;;
	esac
}

# ==========================================
# 2. CORE LOGIC
# ==========================================

# -- Argument & Config Parsing --
parse_args() {
	while [[ "$#" -gt 0 ]]; do
		case $1 in
		-p | --provider)
			CLI_PROVIDER="$2"
			shift
			;;
		-m | --model)
			CLI_MODEL="$2"
			shift
			;;
		-o | --output)
			OUTPUT_FILE="$2"
			shift
			;;
		-l | --limit)
			DIFF_LIMIT="$2"
			shift
			;;
		-b | --brief) BRIEF_MODE="true" ;;
		-e | --emoji) EMOJI_MODE="true" ;;
		-v | --verbose) VERBOSE="true" ;;
		--non-interactive)
			NON_INTERACTIVE_MODE="true"
			;;
		--list-providers)
			LIST_PROVIDERS_MODE="true"
			;;
		--list-models)
			LIST_MODELS_PROVIDER="$2"
			shift
			;;
		-h | --help) usage ;;
		*)
			echo "Unknown parameter: $1"
			usage
			;;
		esac
		shift
	done
}

load_config() {
	local config_file="$HOME/.config/ai-commit/config.sh"
	if [ -f "$config_file" ]; then
		debug_log "Loading config from $config_file"
		# shellcheck source=/dev/null
		source "$config_file"
	else
		debug_log "No config file found at $config_file"
	fi
}

# -- Content Preparation --
prepare_content() {
	debug_log "Preparing git diff..."
	debug_log "Ignoring patterns: ${IGNORED_PATTERNS[*]}"

	local git_args=("--cached" ".")
	for pattern in "${IGNORED_PATTERNS[@]}"; do
		git_args+=(":!$pattern")
	done

	DIFF_CONTENT=$(git diff "${git_args[@]}")
	STAGED_FILES_CONTENT=$(git diff --cached --name-status)

	if [ -z "$DIFF_CONTENT" ] && [ -z "$STAGED_FILES_CONTENT" ]; then
		echo "No staged changes to commit. Press enter to exit." >&2
		read
		exit 1
	fi

	if [ "$DIFF_LIMIT" -gt 0 ] && [ ${#DIFF_CONTENT} -gt "$DIFF_LIMIT" ]; then
		DIFF_CONTENT="${DIFF_CONTENT:0:$DIFF_LIMIT} ... [Diff Truncated]"
		debug_log "Diff was truncated to $DIFF_LIMIT chars."
	fi
}

# -- Provider & Model Selection --
select_provider() {
	if [ -n "$CLI_PROVIDER" ]; then
		PROVIDER=$(echo "$CLI_PROVIDER" | tr '[:upper:]' '[:lower:]')
		debug_log "Using provider from CLI: $PROVIDER"
		return
	fi

	PROVIDER="$DEFAULT_PROVIDER"
	if [ -n "$PROVIDER" ]; then
		debug_log "Using default provider: $PROVIDER"
		return
	fi

	local available_tools
	available_tools=$(find_available_providers)
	read -r -a tools <<<"$available_tools" # Read into array

	if [ ${#tools[@]} -eq 0 ]; then
		echo "Error: No AI CLI tools found (ollama, opencode, copilot, gemini)." >&2
		exit 1
	fi

	if [ ${#tools[@]} -eq 1 ]; then
		PROVIDER="${tools[0]}"
		debug_log "Only one provider found, auto-selecting: $PROVIDER"
		return
	fi

	if [ "$NON_INTERACTIVE_MODE" = "true" ]; then
		echo "Error: Multiple AI providers found. Please specify one with '-p' in non-interactive mode." >&2
		exit 1
	fi

	if command -v gum &>/dev/null; then
		PROVIDER=$(printf "%s\n" "${tools[@]}" | gum choose --header "Select AI Provider")
	elif command -v fzf &>/dev/null; then
		PROVIDER=$(printf "%s\n" "${tools[@]}" | fzf --height=20% --layout=reverse --border --prompt="Select Provider > ")
	else
		echo "Multiple providers found. Please select one:" >&2
		select opt in "${tools[@]}"; do
			if [ -n "$opt" ]; then
				PROVIDER=$opt
				break
			fi
		done
	fi

	if [ -z "$PROVIDER" ]; then
		echo "No provider selected." >&2
		exit 1
	fi
}

select_model() {
	if [ -n "$CLI_MODEL" ]; then
		MODEL="$CLI_MODEL"
		debug_log "Using model from CLI: $MODEL"
		return
	fi

	local model_list
	case $PROVIDER in
	"ollama")
		MODEL="$DEFAULT_OLLAMA_MODEL"
		debug_log "Attempting to find ollama models..."
		if [ "$NON_INTERACTIVE_MODE" = "true" ]; then
			if [ -z "$MODEL" ]; then
				echo "Error: No Ollama model specified. Please use '-m' or set DEFAULT_OLLAMA_MODEL in non-interactive mode." >&2
				exit 1
			fi
			return
		fi
		if command -v ollama &>/dev/null && model_list=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}'); then
			if [ -n "$model_list" ]; then
				if command -v gum &>/dev/null; then
					MODEL=$(echo "$model_list" | gum filter --placeholder "Search ollama models..." --value "$MODEL")
				elif command -v fzf &>/dev/null; then
					MODEL=$(echo "$model_list" | fzf --height=40% --layout=reverse --prompt="Search ollama models > " --query "$MODEL")
				fi
			fi
		fi
		;;
	"opencode")
		MODEL="$DEFAULT_OPENCODE_MODEL"
		debug_log "Attempting to find opencode models..."
		if [ "$NON_INTERACTIVE_MODE" = "true" ]; then
			if [ -z "$MODEL" ]; then
				echo "Error: No OpenCode model specified. Please use '-m' or set DEFAULT_OPENCODE_MODEL in non-interactive mode." >&2
				exit 1
			fi
			return
		fi
		if command -v opencode &>/dev/null && model_list=$(opencode models 2>/dev/null); then
			if [ -n "$model_list" ]; then
				if command -v gum &>/dev/null; then
					MODEL=$(echo "$model_list" | gum filter --placeholder "Search opencode models..." --value "$MODEL")
				elif command -v fzf &>/dev/null; then
					MODEL=$(echo "$model_list" | fzf --height=40% --layout=reverse --prompt="Search opencode models > " --query "$MODEL")
				fi
			fi
		fi
		;;
	*)
		MODEL=""
		debug_log "No model selection for provider '$PROVIDER'."
		;;
	esac
}

# -- Generation & Cleanup --
generate() {
	debug_log "Provider: $PROVIDER"
	debug_log "Model: ${MODEL:-Default}"

	local rules data trigger full_prompt
	rules=$(
		cat <<EOF
You are a git commit message generator.
Follow the Conventional Commits specification.

Format:
<type>[optional scope]: <description>

[optional body]

Rules:
- Types: fix, feat, build, chore, ci, docs, style, refactor, perf, test.
- Use present tense.
- Max title length: 50 chars.
- No markdown code blocks in output.
- No conversational text.
EOF
	)

	if [ "$BRIEF_MODE" = "true" ]; then rules="$rules\nNote: I prefer a very short, one-sentence summary."; fi
	if [ "$EMOJI_MODE" = "true" ]; then rules="$rules\nUse GitMojis (e.g. 🐛 fix:)."; fi

	data=$(
		cat <<EOF
Files changed:
$STAGED_FILES_CONTENT

Diff:
$DIFF_CONTENT
EOF
	)

	trigger="Based on the diff above, generate the commit message now. Output raw text only."

	full_prompt=$(printf "%s\n\n---\n\n%s\n\n---\n\n%s" "$rules" "$data" "$trigger")

	local stderr_capture
	stderr_capture=$(mktemp)

	# We redirect stderr to a file so we can show it on failure or in verbose mode.
	case $PROVIDER in
	"opencode")
		local model_flag_array=()
		if [ -n "$MODEL" ]; then model_flag_array=("-m" "$MODEL"); fi
		debug_log "Running opencode agent 'commit'..."
		COMMIT_MSG=$(opencode run --agent commit "${model_flag_array[@]}" "$data $trigger" 2>"$stderr_capture") || true
		;;
	"ollama")
		debug_log "Running ollama with model '$MODEL'..."
		debug_log "Sending $(echo "$full_prompt" | wc -c | awk '{$1=$1};1') chars to Ollama"
		COMMIT_MSG=$(echo "$full_prompt" | ollama run "$MODEL" 2>"$stderr_capture") || true
		;;
	"copilot")
		debug_log "Running copilot..."
		COMMIT_MSG=$(copilot -s -p "$full_prompt" 2>"$stderr_capture") || true
		;;
	"gemini")
		debug_log "Running gemini..."
		COMMIT_MSG=$(gemini "$full_prompt" 2>"$stderr_capture") || true
		;;
	*)
		echo "Error: Unknown provider '$PROVIDER'" >&2
		exit 1
		;;
	esac

	if [ "$VERBOSE" = "true" ] && [ -s "$stderr_capture" ]; then
		debug_log "--- STDERR from $PROVIDER ---"
		# Indent stderr for clarity
		sed 's/^/    /' "$stderr_capture" >&2
		debug_log "--------------------------"
	fi

	if [ -z "$COMMIT_MSG" ]; then
		echo "Error: AI generation failed. No output received from '$PROVIDER'." >&2
		if [ -s "$stderr_capture" ]; then
			echo "--- Error Details from $PROVIDER ---" >&2
			cat "$stderr_capture" >&2
			echo "--------------------------------" >&2
		fi
		rm -f "$stderr_capture"
		exit 1
	fi
	rm -f "$stderr_capture"
}

cleanup_message() {
	# Remove conversational filler and code blocks
	COMMIT_MSG=$(echo "$COMMIT_MSG" |
		# sed -E 's/^(Sure, |Here is |Here\'s )//I' | # Remove conversational openings
		sed -E '/^```.*$/d' | # Remove code block fences
		awk 'NF {p=1} p')     # Trim leading/trailing newlines
}

# ==========================================
# 3. MAIN EXECUTION
# ==========================================

main() {
	# Ensure we are in a git repository
	if ! git rev-parse --is-inside-work-tree &>/dev/null; then
		echo "Error: Not a git repository." >&2
		exit 1
	fi

	parse_args "$@"

	if [ "$LIST_PROVIDERS_MODE" = "true" ]; then
		find_available_providers
		exit 0
	fi

	if [ -n "$LIST_MODELS_PROVIDER" ]; then
		list_models_for_provider "$LIST_MODELS_PROVIDER"
		exit 0
	fi

	load_config
	prepare_content
	select_provider
	select_model
	generate
	cleanup_message

	if [ "$OUTPUT_FILE" != "/dev/stdout" ]; then
		debug_log "Commit message written to $OUTPUT_FILE"
	fi
	echo "$COMMIT_MSG" >"$OUTPUT_FILE"
}

# Kick off the script
main "$@"
