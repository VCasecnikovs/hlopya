#!/usr/bin/env bash
# One-time Sparkle EdDSA keypair setup. Stores the private key in the macOS
# login keychain under the Sparkle-standard "https://sparkle-project.org"
# service. Prints the matching public key so you can paste it into Info.plist
# as SUPublicEDKey.
#
# Safe to re-run: if a key already exists in the keychain, it just prints it.
# Will not overwrite an existing key.

set -euo pipefail

SPARKLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$SPARKLE_DIR"

# Find generate_keys from Sparkle's SPM artifact.
GEN_KEYS="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*Sparkle*/bin/generate_keys' -print 2>/dev/null | head -1)"
if [[ -z "$GEN_KEYS" ]]; then
    GEN_KEYS="$(find .build -path '*Sparkle*/bin/generate_keys' -print 2>/dev/null | head -1)"
fi

if [[ -z "$GEN_KEYS" ]]; then
    echo "error: generate_keys not found. Run 'make build' first so SPM fetches Sparkle." >&2
    exit 1
fi

# -p prints an existing key. If none exists, fall back to creating one.
if PUBKEY="$("$GEN_KEYS" -p 2>/dev/null)" && [[ -n "$PUBKEY" ]]; then
    echo "existing Sparkle keypair in keychain"
else
    echo "generating new Sparkle keypair (stored in login keychain)..."
    "$GEN_KEYS"
    PUBKEY="$("$GEN_KEYS" -p)"
fi

echo ""
echo "SUPublicEDKey = $PUBKEY"
echo ""
echo "paste the line above into Hlopya/Info.plist under the SUPublicEDKey key"
