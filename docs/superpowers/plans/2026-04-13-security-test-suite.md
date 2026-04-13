# Security Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a mutation-verified security test suite covering SQL injection, CSRF, XSS, authorization bypass, and input validation across all endpoints.

**Architecture:** Security specs live in `spec/security/{endpoint}/{vulnerability_class}_spec.rb`. Shared attack payloads and a restrictive test policy live in `spec/security/support/`. Mutant validates that security tests catch real regressions. CI runs security specs on every push and mutation tests on PRs.

**Tech Stack:** RSpec 7, Mutant (mutation testing), Rails controller specs with `type: :controller`

---

## File Structure

```
spec/security/
├── migrations/
│   ├── sql_injection_spec.rb       — SQL payloads in version/note/database_name params
│   ├── csrf_spec.rb                — POST without CSRF token
│   ├── xss_spec.rb                 — XSS payloads stored via note/version, rendered in show
│   ├── authorization_bypass_spec.rb — deny-all + restrictive policy
│   └── input_validation_spec.rb    — traversal, overflow, unicode, null bytes
├── databases/
│   ├── sql_injection_spec.rb       — SQL payloads in :name route param
│   ├── csrf_spec.rb                — GET idempotency verification
│   ├── xss_spec.rb                 — XSS in database name display
│   ├── authorization_bypass_spec.rb — deny-all + restrictive policy
│   └── input_validation_spec.rb    — traversal, overflow, unicode, null bytes
└── support/
    ├── security_payloads.rb        — shared attack string constants
    └── restrictive_policy.rb       — partial-allow policy for auth bypass tests
```

Other files:
- `Gemfile` — add `mutant-license` and `mutant-rspec`
- `Rakefile` — add `spec:security` and `mutant:security` tasks
- `.mutant.yml` — Mutant configuration targeting security-critical classes
- `.github/workflows/ci.yml` — add security test and mutation test jobs

---

### Task 1: Add shared support files

**Files:**
- Create: `spec/security/support/security_payloads.rb`
- Create: `spec/security/support/restrictive_policy.rb`

- [ ] **Step 1: Create security payloads module**

```ruby
# frozen_string_literal: true

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
    "\"><img src=x onerror=alert(1)>",
  ].freeze

  TRAVERSAL_PAYLOADS = [
    "../../../etc/passwd",
    "....//....//etc/passwd",
    "..%2f..%2f..%2fetc/passwd",
  ].freeze

  OVERFLOW_PAYLOADS = [
    "A" * 10_000,
    "\u202E" * 100,
    "\u200B" * 1_000,
    "\n" * 1_000,
    "\x00version",
  ].freeze
end
```

Write to `spec/security/support/security_payloads.rb`.

- [ ] **Step 2: Create restrictive policy**

```ruby
# frozen_string_literal: true

class RestrictivePolicy
  def initialize(actor, record)
    @actor = actor
    @record = record
  end

  def index? = true
  def show? = true
  def skip? = true
  def unskip? = true
  def create? = false
  def run? = false
end
```

Write to `spec/security/support/restrictive_policy.rb`.

- [ ] **Step 3: Commit**

```bash
git add spec/security/support/
git commit -m "test: add shared security payloads and restrictive policy"
```

---

### Task 2: Migrations SQL injection specs

