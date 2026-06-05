#!/bin/bash
# ppa-upload.sh — Build source packages and upload to a Launchpad PPA
# for Ubuntu 22.04 (jammy) and Ubuntu 24.04 (noble).
#
# Usage:
#   Set the environment variables below (or export them before running),
#   then run this script from the root of the angband-Ubuntu repository.
#
# Required environment variables (no defaults — must be set):
#   DEBFULLNAME   Your full name, e.g. "Jane Smith"
#   DEBEMAIL      Your e-mail address, e.g. "jane@example.com"
#   GPG_KEYID     Your GPG key fingerprint or short key ID, e.g. "ABCDEF01"
#   PPA           Launchpad PPA target, e.g. "ppa:yourusername/angband"
#
# Optional environment variables:
#   BASE_VER      Debian source version to use as base (default: read from
#                 debian/changelog, e.g. "4.2.6-1")
#   SERIES        Space-separated list of Ubuntu series to target
#                 (default: "noble jammy")
#   FORCE_REBUILD Set to "1" to skip the orig tarball existence check.

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

require_var() {
    local var="$1"
    [[ -n "${!var:-}" ]] || die "Environment variable \$$var is not set."
}

# ── validate required vars ───────────────────────────────────────────────────

require_var DEBFULLNAME
require_var DEBEMAIL
require_var GPG_KEYID
require_var PPA

export DEBFULLNAME DEBEMAIL

# ── resolve BASE_VER from changelog if not set ───────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG="$REPO_ROOT/debian/changelog"

[[ -f "$CHANGELOG" ]] || die "debian/changelog not found at $CHANGELOG"

if [[ -z "${BASE_VER:-}" ]]; then
    BASE_VER="$(dpkg-parsechangelog -l "$CHANGELOG" --show-field Version)"
    [[ -n "$BASE_VER" ]] || die "Could not parse version from debian/changelog."
fi

SRC_PKG="$(dpkg-parsechangelog -l "$CHANGELOG" --show-field Source)"
[[ -n "$SRC_PKG" ]] || die "Could not parse source package name from debian/changelog."

# ── resolve series list ──────────────────────────────────────────────────────

SERIES="${SERIES:-noble jammy}"

# ── map series names to version strings ──────────────────────────────────────

series_to_ubuntu_ver() {
    case "$1" in
        noble)  echo "24.04" ;;
        jammy)  echo "22.04" ;;
        focal)  echo "20.04" ;;
        bionic) echo "18.04" ;;
        *)      die "Unknown Ubuntu series: $1 (add it to series_to_ubuntu_ver())" ;;
    esac
}

# ── per-series upload ─────────────────────────────────────────────────────────

cd "$REPO_ROOT"

for SERIES_NAME in $SERIES; do
    UBUNTU_VER="$(series_to_ubuntu_ver "$SERIES_NAME")"

    # Find the next available pocket suffix (~ubuntu<ver>.<N>)
    SUFFIX=1
    while true; do
        PKG_VER="${BASE_VER}~ubuntu${UBUNTU_VER}.${SUFFIX}"
        CHANGES_FILE="../${SRC_PKG}_${PKG_VER}_source.changes"
        if [[ ! -f "$CHANGES_FILE" ]]; then
            break
        fi
        echo "Version $PKG_VER already built (found $CHANGES_FILE), trying .$(( SUFFIX + 1 ))..."
        (( SUFFIX++ ))
    done

    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "  Building source package for Ubuntu ${UBUNTU_VER} (${SERIES_NAME})"
    echo "  Version : $PKG_VER"
    echo "  Changes : $CHANGES_FILE"
    echo "══════════════════════════════════════════════════════════"

    # Update changelog for this series
    dch \
        --newversion "$PKG_VER" \
        --distribution "$SERIES_NAME" \
        --force-distribution \
        "Launchpad PPA upload for Ubuntu ${UBUNTU_VER} (${SERIES_NAME^})."

    # Build signed source-only package
    debuild -S -sa -k"${GPG_KEYID}"

    # Upload to Launchpad
    dput "${PPA}" "$CHANGES_FILE"

    echo "  ✓ Uploaded $PKG_VER to $PPA"

    # Restore changelog to BASE_VER so the next series starts clean
    git checkout -- debian/changelog
done

echo ""
echo "All series uploaded successfully."
