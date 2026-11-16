# Образ вебзастосунку «Електронна бібліотека» (і консольного застосунку).
# Містить Python із залежностями та клієнт PostgreSQL 17 (pg_dump/psql для резервних копій).
FROM docker.io/library/python:3.12-alpine

RUN apk add --no-cache postgresql17-client

WORKDIR /app
COPY web_app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY web_app/ web_app/
COPY console_app/ console_app/

WORKDIR /app/web_app
ENV HOST=0.0.0.0 \
    PYTHONUNBUFFERED=1
EXPOSE 5000
CMD ["python", "app.py"]
