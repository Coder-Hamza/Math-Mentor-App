# Development Log

## Phase 0: Environment & Scaffolding (started 2026-11-10)

### Environment inspection
| Tool | Required | Found | Status |
|---|---|---|---|
| Python | 3.14 | 3.14.4 | OK |
| uv | any | 0.11.7 | OK |
| Git | any | 2.53.0.windows.1 | OK |
| PostgreSQL | local :5432 | 18.4, service `postgresql-x64-18` running, accepting connections | OK, but `bin` is not on PATH |
| Flutter / Dart | stable | not installed | **MISSING** |
| Android SDK / JDK | for Flutter Android builds | not found | **MISSING** |

### Backend dependencies (resolved by `uv sync`)
fastapi 0.156.8 (pinned exactly; the latest release is 0.162.4), sqlalchemy 2.1.8, alembic
1.20.1, pydantic 2.14.3, sympy 1.14.0, google-genai 3.0.0, psycopg 3.3.8, uvicorn 0.54.0,
pytest 9.2.0, httpx 0.28.1, ruff 0.17.4, mypy 2.4.1.

### Done
- Created the full folder structure from the spec.
- Ran `git init` on branch `main`.
- Added `backend/pyproject.toml` (uv, ruff, strict mypy, pytest, and coverage config).
- Added `backend/.env.example`.
- Added a minimal `app/main.py` (`/health` only) and one smoke test, so the gates have
  something to run.
- Wrote `docs/ARCHITECTURE.md`.

### Quality gates
| # | Gate | Result |
|---|---|---|
| 1 | ruff format --check | PASS |
| 2 | ruff check | PASS |
| 3 | mypy app (strict) | PASS |
| 4 | pytest -v | PASS (1 test) |
| 5 | coverage | PASS (100%) |
| 6 | flutter analyze | BLOCKED: Flutter not installed |
| 7 | flutter test | BLOCKED: Flutter not installed |

### Phase 0 completion (2026-11-11)

#### Flutter
- Flutter 3.47.9 (stable), Dart 3.13.7, DevTools 2.60.0, installed at
  `C:\Users\Cloud Primero\flutter`.
- `flutter doctor` results:
  - Passed: Flutter, Windows version, Chrome, connected devices, network resources.
  - Failed: Android toolchain, because the Android SDK was not found.
  - Failed: Visual Studio. This is only needed for Windows desktop builds, which this project
    doesn't target.
- Ran `flutter create --org com.mathmentor --project-name mathmentor --platforms android .`
  in `mobile/`. The package ID is `com.mathmentor.mathmentor`.

#### Final quality gates
| # | Gate | Result |
|---|---|---|
| 1 | ruff format --check | PASS |
| 2 | ruff check | PASS |
| 3 | mypy app (strict) | PASS |
| 4 | pytest -v | PASS (1 test) |
| 5 | coverage | PASS (100%) |
| 6 | flutter analyze | PASS (no issues) |
| 7 | flutter test | PASS (1 test, the default widget smoke test) |

#### Secrets handling
- Real credentials (Gemini key, DB password) live only in `backend/.env`, which is gitignored.
  `.env.example` holds placeholders only.
- Special characters in the DB password (such as `@`) must be URL-encoded in `DATABASE_URL`.

#### Carried into Phase 1
- Install Android Studio (Android SDK and bundled JDK), then run
  `flutter doctor --android-licenses`. This is needed for `flutter run` and APK builds.
- Add `C:\Users\Cloud Primero\flutter\bin` and `C:\Program Files\PostgreSQL\18\bin` to PATH
  for new shells.
- ~~DB login unverified~~ Resolved 2026-11-11: the `mathmentor` role was created, and it owns
  `mathmentor_db` (dev) and `mathmentor_test` (tests). The app connects to both through
  SQLAlchemy/psycopg using `backend/.env`.
- Replace the default counter app and `widget_test.dart` with the MathMentor shell.

**Phase 0 status: COMPLETE.** All 7 gates pass.

---

## Phase 1: Database Models & Core Backend (2026-11-11)

### Models (`app/models/`, SQLAlchemy 2 typed `Mapped[...]`)
| Model | Table | Key constraints |
|---|---|---|
| User | `users` | unique index on `email`; `created_at` uses server default `now()` (timezone-aware); `is_active` server default `true` |
| Unit | `units` | `unit_number` unique; checks that `unit_number > 0` and `page_number > 0` |
| Topic | `topics` | FK to units with ON DELETE CASCADE; unique (`unit_id`, `title`); `difficulty_level` enum |
| Formula | `formulas` | FK to topics with CASCADE; unique (`topic_id`, `name`); `expression` is SymPy syntax |
| PracticeQuestion | `practice_questions` | FK to topics with CASCADE; unique (`topic_id`, `question_text`); `difficulty` and `question_type` enums |
| StudentProgress | `student_progress` | FKs to users and topics with CASCADE; unique (`user_id`, `topic_id`); `score` must be 0–100; `attempts` must be ≥ 0 |

