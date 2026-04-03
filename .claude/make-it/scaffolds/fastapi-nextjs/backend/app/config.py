from pydantic_settings import BaseSettings


_WEAK_SECRETS = {"change-me-in-production", "secret", "changeme", ""}


class Settings(BaseSettings):
    # OIDC
    OIDC_ISSUER_URL: str = "http://mock-oidc:10090"
    OIDC_EXTERNAL_URL: str = "http://localhost:[MOCK_OIDC_PORT]"
    OIDC_CLIENT_ID: str = "mock-oidc-client"
    OIDC_CLIENT_SECRET: str = "mock-oidc-secret"
    # JWT
    JWT_SECRET: str = "change-me-in-production"
    # Database
    DATABASE_URL: str = "postgresql+asyncpg://[APP_SLUG]:[APP_SLUG]@db:5432/[APP_SLUG]"
    # URLs
    FRONTEND_URL: str = "http://localhost:[FRONTEND_PORT]"
    BACKEND_URL: str = "http://localhost:[BACKEND_PORT]"
    # Security
    ENFORCE_SECRETS: bool = False
    # Activity Log
    LOG_BUFFER_SIZE: int = 10000
    # [ADDITIONAL_SERVICE_URLS] -- e.g., JIRA_BASE_URL, TEMPO_BASE_URL

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()


def enforce_secrets() -> None:
    """Validate that secrets are production-strength.

    Called at app startup when ENFORCE_SECRETS=True.
    Raises RuntimeError for weak or missing secrets so the app fails
    fast instead of running with insecure defaults.
    """
    if not settings.ENFORCE_SECRETS:
        return

    errors: list[str] = []
    if settings.JWT_SECRET in _WEAK_SECRETS or len(settings.JWT_SECRET) < 32:
        errors.append(
            "JWT_SECRET must be at least 32 characters and not a default value. "
            "Generate one with: openssl rand -hex 32"
        )
    if settings.OIDC_CLIENT_SECRET in ("mock-oidc-secret", ""):
        errors.append("OIDC_CLIENT_SECRET is still set to the mock default.")

    if errors:
        raise RuntimeError(
            "ENFORCE_SECRETS is enabled but secrets are not production-ready:\n"
            + "\n".join(f"  - {e}" for e in errors)
        )
