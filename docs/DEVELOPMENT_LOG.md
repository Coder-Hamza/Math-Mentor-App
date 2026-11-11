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

**Phase 2 status: COMPLETE.** Committed as `0e59ab3`, together with `docs/TESTING.md` and
`docs/PRD.md`.

---

## Phase 3: Gemini AI Integration + SymPy Verification (2026-11-11)

### What was built
| Module | Responsibility |
|---|---|
| `schemas/ai_schemas.py` | `TutorRequest` (question ≤ 500 characters, `topic_id`, `language` = `urdu_english` or `english`); `TutorResponse`; `VerificationStatus`; and `GeminiTutorAnswer`, the JSON contract for Gemini, which adds a `checks` field |
| `services/ai/prompts.py` | `SYSTEM_PROMPT` and `build_prompt`, built from `TutorPrompt`. That model has no personal fields, and `extra="forbid"` makes adding one an error. |
| `services/ai/privacy.py` | `scrub_pii` removes emails, Pakistani mobile numbers and CNICs from the question |
| `services/ai/gemini_service.py` | Builds the google-genai client lazily, requests JSON via `response_schema`, retries 5xx and network errors with backoff, maps every error to an `AIServiceError`, and falls back to plain text when the JSON is unusable |
| `services/ai/rate_limiter.py` | Sliding-window limits per minute and per day; logs a warning at 80% and returns 429 with `Retry-After` when full |
| `services/mathematics/verifier.py` | `verify_identity`, `verify_numeric` and `verify_expression`, each returning `VerificationResult` (`status`, `is_valid`, `confidence`, `error_message`, `points_checked`) |
| `services/tutor/tutor_service.py` | Loads the topic, unit and syllabus formulas from the DB, calls Gemini, runs SymPy in a worker thread with a timeout, combines the results and builds the response |
| `api/routes/tutor.py` | `POST /api/v1/tutor/ask` (requires a JWT). The user is authenticated but deliberately **not** passed to the service. |

### SymPy verification
- **Method:** each claim is evaluated numerically at 5 or more random rational points (one
  point if there are no variables). Sampling is seeded from the claim, so results are
  reproducible.
- **Status:**
  - `verified`: every claim held.
  - `failed`: at least one claim is wrong. The confidence is the share of points or claims
    that agreed.
  - `unverifiable`: nothing could be checked. This is not the same as wrong.
- **Hardening:** `parse_expr` uses `eval`, so Gemini's text is treated as hostile.
  - Only certain characters are allowed.
  - Attribute access, dunder names and Python keywords are rejected.
  - The namespace has no builtins at all.
  - Functions are built **unevaluated**. Otherwise `factorial(10**9)` would be computed while
    parsing, which is a denial-of-service risk found and fixed during this phase.
  - There are limits on length, node count, numeric exponents, power-tower depth and
    factorial size.
  - Evaluation is numeric only (`evalf`).
- **Accuracy bugs found by the tests and fixed:**
  1. Prose such as "the left side" was split into the symbols s·i·d·e, which produced a false
     "failed". Unknown multi-letter words are now reported as *unverifiable*.
  2. SymPy's `split_symbols` turned `a1` into `a*1`, so `a1 + a2 = 3a` would have *verified*.
     That transformation has been removed.

### Error handling
| Situation | HTTP | Code |
|---|---|---|
| Quota (Google 429 or the local limiter) | 429 + `Retry-After` | `ai_quota_exceeded` |
| Gemini 5xx or network failure (after retries) | 503 | `ai_unavailable` |
| Key rejected, model retired (404), or no key | 503 | `ai_not_configured` |
| Gemini took longer than its 25 s budget | 504 | `ai_timeout` |
| Empty reply | 502 | `ai_bad_response` |
| Non-JSON reply | **200** | plain-text answer, `unverifiable` plus a warning |
| SymPy timeout (5 s) | **200** | `unverifiable` plus a warning |

