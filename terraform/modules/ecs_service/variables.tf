variable "name" {
  type = string
}
variable "cluster_id" {
  type = string
}
variable "image" {
  type = string
}
variable "subnet_ids" {
  type = list(string)
}
variable "security_group_ids" {
  type = list(string)
}
variable "role_arn" {
  type = string
}
variable "region" {
  type = string
}
variable "log_retention_days" {
  type = number
}
variable "environment" {
  type    = map(string)
  default = {}
}
variable "target_group_arn" {
  type    = string
  default = null
}
