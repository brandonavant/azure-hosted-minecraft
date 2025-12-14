locals {
  tags = {
    created_by  = "opentofu"
    project     = var.project_name
    environment = var.environment
    team_name   = var.team_name
  }
}
