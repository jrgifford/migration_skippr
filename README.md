# MigrationSkippr

A Rails engine for skipping (faking) database migrations and unskipping them later. Supports multiple databases, an append-only audit trail, and Pundit-based authorization.

**Use case:** You need to deploy but a migration isn't ready to run yet. Skip it in `schema_migrations` so Rails thinks it already ran, then unskip it later when you're ready.

![Databases overview](docs/screenshots/databases-index.png)

![Migration list with statuses](docs/screenshots/primary-detail.png)

## Installation

Add to your Gemfile:

```ruby
gem "migration_skippr"
```

Run the installer:

```bash
rails generate migration_skippr:install
rails db:migrate
```

Mount the engine in `config/routes.rb`:

```ruby
mount MigrationSkippr::Engine, at: "/migration_skippr"
```

## Configuration

The installer creates `config/initializers/migration_skippr.rb`:

```ruby
MigrationSkippr.configure do |config|
  # Lambda that receives the request and returns the current actor (string).
  # Used for audit trail. If not configured, actor will be nil.
  config.current_actor = ->(request) { request.env["warden"].user&.email }

  # Which database to store migration_skippr_events in.
  # Defaults to :primary.
  config.tracking_database = :primary

  # Pundit policy class for authorization.
  # Default policy denies all access — you must override this.
  config.authorization_policy = "MyApp::MigrationPolicy"
end
```

## Authorization

The default policy **denies all access**. Create your own policy to control who can view and manage migrations:

```ruby
class MyApp::MigrationPolicy < MigrationSkippr::MigrationPolicy
  def index?  = actor&.admin?
  def show?   = actor&.admin?
  def skip?   = actor&.admin?
  def unskip? = actor&.admin?
  def create? = actor&.admin?
end
```

## How it works

### Migration lifecycle

```mermaid
stateDiagram-v2
    [*] --> Pending : migration file created
    Pending --> Ran : rails db:migrate
    Pending --> Skipped : skip
    Skipped --> Pending : unskip
    Ran --> Ran : skip (inserts into schema_migrations)

    state Pending {
        direction LR
        [*] : Not in schema_migrations
    }
    state Skipped {
        direction LR
        [*] : In schema_migrations,\nbut code never ran
    }
    state Ran {
        direction LR
        [*] : In schema_migrations,\ncode executed
    }
```

When you **skip** a migration, MigrationSkippr inserts its version into `schema_migrations` so `rails db:migrate` thinks it already ran. When you **unskip**, it removes the version so the migration becomes pending again.

### Architecture

```mermaid
graph TB
    subgraph "Your Rails App"
        Routes[config/routes.rb]
        Policy[Authorization Policy]
        Actor[Current Actor Lambda]
    end

    subgraph "MigrationSkippr Engine"
        UI[Web UI]
        API[Programmatic API]
        Controllers[Controllers]
        Skipper[Skipper]
        Resolver[Database Resolver]
        Events[Event Model]
    end

    subgraph "Databases"
        SM1[primary: schema_migrations]
        SM2[analytics: schema_migrations]
        ET[primary: migration_skippr_events]
    end

    Routes --> UI
    Policy --> Controllers
    Actor --> Controllers
    UI --> Controllers
    API --> Skipper
    Controllers --> Skipper
    Controllers --> Resolver
    Skipper --> Events
    Skipper --> SM1
    Skipper --> SM2
    Resolver --> SM1
    Resolver --> SM2
    Events --> ET
```

### Audit trail

Every skip and unskip is recorded as an append-only event. Events are never updated or deleted.

```mermaid
erDiagram
    migration_skippr_events {
        bigint id PK
        string database_name "NOT NULL"
        string version "NOT NULL"
        string status "skipped | unskipped"
        string actor "who did it"
        text note "why"
        datetime created_at "NOT NULL"
    }

    schema_migrations {
        string version PK
    }

    migration_skippr_events ||--o| schema_migrations : "manages"
```

## Multi-database support

MigrationSkippr automatically discovers all writable databases configured in `database.yml`. Each database's migrations are tracked independently.

```mermaid
graph LR
    subgraph "database.yml"
        P[primary]
        A[analytics]
        R[replica]
    end

    subgraph "MigrationSkippr"
        DR[DatabaseResolver]
    end

    P -->|writable| DR
    A -->|writable| DR
    R -.->|excluded| DR
```

## Programmatic API

```ruby
# Skip a migration
MigrationSkippr.skip("20240101000001", database: "primary", actor: "alice", note: "Not ready")

# Unskip a migration
MigrationSkippr.unskip("20240101000001", database: "primary", actor: "alice", note: "Ready now")

# Check status
MigrationSkippr.status("primary")

# View history for a specific migration
MigrationSkippr.history("primary", "20240101000001")
```

## Requirements

- Ruby >= 3.2
- Rails >= 7.1, < 9.0
- Pundit >= 2.3

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
