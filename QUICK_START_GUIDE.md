# Quick Start Guide
## AWS Cost Optimization for DynamoDB & ElastiCache

Get started with AWS cost optimization in 30 minutes!

---

## Prerequisites

**Required:**
- AWS account with appropriate permissions
- Python 3.8 or higher
- AWS CLI configured with credentials

**Permissions Required:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:ListTables",
        "dynamodb:ListTagsOfResource",
        "dynamodb:TagResource",
        "dynamodb:UpdateTable",
        "elasticache:DescribeCacheClusters",
        "elasticache:DescribeReplicationGroups",
        "elasticache:ListTagsForResource",
        "elasticache:AddTagsToResource",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:PutMetricAlarm",
        "application-autoscaling:*",
        "budgets:*",
        "ce:*",
        "sns:*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Installation

### Step 1: Clone or Download Files

```bash
# If using git
git clone https://github.com/your-org/aws-cost-optimization.git
cd aws-cost-optimization

# Or download and extract ZIP
```

### Step 2: Install Dependencies

```bash
# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install required packages
pip install -r requirements.txt
```

### Step 3: Configure AWS Credentials

```bash
# Option 1: Using AWS CLI
aws configure

# Option 2: Using environment variables
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1

# Option 3: Using AWS profile
export AWS_PROFILE=your-profile-name
```

### Step 4: Verify Setup

```bash
# Test AWS connectivity
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

---

## 30-Minute Quick Start

### Minute 0-5: Initial Cost Analysis

Run the cost analysis scripts to understand your current spend:

```bash
# Analyze DynamoDB costs
python cost_analysis_dynamodb.py --region us-east-1

# Analyze ElastiCache costs
python cost_analysis_elasticache.py --region us-east-1
```

**What to look for:**
- Total estimated monthly cost
- Top 5 most expensive resources
- Untagged resources count
- Over-provisioned resources

**Example Output:**
```
================================================================================
DynamoDB Cost Analysis Report
Region: us-east-1
Generated: 2026-01-21 10:30:00
================================================================================

Found 12 DynamoDB tables

┌────────────────────┬──────────────┬─────────┬────────┬──────┬────────────────┐
│ Table Name         │ Billing Mode │ Size    │ Items  │ GSIs │ Est. Cost/Month│
├────────────────────┼──────────────┼─────────┼────────┼──────┼────────────────┤
│ users-prod         │ PROVISIONED  │ 25.3 GB │ 500K   │ 3    │ $850.00        │
│ orders-prod        │ ON_DEMAND    │ 10.2 GB │ 150K   │ 1    │ $420.00        │
│ sessions-prod      │ PROVISIONED  │ 5.1 GB  │ 80K    │ 0    │ $180.00        │
└────────────────────┴──────────────┴─────────┴────────┴──────┴────────────────┘

Total Estimated Monthly Cost: $2,450.00

UNTAGGED TABLES (HIGH PRIORITY)
  • users-prod
    Missing tags: Environment, CostCenter, Owner
```

---

### Minute 5-10: Tag Compliance Check

Check which resources are missing required tags:

```bash
# Generate tagging compliance report
python tag_enforcement.py --report --region us-east-1
```

**What to look for:**
- Non-compliant resources count
- Missing mandatory tags
- Tag coverage percentage

**Example Output:**
```
COMPLIANCE SUMMARY
Compliant Resources: 3 (25.0%)
Non-Compliant Resources: 9 (75.0%)

NON-COMPLIANT RESOURCES
┌─────────────────┬──────────────────┬────────────────────────────────────┐
│ Type            │ Resource Name    │ Issues                             │
├─────────────────┼──────────────────┼────────────────────────────────────┤
│ dynamodb        │ users-prod       │ Missing: Environment, CostCenter   │
│ elasticache     │ cache-cluster-1  │ Missing: Owner, Application        │
└─────────────────┴──────────────────┴────────────────────────────────────┘
```

---

### Minute 10-15: Apply Tags (Dry Run)

Test tagging automation before applying:

```bash
# Dry run - see what would be tagged
python tag_enforcement.py --bulk-tag --region us-east-1
```

**Review the output carefully!**

If everything looks good:

```bash
# Apply tags to all resources
python tag_enforcement.py --bulk-tag --apply --region us-east-1
```

**Expected Result:**
- All resources tagged with mandatory tags
- 100% compliance achieved

---

### Minute 15-20: Auto-Scaling Analysis

Analyze tables for auto-scaling opportunities:

```bash
# Analyze DynamoDB auto-scaling opportunities
python dynamodb_autoscaling_analyzer.py --region us-east-1
```

**What to look for:**
- Over-provisioned tables (utilization <30%)
- Under-provisioned tables (utilization >80%)
- Recommended capacity mode (On-Demand vs Provisioned)
- Potential monthly savings

**Example Output:**
```
AUTO-SCALING CONFIGURATION SUMMARY
┌─────────────┬──────────────┬─────────────┬─────────────┬─────────────┬──────────────┐
│ Table Name  │ Current Mode │ Auto-Scaling│ Pattern     │ Variability │ Recommended  │
├─────────────┼──────────────┼─────────────┼─────────────┼─────────────┼──────────────┤
│ users-prod  │ PROVISIONED  │ No          │ steady      │ 15.2%       │ provisioned- │
│             │              │             │             │             │ autoscaling  │
│ orders-prod │ ON_DEMAND    │ N/A         │ spiky       │ 85.3%       │ on-demand    │
└─────────────┴──────────────┴─────────────┴─────────────┴─────────────┴──────────────┘