**Files:**
- Create: `spec/security/migrations/sql_injection_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Migrations - SQL Injection", type: :controller do
  controller_class = MigrationSkippr::MigrationsController

  # Use the engine's controller class directly
  tests controller_class
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }
  let(:safe_version) { "20260101000099" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
    connection = ActiveRecord::Base.connection
    connection.execute("DELETE FROM schema_migrations WHERE version NOT LIKE '2026041%'")
  rescue
    nil
  end

  describe "POST #create" do
    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "when version is #{payload.truncate(40).inspect}" do
        it "does not execute injected SQL" do
          schema_before = ActiveRecord::Base.connection
            .select_values("SELECT version FROM schema_migrations").sort

          post :create, params: {database_name: database_name, version: payload, note: "test"}

          expect(response.status).not_to eq(500)

          schema_after = ActiveRecord::Base.connection
            .select_values("SELECT version FROM schema_migrations").sort

          # The payload may have been inserted as a literal version string — that's fine.
          # What matters is no OTHER rows were affected and no tables were dropped.
          expect(ActiveRecord::Base.connection.table_exists?(:schema_migrations)).to be true
          expect((schema_before - schema_after)).to be_empty
        end
      end

      context "when note is #{payload.truncate(40).inspect}" do
        it "does not execute injected SQL via note field" do
          post :create, params: {database_name: database_name, version: safe_version, note: payload}

          expect(response.status).not_to eq(500)
          expect(ActiveRecord::Base.connection.table_exists?(:schema_migrations)).to be true
        end
      end
    end
  end

  describe "POST #skip" do
    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "when version is #{payload.truncate(40).inspect}" do
        it "does not execute injected SQL" do
          post :skip, params: {database_name: database_name, version: payload}

          expect(response.status).not_to eq(500)
          expect(ActiveRecord::Base.connection.table_exists?(:schema_migrations)).to be true
        end
      end
    end
  end

  describe "POST #unskip" do
    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "when version is #{payload.truncate(40).inspect}" do
        it "does not execute injected SQL" do
          # Attempt to unskip with a payload version — should fail gracefully
          post :unskip, params: {database_name: database_name, version: payload}

          expect(response.status).not_to eq(500)
          expect(ActiveRecord::Base.connection.table_exists?(:schema_migrations)).to be true
        end
      end
    end
  end
end
```

Write to `spec/security/migrations/sql_injection_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/migrations/sql_injection_spec.rb --format documentation`
Expected: All examples pass (no 500 errors, tables intact).

- [ ] **Step 3: Commit**

```bash
git add spec/security/migrations/sql_injection_spec.rb
git commit -m "test: add SQL injection specs for migrations endpoints"
```

---

### Task 3: Migrations CSRF specs

**Files:**
- Create: `spec/security/migrations/csrf_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Migrations - CSRF", type: :controller do
  tests MigrationSkippr::MigrationsController
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }
  let(:version) { "20260101000099" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
    ActionController::Base.allow_forgery_protection = true
  end

  after do
    ActionController::Base.allow_forgery_protection = false
    MigrationSkippr.reset_configuration!
  end

  describe "POST #create without CSRF token" do
    it "raises InvalidAuthenticityToken" do
      expect {
        post :create, params: {database_name: database_name, version: version}
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "does not create any records" do
      event_count_before = MigrationSkippr::Event.count

      begin
        post :create, params: {database_name: database_name, version: version}
      rescue ActionController::InvalidAuthenticityToken
        # expected
      end

      expect(MigrationSkippr::Event.count).to eq(event_count_before)
    end
  end

  describe "POST #skip without CSRF token" do
    it "raises InvalidAuthenticityToken" do
      expect {
        post :skip, params: {database_name: database_name, version: version}
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end
  end

  describe "POST #unskip without CSRF token" do
    it "raises InvalidAuthenticityToken" do
      expect {
        post :unskip, params: {database_name: database_name, version: version}
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end
  end
end
```

