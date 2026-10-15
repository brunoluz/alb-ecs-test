variable "region" {
  description = "Região AWS onde a infraestrutura será criada."
  type        = string
  default     = "sa-east-1"
}

variable "image_tag" {
  description = "Tag da imagem da aplicação publicada no ECR."
  type        = string
  default     = "latest"
}
