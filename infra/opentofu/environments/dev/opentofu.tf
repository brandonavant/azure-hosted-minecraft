terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
  }
  # TODO bavant: Clarify between local and CI/CD pipeline
  backend "azurerm" { } # Pass in via backend.dev.hcl
}
