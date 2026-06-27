# ==============================================================================
# Dynamic Project Configurations
# ==============================================================================
PROJECT_ID   := $(shell gcloud config get-value project 2>/dev/null)
PROJECT_NUM  := $(shell gcloud projects describe $(PROJECT_ID) --format="value(projectNumber)" 2>/dev/null)
REGION       := asia-south1
REPO_NAME    := my-fastapi-repo
APP_NAME     := fastapi-app

.PHONY: all help check-project init local-run pre-setup build-deploy setup-github-sa destroy-all clean

# Default target when you just run 'make'
all: help

help:
	@echo "======================================================================="
	@echo "                   FastAPI Cloud Build Automation                      "
	@echo "======================================================================="
	@echo " 1. make init         - Install local Python dependencies"
	@echo " 2. make local-run    - Run FastAPI app locally (port 8000)"
	@echo " 3. make pre-setup    - One-time GCP configurations (API, Repo, IAM)"
	@echo " 4. make build-deploy - Trigger Cloud Build workflow pipeline"
	@echo " 5. make setup-github-sa - Configure Keys for GitHub Actions Engine"
	@echo " 6. make destroy-all  - COMPLETELY DELETES app and repo from Google Cloud"
	@echo " 7. make clean        - Purge local temporary development caches"
	@echo "======================================================================="
	@echo " Current GCP Project Detected: $(PROJECT_ID)"
	@echo "======================================================================="

# Core blocker to intercept deployments if local active configuration is empty
check-project:
	@if [ -z "$(PROJECT_ID)" ] || [ "$(PROJECT_ID)" = "(unset)" ]; then \
		echo "ERROR: No active Google Cloud project detected."; \
		echo "Please configure it using: gcloud config set project YOUR_PROJECT_ID"; \
		exit 1; \
	fi

# Step 1: Initialize local Python environment
init:
	@echo "--> Installing application requirements..."
	pip install -r requirements.txt

# Step 2: Run application engine natively
local-run:
	@echo "--> Starting FastAPI server locally on port 8000..."
	python main.py

# Step 3: Run infrastructure creation & assign core orchestration security roles
pre-setup: check-project
	@echo "--> Enabling required Google Cloud Service APIs..."
	gcloud services enable run.googleapis.com \
		artifactregistry.googleapis.com \
		cloudbuild.googleapis.com
	
	@echo "--> Checking/Provisioning Artifact Registry Repository in $(REGION)..."
	@gcloud artifacts repositories describe $(REPO_NAME) --location=$(REGION) >/dev/null 2>&1 || \
		gcloud artifacts repositories create $(REPO_NAME) \
			--repository-format=docker \
			--location=$(REGION) \
			--description="FastAPI Docker repository for Cloud Build"
	
	@echo "--> Granting Cloud Build Service Account required orchestration roles..."
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(PROJECT_NUM)@cloudbuild.gserviceaccount.com" \
		--role="roles/run.admin" --quiet >/dev/null
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(PROJECT_NUM)@cloudbuild.gserviceaccount.com" \
		--role="roles/iam.serviceAccountUser" --quiet >/dev/null
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(PROJECT_NUM)@cloudbuild.gserviceaccount.com" \
		--role="roles/artifactregistry.writer" --quiet >/dev/null
	
	@echo "--> Granting Default Compute Account public IAM modification rights..."
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(PROJECT_NUM)-compute@developer.gserviceaccount.com" \
		--role="roles/resourcemanager.projectIamAdmin" --quiet >/dev/null
	@echo "--> Base infrastructure check finished safely."

# Step 4: Submit code to Google Cloud Build pipeline
build-deploy: check-project pre-setup
	@echo "--> Submitting local workspace source files to Cloud Build..."
	gcloud builds submit --config cloudbuild.yaml

# Step 5: Provision secure Service Accounts for GitHub runner connections
setup-github-sa: check-project pre-setup
	@echo "--> Creating GitHub Service Account and generating deployment key..."
	gcloud iam service-accounts create github-deployer --display-name="GitHub Actions Deployer" || true
	
	@echo "--> Assigning workflow triggers rights to GitHub Action identities..."
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:github-deployer@$(PROJECT_ID).iam.gserviceaccount.com" \
		--role="roles/cloudbuild.builds.editor" --quiet >/dev/null
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:github-deployer@$(PROJECT_ID).iam.gserviceaccount.com" \
		--role="roles/iam.serviceAccountUser" --quiet >/dev/null
	
	@echo "--> Generating credentials file..."
	gcloud iam service-accounts keys create gcp-key.json \
		--iam-account=github-deployer@$(PROJECT_ID).iam.gserviceaccount.com
	@echo "======================================================================="
	@echo " SUCCESS: Copy the string inside 'gcp-key.json' to GitHub Secrets!"
	@echo "======================================================================="

# Step 6: Complete cloud asset cleanup hook
destroy-all: check-project
	@echo "⚠️ WARNING: This will permanently delete your Cloud Run service and Docker repository!"
	@echo "Proceeding in 3 seconds... Press Ctrl+C to abort." && sleep 3
	@echo "--> Deleting Cloud Run Service ($(APP_NAME))..."
	gcloud run services delete $(APP_NAME) --region=$(REGION) --quiet || echo "Service not found."
	@echo "--> Deleting Artifact Registry Repository ($(REPO_NAME))..."
	gcloud artifacts repositories delete $(REPO_NAME) --location=$(REGION) --quiet || echo "Repository not found."
	@echo "--> Clean up complete. All remote cloud resources have been removed."

# Step 7: Clear out code tracking caches
clean:
	@echo "--> Purging temporary local environment cache structures..."
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
