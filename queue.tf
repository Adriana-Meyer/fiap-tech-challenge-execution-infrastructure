# The queue the OS service sends this service's commands to (EnqueueExecution).
# The answers go the other way, through the saga-events topic that
# os-infrastructure creates.
#
# The name is fixed and carries no project prefix on purpose: the OS service
# sends to "execution-commands" and this service listens on it by default
# (COMMANDS_QUEUE). The same layout runs locally in
# os-service/e2e/localstack-init/01-saga-topology.sh.

# Commands this service could not handle after `max_receive_count` attempts
# land here instead of being retried for ever. Kept for the longest period SQS
# allows (14 days) so there is time to look at them.
resource "aws_sqs_queue" "commands_dlq" {
  name                      = "${var.service_name}-commands-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Name = "${var.service_name}-commands-dlq"
  }
}

resource "aws_sqs_queue" "commands" {
  name = "${var.service_name}-commands"
  # Longer than the slowest handling of one command, so a command being worked
  # on is not delivered a second time. The handlers are idempotent anyway.
  visibility_timeout_seconds = var.queue_visibility_timeout_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.commands_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = "${var.service_name}-commands"
  }
}
