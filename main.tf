data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, 2)
  subnet_ids   = [for az in local.selected_azs : one(data.aws_subnets.default[az].ids)]
  app_image_source_files = concat(
    [".dockerignore", "Dockerfile", "requirements.txt"],
    [for file in sort(fileset("${path.module}/app", "**")) : "app/${file}"]
  )
  app_image_source_hash = sha256(join("", [
    for file in local.app_image_source_files : "${file}:${filesha256("${path.module}/${file}")}"
  ]))
}

data "aws_subnets" "default" {
  for_each = toset(local.selected_azs)

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = [each.key]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "alb-teste-fastapi"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "terraform_data" "app_image" {
  triggers_replace = {
    image_tag      = var.image_tag
    repository_url = aws_ecr_repository.app.repository_url
    source_hash    = local.app_image_source_hash
  }

  input = local.app_image_source_hash

  provisioner "local-exec" {
    working_dir = path.module
    command     = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.app.repository_url)[0]} && docker build --platform linux/amd64 --file Dockerfile --tag ${aws_ecr_repository.app.repository_url}:${var.image_tag} . && docker push ${aws_ecr_repository.app.repository_url}:${var.image_tag}"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/alb-teste-fastapi"
  retention_in_days = 7
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "alb-teste-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "vpc_link" {
  name        = "alb-teste-vpc-link"
  description = "Saida do API Gateway VPC Link para o ALB."
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Saida necessaria para a integracao privada"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name        = "alb-teste-alb"
  description = "Recebe trafego somente do API Gateway VPC Link."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "API Gateway VPC Link"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
  }

  egress {
    description = "Aplicacao FastAPI nas tasks na VPC"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

resource "aws_security_group" "tasks" {
  name        = "alb-teste-ecs-tasks"
  description = "Recebe trafego somente do ALB."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Trafego do ALB"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Saida para baixar a imagem e enviar logs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app" {
  name               = "alb-teste-fastapi"
  internal           = true
  load_balancer_type = "application"
  subnets            = local.subnet_ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "app" {
  name        = "alb-teste-fastapi"
  port        = 8081
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 8081
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_cluster" "app" {
  name = "alb-teste-fastapi"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "alb-teste-fastapi"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "fastapi"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true

      dockerLabels = {
        "app.image.source-hash" = terraform_data.app_image.output
      }

      portMappings = [
        {
          containerPort = 8081
          hostPort      = 8081
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "fastapi"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "alb-teste-fastapi"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "fastapi"
    container_port   = 8081
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  health_check_grace_period_seconds = 60

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution,
    aws_lb_listener.app
  ]
}

resource "aws_apigatewayv2_vpc_link" "app" {
  name               = "alb-teste-vpc-link"
  subnet_ids         = local.subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]
}

resource "aws_apigatewayv2_api" "app" {
  name          = "alb-teste-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "app" {
  api_id                 = aws_apigatewayv2_api.app.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.app.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.app.id
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "test" {
  api_id    = aws_apigatewayv2_api.app.id
  route_key = "GET /teste"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.app.id
  name        = "$default"
  auto_deploy = true
}
