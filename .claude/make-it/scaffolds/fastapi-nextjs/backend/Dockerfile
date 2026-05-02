ARG DOCKER_HUB_PREFIX=
FROM ${DOCKER_HUB_PREFIX}python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends g++ curl && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=appuser:appgroup . .

USER appuser

ENV PYTHONPATH=/app

CMD ["bash", "entrypoint.sh"]
