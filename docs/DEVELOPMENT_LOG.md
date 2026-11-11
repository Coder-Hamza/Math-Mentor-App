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

**Phase 1 status: COMPLETE. Waiting for approval before starting Phase 2.**
