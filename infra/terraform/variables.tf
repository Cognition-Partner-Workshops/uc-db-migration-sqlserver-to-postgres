variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  type    = string
  default = "pc-insurance"
}

variable "engine_version" {
  description = "Aurora PostgreSQL 18 minor version"
  type        = string
  default     = "18.6"
}

variable "instance_class" {
  type    = string
  default = "db.r7g.large"
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}
