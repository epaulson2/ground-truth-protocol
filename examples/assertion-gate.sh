#!/bin/bash
# Ground Truth Protocol — Assertion Gate
# Generic assertion gate that checks pre-conditions before actions.
#
# Usage: ./assertion-gate.sh <gate_type> <resource_name> [extra_args...]
#
# Gate types:
#   database   — Assert database does not exist before CREATE DATABASE
#   table      — Assert table does not exist before CREATE TABLE
#   file       — Assert file does not exist before creating
#   service    — Assert service is not running before starting
#   docker     — Assert container does not exist before creating
#   env        — Assert required env vars are set before deployment
#   references — Assert no references exist before deleting code
#
# Exit codes:
#   0 — Assertion passed, proceed with action
#   1 — Assertion failed, action should be blocked

set -euo pipefail

GATE_TYPE="${1:?Usage: assertion-gate.sh <type> <name> [args...]}"
RESOURCE_NAME="${2:?Usage: assertion-gate.sh <type> <name> [args...]}"

# Configuration
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-appuser}"
LOG_DIR="${GROUND_TRUTH_LOG:-.ground-truth/gate-log}"

# Logging
mkdir -p "$LOG_DIR"
log_gate() {
  local result="$1"
  local details="$2"
  echo "$(date -Iseconds) | $GATE_TYPE | $RESOURCE_NAME | $result | $details" >> "$LOG_DIR/gates.log"
}

case "$GATE_TYPE" in

  database)
    if psql -h "$DB_HOST" -U "$DB_USER" -d "$RESOURCE_NAME" -c "SELECT 1" &>/dev/null; then
      TABLE_COUNT=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$RESOURCE_NAME" -t -c \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" | tr -d ' ')
      echo "GATE BLOCKED: Database '$RESOURCE_NAME' already exists with $TABLE_COUNT tables."
      echo "ACTION: Query the existing database instead of creating a new one."
      log_gate "BLOCKED" "Database exists with $TABLE_COUNT tables"
      exit 1
    fi
    echo "GATE PASSED: Database '$RESOURCE_NAME' does not exist."
    log_gate "PASSED" "Database does not exist"
    ;;

  table)
    DB="${3:-$RESOURCE_NAME}"
    TABLE="$RESOURCE_NAME"
    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB" -c "SELECT 1 FROM $TABLE LIMIT 0" &>/dev/null; then
      ROW_COUNT=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB" -t -c "SELECT count(*) FROM $TABLE" | tr -d ' ')
      echo "GATE BLOCKED: Table '$TABLE' already exists in database '$DB' with $ROW_COUNT rows."
      echo "ACTION: Use the existing table. If you need to modify it, use ALTER TABLE."
      log_gate "BLOCKED" "Table exists with $ROW_COUNT rows"
      exit 1
    fi
    echo "GATE PASSED: Table '$TABLE' does not exist in database '$DB'."
    log_gate "PASSED" "Table does not exist"
    ;;

  file)
    if [ -f "$RESOURCE_NAME" ]; then
      LINE_COUNT=$(wc -l < "$RESOURCE_NAME")
      echo "GATE BLOCKED: File '$RESOURCE_NAME' already exists ($LINE_COUNT lines)."
      echo "ACTION: Edit the existing file instead of creating a new one."
      log_gate "BLOCKED" "File exists with $LINE_COUNT lines"
      exit 1
    fi
    echo "GATE PASSED: File '$RESOURCE_NAME' does not exist."
    log_gate "PASSED" "File does not exist"
    ;;

  service)
    if systemctl is-active --quiet "$RESOURCE_NAME" 2>/dev/null; then
      echo "GATE BLOCKED: Service '$RESOURCE_NAME' is already running."
      echo "ACTION: Use the existing service. To reconfigure, use systemctl restart."
      log_gate "BLOCKED" "Service is running"
      exit 1
    fi
    echo "GATE PASSED: Service '$RESOURCE_NAME' is not running."
    log_gate "PASSED" "Service not running"
    ;;

  docker)
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${RESOURCE_NAME}$"; then
      echo "GATE BLOCKED: Docker container '$RESOURCE_NAME' is already running."
      echo "ACTION: Use the existing container. To recreate, stop it first."
      log_gate "BLOCKED" "Container is running"
      exit 1
    fi
    echo "GATE PASSED: Docker container '$RESOURCE_NAME' is not running."
    log_gate "PASSED" "Container not running"
    ;;

  env)
    # Check that required environment variables are set
    # Usage: ./assertion-gate.sh env "VAR1,VAR2,VAR3"
    MISSING=""
    IFS=',' read -ra VARS <<< "$RESOURCE_NAME"
    for var in "${VARS[@]}"; do
      var=$(echo "$var" | tr -d ' ')
      if [ -z "${!var:-}" ]; then
        MISSING="$MISSING $var"
      fi
    done
    if [ -n "$MISSING" ]; then
      echo "GATE BLOCKED: Required environment variables not set:$MISSING"
      echo "ACTION: Set these variables before proceeding."
      log_gate "BLOCKED" "Missing env vars:$MISSING"
      exit 1
    fi
    echo "GATE PASSED: All required environment variables are set."
    log_gate "PASSED" "All env vars set"
    ;;

  references)
    # Check that no references to a symbol exist before deleting it
    # Usage: ./assertion-gate.sh references "symbol_name" "file_being_deleted"
    SYMBOL="$RESOURCE_NAME"
    FILE="${3:-.}"
    REFS=$(grep -rn "$SYMBOL" . \
      --include="*.py" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
      2>/dev/null \
      | grep -v "$FILE" \
      | grep -v "node_modules" \
      | grep -v ".git" \
      | head -10)
    if [ -n "$REFS" ]; then
      REF_COUNT=$(echo "$REFS" | wc -l)
      echo "GATE BLOCKED: Symbol '$SYMBOL' has $REF_COUNT references outside '$FILE'."
      echo ""
      echo "References found:"
      echo "$REFS"
      echo ""
      echo "ACTION: Remove or update all references before deleting."
      log_gate "BLOCKED" "$REF_COUNT external references"
      exit 1
    fi
    echo "GATE PASSED: No external references to '$SYMBOL' found."
    log_gate "PASSED" "No external references"
    ;;

  *)
    echo "ERROR: Unknown gate type '$GATE_TYPE'"
    echo "Valid types: database, table, file, service, docker, env, references"
    exit 2
    ;;
esac

exit 0
