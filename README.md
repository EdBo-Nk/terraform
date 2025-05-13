# Payload pharsing and storing microservices 

A deployment system for two Docker microservices on AWS ECS using Terraform and GitHub Actions.

## flow

```
[Internet] → [ALB:8080] → [email-api] → [SQS] → [sqs-to-s3] → [S3]
                     ↘ [ALB:3000] → [Grafana]
```

## Components

1. **Infrastructure (This Repository)**
   - AWS resources managed with Terraform
   - CI/CD pipeline with GitHub Actions
   - Automatic infrastructure updates on code changes (triggered when main code changes are pushed on the microservices repos, causing a pus on this repo, causing the docker containers to be deployed into "production")

2. **Microservice 1: Email API** [https://github.com/EdBo-Nk/email-api-micro1]
   - REST API validating requests and forwarding to SQS
   - Token validation via SSM Parameter Store

3. **Microservice 2: SQS to S3** [https://github.com/EdBo-Nk/sqs-to-s3-micro2]
   - Pulls messages from SQS and stores in designated S3 bucket

## Deployment

1. **Terraform Setup**
   ```bash
   terraform init
   terraform apply
   ```

2. **Create Authentication Token**
   ```bash
   aws ssm put-parameter --name "email-api-token" --type "SecureString" --value "your-token" --region us-east-2
   ```

3. **API Usage**

```
```bash
curl -X POST http://email-api-alb-<insert-alb-id>.us-east-2.elb.amazonaws.com:8080/send \
  -H "Content-Type: application/json" \
  -d "{
    \"data\": {
      \"email_subject\": \"Test Subject\",
      \"email_sender\": \"test@checkpoint.com\",
      \"email_timestream\": \"$(date +%s)\",
      \"email_content\": \"Just a check\"
    },
    \"token\": \"your-token\"
  }"
```


4. **Monitoring**: Access Grafana at `[http://{alb-dns-name}](http://email-api-alb-<insert-alb-id>.us-east-2.elb.amazonaws.com:3000` (Will not contain the dashboards I created, since its a new deployment)

## Notes

- Least privilege IAM roles (started with testing as admin, working way down to least privileages)
- Automated build and deployment workflow
