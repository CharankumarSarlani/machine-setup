#!/usr/bin/env bash

CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
CONFIG_FILE="$CONFIG_DIR/config.ghostty"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<'EOF'
font-size = 126
EOF

echo "Ghostty config overwritten:"
cat "$CONFIG_FILE"
