# Testing Strategy

MathMentor AI follows a simple rule: **accuracy first, and no feature ships without tests.**
Every phase must pass all 7 quality gates before it is committed.

## 1. Quality gates

Run the backend gates from `backend/` and the mobile gates from `mobile/`.

| # | Command | Purpose |
|---|---|---|
| 1 | `uv run ruff format --check .` | Formatting |
| 2 | `uv run ruff check .` | Lint, including security rules (`S`) and modern-Python rules (`UP`) |
| 3 | `uv run mypy app` | Strict static typing (application code) |
| 4 | `uv run pytest -v` | All backend tests |
| 5 | `uv run pytest --cov=app --cov-report=term-missing` | Coverage. The build fails below 90% (`fail_under`). |
| 6 | `flutter analyze` | Dart static analysis |
| 7 | `flutter test` | Flutter widget and unit tests |

## 2. Test layout (`backend/tests/`)

| Folder | Needs PostgreSQL? | What belongs here |
|---|---|---|
| `unit/` | No | Pure logic: schemas, security, tokens, model metadata, syllabus data validation, SymPy verifier, Gemini prompt building and error mapping, tutor orchestration with fakes |
| `integration/` | Yes | Real database behaviour: migrations, constraints, cascades, repositories, the seed script |
| `api/` | Yes (most) | HTTP behaviour through FastAPI's `TestClient`: status codes, the error envelope, auth, CORS, OpenAPI |

Tests that need the database are marked `@pytest.mark.integration`.

## 3. Database tests

- **Database:** tests use `TEST_DATABASE_URL` (`mathmentor_test`) and never the dev database.
  The fixtures **refuse to run** against a database whose name doesn't contain `test`.
- **Schema:** built once per session with the real Alembic migrations (`upgrade head`), and
  torn down at the end (`downgrade base`). This means the migrations themselves are tested.
- **Isolation:** each test runs inside a transaction that is rolled back afterwards, using
  `join_transaction_mode="create_savepoint"`. Code under test can call `commit()` safely.
- **Drift check:** `test_models_and_migrations_have_no_drift` fails if a model changes without
  a new migration.
- **Fixtures:** the shared ones live in `tests/conftest.py`: `db_session`, `make_unit`,
  `make_topic` and `make_user`. API fixtures (`client`, `user`, `auth_headers`, `seeded`) live
  in `tests/api/conftest.py`.

## 4. Mathematical accuracy

- **Seed formulas:** every formula in `syllabus/formulas/formulas.json` must parse with SymPy.
  Formulas flagged `identity: true` are checked numerically at 5 or more random rational points
  (`tests/unit/test_syllabus_data.py`).
- **Verifier sanity check:** a deliberately wrong identity
  (`sin(x+y) = sin x + sin y`) must fail, which proves the verifier doesn't pass everything.
- **Runtime verifier:** `app/services/mathematics/verifier.py` has its own tests. They cover
  correct identities, wrong identities, unparseable input (which must come back as
  "unverifiable", not "wrong"), and unsafe or oversized input.

## 5. External services (Gemini)

- **The real Gemini API is never called in tests.** `GeminiService` accepts an injected
  `generate` function, and tests pass in fakes that return canned responses or raise SDK
  errors.
- **API tests:** these override the `get_tutor_service` or `get_gemini_service` dependency.
- **Privacy:** a dedicated test registers a user with a distinctive name and email, calls
  `/tutor/ask`, and asserts that neither string appears in anything sent to Gemini.
- **Opt-in real calls:** a test marked `gemini` would call the real API. Such tests are reserved
  for manual runs and are never part of the gates.

## 6. Common commands

```bash
cd backend
uv run pytest tests/unit -q                 # fast, no database
uv run pytest tests/integration tests/api   # needs PostgreSQL running
uv run pytest -k tutor -v                   # one feature
uv run pytest --cov=app --cov-report=html   # browsable report in htmlcov/
```

## 7. Writing new tests

- **One behaviour per test,** named after what it proves (`test_expired_token_rejected`).
- **Errors:** assert the status code *and* the error envelope (`assert_error(body, "not_found")`).
- **Security tests:** never weaken an existing one to make a feature pass.
- **New models:** create a migration with
  `uv run alembic revision --autogenerate -m "..."`. Otherwise the drift test fails.
