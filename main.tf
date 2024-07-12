data "google_sql_database_instance" "instance" {
  name = var.instance_name
}

data "google_project" "project" {}


resource "google_storage_bucket" "backups" {
  # TODO: expose variables
  name                        = var.bucket_name
  force_destroy               = false
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  storage_class               = "ARCHIVE"
  location                    = "EU"
  custom_placement_config {   
    data_locations = [
      upper(data.google_sql_database_instance.instance.region), # same as DB so initial export is faster
      "EUROPE-CENTRAL2",                                        # replicate to Poland, 100m above sea level. Just in case
    ]
  }

  # bucket is encrypted by default, thus no config is required,
  # unless we need custome encryption keys to be used.

  # All periodic backups are saved as different versions 
  # of the same file, due to CRON limitations
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = var.retention.weekly
      matches_prefix     = ["weekly_"]
    }
    action {
      type = "Delete"
    }
  }
  lifecycle_rule {
    condition {
      num_newer_versions = var.retention.daily
      matches_prefix     = ["daily_"]
    }
    action {
      type = "Delete"
    }
  }
}


resource "google_storage_bucket_iam_member" "allow_write_db_instance" {
  bucket = google_storage_bucket.backups.name
  member = "serviceAccount:${data.google_sql_database_instance.instance.service_account_email_address}"
  role   = "roles/storage.objectUser"
}

resource "google_service_account" "export" {
  account_id   = "sqlexport-backups-${var.instance_name}"
  display_name = "SQL Export Backups"
  description  = "Used to trigger sql export by cron"
}

# google_service_account_iam_member didn't work, since this permission shall be set on a project level.
resource "google_project_iam_member" "cron_sqlesport" {
  project = data.google_project.project.project_id
  role    = "roles/cloudsql.viewer" # RO; minimum required permission is "cloudsql.instances.export"
  member  = "serviceAccount:${google_service_account.export.email}"
}

resource "google_cloud_scheduler_job" "daily" {
  name             = "cloudsql-export-${var.instance_name}-daily"
  region           = data.google_sql_database_instance.instance.region # can be hardcoded.
  description      = "Backups ${var.instance_name} to ${var.bucket_name}"
  schedule         = "0 9 * * 1-6" # Mon-Sat at 9 AM
  time_zone        = "Europe/Amsterdam"
  attempt_deadline = "1800s" # 30m

  http_target {
    http_method = "POST"
    # uri = "/sql/v1beta4/projects/{project}/instances/{instance}/export"
    uri = "https://sqladmin.googleapis.com/sql/v1beta4/projects/${data.google_sql_database_instance.instance.project}/instances/${data.google_sql_database_instance.instance.id}/export"
    body = base64encode(<<-EOT
      {
       "exportContext":
         {
            "fileType": "SQL",
            "uri": "gs://${var.bucket_name}/daily_${var.instance_name}.sql.gz",
            "databases": ${jsonencode(var.databases)},
            "offload": false
          }
      }
      EOT
    )
    oauth_token { # oauth shall be used for *googleapis.com
      service_account_email = google_service_account.export.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform" # https://www.googleapis.com/auth/sqlservice.admin
    }
  }
}

resource "google_cloud_scheduler_job" "weekly" {
  name             = "cloudsql-export-${var.instance_name}-weekly"
  region           = data.google_sql_database_instance.instance.region # can be hardcoded.
  description      = "Backups ${var.instance_name} to ${var.bucket_name}"
  schedule         = "0 9 * * 0" # Sun at 9 AM
  time_zone        = "Europe/Amsterdam"
  attempt_deadline = "1800s" # 30m

  http_target {
    http_method = "POST"
    uri         = "https://sqladmin.googleapis.com/sql/v1beta4/projects/${data.google_sql_database_instance.instance.project}/instances/${data.google_sql_database_instance.instance.id}/export"
    body = base64encode(<<-EOT
      {
       "exportContext":
         {
            "fileType": "SQL",
            "uri": "gs://${var.bucket_name}/weekly_${var.instance_name}.sql.gz",
            "databases": ${jsonencode(var.databases)},
            "offload": false
          }
      }
      EOT
    )
    oauth_token { # oauth shall be used for *googleapis.com
      service_account_email = google_service_account.export.email
    }
  }
}
