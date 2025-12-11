#!/usr/bin/env bash
#
# AI-Powered Git Tag Message Generator
#
# This script uses AI to generate release notes based on the commit history since the last tag.
# It supports multiple AI providers (Ollama, OpenCode, Copilot, Gemini) and
# offers a user-friendly interface for selecting providers and models.
#
# Website: https://github.com/mar-mot/ai-commits
#
# Usage: ./ai-tag.sh <tag-name> [options]
#

set -eo pipefail

# ==========================================
# 0. CONFIGURATION & DEFAULTS
# ==========================================

VERBOSE="false"
# -- Defaults (can be overridden by config) --
DEFAULT_PROVIDER=""
DEFAULT_OLLAMA_MODEL="llama3"
DEFAULT_OPENCODE_MODEL=""

# -- Globals --
CLI_PROVIDER=""
CLI_MODEL=""
COMMIT_LOG=""
TAG_NAME=""
TAG_MESSAGE=""
NON_INTERACTIVE_MODE="false"
LIST_PROVIDERS_MODE="false"
LIST_MODELS_PROVIDER=""

# ==========================================
# 1. HELPER FUNCTIONS
# ==========================================

source "$(dirname "$0")/common.sh"

usage() {
	cat <<EOF
Usage: $0 <tag-name> [options]

AI-Powered Git Tag Message Generator.
Creates an annotated tag with an AI-generated message based on the commits since the last tag.

Arguments:
  <tag-name>            The name of the tag to create (e.g., v1.2.3)

Options:
  -p, --provider <name>   Specify provider (ollama, opencode, copilot, gemini)
  -m, --model <name>      Specify model name (e.g., llama3, gpt-4)
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
	if [ -z "$1" ] || [[ "$1" == -* ]]; then
		echo "Error: Tag name is a required argument." >&2
		usage
	fi
	TAG_NAME="$1"
	shift

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

# -- Content Preparation --
prepare_content() {
	debug_log "Preparing commit log..."
	local last_tag
	if ! last_tag=$(git describe --tags --abbrev=0 2>/dev/null); then
		debug_log "No previous tag found. Getting all commits."
		# If no tags, get all commits from the beginning.
		COMMIT_LOG=$(git log --pretty=format:"%h - %s")
	else
		debug_log "Found last tag: $last_tag. Getting commits since then."
		COMMIT_LOG=$(git log "${last_tag}"..HEAD --pretty=format:"%h - %s")
	fi

	if [ -z "$COMMIT_LOG" ]; then
		echo "No new commits since last tag to create a release from. Press enter to exit." >&2
		read
		exit 1
	fi

	debug_log "Commit log prepared."
}

# -- Generation & Cleanup --
generate_release_notes() {
	debug_log "Provider: $PROVIDER"
	debug_log "Model: ${MODEL:-Default}"

	local rules data trigger full_prompt
	rules=$(
		cat <<EOF
You are a release notes generator for a git repository.
Your task is to summarize a list of commit messages into a cohesive and well-formatted release notes document.

Rules:
- Use markdown headings (e.g., "### ✨ Features") for sections. Do not start any other lines with a hash symbol (#) unless it is for a heading.
- The output should be formatted in Markdown.
- Group changes by their type (e.g., "✨ Features", "🐛 Bug Fixes", "🔧 Miscellaneous").
- Each item in the list should be a brief, clear summary of the change.
- Omit the commit hashes from the output.
- The tone should be professional and user-friendly.
- Do not include conversational text or any text outside of the release notes themselves.
EOF
	)

	data=$(
		cat <<EOF
Commit History:
$COMMIT_LOG
EOF
	)

	trigger="Based on the commit history above, generate the release notes now. Output raw text only."

	full_prompt=$(printf "%s\n\n---\n\n%s\n%s" "$data" "$rules" "$trigger")

	run_ai_provider "$full_prompt" "$PROVIDER" "$MODEL" "TAG_MESSAGE"
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
	generate_release_notes
	TAG_MESSAGE=$(cleanup_message "$TAG_MESSAGE")

	echo "$TAG_MESSAGE"
}

# Kick off the script
main "$@"
