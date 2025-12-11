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

source "$(dirname "$0")/common.sh"

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
			echo "Unknown parameter: $1" >&2
			usage
			;;
		esac
		shift
	done
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

# -- Generation & Cleanup --
generate_commit_message() {
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
- No conversational text.
- Only respond with the commit message. Don't give any notes.
- Explain what were the changes and why the changes were done.
- Focus the most important changes.
- Use the present tense.
- Use a semantic commit prefix.
- Hard wrap lines at 72 characters.
- Ensure the title is only 50 characters.
- IMPORTANT: Do not start any line with the hash symbol (#). It will be interpreted as a comment and ignored.
EOF
	)

	if [ "$BRIEF_MODE" = "true" ]; then rules="$rules\nNote: I prefer a very short, one-sentence summary."; fi
	if [ "$EMOJI_MODE" = "true" ]; then rules="$rules\nUse GitMojis (e.g. 🐛 fix:)."; fi

	data=$(
		cat <<EOF
Files changed:
$STAGED_FILES_CONTENT

\`\`\`
$DIFF_CONTENT
\`\`\`
EOF
	)

	trigger="Based on the diff above, generate the commit message now. Output raw text only."

	full_prompt=$(printf "%s\n\n---\n\n%s\n%s" "$data" "$rules" "$trigger")

	run_ai_provider "$full_prompt" "$PROVIDER" "$MODEL" "COMMIT_MSG"
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
	generate_commit_message
	COMMIT_MSG=$(cleanup_message "$COMMIT_MSG")

	if [ "$OUTPUT_FILE" != "/dev/stdout" ]; then
		debug_log "Commit message written to $OUTPUT_FILE"
	fi
	echo "$COMMIT_MSG" >"$OUTPUT_FILE"
}

# Kick off the script
main "$@"
