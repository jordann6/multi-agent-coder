# multi-agent-coder

A multi-agent system deployed on AWS Lambda that routes natural language coding tasks to specialist agents via an orchestrator. The orchestrator receives a task over HTTP, delegates to a Coder specialist Lambda, and returns a structured result. Built with the Anthropic SDK tool-use pattern and fully provisioned with Terraform.

## Architecture

```
Client
  POST /task
    API Gateway (HTTP API)
      Orchestrator Lambda
        invoke() → Coder Lambda
                      tool-use loop (write_code | explain_code | debug_code)
                      returns structured JSON result
        synthesizes → final response
```

## Supported task types

| Type | Example prompt |
|---|---|
| write_code | "Write a Python function that flattens a nested list" |
| explain_code | "Explain what this Go function does: ..." |
| debug_code | "Debug this JavaScript: ... Error: Cannot read property of undefined" |

## Deploy

```bash
chmod +x build.sh && ./build.sh
cd terraform
terraform init
terraform apply -var="anthropic_api_key=sk-ant-..."
```

## Test

```bash
curl -X POST <API_ENDPOINT> \
  -H "Content-Type: application/json" \
  -d '{"task": "Write a Python function that flattens a nested list"}'
```

## Teardown

```bash
cd terraform
terraform destroy -var="anthropic_api_key=placeholder"
```