Write to `spec/security/migrations/csrf_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/migrations/csrf_spec.rb --format documentation`
Expected: All examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/security/migrations/csrf_spec.rb
git commit -m "test: add CSRF protection specs for migrations endpoints"
```

---

### Task 4: Migrations XSS specs

**Files:**
- Create: `spec/security/migrations/xss_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Migrations - XSS", type: :controller do
  tests MigrationSkippr::DatabasesController
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
    ActiveRecord::Base.connection.execute(
      "DELETE FROM schema_migrations WHERE version NOT LIKE '2026041%'"
    )
  rescue
    nil
  end

  describe "stored XSS via note field" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "when note contains #{payload.truncate(40).inspect}" do
        it "escapes the payload in rendered output" do
          # Store a migration with the XSS payload as the note
          version = "20260101000098"
          MigrationSkippr::Skipper.skip!(version, database: database_name, note: payload)

          get :show, params: {name: database_name}

          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "stored XSS via version field" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "when version contains #{payload.truncate(40).inspect}" do
        it "escapes the payload in rendered output" do
          MigrationSkippr::Skipper.skip!(payload, database: database_name)

          get :show, params: {name: database_name}

          # The raw XSS payload should not appear unescaped in HTML
          # ERB auto-escaping should convert < to &lt; etc.
          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "reflected XSS via flash messages" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "when flash contains #{payload.truncate(40).inspect}" do
        it "escapes the payload in flash output" do
          # Trigger a flash message that includes user input
          # The create action includes the version in flash[:notice]
          migrations_controller = MigrationSkippr::MigrationsController
          # We test by checking the show page renders flash safely
          # Set a flash with the payload and render the page
          get :show, params: {name: database_name}, flash: {notice: payload}

          expect(response.body).not_to include(payload)
        end
      end
    end
  end
end
```

Write to `spec/security/migrations/xss_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/migrations/xss_spec.rb --format documentation`
Expected: All examples pass (payloads are HTML-escaped, raw strings not found).

- [ ] **Step 3: Commit**

```bash
git add spec/security/migrations/xss_spec.rb
git commit -m "test: add XSS specs for migrations data rendered in views"
```

---

### Task 5: Migrations authorization bypass specs

**Files:**
- Create: `spec/security/migrations/authorization_bypass_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/restrictive_policy"

RSpec.describe "Migrations - Authorization Bypass", type: :controller do
  tests MigrationSkippr::MigrationsController
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }
  let(:version) { "20260101000099" }

  after do
    MigrationSkippr.reset_configuration!
    ActiveRecord::Base.connection.execute(
      "DELETE FROM schema_migrations WHERE version = '#{version}'"
    )
  rescue
    nil
  end

  context "with default deny-all policy" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "MigrationSkippr::MigrationPolicy"
      end
    end

    it "denies skip" do
      expect {
        post :skip, params: {database_name: database_name, version: version}
      }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end

    it "denies unskip" do
      expect {
        post :unskip, params: {database_name: database_name, version: version}
      }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end

    it "denies create" do
      expect {
        post :create, params: {database_name: database_name, version: version}
      }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end

    it "does not modify state when denied" do
      event_count_before = MigrationSkippr::Event.count

      begin
        post :create, params: {database_name: database_name, version: version}
      rescue MigrationSkippr::NotAuthorizedError
        # expected
      end

      expect(MigrationSkippr::Event.count).to eq(event_count_before)
    end
  end

  context "with restrictive policy (allows skip/unskip, denies create)" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "RestrictivePolicy"
      end
    end

    it "allows skip" do
      post :skip, params: {database_name: database_name, version: version}

      expect(response).to redirect_to(database_path(name: database_name))
    end

    it "allows unskip after skip" do
      MigrationSkippr::Skipper.skip!(version, database: database_name)

      post :unskip, params: {database_name: database_name, version: version}

      expect(response).to redirect_to(database_path(name: database_name))
    end

    it "denies create" do
      expect {
        post :create, params: {database_name: database_name, version: version}
      }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end
  end
end
```

Write to `spec/security/migrations/authorization_bypass_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/migrations/authorization_bypass_spec.rb --format documentation`
Expected: All examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/security/migrations/authorization_bypass_spec.rb
git commit -m "test: add authorization bypass specs for migrations endpoints"
```

---

### Task 6: Migrations input validation specs

