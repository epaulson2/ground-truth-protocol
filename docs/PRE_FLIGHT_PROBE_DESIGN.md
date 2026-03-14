# Designing Your Pre-Flight Probe

The pre-flight probe is the foundation of the Ground Truth Protocol. It replaces large context documents with a small, factual, current-state summary that is injected into the AI agent's context at session start.

## What to Probe

A probe answers one question: **"What does this project actually look like right now?"**

### Database State

The most common context drift failure is the agent not knowing what database objects exist. Probe for:

- How many tables exist in each schema
- Row counts for key tables (not all tables -- pick 3-5 that indicate "this is a populated, working database")
- Whether migrations are pending
- Connection status (can we connect at all?)

```bash
echo "## Database"
if psql -c "SELECT 1" "$DB_NAME" 2>/dev/null; then
  echo "Connection: OK"
  echo "Tables: $(psql -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" "$DB_NAME")"
  echo "Key counts:"
  psql -t -c "SELECT 'users', count(*) FROM users UNION ALL SELECT 'orders', count(*) FROM orders UNION ALL SELECT 'products', count(*) FROM products" "$DB_NAME" 2>/dev/null
  echo "Pending migrations: $(ls -1 migrations/pending/ 2>/dev/null | wc -l)"
else
  echo "Connection: FAILED"
fi
```

### File System

The agent needs to know what code exists, not the contents of every file. Probe for structure:

```bash
echo "## Project Structure"
echo "Source files:"
find src -name "*.py" -o -name "*.ts" -o -name "*.tsx" | wc -l
echo ""
echo "Key directories:"
find src -maxdepth 2 -type d | sort
echo ""
echo "Config files:"
ls -1 *.yaml *.yml *.json *.toml 2>/dev/null | grep -v node_modules | grep -v package-lock
```

### Running Services

What is currently running? This prevents the agent from suggesting you start things that are already running or set up infrastructure that already exists:

```bash
echo "## Services"
# Systemd services
systemctl list-units --type=service --state=running --no-pager | grep -E 'api|web|redis|postgres|nginx|worker' || echo "No app services found"
echo ""
# Docker containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running"
echo ""
# Listening ports
ss -tlnp 2>/dev/null | grep -E ':(3000|5000|8000|8080|5432|6379)' || echo "No standard app ports listening"
```

### Configured Credentials

Show what is configured (never the values):

```bash
echo "## Credentials"
for key in DATABASE_URL OPENAI_API_KEY ANTHROPIC_API_KEY AWS_ACCESS_KEY_ID STRIPE_SECRET_KEY; do
  if [ -n "${!key:-}" ]; then
    echo "  $key: SET (${#!key} chars)"
  else
    echo "  $key: NOT SET"
  fi
done
echo ""
# Check for .env files
for envfile in .env .env.local .env.production; do
  if [ -f "$envfile" ]; then
    echo "  $envfile: $(wc -l < "$envfile") entries"
  fi
done
```

### Git State

Where are we in the development process?

```bash
echo "## Git"
echo "Branch: $(git branch --show-current)"
echo "Last 5 commits:"
git log --oneline -5
echo "Uncommitted changes: $(git status --short | wc -l) files"
git status --short | head -10
```

## Output Format

### Structured, Not Narrative

The probe output should be structured data, not prose. The agent needs facts it can reference, not a story it needs to interpret.

**Bad (narrative):**
```
The project currently has a PostgreSQL database named mydb which contains 38 tables
in the public schema. The database was set up in January and has been populated with
production data including approximately 50,000 drug records and 1,500 supplement entries.
```

**Good (structured):**
```
## Database
Connection: OK (mydb@127.0.0.1)
Tables: 38 (public schema)
Key counts: drugs=50279, supplements=1503, interactions=10966
Pending migrations: 0
```

### Concise, Not Exhaustive

The probe should be under 2,000 tokens. This is roughly 50-80 lines of structured output. If your probe is longer, you are probing too much.

**Guideline**: If a piece of information would not change the agent's behavior, do not include it. The agent does not need to know the exact schema of every table. It needs to know that tables exist and are populated.

### Timestamped

Always include a timestamp so the agent (and human) can tell when the probe ran:

```bash
echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
```

## Example Probes for Common Stacks

### Python/FastAPI + PostgreSQL

