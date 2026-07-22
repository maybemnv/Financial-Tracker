#!/bin/bash
set -e

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.2}"
FLUTTER_HOME="$HOME/flutter"

if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -d "$FLUTTER_HOME/bin" ]; then
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi
  export PATH="$FLUTTER_HOME/bin:$PATH"
fi

flutter config --no-analytics
flutter config --enable-web

# Browser-safe values only. GEMINI_API_KEY is intentionally NOT built into the
# bundle — it lives as a Supabase function secret (see docs/RUNBOOK.md §4).
: "${SUPABASE_URL:?ERROR: SUPABASE_URL is not set}"
: "${SUPABASE_ANON_KEY:?ERROR: SUPABASE_ANON_KEY is not set}"

printf "SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\n" \
  "$SUPABASE_URL" "$SUPABASE_ANON_KEY" > .env

flutter pub get
flutter build web
