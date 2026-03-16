# Acceptance Gate Reference

Acceptance gates are YAML-defined verification criteria that run against the live system. They are the foundation of the Hold Point system -- without gates, there is nothing to verify.

---

## Full Schema

```yaml
gate:
  name: string                    # Required. Unique identifier for this gate.
  stage: string                   # Required. Pipeline stage: design | backend | frontend | integration | deploy
  description: string             # Optional. Human-readable description of what this gate verifies.
  pass_threshold: float           # Optional. Fraction of criteria that must pass (0.0-1.0). Default: 1.0 (all must pass).

  criteria:
    - name: string                # Required. Unique identifier for this criterion within the gate.
      type: enum                  # Required. One of: file_exists | command | http | sql
      description: string         # Optional. What this criterion verifies.
      # ... type-specific fields (see below)

  status_rules:                   # Optional. Maps gate results to pipeline states.
    all_pass: GATES_PASSING       # Default. State when all criteria pass.
    some_fail: IN_PROGRESS        # Default. State when some criteria fail.
    none_run: GATES_DEFINED       # Default. State when criteria exist but have not been run.
```

---

## Gate Types

### `file_exists` -- Verify a file exists with expected content

Checks that a file exists on disk and optionally verifies its contents.

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | Yes | File path (relative to project root) |
| `contains` | string | No | String or regex that file content must include |
| `not_contains` | string | No | String or regex that file content must NOT include |
| `min_lines` | int | No | Minimum number of lines in the file |
| `max_lines` | int | No | Maximum number of lines in the file |

**Example: Verify a migration file exists and is non-trivial**

```yaml
gate:
  name: database-migration
  stage: backend
  criteria:
    - name: migration-file-exists
      type: file_exists
      description: Alembic migration file exists for the users table
      path: alembic/versions/*_create_users_table.py
      contains: "op.create_table.*users"
      min_lines: 20

    - name: model-file-exists
      type: file_exists
      description: SQLAlchemy model file exists
      path: src/models/user.py
      contains: "class User"
      not_contains: "pass  # TODO"
      min_lines: 15
```

**When to use:** Verifying that implementation files exist and are not stubs. The `min_lines` check catches the common failure where the agent creates a file with a class definition and a `pass` statement.

---

### `command` -- Run a shell command and verify the result

Executes a shell command and checks the exit code and optionally the output.

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run` | string | Yes | Shell command to execute |
| `expect_exit` | int | No | Expected exit code (default: 0) |
| `expect_output` | string | No | Regex the stdout must match |
| `not_expect_output` | string | No | Regex the stdout must NOT match |
| `timeout` | int | No | Timeout in seconds (default: 30) |
| `env` | map | No | Additional environment variables |

**Example: Verify tests pass and code compiles**

```yaml
gate:
  name: code-quality
  stage: backend
  criteria:
    - name: tests-pass
      type: command
      description: All unit tests pass
      run: python -m pytest tests/unit/ -v --tb=short
      expect_exit: 0
      timeout: 120

    - name: type-check-passes
      type: command
      description: mypy type checking passes
      run: python -m mypy src/ --ignore-missing-imports
      expect_exit: 0
      timeout: 60

    - name: no-import-errors
      type: command
      description: All imports resolve correctly
      run: python -c "from src.auth.login import LoginHandler; print('OK')"
      expect_exit: 0
      expect_output: "OK"

    - name: password-hashing-works
      type: command
      description: Bcrypt hashing produces valid hash
      run: |
        python -c "
        from src.auth.utils import hash_password, verify_password
        h = hash_password('test123')
        assert verify_password('test123', h), 'Verify failed'
        assert h.startswith('\$2b\$'), 'Not bcrypt'
        print('OK')
        "
      expect_exit: 0
      expect_output: "OK"
