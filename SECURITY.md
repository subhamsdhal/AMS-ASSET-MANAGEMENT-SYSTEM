# Security Policy

The security of the **Railway Asset Management System (AMS)** is a top priority. We take security vulnerabilities seriously and appreciate responsible disclosure from the community.

---

## 🛡️ Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

---

## 🔒 Security Architecture Highlights

Railway AMS incorporates multi-layered defense-in-depth security principles:

1. **Authentication & Password Security:**
   - Passwords hashed using industry-standard **jBCrypt** with salted cryptographic hashes.
   - Account lockout enforcement after consecutive failed login attempts.
   - Session fixation protection on successful authentication.
   - Forced password rotation support for initial or temporary logins.

2. **Access Control & RBAC:**
   - Dual-layer servlet filters (`SecurityHeadersFilter` and `RoleAuthorizationFilter`) running deterministically before endpoints.
   - Default-deny architecture on protected resources.
   - Granular role scopes across Super Admin, Admin, Asset Manager, Department Head, Verifier, Auditor, and Employee.

3. **Data Protection & Secret Storage:**
   - Sensitive third-party API keys (OpenAI, Gemini, Claude, Groq) encrypted using **AES encryption** (`CryptoUtil`) before persistence.
   - Database credentials and SMTP secrets managed via runtime environment variables (`AMS_DB_*`, `AMS_CRYPTO_KEY`).

4. **Input Sanitization & Injection Prevention:**
   - 100% parameterized JDBC `PreparedStatement` queries across all DAOs.
   - XSS sanitization and output escaping utility (`HtmlEscapeUtil`).
   - Anti-tampering QR tokens with cryptographic signature and expiration validation.

5. **Audit Logging & Non-Repudiation:**
   - Centralized `AuditDAO` with client IP and User-Agent binding via `RequestContext`.
   - Comprehensive audit trail across allocations, transfers, returns, disposals, and administrative overrides.

---

## 🚨 Reporting a Vulnerability

If you discover a security vulnerability within this project:

1. **Do NOT open a public GitHub issue.**
2. Send an email to the project maintainer at `subhamsdhal@gmail.com` with the subject `[SECURITY VULNERABILITY] Railway AMS`.
3. Include:
   - Type of vulnerability (e.g., IDOR, XSS, CSRF, auth bypass)
   - Step-by-step reproduction instructions or proof-of-concept
   - Impact assessment
   - Suggested remediation (if available)

### Response Timeline
- **Initial Response:** Within 48 hours.
- **Triage & Assessment:** Within 5 business days.
- **Fix & Advisory Release:** Coordinated with the reporter before public disclosure.
