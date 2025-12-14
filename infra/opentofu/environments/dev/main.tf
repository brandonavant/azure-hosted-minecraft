module "minecraft_vm" {
  source        = "../../modules/minecraft_vm"
  team_name     = var.team_name
  environment   = var.environment
  project_name  = var.project_name
  location      = var.location
}
