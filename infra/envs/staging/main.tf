terraform {
  required_version = ">=1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
  }
}

provider "google" {
  project = "project-39eb557f-9be4-42ee-b0c"
  region  = "us-central1"
}