**Files:**
- Create: `spec/security/migrations/input_validation_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Migrations - Input Validation", type: :controller do
  tests MigrationSkippr::MigrationsController
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
    ActiveRecord::Base.connection.execute(
      "DELETE FROM schema_migrations WHERE version NOT LIKE '2026041%'"
    )
  rescue
    nil
  end

  describe "POST #create with traversal payloads" do
    SecurityPayloads::TRAVERSAL_PAYLOADS.each do |payload|
      context "when version is #{payload.truncate(40).inspect}" do
        it "handles gracefully without server error" do
          post :create, params: {database_name: database_name, version: payload, note: "test"}

          expect(response.status).not_to eq(500)
        end
      end

      context "when note is #{payload.truncate(40).inspect}" do
        it "handles gracefully without server error" do
          post :create, params: {database_name: database_name, version: "20260101000099", note: payload}

          expect(response.status).not_to eq(500)
        end
      end
    end
  end

  describe "POST #create with overflow payloads" do
    SecurityPayloads::OVERFLOW_PAYLOADS.each do |payload|
      context "when version is #{payload.truncate(40).inspect}" do
        it "handles gracefully without server error" do
          post :create, params: {database_name: database_name, version: payload, note: "test"}

          expect(response.status).not_to eq(500)
        end
      end

      context "when note is #{payload.truncate(40).inspect}" do
        it "handles gracefully without server error" do
          post :create, params: {database_name: database_name, version: "20260101000099", note: payload}

          expect(response.status).not_to eq(500)
        end
      end
    end
  end

  describe "POST #skip with malicious payloads" do
    (SecurityPayloads::TRAVERSAL_PAYLOADS + SecurityPayloads::OVERFLOW_PAYLOADS).each do |payload|
      context "when version is #{payload.truncate(40).inspect}" do
        it "handles gracefully without server error" do
          post :skip, params: {database_name: database_name, version: payload}

          expect(response.status).not_to eq(500)
        end
      end
    end
  end

  describe "POST #unskip with malicious payloads" do
    (SecurityPayloads::TRAVERSAL_PAYLOADS + SecurityPayloads::OVERFLOW_PAYLOADS).each do |payload|
      context "when version is #{payload.truncate(40).inspect}" do
        it "handles gracefully without server error" do
          post :unskip, params: {database_name: database_name, version: payload}

          expect(response.status).not_to eq(500)
        end
      end
    end
  end
end
```

Write to `spec/security/migrations/input_validation_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/migrations/input_validation_spec.rb --format documentation`
Expected: All examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/security/migrations/input_validation_spec.rb
git commit -m "test: add input validation specs for migrations endpoints"
```

---

### Task 7: Databases SQL injection specs

**Files:**
- Create: `spec/security/databases/sql_injection_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Databases - SQL Injection", type: :controller do
  tests MigrationSkippr::DatabasesController
  routes { MigrationSkippr::Engine.routes }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "GET #show" do
    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "when database name is #{payload.truncate(40).inspect}" do
        it "rejects the unknown database without SQL execution" do
          expect {
            get :show, params: {name: payload}
          }.to raise_error(ActiveRecord::RecordNotFound)

          # Verify schema_migrations still exists
          expect(ActiveRecord::Base.connection.table_exists?(:schema_migrations)).to be true
        end
      end
    end
  end

  describe "GET #index" do
    it "does not expose SQL injection via database listing" do
      get :index

      expect(response.status).not_to eq(500)
      expect(ActiveRecord::Base.connection.table_exists?(:schema_migrations)).to be true
    end
  end
