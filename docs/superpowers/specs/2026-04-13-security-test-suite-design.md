# Security Test Suite Design

**Issue:** [#9 — Create test suite attempting to sql inject](https://github.com/jrgifford/migration_skippr/issues/9)
**Date:** 2026-04-13

## Goals

1. **Regression safety net** — Ensure future code changes don't introduce injection vulnerabilities
2. **Audit evidence** — Demonstrate the app has been tested against OWASP-style attacks
3. **Mutation-verified** — Prove security tests actually catch real regressions via Mutant

## Scope

Five vulnerability classes tested across two endpoint groups:

| Vulnerability Class | Migrations Endpoints | Databases Endpoints |
|--------------------|--------------------|-------------------|
| SQL Injection | create, skip, unskip, run | index, show |
| CSRF | create, skip, unskip, run | index, show |
| XSS | note, version, flash messages | database name display |
| Authorization Bypass | default + restrictive policy | default + restrictive policy |
| Input Validation | traversal, null bytes, overflow, unicode | traversal, null bytes, overflow, unicode |

## Current Security Posture

The codebase is already well-protected. This suite proves that protection with tests:

- All raw SQL uses `connection.quote()` (parameterized)
- CSRF protection enabled globally via `protect_from_forgery with: :exception`
- ERB auto-escaping on all template output (no `raw` or `html_safe` calls)
- Pundit authorization enforced on every controller action
- Database names validated against `DatabaseResolver.writable_databases` allowlist
- Version params stripped and checked for blank

## File Structure

```
spec/security/
├── migrations/
│   ├── sql_injection_spec.rb
│   ├── csrf_spec.rb
│   ├── xss_spec.rb
│   ├── authorization_bypass_spec.rb
│   └── input_validation_spec.rb
├── databases/
│   ├── sql_injection_spec.rb
│   ├── csrf_spec.rb
│   ├── xss_spec.rb
│   ├── authorization_bypass_spec.rb
│   └── input_validation_spec.rb
└── support/
    ├── security_payloads.rb
    └── restrictive_policy.rb
```

## Shared Payloads Module

`spec/security/support/security_payloads.rb` defines reusable attack strings:

```ruby
module SecurityPayloads
  SQL_PAYLOADS = [
    "'; DROP TABLE schema_migrations;--",
    "1 OR 1=1",
    "' UNION SELECT version FROM schema_migrations--",
    "1; SELECT pg_sleep(5)--",
    "' AND 1=CAST((SELECT version FROM schema_migrations LIMIT 1) AS int)--",
  ].freeze

  XSS_PAYLOADS = [
    "<script>alert(1)</script>",
    "<img onerror=alert(1) src=x>",
    "javascript:alert(1)",
    "' onmouseover='alert(1)'",
    "<svg/onload=alert(1)>",
    "#{}<img src=x onerror=alert(1)>",
  ].freeze

  TRAVERSAL_PAYLOADS = [
    "../../../etc/passwd",
    "....//....//etc/passwd",
    "..%2f..%2f..%2fetc/passwd",
    "%00",
    "version\x00.rb",
  ].freeze

  OVERFLOW_PAYLOADS = [
    "A" * 10_000,
    "\u202E" * 100,       # RTL override
    "\u200B" * 1_000,     # zero-width space
    "\n" * 1_000,
  ].freeze
end
```

Adding a new payload to any array automatically expands coverage across all specs that use it.

## Restrictive Test Policy

`spec/security/support/restrictive_policy.rb` defines a realistic partial-allow policy:

```ruby
class RestrictivePolicy < MigrationSkippr::MigrationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def skip?
    true
  end

  def unskip?
    true
  end

  def run?
    false  # Explicitly denied
  end

  def create?
    true
  end
end
```

## Spec Details

### SQL Injection

**`migrations/sql_injection_spec.rb`** — Tests all four POST endpoints (create, skip, unskip, run) with `SQL_PAYLOADS` in `version`, `note`, and `database_name` params.

Assertions:
- No 500 errors (no SQL syntax errors leak through)
- Injected SQL not executed (schema_migrations table intact, no extra/missing records)
- Application handles input gracefully (redirect or controlled error)

**`databases/sql_injection_spec.rb`** — Tests GET index and show with `SQL_PAYLOADS` in `:name` route param.

Assertions:
- Database resolver rejects unknown names without passing them to queries
- No 500 errors

### CSRF

**`migrations/csrf_spec.rb`** — All four POST endpoints called without CSRF token.

Assertions:
- Returns `422 Unprocessable Entity` or raises `ActionController::InvalidAuthenticityToken`
- No state change occurs (no records created/modified)

**`databases/csrf_spec.rb`** — Verifies GET endpoints are idempotent: no records created, no state changes. Also confirms that if any database endpoint were accidentally changed to POST, CSRF protection would apply. This file is lighter than the migrations CSRF spec since databases only has GET endpoints.

### XSS

**`migrations/xss_spec.rb`** — Creates migrations with `XSS_PAYLOADS` in `note` and `version` fields, then renders the database show page.

Assertions:
- Payloads appear HTML-escaped in response body (e.g., `&lt;script&gt;`)
- Raw payload string does NOT appear unescaped in HTML output
- Flash messages with injected content are also escaped

**`databases/xss_spec.rb`** — Tests database name display on index page. Database names are validated against the resolver's allowlist, so they should be rejected before rendering.

Assertions:
- No unescaped output even if validation were bypassed

### Authorization Bypass

**`migrations/authorization_bypass_spec.rb`** — Two policy contexts:

1. **Default deny-all policy** — All four actions return 403/redirect with denial message
2. **Restrictive policy** — Skip and unskip succeed, run is blocked. Verifies policy is checked per-action.

**`databases/authorization_bypass_spec.rb`** — Same two-policy approach for index and show.

### Input Validation

**`migrations/input_validation_spec.rb`** — Tests with `TRAVERSAL_PAYLOADS` and `OVERFLOW_PAYLOADS` in `version`, `note`, and `database_name` params.

Assertions:
- No 500 errors
- No unexpected file access
- Graceful handling (redirect with error or safe rejection)

**`databases/input_validation_spec.rb`** — Same payload categories against route params for index/show.

## Mutation Testing

### Gem

`mutant` and `mutant-rspec` added to the Gemfile test group.

### Target Classes

| Class | Reason |
|-------|--------|
| `MigrationSkippr::Skipper` | Raw SQL with `connection.quote()` — mutation could introduce injection |
| `MigrationSkippr::Runner` | Raw SQL queries + advisory lock logic |
| `MigrationSkippr::DatabaseResolver` | Database name validation — mutation could allow arbitrary names |
| `MigrationSkippr::MigrationsController` | Parameter handling, authorization calls |
| `MigrationSkippr::DatabasesController` | Parameter handling, authorization calls |

### What It Proves

If Mutant removes `connection.quote()` from a query, the SQL injection specs must fail (killing the mutant). If they don't, the tests aren't catching unsafe query construction. Same logic applies to authorization (`authorize!` calls), input validation (`strip`/`blank?` checks), and parameter handling.

### Configuration

`.mutant.yml` at project root scopes Mutant to the target classes and security specs.

## CI Integration

### Rake Tasks

- `rake spec:security` — Runs `spec/security/` only
- `rake mutant:security` — Runs Mutant against target classes using security specs

### Pipeline

- **Every push:** `rake spec:security` runs alongside existing test suite
- **PRs only:** `rake mutant:security` runs as a separate job (heavier, slower)

Both must pass for CI to go green. A surviving mutant in a security-critical class blocks the PR.

## Test Style

Descriptive `context`/`it` blocks that serve as audit documentation:

```ruby
RSpec.describe "Migrations endpoint - SQL Injection", type: :request do
  include SecurityPayloads

  SecurityPayloads::SQL_PAYLOADS.each do |payload|
    context "when version param is '#{payload.truncate(40)}'" do
      it "does not execute injected SQL" do
        post database_migrations_path(database_name: "primary"),
             params: { version: payload, note: "test" }

        expect(response).not_to have_http_status(:internal_server_error)
        # Verify schema_migrations table is unchanged
      end
    end
  end
end
```
