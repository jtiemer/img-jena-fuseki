variable "resource_group_name" {
  description = "Azure resource group for database infrastructure"
  type        = string
  default     = "rg-vis-vts-db-dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}