```bash
#!/bin/bash
set -euo pipefail

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_NAME="${DB_NAME:-appdb}"
DB_USER="${DB_USER:-appuser}"

echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

echo ""
echo "## Database ($DB_NAME@$DB_HOST)"
if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" &>/dev/null; then
  echo "Connection: OK"
  PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT 'tables', count(*) FROM information_schema.tables WHERE table_schema='public'
    UNION ALL
    SELECT 'views', count(*) FROM information_schema.views WHERE table_schema='public'
  "
  echo "Alembic head: $(alembic heads 2>/dev/null || echo 'N/A')"
  echo "Pending migrations: $(alembic check 2>&1 | grep -c 'not up to date' || echo '0')"
else
  echo "Connection: FAILED"
fi

echo ""
echo "## Python Environment"
echo "Python: $(python --version 2>&1)"
echo "Packages: $(pip list 2>/dev/null | wc -l)"
echo "FastAPI installed: $(pip show fastapi 2>/dev/null | grep Version || echo 'NO')"

echo ""
echo "## Services"
for svc in api-server celery-worker redis; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo "  $svc: RUNNING"
  else
    echo "  $svc: NOT RUNNING"
  fi
done

echo ""
echo "## API Health"
curl -s http://localhost:8000/health 2>/dev/null | head -1 || echo "API not responding"

echo ""
echo "## Project"
echo "Source files: $(find src -name '*.py' 2>/dev/null | wc -l) Python files"
echo "Tests: $(find tests -name 'test_*.py' 2>/dev/null | wc -l) test files"
echo "Specs: $(ls docs/design/*.md 2>/dev/null | wc -l) design docs"

echo ""
echo "## Git"
echo "Branch: $(git branch --show-current)"
git log --oneline -3

echo ""
echo "=== END PROBE ==="
```

### Node.js/Next.js + PostgreSQL

```bash
#!/bin/bash
set -euo pipefail

echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

echo ""
echo "## Database"
if npx prisma db execute --stdin <<< "SELECT 1" &>/dev/null; then
  echo "Connection: OK"
  echo "Tables:"
  npx prisma db execute --stdin <<< "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename" 2>/dev/null
  echo "Pending migrations: $(npx prisma migrate status 2>&1 | grep -c 'not yet applied' || echo '0')"
else
  echo "Connection: FAILED (check DATABASE_URL)"
fi

echo ""
echo "## Node Environment"
echo "Node: $(node --version)"
echo "Package manager: $(which pnpm >/dev/null && echo pnpm || which yarn >/dev/null && echo yarn || echo npm)"
echo "Dependencies: $(ls node_modules 2>/dev/null | wc -l) packages"

echo ""
echo "## Next.js"
echo "Pages: $(find app -name 'page.tsx' -o -name 'page.ts' 2>/dev/null | wc -l)"
echo "API routes: $(find app/api -name 'route.ts' -o -name 'route.tsx' 2>/dev/null | wc -l)"
echo "Components: $(find components -name '*.tsx' 2>/dev/null | wc -l)"

echo ""
echo "## Services"
echo "Dev server: $(lsof -i :3000 2>/dev/null && echo 'RUNNING on :3000' || echo 'NOT RUNNING')"
echo "Database: $(lsof -i :5432 2>/dev/null && echo 'RUNNING on :5432' || echo 'NOT RUNNING')"

echo ""
echo "## Git"
echo "Branch: $(git branch --show-current)"
git log --oneline -3

echo ""
echo "=== END PROBE ==="
```

### Django + MySQL

```bash
#!/bin/bash
set -euo pipefail

echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

echo ""
echo "## Database"
if python manage.py dbshell <<< "SELECT 1" &>/dev/null; then
  echo "Connection: OK"
  echo "Tables: $(python manage.py dbshell <<< 'SHOW TABLES' 2>/dev/null | wc -l)"
  echo "Pending migrations:"
  python manage.py showmigrations --list 2>/dev/null | grep '\[ \]' | head -5
  PENDING=$(python manage.py showmigrations --list 2>/dev/null | grep -c '\[ \]' || echo '0')
  echo "Total pending: $PENDING"
else
  echo "Connection: FAILED"
fi

echo ""
echo "## Django"
echo "Python: $(python --version 2>&1)"
echo "Django: $(python -c 'import django; print(django.VERSION)' 2>/dev/null || echo 'NOT INSTALLED')"
echo "Apps: $(python manage.py showmigrations --list 2>/dev/null | grep '^\[' | wc -l)"
echo "URL patterns: $(python -c 'from project.urls import urlpatterns; print(len(urlpatterns))' 2>/dev/null || echo 'N/A')"

echo ""
echo "## Services"
echo "Runserver: $(lsof -i :8000 2>/dev/null && echo 'RUNNING on :8000' || echo 'NOT RUNNING')"
echo "Celery: $(celery -A project inspect active 2>/dev/null && echo 'RUNNING' || echo 'NOT RUNNING')"
echo "MySQL: $(lsof -i :3306 2>/dev/null && echo 'RUNNING on :3306' || echo 'NOT RUNNING')"

echo ""
echo "## Git"
echo "Branch: $(git branch --show-current)"
git log --oneline -3

echo ""
echo "=== END PROBE ==="
```

