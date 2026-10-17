output "ecr_repository_url" {
  description = "URL do repositório ECR da aplicação."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_service2_url" {
  description = "URL do repositório ECR do servico-2."
  value       = aws_ecr_repository.app2.repository_url
}

output "api_endpoint" {
  description = "Endpoint base da API Gateway HTTP API."
  value       = aws_apigatewayv2_api.app.api_endpoint
}

output "test_url" {
  description = "URL da rota GET /teste."
  value       = "${aws_apigatewayv2_api.app.api_endpoint}/teste"
}

output "service2_url" {
  description = "URL da rota GET /service2."
  value       = "${aws_apigatewayv2_api.app.api_endpoint}/service2"
}

output "ecs_cluster_name" {
  description = "Nome do cluster ECS criado para a PoC."
  value       = aws_ecs_cluster.app.name
}
