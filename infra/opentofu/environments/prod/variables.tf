variable "team_name" {
  description = "The name of the team responsible for the resources."
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g., dev, prod)."
  type        = string
}

variable "project_name" {
  description = "The name of the project."
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed."
  type        = string
}