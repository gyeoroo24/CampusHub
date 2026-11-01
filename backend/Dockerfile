# Always-on container for the EC2 baseline in the PRD's Lambda-vs-EC2 evaluation (same code).
# Build:  docker build -t campushub-api .
# Run:    docker run -p 8000:8000 --env-file .env campushub-api
FROM python:3.12-slim

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt "uvicorn[standard]==0.34.0"

# The category-suggestion model (34 MB; app/categories_suggest.py), checksum-checked.
COPY scripts/fetch_match_models.py /tmp/
RUN python /tmp/fetch_match_models.py --suggest-only /srv/models && rm /tmp/fetch_match_models.py

COPY app ./app

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
