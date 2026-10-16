variable "region" {
  description = "Região AWS onde a infraestrutura será criada."
  type        = string
  default     = "sa-east-1"
}

variable "image_tag" {
  description = "Tag da imagem da aplicação que será publicada no ECR."
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "A tag da imagem deve seguir o formato de tags Docker (até 128 caracteres)."
  }
}