```

**When to use:** Anything that can be verified by running a command: tests, compilation, linting, smoke checks, data validation, script execution. This is the most versatile gate type.

---

### `http` -- Make an HTTP request and verify the response

Makes an HTTP request to a running service and checks the response.

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `method` | string | Yes | HTTP method: GET, POST, PUT, DELETE, PATCH |
| `url` | string | Yes | Full URL to request |
| `headers` | map | No | HTTP headers (key-value pairs) |
| `body` | string | No | Request body (for POST, PUT, PATCH) |
| `expect_status` | int | Yes | Expected HTTP status code |
| `expect_body` | string | No | Regex the response body must match |
| `not_expect_body` | string | No | Regex the response body must NOT match |
| `expect_header` | map | No | Headers the response must include |
| `timeout` | int | No | Request timeout in seconds (default: 10) |

**Example: Verify API endpoints work end-to-end**

```yaml
gate:
  name: auth-api
  stage: integration
  criteria:
    - name: health-endpoint
      type: http
      description: API health check returns 200
      method: GET
      url: http://localhost:8000/health
      expect_status: 200
      expect_body: '"status":\s*"healthy"'

    - name: login-endpoint
      type: http
      description: Login returns JWT token
      method: POST
      url: http://localhost:8000/api/auth/login
      headers:
        Content-Type: application/json
      body: '{"email": "test@example.com", "password": "testpass123"}'
      expect_status: 200
      expect_body: '"token":\s*"eyJ'

    - name: protected-endpoint-rejects-anonymous
      type: http
      description: Protected endpoint returns 401 without token
      method: GET
      url: http://localhost:8000/api/users/me
      expect_status: 401

    - name: protected-endpoint-accepts-token
      type: http
      description: Protected endpoint returns user data with valid token
      method: GET
      url: http://localhost:8000/api/users/me
      headers:
        Authorization: "Bearer ${AUTH_TOKEN}"
      expect_status: 200
      expect_body: '"email":\s*"test@example.com"'
```

**When to use:** Verifying that API endpoints, web pages, and services respond correctly. This tests the running system, not the code -- which is the entire point. A file can exist with the right code and still not work when deployed.

---

### `sql` -- Execute a SQL query and verify the result

Runs a SQL query against a database and checks the result.

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `connection` | string | Yes | Connection string or env var name (e.g., `$DATABASE_URL`) |
| `query` | string | Yes | SQL query to execute |
| `expect_rows` | int | No | Expected number of rows returned |
| `expect_min_rows` | int | No | Minimum number of rows returned |
| `expect_value` | string | No | Expected value in first column of first row |
| `expect_column` | map | No | Column name -> expected value mapping |
| `timeout` | int | No | Query timeout in seconds (default: 10) |

**Example: Verify database schema and data**

```yaml
gate:
  name: database-state
  stage: backend
  criteria:
    - name: users-table-exists
      type: sql
      description: Users table exists with expected columns
      connection: $DATABASE_URL
      query: |
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'users' AND table_schema = 'public'
        ORDER BY ordinal_position
      expect_min_rows: 5

    - name: password-column-is-varchar
      type: sql
      description: Password column is varchar (not text, not int)
      connection: $DATABASE_URL
      query: |
        SELECT data_type FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'password_hash'
      expect_rows: 1
      expect_value: "character varying"

    - name: test-user-exists
      type: sql
      description: Test user was seeded correctly
      connection: $DATABASE_URL
      query: |
        SELECT email, is_active FROM users WHERE email = 'test@example.com'
      expect_rows: 1
      expect_column:
        email: "test@example.com"
        is_active: "true"

    - name: indexes-exist
      type: sql
      description: Email index exists for performance
      connection: $DATABASE_URL
      query: |
        SELECT indexname FROM pg_indexes
        WHERE tablename = 'users' AND indexdef LIKE '%email%'
      expect_min_rows: 1
```

**When to use:** Verifying database schema, data integrity, migration results, and seed data. SQL gates test the actual database state, not what the migration file says should exist.

---

## Writing Good Gates

### Test Behavior, Not Filenames

**Bad gate** -- tests that a file exists:
```yaml
- name: auth-handler-exists
  type: file_exists
  path: src/auth/handler.py
