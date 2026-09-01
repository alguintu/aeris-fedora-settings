#!/usr/bin/bash
set -euo pipefail

if ! command -v git >/dev/null; then
    echo "Git is not installed. On Fedora, run: sudo dnf install git" >&2
    exit 1
fi

git config --global user.name "Drei Guintu"
git config --global user.email "6581480+alguintu@users.noreply.github.com"

echo "Git commit identity configured:"
echo "  $(git config --global user.name)"
echo "  $(git config --global user.email)"

if command -v gh >/dev/null; then
    if gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI is authenticated."
    else
        echo "GitHub CLI is installed but not authenticated; run: gh auth login"
    fi
else
    echo "GitHub CLI is not installed; on Fedora, run: sudo dnf install gh"
fi
