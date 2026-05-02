from app.config import settings


def get_model(tier: str) -> str:
    mapping = {
        "heavy": settings.AI_MODEL_HEAVY,
        "standard": settings.AI_MODEL_STANDARD,
        "light": settings.AI_MODEL_LIGHT,
    }
    return mapping.get(tier, settings.AI_MODEL_STANDARD)
