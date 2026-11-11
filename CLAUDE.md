# MathMentor AI — Claude Code Memory File
# Read this FIRST at the start of every session.
# This file is your complete project memory.

## What This Project Is
AI math tutor app for Sindh Board HSC-I (Class 11) students.
Stack: Flutter (Android) + FastAPI + PostgreSQL + Gemini API + SymPy
Location: D:\Backend\MathMentor AI\math-mentor-ai\

## Rules — Never Break These
1. Read this file at the start of EVERY session
2. No paid APIs. No Claude API. Gemini free tier only.
3. ALL 7 quality gates must pass before any commit
4. No feature without tests. Coverage must stay above 90%.
5. Never commit secrets. .env is gitignored.
6. Update CLAUDE.md and DEVELOPMENT_LOG.md after every phase
7. Do NOT start next phase without explicit user approval

## Quality Gates (Run Every Time)
ruff format --check .
ruff check .
mypy app
pytest -v
pytest --cov=app --cov-report=term-missing
flutter analyze
flutter test

## Tech Stack Versions
Python: 3.14.4
FastAPI: latest compatible
SQLAlchemy: 2.1.8
Alembic: 1.20.1
Pydantic: 2.14.3
SymPy: 1.14.0
google-genai: 3.0.0
Flutter: 3.47.9 / Dart 3.13.7
PostgreSQL: 18.4 (local)
uv: 0.11.7

## Database
Dev DB:  mathmentor_db  (user: mathmentor)
Test DB: mathmentor_test (user: mathmentor)
Connection: postgresql+psycopg://mathmentor:***@localhost:5432/
Alembic revisions: f7794967963c (initial schema) -> 379d357d50ab (practice answers
  + attempts) — at head. After upgrading, re-run the seed to fill the answer key.

## Project Structure
math-mentor-ai/
├── mobile/lib/          # Flutter Android app
├── backend/
│   ├── app/
│   │   ├── api/         # FastAPI routes (Phase 2)
│   │   ├── core/        # Config, security
│   │   ├── database/    # DB connection, seed.py
│   │   ├── models/      # SQLAlchemy models
│   │   ├── schemas/     # Pydantic schemas
│   │   ├── repositories/# CRUD layer
│   │   └── services/    # AI, math, tutor logic
│   ├── tests/
│   │   ├── unit/        # 627 tests
│   │   ├── integration/ # 88 tests
│   │   └── api/         # 127 tests
│   └── alembic/
├── syllabus/
│   ├── chapters/units.json        # 12 units
│   ├── topics/topics.json         # 52 topics
│   ├── formulas/formulas.json     # 72 formulas
│   └── question_patterns/         # 36 questions + answer key
│                                  # (16 mcq, 8 short, 8 long, 4 proof)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEVELOPMENT_LOG.md
│   └── TESTING.md
├── CLAUDE.md            # THIS FILE — read every session
└── README.md

## Syllabus (Sindh Board HSC-I)
Unit 1:  Complex Numbers (pg 1)
Unit 2:  Matrices & Determinants (pg 25)
Unit 3:  Vectors (pg 74)
Unit 4:  Sequences & Series (pg 124)
Unit 5:  Miscellaneous Series (pg 162)
Unit 6:  Permutation, Combination & Probability (pg 179)
Unit 7:  Mathematical Induction & Binomial Theorem (pg 214)
Unit 8:  Functions & Graphs (pg 238)
Unit 9:  Linear Programming (pg 267)
Unit 10: Trigonometric Identities — Sum & Difference (pg 292)
Unit 11: Application of Trigonometry (pg 317)
Unit 12: Graphs of Trig & Inverse Trig + Trig Equations (pg 337)

## Completed Phases

### Phase 0 — Environment Setup ✅ COMPLETE
- Python 3.14.4, uv, Git, Flutter 3.47.9, PostgreSQL 18.4
- Project folder structure created
- Git initialized, .gitignore configured
- All 7 quality gates passing
- Committed: "Phase 0: Environment setup complete"

### Phase 1 — Database Models & Seed Data ✅ COMPLETE
- Models: User, Unit, Topic, Formula, 
  PracticeQuestion, StudentProgress
- Pydantic schemas: Create/Update/Read for all models
- Alembic migration: f7794967963c applied
- Seed data: 12 units, 52 topics, 72 formulas, 
  36 practice questions
- Repositories: base, user, unit, topic
- Tests: 239/239 pass, 100% coverage
- SymPy verifies 39 identity formulas automatically
- Password hashing: scrypt (built-in Python)
- All 7 gates: PASS

### Phase 2 — Authentication & Core API ✅ COMPLETE (awaiting approval for Phase 3)
- JWT (PyJWT 2.15, HS256): access 60 min + refresh 7 days, `type` claim
  stops refresh tokens being used as access tokens
