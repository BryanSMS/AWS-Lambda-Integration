variable "aws_region" {
  description = "Region de AWS donde se despliega"
  type        = string
  default     = "us-east-2"
}
variable "aws_profile" {
  description = "Perfil de AWS CLI que usa Terraform"
  type        = string
  default     = "bryan"
}
variable "project_name" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "image-processor"
}
variable "environment" {
  description = "Entorno de despliegue: dev, qa o prod"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "alert_email" {
  description = "Correo que recibe la alerta cuando hay mensajes en la DLQ"
  type        = string
  default     = ""
}