output "namespace" {
  description = "Namespace the service is deployed into."
  value       = kubernetes_namespace_v1.service.metadata[0].name
}

output "commands_queue_url" {
  description = "Queue the OS service sends this service's commands to."
  value       = aws_sqs_queue.commands.url
}

output "commands_dlq_url" {
  description = "Where commands this service could not handle end up after max_receive_count attempts."
  value       = aws_sqs_queue.commands_dlq.url
}
