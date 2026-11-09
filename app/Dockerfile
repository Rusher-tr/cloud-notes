# ---------- Application tier: Flask API served by Gunicorn ----------
# Stage 1: install dependencies into a virtualenv (build tools stay out of the final image)
FROM python:3.12-slim AS build
WORKDIR /build
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# Stage 2: small runtime image
FROM python:3.12-slim
ARG APP_VERSION=dev
ENV PATH="/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION} \
    GUNICORN_WORKERS=2 \
    GUNICORN_THREADS=4

# Run as an unprivileged user (least privilege inside the container)
RUN useradd --system --uid 10001 --no-create-home appuser
WORKDIR /srv
COPY --from=build /venv /venv
COPY app.py .

USER appuser
EXPOSE 5000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/api/health', timeout=2).status == 200 else 1)"

CMD gunicorn "app:create_app()" \
    --bind 0.0.0.0:5000 \
    --workers ${GUNICORN_WORKERS} --threads ${GUNICORN_THREADS} \
    --access-logfile - --error-logfile - \
    --forwarded-allow-ips="*"
