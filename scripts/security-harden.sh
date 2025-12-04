#!/bin/bash
# Security Hardening Script for TDL
# Run this after initial setup

set -e

echo "🔒 TDL Security Hardening Script"
echo "================================"
echo ""

# Fix file permissions
echo "1. Fixing file permissions..."
if [ -d "$HOME/.tdl" ]; then
    chmod 700 "$HOME/.tdl"
    echo "   ✅ Set .tdl directory to 700"
    
    if [ -f "$HOME/.tdl/gdrive_credentials.json" ]; then
        chmod 600 "$HOME/.tdl/gdrive_credentials.json"
        echo "   ✅ Set gdrive_credentials.json to 600"
    fi
    
    if [ -f "$HOME/.tdl/gdrive_token.json" ]; then
        chmod 600 "$HOME/.tdl/gdrive_token.json"
        echo "   ✅ Set gdrive_token.json to 600"
    fi
    
    if [ -d "$HOME/.tdl/data" ]; then
        chmod 700 "$HOME/.tdl/data"
        echo "   ✅ Set data directory to 700"
    fi
else
    echo "   ⚠️  .tdl directory not found - will be created on first run"
fi

echo ""
echo "2. Checking disk encryption..."
if [ -f "/sys/block/dm-0/dm/name" ]; then
    echo "   ✅ Disk encryption detected (LVM/LUKS)"
elif mount | grep -q "BitLocker\|FileVault"; then
    echo "   ✅ Disk encryption detected"
else
    echo "   ⚠️  Disk encryption not detected"
    echo "   💡 Recommendation: Enable full-disk encryption"
    echo "      - Windows: BitLocker"
    echo "      - Linux: LUKS"
    echo "      - macOS: FileVault"
fi

echo ""
echo "3. Security checklist:"
echo "   [ ] Enable Telegram 2FA (Two-Step Verification)"
echo "   [ ] Use strong unique passwords"
echo "   [ ] Keep software updated"
echo "   [ ] Review SECURITY_AUDIT.md for details"

echo ""
echo "4. Optional: Check for vulnerabilities"
echo "   Run: govulncheck ./..."
echo "   Install: go install golang.org/x/vuln/cmd/govulncheck@latest"

echo ""
echo "✅ Security hardening complete!"
echo ""
echo "📖 Read full security audit: SECURITY_AUDIT.md"
