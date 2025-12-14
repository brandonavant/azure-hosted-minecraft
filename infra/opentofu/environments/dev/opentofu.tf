terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
  }

  backend "azurerm" { } # Pass in via backend.dev.hcl locally; -backend-config in GitHub Workflow
}