end
```

Write to `spec/security/databases/sql_injection_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/databases/sql_injection_spec.rb --format documentation`
Expected: All examples pass (unknown database names raise RecordNotFound).

- [ ] **Step 3: Commit**

```bash
git add spec/security/databases/sql_injection_spec.rb
git commit -m "test: add SQL injection specs for databases endpoints"
```

---

### Task 8: Databases CSRF specs

**Files:**
- Create: `spec/security/databases/csrf_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Databases - CSRF / Idempotency", type: :controller do
  tests MigrationSkippr::DatabasesController
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "GET #index" do
    it "is idempotent and produces no state changes" do
      event_count_before = MigrationSkippr::Event.count

      get :index
      get :index

      expect(MigrationSkippr::Event.count).to eq(event_count_before)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET #show" do
    it "is idempotent and produces no state changes" do
      event_count_before = MigrationSkippr::Event.count

      get :show, params: {name: database_name}
      get :show, params: {name: database_name}

      expect(MigrationSkippr::Event.count).to eq(event_count_before)
      expect(response).to have_http_status(:ok)
    end
  end
end
```

Write to `spec/security/databases/csrf_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/databases/csrf_spec.rb --format documentation`
Expected: All examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/security/databases/csrf_spec.rb
git commit -m "test: add CSRF/idempotency specs for databases endpoints"
```

---

### Task 9: Databases XSS specs

**Files:**
- Create: `spec/security/databases/xss_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Databases - XSS", type: :controller do
  tests MigrationSkippr::DatabasesController
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "GET #show with XSS in flash" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "when flash notice contains #{payload.truncate(40).inspect}" do
        it "escapes the payload in rendered HTML" do
          get :show, params: {name: database_name}, flash: {notice: payload}

          expect(response.body).not_to include(payload)
        end
      end

      context "when flash alert contains #{payload.truncate(40).inspect}" do
        it "escapes the payload in rendered HTML" do
          get :show, params: {name: database_name}, flash: {alert: payload}

          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "GET #index with XSS in flash" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "when flash notice contains #{payload.truncate(40).inspect}" do
        it "escapes the payload in rendered HTML" do
          get :index, flash: {notice: payload}

          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "GET #show with XSS database name" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "when database name is #{payload.truncate(40).inspect}" do
        it "rejects invalid database name before rendering" do
          expect {
            get :show, params: {name: payload}
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
```

Write to `spec/security/databases/xss_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/databases/xss_spec.rb --format documentation`
Expected: All examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/security/databases/xss_spec.rb
git commit -m "test: add XSS specs for databases endpoints"
```

---

### Task 10: Databases authorization bypass specs

**Files:**
- Create: `spec/security/databases/authorization_bypass_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/restrictive_policy"

RSpec.describe "Databases - Authorization Bypass", type: :controller do
  tests MigrationSkippr::DatabasesController
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }

  after do
    MigrationSkippr.reset_configuration!
  end

  context "with default deny-all policy" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "MigrationSkippr::MigrationPolicy"
      end
    end

    it "denies index" do
      expect {
        get :index
      }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end

    it "denies show" do
      expect {
        get :show, params: {name: database_name}
      }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end
  end

  context "with restrictive policy (allows index/show)" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "RestrictivePolicy"
      end
    end

    it "allows index" do
      get :index

      expect(response).to have_http_status(:ok)
    end

    it "allows show" do
      get :show, params: {name: database_name}

      expect(response).to have_http_status(:ok)
    end
  end
end
```

Write to `spec/security/databases/authorization_bypass_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/databases/authorization_bypass_spec.rb --format documentation`
Expected: All examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/security/databases/authorization_bypass_spec.rb
git commit -m "test: add authorization bypass specs for databases endpoints"
```

---

### Task 11: Databases input validation specs

**Files:**
- Create: `spec/security/databases/input_validation_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Databases - Input Validation", type: :controller do
  tests MigrationSkippr::DatabasesController
  routes { MigrationSkippr::Engine.routes }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "GET #show with traversal payloads" do
    SecurityPayloads::TRAVERSAL_PAYLOADS.each do |payload|
      context "when database name is #{payload.truncate(40).inspect}" do
        it "rejects the invalid database name" do
          expect {
            get :show, params: {name: payload}
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end

  describe "GET #show with overflow payloads" do
    SecurityPayloads::OVERFLOW_PAYLOADS.each do |payload|
      context "when database name is #{payload.truncate(40).inspect}" do
        it "rejects the invalid database name" do
          expect {
            get :show, params: {name: payload}
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
```

