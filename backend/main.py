import base64
import json
import logging
import os
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("foodscore")

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, UploadFile
from openai import OpenAI
from pydantic import BaseModel

load_dotenv()

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

_api_key = os.getenv("OPENAI_API_KEY")
if not _api_key or _api_key.startswith("your-"):
    raise RuntimeError(
        "OPENAI_API_KEY is missing or still set to a placeholder. "
        "Add your real key to backend/.env"
    )

client = OpenAI(api_key=_api_key)


# ---------------------------------------------------------------------------
# Step 1: Extract nutrition data from the photo (vision call)
# ---------------------------------------------------------------------------

EXTRACTION_PROMPT = """You are a nutrition label reader. Analyze this image of a nutrition label / food package.

Return ONLY valid JSON with these exact keys:
{
  "calories": <number>,
  "servingSizeGrams": <number or null>,
  "proteinGrams": <number>,
  "fiberGrams": <number>,
  "addedSugarGrams": <number>,
  "totalSugarGrams": <number or null>,
  "totalFatGrams": <number or null>,
  "saturatedFatGrams": <number or null>,
  "ingredientList": [<list of individual ingredient strings>],
  "readable": <true if you can read a nutrition label, false otherwise>,
  "confidence": <"high", "medium", or "low">
}

Rules:
- Use per-serving values.
- If a field is not visible, use null (except readable and confidence).
- If the image is not a nutrition label or is too blurry to read, set readable to false.
- Do NOT compute any scores. Only extract what you see.
- Return raw JSON only, no markdown fences."""


async def extract_nutrition(image_bytes: bytes) -> dict:
    b64 = base64.b64encode(image_bytes).decode()
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": EXTRACTION_PROMPT},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                ],
            }
        ],
        max_tokens=1000,
    )
    raw = response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(raw)


# ---------------------------------------------------------------------------
# Step 2: Score the extracted nutrition data (text call, no image)
# ---------------------------------------------------------------------------

# How the model should think about each purpose
PURPOSE_GUIDANCE = {
    "snack": "Evaluate as a snack: light, moderate satiety and balance. Should tide someone over without being too heavy.",
    "meal": "Evaluate as a meal: expect more completeness and satiety. Should provide substantial nutrition.",
    "post_workout": "Evaluate as post-workout nutrition: prioritize protein and recovery usefulness. Processing is less important if it delivers good protein.",
    "treat": "Evaluate as a treat: allow more flexibility. Do not over-penalize indulgence — treats are part of a balanced life.",
    "convenience": "Evaluate as a convenience food: consider practicality and ease, not just nutritional perfection. Being good enough and accessible matters.",
    "ingredient": "Evaluate as an ingredient in a larger meal (e.g. bread, sauce, cheese, condiment). Do not penalize heavily for lack of protein or fiber — those come from the rest of the meal. Focus on added sugar, sodium, processing level, and calorie density. Consider whether this would contribute positively or negatively when combined with other foods. Think in terms of: is this a reasonable building block?",
}

SCORING_PROMPT = """You are evaluating a food product based on its nutrition label and ingredients.

Your goal is to answer:
"Is this a reasonable choice for this person to eat right now, for this purpose?"

This is not about perfection or optimization. It is about practical, everyday decisions.

Here is the extracted nutrition data:
{nutrition_json}

The intended purpose of eating this food right now is: {purpose}
{purpose_guidance}

Evaluate whether this food makes sense for that purpose.

Instructions:
1. Weigh tradeoffs rather than applying rigid rules.
2. Consider:
   - protein and fiber (satiety)
   - added sugar (especially without protein/fiber)
   - ingredient quality and level of processing
   - calorie density (how easy it is to overeat)
3. Do not treat any single factor as decisive.
4. Avoid extreme scores unless clearly justified.
5. Most foods should fall between 5 and 8, unless clearly very good or very poor.
6. Consider how this food is typically used in real life.
   - Do not penalize foods too harshly for processing if they serve a practical purpose.
   - Evaluate whether the food makes sense for its intended use case, not just in isolation.
7. Avoid over-penalizing foods that are "good enough" for their purpose.

Tone:
- practical, not judgmental
- acknowledge tradeoffs ("good protein, but fairly processed")
- avoid sounding like a diet rulebook
- write the explanation points in a balanced, conversational tone

Explanation guidance:
- "whatHelps" should sound like reasons this could be a good choice
- "whatHurts" should sound like considerations or tradeoffs, not warnings or criticism
- avoid harsh or alarmist phrasing
- frame negatives as "things to keep in mind" rather than "problems"
- aim for wording that feels like practical advice from a knowledgeable but non-judgmental friend

Return JSON:

{
  "score": <number 1-10>,
  "whatHelps": [<2-3 concise points>],
  "whatHurts": [<2-3 concise points>],
  "interpretation": "<short sentence describing how to think about this food for this purpose>"
}

Interpretation guidance:
- 9-10: excellent everyday choice
- 7-8: strong option with minor tradeoffs
- 5-6: fine in context, not ideal
- 3-4: occasional food
- 1-2: not a great choice most of the time

Return raw JSON only, no markdown fences."""


