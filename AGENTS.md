# AGENTS.md - Development Guide for AI Coding Agents

## Build/Test/Lint Commands
- `terraform init` - Initialize Terraform working directory
- `terraform plan` - Preview infrastructure changes
- `terraform apply` - Apply infrastructure changes
- `terraform destroy` - Destroy all resources
- `terraform validate` - Validate Terraform configuration syntax
- `terraform fmt` - Format Terraform files to canonical style

## Code Style Guidelines

### Terraform Files (.tf)
- Use snake_case for all resource names, variables, and locals
- Indent with 2 spaces consistently
- Use double quotes for strings
- Group related resources in separate files (e.g., k3s-servers.tf, k3s-agents.tf)
- Add descriptions to all variables using the `description` attribute
- Use validation blocks for variables with restricted values

### Variable Conventions
- Define default values where appropriate
- Use proper types (string, number, bool, list, map)
- Group related variables together in variables.tf
- Use meaningful variable names that describe their purpose

### Resource Naming
- Prefix resources with common identifier (e.g., "k3s_server", "k3s_agent")
- Use descriptive names that indicate resource purpose
- Follow pattern: `resource_type.descriptive_name`

### Comments and Documentation
- Use inline comments sparingly, prefer self-documenting code
- Document complex templatefile() usage
- Explain non-obvious resource dependencies

This is a Terraform project for deploying IBM AIOps on vSphere with K3s cluster.