- Routes: register, login, refresh, me + 6 content routes (all content
  routes require a Bearer access token); app factory `create_app()`
- Error envelope on every non-2xx: {"error": {code, message, details}}
  (422 details never echo input; 500 is generic + logged)
- CORS: origins from CORS_ORIGINS in .env (localhost, 10.0.2.2)
- Swagger at /docs with Authorize (HTTPBearer)
- SECRET_KEY: real random value in backend/.env only (min 32 chars enforced)
- Tests: 324/324 pass (unit 204, integration 49, api 71), 100% coverage
- All 7 gates: PASS
- No new migration (still f7794967963c)

### Phase 3 — Gemini AI Integration + SymPy Verification ✅ COMPLETE
- POST /api/v1/tutor/ask (JWT) -> TutorResponse {question, explanation,
  steps, formulas_used, sympy_verified, verification_confidence,
  verification_status, topic, unit, warning}
- services/ai: gemini_service (injectable transport, retries 5xx only),
  prompts (TutorPrompt has NO personal fields), privacy (scrubs email/
  phone/CNIC), rate_limiter (per-minute + per-day, warns at 80%)
- services/mathematics/verifier.py: verify_identity / verify_numeric /
  verify_expression; >=5 random points; hardened parser (no builtins,
  unevaluated functions, size/exponent/tower limits, prose -> unverifiable)
- services/tutor/tutor_service.py: DB context -> Gemini -> SymPy -> response
- Errors: 429 ai_quota_exceeded (+Retry-After), 503 ai_unavailable /
  ai_not_configured, 504 ai_timeout, 502 ai_bad_response
- Timeouts: TUTOR 30s total = Gemini 25s budget + SymPy 5s
- Tests: 512/512 pass (unit 354, integration 62, api 96), 100% coverage;
  Gemini is ALWAYS faked in tests (tests/fakes.py)
- Fix (after Phase 3): model 3.5-flash + 3.1-flash-lite fallback on 404;
  tests now 521/521, 100% coverage
- Fix: LOG_LEVEL wired + request logging; fallback also on 429 with
  cooldown. Tests 544/544 (unit 386, integration 62, api 96), 100% coverage
- All 7 gates: PASS

### Phase 4 — Flutter UI ✅ COMPLETE
- Screens: Splash, Login, Register, Home (12 units), Unit detail (topics +
  difficulty badges), Topic detail (formulas, Ask AI, recent questions),
  Tutor (chat, loading, markdown, numbered steps, formula chips,
  verification badge, yellow warning, errors with retry, language menu)
- State: provider (AuthProvider, UnitsProvider); services: ApiService
  (Bearer JWT, silent refresh on 401 then logout), AuthService,
  StorageService (tokens + per-topic recent questions, wiped on logout)
- API URL: lib/core/constants.dart; default http://10.0.2.2:8000; override
  with --dart-define=API_BASE_URL=http://<ip>:8000 (no code change)
- Packages: http, provider, shared_preferences, flutter_markdown_plus
  (flutter_markdown is discontinued), loading_animation_widget.
  google_fonts NOT used: its objective_c native hook breaks because the
  Flutter SDK path has a space; Poppins is bundled via pubspec `fonts:`.
- minSdk = Flutter default 24 (Flutter 3.47 cannot build below API 23)
- Cleartext HTTP allowed in debug/profile manifests only
- Tests: Flutter 87 (97.5% line coverage) — mock HTTP (FakeBackend in
  test/helpers.dart), no real API calls; backend unchanged 544
- All 7 gates: PASS

### Phase 5 — Practice & Progress Tracking ✅ COMPLETE (awaiting approval for Phase 6)
- Migration 379d357d50ab: practice_questions.correct_answer / answer_explanation /
  options (JSON, MCQ only; CHECK mcq <=> options NOT NULL; JSON(none_as_null=True)),
  student_progress.correct_count / points, new table practice_attempts
- Endpoints (JWT): GET /practice/random?unit_id=&count=5 (no answers, proofs
  excluded), POST /practice/submit, GET /progress/, GET /progress/weak-topics (<60%)
- Grading: services/practice/answer_matching.py — MCQ exact/letter match; else SymPy
  part-by-part (labels, ±, i, degrees, √, units, rounding >= 2 dp), fallback difflib
  >= 0.85. NO Gemini. Runs in a thread with sympy_timeout_seconds.
- practice_service.py: evaluate_answer, calculate_points (10/20/30, +5 under 60 s),
  get_encouragement (Urdu/English), PracticeService (locks user row FOR UPDATE)
