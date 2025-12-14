resource "azurerm_resource_group" "rg_main" {
  name     = "rg-${var.team_name}-${var.environment}-${var.project_name}"
  location = var.location

  tags = local.tags
}
