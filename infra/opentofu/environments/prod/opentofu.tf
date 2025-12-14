terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
  }

  # TODO bavant: DITTO
  backend "azurerm" { } # Pass in via backend.prod.hcl
}
