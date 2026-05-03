# Testing & Quality Assurance

This project uses an automated quality gate system to ensure code stability and reliability.

## 🧪 Running Tests Locally

### Backend (Node.js)

Navigate to the `backend/` directory:
- **Run all tests**: `npm test`
- **Run tests with coverage**: `npm run test:coverage`
- **Run lint check**: `npm run lint`
- **Auto-fix lint issues**: `npm run lint:fix`
- **Format code**: `npm run format`

### Frontend (Flutter)

Navigate to the `app/` directory:
- **Run all tests**: `flutter test`
- **Run tests with coverage**: `flutter test --coverage`
- **Run static analysis**: `flutter analyze`
- **Format code**: `dart format .`

---

## 🏗️ CI/CD Pipeline

On every Push or Pull Request to the main branches, the following checks are automatically performed:

1. **Backend**:
   - Dependency installation integrity (`npm ci`)
   - ESLint static analysis
   - Jest unit and integration tests
   - Coverage report generation

2. **Frontend**:
   - Flutter static analysis (strict rules in `analysis_options.yaml`)
   - Unit and Widget testing
   - Build verification (Web build smoke test)

The pipeline will **FAIL** if any of these steps fail, preventing broken code from being merged.

---

## 📝 Adding New Tests

### Backend
- Place new tests in `backend/test/` or `backend/test/integration/`.
- File naming convention: `*.test.js`.
- Use `jest.mock()` to isolate external dependencies (DB, S3, APIs).

### Frontend
- Place new tests in `app/test/`.
- File naming convention: `*_test.dart`.
- Use `mockito` or `mocktail` for dependency mocking.

---

## 📊 Coverage Thresholds

The current target is **80%+ coverage** for critical business logic (Auth, Recording, Session Management).
Check the `coverage/` directory after running coverage commands for detailed HTML reports.
