variable "noncurrent_version_retention_days" {
  description = "Days to keep overwritten/deleted object versions before pruning"
  type        = number
  default     = 30
}
