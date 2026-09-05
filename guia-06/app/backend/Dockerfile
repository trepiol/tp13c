FROM python:3.13-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY --chown=appuser:appuser app.py entrypoint.sh ./
RUN chmod 0555 entrypoint.sh
USER appuser
EXPOSE 5000
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health',timeout=2)"
ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn","--bind=0.0.0.0:5000","--workers=2","--access-logfile=-","app:app"]

