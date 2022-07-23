#  main.tf
#  Creation d'une lambda pour piloter l'ALB
#
###########################################################################

###########################################################################
# Random_id for stack
###########################################################################
resource "random_id" "i" {
  byte_length = 8
}

###########################################################################
# Création du role de la lambda
###########################################################################
resource "aws_iam_role" "iam_for_lambda" {
  name = "lambda-${var.stackname}-${random_id.i.id}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lamdba" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "allow_ecs_management_policy" {
  name = "allow_ecs_management_policy-${var.stackname}-${random_id.i.id}"
  role = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecs:List*",
          "ecs:Describe*",
          "ecs:UpdateService",
          "elasticloadbalancing:SetRulePriorities"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

###########################################################################
# Création du zip de la lambda
###########################################################################
data "archive_file" "src" {
  type        = "zip"
  source_file = "${path.module}/src/index.py"
  output_path = "${path.module}/scaleto0lambda_function_payload.zip"
}

###########################################################################
# Création de la lambda
###########################################################################
resource "aws_lambda_function" "scaleto0_lambda" {
  filename      = "${path.module}/scaleto0lambda_function_payload.zip"
  function_name = "scaleto0lambda_${var.stackname}-${random_id.i.id}"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.handler"
  timeout       = 300

#  source_code_hash = filebase64sha256("${path.module}/scaleto0lambda_function_payload.zip")

  runtime = "python3.9"

  environment {
    variables = {
      RULE_ARN = "${var.rule_arn}"
      RULE_PRIORITY = "${var.rule_priority}"
      ECS_CLUSTER_NAME = "${var.ecs_cluster_name}"
      ECS_SERVICE_NAME = "${var.ecs_service_name}"
    }
  }
  depends_on = [
    data.archive_file.src
  ]
}

###########################################################################
# Création du target group pour la lambda
###########################################################################
resource "aws_lambda_permission" "allow_alb" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaleto0_lambda.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaleto0_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.monitoring.arn
}


###########################################################################
# Création du target group pour la lambda
###########################################################################
resource "aws_lb_target_group" "lambda" {
  name        = "tf-${random_id.i.id}"
  target_type = "lambda"
  health_check { 
    enabled = false
    interval = 300
    timeout = 30
  }
}
resource "aws_lb_target_group_attachment" "a" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = "${aws_lambda_function.scaleto0_lambda.arn}"

  depends_on = [
    aws_lambda_permission.allow_alb
  ]
}
 
###########################################################################
# Création d'une rule dans l'alb pour rediriger sur la lambda
###########################################################################
resource "aws_lb_listener_rule" "lambda" {
  listener_arn = var.alb_listener_arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    host_header {
      values = ["*.aws.kapable.info"]
    }
  }
}

###########################################################################
# Création d'une sns pour recevoir les alertes
###########################################################################
resource "aws_sns_topic" "monitoring" {
  name = "AlertStopService${var.stackname}${random_id.i.id}"
}
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.monitoring.arn
  protocol  = "email"
  endpoint  = "matgou1@msn.com"
}
resource "aws_sns_topic_subscription" "sns-topic" {
  topic_arn = aws_sns_topic.monitoring.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.scaleto0_lambda.arn
}

resource "aws_sns_topic_policy" "default" {
  arn    = aws_sns_topic.monitoring.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.monitoring.arn]
  }
}
###########################################################################
# Création d'une sns pour recevoir les alertes
###########################################################################

resource "aws_cloudwatch_metric_alarm" "stop" {
  alarm_name                = "stop-svc-${var.stackname}-${random_id.i.id}"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = "4"
  metric_name               = "RequestCount"
  namespace                 = "AWS/ApplicationELB"
  period                    = "300"
  statistic                 = "Maximum"
  threshold                 = "0"
  alarm_description         = "This metric monitors utilization of svc"
  insufficient_data_actions = []

  dimensions = {
    TargetGroup = var.target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }
}
resource "aws_cloudwatch_event_rule" "stop" {
  name        = "capture-stop-svc-${var.stackname}-${random_id.i.id}"
  description = "Capture no request on ${var.stackname} ${random_id.i.id}"

  event_pattern = <<EOF
{
  "source": [
    "aws.cloudwatch"
  ],
  "detail-type": [
    "CloudWatch Alarm State Change"
  ],
  "resources": [
    "${aws_cloudwatch_metric_alarm.stop.arn}"
  ]
}
EOF
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.stop.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.monitoring.arn
}