### Rails + PostgreSQL

```bash
#!/bin/bash
set -euo pipefail

echo "=== GROUND TRUTH PROBE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

echo ""
echo "## Database"
if bundle exec rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" &>/dev/null; then
  echo "Connection: OK"
  echo "Tables: $(bundle exec rails runner "puts ActiveRecord::Base.connection.tables.count" 2>/dev/null)"
  echo "Pending migrations: $(bundle exec rails db:migrate:status 2>/dev/null | grep -c 'down' || echo '0')"
  echo "Schema version: $(bundle exec rails runner "puts ActiveRecord::Migrator.current_version" 2>/dev/null)"
else
  echo "Connection: FAILED"
fi

echo ""
echo "## Rails"
echo "Ruby: $(ruby --version | cut -d' ' -f2)"
echo "Rails: $(bundle exec rails version 2>/dev/null || echo 'N/A')"
echo "Models: $(ls app/models/*.rb 2>/dev/null | wc -l)"
echo "Controllers: $(ls app/controllers/*_controller.rb 2>/dev/null | wc -l)"
echo "Routes: $(bundle exec rails routes 2>/dev/null | wc -l)"

echo ""
echo "## Services"
echo "Puma: $(lsof -i :3000 2>/dev/null && echo 'RUNNING on :3000' || echo 'NOT RUNNING')"
echo "Sidekiq: $(pgrep -f sidekiq >/dev/null && echo 'RUNNING' || echo 'NOT RUNNING')"
echo "PostgreSQL: $(lsof -i :5432 2>/dev/null && echo 'RUNNING on :5432' || echo 'NOT RUNNING')"

echo ""
echo "## Git"
echo "Branch: $(git branch --show-current)"
git log --oneline -3

echo ""
echo "=== END PROBE ==="
```

## How to Keep Probes Fast (< 5 seconds)

1. **Use `count(*)` not `SELECT *`.** You need to know how many rows exist, not what they contain.
2. **Limit output.** Use `| head -10` or `LIMIT 5` for any query that might return many rows.
3. **Skip slow checks.** If a service takes 3 seconds to respond to a health check, skip it or use a timeout: `timeout 2 curl -s http://localhost:8000/health`.
4. **Cache nothing.** The probe must always query live state. Caching defeats the purpose.
5. **Parallelize independent checks.** Database, service, and git checks are independent -- run them concurrently if needed.

```bash
# Parallel probing (for slow environments)
{
  echo "## Database" && psql -c "\dt" mydb 2>/dev/null | wc -l
} &
{
  echo "## Services" && systemctl list-units --state=running | grep myapp
} &
{
  echo "## Git" && git log --oneline -3
} &
wait
```

## What NOT to Probe

Avoid information overload. The probe should answer common questions, not anticipate every possible question.

| Do Not Probe | Why |
|-------------|-----|
| Full table schemas | Too verbose; agent can query these when needed |
| File contents | The agent can read files on demand |
| All environment variables | Most are irrelevant to the current task |
| Historical data | The agent needs current state, not history |
| Performance metrics | Relevant for monitoring, not for coding sessions |
| Test results | Tests should run as part of the workflow, not the probe |

The probe answers: "What exists?" It does not answer: "How does it work?" or "Is it healthy?" or "What happened yesterday?"

## Probe Maintenance

The probe should evolve as your project evolves:

- **Add a check** when a new failure mode reveals a missing piece of state (e.g., the agent did not know about a new microservice -- add it to the service check)
- **Remove a check** when it consistently produces the same output and never changes the agent's behavior
- **Reorder checks** to put the most commonly referenced information first (high-attention position)

Review the probe quarterly. If it has grown past 100 lines of script or 2,000 tokens of output, it is doing too much.
