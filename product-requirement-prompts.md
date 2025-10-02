# Product Requirement Prompts


## Objective

```
# What is the main goal of this project? Be specific and concise
Create a Terraform configuration to host a small Elasticsearch cluster on Digital Ocean. 

3 hot nodes (8 GB RAM)
1 cold node (2 GB RAM)
1 frozen node (2 GB RAM)

The lastest version of Elastic, 9.2, should be used.
## Why

```
# Explain the business value and problem this solves.
This is to create small PoC self-managed Elasticsearch clusters


```

## Success criteria

```
# Define measurable success metrics and acceptance criteria.
The Elasticsearch cluster has secure intranet networking setup and has appropriate ports open to the internet. 

A Searchable Snapshot repo is setup and Elastic ILM can writes data to it

The cluser follows the zero trust "principle of least privelege". 


```
## Documentation and references (Optional)

```
https://www.elastic.co/docs/

https://registry.terraform.io/providers/elastic/elasticstack/latest

https://registry.terraform.io/providers/digitalocean/digitalocean/latest


```

## Validation loop (Optional)

```
# Describe how to validate the implementation works correctly.
# Example: "1. Run test suite: npm test
#          2. Start local server: npm run dev
#          3. Test with Postman collection: ./tests/postman/"



```

## Syntax and style (Optional)

```
# Specify any coding standards or style preferences beyond the defaults.
# The template already includes Black, isort, and type hints.
# Example: "- Use async/await for all database operations
#          - Prefer composition over inheritance"



```

## Unit tests

```
# Describe the testing approach and any specific test cases needed.
# Example: "- Test all API endpoints with valid and invalid inputs
#          - Mock external services
#          - Test error handling and edge cases"



```

## Integration tests (Optional)

```
# Describe end-to-end testing requirements if applicable.
# Example: "- Test full order workflow from creation to delivery
#          - Test with real database (using test containers)
#          - Verify email notifications are sent"



```

## Security requirements (Optional)

```
# List specific security requirements beyond the template's built-in checks.
# Example: "- Implement rate limiting on all endpoints
#          - Audit log all data modifications
#          - Encrypt PII in database"



```