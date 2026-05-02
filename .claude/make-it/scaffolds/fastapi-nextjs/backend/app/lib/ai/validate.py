"""Output validation utilities for AI responses."""

import json
import re
from typing import Any


_HTML_TAG_RE = re.compile(r"<[^>]+>")


def strip_html(text: str) -> str:
    """Remove HTML tags from text to prevent XSS in AI output."""
    return _HTML_TAG_RE.sub("", text)


def validate_json_schema(text: str, schema: dict[str, Any]) -> dict[str, Any]:
    """Validate that AI output parses as JSON and conforms to expected keys."""
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"AI output is not valid JSON: {exc}") from exc

    if not isinstance(data, dict):
        raise ValueError("AI output must be a JSON object")

    missing = set(schema.keys()) - set(data.keys())
    if missing:
        raise ValueError(f"AI output missing required keys: {sorted(missing)}")

    for key, expected_type in schema.items():
        if not isinstance(data[key], expected_type):
            raise ValueError(
                f"Key '{key}' expected type {expected_type.__name__}, "
                f"got {type(data[key]).__name__}"
            )

    return data


def sanitize_ai_output(text: str) -> str:
    """Clean AI output by stripping HTML and normalizing whitespace."""
    cleaned = strip_html(text)
    cleaned = cleaned.strip()
    return cleaned
