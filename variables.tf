variable "instance_name" {
  type        = string
  description = "Existing cloud sql database instance name"
}

variable "databases" {
  type        = list(string)
  description = "List of SQL databases to export/backup"
}

variable "bucket_name" {
  type        = string
  description = "Bucket, that would be created"
}

variable "retention" {
  type = object({
    daily  = number
    weekly = number
  })
  default = {
    daily  = 31
    weekly = 52 # approx 1 year
  }
  description = <<-EOT
  Set's number of backups to be stored in bucket per type
  During a week, 6 daily backups would be created and 1 weekly
  usage:
  ```hcl
  retention = {
    daily = 31
    weekly = 52
  }
  ```
  EOT
}
