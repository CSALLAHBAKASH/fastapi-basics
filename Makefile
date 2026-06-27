# ==============================================================================
# Dynamic Project Configurations
# ==============================================================================
PROJECT_ID   := $(shell gcloud config get-value project 2>/dev/null)
PROJECT_NUM  := $(shell gcloud projects describe $(PROJECT_ID) --format="value(projectNumber)" 2>/dev/null)
REGION       := asia-south1
REPO_NAME    := my-fastapi-repo
APP_NAME     := fastapi-app

.PHONY: all help check-project init local-run pre-setup build-deploy clean

all: help

help:
	@echo "======================================================================="
	@echo "                   FastAPI Cloud Build Automation                      "
	@echo "======================================================================="
	@echo " 1. make init         - Install local Python dependencies"
	@echo " 2. make local-run   - Run FastAPI app locally (port 8000)"
	@echo " 3. make pre-setup   - One-time GCP configurations (API, Repo, IAM)"
	@echo " 4. make build-deploy- Trigger Cloud Build workflow pipeline"
	@echo " 5. make clean        - Purge local temporary development caches"
	@echo "======================================================================="
	@echo " Current GCP Project Detected: $(PROJECT_ID)"
	@echo "======================================================================="

check-project:
	@if [ -z "$(PROJECT_ID)" ] || [ "$(PROJECT_ID)" = "(unset)" ]; then \
		echo "ERROR: No active Google Cloud project detected."; \
		echo "Please configure it using: gcloud config set project YOUR_PROJECT_ID"; \
		exit 1; \
	fi

init:
	@echo "--> Installing application requirements..."
	pip install -r requirements.txt

local-run:
	@echo "--> Starting FastAPI server locally on port 8000..."
	python main.py

pre-setup: check-project
	@echo "--> Enabling required Google Cloud Service APIs..."
	gcloud services enable run.googleapis.com \
		artifactregistry.googleapis.com \
		cloudbuild.googleapis.com
	
	@echo "--> Provisioning Artifact Registry Docker Repository in $(REGION)..."
	gcloud artifacts repositories create $(REPO_NAME) \
		--repository-format=docker \
		--location=$(REGION) \
		--description="FastAPI Docker repository for Cloud Build" || echo "Repository might already exist..."
	
	@echo "--> Binding IAM Role (Cloud Run Admin) to Cloud Build..."
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(PROJECT_NUM)@cloudbuild.gserviceaccount.com" \
		--role="roles/run.admin"
	
	@echo "--> Binding IAM Role (Service Account User) to Cloud Build..."
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(PROJECT_NUM)@cloudbuild.gserviceaccount.com" \
		--role="roles/iam.serviceAccountUser"

	@echo "--> Binding IAM Role (Artifact Registry Writer) to Cloud Build..."
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(PROJECT_NUM)@cloudbuild.gserviceaccount.com" \
		--role="roles/artifactregistry.writer"
	@echo "--> Configuration complete."

build-deploy: check-project pre-setup
	@echo "--> Submitting local workspace source files to Cloud Build..."
	gcloud builds submit --config cloudbuild.yaml

# Completely tears down all cloud infrastructure created for this app
destroy-all: check-project
	@echo "⚠️ WARNING: This will permanently delete your Cloud Run service and Docker repository!"
	@echo "Proceeding in 3 seconds... Press Ctrl+C to abort." && sleep 3
	
	@echo "--> Deleting Cloud Run Service ($(APP_NAME))..."
	gcloud run services delete $(APP_NAME) --region=$(REGION) --quiet || echo "Service already deleted or not found."
	
	@echo "--> Deleting Artifact Registry Repository ($(REPO_NAME))..."
	gcloud artifacts repositories delete $(REPO_NAME) --location=$(REGION) --quiet || echo "Repository already deleted or not found."
	
	@echo "--> Clean up complete. All remote cloud resources have been removed."

clean:
	@echo "--> Purging temporary local environment cache structures..."
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
