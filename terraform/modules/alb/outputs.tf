output "dns_name" {
  value = aws_lb.this.dns_name
}
output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}
output "security_group_id" {
  value = aws_security_group.alb.id
}
output "lb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}
output "target_group_arn_suffix" {
  value = aws_lb_target_group.this.arn_suffix
}
