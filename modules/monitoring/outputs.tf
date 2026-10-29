output "dashboard_name" { value = aws_cloudwatch_dashboard.hybrid.dashboard_name }
output "alarm_names" { value = { for key, alarm in aws_cloudwatch_metric_alarm.health : key => alarm.alarm_name } }
output "audit_trail_arn" { value = local.trail_arn }
output "budget_name" { value = var.existing_budget_name != null ? var.existing_budget_name : aws_budgets_budget.monthly[0].name }