- Points only the FIRST time a question is solved (already_solved flag) — anti-farming
- repositories/progress_repository.py: get_or_create_progress, update_after_attempt,
  get_overall_progress, get_unit_progress, get_weak_topics, current_streak, ...
- Flutter: bottom nav (Units / Practice / Progress), PracticeScreen, ProgressScreen,
  models practice_question / practice_result / progress, services practice_service /
  progress_service, route /practice (PracticeRouteArgs)
- Tests: backend 842 (unit 627, integration 88, api 127), 100% coverage;
  Flutter 122, 98.3% line coverage
- All 7 gates: PASS

## Current Phase
### None in progress — waiting for user approval to start Phase 6

## Phase 2 Tasks (done)
1. JWT authentication (login, register, token refresh)
2. Password hashing already done (scrypt) — wire it up
3. API routes in app/api/:
   - POST /api/v1/auth/register
   - POST /api/v1/auth/login
   - GET  /api/v1/auth/me
   - GET  /api/v1/units/
   - GET  /api/v1/units/{unit_id}
   - GET  /api/v1/units/{unit_id}/topics
   - GET  /api/v1/topics/{topic_id}
   - GET  /api/v1/topics/{topic_id}/formulas
   - GET  /api/v1/topics/{topic_id}/questions
4. Protected routes — require valid JWT token
5. CORS configured for Flutter (10.0.2.2 for emulator)
6. API error handling (404, 422, 401, 500)
7. Swagger docs working at /docs
8. Tests for every endpoint (auth + content)
9. All 7 quality gates must pass
10. Update CLAUDE.md and DEVELOPMENT_LOG.md

## Upcoming Phases (Do Not Start Without Approval)
(Phases 0-5 done. The AI tutor chat screen was delivered in Phase 4; the user
re-numbered Practice & Progress as Phase 5.)
Phase 6+: as specified by the user (remaining from the original plan: polish,
offline support, final testing)

## Important Notes
- Topics list is best-guess reconstruction — 
  verify against DCAR textbook
- Practice answer key lives in syllabus/question_patterns/practice_questions.json;
  every short/long answer must be SymPy-checkable (a test enforces it). Proofs are
  stored but never served for practice (not gradable without AI).
- Android SDK not yet installed — needed for 
  flutter run and APK builds
- Postgres superuser password was changed after 
  Phase 0 security review
- Ruff security rules relaxed in test files only 
  (not in app code)
- Shared DB fixtures live in backend/tests/conftest.py; tests refuse to
  run against a DB whose name lacks "test"
- Tokens are stateless: no logout/revocation yet; no login rate limiting
  yet — consider before production
- docs/TESTING.md and docs/PRD.md written (Phase 3 start)
- GEMINI MODELS (user-approved 2026-11-11):
  GEMINI_MODEL=gemini-3.5-flash (primary)
  GEMINI_FALLBACK_MODEL=gemini-3.1-flash-lite
  Fallback triggers: HTTP 404 (model unavailable -> skipped for the rest of
  the process) and HTTP 429 (that model's quota -> cooldown for Google's
  retryDelay, else 60s). All models cooling down -> 429 immediately, no
  request spent. Both 404 -> 503 ai_model_unavailable. 5xx/401/400 never
  switch models. The LOCAL RateLimiter is app-wide and does NOT trigger
  fallback. gemini-2.5-flash is retired for new keys (404).
  Live check 2026-11-11: POST /tutor/ask -> 200 in 9.5s from
  gemini-3.5-flash, Roman-Urdu/English steps, sympy_verified=true.
- Logging: LOG_LEVEL (.env, case-insensitive, validated) configures the
  "app" logger in create_app (app/core/logging.py). Middleware
  app/api/middleware.py logs "METHOD /path -> status (ms)" — path only,
  never query string/headers/body. Tutor logs which model answered.
- SymPy has no type stubs: mypy override ignore_missing_imports for sympy
- Never use the Edit/Write tools to write "\uXXXX" escapes — they get
  converted to literal characters (RUF001). Use a script with chr(92).
- Flutter SDK moved to C:\src\flutter (no space) during Phase 5; ran
  `flutter pub get` to fix the stale package_config. Flutter is not on PATH in
  tool shells: prepend the User+Machine PATH from the registry before calling
  flutter. (google_fonts was dropped in Phase 4 because of the old space.)
- Android SDK still not installed: the app has never run on a device;
  flutter analyze/test only. Install Android Studio to run the app.
- PowerShell Set-Content/Get-Content mangle UTF-8 (em dash -> mojibake);
  prefer Edit/Write or Python for text edits.
- Bash heredocs with mixed quotes sometimes fail in the tool shell; write files
  with the Write tool (or a Python script) instead.
