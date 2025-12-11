# ai-commit

Generate conventional commit messages with the power of AI, right from your command line.

`ai-commit` is a shell script that uses the diff of your staged files to generate a descriptive and conventional commit message. It's designed to be fast, flexible, and integrate with your favorite AI tools.

## Features

-   **Conventional Commits:** Automatically generates messages following the [Conventional Commits specification](https://www.conventionalcommits.org/).
-   **Multi-Provider Support:** Works out-of-the-box with `ollama`, `opencode`, `copilot`, and `gemini`.
-   **User-Friendly Selection:** If you have multiple tools, `ai-commit` provides an interactive prompt (using `gum` or `fzf`) to select the provider and model for each run.
-   **Configurable:** Set your default provider, model, and ignored file patterns in a simple configuration file.
-   **Emoji Support:** Add GitMoji style emojis to your commits with the `-e` flag.
-   **Brief Mode:** Get a single-sentence summary with the `-b` flag.

## Dependencies

### Required

-   `git`
-   At least one of the following AI command-line tools:
    -   [Ollama](https://ollama.ai/)
    -   [OpenCode](https://opencode.sh/)
    -   [GitHub Copilot CLI](https://github.com/cli/cli-extension-copilot)
    -   [Gemini CLI](https://github.com/google/generative-ai-go/tree/main/cmd/gemini)

### Optional

For an enhanced interactive experience when selecting providers or models:

-   [gum](https://github.com/charmbracelet/gum)
-   [fzf](https://github.com/junegunn/fzf)

If neither is installed, `ai-commit` falls back to the standard `select` prompt.

## Installation

You can install `ai-commit` with a single command using `curl` or `wget`.

1.  **Choose an installation directory.** We recommend `~/.local/bin` as it's a common place for user scripts. Make sure it's in your `PATH`.
    ```sh
    mkdir -p ~/.local/bin
    # Add to your shell profile (e.g., ~/.bashrc, ~/.zshrc) if not already present
    export PATH="$HOME/.local/bin:$PATH"
    ```

2.  **Download the script:**

    *   Using `curl`:
        ```sh
        curl -L https://raw.githubusercontent.com/mar-mot/ai-commits/main/ai-commit.sh -o ~/.local/bin/ai-commit
        ```
    *   Using `wget`:
        ```sh
        wget https://raw.githubusercontent.com/mar-mot/ai-commits/main/ai-commit.sh -O ~/.local/bin/ai-commit
        ```

3.  **Make it executable:**
    ```sh
    chmod +x ~/.local/bin/ai-commit
    ```

4.  **Verify the installation:**
    ```sh
    ai-commit --help
    ```

## Configuration

You can create a configuration file at `~/.config/ai-commit/config.sh` to set your preferences.

1.  Create the directory and file:
    ```sh
    mkdir -p ~/.config/ai-commit
    touch ~/.config/ai-commit/config.sh
    ```

2.  Add your custom settings. Here is an example:
    ```sh
    # ~/.config/ai-commit/config.sh

    # Set a default provider to avoid being asked every time
    # Options: "ollama", "opencode", "copilot", "gemini"
    DEFAULT_PROVIDER="ollama"

    # Set a default model for your provider
    DEFAULT_OLLAMA_MODEL="llama3:8b"
    # DEFAULT_OPENCODE_MODEL="<your-opencode-model>"

    # Add custom file patterns to ignore (appended to the default list)
    # IGNORED_PATTERNS+=("*.log" "tmp/")
    ```

## Usage

1.  Stage your changes with `git add`.
2.  Run `ai-commit`.

The generated message will be printed to standard output. To commit with the message, you can use:

```sh
git commit -m "$(ai-commit)"
```

### Options

```
Usage: ./ai-commit.sh [options]

AI-Powered Git Commit Message Generator

Options:
  -p, --provider <name>   Specify provider (ollama, opencode, copilot, gemini)
  -m, --model <name>      Specify model name (e.g., llama3, gpt-4)
  -l, --limit <num>       Set diff character limit (default: 20000)
  -b, --brief             Force short 1-sentence summary
  -e, --emoji             Enable GitMoji style
  -v, --verbose           Enable debug logs
  -h, --help              Show this help message
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.