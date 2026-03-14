#!/bin/bash
# Ground Truth Protocol — Pre-Flight Probe
# Run at the start of every AI session.
# Output is injected into AI context automatically.
#
# Usage: ./pre-flight-probe.sh
# Configure as a session-start hook in your AI tool.
#
# Customize the sections below for your project's stack.
# Keep total output under 2,000 tokens (~80 lines).
# Keep execution time under 5 seconds.

set -euo pipefail

# Configuration — customize these for your project
DB_NAME="${DB_NAME:-mydb}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-appuser}"
APP_SERVICE_PATTERNS="api|web|redis|worker|nginx"
REQUIRED_ENV_VARS="DATABASE_URL API_KEY SECRET_KEY"
SRC_DIR="${SRC_DIR:-src}"
SPEC_DIR="${SPEC_DIR:-docs/design}"

echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# --- Database State ---
echo ""
echo "## Database ($DB_NAME@$DB_HOST)"
if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" &>/dev/null; then
  echo "Connection: OK"
  TABLE_COUNT=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null | tr -d ' ')
  echo "Tables: $TABLE_COUNT (public schema)"

  # Show key table row counts (customize these table names)
  echo "Key tables:"
  psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT tablename, n_live_tup
    FROM pg_stat_user_tables
    WHERE n_live_tup > 0
    ORDER BY n_live_tup DESC
    LIMIT 5;
  " 2>/dev/null || echo "  (stats not available)"
else
  echo "Connection: FAILED"
fi

# --- Running Services ---
echo ""
echo "## Services"
if command -v systemctl &>/dev/null; then
  systemctl list-units --type=service --state=running --no-pager 2>/dev/null \
    | grep -E "$APP_SERVICE_PATTERNS" \
    || echo "No app services found via systemctl"
fi

if command -v docker &>/dev/null && docker info &>/dev/null; then
  echo "Docker containers:"
  docker ps --format "  {{.Names}}: {{.Status}} ({{.Ports}})" 2>/dev/null \
    || echo "  No containers running"
fi

# --- Git State ---
echo ""
echo "## Git"
if [ -d .git ]; then
  echo "Branch: $(git branch --show-current 2>/dev/null || echo 'detached')"
  echo "Recent commits:"
  git log --oneline -3 2>/dev/null
  UNCOMMITTED=$(git status --short 2>/dev/null | wc -l)
  echo "Uncommitted changes: $UNCOMMITTED files"
  if [ "$UNCOMMITTED" -gt 0 ]; then
    git status --short 2>/dev/null | head -5
  fi
else
  echo "Not a git repository"
fi

# --- Environment ---
echo ""
echo "## Configured Credentials"
for key in $REQUIRED_ENV_VARS; do
  if [ -n "${!key:-}" ]; then
    echo "  $key: SET (${#!key} chars)"
  else
    echo "  $key: NOT SET"
  fi
done

# Check for .env files
for envfile in .env .env.local .env.production .env.development; do
  if [ -f "$envfile" ]; then
    echo "  $envfile: $(wc -l < "$envfile") entries"
  fi
done

# --- Project Structure ---
echo ""
echo "## Project Structure"
if [ -d "$SRC_DIR" ]; then
  PY_COUNT=$(find "$SRC_DIR" -name "*.py" 2>/dev/null | wc -l)
  TS_COUNT=$(find "$SRC_DIR" -name "*.ts" -o -name "*.tsx" 2>/dev/null | wc -l)
  JS_COUNT=$(find "$SRC_DIR" -name "*.js" -o -name "*.jsx" 2>/dev/null | wc -l)
  echo "Source files: ${PY_COUNT} Python, ${TS_COUNT} TypeScript, ${JS_COUNT} JavaScript"
fi

if [ -d "$SPEC_DIR" ]; then
  SPEC_COUNT=$(ls -1 "$SPEC_DIR"/*.md 2>/dev/null | wc -l)
  echo "Spec documents: $SPEC_COUNT in $SPEC_DIR"
fi

TEST_COUNT=$(find . -name "test_*.py" -o -name "*.test.ts" -o -name "*.test.tsx" -o -name "*.spec.ts" 2>/dev/null | grep -v node_modules | wc -l)
echo "Test files: $TEST_COUNT"

echo ""
echo "=== END GROUND TRUTH PROBE ==="
