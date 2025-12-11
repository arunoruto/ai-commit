#!/usr/bin/env bash

# ==========================================
# 1. HELPER FUNCTIONS
# ==========================================

debug_log() {
	if [ "$VERBOSE" = "true" ]; then
		# Use >&2 to send debug messages to stderr
		echo -e "\033[0;33m[DEBUG] $1\033[0m" >&2
	fi
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

select_provider() {
	if [ -n "$CLI_PROVIDER" ]; then
		PROVIDER=$(echo "$CLI_PROVIDER" | tr '[:upper:]' '[:lower:]')
		debug_log "Using provider from CLI: $PROVIDER"
		return
	fi

	local -a tools=()
	while read -r tool; do
		tools+=("$tool")
	done < <(find_available_providers)

	if [ ${#tools[@]} -eq 0 ]; then
		echo "Error: No AI CLI tools found (ollama, opencode, copilot, gemini)." >&2
		exit 1
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

cleanup_message() {
	local msg="$1"
	echo "$msg" |
		sed -E '/^```.*$/d' | # Remove code block fences
		awk 'NF {p=1} p'
}

run_ai_provider() {
	local full_prompt="$1"
	local provider="$2"
	local model="$3"
	local result_var_name="$4"

	local stderr_capture
	stderr_capture=$(mktemp)
	local output=""

	case $provider in
	"opencode")
		local model_flag_array=()
		if [ -n "$model" ]; then model_flag_array=("-m" "$model"); fi
		debug_log "Running opencode..."
		output=$(echo "$full_prompt" | opencode run "${model_flag_array[@]}" 2>"$stderr_capture") || true
		;;
	"ollama")
		debug_log "Running ollama with model '$model'..."
		debug_log "Sending $(echo "$full_prompt" | wc -c | awk '{$1=$1};1') chars to Ollama"
		output=$(echo "$full_prompt" | ollama run "$model" 2>"$stderr_capture") || true
		;;
	"copilot")
		debug_log "Running copilot..."
		output=$(copilot -s -p "$full_prompt" 2>"$stderr_capture") || true
		;;
	"gemini")
		debug_log "Running gemini..."
		output=$(echo "$full_prompt" | gemini 2>"$stderr_capture") || true
		;;
	*)
		echo "Error: Unknown provider '$provider'" >&2
		exit 1
		;;
	esac

	if [ "$VERBOSE" = "true" ] && [ -s "$stderr_capture" ]; then
		debug_log "--- STDERR from $provider ---"
		sed 's/^/    /' "$stderr_capture" >&2
		debug_log "--------------------------"
	fi

	if [ -z "$output" ]; then
		echo "Error: AI generation failed. No output received from '$provider'." >&2
		if [ -s "$stderr_capture" ]; then
			echo "--- Error Details from $provider ---" >&2
			cat "$stderr_capture" >&2
			echo "--------------------------------" >&2
		fi
		rm -f "$stderr_capture"
		exit 1
	fi
	rm -f "$stderr_capture"

	printf -v "$result_var_name" "%s" "$output"
}
