# Contributing to Railway Asset Management System (AMS)

Thank you for your interest in contributing to the **Railway Asset Management System (AMS)**! We welcome contributions from developers, testers, and reviewers to help maintain and improve this enterprise platform.

---

## 🛠️ Development Environment & Prerequisites

Before you start, make sure you have the following installed:

- **Java Development Kit (JDK):** Version 17 or higher (tested with Eclipse Temurin / Oracle JDK 17, 21, and 26)
- **Maven:** Version 3.9+ (or use the included `./mvnw` / `mvnw.cmd` wrapper)
- **Database:** MySQL 8.0 or higher
- **Servlet Container:** Apache Tomcat 10.1+ (Jakarta EE 10 compatible) or Docker

---

## 🚀 Getting Started

1. **Fork and Clone the Repository:**
   ```bash
   git clone https://github.com/subhamsdhal/AMS-ASSET-MANAGEMENT-SYSTEM.git
   cd AMS-ASSET-MANAGEMENT-SYSTEM
   ```

2. **Initialize the Database:**
   ```bash
   mysql -u root -p -e "CREATE DATABASE asset_management_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
   mysql -u root -p asset_management_system < database/schema.sql
   mysql -u root -p asset_management_system < database/seed_data.sql
   ```

3. **Configure Local Environment:**
   Copy the example configuration:
   ```bash
   cp src/main/resources/db.properties.example src/main/resources/db.properties
   ```
   Or set environment variables:
   ```bash
   export AMS_DB_URL="jdbc:mysql://localhost:3306/asset_management_system?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Kolkata"
   export AMS_DB_USER="root"
   export AMS_DB_PASSWORD="your_password"
   ```

4. **Verify the Build & Test Suite:**
   ```bash
   # Linux / macOS
   ./mvnw clean test

   # Windows
   .\mvnw.cmd clean test
   ```

5. **Package the WAR File:**
   ```bash
   ./mvnw clean package
   # Built artifact: target/RailwayAMS.war
   ```

---

## 🌿 Branching & Commit Guidelines

- **Main Branch (`main`):** Contains production-ready code.
- **Feature Branches:** Use descriptive names like `feature/qr-scanner-improvements` or `fix/auth-session-handling`.
- **Commit Messages:** Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
  - `feat: add export to PDF for physical verification`
  - `fix: resolve SQL parameter binding in AssetReturnDAO`
  - `docs: update deployment and architecture guides`
  - `test: add unit tests for RoleDutyAssignmentSecurity`

---

## 🔒 Security & Code Standards

- **Never Commit Secrets:** Do not commit database passwords, API keys, SMTP credentials, or real `.env` files.
- **SQL Injection Prevention:** Always use parameterized `PreparedStatement` queries. Never concatenate untrusted strings into SQL.
- **XSS & Output Encoding:** Ensure user input rendered in JSPs uses HTML escaping (`HtmlEscapeUtil.escapeHtml()`).
- **Access Control:** All endpoints must specify role permissions in `RoleAuthorizationFilter` or `SecurityHeadersFilter`.
- **Tests First:** Any new DAO methods or business logic must include corresponding unit tests in `src/test/java/`.

---

## 📬 Submitting a Pull Request

1. Ensure all 200+ unit tests pass:
   ```bash
   ./mvnw test
   ```
2. Verify formatting and compile clean:
   ```bash
   ./mvnw compile
   ```
3. Push your branch and open a Pull Request against `main`.
4. Provide a clear description of the problem solved, implementation details, and test verification results.
