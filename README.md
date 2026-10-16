# PoC: API Gateway -> ALB -> ECS Fargate

Este projeto cria uma HTTP API do API Gateway com `GET /teste`, integrada por
VPC Link a um ALB interno. O ALB encaminha as chamadas para duas tasks ECS
Fargate com uma aplicação FastAPI na porta `8081`. A resposta de `GET /teste`
é o texto plano `testado`.

## Rede utilizada

O Terraform encontra a VPC default na região configurada e seleciona as
sub-redes default de duas zonas de disponibilidade. Na conta consultada para
esta PoC, a região padrão é `sa-east-1`.

O ALB é interno. As tasks recebem IP público para poderem baixar a imagem do
ECR sem criar um NAT Gateway, mas o security group delas aceita conexões na
porta `8081` somente do ALB. O security group do ALB, por sua vez, aceita
conexões somente do VPC Link. Nenhum NAT Gateway é criado.

## Pré-requisitos

- Terraform `>= 1.5`
- AWS CLI autenticado com permissões para criar API Gateway, VPC Link, EC2
  security groups, ALB, ECS, ECR, CloudWatch Logs e IAM
- Docker em execução na máquina onde o Terraform será executado
- Uma VPC default com sub-redes default em pelo menos duas zonas

## Criar a infraestrutura e publicar a aplicação

O `terraform apply` cria o repositório ECR, autentica o Docker na AWS, constrói
a imagem da aplicação e a publica no ECR antes de criar a task definition do
ECS. Execute na raiz do projeto:

```sh
terraform init
terraform apply
```

Se usar outra região, configure-a no apply, por exemplo:
`terraform apply -var="region=us-east-1"`.

Para publicar uma tag diferente de `latest`, use
`terraform apply -var="image_tag=v1"`. Alterações no `Dockerfile`,
`requirements.txt`, `.dockerignore` ou nos arquivos de `app/` fazem o Terraform
reconstruir e publicar a imagem automaticamente. A mudança do conteúdo da
imagem também gera uma nova revisão da task definition e um novo deployment ECS.

Quando o `terraform apply` terminar, consulte `test_url` com:

```sh
curl "$(terraform output -raw test_url)"
```

O corpo da resposta deve ser `testado` e o `Content-Type` deve indicar texto
plano. O endpoint pode levar alguns minutos para ficar pronto enquanto o VPC
Link é provisionado e as tasks passam no health check do ALB.

## Custos e limpeza

Esta PoC cria recursos cobrados enquanto estiverem ativos, incluindo ALB,
VPC Link, duas tasks Fargate e endereços IPv4 públicos. Verifique os preços da
região antes de aplicar. Para remover os recursos e a imagem do ECR:

```sh
terraform destroy
```
