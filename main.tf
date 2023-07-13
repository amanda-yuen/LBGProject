terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.72.1"
    }
  }
}

provider "google" {
  project     = "projectlbg"
  region      = "europe-west2"
  zone        = "europe-west2-a"
}

resource "google_compute_network" "vpc_network" {
  name                    = "terraform-network"
  auto_create_subnetworks = false
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-small"
  zone         = "europe-west2-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }
}

resource "google_notebooks_instance" "vertexai_instance" {
  name         = "vertexai-notebook"
  machine_type = "e2-small"
  location     = "europe-west2-a"

  vm_image {
    project      = "deeplearning-platform-release"
    image_family = "tf-latest-cpu"
  }
}

resource "google_storage_bucket" "private_bucket" {
  name     = "lbg-proj-retentionpolicy-bucket"
  location = "europe-west2"

  public_access_prevention    = "enforced"
  force_destroy               = true
  uniform_bucket_level_access = true
  retention_policy {
    retention_period = 10
  }
}

resource "google_storage_bucket_object" "movies_csv" {
  name         = "movies-data.csv"
  bucket       = "lbg-proj-retentionpolicy-bucket"
  source       = "movies.csv"
  content_type = "CSV"

  depends_on = [google_storage_bucket.private_bucket]
}

resource "google_bigquery_dataset" "dataset" {
  dataset_id  = "bigquery_dataset"
  location    = "europe-west2"
  description = "A BigQuery Dataset"

  delete_contents_on_destroy = true
}
resource "google_bigquery_table" "moviesheet1" {
  dataset_id          = google_bigquery_dataset.dataset.dataset_id
  table_id            = "moviesheet1"
  description         = "movie without csv, with partition and clustering"
  deletion_protection = false
  clustering          = ["genres"]

  schema = file("movies_schema.json")

  time_partitioning {
    field                    = "production_date"
    require_partition_filter = true
    type                     = "DAY"
  }
}

resource "google_bigquery_table" "moviesheet2" {
  dataset_id          = google_bigquery_dataset.dataset.dataset_id
  table_id            = "moviesheet2"
  description         = "movie with external csv"
  deletion_protection = false

  schema = file("movies_schema.json")

  external_data_configuration {
    autodetect    = true
    source_format = "CSV"
    source_uris   = ["${google_storage_bucket.private_bucket.url}/movies-data"]

    csv_options {
      quote             = "\""
      skip_leading_rows = 1
      field_delimiter   = ","
    }

    schema = file("movies_schema.json")
  }
}
