# AWS Architecture

GitHub renders this diagram automatically. To export a PNG for submission, paste it into
https://mermaid.live and download, or redraw it in draw.io and save as `architecture.png` here.

```mermaid
flowchart TB
    user([Users / Internet])
    gh([GitHub Actions<br/>OIDC])

    subgraph aws[AWS Account - ap-south-1]
        r53[Route 53<br/>app.domain]
        acm[ACM Certificate]
        sm[Secrets Manager<br/>DB credentials]
        s3app[(S3 App Bucket<br/>code + storage)]
        s3logs[(S3 ALB Logs)]
        s3state[(S3 Terraform State)]

        subgraph vpc[VPC 10.0.0.0/16]
            igw[Internet Gateway]

            subgraph az1[AZ a]
                pub1[Public Subnet<br/>10.0.0.0/24]
                nat[NAT Gateway]
                app1[Private App Subnet<br/>10.0.10.0/24<br/>EC2]
                db1[Private DB Subnet<br/>10.0.20.0/24<br/>RDS MySQL]
            end

            subgraph az2[AZ b]
                pub2[Public Subnet<br/>10.0.1.0/24]
                app2[Private App Subnet<br/>10.0.11.0/24<br/>EC2]
                db2[Private DB Subnet<br/>10.0.21.0/24<br/>standby if Multi-AZ]
            end

            alb[Application Load Balancer<br/>443 HTTPS / 80 redirect]
            asg{{Auto Scaling Group<br/>Launch Template}}
        end
    end

    user -->|HTTPS| r53 --> alb
    acm -.TLS cert.-> alb
    igw --- alb
    alb -->|HTTP 8080| app1 & app2
    asg -.manages.-> app1 & app2
    app1 & app2 -->|MySQL 3306 TLS| db1
    db1 -.replication.-> db2
    app1 & app2 -->|GetSecretValue| sm
    app1 & app2 -->|outbound 443| nat --> igw
    app1 & app2 -->|app code| s3app
    alb -->|access logs| s3logs
    gh -->|terraform apply| aws
    gh -.state.-> s3state
```

## Traffic flow

1. A user opens `https://app.<domain>`. Route 53 resolves it to the ALB.
2. The ALB terminates TLS with the ACM certificate. Port 80 only returns a 301 redirect to HTTPS.
3. The ALB forwards to healthy EC2 instances on port 8080 in the private app subnets (2 AZs).
4. Instances fetch DB credentials from Secrets Manager and connect to RDS MySQL over TLS.
5. The ALB writes access logs to the logs bucket.
6. Instances have no public IPs. Outbound traffic (packages, AWS APIs) goes through the NAT Gateway.

## Security groups

| SG | Inbound | Outbound |
|---|---|---|
| alb-sg | 443, 80 from 0.0.0.0/0 | 8080 to app-sg |
| app-sg | 8080 from alb-sg | 443 to 0.0.0.0/0, 3306 to rds-sg |
| rds-sg | 3306 from app-sg | none |
