#!/usr/bin/env bash
set -euo pipefail

# Devcontainer Features run as root at image-build time. $_REMOTE_USER is
# injected by the devcontainer CLI for the user the container will run as.
TARGET_USER="${_REMOTE_USER:-vscode}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TARGET_HOME="${TARGET_HOME:-/home/${TARGET_USER}}"

# CLI install itself is handled by the "dependsOn" feature
# ghcr.io/anthropics/devcontainer-features/claude-code, which runs before
# this script (per the Dev Container Features installation-order spec).

# Persist the whole ~/.claude directory (credentials, sessions, memory)
# across rebuilds via the volume mounted at PERSIST_DIR (see
# devcontainer-feature.json). The mount target can't reference TARGET_HOME
# (feature "mounts" only supports ${devcontainerId} substitution), so we
# mount at a fixed system path instead and symlink it into place here,
# where the real remote user is known.
PERSIST_DIR="/var/lib/claude-home"
mkdir -p "${PERSIST_DIR}"
chown "${TARGET_USER}:${TARGET_USER}" "${PERSIST_DIR}"
if [ -e "${TARGET_HOME}/.claude" ] && [ ! -L "${TARGET_HOME}/.claude" ]; then
  rm -rf "${TARGET_HOME}/.claude"
fi
ln -sfn "${PERSIST_DIR}" "${TARGET_HOME}/.claude"
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.claude"

# ~/.claude.json (OAuth account, personal MCP servers, per-project trust)
# lives outside ~/.claude, directly in $HOME, so it needs its own symlink
# into the same persisted volume.
CONFIG_TARGET="${PERSIST_DIR}/claude.json"
if [ -e "${TARGET_HOME}/.claude.json" ] && [ ! -L "${TARGET_HOME}/.claude.json" ]; then
  rm -f "${TARGET_HOME}/.claude.json"
fi
touch "${CONFIG_TARGET}"
chown "${TARGET_USER}:${TARGET_USER}" "${CONFIG_TARGET}"
ln -sfn "${CONFIG_TARGET}" "${TARGET_HOME}/.claude.json"

# Seed a default permission policy the first time this volume is ever used
# (never overwritten on later rebuilds, so a user's own edits stick): local
# file edits and read-only exploration - including git fetch/pull, which
# only update local refs - are frictionless, but anything that writes or
# authenticates outside the container - git push/clone, ssh/scp, curl/wget,
# gh, package-manager installs, WebFetch to an unlisted domain - requires
# explicit approval. Devcontainers commonly forward the host's SSH
# agent, GPG agent, and git credential helper ambiently, so this is the
# deliberate gate on outbound actions that the container boundary itself
# doesn't provide. Note: there is deliberately no bare "WebFetch" entry in
# the ask list alongside the domain-scoped allow rules - that combination
# was found to make the ask rule shadow the more specific allows, so every
# WebFetch call (even to allowlisted domains) kept prompting.
#
# Also hardens the permission policy itself: a path-scoped ask rule on
# ~/.claude/settings.json forces the real permission prompt for any edit to
# it, in every permission mode, and can't be loosened by a project's own
# .claude/settings.local.json - ask rules from any settings scope always
# beat allow rules regardless of specificity or scope (confirmed against
# code.claude.com/docs/en/permissions). An earlier version of this file used
# an autoMode.hard_deny rule instead; that turned out to be a one-way
# ratchet - once added, it blocked every subsequent tool-call edit to any
# permission file, including edits to undo itself, with no working retry
# path, because autoMode hard_deny/soft_deny are pure classifier judgments
# over the conversation transcript, not a dialog. permissions.ask doesn't
# have that failure mode: it's evaluated before the classifier ever runs.
SETTINGS_TARGET="${PERSIST_DIR}/settings.json"
if [ ! -e "${SETTINGS_TARGET}" ]; then
  cat > "${SETTINGS_TARGET}" <<EOF
{
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "NotebookEdit",
      "Read",
      "Grep",
      "Glob",
      "WebSearch",
      "WebFetch(domain:containers.dev)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:docs.anthropic.com)",
      "WebFetch(domain:developer.mozilla.org)",
      "WebFetch(domain:npmjs.com)",
      "Bash(git status)",
      "Bash(git status *)",
      "Bash(git diff)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git show *)",
      "Bash(git branch *)",
      "Bash(git checkout *)",
      "Bash(git stash *)",
      "Bash(git fetch *)",
      "Bash(git pull *)"
    ],
    "ask": [
      "Bash(git push *)",
      "Bash(git clone *)",
      "Bash(git remote add *)",
      "Bash(git remote set-url *)",
      "Bash(git remote remove *)",
      "Bash(ssh *)",
      "Bash(scp *)",
      "Bash(sftp *)",
      "Bash(rsync *)",
      "Bash(curl *)",
      "Bash(wget *)",
      "Bash(gh *)",
      "Bash(npm install *)",
      "Bash(npm publish *)",
      "Bash(npm ci *)",
      "Bash(npx *)",
      "Bash(pip install *)",
      "Bash(pip3 install *)",
      "Bash(yarn add *)",
      "Bash(yarn install *)",
      "Bash(pnpm add *)",
      "Bash(pnpm install *)",
      "Bash(apt-get install *)",
      "Bash(apt-get update *)",
      "Bash(apt install *)",
      "Bash(sudo apt-get install *)",
      "Bash(sudo apt-get update *)",
      "Bash(sudo apt install *)",
      "Bash(brew install *)",
      "Bash(gem install *)",
      "Bash(cargo install *)",
      "Bash(go install *)",
      "Bash(go get *)",
      "Edit(//${TARGET_HOME}/.claude/settings.json)",
      "Write(//${TARGET_HOME}/.claude/settings.json)"
    ]
  }
}
EOF
  chown "${TARGET_USER}:${TARGET_USER}" "${SETTINGS_TARGET}"
fi
