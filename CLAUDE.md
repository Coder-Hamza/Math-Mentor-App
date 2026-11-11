# ✅ PROJECT COMPLETE — MathMentor AI v1.0 (Phases 0-6 done, 2026-11-11)

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
│   │   ├── unit/        # 669 tests
│   │   ├── integration/ # 88 tests
│   │   └── api/         # 144 tests
│   └── alembic/
├── mobile/test/         # 188 Flutter tests (99.0% line coverage)
├── syllabus/
│   ├── chapters/units.json        # 12 units
│   ├── topics/topics.json         # 52 topics
│   ├── formulas/formulas.json     # 72 formulas
│   └── question_patterns/         # 36 questions + answer key
│                                  # (16 mcq, 8 short, 8 long, 4 proof)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── PRD.md
│   ├── RELEASE.md       # signing key + APK build steps
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

### Phase 5 — Practice & Progress Tracking ✅ COMPLETE
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

### Phase 6 — Final Polish, Phone Testing Prep & APK Build ✅ COMPLETE
- API URL: default emulator 10.0.2.2; --dart-define=API_TARGET=usb -> 127.0.0.1
  (with adb reverse tcp:8000 tcp:8000); --dart-define=API_BASE_URL=... overrides both
- Requests time out after 30 s (tutor 40 s) with retry; silent refresh + retry tested
- App icon (+ - x / on #1565C0): mobile/tool/make_icon.py -> assets/icon ->
  `dart run flutter_launcher_icons` (dev dependency, config in pubspec.yaml)
- Empty states (AppStrings.noProgress / noWeakTopics), DismissKeyboard in
  MaterialApp.builder, tutor scrolls on keyboard open, tutor back-guard for unsent
  question, Home back -> Units tab
- ProgressService caches last progress (shown instantly, background refresh), wiped on
  logout; units/topics/formulas cached in UnitsProvider
- Android: minSdk 24 explicit; network_security_config per build type (release: HTTPS
  only except 127.0.0.1/localhost; debug/profile: cleartext); release signing from
  android/key.properties (gitignored, template key.properties.example), falls back to
  debug key when absent. NOT compiled yet (no Android SDK).
- docs/RELEASE.md; README rewritten as full setup + phone test guide
- Tests: backend 842, 100% coverage (unchanged); Flutter 137, 98.3% line coverage
- All 7 gates: PASS

### UI Upgrade — Glassmorphism + Dark/Light Mode ✅ COMPLETE (awaiting approval)
- Mobile only; backend untouched. AppColors REMOVED: every colour comes from
  `GlassPalette` (ThemeExtension in core/theme.dart, read with `context.palette`;
  dark = default, light). Theme switch lerps over 400 ms (themeAnimationDuration).
- ThemeProvider (providers/theme_provider.dart): isDarkMode (default true),
  toggleTheme(), saved in SharedPreferences 'isDarkMode' via StorageService;
  survives logout (clearUserData does not touch it). ThemeToggleButton
  (key 'theme-toggle') sits in every app bar via GlassScaffold.
- Widgets: glass_card.dart (GlassCard, GlassPill, GradientText, GradientButton,
  GradientCircle, TapScale 0.95/100 ms, SectionHeader), gradient_background.dart
  (gradient + 3 radial-gradient "orbs", 1.2 s entry then idle, owns BackdropGroup),
  glass_scaffold.dart (GlassScaffold, ThemeToggleButton, GlassBottomBar),
  motion.dart (Appear: 200 ms fade+slide), LoadingWidget = ShimmerBar.
- Performance rules: blur = BackdropFilter.grouped (shared backdrop per screen);
  list cards pass blur: false; NO blur and NO ambient motion when
  MediaQuery.disableAnimations (OS "remove animations") = low-end fallback;
  background never animates while idle. Shadows use BlurStyle.outer (normal
  shadows grey the translucent glass).
- Home paints ONE background for all tabs: tab screens use
  GlassScaffold(background: false); PracticeScreen(inTab: true) from Home.
- Page transitions: FadePageTransitionsBuilder (300 ms) on all platforms.
- Packages: +flutter_animate ^4.5.2 (splash title only — it schedules a
  Future.delayed per widget, so list animations use Appear instead);
  -loading_animation_widget.
- Tests: Flutter 168 (+31: test/screens/theme_test.dart), 98.8% line coverage;
  backend 842, 100% (unchanged). All 7 gates: PASS.
- Screenshots can be rendered from widget tests (load Poppins + MaterialIcons
  with FontLoader, capture the root layer with physical size); emoji show as
  boxes in the test renderer only.

### Feature — Smart Question Solver ✅ COMPLETE (awaiting approval)
- POST /api/v1/solver/solve (JWT): SolverRequest {chapter_name<=200, question<=1000,
  book_answer<=500|null ("" -> null), grade_level="HSC-I", language} ->
  SolverResponse {question, chapter, solution, steps[{step_number, title, explanation,
  formula_used, calculation}], method_used, formulas_applied, key_concepts,
  answer_verified, book_answer, our_answer, sympy_verified, difficulty_level, pro_tip,
  warning}. Errors as tutor: 401/422/429/502/503/504.
- Gemini returns JSON (schemas/solver_schemas.py GeminiSolverAnswer); the SERVER renders
  `solution` in the textbook pattern (services/ai/solver_prompts.py render_solution:
  Sawal / Diya hua / Poochha gaya / Hal / Qadam n / Jawab / Exam Tip). SolverPrompt has
  no personal fields; chapter, question and book answer are PII-scrubbed. With a book
  answer the prompt says "Book ka jawab hai: X. Isi jawab tak pohoncho."
- services/tutor/solver_service.py: sympy_verified = tutor `summarize` over Gemini's
  checks; answer_verified = book answer given AND answers_match (practice
  answer_matching: SymPy equivalence, labels/±/i/√/rounding; similarity fallback).
  Warnings: book mismatch, SymPy failed, check timeout, unstructured (raw text shown).
- Timeouts: solver_timeout_seconds=45 -> Gemini 40 s (per attempt AND total) + SymPy
  5 s. GeminiService._call now takes config + attempt_seconds (tutor unchanged: 25 s).
- Flutter: Solver is bottom-nav tab 1 (Units, Solver, Practice, Progress; type fixed);
  screens/solver/solver_screen.dart (form -> loading -> result: header, expandable Qadam
  cards with Urdu ordinals, formula/concept chips, answer card with book match, SymPy
  pill, amber Exam Tip, "Dobara Solve Karo", "AI Tutor se poochein" -> matchUnit()
  picks the unit from the chapter name, else a unit picker; question cut to 500).
  models/solver_result.dart, services/solver_service.dart (timeout 55 s).
- Tests: backend 901 (unit 669, integration 88, api 144), 100% coverage; Flutter 188,
  99.0% line coverage. All 7 gates: PASS.

## Current Phase
### None — awaiting approval after the Smart Question Solver. Any further work needs explicit user approval.

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

## Possible Follow-ups (Do Not Start Without Approval)
- Install Android Studio, run on a real phone, build the signed APK (README §3-6)
- Login rate limiting + token revocation + HTTPS hosting before public use
- Persistent offline cache across app restarts (v1.1 candidate)
- Teacher review of topics/answers against the DCAR textbook

## Important Notes
- Topics list is best-guess reconstruction — 
  verify against DCAR textbook
- Practice answer key lives in syllabus/question_patterns/practice_questions.json;
  every short/long answer must be SymPy-checkable (a test enforces it). Proofs are
  stored but never served for practice (not gradable without AI).
- Android SDK not yet installed — needed for 
  flutter run and APK builds (flutter doctor 2026-11-11: Android toolchain X)
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
