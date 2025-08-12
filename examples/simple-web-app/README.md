# Simple Web Application Example

This example demonstrates how to use the IaC solution modules to deploy a basic web application with the following architecture:

- **VPC** with public and private subnets across multiple AZs
- **Application Load Balancer** for high availability
- **Web servers** in public subnets (2 instances)
- **Application servers** in private subnets (1 instance)
- **Optional RDS database** in private subnets
- **Security groups** with proper access controls

## Architecture Diagram