Design notes:
- **Enums:** stored as VARCHAR with a CHECK constraint, not native PG enums, so they are easier to
  migrate. The values are `easy`/`medium`/`hard` and `mcq`/`short`/`long`/`proof`.
- **Constraint names:** a fixed naming convention gives every constraint a predictable name, so
  migrations stay stable.
- **Passwords:** hashed with the standard-library scrypt (`app/core/security.py`), so no extra
  dependency is needed. The hash never appears in a `repr` or in `UserRead`.
- **Settings:** come from `pydantic-settings`, reading `backend/.env`. Secrets are `SecretStr`.

### Schemas (`app/schemas/`)
- **Variants:** each model has Create, Update and Read schemas.
- **Input schemas:** Create and Update reject unknown fields.
- **Read schemas:** frozen and built with `from_attributes`.
- **Users:** emails are lowercased, and passwords must be 8–128 characters.

### Migration
- **Revision:** `f7794967963c` "initial schema", autogenerated. Alembic hooks run Ruff format
  and Ruff fix on every new migration file.
- **Credentials:** `env.py` reads the DB URL from app settings; `alembic.ini` contains no
  credentials.
- **Dev DB:** `alembic upgrade head` was applied to `mathmentor_db` and is at head.

### Seed data (`/syllabus`, loaded by `app/database/seed.py`)
| File | Rows |
|---|---|
| `chapters/units.json` | 12 units, with page numbers matching the spec |
| `topics/topics.json` | 52 topics (3–5 per unit) |
| `formulas/formulas.json` | 72 formulas; 39 are flagged `identity` and verified by SymPy in tests |
| `question_patterns/practice_questions.json` | 36 practice questions (3 per unit) |

- **Validation:** Pydantic checks every file, plus cross-file integrity: no duplicates, no
  dangling references, and every unit has topics.
- **Idempotent:** the seed upserts on natural keys. The first run on the dev DB created
  12/52/72/36 rows; the second run created and updated nothing.
- **Usage:** `uv run python -m app.database.seed`

### Repositories (`app/repositories/`)
- **`BaseRepository`:** generic CRUD with `get`, `get_multi` (paged, max 500), `count`,
  `create`, partial `update`, and `delete`. Repositories flush but never commit; the caller owns
  the transaction.
- **`UserRepository`:** `get_by_email` (case-insensitive), password hashing on create and
  update, and `authenticate` (inactive users are rejected).
- **`UnitRepository`:** `get_by_number`, `list_ordered`, and `list_with_topics` (eager-loaded,
  no N+1 queries).
- **`TopicRepository`:** `list_by_unit`, `get_by_title`, `list_by_difficulty`, and
  `get_with_content` (formulas and questions eager-loaded).

### Tests: 239 passing
| Suite | Tests | Covers |
|---|---|---|
| `tests/unit` | 189 | Security, schemas, model metadata, config/session, and syllabus integrity. SymPy checks each identity formula at 5 random rational points and must also catch a deliberately wrong identity. |
| `tests/integration` | 49 | Real PostgreSQL (`mathmentor_test`). The schema is built with the Alembic migration, and each test is rolled back. Covers model/migration drift, the downgrade/upgrade round trip, constraints and cascades at the database level, all repository methods, and the seed (counts, idempotency, update path). |
| `tests/api` | 1 | `/health` |

The integration fixtures refuse to run against any database whose name doesn't contain `test`.

### Quality gates
| # | Gate | Result |
|---|---|---|
| 1 | ruff format --check | PASS |
| 2 | ruff check | PASS (tests may use literal passwords and a seeded RNG: S105/S106/S311) |
| 3 | mypy app (strict) | PASS (36 files) |
| 4 | pytest -v | PASS (239/239) |
| 5 | coverage | PASS (100%; the threshold is now `fail_under = 90`) |
| 6 | flutter analyze | PASS |
| 7 | flutter test | PASS |

### Notes and follow-ups
- **Unit titles:** units 10 and 12 use the full textbook-style titles. Shorten them in
  `units.json` if the app needs short labels.
- **Topic lists:** the topic breakdown follows the standard HSC-I content. It should be checked
  against the DCAR textbook's exercise headings.
- **Seed deletions:** the seed never deletes rows that were removed from the JSON, because
  student progress may point to them.

**Phase 1 status: COMPLETE.** Committed as `b6fa48d`, together with the new `CLAUDE.md`.