ESTIMATED SAVINGS POTENTIAL
Monthly: $680.00
Annual: $8,160.00
```

---

### Minute 20-25: Set Up Budgets

Configure budget alerts to monitor spending:

```bash
# Set up budgets (dry run first)
python budget_alerts.py --setup \
  --total-budget 5000 \
  --emails ops@company.com \
  --region us-east-1
```

Review the configuration, then apply:

```bash
# Apply budget configuration
python budget_alerts.py --setup \
  --total-budget 5000 \
  --emails ops@company.com finance@company.com \
  --apply
```

**What this does:**
- Creates SNS topic for alerts
- Subscribes your email addresses
- Sets up budget thresholds (60%, 80%, 90%, 100%)
- Enables cost anomaly detection

**Important:** Check your email and confirm SNS subscriptions!

---

### Minute 25-30: Review & Plan

Review the generated reports and plan your optimization:

```bash
# List all generated reports
ls -lh *_analysis_*.json *_report_*.json

# Review implementation roadmap
cat IMPLEMENTATION_ROADMAP.md
```

**Key Questions to Answer:**
1. What's our current monthly spend?
2. What's our biggest cost driver?
3. How much can we save with auto-scaling?
4. Which resources should we optimize first?
5. What's our timeline for implementation?

---

## Next Steps

### Immediate Actions (This Week)

1. **Clean up old resources**
   ```bash
   python cleanup_automation.py --report --region us-east-1
   # Review recommendations
   python cleanup_automation.py --cleanup-backups --apply
   ```

2. **Implement auto-scaling for top 3 tables**
   ```bash
   python implement_autoscaling.py \
     --analysis-file dynamodb_autoscaling_analysis_*.json \
     --apply
   ```

3. **Monitor for 24-48 hours**
   - Watch CloudWatch metrics
   - Check for throttling
   - Verify cost reduction in Cost Explorer

### Week 2-4: Full Implementation

Follow the complete [Implementation Roadmap](IMPLEMENTATION_ROADMAP.md) for:
- Phase 2: Quick wins and cleanup
- Phase 3: Advanced optimization
- Phase 4: Automation and governance

---

## Common Issues & Solutions

### Issue: "Access Denied" Errors

**Solution:**
```bash
# Check your permissions
aws sts get-caller-identity

# Verify you have required IAM permissions
aws iam get-user-policy --user-name YourUser --policy-name YourPolicy
```

### Issue: "No resources found"

**Solution:**
- Verify you're in the correct region: `--region us-east-1`
- Check if resources exist: `aws dynamodb list-tables`
- Ensure AWS CLI is configured correctly

### Issue: Scripts run slowly

**Solution:**
- Reduce analysis period: `--usage-days 7` instead of 14
- Analyze specific tables only
- Run during off-peak hours

### Issue: Can't install dependencies

**Solution:**
```bash
# Upgrade pip first
pip install --upgrade pip

# Install with verbose output
pip install -r requirements.txt -v

# If on Mac with M1/M2:
pip install --only-binary :all: -r requirements.txt
```

### Issue: Email alerts not received

**Solution:**
1. Check spam/junk folder
2. Confirm SNS subscription (check email)
3. Verify email address in configuration
4. Test SNS topic manually:
   ```bash
   aws sns publish \
     --topic-arn arn:aws:sns:us-east-1:123456789012:cost-alerts \
     --message "Test alert"
   ```

---

## Useful Commands Reference

### Cost Analysis
```bash
# DynamoDB analysis with specific region
python cost_analysis_dynamodb.py --region us-east-1 --profile prod

# ElastiCache analysis
python cost_analysis_elasticache.py --region us-west-2

# Export results to JSON
python cost_analysis_dynamodb.py > analysis.log 2>&1
```

### Tagging Operations
```bash
# Compliance report only
python tag_enforcement.py --report

# Bulk tag with dry-run
python tag_enforcement.py --bulk-tag

# Apply tags
python tag_enforcement.py --bulk-tag --apply