```

This passes even if `handler.py` contains nothing but `pass`.

**Good gate** -- tests that the behavior works:
```yaml
- name: auth-handler-works
  type: command
  run: |
    python -c "
    from src.auth.handler import AuthHandler
    handler = AuthHandler()
    result = handler.authenticate('test@example.com', 'testpass')
    assert result.success, f'Auth failed: {result.error}'
    assert result.token is not None, 'No token returned'
    print('OK')
    "
  expect_exit: 0
  expect_output: "OK"
```

### Test the Live System, Not Unit Tests

**Bad gate** -- runs unit tests as verification:
```yaml
- name: auth-tests-pass
  type: command
  run: pytest tests/unit/test_auth.py
```

Unit tests verify the code in isolation. They can pass while the feature is broken in the live system (wrong config, missing wiring, database not migrated).

**Good gate** -- tests the live system:
```yaml
- name: auth-works-live
  type: http
  method: POST
  url: http://localhost:8000/api/auth/login
  body: '{"email": "test@example.com", "password": "testpass"}'
  expect_status: 200
  expect_body: '"token"'
```

### Test Edge Cases, Not Just Happy Paths

**Incomplete gate** -- only tests success:
```yaml
criteria:
  - name: login-works
    type: http
    method: POST
    url: http://localhost:8000/api/auth/login
    body: '{"email": "test@example.com", "password": "testpass"}'
    expect_status: 200
```

**Complete gate** -- tests success and failure:
```yaml
criteria:
  - name: login-succeeds-with-valid-credentials
    type: http
    method: POST
    url: http://localhost:8000/api/auth/login
    body: '{"email": "test@example.com", "password": "testpass"}'
    expect_status: 200
    expect_body: '"token"'

  - name: login-fails-with-wrong-password
    type: http
    method: POST
    url: http://localhost:8000/api/auth/login
    body: '{"email": "test@example.com", "password": "wrongpass"}'
    expect_status: 401

  - name: login-fails-with-missing-fields
    type: http
    method: POST
    url: http://localhost:8000/api/auth/login
    body: '{}'
    expect_status: 422

  - name: login-fails-with-nonexistent-user
    type: http
    method: POST
    url: http://localhost:8000/api/auth/login
    body: '{"email": "nobody@example.com", "password": "testpass"}'
    expect_status: 401
```

### Make Gates Independently Runnable

Each gate should be runnable in isolation without depending on other gates having run first. If gate B depends on gate A's side effects, gate B is fragile and order-dependent.

**Bad** -- depends on another gate's side effect:
```yaml
# Gate A creates the user
- name: create-user
  type: http
  method: POST
  url: http://localhost:8000/api/users
  body: '{"email": "test@example.com"}'
  expect_status: 201

# Gate B depends on Gate A having run
- name: login-user
  type: http
  method: POST
  url: http://localhost:8000/api/auth/login
  body: '{"email": "test@example.com", "password": "testpass"}'
  expect_status: 200
```

**Good** -- uses seed data or setup commands:
```yaml
# Gate uses pre-seeded test data
- name: login-user
  type: http
  description: Uses test user from seed data (see scripts/seed-test-data.sh)
  method: POST
  url: http://localhost:8000/api/auth/login
  body: '{"email": "test@example.com", "password": "testpass"}'
  expect_status: 200
```

---

## `pass_threshold` Configuration

By default, all criteria must pass for the gate to pass (`pass_threshold: 1.0`). You can lower this for gates with optional or aspirational criteria:

```yaml
gate:
  name: performance-benchmarks
  stage: integration
  pass_threshold: 0.8    # 80% of criteria must pass
  criteria:
    - name: p50-under-100ms
      type: command
      run: ./scripts/benchmark.sh --percentile 50 --max 100
    - name: p95-under-500ms
      type: command
      run: ./scripts/benchmark.sh --percentile 95 --max 500
    - name: p99-under-1000ms
      type: command
      run: ./scripts/benchmark.sh --percentile 99 --max 1000
