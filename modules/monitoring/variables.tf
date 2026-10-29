variable "project_name" { type = string }
variable "asg_name" { type = string }
variable "function_name" { type = string }
variable "worker_log_group" { type = string }
variable "application_log_group" { type = string }
variable "existing_audit_trail_name" {
  type    = string
  default = null
}
variable "existing_budget_name" {
  type    = string
  default = null
}
variable "budget_alert_email" {
  type      = string
  default   = null
  sensitive = true
}
