terraform {
  required_version = "~> 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.82" # not tested on earlier versions
    }
  }
}
