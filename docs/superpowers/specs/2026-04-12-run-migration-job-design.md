# Run Migration Job Design

## Context

MigrationSkippr currently only **skips** migrations (inserts version into `schema_migrations` without executing the migration code). There is no mechanism to actually execute a skipped migration's `up` method. This feature adds an ActiveJob that takes a migration version and database name, then executes the migration asynchronously against the target database — with full audit trail, failure handling, and concurrency protection.

## Requirements

- Execute a skipped migration's `up` method against a named database via ActiveJob
- If the migration was previously skipped, unskip it first (remove from `schema_migrations`), then execute
- On failure: record a `failed` Event, re-skip the migration with the error message as the reason, re-raise the exception
- No automatic retries — operator re-enqueues manually
- Advisory lock to prevent concurrent execution of the same migration
- Async-only API — no synchronous execution path (migrations can take a long time)
- Web UI "Run" button for skipped migrations only
- New Pundit policy action `:run?`

## Design

### Event Model Changes

**File:** `app/models/migration_skippr/event.rb`

Expand status validation from `%w[skipped unskipped]` to `%w[skipped unskipped running completed failed]`.

State transitions for a run operation:

```
skipped → running → completed                          (happy path)
skipped → running → failed + skipped(with error note)   (failure path)
```

On failure, two events are recorded:
1. `failed` event with `note: error.message`
2. `skipped` event with `note: "Auto-skipped after failure: #{error.message}"`

This ensures the migration shows as `skipped` in the UI with the failure reason visible.

### Runner Service

**File:** `lib/migration_skippr/runner.rb`

Internal service class (not part of public API). Only invoked by `RunMigrationJob`.

```ruby
Runner.run!(version, database:, actor: nil)
```

**Execution flow:**

1. **Acquire advisory lock** on `(database, version)`:
   - PostgreSQL: `pg_try_advisory_lock(lock_key)` where `lock_key = Zlib.crc32("migration_skippr_run_#{database}_#{version}")`
   - Non-PG adapters: check for existing `running` Event (best-effort guard)
   - If lock fails: raise `MigrationAlreadyRunningError`

2. **Check current state:**
   - `skipped` → unskip first (call `Skipper.unskip!` to remove from `schema_migrations` and record event)
   - `pending` (no current state, version not in `schema_migrations`) → proceed
   - Already ran/completed → raise `AlreadyRanError`

3. **Record `running` Event**

4. **Load and execute migration:**
   - Find migration file via `DatabaseResolver.migration_paths_for(database)`
   - Require the file, instantiate the migration class
   - Execute against target database connection

5. **On success:** Insert version into `schema_migrations` (same approach as `Skipper.insert_into_schema_migrations`), then record `completed` Event.

6. **On failure:**
   - Record `failed` Event with `note: error.message`
   - Re-skip: insert version into `schema_migrations` + record `skipped` Event with `note: "Auto-skipped after failure: #{error.message}"`
   - Re-raise exception (job marked failed in queue backend)

7. **Release advisory lock** in `ensure` block

### RunMigrationJob

**File:** `app/jobs/migration_skippr/run_migration_job.rb`

```ruby
module MigrationSkippr
  class RunMigrationJob < ApplicationJob
    queue_as :default
    discard_on MigrationAlreadyRunningError, AlreadyRanError

    def perform(version, database_name, actor: nil)
      Runner.run!(version, database: database_name, actor: actor)
    end
  end
end
```

- `discard_on` for concurrency/duplicate errors — no retry
- Migration execution failures re-raise (job marked failed in queue backend)

### Public API

**File:** `lib/migration_skippr.rb`

```ruby
def run(version, database:, actor: nil)
  RunMigrationJob.perform_later(version, database, actor: actor)
end
```

Async-only. Returns the enqueued job instance.

### Error Classes

**File:** `lib/migration_skippr.rb`

```ruby
class MigrationAlreadyRunningError < StandardError; end
class AlreadyRanError < StandardError; end
class MigrationFileNotFoundError < StandardError; end
```

### Controller Changes

**File:** `app/controllers/migration_skippr/migrations_controller.rb`

New `run` action:

```ruby
def run
  authorize!(:run?)
  MigrationSkippr.run(params[:version], database: params[:database_name], actor: @current_actor)
  redirect_to database_path(name: params[:database_name]), notice: "Migration #{params[:version]} enqueued for execution."
end
```

### Route Changes

**File:** `config/routes.rb`

```ruby
member do
  post :skip
  post :unskip
  post :run
end
```

### Policy Changes

**File:** `app/policies/migration_skippr/migration_policy.rb`

Add `run?` method (default: `false`, matching existing deny-all pattern).

### UI Changes

**File:** `app/views/migration_skippr/databases/show.html.erb`

Add a "Run" button next to skipped migrations only. The button posts to the new `run` route.

### Advisory Lock Implementation

**File:** `lib/migration_skippr/runner.rb` (private methods)

```ruby
def self.acquire_lock(connection, database, version)
  lock_key = Zlib.crc32("migration_skippr_run_#{database}_#{version}")
  if postgresql?(connection)
    result = connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
    raise MigrationAlreadyRunningError unless result
  else
    # Best-effort: check for running event
    current = Event.current_state_for(database, version)
    raise MigrationAlreadyRunningError if current&.status == "running"
  end
end

def self.release_lock(connection, database, version)
  if postgresql?(connection)
    lock_key = Zlib.crc32("migration_skippr_run_#{database}_#{version}")
    connection.execute("SELECT pg_advisory_unlock(#{lock_key})")
  end
end

def self.postgresql?(connection)
  connection.adapter_name.downcase.include?("postgresql")
end
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/migration_skippr/runner.rb` | Create |
| `app/jobs/migration_skippr/run_migration_job.rb` | Create |
| `app/models/migration_skippr/event.rb` | Modify (expand status validation) |
| `lib/migration_skippr.rb` | Modify (add `run` method, require runner) |
| `app/controllers/migration_skippr/migrations_controller.rb` | Modify (add `run` action) |
| `config/routes.rb` | Modify (add `run` route) |
| `app/policies/migration_skippr/migration_policy.rb` | Modify (add `run?`) |
| `app/views/migration_skippr/databases/show.html.erb` | Modify (add Run button) |
| `spec/lib/migration_skippr/runner_spec.rb` | Create |
| `spec/jobs/migration_skippr/run_migration_job_spec.rb` | Create |

## Verification

1. **Unit tests:** Runner service tests covering happy path, failure path, advisory lock, already-running, already-ran scenarios
2. **Job tests:** Verify job delegates to Runner, discard_on behavior
3. **Controller tests:** Verify authorization, enqueue, redirect
4. **Integration test:** Full flow — skip a migration, run it via job, verify it executes and records events
5. **Manual test:** In dummy app, skip a migration, click Run, verify it executes
