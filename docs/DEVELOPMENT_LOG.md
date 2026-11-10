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
- DB login as `mathmentor` is not yet verified.
  - An earlier login check with the first password failed.
  - The password in `.env` has since changed and hasn't been tested.
  - The database was created as `mathmentor_db`, but `.env` uses `mathmentor`. One of them
    has to change so the names match.
- Replace the default counter app and `widget_test.dart` with the MathMentor shell.

**Phase 0 status: COMPLETE.** All 7 gates pass.
