#!/usr/bin/env bash
# Automated release gates (Phase 11.8). Run from a clean checkout before every
# production deploy. Exits non-zero on the first failure so CI can block on it.
#
#   bash scripts/release_gate.sh
set -euo pipefail

cd "$(dirname "$0")/.."
fail() { echo "GATE FAILED: $1" >&2; exit 1; }
ok()   { echo "  ok — $1"; }

echo "[1/6] flutter pub get"
flutter pub get >/dev/null || fail "pub get"
ok "dependencies resolve from a clean checkout"

echo "[2/6] flutter analyze"
flutter analyze || fail "analyze reported issues"
ok "analyze clean"

echo "[3/6] flutter test"
flutter test || fail "tests failed"
ok "all tests pass"

echo "[4/6] release web build WITHOUT GEMINI_API_KEY in the environment"
# The key must live only as a Supabase function secret. A build that needs it is
# a build that would ship it.
if [ -n "${GEMINI_API_KEY:-}" ]; then
  fail "GEMINI_API_KEY is set in this environment — unset it before building"
fi
flutter build web --release >/dev/null || fail "web build"
ok "build/web produced with no Gemini key present"

echo "[5/6] scan build output + sources for leaked secrets"
# service-role JWTs, and any literal Gemini key shape. The anon key is expected
# in the bundle and is safe; the service-role key and Gemini key are not.
LEAKS=0
if grep -rIl --exclude-dir=.git -E 'service_role|serviceRole' build/web lib 2>/dev/null; then
  echo "  ^ 'service_role' appears above"; LEAKS=1
fi
# Google AI Studio keys start AIza; catch any that slipped into the bundle.
if grep -rIl --exclude-dir=.git -E 'AIza[0-9A-Za-z_-]{20,}' build/web lib 2>/dev/null; then
  echo "  ^ a Gemini-shaped key appears above"; LEAKS=1
fi
[ "$LEAKS" -eq 0 ] || fail "a privileged secret was found in the build or source"
ok "no service-role or Gemini secret in build/web or lib"

echo "[6/6] confirm the render-blocking third-party script stayed removed"
if grep -q "corbado" web/index.html; then
  fail "the Corbado CDN script is back in web/index.html"
fi
ok "no blocking third-party startup dependency"

echo
echo "ALL RELEASE GATES PASSED"
echo "Manual checks still required (Phase 11.6 / 11.9): installed-PWA resume on a"
echo "real device, and the owner/anon/expired/non-owner API matrix. See"
echo "docs/RUNBOOK.md and docs/GO_LIVE.md."
