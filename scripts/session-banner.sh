#!/usr/bin/env bash
# SessionStart hook for NL-OKF-Bundler. Runs once when a Claude Code session
# starts in this repo. It (1) sets the terminal tab title to "OKF Bundler"
# out-of-band via an OSC escape, and (2) prints a JSON payload that shows the
# user a banner and tells the agent to announce it is the bundler orchestrator.
set -uo pipefail

# Terminal tab title (best-effort; harmless if there's no controlling tty).
# Pair with "terminalTitleFromRename": false in settings.json so Claude Code
# does not overwrite it.
printf '\033]0;OKF Bundler\007' > /dev/tty 2>/dev/null || true

# Hook result on stdout. additionalContext nudges the agent to self-announce;
# systemMessage shows the user a one-line banner at session start.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"This session is the NL-OKF-Bundler bundler orchestrator (operate per harness/bundler.md). Open your first reply with the line: “▶ NL-OKF-Bundler ready — tell me: bundle <refs> into <OUT>.”"},"systemMessage":"🧶 NL-OKF-Bundler harness active — prompt: bundle <refs> into <OUT>"}
JSON
