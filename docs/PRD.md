# Product Requirements: MathMentor AI

| | |
|---|---|
| Product | MathMentor AI (Android app and backend) |
| Audience | HSC-I (Class 11) students, Sindh Board (DCAR) Mathematics |
| Status | **v1.0 complete** (Phases 0–6, 2026-11-11; see `DEVELOPMENT_LOG.md`) |
| Constraint | Free tier only: no paid APIs or cloud services |

## 1. Problem

Class 11 students in Sindh often have no one to ask when they get stuck on a textbook exercise
outside school hours. Tuition costs money. Generic AI chatbots ignore the Sindh Board syllabus,
answer only in English, and can be confidently wrong about mathematics.

## 2. Goal

A patient, syllabus-aligned tutor in the student's pocket. It explains **step by step**, in
**simple Urdu/English**, and **never presents an unverified answer as certain**.

### Success measures
| Metric | Target |
|---|---|
| Answers with verifiable math that SymPy confirms | ≥ 90% |
| Verified-wrong answers shown without a warning | 0 |
| Tutor response time (p90) | ≤ 15 s |
| Syllabus coverage | All 12 units with topics, formulas and practice questions |
| Students who return within 7 days | ≥ 40% (once launched) |

## 3. Users

- **Primary: the HSC-I student** (around 16–17 years old). Uses an Android phone, often on
  mobile data, and is comfortable with Roman-Urdu/English code-mixing.
- **Secondary: teachers and parents.** Later phases may give them a read-only view of progress.

## 4. Scope

### In scope
1. **Accounts:** register and log in with email and password. JWT sessions with refresh
   tokens.
2. **Syllabus browser:** 12 units, then their topics, then formulas and practice questions for
   each topic, matching the DCAR textbook order and page numbers.
3. **AI tutor:** the student asks a question about a topic and gets back an explanation,
   numbered steps, and the formulas used.
   - Each answer carries a verification badge: verified, could not verify, or possible error.
   - The student chooses the language: Urdu/English mix (the default) or English.
4. **Practice:** topic-wise questions with difficulty levels, and grading against stored
   answers.
5. **Progress:** per-topic score, attempt count and last activity, plus weak-topic hints.
6. **Responsive UI:** units, topics, formulas and progress are cached in memory for the
   session, so screens reopen instantly. Every request has a loader, a friendly error and
   a retry. The app itself needs a connection: there is no persistent offline mode in
   v1.0.

### Out of scope (for now)
Payments, iOS, HSC-II and other boards, handwriting/photo recognition, live human tutoring,
and social features.

## 5. Functional requirements

| ID | Requirement | Phase |
|---|---|---|
| FR-1 | Register with a unique email, a name, and a password of 8 or more characters | 2 ✅ |
| FR-2 | Log in and receive access and refresh tokens; refresh without logging in again | 2 ✅ |
| FR-3 | List units and topics, and view a topic's formulas and questions (logged-in users only) | 2 ✅ |
| FR-4 | Ask the tutor a question (up to 500 characters) for a topic; get explanation, steps and formulas | 3 ✅ |
| FR-5 | SymPy verifies every machine-checkable claim; the result is exposed as `sympy_verified` plus a confidence score | 3 ✅ |
| FR-6 | If verification is impossible or fails, the answer is still shown with a clear warning | 3 ✅ |
| FR-7 | Gemini outages, timeouts and quota limits return a friendly error, never a crash | 3 ✅ |
| FR-8 | Flutter screens: splash, login, register, unit list, topic list, topic detail | 4 ✅ |
| FR-9 | Tutor chat screen with step cards, Markdown rendering, a verification badge and a language choice | 4 ✅ |
| FR-10 | Practice mode graded by SymPy without AI; progress dashboard with weak topics | 5 ✅ |
| FR-11 | Polish: app icon, empty states, keyboard handling, back-button guards, caching, 30 s timeouts with retry, silent token refresh, release signing | 6 ✅ |

### v1.0 feature list (final)

| Area | Delivered |
|---|---|
| Accounts | Register and login, JWT access (60 min) and refresh (7 days) tokens, silent refresh and retry when a token expires mid-session, logout with confirmation |
| Syllabus | 12 units, 52 topics, 72 formulas (39 checked as identities by SymPy) in DCAR textbook order with page numbers, and difficulty badges |
| AI tutor | Gemini 3.5 Flash with a 3.1 Flash-Lite fallback; Urdu/English or English; numbered steps, formulas used, a verified / could-not-verify / possible-error badge; PII scrubbing; per-minute and per-day limits; recent questions kept per topic |
| Practice | 32 gradable questions (16 MCQ, 8 short, 8 long), 5 at a time, filterable by unit; SymPy grading tolerates labels, ±, i, degrees, √, units and rounding; points (10/20/30, +5 for speed) only the first time a question is solved; streaks; Urdu/English encouragement |
| Progress | Points, accuracy, streak, per-unit bars and weak topics (< 60%) with a "practise this unit" shortcut; cached data appears instantly and refreshes in the background; empty states for new students |
| UX | Bottom navigation, a loader on every request, friendly Roman-Urdu errors with retry, tapping outside a field closes the keyboard, the tutor scrolls with the keyboard, back-button guards, and a math-themed launcher icon |
| Android | minSdk 24; release builds HTTPS-only (loopback allowed for USB testing); signing from a gitignored `key.properties`; backend chosen with `--dart-define` (`API_TARGET=usb` / `API_BASE_URL`) |
| Quality | 7 gates on every commit; backend 842 tests at 100% coverage; Flutter 137 tests at 98% line coverage |

## 6. Non-functional requirements

- **Accuracy:** the LLM explains and SymPy verifies. A wrong answer is never labelled
  verified.
- **Privacy:**
  - No personal data (name, email, phone, CNIC) is sent to Gemini.
  - Free-text questions are scrubbed of contact details before leaving the server.
  - Passwords are hashed with scrypt, and secrets live only in `.env`.
- **Security:**
  - JWT with a pinned algorithm.
  - Generic login errors, with timing that doesn't reveal which emails exist.
  - Validation errors never echo what was submitted.
  - Generic 500 errors.
- **Cost:** Gemini free tier only. The backend enforces per-minute and per-day request limits
  so the app degrades gracefully instead of failing at the quota.
- **Performance:** the tutor endpoint has a hard 30-second timeout. Content endpoints
  respond in under 200 ms locally.
- **Quality:** the 7 quality gates must pass before every commit, and coverage must stay at or
  above 90%.

## 7. Key risks

| Risk | Mitigation |
|---|---|
| LLM gives wrong math | SymPy verification, a warning badge, and practice grading against stored answers |
| Free-tier quota exhausted | Local rate limiter, a clear "try again later" message, and an automatic fallback from `gemini-3.5-flash` to `gemini-3.1-flash-lite` |
| Syllabus mismatch | Seed data lives as reviewable JSON; topics must be checked against the DCAR textbook |
| Students paste personal info | PII scrubber, and the prompt is built from a schema with no personal fields |

## 8. Open questions

- Should units and topics be browsable without logging in?
- Should a failed SymPy check trigger an automatic second Gemini attempt? Each retry costs free
  quota.
- Who curates and approves practice-question answers? The 36 answers pass automated SymPy
  checks but still need a teacher's review against the DCAR textbook.
- Hosting: a public deployment needs HTTPS, plus login rate limiting and token revocation,
  before real students use it.
- Persistent offline mode (an on-device cache across app restarts) is a candidate for v1.1.
