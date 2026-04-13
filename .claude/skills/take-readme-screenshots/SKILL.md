---
name: take-readme-screenshots
description: Use when UI views change (new buttons, layout changes, status badges) and README screenshots need updating, or when asked to retake screenshots
---

# Take README Screenshots

Capture screenshots of the MigrationSkippr dummy Rails app for the README using `agent-browser`.

## Screenshots to Capture

| Screenshot | URL Path | Notes |
|---|---|---|
| `docs/screenshots/databases-index.png` | `/migration_skippr/` | Databases overview |
| `docs/screenshots/primary-detail.png` | `/migration_skippr/databases/primary` | Migration list — scroll down ~200px to show full table |

## Steps

### 1. Add puma to Gemfile temporarily

```ruby
# In Gemfile, inside the group :development, :test block:
gem "puma"
```

Run `bundle install`.

### 2. Add development database config

Add a `development:` section to `spec/dummy/config/database.yml`:

```yaml
development:
  primary:
    adapter: sqlite3
    database: db/development.sqlite3
```

### 3. Create temporary allow-all initializer

Write `spec/dummy/config/initializers/migration_skippr.rb`:

```ruby
class ScreenshotPolicy
  def initialize(actor, record) = nil
  def index? = true
  def show? = true
  def skip? = true
  def unskip? = true
  def create? = true
  def run? = true
end

MigrationSkippr.configure do |config|
  config.authorization_policy = "ScreenshotPolicy"
end
```

### 4. Seed the development database

```ruby
# Run via: cd spec/dummy && RAILS_ENV=development bundle exec ruby -e '...'
require_relative "config/environment"
conn = ActiveRecord::Base.connection
conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version varchar NOT NULL PRIMARY KEY)")
conn.execute("CREATE TABLE IF NOT EXISTS ar_internal_metadata (key varchar NOT NULL PRIMARY KEY, value varchar, created_at datetime(6) NOT NULL, updated_at datetime(6) NOT NULL)")
# Mark existing migrations as ran
conn.execute("INSERT OR IGNORE INTO schema_migrations (version) VALUES ('20260101000001')")
conn.execute("INSERT OR IGNORE INTO schema_migrations (version) VALUES ('20260412000000')")
# Create tables those migrations would have created
conn.execute("CREATE TABLE IF NOT EXISTS users (id integer PRIMARY KEY, email varchar NOT NULL, created_at datetime NOT NULL, updated_at datetime NOT NULL)")
conn.execute("CREATE TABLE IF NOT EXISTS migration_skippr_events (id integer PRIMARY KEY AUTOINCREMENT, database_name varchar NOT NULL, version varchar NOT NULL, status varchar NOT NULL, actor varchar, note text, created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP)")
conn.execute("CREATE INDEX IF NOT EXISTS idx_migration_skippr_events_lookup ON migration_skippr_events (database_name, version, status, created_at)")
# Skip one migration so the UI shows Unskip + Run buttons
MigrationSkippr::Skipper.skip!("20260101000002", database: "primary", actor: "demo@example.com", note: "Waiting for data backfill")
```

### 5. Start the server

```bash
RAILS_ENV=development bundle exec puma config.ru -p 3999 &>/tmp/puma.log &
sleep 2
# Verify: curl -s -o /dev/null -w "%{http_code}" http://localhost:3999/migration_skippr/
# Should return 200
```

### 6. Take screenshots with agent-browser

```bash
# Close any existing browser session first
agent-browser close

# Databases index
agent-browser open http://localhost:3999/migration_skippr/ --viewport 1280x800 --args "--no-sandbox"
agent-browser screenshot docs/screenshots/databases-index.png

# Primary detail — scroll to show full migration table
agent-browser open http://localhost:3999/migration_skippr/databases/primary --viewport 1280x800
agent-browser scroll down 200
agent-browser screenshot docs/screenshots/primary-detail.png

agent-browser close
```

Verify screenshots with the Read tool to confirm they look correct before committing.

### 7. Clean up

Remove all temporary changes — do NOT commit them:

- Delete `spec/dummy/config/initializers/migration_skippr.rb`
- Delete `spec/dummy/db/development.sqlite3`
- Revert `spec/dummy/config/database.yml` (remove `development:` section)
- Revert `Gemfile` (remove `gem "puma"`)
- Run `bundle install` to update lockfile
- Kill the puma server: `kill $(lsof -t -i:3999)`

### 8. Verify and commit

Run `bundle exec rspec` to confirm nothing is broken, then commit just the screenshot PNGs.
