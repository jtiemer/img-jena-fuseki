terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Scaffold only: replace with actual resources for container app/AKS, storage, and identity.
resource "azurerm_resource_group" "database" {
  name     = var.resource_group_name
  location = var.location
}
