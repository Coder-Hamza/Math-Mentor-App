# MathMentor AI — System Architecture

MathMentor AI is a step-by-step mathematics tutor for Sindh Board HSC-I (Class 11, DCAR)
students. Explanations use a simple Urdu/English mix. **Every mathematical result shown to a
student must be verified by SymPy before it is returned.**

## 1. Constraints

| Constraint | Decision |
|---|---|
| Cost | Free tier only: Gemini via Google AI Studio, local PostgreSQL, no Firebase, no cloud DB |
| Accuracy | The LLM writes the explanations. SymPy checks the answers. Pydantic checks the structure. |
| Privacy | No student PII (name, phone, school, account ID) is ever sent to Gemini |
| Platform | Android (Flutter) client, Python 3.14 + FastAPI 0.156.8 backend |

## 2. High-level flow

```
┌──────────────┐  HTTPS/JSON   ┌────────────────────────── FastAPI backend ───────────────────────────┐
│ Flutter app  │ ────────────► │ api/ (routers) ─► services/tutor (orchestrator)                       │
│ (Android)    │               │                        │                                              │
│              │ ◄──────────── │                        ├─► services/ai        ─► Gemini API (free)    │
└──────────────┘  structured   │                        │      (PII-scrubbed prompt, JSON output)      │
                  response     │                        ├─► services/mathematics (SymPy verification) │
                               │                        ├─► schemas/ (Pydantic 2 validation)           │
                               │                        └─► repositories/ ─► PostgreSQL (localhost)    │
                               └───────────────────────────────────────────────────────────────────────┘
```

### Request lifecycle: "solve / explain a question"
1. **Flutter** sends `{question_text, unit_id, topic_id}`. It sends no personal data.
2. **API layer** validates the request with a Pydantic schema and checks authentication.
3. **Tutor service** classifies the question against the syllabus (unit, topic, question pattern).
4. **Mathematics service (SymPy)** tries to compute the answer independently when the question
   type supports it (complex numbers, matrices, determinants, vectors, series, binomial, trig
   identities and equations, and so on).
5. **AI service (Gemini)** gets a scrubbed prompt and returns *structured JSON*: steps, final
   answer, and hints in Urdu/English.
6. **Verification:** Gemini returns up to 10 `checks`. Each is an `{lhs, rhs}` pair in SymPy
   syntax that must be either an identity or a numeric fact, such as the answer substituted
   back into the equation. SymPy evaluates each pair at 5 or more random points, using
   numeric `evalf` only and a hardened parser (see `services/mathematics/verifier.py`).
   - All checkable claims hold: `sympy_verified: true`, status `verified`.
   - Any claim is wrong: status `failed`, `sympy_verified: false`, and a warning. The answer
     is still shown, and a wrong answer is never labelled verified. There is no automatic
     retry, which saves free-tier quota.
   - Nothing could be checked (proofs, prose, plain-text replies): status `unverifiable`, with
     a warning.
7. **Pydantic** validates the final response model. Invalid LLM JSON is a handled error, not a
   500.
8. **Repository** stores the attempt and progress in PostgreSQL.

## 3. Backend layers (`backend/app/`)

| Package | Responsibility | May depend on |
|---|---|---|
| `api/` | FastAPI routers, HTTP concerns, dependency injection | schemas, services |
| `core/` | Settings (pydantic-settings), logging, security, errors | — |
| `database/` | SQLAlchemy 2 engine, session factory, `Base` | core |
| `models/` | SQLAlchemy ORM models | database |
| `schemas/` | Pydantic 2 request/response and LLM-output contracts | — |
| `repositories/` | All DB access (no SQL outside this layer) | models, database |
| `services/ai/` | Gemini client, prompt templates, PII scrubber, rate limiter, JSON parsing | core, schemas |
| `services/mathematics/` | SymPy solvers and verifiers per syllabus unit | schemas |
| `services/tutor/` | Orchestration: classify → solve → explain → verify | ai, mathematics, repositories |
| `services/practice/` | Practice question generation and grading (SymPy-graded) | mathematics, ai, repositories |