# Custom policy file
python tag_enforcement.py --policy-file custom_tags.json --report
```

### Auto-Scaling
```bash
# Analyze only
python dynamodb_autoscaling_analyzer.py --region us-east-1

# Implement (dry-run)
python implement_autoscaling.py \
  --analysis-file analysis.json

# Apply changes
python implement_autoscaling.py \
  --analysis-file analysis.json \
  --apply
```

### Cleanup
```bash
# Generate cleanup report
python cleanup_automation.py --report

# Delete old backups (30+ days)
python cleanup_automation.py --cleanup-backups \
  --backup-age-days 30 --apply

# Identify unused resources
python cleanup_automation.py --report --usage-days 14
```

### Budget Management
```bash
# Setup budgets
python budget_alerts.py --setup \
  --total-budget 5000 \
  --emails ops@company.com

# List existing budgets
python budget_alerts.py --list

# Update budget thresholds
# Edit the script or use AWS Console
```

---

## Monitoring Your Results

### Daily Checks (Automated)
- Tag compliance report
- Budget alert review
- Cost anomaly notifications

### Weekly Reviews
```bash
# Run weekly cost analysis
python cost_analysis_dynamodb.py > weekly_report.log
python cost_analysis_elasticache.py >> weekly_report.log

# Check for new optimization opportunities
python dynamodb_autoscaling_analyzer.py
```

### Monthly Reviews
- Compare actual vs budgeted spend
- Review Reserved Capacity utilization
- Assess auto-scaling effectiveness
- Update optimization strategy

### Key Metrics to Track

1. **Cost Metrics:**
   - Total monthly AWS spend
   - Cost per service (DynamoDB, ElastiCache)
   - Cost per environment (prod, staging, dev)
   - Month-over-month change

2. **Efficiency Metrics:**
   - DynamoDB average utilization %
   - ElastiCache cache hit rate %
   - Throttled requests (target: <0.1%)
   - Unused resources count (target: 0)

3. **Governance Metrics:**
   - Tagging compliance (target: 100%)
   - Budget variance (target: <5%)
   - Alert response time (target: <1 hour)

---

## Getting Help

### Documentation
- [Main README](AWS-COST-OPTIMIZATION-README.md)
- [Implementation Roadmap](IMPLEMENTATION_ROADMAP.md)
- [Tagging Policy](tagging_policy.json)

### AWS Resources
- [AWS Cost Management Console](https://console.aws.amazon.com/cost-management/)
- [DynamoDB Pricing](https://aws.amazon.com/dynamodb/pricing/)
- [ElastiCache Pricing](https://aws.amazon.com/elasticache/pricing/)

### Support Channels
- GitHub Issues: [Your Repo URL]
- Internal Slack: #aws-cost-optimization
- Email: cloud-ops@company.com

### AWS Support
- AWS Support Console
- AWS Trusted Advisor
- AWS Cost Explorer
- Your AWS Technical Account Manager (TAM)

---

## Success Checklist

After completing this quick start, you should have:

- [ ] Installed all dependencies
- [ ] Configured AWS credentials
- [ ] Run initial cost analysis
- [ ] Identified untagged resources
- [ ] Applied tags to all resources
- [ ] Analyzed auto-scaling opportunities
- [ ] Set up budget alerts
- [ ] Received and confirmed email subscriptions
- [ ] Reviewed potential savings estimates
- [ ] Created implementation plan

**Estimated Time:** 30 minutes
**Expected Immediate Value:** Complete visibility into current costs

**Next Milestone:** Implement auto-scaling and achieve 20-30% cost reduction within 2 weeks.

---

## Tips for Success

1. **Start Small:** Optimize 2-3 high-cost resources first
2. **Monitor Closely:** Watch metrics for 24-48 hours after changes
3. **Document Everything:** Keep track of what you change and why
4. **Test in Non-Prod:** Validate changes in dev/staging first
5. **Have Rollback Plans:** Know how to revert changes quickly
6. **Communicate:** Keep stakeholders informed of changes
7. **Automate:** Schedule scripts to run regularly
8. **Review Regularly:** Monthly cost optimization reviews

---

## Advanced Features

Once you're comfortable with the basics, explore:

- **Custom Dashboards:** Create Grafana dashboards
- **Advanced Automation:** Lambda functions for continuous optimization
- **Cost Allocation:** Detailed per-team/application cost tracking
- **Reserved Capacity:** Long-term savings with 1-3 year commitments
- **Savings Plans:** Flexible pricing model across services
- **Cross-Service Optimization:** Expand to EC2, S3, RDS

---

**Ready to save money? Let's get started! 🚀**

For questions or issues, refer to the [main documentation](AWS-COST-OPTIMIZATION-README.md) or contact your cloud operations team.