### Real Gemini check (one manual call, not a test)
`gemini-2.5-flash` returned **HTTP 404: "no longer available to new users"** for this API key.
The model list now offers `gemini-3.x` flash and flash-lite models. The pipeline handled the
failure correctly: a friendly 503 and no crash. A 404 now maps to `ai_not_configured` and
logs Google's message. **The model was not changed.** The user must choose a free-tier model
and set `GEMINI_MODEL`.

### Tests: 512 passing (+188)
| Suite | Tests | New in Phase 3 |
|---|---|---|
| unit | 354 | Verifier (correct and wrong identities, unverifiable input, 23 hostile or expensive inputs, unicode); Gemini service (prompt contents, PII scrubbing, JSON parsing and fallback, every error mapping, retries and backoff, timeout); rate limiter; result summarizing |
| integration | 62 | `TutorService` against the real DB and real SymPy with fake Gemini: verified, failed, unverifiable, partial, plain text, unknown topic, Gemini timeout, SymPy timeout |
| api | 96 | `/tutor/ask`: 200, 401, 422 (7 bad payloads), 404, 429, 502, 503 (×3), 504; a mocked `TutorService`; a **privacy test** checking that a registered user's name, email, phone, password and token never reach Gemini |

Gemini is faked in every test (`tests/fakes.py`).

### Quality gates
| # | Gate | Result |
|---|---|---|
| 1 | ruff format --check | PASS |
| 2 | ruff check | PASS |
| 3 | mypy app (strict) | PASS (56 files; SymPy is marked as untyped) |
| 4 | pytest -v | PASS (512/512) |
| 5 | coverage | PASS (100%) |
| 6 | flutter analyze | PASS |
| 7 | flutter test | PASS |

### Decisions
- **`checks` field:** added to Gemini's JSON contract. Prose steps can't be verified, so Gemini
  must also emit SymPy-checkable equalities.
- **`ask_tutor` return type:** it returns a `GeminiResult`, not a `TutorResponse`, because
  Gemini can't know `sympy_verified`. `TutorService` builds the `TutorResponse`.
- **Extra response field:** `verification_status` was added so the UI can tell "wrong" from
  "unverifiable".
- **No retry on failed checks:** a failed check doesn't trigger a second Gemini call, to
  protect free-tier quota.
- **Timeouts:** 30 s total, split into 25 s for Gemini and 5 s for SymPy.
  `GEMINI_TIMEOUT_SECONDS` changed from 30 to 25.

**Phase 3 status: COMPLETE.** Committed as `f5401c9`.

---

## Fix: Gemini model update (2026-11-11)

- **Models:** `GEMINI_MODEL=gemini-3.5-flash` (primary) and
  `GEMINI_FALLBACK_MODEL=gemini-3.1-flash-lite`, both chosen by the user. The defaults in
  `config.py` match.
- **Fallback:**
  - **Trigger:** the fallback is tried **only when the primary returns HTTP 404**. A 404 is
    never retried. Quota, auth and 5xx errors keep their existing handling and do not switch
    models.
  - **Memory:** a model that returned 404 is skipped for the rest of the process. If every
    model is marked unavailable, they are all probed again.
  - **Both fail:** if both models return 404, the response is 503 `ai_model_unavailable`
    ("The AI tutor's language model is not available right now. Please try again later."),
    and the server logs which models were tried.
- **Logging:** `GeminiResult.model` records which model answered. It appears in the log
  summary.
- **Tests:** 9 new ones (fallback success, the skip-after-404 cache, both models failing,
  re-probing, no or duplicate fallback, non-404 errors not falling back). **521 passing, 100%
  coverage, all 7 gates pass.**
- **Live check (one real request, real HTTP server):** `POST /api/v1/tutor/ask` with "What is
  a complex number? Explain with example." returned **HTTP 200 in 9.5 s**, answered by
  `gemini-3.5-flash` (no 404 or fallback in the server log). The answer had 5 Roman-Urdu/English
  steps and 2 formulas, with `verification_status: verified` and confidence 1.0. The temporary
  test user was deleted afterwards.
