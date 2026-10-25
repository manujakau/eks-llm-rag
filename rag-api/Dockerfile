FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# unprivileged user, so listen above 1024
USER 65534:65534
EXPOSE 8080

# one worker per pod: prometheus metrics are per process; scale with replicas instead
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