```

**Use `pass_threshold < 1.0` sparingly.** The default of 1.0 exists for a reason -- if a criterion is not important enough to require, it should not be a criterion. Lower thresholds are appropriate for performance benchmarks, coverage targets, and other metrics that have acceptable ranges.

---

## `status_rules` Mapping

Status rules map gate results to pipeline states:

```yaml
status_rules:
  all_pass: GATES_PASSING       # All criteria passed
  some_fail: IN_PROGRESS        # At least one criterion failed
  none_run: GATES_DEFINED       # Gate exists but has not been run
```

You can customize these for non-standard pipelines:

```yaml
status_rules:
  all_pass: READY_FOR_REVIEW
  some_fail: NEEDS_WORK
  none_run: CRITERIA_PENDING
```

---

## Gate Organization

### One Gate Per Feature

Each feature or work item gets its own YAML file. Do not combine unrelated features into a single gate.

```
.hold-point/gates/
  auth-login.yaml         # Login feature
  auth-registration.yaml  # Registration feature
  auth-password-reset.yaml # Password reset feature
  user-profile.yaml       # User profile feature
  payment-checkout.yaml   # Payment checkout feature
```

### Stage-Based Organization

For larger projects, organize gates by pipeline stage:

```
.hold-point/gates/
  design/
    auth-spec-complete.yaml
  backend/
    auth-api.yaml
    auth-models.yaml
  frontend/
    auth-ui.yaml
    auth-forms.yaml
  integration/
    auth-end-to-end.yaml
  deploy/
    auth-production-ready.yaml
```

---

## Common Gate Recipes

### "Feature is wired into the application"

The most common agent failure: code exists but is not connected to the application.

```yaml
gate:
  name: feature-wired
  stage: integration
  criteria:
    - name: route-registered
      type: command
      description: Route is registered in the application
      run: |
        python -c "
        from src.app import create_app
        app = create_app()
        routes = [rule.rule for rule in app.url_map.iter_rules()]
        assert '/api/auth/login' in routes, f'Route not found. Routes: {routes}'
        print('OK')
        "
      expect_exit: 0

    - name: endpoint-responds
      type: http
      description: Endpoint responds (not 404)
      method: POST
      url: http://localhost:8000/api/auth/login
      body: '{"email": "x", "password": "x"}'
      expect_status: [401, 422]  # Any non-404 response means it is wired
```

### "Database migration applied"

```yaml
gate:
  name: migration-applied
  stage: backend
  criteria:
    - name: table-exists
      type: sql
      connection: $DATABASE_URL
      query: "SELECT 1 FROM information_schema.tables WHERE table_name = 'users'"
      expect_rows: 1

    - name: columns-correct
      type: sql
      connection: $DATABASE_URL
      query: |
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'users'
        ORDER BY ordinal_position
      expect_min_rows: 5
```

### "Service starts and stays running"

```yaml
gate:
  name: service-stable
  stage: deploy
  criteria:
    - name: service-starts
      type: command
      run: systemctl start myapp && sleep 2 && systemctl is-active myapp
      expect_exit: 0

    - name: service-responds
      type: http
      method: GET
      url: http://localhost:8000/health
      expect_status: 200
      timeout: 5

    - name: no-error-logs
      type: command
      description: No ERROR-level logs in the last 10 seconds
      run: |
        journalctl -u myapp --since "10 seconds ago" --no-pager | grep -c "ERROR" | grep -q "^0$"
      expect_exit: 0
```

### "Frontend component renders"

```yaml
gate:
  name: login-page
  stage: frontend
  criteria:
    - name: page-loads
      type: http
      method: GET
      url: http://localhost:3000/login
      expect_status: 200
      expect_body: '<form'

    - name: component-exists
      type: file_exists
      path: src/components/LoginForm.tsx
      contains: "export.*LoginForm"
      min_lines: 20

    - name: e2e-test-passes
      type: command
      run: npx playwright test tests/e2e/login.spec.ts --reporter=list
      expect_exit: 0
      timeout: 60
```
