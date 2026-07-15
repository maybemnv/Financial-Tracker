#!/bin/bash
set -e

: "${SUPABASE_URL:?ERROR: SUPABASE_URL is not set}"
: "${SUPABASE_ANON_KEY:?ERROR: SUPABASE_ANON_KEY is not set}"
: "${GROQ_API_KEY:?ERROR: GROQ_API_KEY is not set}"

printf "SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\nGROQ_API_KEY=%s\n" \
  "$SUPABASE_URL" "$SUPABASE_ANON_KEY" "$GROQ_API_KEY" > .env

flutter build web
