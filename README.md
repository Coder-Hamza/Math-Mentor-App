# MathMentor AI

An AI math tutor for Sindh Board HSC-I (Class 11) students. Gemini writes step-by-step
Urdu/English explanations, and SymPy verifies every answer before a student sees it.

- `backend/`: FastAPI + SQLAlchemy + SymPy + Gemini (Python 3.14, managed with uv)
- `mobile/`: Flutter Android app
- `syllabus/`: syllabus seed data (units, topics, formulas, question patterns)
- `docs/`: architecture, PRD, testing, and the development log

## Backend quick start
```bash
cd backend
cp .env.example .env      # fill in DB credentials + GEMINI_API_KEY
uv sync
uv run uvicorn app.main:app --reload
```

See `docs/ARCHITECTURE.md` for the system design.
