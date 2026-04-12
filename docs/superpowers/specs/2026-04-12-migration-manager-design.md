# MigrationSkippr — Design Spec

A Ruby on Rails gem (engine) for managing database migrations across multiple databases. Allows marking migrations as "skipped" so they appear as already-run to Rails, then unskipping them later to run during off-hours or low-contention windows.

## Requirements

- Rails 7.1+ only
- Multi-database aware: works with single-DB and multi-DB apps
- Does NOT execute migrations — host app handles that
- Append-only audit trail for all state changes
- Self-contained web UI (own layout, CSS, no host app dependencies)
- Pundit-based authorization with role-based permissions (view vs. manage)
- Supports adding arbitrary migration versions not yet on disk (for pre-registering upcoming migrations)
- 100% test coverage, CI matrix across Ruby/Rails/DB adapters

## Data Model

### `migration_skippr_events` (append-only)

| Column | Type | Purpose |
|--------|------|---------|
| `id` | bigint PK | — |
| `database_name` | string, not null | Which DB config (e.g., `"primary"`, `"analytics"`) |
| `version` | string, not null | Migration version timestamp (e.g., `"20240312150000"`) |
| `status` | string, not null | `"skipped"` or `"unskipped"` |
| `actor` | string, nullable | Who made the change (from configured lambda) |
| `note` | text, nullable | Optional reason |
| `created_at` | datetime, not null | When it happened |

**Index:** `[database_name, version, status, created_at]`

**Current state resolution:** The most recent row per `[database_name, version]` (by `created_at` descending) is the current state. No rows are ever updated or deleted.

## Skip/Unskip Mechanism

### Skip

1. Insert an event row with `status: "skipped"` into `migration_skippr_events` (on the tracking database)
2. Insert the version into the target database's `schema_migrations` table (using that database's connection)

### Unskip

1. Insert an event row with `status: "unskipped"` into `migration_skippr_events`
2. Remove the version from the target database's `schema_migrations` table

Both writes happen sequentially. If step 2 fails, it fails loudly — no reconciliation machinery. This operation is infrequent enough that simple error handling is sufficient.

## Database Discovery

1. Read `ActiveRecord::Base.configurations` for the current Rails environment
2. Filter out configs where `replica: true` or `database_tasks: false`
3. Present each as a named database in the UI

For single-DB apps, this finds `"primary"`. For multi-DB apps, it finds all writable databases.

## Configuration

```ruby
MigrationSkippr.configure do |config|
  # Required for audit trail: lambda receiving the request, returns actor string
  config.current_actor = ->(request) { request.env["warden"].user&.email }

  # Which database holds the migration_skippr_events table (default: :primary)
  config.tracking_database = :primary

  # Override the default Pundit policy class (default: "MigrationSkippr::MigrationPolicy")
  config.authorization_policy = "MigrationSkippr::MigrationPolicy"
end
```

The gem never accesses `current_user` directly. The `current_actor` lambda is optional — if not configured, `actor` is recorded as `nil`.

## Public Ruby API

```ruby
# Skip a migration
MigrationSkippr.skip("20240312150000", database: "primary", actor: "jrg", note: "slow-roll batch 1")

# Unskip a migration
MigrationSkippr.unskip("20240312150000", database: "primary", actor: "jrg", note: "ready to run")

# Query current state
MigrationSkippr.status(database: "primary")
# => [{ version: "20240312150000", status: "skipped", actor: "jrg", ... }, ...]

# Query events for a specific migration
MigrationSkippr.history("20240312150000", database: "primary")
# => [{ status: "skipped", actor: "jrg", created_at: ..., note: "..." }, ...]
```

This API is used by the UI controllers and is available for scripting bulk operations.

## Web UI

### Mounting

```ruby
# host app's config/routes.rb
mount MigrationSkippr::Engine, at: "/migration_skippr"
```

### Pages

1. **Dashboard** (`GET /migration_skippr`) — lists all discovered databases with counts of pending and skipped migrations
2. **Database detail** (`GET /migration_skippr/databases/:name`) — shows all migrations for that database:
   - **On disk + ran** — completed, no action
   - **On disk + pending** — can skip
   - **On disk + skipped** — can unskip
   - **Not on disk + skipped** — pre-registered, waiting for deploy
   - **Not on disk + unskipped** — was pre-registered, then unskipped
3. **Add migration form** — on the database detail page, a form to add a single version with an optional note and mark it as skipped

### Actions