Rule: dependencies point downward only. `api` never imports `repositories` directly, and
`mathematics` never calls Gemini.

## 4. Data model (initial sketch, finalized in Phase 1)

- `units`: 12 syllabus units (number, title, textbook start page)
- `topics`: topics within a unit
- `formulas`: canonical formulas (LaTeX plus a SymPy expression string)
- `question_patterns`: board-exam question templates per topic
- `students`: local account (pseudonymous ID; PII stays here, never sent to the LLM)
- `attempts`: question, LLM response, verification status, correctness, timestamp
- `progress`: per-student, per-topic mastery

Syllabus seed data lives in `/syllabus/*` as version-controlled JSON/YAML and is loaded through
Alembic data migrations or a seed script.

## 5. Syllabus coverage

| # | Unit | Pg | SymPy verifiability |
|---|---|---|---|
| 1 | Complex Numbers | 1 | High |
| 2 | Matrices & Determinants | 25 | High |
| 3 | Vectors | 74 | High |
| 4 | Sequences & Series | 124 | High |
| 5 | Miscellaneous Series | 162 | High (`summation`) |
| 6 | Permutation, Combination & Probability | 179 | High (numeric) |
| 7 | Mathematical Induction & Binomial Theorem | 214 | Binomial: high. Induction proofs: partial (base case and identity checks) |
| 8 | Functions & Graphs | 238 | Medium (domain/range, inverse, composition) |
| 9 | Linear Programming | 267 | High (vertex enumeration) |
| 10 | Trig Identities: Sum & Difference | 292 | High (`trigsimp`, numeric spot-check) |
| 11 | Application of Trigonometry | 317 | Medium/High (triangle solving) |
| 12 | Graphs of Trig & Inverse Trig + Trig Equations | 337 | High for equations (`solveset` on interval) |

## 6. AI integration (Gemini free tier)

- SDK: `google-genai`. The model is configured by `GEMINI_MODEL` and is not hardcoded.
- Structured output: a JSON schema derived from Pydantic models, then validated with Pydantic.
- Guardrails:
  - A 30-second budget for the endpoint: Gemini gets 25 s and SymPy gets 5 s.
  - Retries only for transient 5xx and network errors.
  - A process-wide rate limiter with per-minute and per-day limits that logs a warning at
    80% of either limit.
  - Errors that map to friendly responses: 429 with `Retry-After` (quota), 503 (unavailable
    or not configured), 504 (timeout), 502 (empty reply).
  - Non-JSON replies are shown as plain text marked unverifiable.
- Privacy: `services/ai` accepts only a `TutorPrompt` schema that has no PII fields. A scrubber
  also redacts phone numbers, emails, and CNIC patterns from free text.
- Tests: the Gemini client sits behind a protocol interface and is faked in unit and API tests.
  Real calls run only under `@pytest.mark.gemini`.

## 7. Mobile (`mobile/lib/`)

| Folder | Purpose |
|---|---|
| `core/` | Theme, constants, API base URL, error types |
| `models/` | Dart data classes mirroring backend schemas |
| `services/` | HTTP client for the FastAPI backend |
| `providers/` | State management |
| `screens/` | Unit list, topic view, solver, practice, progress |
| `widgets/` | Step cards, math rendering, verification badge |

From the Android emulator the backend is reachable at `http://10.0.2.2:8000`.

## 8. Quality gates (every phase)

Backend: run these from `backend/` with `uv run`.
1. `ruff format --check .`
2. `ruff check .`
3. `mypy app` (strict)
4. `pytest -v`
5. `pytest --cov=app --cov-report=term-missing`

Mobile: run these from `mobile/`.
6. `flutter analyze`
7. `flutter test`