Write to `spec/security/databases/input_validation_spec.rb`.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/security/databases/input_validation_spec.rb --format documentation`
Expected: All examples pass (all payloads rejected by DatabaseResolver allowlist).

- [ ] **Step 3: Commit**

```bash
git add spec/security/databases/input_validation_spec.rb
git commit -m "test: add input validation specs for databases endpoints"
```

---

### Task 12: Add Mutant and Rake tasks

**Files:**
- Modify: `Gemfile`
- Modify: `Rakefile`
- Create: `.mutant.yml`

- [ ] **Step 1: Add mutant gems to Gemfile**

Add to the `group :development, :test` block in `Gemfile`:

```ruby
  gem "mutant-rspec"
  gem "mutant-license"
```

- [ ] **Step 2: Run bundle install**

Run: `bundle install`
Expected: Gems install successfully.

- [ ] **Step 3: Create Mutant configuration**

```yaml
# .mutant.yml
integration:
  name: rspec

matcher:
  subjects:
    - MigrationSkippr::Skipper
    - MigrationSkippr::Runner
    - MigrationSkippr::DatabaseResolver
    - MigrationSkippr::MigrationsController
    - MigrationSkippr::DatabasesController

requires:
  - migration_skippr

includes:
  - lib
  - app
```

Write to `.mutant.yml`.

- [ ] **Step 4: Add Rake tasks to Rakefile**

Replace the contents of `Rakefile` with:

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)

  RSpec::Core::RakeTask.new("spec:security") do |t|
    t.pattern = "spec/security/**/*_spec.rb"
  end

  task default: :spec
rescue LoadError
  # rspec not available in consuming apps
end

desc "Run mutation testing against security-critical classes"
task "mutant:security" do
  sh "bundle exec mutant run --use rspec -- " \
     "'MigrationSkippr::Skipper' " \
     "'MigrationSkippr::MigrationsController' " \
     "'MigrationSkippr::DatabasesController' " \
     "'MigrationSkippr::DatabaseResolver'"
end
```

- [ ] **Step 5: Verify Rake tasks exist**

Run: `bundle exec rake -T | grep -E "security|mutant"`
Expected:
```
rake mutant:security   # Run mutation testing against security-critical classes
rake spec:security     # Run RSpec code examples
```

- [ ] **Step 6: Run security specs via Rake**

Run: `bundle exec rake spec:security`
Expected: All security specs pass.

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock Rakefile .mutant.yml
git commit -m "chore: add Mutant for mutation testing and security Rake tasks"
```

---

### Task 13: Add CI jobs for security tests

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add security test job**

Add the following jobs to `.github/workflows/ci.yml` after the existing `test` job:

```yaml
  security-test:
    needs: lint
    runs-on: ubuntu-latest
    env:
      RAILS_ENV: test
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true

      - name: Run security specs
        run: bundle exec rake spec:security

  mutation-test:
    if: github.event_name == 'pull_request'
    needs: security-test
    runs-on: ubuntu-latest
    env:
      RAILS_ENV: test
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true

      - name: Run mutation tests
        run: bundle exec rake mutant:security
```

- [ ] **Step 2: Verify YAML is valid**

Run: `ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'valid'"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add security test and mutation test jobs"
```

---

### Task 14: Full test suite verification

- [ ] **Step 1: Run all security specs**

Run: `bundle exec rake spec:security`
Expected: All examples pass.

- [ ] **Step 2: Run the full existing test suite**

Run: `bundle exec rspec`
Expected: All existing + security examples pass, 100% coverage maintained.

- [ ] **Step 3: Run Mutant (if license available)**

Run: `bundle exec rake mutant:security`
Expected: All mutants killed or documented as equivalent.

- [ ] **Step 4: Final commit if any adjustments needed**

Only commit if fixes were required during verification.
