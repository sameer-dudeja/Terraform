output "env_url" {
  description = "DNS name of the load balancer"
  value       = module.blog_alb.dns_name
}

