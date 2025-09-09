variable "kubeconfig" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "poc-local"
}

variable "enable_newrelic" {
  type    = bool
  default = false
}

variable "newrelic_license_b64" {
  type    = string
  default = ""
}
