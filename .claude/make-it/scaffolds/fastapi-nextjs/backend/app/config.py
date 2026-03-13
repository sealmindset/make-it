from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # OIDC
    OIDC_ISSUER_URL: str = "http://mock-oidc:10090"
    OIDC_CLIENT_ID: str = "mock-oidc-client"
    OIDC_CLIENT_SECRET: str = "mock-oidc-secret"
    # JWT
    JWT_SECRET: str = "change-me-in-production"
    # Database
    DATABASE_URL: str = "postgresql+asyncpg://[APP_SLUG]:[APP_SLUG]@db:5432/[APP_SLUG]"
    # URLs
    FRONTEND_URL: str = "http://localhost:[FRONTEND_PORT]"
    BACKEND_URL: str = "http://localhost:[BACKEND_PORT]"
    # [ADDITIONAL_SERVICE_URLS] -- e.g., JIRA_BASE_URL, TEMPO_BASE_URL

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