---

## Phase 2: Authentication & Core API (2026-11-11)

### Authentication
- **Library:** PyJWT 2.15.1, signing with HS256. This is the one new dependency; it is free and
  open source.
- **Algorithm pinned:** the server only accepts HS256 and ignores the algorithm named in the
  token header. Unsigned `alg: none` tokens are rejected.
- **Token pair:** an access token (60 min) and a refresh token (7 days). Claims are `sub`,
  `type`, `iat` and `exp`.
- **`type` claim:** refresh tokens are rejected on protected routes, and access tokens are
  rejected by `/refresh`.
- **`SECRET_KEY`:** a random 64-character value, stored only in `backend/.env`. Settings refuse
  a key shorter than 32 characters.
- **Login timing:** `UserRepository.authenticate` checks a dummy hash when the email is
  unknown, so response time doesn't reveal which emails are registered.
- **Inactive users:** they can't log in or refresh, and their existing access tokens stop
  working.

### Endpoints (`app/api/`)
| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | /api/v1/auth/register | public | 201 returns `UserRead`; 409 if the email is taken (including a simultaneous registration) |
| POST | /api/v1/auth/login | public | JSON `{email, password}` returns a `TokenPair`; 401 uses one generic message |
| POST | /api/v1/auth/refresh | public | `{refresh_token}` returns a new `TokenPair` |
| GET | /api/v1/auth/me | Bearer | the current user |
| GET | /api/v1/units/ | Bearer | 12 units in syllabus order |
| GET | /api/v1/units/{unit_id} | Bearer | 404 if missing |
| GET | /api/v1/units/{unit_id}/topics | Bearer | 404 if the unit is missing |
| GET | /api/v1/topics/{topic_id} | Bearer | |
| GET | /api/v1/topics/{topic_id}/formulas | Bearer | ordered by id |
| GET | /api/v1/topics/{topic_id}/questions | Bearer | ordered by id |
| GET | /health | public | |

- **ID validation:** path ids must be between 1 and 2³¹−1. Out-of-range ids get a 422 instead
  of reaching the database and causing a 500.
- **Error format:** every non-2xx response uses
  `{"error": {"code", "message", "details"}}`.
  - Codes: `not_found`, `validation_error`, `not_authenticated` (with a
    `WWW-Authenticate: Bearer` header), `conflict`, `method_not_allowed`, `internal_error`.
  - A 422 response lists `loc`, `msg` and `type` for each problem, but never echoes the rejected
    input, so passwords don't leak back.
  - A 500 response is generic; the actual exception goes to the server log.
- **CORS:** origins come from `CORS_ORIGINS` in `.env`. Credentials are off because tokens are
  sent in a header, not cookies. The native Android app doesn't send an `Origin` header, so CORS
  only matters for web clients.
- **Swagger:** served at `/docs`. The **Authorize** button takes the `access_token` from login.
- **App factory:** the app is built by `app.main.create_app()`, so each test gets a fresh,
  isolated app.

### Tests: 324 passing (+85)
| Suite | Tests | New coverage |
|---|---|---|
| unit | 204 | Token round trips, expiry, wrong type, wrong key, `alg: none`, malformed tokens, missing claims, secret-key length, CORS parsing |
| integration | 49 | Unchanged. Shared DB fixtures moved to `tests/conftest.py`. |
| api | 71 | Every endpoint: success cases, 401 (missing, garbage, expired, wrong-type, deleted-user and inactive-user tokens), 404, 422 (bad payloads, bad ids, no password echo), 409 (including a simulated race), 405, 500 (no leak, logged), CORS allow and deny, `/docs`, and an exact OpenAPI route list |

### Quality gates
| # | Gate | Result |
|---|---|---|
| 1 | ruff format --check | PASS |
| 2 | ruff check | PASS (two inline `noqa: S105` on non-secret strings: `"bearer"` and an error message) |
| 3 | mypy app (strict) | PASS (47 files) |
| 4 | pytest -v | PASS (324/324) |
| 5 | coverage | PASS (100%) |
| 6 | flutter analyze | PASS |
| 7 | flutter test | PASS |

### Decisions and follow-ups
- **Protected content:** all content routes require login, since the app is login-gated.
- **Login body:** login takes JSON rather than an OAuth2 form, because that's simpler for
  Flutter. Swagger uses HTTPBearer, so you paste the token in.
- **Stateless tokens:** there is no logout or revocation list yet, and no rate limiting on
  login. Both should be added before production.
- **No schema change:** the database is still at revision `f7794967963c`. Topic → formulas and
  questions now return in id order, which is ORM-only and needs no migration.

**Phase 2 status: COMPLETE. Waiting for approval before starting Phase 3.**
