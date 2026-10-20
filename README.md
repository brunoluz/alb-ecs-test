# PoC: API Gateway -> ALB -> ECS Fargate

Este projeto cria uma REST API do API Gateway integrada por VPC Link v2 a um ALB
interno. A API usa o estágio `prod`; seus outputs já incluem esse prefixo. O ALB
encaminha `GET /teste` para o serviço `alb-teste-fastapi` e
`GET /service2` para o serviço ECS `servico-2`; ambos rodam aplicações FastAPI
na porta `8081`. As respostas são texto plano: `testado` em `/teste` e
`segundo service` em `/service2`.

Cada integração privada aponta explicitamente ao caminho correspondente na
aplicação (`/teste` ou `/service2`), mantendo o roteamento existente no ALB.

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
- AWS CLI autenticado com permissões para criar API Gateway REST API, VPC Link,
  EC2 security groups, ALB, ECS, ECR, CloudWatch Logs e IAM
- Docker em execução na máquina onde o Terraform será executado
- Uma VPC default com sub-redes default em pelo menos duas zonas

## Criar a infraestrutura e publicar a aplicação

O `terraform apply` cria os repositórios ECR, obtém credenciais temporárias da
AWS, constrói as imagens da aplicação e as publica no ECR antes de criar as
task definitions do ECS. As credenciais são gravadas em uma configuração Docker
temporária e isolada, removida ao final, sem usar o Keychain do sistema. Execute
na raiz do projeto:

```sh
terraform init
terraform apply
```

Se usar outra região, configure-a no apply, por exemplo:
`terraform apply -var="region=us-east-1"`.

Para publicar uma tag diferente de `latest`, use
`terraform apply -var="image_tag=v1"`. Alterações no `Dockerfile`,
`requirements.txt`, `.dockerignore` ou nos arquivos de `app/` fazem o Terraform
reconstruir e publicar a primeira imagem. Alterações no `Dockerfile.app2`,
`requirements.txt`, `.dockerignore` ou nos arquivos de `app2/` fazem o mesmo
para a segunda imagem. A mudança do conteúdo de cada imagem também gera uma
nova revisão da task definition correspondente e um novo deployment ECS.

Quando o `terraform apply` terminar, consulte `test_url` com:

```sh
curl "$(terraform output -raw test_url)"
```

O corpo da resposta deve ser `testado` e o `Content-Type` deve indicar texto
plano. Para testar o segundo serviço:

```sh
curl "$(terraform output -raw service2_url)"
```

O corpo da resposta deve ser `segundo service`. Os endpoints podem levar alguns
minutos para ficar prontos enquanto o VPC Link é provisionado e as tasks passam
no health check do ALB.

## Custos e limpeza

Esta PoC cria recursos cobrados enquanto estiverem ativos, incluindo ALB,
VPC Link, quatro tasks Fargate e endereços IPv4 públicos. Verifique os preços
da região antes de aplicar. Para remover os recursos e as imagens do ECR:

```sh
terraform destroy
```
