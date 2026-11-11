# MathMentor AI v1.0

An AI math tutor for Sindh Board HSC-I (Class 11) students. Gemini writes step-by-step
Urdu/English explanations, and SymPy verifies every answer before a student sees it.
Students can also practise board-style questions, graded without AI, and track their
progress.

| Folder | What it holds |
|---|---|
| `backend/` | FastAPI + SQLAlchemy + PostgreSQL + SymPy + Gemini (Python 3.14, managed with uv) |
| `mobile/` | Flutter Android app (Android 7.0+, API 24) |
| `syllabus/` | Seed data: 12 units, 52 topics, 72 formulas, 36 practice questions with an answer key |
| `docs/` | `ARCHITECTURE.md`, `PRD.md`, `TESTING.md`, `RELEASE.md`, `DEVELOPMENT_LOG.md` |

## Contents
1. Requirements
2. Start the backend
3. Android SDK setup (once)
4. Run the app (emulator, USB phone, Wi-Fi phone)
5. Manual test checklist
6. Build a release APK
7. Quality gates
8. Troubleshooting

---

## 1. Requirements

| Tool | Version |
|---|---|
| Python | 3.14 (with [uv](https://docs.astral.sh/uv/) 0.11+) |
| PostgreSQL | 18 (local) |
| Flutter | 3.47 / Dart 3.13, installed at a path **without spaces**, e.g. `C:\src\flutter` |
| Android Studio | Latest (provides the Android SDK, platform-tools/`adb`, emulator, JDK) |
| Gemini API key | Free tier, from https://aistudio.google.com/apikey |

## 2. Start the backend

```powershell
cd backend
copy .env.example .env               # fill in DATABASE_URL, SECRET_KEY, GEMINI_API_KEY
uv sync
uv run alembic upgrade head          # creates / upgrades the tables
uv run python -m app.database.seed   # loads the syllabus (safe to re-run)
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- Check it: http://localhost:8000/docs (Swagger) should open.
- `--host 0.0.0.0` is only needed for a phone on **Wi-Fi**. For the emulator and for USB
  with `adb reverse`, `--host 127.0.0.1` is enough and safer.
- After pulling a change that adds a migration, run `alembic upgrade head` and then the
  seed again. The seed is idempotent.

Main endpoints, all under `/api/v1` and all requiring JWT except register and login:

| Area | Endpoints |
|---|---|
| Auth | `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `GET /auth/me` |
| Syllabus | `GET /units/`, `/units/{id}`, `/units/{id}/topics`, `/topics/{id}`, `/topics/{id}/formulas`, `/topics/{id}/questions` |
| AI tutor | `POST /tutor/ask`: Gemini explanation plus SymPy verification |
| Practice | `GET /practice/random?unit_id=&count=5`, `POST /practice/submit`: graded by SymPy, no AI |
| Progress | `GET /progress/`, `GET /progress/weak-topics` |

## 3. Android SDK setup (once)

`flutter doctor` must show **[√] Android toolchain**. If it says *Unable to locate Android
SDK*:

1. Install **Android Studio** from https://developer.android.com/studio and run it once.
   The setup wizard downloads the SDK to `%LOCALAPPDATA%\Android\Sdk`.
2. In Android Studio, open **More Actions → SDK Manager**:
   - **SDK Platforms**: tick the latest Android platform.
   - **SDK Tools**: tick *Android SDK Command-line Tools (latest)*, *Android SDK
     Platform-Tools*, and *Android SDK Build-Tools*. Click Apply.
3. Tell Flutter where the SDK is, and accept the licences:
   ```powershell
   flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
   flutter doctor --android-licenses      # answer y to each
   ```
4. Put `adb` on your PATH: add `%LOCALAPPDATA%\Android\Sdk\platform-tools` to the user
   PATH, then open a new terminal.
5. `flutter doctor` should now show the Android toolchain as OK. The *Visual Studio* item
   only matters for Windows desktop apps and can be ignored.

Optional emulator: **Device Manager → Create device**, for example a Pixel with a recent
system image.

## 4. Run the app

```powershell
cd mobile
flutter pub get
flutter devices                      # your emulator / phone must be listed
```

The backend URL is chosen at build time, with no code change:

| Where the app runs | Command | App calls |
|---|---|---|
| Android emulator | `flutter run` | `http://10.0.2.2:8000` |
| **Phone via USB (recommended)** | `adb reverse tcp:8000 tcp:8000`<br>`flutter run --dart-define=API_TARGET=usb` | `http://127.0.0.1:8000` |
| Phone on the same Wi-Fi | `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000` | your PC's IPv4 from `ipconfig` |

`API_BASE_URL` overrides `API_TARGET`. Debug builds allow plain HTTP. Release builds allow
it only for `127.0.0.1` (see section 6).

### Step by step: real phone over USB

1. **Start the backend** (section 2) in its own terminal and leave it running.
2. **Prepare the phone**, once: Settings → About phone → tap **Build number** 7 times.
   Then Settings → System → Developer options → turn on **USB debugging**.
3. **Connect the USB cable.** On the phone, accept *Allow USB debugging?* and tick
   *Always allow*.
4. **Check that it is seen:**
   ```powershell
   adb devices            # shows   <serial>   device   (not "unauthorized")
   ```
5. **Forward the port** so the phone's `127.0.0.1:8000` reaches the PC:
   ```powershell
   adb reverse tcp:8000 tcp:8000
   adb reverse --list     # shows   tcp:8000 tcp:8000
   ```
   Run this again whenever you unplug the phone or restart adb.
6. **Launch the app:**
   ```powershell
   cd mobile
   flutter run --dart-define=API_TARGET=usb
   ```
   The first build takes a few minutes. Press `r` to hot-reload and `q` to quit.

If you have more than one device, add `-d <serial>` from `flutter devices`.

## 5. Manual test checklist

Run through these on the phone after every release candidate.

| # | Screen | What to check |
|---|---|---|
| 1 | **Splash** | Logo, then Login on first launch, or Home if already logged in |
| 2 | **Register** | Bad email or short password shows field errors. An existing email shows "pehle se bana hua". Success goes to Home. |
| 3 | **Login** | A wrong password shows a friendly error and the spinner on the button. Tapping outside a field closes the keyboard. |
| 4 | **Home / Units** | 12 units load once. Pull down to refresh. Logout asks for confirmation. Back on the Practice/Progress tab returns to Units. |
| 5 | **Unit detail** | Topics with green, orange and red difficulty badges. Going back and in again does not reload them, because they are cached. |
| 6 | **Topic detail** | Formulas expand. "Ask AI Tutor" works. "Recent questions" appears after asking. |
| 7 | **AI Tutor** | Ask "z = 3 + 4i ka modulus kya hai?". The loader shows, and an answer arrives in about 10–20 s with steps and a verification badge. Switch the language. Typing a question and pressing back asks before leaving. With the keyboard open, the latest answer stays visible. |
| + | **Practice tab** | 5 questions. MCQ and typed answers are graded. Points, then a summary, then "Dobara Khelo". |
| + | **Progress tab** | A new account shows "Abhi koi sawaal hall nahi kiya...". After practice, stats and unit bars appear. Reopening shows the old numbers instantly while it refreshes. |

Resilience checks:
- **Stop the backend**, then pull to refresh. You should see "Server se connection nahi
  hua" with a retry button. Start the backend and tap retry.
- **Airplane mode** shows "Internet connection check karein".
- **Slow network:** normal requests give up after 30 s with a retry button. The tutor
  waits up to 40 s.
- **Token expiry:** after 60 minutes the app refreshes the token silently and repeats
  the request. You are only sent to Login if the 7-day refresh token has also expired.

## 6. Build a release APK

Full steps, including creating the signing key, are in **`docs/RELEASE.md`**. Short
version:

```powershell
cd mobile\android
copy key.properties.example key.properties   # fill in; this file is gitignored
cd ..
flutter build apk --release --dart-define=API_TARGET=usb
# -> build\app\outputs\flutter-apk\app-release.apk
```

## 7. Quality gates

All 7 must pass before every commit:

```powershell
cd backend
uv run ruff format --check .
uv run ruff check .
uv run mypy app
uv run pytest -v
uv run pytest --cov=app --cov-report=term-missing
cd ..\mobile
flutter analyze
flutter test
```

The backend tests need the `mathmentor_test` database. Gemini is always faked in tests,
and Flutter tests use a mocked HTTP backend. See `docs/TESTING.md`.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| App: "Server se connection nahi hua" | Is uvicorn running? For USB, run `adb reverse tcp:8000 tcp:8000` again. For Wi-Fi, use `--host 0.0.0.0` and allow TCP 8000 in Windows Firewall. |
| `adb devices` shows `unauthorized` | Unlock the phone and accept the USB debugging prompt, or revoke the authorisations in Developer options and reconnect |
| `adb` not found | Add `%LOCALAPPDATA%\Android\Sdk\platform-tools` to PATH |
| Tutor: "AI tutor abhi bohat busy hai" | The free-tier Gemini quota is used up. Wait a minute, or until the next day for the daily limit. |
| Build fails with a path error | Flutter must live in a path without spaces, e.g. `C:\src\flutter` |
| Release APK cannot connect | Release builds block `http://` except `127.0.0.1`. Use HTTPS or `API_TARGET=usb`. |

## Regenerating the app icon

```powershell
cd mobile
python tool/make_icon.py assets/icon       # needs Pillow
dart run flutter_launcher_icons
```
