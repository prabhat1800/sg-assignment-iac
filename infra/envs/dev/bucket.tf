/*resource "google_storage_bucket" "tfstate" {
  name                        = "${local.project_id}-tfstate-${local.environment}"
  location                    = local.region
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  labels = {
    environment = local.environment
  }

  lifecycle {
    prevent_destroy = true
  }

}
*/