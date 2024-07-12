# Periodic CloudSQL backup to bucket (dump)

A tiny setup for a periodic external dump-backup, without scripting or external dependencies
No code, just staticly defined cron job, access and policies.

## How it works

### Export

Scheduler (CRON) triggers [CloudSQL export](https://cloud.google.com/sql/docs/mysql/import-export/import-export-sql) with an [HTTP request](https://cloud.google.com/sql/docs/mysql/import-export/import-export-sql#rest-v1beta4).
This request is [authenticated by Scheduler](https://cloud.google.com/scheduler/docs/http-target-auth) as SA, thus has `roles/cloudsql.viewer` required for export feature.
We also assign `roles/storage.objectUser` on bucket for DB instance itself, so it can save file there.

### Versioning

Since, GCPs Scheduler, does not expose any variables that can be used
in the HTTP request, nor any meaningful scripting, we are limited to
static request body, thus the same file name across invocations.

This can be overcame by enabling bucket `versioning`,
so same file will keep up to 1000 of older backups as versions.
Then Mon-Sat backups exported with `daily_` prefix, and Sun with `weekly_` prefix.
With lifecycle rules that keep desired amount of each, using those prefixes.

## Usage

I would rather recommend to copy&paste module,
and hack it according to your needs.

```hcl
module "db_backup" {
  source = "github.com/ubombi/gcp_sqlexport"
  # source = "../myhacked_sqlexport"

  bucket_name   = "my_db_backups"
  instance_name = "my_db"
  databases     = ["postgres"]

  # optional, following is a default value
  retention     = {
    daily = 31      # ~1 Month
    weekly = 52     # ~1 Year
  }
}
```

### TODO

- [ ] Allow reuse of existing buckets, and multi-instance export into single bucket
- [ ] Allow external buckets, in separate accounts (for resiliency)
- [ ] Expose CRON/Scheduling and dedlines config.

### Known issues

For very old GCP accounts, it may be required to
add scheduler to `roles/cloudscheduler.serviceAgent` role manualy.
New accounts have this permissions by default.

```bash
gcloud projects add-iam-policy-binding [project name] \
   --member serviceAccount:service-[project number]@gcp-sa-cloudscheduler.iam.gserviceaccount.com \
   --role roles/cloudscheduler.serviceAgent
```
