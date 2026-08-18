terraform {

  backend "gcs" {
    bucket = "project-39eb557f-9be4-42ee-b0c-tfstate-dev"
    prefix = "terraform/state/staging"
  }
}