- **Follow-up:** `LOG_LEVEL` is not wired to Python logging yet, so the app's INFO logs (for
  example the answering model) are not printed. Fixed below.

---

## Fix: logging setup and quota fallback (2026-11-11)

**Logging**
- **Configuration:** `app/core/logging.py` attaches one handler to the `app` logger at
  `LOG_LEVEL`, from `create_app`. Calling it again is safe, and records still propagate, so
  pytest's `caplog` keeps working.
- **Validation:** `LOG_LEVEL` is case-insensitive and must be one of DEBUG, INFO, WARNING,
  ERROR or CRITICAL.
- **Request lines:** `app/api/middleware.py` logs `METHOD /path -> status (ms)` for every
  request, including ones that crash with a 500. It never logs query strings, headers or
  bodies.
- **Tutor log:** "Tutor answer received" now appears, showing
  `{"model", "structured", "steps", "checks"}`.
- **Checked on a real server:** `INFO app.request: GET /health -> 200 (53 ms)`.

**Quota fallback (429)**
- **Trigger:** when the primary returns 429, the service tries `gemini-3.1-flash-lite`. A 429
  is never retried on the same model.
- **Cooldown:** a model that returned 429 is skipped until its cooldown ends. The cooldown
  uses Google's `RetryInfo.retryDelay` (for example `37.2s` becomes 38 s), or 60 s if there is
  none.
- **Everything cooling down:** if every model is cooling down, the tutor returns 429 right
  away with an accurate `Retry-After`, without spending a request.
- **Mixed failures:** primary 404 plus fallback 429 returns 429 (quota). Both 429 return 429
  with the shorter wait.
- **Unchanged:** 5xx, 400 and 401/403 errors never switch models. The local `RateLimiter` is
  app-wide (both models share the 10/min and 250/day budget) and does not trigger the
  fallback.

**Results:** 23 new tests, **544 passing** (unit 386, integration 62, api 96), **100%
coverage, and all 7 gates pass.**

---

## Phase 4: Flutter Android app (2026-11-11)

