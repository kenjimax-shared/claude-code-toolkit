# --- Remote Claude Code Setup: .bashrc additions ---
# Add these to the bottom of your ~/.bashrc

# Auto-attach to tmux when opening a terminal in code-server.
# $TMUX is empty when not inside tmux; $TERM_PROGRAM is set by code-server.
if command -v tmux &> /dev/null && [ -z "$TMUX" ] && [ -n "$TERM_PROGRAM" ]; then
    tmux new-session -A -s main
fi
