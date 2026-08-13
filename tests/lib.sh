#!/usr/bin/env bash
# Assertion helpers for the dotfiles container harness.

FAILURES=0

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

assert_contains() {   # description, needle, haystack
  case "$3" in
    *"$2"*) pass "$1" ;;
    *)      fail "$1 (missing: $2)" ;;
  esac
}

assert_not_contains() {
  case "$3" in
    *"$2"*) fail "$1 (unexpectedly present: $2)" ;;
    *)      pass "$1" ;;
  esac
}

summary() {
  if [ "$FAILURES" -eq 0 ]; then
    printf '\n\033[32mall checks passed\033[0m\n'; return 0
  fi
  printf '\n\033[31m%d check(s) failed\033[0m\n' "$FAILURES"; return 1
}
