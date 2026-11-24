ARG DOCKER_HUB_PREFIX=
FROM ${DOCKER_HUB_PREFIX}python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# --no-proxy-headers: the peer address is the real one, never an X-Forwarded-For/Forwarded header
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "10090", "--no-proxy-headers"]