- `POST /migration_skippr/databases/:name/migrations/:version/skip` — skip a migration
- `POST /migration_skippr/databases/:name/migrations/:version/unskip` — unskip a migration
- `POST /migration_skippr/databases/:name/migrations` — add an arbitrary version (marked as skipped)

### Frontend

Server-rendered ERB with Turbo/Stimulus for interactivity. Self-contained layout with its own CSS — no dependency on host app styling. Similar to Sidekiq's web UI approach.

## Authorization (Pundit)

The gem ships a default `MigrationSkippr::MigrationPolicy`:

```ruby
module MigrationSkippr
  class MigrationPolicy
    attr_reader :actor, :record

    def initialize(actor, record)
      @actor = actor
      @record = record
    end

    # Viewing migrations and databases
    def index?  = false
    def show?   = false

    # Managing skip state
    def skip?   = false
    def unskip? = false
    def create? = false  # adding arbitrary versions
  end
end
```

Default-deny. The host app overrides this policy to implement its own authorization logic. The gem's controllers call Pundit in the standard way, using the actor from the configured `current_actor` lambda (not `current_user`).

## Gem Structure

```
migration_skippr/
├── app/
│   ├── controllers/migration_skippr/
│   │   ├── application_controller.rb
│   │   ├── databases_controller.rb      # dashboard + detail
│   │   └── migrations_controller.rb     # skip/unskip/add
│   ├── models/migration_skippr/
│   │   └── event.rb
│   ├── policies/migration_skippr/
│   │   └── migration_policy.rb          # default Pundit policy
│   └── views/migration_skippr/
│       ├── layouts/migration_skippr.html.erb
│       ├── databases/
│       │   ├── index.html.erb           # dashboard
│       │   └── show.html.erb            # database detail
│       └── migrations/
│           └── _form.html.erb           # add migration form
├── config/
│   └── routes.rb
├── db/
│   └── migrate/
│       └── create_migration_skippr_events.rb
├── lib/
│   ├── migration_skippr.rb
│   ├── migration_skippr/
│   │   ├── engine.rb
│   │   ├── configuration.rb
│   │   ├── database_resolver.rb         # discovers writable DBs
│   │   └── skipper.rb                   # skip/unskip + schema_migrations sync
│   └── generators/
│       └── migration_skippr/
│           └── install_generator.rb     # rails g migration_skippr:install
├── migration_skippr.gemspec
├── Gemfile
└── spec/
    ├── spec_helper.rb
    ├── rails_helper.rb
    ├── dummy/                           # dummy Rails app for testing
    │   ├── config/
    │   │   └── database.yml             # multi-database config
    │   └── ...
    ├── models/
    │   └── migration_skippr/
    │       └── event_spec.rb
    ├── lib/
    │   └── migration_skippr/
    │       ├── skipper_spec.rb
    │       └── database_resolver_spec.rb
    ├── controllers/
    │   └── migration_skippr/
    │       ├── databases_controller_spec.rb
    │       └── migrations_controller_spec.rb
    └── policies/
        └── migration_skippr/
            └── migration_policy_spec.rb
```

All classes are namespaced under `MigrationSkippr::`.

## Testing

- **RSpec** with **SimpleCov** enforcing 100% line coverage
- **Dummy Rails app** in `spec/dummy/` with multi-database configuration
- **Appraisals gem** for Rails version matrix

### CI Matrix (GitHub Actions)

| Axis | Values |
|------|--------|
| Ruby | 3.2, 3.3, 3.4, 4.0 |
| Rails | 7.1, 7.2, 8.0 |
| Database | SQLite, PostgreSQL, MySQL |

PostgreSQL and MySQL run as GitHub Actions services. SQLite uses the filesystem.

### Test Coverage Areas

- `MigrationSkippr::Skipper` — event creation, `schema_migrations` sync, error handling
- `MigrationSkippr::DatabaseResolver` — discovers writable DBs, excludes replicas, handles single and multi-DB configs
- `MigrationSkippr::Event` — scopes for current state resolution, query methods
- Controllers — auth enforcement (Pundit), skip/unskip/add actions, correct responses
- Policy — default-deny behavior
- Integration — full flow from UI action through to `schema_migrations` change
- Configuration — `current_actor`, `tracking_database`, `authorization_policy`
- Public API — `MigrationSkippr.skip`, `.unskip`, `.status`, `.history`

## Install Generator

`rails g migration_skippr:install` will:

1. Copy the `create_migration_skippr_events` migration into the host app
2. Add a default initializer at `config/initializers/migration_skippr.rb`
3. Print instructions to mount the engine in routes
