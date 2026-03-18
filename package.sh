#!/bin/bash
# package.sh — builds dist/setup.sh as a self-extracting installer
# Embeds all distribution files as a base64-encoded tarball.
# Version is read from the latest git tag.
#
# Usage: bash package.sh
# Output: dist/setup.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null || echo "dev")

mkdir -p "$SCRIPT_DIR/dist"
OUT="$SCRIPT_DIR/dist/workday-notify-${VERSION}.sh"

# Files to include in the distribution
DIST_FILES=(
    src/banner.sh
    src/workday-notify.sh
    src/platform/macos.sh
    src/platform/linux.sh
    install.sh
    uninstall.sh
    config.conf
)

echo "Packaging workday-notify $VERSION..."

# Verify all files exist
for f in "${DIST_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
        echo "Error: missing $f" >&2
        exit 1
    fi
done

# Create tarball
PAYLOAD=$(cd "$SCRIPT_DIR" && tar czf - "${DIST_FILES[@]}" | base64)

# Write self-extracting installer
cat > "$OUT" << HEADER
#!/bin/bash
# workday-notify $VERSION — self-extracting installer
# Usage: curl -sL <url>/setup.sh | bash
# Or:    bash setup.sh
set -e

# Ensure a sufficiently new Bash (>=4). If running under older bash (macOS /bin/bash v3),
# try common locations for newer bash (Homebrew). If found, re-exec this script with it.
ensure_modern_bash() {
    # If running under bash and version >=4, OK
    if [ -n "\${BASH_VERSION-}" ]; then
        major=\${BASH_VERSION%%.*}
        if [ "\$major" -ge 4 ]; then
            return 0
        fi
    fi

    # Candidate locations to try (arm/Intel Homebrew + common paths)
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash; do
        if [ -x "\$candidate" ]; then
            ver=\$("\$candidate" -c 'printf "\\%s\\n" "\${BASH_VERSION:-0}"' 2>/dev/null || echo "")
            major=\${ver%%.*}
            if [ -n "\$major" ] && [ "\$major" -ge 4 ]; then
                exec "\$candidate" "\$0" "\$@"
            fi
        fi
    done

    echo "Warning: Bash >=4 not found; installer may fail on older systems." >&2
    return 1
}

ensure_modern_bash

INSTALL_DIR="\$HOME/.workday-notify"
VERSION="$VERSION"

# Extract embedded archive
extract() {
    local archive_start
    archive_start=\$(awk '/^__ARCHIVE__\$/ {print NR+1; exit}' "\$0")
    tail -n +"\$archive_start" "\$0" | base64 -d | tar xzf - -C "\$INSTALL_DIR"
}

# Preserve existing config
BACKUP=""
if [[ -f "\$INSTALL_DIR/config.conf" ]]; then
    BACKUP=\$(cat "\$INSTALL_DIR/config.conf")
fi

mkdir -p "\$INSTALL_DIR/src/platform"
extract

# Restore user config if it existed
if [[ -n "\$BACKUP" ]]; then
    echo "\$BACKUP" > "\$INSTALL_DIR/config.conf"
fi

# Run the installer
bash "\$INSTALL_DIR/install.sh"
echo ""
echo "  Uninstall: bash \$INSTALL_DIR/uninstall.sh"
echo ""
echo "Edit \$INSTALL_DIR/config.conf to customize your schedule."
exit 0
__ARCHIVE__
HEADER

# Append the payload
echo "$PAYLOAD" >> "$OUT"
chmod +x "$OUT"

echo "✓ Created dist/workday-notify-${VERSION}.sh ($(wc -c < "$OUT" | tr -d ' ') bytes)"
echo "  Embedded: ${DIST_FILES[*]}"
