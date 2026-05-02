import re

_INJECTION_PATTERNS = [
    r"ignore\s+(all\s+)?previous\s+instructions",
    r"disregard\s+(above|your)\s+instructions",
    r"you\s+are\s+now",
    r"system:",
    r"###\s*(System|Human|Assistant):",
    r"<\|(system|user|assistant)\|>",
]

_COMPILED = [re.compile(p, re.IGNORECASE) for p in _INJECTION_PATTERNS]


def sanitize_prompt_input(text: str) -> str:
    sanitized = text
    for pattern in _COMPILED:
        sanitized = pattern.sub("[FILTERED]", sanitized)
    return f"<user_input>{sanitized}</user_input>"
