#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# NOTE: This script runs as a regular user (NOT root)
# The orchestrator calls this with: su - $SUDO_USER -c "bash /path/to/04-claude-code.sh"

info "Starting Claude Code CLI installation (running as $(whoami))..."

# Step 1: Check if claude is already installed
info "Checking if Claude Code CLI is already installed..."

if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 || echo "unknown")
    ok "Claude Code CLI already installed: $CLAUDE_VERSION"
    ok "Skipping installation"
    exit 0
elif [[ -f "$HOME/.local/bin/claude" ]]; then
    if "$HOME/.local/bin/claude" --version &> /dev/null; then
        CLAUDE_VERSION=$("$HOME/.local/bin/claude" --version 2>&1 || echo "unknown")
        ok "Claude Code CLI already installed at ~/.local/bin/claude: $CLAUDE_VERSION"
        ok "Skipping installation"
        exit 0
    fi
fi

# Step 2: Install Claude Code CLI
info "Installing Claude Code CLI..."
info "Running: curl -fsSL https://claude.ai/install.sh | bash"

# Download and execute installer
if curl -fsSL https://claude.ai/install.sh | bash; then
    ok "Claude Code CLI installed successfully"
else
    err "Failed to install Claude Code CLI"
    exit 1
fi

# Step 3: Verify installation
info "Verifying installation..."

# Wait a moment for installation to complete
sleep 2

# Check if claude is available
if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 || echo "unknown")
    ok "✓ Claude Code CLI verified: $CLAUDE_VERSION"
elif [[ -f "$HOME/.local/bin/claude" ]]; then
    if "$HOME/.local/bin/claude" --version &> /dev/null; then
        CLAUDE_VERSION=$("$HOME/.local/bin/claude" --version 2>&1 || echo "unknown")
        ok "✓ Claude Code CLI verified at ~/.local/bin/claude: $CLAUDE_VERSION"

        # Add to PATH for current session if not already there
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            export PATH="$HOME/.local/bin:$PATH"
            info "Added ~/.local/bin to PATH for this session"
        fi
    else
        warn "Claude binary exists at ~/.local/bin/claude but cannot verify version"
    fi
else
    err "Installation completed but claude command not found"
    err "Expected location: ~/.local/bin/claude"
    exit 1
fi

# Step 4: Print guidance
echo ""
ok "═══════════════════════════════════════════════════════════"
ok "Claude Code CLI Installation Complete"
ok "═══════════════════════════════════════════════════════════"
info "Installation location: ~/.local/bin/claude"
echo ""
info "Next steps:"
echo "  1. Ensure ~/.local/bin is in your PATH:"
echo "     • Should be automatic for bash/zsh"
echo "     • Or manually add: export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "  2. Authenticate Claude Code CLI:"
echo "     $ claude"
echo "     • This will open a browser for OAuth authentication"
echo "     • Follow the prompts to link your Anthropic account"
echo ""
echo "  3. Run oh-my-claudecode setup:"
echo "     $ /oh-my-claudecode:omc-setup"
echo "     • Configures multi-agent orchestration"
echo "     • Sets default execution modes"
echo ""
echo "  4. Copy CLAUDE.md from your Mac (if applicable):"
echo "     $ scp user@mac:~/.claude/CLAUDE.md ~/.claude/"
echo "     • Contains your personal Claude configuration"
echo "     • Or manually create ~/.claude/CLAUDE.md"
echo ""
ok "Documentation: https://claude.ai/docs/cli"
ok "═══════════════════════════════════════════════════════════"