### Screens
| Screen | What it does |
|---|---|
| Splash | Logo and spinner. Checks the stored JWT with `/auth/me`: a valid token goes to Home, no token or an expired one goes to Login, and offline goes to Home, which offers retry. |
| Login | Email and password with validation. The button disables and shows a spinner while busy. Errors are bilingual. Shows "Session khatam ho gaya" after a forced logout. Links to Register. |
| Register | Name, email and password (validated with the backend's rules). Logs in automatically and goes to Home. Handles "email already registered". |
| Home | "MathMentor AI" app bar with a logout button (confirms first), a greeting, 12 unit cards (number, title, page) and pull to refresh. |
| Unit detail | Unit header and topic cards with a difficulty badge (easy green, medium orange, hard red). Pull to refresh. |
| Topic detail | Header, a prominent **Ask AI Tutor** button, expandable formula cards (SymPy syntax shown in textbook form, e.g. `I**2` becomes `i^2`), and recent questions. |
| Tutor | A topic context bar, a chat list, and the "Apna sawal likhein..." input (500-character limit). Shows a loading animation while Gemini answers, then a response card (see below). Errors are friendly, with a retry button. A language menu switches between Urdu + English and English. |

The tutor's response card shows:
- A **verification badge**: SymPy verified ✓, Possible mistake found, or Not verified.
- A **yellow warning box** when the backend sends a warning.
- The **explanation**, rendered as Markdown.
- **Numbered steps**, with Gemini's own "Step N:" prefix removed.
- **Formula chips** for the formulas used.

### Architecture
- **Services:**
  - `ApiService` sends a Bearer JWT with every request. On a 401 it tries one silent refresh
    (shared by requests that fail at the same time), then retries the request. If the refresh
    fails, it clears the tokens and sends the student to Login.
  - Every failure becomes an `ApiException` with an Urdu/English message.
  - Responses are always decoded as UTF-8, which Urdu text and math symbols need.
  - `AuthService` handles login, register and logout. `StorageService` holds the tokens and
    each topic's recent questions, and wipes both on logout.
- **Providers:** `AuthProvider` (session state) and `UnitsProvider` (units, topics and formulas
  cached in memory; stale data is kept when a refresh fails).
- **Navigation:** the app root listens to `AuthProvider`. Logout or an unrecoverable 401
  clears the cache and resets to Login.
- **Error messages:**
  - No internet: "Internet connection check karein."
  - Server down (connection refused, 502/503 without an AI code): "Server se connection nahi
    hua..."
  - AI unavailable (503/502 with an `ai_*` code): "AI tutor abhi available nahi, thodi der baad
    try karein."
  - Timeout (client side, or 504): "Request timeout, dobara try karein."
  - Quota (429): "AI tutor abhi bohat busy hai..."
- **API URL:** `http://10.0.2.2:8000` by default. Override it at run time with
  `--dart-define=API_BASE_URL=...`, with no code change.

### Decisions and deviations from the spec
| Spec | Done | Why |
|---|---|---|
| `flutter_markdown ^0.6.0` | `flutter_markdown_plus ^1.0.12` | `flutter_markdown` is discontinued; pub.dev names this as its replacement (same API) |
| `google_fonts ^6.0.0` | Poppins bundled through `fonts:` in `pubspec.yaml` (OFL licence) | `google_fonts` pulls in `objective_c`, whose native build hook fails because the Flutter SDK path contains a space. Bundling also works offline and gives true weights. |
| Package versions | `http ^1.6.0`, `provider ^6.1.5`, `shared_preferences ^2.5.6`, `loading_animation_widget ^1.3.0` | Current releases |
| Min Android API 21 | API 24 (Flutter's default) | Flutter 3.47 refuses to build below API 23 |
| Splash: "token valid" | Checked with `/auth/me` | A stored token alone doesn't prove the session is still valid |
| On 401, go to login | Silent refresh first | The access token lasts 60 minutes; without a refresh, students would be logged out every hour |
| Recent questions | Stored on the phone, per topic, newest first, max 5 | There is no backend history yet. They are cleared on logout. |
| Plain HTTP | Allowed in debug and profile builds only | Android blocks cleartext HTTP by default; release builds need HTTPS |

Two real bugs were caught by the widget tests and fixed: the splash spinner overflowed its
box, and a test helper's variable shadowed a constant.

### Tests
- **Flutter:** 87 passing, with **97.5% line coverage**. Everything runs against a mocked HTTP
  client (`FakeBackend` in `test/helpers.dart`); no real API calls.
  - `ApiService` (24): auth headers, refresh, error mapping, network, timeout, UTF-8.
  - Storage, models and validators (18).
  - Splash, login and register, session handling (19).
  - Home, unit and topic screens (11).
  - Tutor screen (15).
- **Backend:** unchanged, 544 passing with 100% coverage.

### Quality gates
| # | Gate | Result |
|---|---|---|
| 1 | ruff format --check | PASS |
| 2 | ruff check | PASS |
| 3 | mypy app | PASS |
| 4 | pytest -v | PASS (544) |
| 5 | coverage | PASS (100%) |
| 6 | flutter analyze | PASS (strict casts, extra lints) |
| 7 | flutter test | PASS (87) |

### Not verified yet
The Android SDK is not installed, so the app has **not run on an emulator or phone**. It has
only been analyzed and widget-tested. See `README.md` for how to run it.

**Phase 4 status: COMPLETE. Waiting for approval before starting Phase 5.**

---

## Phase 5: Practice & progress tracking (2026-11-11)

### Backend
- **Answer key** (migration `379d357d50ab`): `practice_questions` gains `correct_answer`,
  `answer_explanation` and `options` (JSON, the 4 MCQ choices). A check constraint ties
  `question_type = 'mcq'` to `options IS NOT NULL`. Existing rows are backfilled with an empty
  answer key (not gradable) until the seed runs again.
- **Seed:** all 36 questions now have an answer and an explanation. 16 became MCQs: graph
  regions, matrices, triangle solutions, general solutions and domain/range can't be graded
  fairly as free text. The other 16 are short or long, plus the 4 proofs. The seed
  validates every MCQ: 4 distinct options, and the answer must be one of them. The correct
  option's position varies (A to D).
- **New table `practice_attempts`:** one row per submission. It drives streaks and "points only
  once per question".
- **`student_progress`** gains `correct_count` and `points`; `score` is now the topic accuracy (%).
- **Endpoints** (all JWT):
  - `GET /practice/random?unit_id=&count=5` returns questions without answers; proofs are excluded.
  - `POST /practice/submit` returns `is_correct`, `correct_answer`, `explanation`,
    `points_earned`, `new_total_points`, `streak`, `encouragement` and `already_solved`.
  - `GET /progress/` returns points, attempts, correct answers, accuracy, streak and per-unit
    progress.
  - `GET /progress/weak-topics` returns topics with accuracy below 60%, weakest first.
- **Grading** (`services/practice/answer_matching.py`), with no Gemini call:
  - MCQ: exact, case-insensitive match on the option text or its letter A to D.
  - Short and long answers are checked by SymPy first. Answers are split into parts and each
    part is compared mathematically:
    - Labels are matched by name (`R = 65/8, r = 4`).
    - Unordered roots: `2 ± 3i` equals `2 + 3i, 2 - 3i`.
    - `i` is read as the imaginary unit.
    - Degrees are converted: `-30°` and a bare `-30` both match `-π/6`.
    - `√`, units (`28.87 m`), `≈` and thousands separators are handled.
    - Decimals are accepted when correctly rounded to at least 2 places: `9.95` matches
      `9.950`, `9.94` does not.
  - Anything that isn't maths falls back to `difflib` similarity (at least 0.85).
  - Grading runs in a worker thread with the 5 s SymPy timeout and falls back to similarity
    if that runs out.
  - Student text goes through the hardened parser (`verifier.parse_math`).
- **Points:**
  - Base points by difficulty: easy 10, medium 20, hard 30.
  - Bonus: +5 for a correct answer in under 60 s.
  - A wrong answer earns 0.
- **Encouragement:**
  - "Shabash! N sawaal lagataar sahi! 🔥" (streak ≥ 3)
  - "Bilkul sahi! Bohat acha! ✅"
  - "Himmat mat haro! Agle mein zaroor sahi hoga 🌟" (lost a streak of ≥ 3)
  - "Koi baat nahi, dobara koshish karo 💪"
- **Concurrency:** submit locks the user row (`SELECT ... FOR UPDATE`), so one student's
  submissions can't interleave.

### Flutter
- **Bottom navigation:** Units, Practice and Progress. Tabs are built the first time they are
  opened. Practice keeps its session while switching tabs; Progress reloads every time it is
  opened.
- **Practice screen:**
  - Shows 5 random questions one at a time, each with "Sawaal 1/5", a difficulty badge, the
    unit and topic, and the question.
  - Answers: MCQs have 4 lettered option buttons; other questions use a text field.
  - Submit shows a spinner while the answer is graded.
  - The result card shows ✅ or ❌, the correct answer, the explanation, points, the
    encouragement and the streak. After grading, the options are locked and the correct one
    is marked.
  - The screen auto-scrolls to the result.
  - "Agla Sawaal" moves on. After the last question, a summary shows points and right/wrong
    counts, with "Dobara Khelo" and "Home".
- **Progress screen:**
  - Stats card: 🏆 points, accuracy, 🔥 streak, attempted.
  - Unit progress bars: red below 40%, orange 40–70%, green above 70%.
  - Weak topics are shown in red with a "Practice karein" button, which opens practice for
    that unit.
  - Pull to refresh.
- **New code:**
  - Models: `practice_question`, `practice_result`, `progress`.
  - Services: `practice_service`, `progress_service`.
  - Widgets: `practice_result_card`, `progress_widgets`.
  - Route: `/practice` with `PracticeRouteArgs`.

### Decisions
| Spec | Done | Why |
|---|---|---|
| MCQ needs options | Added an `options` JSON column. 16 questions became MCQs (question text unchanged). | None of the 36 questions were MCQs before, and several could not be graded as free text |
| Answers for proofs | Stored, but proofs are excluded from `/practice/random`; submitting one returns 422 `question_not_gradable` | A proof can't be checked by SymPy or string matching without AI |
| Points on every correct answer | Points only the **first** time a question is solved (`already_solved` flag); repeats still count for accuracy and streak | The answer is revealed after each submission, so repeats would let students farm points |
| `progress_percent` | Sum of topic accuracies ÷ topics in the unit that have gradable questions (`topics_total`) | Gives 100% when every practisable topic is fully correct. `avg_score` averages only the attempted topics. |
| "Streak broken" message | Shown when a streak of ≥ 3 (the 🔥 threshold) is lost | One correct answer isn't a streak |
| Answer tolerance | Correctly rounded decimals with at least 2 places | `0.97` for `(√6+√2)/4` is right; `1` is not |

A test caught that no MCQ had its answer at option A, so 4 were reordered. Another
caught that SQLAlchemy stores Python `None` as JSON `null`, not SQL NULL, which broke the
check constraint (fixed with `JSON(none_as_null=True)`). Writing the navigation tests also
showed that the result card could sit below the fold, so the practice screen now
auto-scrolls to it.

### Environment
The Flutter SDK now lives at `C:\src\flutter`, with no space in the path. The old
`.dart_tool/package_config.json` still pointed at the previous location and made
`flutter analyze` report 2134 errors; `flutter pub get` fixed it. The Android SDK is still
missing.

### Tests
- **Backend:** 842 passing (+298), 100% coverage (unit 627, integration 88, API 127). New:
  - `test_answer_matching` (144): MCQ, SymPy equivalence, rounding, labels, degrees, hostile
    input, similarity.
  - `test_practice_rules` (22): `evaluate_answer`, `calculate_points`, `get_encouragement`,
    the grading timeout.
  - Syllabus answer key:
    - Every short or long answer key is graded by SymPy, not by text similarity.
    - A typical student answer is accepted for each of the 16 short/long questions.
    - The MCQ checks above (4 options, answer present, varied position).
  - `test_progress_repository` (10): every method, plus isolation between students.
  - `test_practice_service` (12): first solve, repeat solve, streak, broken streak, letter
    answers, ungradable questions, 404, the timeout fallback, random selection.
  - `test_practice` API (31): submit correct, wrong and invalid; random; progress; weak topics;
    no answer leaks; auth.
  - Migrations: the answer fields exist; upgrading from Phase 4 backfills existing rows.
- **Flutter:** 122 passing (+35), **98.3% line coverage**, all against mocked HTTP:
  - Practice screen (12).
  - Progress screen (9).
  - Bottom navigation (4).
  - Practice and progress services and models (10).

### Quality gates
| # | Gate | Result |
|---|---|---|
| 1 | ruff format --check | PASS |
| 2 | ruff check | PASS |
| 3 | mypy app | PASS |
| 4 | pytest -v | PASS (842) |
| 5 | coverage | PASS (100%) |
| 6 | flutter analyze | PASS |
| 7 | flutter test | PASS (122) |

### Live check
I seeded the dev DB, then called random, submit (wrong answer), progress and weak-topics with
`TestClient` against the real database. All returned 200 with the expected data, and the
temporary user was deleted afterwards.

**Phase 5 status: COMPLETE. Waiting for approval before starting Phase 6.**
