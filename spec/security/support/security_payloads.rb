# frozen_string_literal: true

module SecurityPayloads
  SQL_PAYLOADS = [
    "' OR '1'='1",
    "'; DROP TABLE schema_migrations; --",
    "1; DELETE FROM schema_migrations",
    "' UNION SELECT version FROM schema_migrations --",
    "1' OR '1'='1' /*",
    "'; UPDATE schema_migrations SET version='hacked'; --",
    "' AND 1=0 UNION SELECT sqlite_version(); --",
    "1; SELECT * FROM schema_migrations WHERE '1'='1"
  ].freeze

  XSS_PAYLOADS = [
    "<script>alert('xss')</script>",
    "<img src=x onerror=alert('xss')>",
    "<svg onload=alert('xss')>",
    "javascript:alert('xss')",
    "<iframe src='javascript:alert(1)'>",
    "'\"><script>alert(document.cookie)</script>",
    "<body onload=alert('xss')>",
    "<input onfocus=alert('xss') autofocus>"
  ].freeze

  TRAVERSAL_PAYLOADS = [
    "../../../etc/passwd",
    "..\\..\\..\\windows\\system32",
    "%2e%2e%2f%2e%2e%2f",
    "....//....//",
    "\x00/etc/passwd",
    "file:///etc/passwd",
    "/dev/null",
    "..%252f..%252f"
  ].freeze

  OVERFLOW_PAYLOADS = [
    "A" * 10_000,
    "🎉" * 1_000,
    "\u0000" * 100,
    "version\x00injected",
    "\uFEFF" + "normal_text",
    "\u202Emalicious\u202C",
    "a" * 100_000,
    ("\\n" * 1_000).to_s
  ].freeze
end
