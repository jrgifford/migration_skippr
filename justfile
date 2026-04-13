# Run all checks (lint + test)
default: lint test

# Run all linters
lint: standard reek flay flog brakeman bundle-audit

# Run test suite
test:
    bundle exec rspec

# Run tests against all Appraisal gemfiles
test-all:
    bundle exec appraisal rspec

# Ruby style check
standard:
    bundle exec standardrb

# Ruby style auto-fix
fix:
    bundle exec standardrb --fix

# Check for code smells
reek:
    bundle exec reek lib/ app/

# Check for code duplication
flay:
    bundle exec flay lib/ app/

# Check method complexity (max 25 per method)
flog:
    bundle exec flog -a lib/ app/ | awk 'NR>2 && /^ +[0-9]/ {score=$1+0; if (score > 25) {print "FAIL: " $0; exit 1}}'

# Security scan
brakeman:
    bundle exec brakeman --path . --no-pager -q

# Check for vulnerable gems
bundle-audit:
    bundle exec bundle-audit check
