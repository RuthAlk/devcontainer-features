# devcontainer-features

Shared [Dev Container Features](https://containers.dev/implementors/features/) for use across
independent project repos (Android, Godot, Go, Rust, Pico, ...), so common setup only has to be
written once.

## Features

- **claude-setup** (`src/claude-setup`) — depends on the official
  `ghcr.io/anthropics/devcontainer-features/claude-code` feature for the CLI itself, and adds
  what that one doesn't: persists the whole `~/.claude` directory and `~/.claude.json`
  (credentials, sessions, memory, OAuth account, trust settings) across rebuilds via a single
  named volume (`claude-home`) shared by every devcontainer on the host, so Claude stays logged
  in and keeps memory/session history across rebuilds *and* across projects — log in once, use
  everywhere.

  Most of what lives under `~/.claude` is already namespaced by working-directory path (session
  history, memory) under `~/.claude/projects/<encoded-cwd>/...`, so different projects don't
  collide on that data even though the volume is shared — it just becomes visible to every
  container instead of isolated per project. The exceptions are `settings.json` (the permission
  policy) and `~/.claude.json` (OAuth token, per-project trust map), which are single shared
  files: an edit made from one project's devcontainer applies everywhere, and if you run two
  devcontainers at once, a near-simultaneous edit to either file is last-writer-wins (no
  corruption — writes are write-then-rename) — the same tradeoff a bare host install already has
  running two concurrent `claude` sessions in different terminals.

  Before v2.0.0 this feature scoped the volume per project using `${devcontainerId}`, so each
  devcontainer got its own credentials/settings/memory. Upgrading to v2.0.0 in an existing
  project switches it onto the shared `claude-home` volume; the old per-`devcontainerId` volumes
  are left behind on the host (not deleted, not migrated) and can be removed manually via
  `docker volume rm` once no longer needed.

  The first time the volume is used (i.e. no `settings.json` exists in it yet), it also seeds a
  default permission policy: local file edits (`Edit`/`Write`/`NotebookEdit`) and read-only
  exploration (`Read`/`Grep`/`Glob`, local `git status`/`diff`/`log`/`show`, and `git fetch`/`pull`,
  which only update local refs) are auto-allowed, but anything that writes or authenticates outside
  the container — `git push`/`clone`, `ssh`/`scp`/`sftp`/`rsync`, `curl`/`wget`, `gh`,
  package-manager installs (`npm`/`pip`/`apt`/`brew`/`gem`/`cargo`/`go`), and `WebFetch` to any
  domain outside a small doc-site allowlist — requires explicit approval. This exists because dev
  containers commonly forward the host's SSH agent,
  GPG agent, and git credential helper ambiently (so any process in the container can push/sign/
  auth as the host user with no OS-level prompt); Claude Code's own permission gate is the
  deliberate checkpoint on outbound actions that the container boundary doesn't otherwise provide.
  Only written once — a user's own edits to `settings.json` afterward are never overwritten by a
  later rebuild.

  It also adds a path-scoped `permissions.ask` rule on `~/.claude/settings.json` itself, so any
  edit to that file always forces the real approval prompt, in every permission mode, and can't be
  loosened by a project's own `.claude/settings.local.json` — ask rules from any settings scope
  beat allow rules regardless of specificity or scope. An earlier version of this feature used an
  `autoMode.hard_deny` rule for this instead; that turned out to be a one-way ratchet that blocked
  every subsequent edit to any permission file, including undoing itself, with no working retry
  path, because auto-mode hard_deny/soft_deny are classifier judgments over the conversation
  transcript rather than a dialog. `permissions.ask` doesn't have that failure mode.

## Publishing

Pushing to `main` (touching `src/**`) auto-publishes via `.github/workflows/publish.yml` — no
manual steps needed. The package is public on GHCR, so consuming devcontainers can pull it with no
authentication.

Consuming projects reference it as:

```json
"features": {
  "ghcr.io/<your-github-username>/devcontainer-features/claude-setup:1": {}
}
```
