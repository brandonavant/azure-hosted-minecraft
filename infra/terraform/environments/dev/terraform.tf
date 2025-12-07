terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
  }

  backend "azurerm" { } # Pass in by CI/CD pipeline via -backend-config
}
