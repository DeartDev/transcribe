# Imagen oficial de Python, fijada a familia 3.12 y Debian Bookworm slim.
# No se usa python:latest. No se expone ningún puerto.
FROM python:3.12-slim-bookworm

ARG APP_UID=10001
ARG APP_GID=10001

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    HOME=/tmp/home \
    XDG_CACHE_HOME=/tmp/cache \
    HF_HOME=/models/.cache/huggingface \
    HF_HUB_DISABLE_TELEMETRY=1 \
    HF_HUB_DISABLE_PROGRESS_BARS=1

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates libgomp1; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd --gid "${APP_GID}" app; \
    useradd --uid "${APP_UID}" --gid "${APP_GID}" --no-create-home --shell /usr/sbin/nologin app; \
    mkdir -p /app /input /output /models /tmp/home /tmp/cache; \
    chown -R app:app /app /input /output /models /tmp/home /tmp/cache

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN python -m pip install --no-cache-dir --requirement /app/requirements.txt

COPY src/ /app/src/
RUN chmod -R a+rX /app

USER app:app

ENTRYPOINT ["python"]
CMD ["/app/src/transcribir.py", "--help"]