async def score_nutrition(nutrition: dict, purpose: str = "snack") -> dict:
    nutrition_text = json.dumps(nutrition, indent=2)
    guidance = PURPOSE_GUIDANCE.get(purpose, PURPOSE_GUIDANCE["snack"])
    prompt = (
        SCORING_PROMPT
        .replace("{nutrition_json}", nutrition_text)
        .replace("{purpose}", purpose)
        .replace("{purpose_guidance}", guidance)
    )

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=500,
    )
    raw = response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(raw)


# ---------------------------------------------------------------------------
# API endpoints
# ---------------------------------------------------------------------------

@app.post("/extract")
async def extract(image: UploadFile = File(...)):
    """Extract nutrition data from the image only. No scoring."""
    image_bytes = await image.read()
    return await extract_nutrition(image_bytes)


@app.post("/analyze")
async def analyze(
    image: UploadFile = File(...),
    purpose: str = Form("snack"),
):
    image_bytes = await image.read()

    # Step 1: Extract nutrition data from the image
    nutrition = await extract_nutrition(image_bytes)

    # Step 2: If the label isn't readable, return a fallback
    if not nutrition.get("readable", False):
        return {
            "score": None,
            "whatHelps": [],
            "whatHurts": [],
            "interpretation": "I couldn't clearly read a nutrition label in this image. Try a closer, clearer photo of the nutrition facts panel.",
            "extractedNutrition": nutrition,
            "confidence": nutrition.get("confidence", "low"),
        }

    # Step 3: Score the extracted data for the given purpose
    result = await score_nutrition(nutrition, purpose)

    return {
        "score": int(result["score"]) if result.get("score") is not None else None,
        "whatHelps": result.get("whatHelps", []),
        "whatHurts": result.get("whatHurts", []),
        "interpretation": result.get("interpretation", ""),
        "extractedNutrition": nutrition,
        "confidence": nutrition.get("confidence", "medium"),
    }


class ScoreRequest(BaseModel):
    extractedNutrition: dict
    purpose: str = "snack"


@app.post("/score")
async def score(request: ScoreRequest):
    """Re-score previously extracted nutrition data with a different purpose.
    This avoids re-uploading and re-extracting the image."""
    result = await score_nutrition(request.extractedNutrition, request.purpose)

    return {
        "score": int(result["score"]) if result.get("score") is not None else None,
        "whatHelps": result.get("whatHelps", []),
        "whatHurts": result.get("whatHurts", []),
        "interpretation": result.get("interpretation", ""),
        "extractedNutrition": request.extractedNutrition,
        "confidence": request.extractedNutrition.get("confidence", "medium"),
    }


# ---------------------------------------------------------------------------
# Feedback
# ---------------------------------------------------------------------------

FEEDBACK_FILE = Path(__file__).parent / "feedback.json"
_feedback_lock = threading.Lock()


def _load_feedback() -> list[dict]:
    if not FEEDBACK_FILE.exists():
        return []
    try:
        return json.loads(FEEDBACK_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return []


def _save_feedback(entries: list[dict]) -> None:
    FEEDBACK_FILE.write_text(json.dumps(entries, indent=2))


class FeedbackRequest(BaseModel):
    feedback: str                           # "yes" or "not_really"
    purpose: str
    score: Optional[int] = None
    interpretation: str = ""
    unreadable: bool = False
    resultId: Optional[str] = None          # historyEntryID from the app


@app.post("/feedback")
async def post_feedback(request: FeedbackRequest):
    """Record a user's feedback on a score result."""
    entry = {
        "id": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "feedback": request.feedback,
        "purpose": request.purpose,
        "score": request.score,
        "interpretation": request.interpretation,
        "unreadable": request.unreadable,
        "resultId": request.resultId,
    }
    logger.info(
        "FEEDBACK RECEIVED: %s | score=%s | purpose=%s | resultId=%s",
        request.feedback,
        request.score,
        request.purpose,
        request.resultId,
    )
    with _feedback_lock:
        entries = _load_feedback()
        entries.append(entry)
        _save_feedback(entries)
    logger.info("FEEDBACK SAVED: total entries = %d", len(entries))
    return {"status": "ok"}


@app.get("/feedback")
async def get_feedback():
    """Return all stored feedback (for review)."""
    return _load_feedback()


@app.get("/feedback-debug")
async def feedback_debug():
    """Temporary: return the 10 most recent feedback items for debugging."""
    entries = _load_feedback()
    recent = entries[-10:] if len(entries) > 10 else entries
    return {
        "totalCount": len(entries),
        "showing": len(recent),
        "feedbackFilePath": str(FEEDBACK_FILE),
        "entries": list(reversed(recent)),  # newest first
    }
