variable "region" {
  description = "Région AWS (le Learner Lab n'autorise que us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "noncurrent_version_retention_days" {
  description = "Durée de conservation des anciennes versions de l'état."
  type        = number
  default     = 90
}
