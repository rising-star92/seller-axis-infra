output "alb_arn" {
  description = "The ALB ARN"
  value       = aws_lb.selleraxis_lb.arn
}

output "aws_lb_target_group_arn" {
  description = "The ALB target group ARN"
  value       = aws_lb_target_group.selleraxis_lb_target_group.arn
}

output "target_group_arn_suffix" {
  description = "The ALB target group ARN"
  value       = aws_lb_target_group.selleraxis_lb_target_group.arn_suffix
}

output "lb_arn_suffix" {
  description = "The ALB target group ARN"
  value       = aws_lb.selleraxis_lb.arn_suffix
}
