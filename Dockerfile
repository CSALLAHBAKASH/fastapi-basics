FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Match Cloud Run's default routing port
EXPOSE 8080

# 'fastapi run' dynamically reads the $PORT env variable injected by Cloud Run
CMD ["fastapi", "run", "main.py", "--host", "0.0.0.0", "--port", "8080"]


# gcloud auth login
# gcloud config set project gen-lang-client-0854258586
# gcloud config set run/region asia-south1
# gcloud run deploy SERVICE_NAME --source . --port 8080 --allow-unauthenticated --region=asia-south1

# gcloud run services delete fastapp --region=asia-south1
# gcloud artifacts repositories delete cloud-run-source-deploy --region=asia-south1
# gcloud run services describe fastapp --region=asia-south1
