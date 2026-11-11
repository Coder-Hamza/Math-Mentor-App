# MathMentor AI

An AI math tutor for Sindh Board HSC-I (Class 11) students. Gemini writes step-by-step
Urdu/English explanations, and SymPy verifies every answer before a student sees it.

- `backend/`: FastAPI + SQLAlchemy + SymPy + Gemini (Python 3.14, managed with uv)
- `mobile/`: Flutter Android app
- `syllabus/`: syllabus seed data (units, topics, formulas, question patterns)
- `docs/`: architecture, PRD, testing, and the development log

## 1. Start the backend

```bash
cd backend
cp .env.example .env              # fill in DB credentials + GEMINI_API_KEY
uv sync
uv run alembic upgrade head       # first time only
uv run python -m app.database.seed  # first time only (12 units, 52 topics, ...)
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` lets a phone on your network reach the server. The API docs are at
http://localhost:8000/docs.

After pulling a change that adds a migration (for example Phase 5's practice answer key),
run `uv run alembic upgrade head` and then `uv run python -m app.database.seed` again. The
seed is idempotent and fills in new columns on existing rows.

### Practice and progress
- `GET /api/v1/practice/random` serves questions without answers.
- `POST /api/v1/practice/submit` grades an answer with SymPy and string matching, without any
  AI call.
- `GET /api/v1/progress/` and `/progress/weak-topics` power the app's Progress tab.

A question earns points (easy 10, medium 20, hard 30, +5 under 60 s) only the first time it
is solved.

## 2. Run the Android app

You need Android Studio, which installs the Android SDK. Afterwards, `flutter doctor` should
show the Android toolchain as OK.

```bash
cd mobile
flutter pub get
flutter devices                   # your emulator / phone must be listed
```

| Where the app runs | Command |
|---|---|
| Android emulator | `flutter run`. The app calls `http://10.0.2.2:8000`, which reaches your PC. |
| Phone via USB (simplest) | `adb reverse tcp:8000 tcp:8000`, then `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000` |
| Phone on the same Wi-Fi | `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000`, using your PC's IPv4 from `ipconfig`. Allow inbound TCP 8000 in Windows Firewall. |

To prepare a phone:
1. Enable **Developer options**: tap *Build number* 7 times.
2. Turn on **USB debugging**, then accept the prompt on the phone.

Debug builds allow plain HTTP to the local backend. Release builds will need HTTPS.

## 3. Quality gates

```bash
cd backend && uv run ruff format --check . && uv run ruff check . && uv run mypy app && uv run pytest --cov=app
cd mobile  && flutter analyze && flutter test
```

See `docs/ARCHITECTURE.md` for the system design and `docs/TESTING.md` for the test
strategy.
