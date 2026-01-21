#!/usr/bin/env python3
"""
AWS Budget and Alert Configuration

Sets up AWS Budgets with alert notifications for cost control.
Configures multi-threshold alerts and cost anomaly detection.
"""

import boto3
import json
from datetime import datetime
from typing import Dict, List, Any
import sys


class BudgetManager:
    def __init__(self, account_id: str = None):
        self.budgets = boto3.client('budgets', region_name='us-east-1')  # Budgets API is global
        self.ce = boto3.client('ce', region_name='us-east-1')  # Cost Explorer
        self.sns = boto3.client('sns', region_name='us-east-1')
        self.cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')

        # Get account ID if not provided
        if account_id is None:
            sts = boto3.client('sts')
            self.account_id = sts.get_caller_identity()['Account']
        else:
            self.account_id = account_id

    def create_sns_topic(self, topic_name: str, dry_run: bool = True) -> str:
        """Create SNS topic for budget alerts."""
        if dry_run:
            print(f"[DRY RUN] Would create SNS topic: {topic_name}")
            return f"arn:aws:sns:us-east-1:{self.account_id}:cost-optimization-alerts"

        try:
            response = self.sns.create_topic(Name=topic_name)
            topic_arn = response['TopicArn']
            print(f"✓ Created SNS topic: {topic_arn}")
            return topic_arn
        except self.sns.exceptions.TopicLimitExceededException:
            # Topic might already exist
            response = self.sns.list_topics()
            for topic in response['Topics']:
                if topic_name in topic['TopicArn']:
                    print(f"✓ Using existing SNS topic: {topic['TopicArn']}")
                    return topic['TopicArn']
            raise
        except Exception as e:
            print(f"✗ Error creating SNS topic: {e}")
            raise

    def subscribe_email_to_topic(self, topic_arn: str, email: str, dry_run: bool = True) -> None:
        """Subscribe an email address to SNS topic."""
        if dry_run:
            print(f"[DRY RUN] Would subscribe {email} to {topic_arn}")
            return

        try:
            self.sns.subscribe(
                TopicArn=topic_arn,
                Protocol='email',
                Endpoint=email
            )
            print(f"✓ Subscribed {email} to alerts (confirmation required)")
        except Exception as e:
            print(f"✗ Error subscribing email: {e}")

    def create_monthly_budget(self, budget_name: str, amount: float, threshold_percents: List[int],
                             topic_arn: str, dry_run: bool = True) -> bool:
        """Create a monthly cost budget with multiple thresholds."""
        if dry_run:
            print(f"[DRY RUN] Would create budget:")
            print(f"  Name: {budget_name}")
            print(f"  Amount: ${amount:.2f}/month")
            print(f"  Thresholds: {threshold_percents}")
            return True

        try:
            # Create budget
            budget = {
                'BudgetName': budget_name,
                'BudgetLimit': {
                    'Amount': str(amount),
                    'Unit': 'USD'
                },
                'TimeUnit': 'MONTHLY',
                'BudgetType': 'COST',
                'CostFilters': {},
                'CostTypes': {
                    'IncludeTax': True,
                    'IncludeSubscription': True,
                    'UseBlended': False,
                    'IncludeRefund': False,
                    'IncludeCredit': False,
                    'IncludeUpfront': True,
                    'IncludeRecurring': True,
                    'IncludeOtherSubscription': True,
                    'IncludeSupport': True,
                    'IncludeDiscount': True,
                    'UseAmortized': False
                }
            }

            # Create notifications for each threshold
            notifications = []
            for threshold in threshold_percents:
                notifications.append({
                    'Notification': {
                        'NotificationType': 'ACTUAL',
                        'ComparisonOperator': 'GREATER_THAN',
                        'Threshold': threshold,
                        'ThresholdType': 'PERCENTAGE',
                        'NotificationState': 'ALARM'
                    },
                    'Subscribers': [
                        {
                            'SubscriptionType': 'SNS',
                            'Address': topic_arn
                        }
                    ]
                })

            # Also add forecasted threshold at 100%
            notifications.append({
                'Notification': {
                    'NotificationType': 'FORECASTED',
                    'ComparisonOperator': 'GREATER_THAN',
                    'Threshold': 100,
                    'ThresholdType': 'PERCENTAGE',
                    'NotificationState': 'ALARM'
                },
                'Subscribers': [
                    {
                        'SubscriptionType': 'SNS',
                        'Address': topic_arn
                    }
                ]
            })

            self.budgets.create_budget(
                AccountId=self.account_id,
                Budget=budget,
                NotificationsWithSubscribers=notifications
            )

            print(f"✓ Created budget: {budget_name} (${amount}/month)")
            return True

        except self.budgets.exceptions.DuplicateRecordException:
            print(f"✓ Budget {budget_name} already exists")
            return True
        except Exception as e:
            print(f"✗ Error creating budget: {e}")
            return False

    def create_service_budget(self, service_name: str, amount: float, threshold_percents: List[int],
                             topic_arn: str, dry_run: bool = True) -> bool:
        """Create a budget for a specific service."""
        if dry_run:
            print(f"[DRY RUN] Would create {service_name} budget:")
            print(f"  Amount: ${amount:.2f}/month")
            print(f"  Thresholds: {threshold_percents}")
            return True

        try:
            budget_name = f"{service_name}-monthly-budget"

            budget = {
                'BudgetName': budget_name,
                'BudgetLimit': {
                    'Amount': str(amount),
                    'Unit': 'USD'
                },
                'TimeUnit': 'MONTHLY',
                'BudgetType': 'COST',
                'CostFilters': {
                    'Service': [service_name]
                },
                'CostTypes': {
                    'IncludeTax': True,
                    'IncludeSubscription': True,
                    'UseBlended': False,
                    'IncludeRefund': False,
                    'IncludeCredit': False,
                    'IncludeUpfront': True,
                    'IncludeRecurring': True,
                    'IncludeOtherSubscription': True,
                    'IncludeSupport': True,
                    'IncludeDiscount': True,
                    'UseAmortized': False
                }
            }

            notifications = []
            for threshold in threshold_percents:
                notifications.append({
                    'Notification': {
                        'NotificationType': 'ACTUAL',
                        'ComparisonOperator': 'GREATER_THAN',
                        'Threshold': threshold,
                        'ThresholdType': 'PERCENTAGE',
                        'NotificationState': 'ALARM'
                    },
                    'Subscribers': [
                        {
                            'SubscriptionType': 'SNS',
                            'Address': topic_arn
                        }
                    ]
                })

            self.budgets.create_budget(
                AccountId=self.account_id,
                Budget=budget,
                NotificationsWithSubscribers=notifications
            )

            print(f"✓ Created budget for {service_name}: ${amount}/month")
            return True

        except self.budgets.exceptions.DuplicateRecordException:
            print(f"✓ Budget for {service_name} already exists")
            return True
        except Exception as e:
            print(f"✗ Error creating {service_name} budget: {e}")
            return False

    def enable_cost_anomaly_detection(self, dry_run: bool = True) -> bool:
        """Enable AWS Cost Anomaly Detection."""
        if dry_run:
            print("[DRY RUN] Would enable Cost Anomaly Detection")
            return True

        try:
            # Create anomaly monitor for all services
            monitor_response = self.ce.create_anomaly_monitor(
                AnomalyMonitor={
                    'MonitorName': 'AllServices-AnomalyMonitor',
                    'MonitorType': 'DIMENSIONAL',
                    'MonitorDimension': 'SERVICE'
                }
            )
            monitor_arn = monitor_response['MonitorArn']
            print(f"✓ Created anomaly monitor: {monitor_arn}")

            # Create subscription for alerts
            subscription_response = self.ce.create_anomaly_subscription(
                AnomalySubscription={
                    'SubscriptionName': 'DailyAnomalyAlerts',
                    'MonitorArnList': [monitor_arn],
                    'Subscribers': [
                        {
                            'Type': 'EMAIL',
                            'Address': 'cloud-ops@company.com'  # Update with actual email
                        }
                    ],
                    'Threshold': 100.0,  # Alert on anomalies > $100
                    'Frequency': 'DAILY'
                }
            )
            print(f"✓ Created anomaly subscription")
            return True

        except Exception as e:
            if 'already exists' in str(e).lower():
                print("✓ Cost Anomaly Detection already enabled")
                return True
            print(f"✗ Error enabling anomaly detection: {e}")
            return False

    def create_cloudwatch_alarms(self, dry_run: bool = True) -> None:
        """Create CloudWatch alarms for cost monitoring."""
        if dry_run:
            print("[DRY RUN] Would create CloudWatch alarms for cost monitoring")
            return

        # Note: CloudWatch billing metrics are only available in us-east-1
        try:
            # Alarm for estimated charges
            self.cloudwatch.put_metric_alarm(
                AlarmName='HighEstimatedCharges',
                ComparisonOperator='GreaterThanThreshold',
                EvaluationPeriods=1,
                MetricName='EstimatedCharges',
                Namespace='AWS/Billing',
                Period=21600,  # 6 hours
                Statistic='Maximum',
                Threshold=5000.0,  # Alert if estimated charges > $5000
                ActionsEnabled=True,
                AlarmDescription='Alert when estimated AWS charges exceed $5000',
                Dimensions=[
                    {
                        'Name': 'Currency',
                        'Value': 'USD'
                    }
                ]
            )
            print("✓ Created CloudWatch alarm for estimated charges")
        except Exception as e:
            print(f"✗ Error creating CloudWatch alarm: {e}")

    def setup_complete_budget_configuration(self, total_budget: float, alert_emails: List[str],
                                           dry_run: bool = True) -> None:
        """Set up complete budget configuration with all thresholds."""
        print("=" * 80)
        print("AWS Budget Configuration Setup")
        print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
        print(f"Account ID: {self.account_id}")
        print("=" * 80)
        print()

        # Create SNS topic
        print("Step 1: Creating SNS topic for alerts...")
        topic_arn = self.create_sns_topic('cost-optimization-alerts', dry_run)
        print()

        # Subscribe emails
        print("Step 2: Subscribing email addresses...")
        for email in alert_emails:
            self.subscribe_email_to_topic(topic_arn, email, dry_run)
        print()

        # Create main budget with multiple thresholds
        print("Step 3: Creating main budget...")
        thresholds = [60, 80, 90, 100]  # Alert at 60%, 80%, 90%, and 100%
        self.create_monthly_budget(
            'Total-Monthly-Budget',
            total_budget,
            thresholds,
            topic_arn,
            dry_run
        )
        print()

        # Create service-specific budgets
        print("Step 4: Creating service-specific budgets...")

        # Allocate budget across services (adjust percentages as needed)
        service_allocations = {
            'Amazon DynamoDB': 0.50,  # 50% of budget
            'Amazon ElastiCache': 0.30,  # 30% of budget
            'Other': 0.20  # 20% for other services
        }

        for service, percentage in service_allocations.items():
            if service != 'Other':
                service_budget = total_budget * percentage
                self.create_service_budget(
                    service,
                    service_budget,
                    [80, 100],  # Alert at 80% and 100% for services
                    topic_arn,
                    dry_run
                )
        print()

        # Enable anomaly detection
        print("Step 5: Enabling Cost Anomaly Detection...")
        self.enable_cost_anomaly_detection(dry_run)
        print()

        # Create CloudWatch alarms
        print("Step 6: Creating CloudWatch alarms...")
        self.create_cloudwatch_alarms(dry_run)
        print()

        print("=" * 80)
        print("SETUP COMPLETE")
        print("=" * 80)
        print(f"Total monthly budget: ${total_budget:.2f}")
        print(f"Alert thresholds: {', '.join(f'{t}%' for t in thresholds)}")
        print(f"Subscribed emails: {len(alert_emails)}")
        print()

        if dry_run:
            print("This was a DRY RUN. Use --apply to create actual budgets.")
        else:
            print("Budget configuration is active!")
            print("Note: Email subscribers need to confirm their subscriptions.")
        print()

    def list_existing_budgets(self) -> None:
        """List all existing budgets."""
        print("=" * 80)
        print("Existing Budgets")
        print("=" * 80)
        print()

        try:
            response = self.budgets.describe_budgets(AccountId=self.account_id)

            if not response['Budgets']:
                print("No budgets found.")
                return

            for budget in response['Budgets']:
                print(f"Budget: {budget['BudgetName']}")
                print(f"  Type: {budget['BudgetType']}")
                print(f"  Amount: ${float(budget['BudgetLimit']['Amount']):.2f} {budget['BudgetLimit']['Unit']}")
                print(f"  Time Unit: {budget['TimeUnit']}")

                # Get notifications
                try:
                    notif_response = self.budgets.describe_notifications_for_budget(
                        AccountId=self.account_id,
                        BudgetName=budget['BudgetName']
                    )
                    if notif_response['Notifications']:
                        print(f"  Notifications:")
                        for notif in notif_response['Notifications']:
                            print(f"    - {notif['NotificationType']}: {notif['Threshold']}% ({notif['ComparisonOperator']})")
                except Exception:
                    pass

                print()

        except Exception as e:
            print(f"Error listing budgets: {e}")


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Configure AWS Budgets and cost alerts'
    )
    parser.add_argument('--profile', help='AWS profile to use')
    parser.add_argument('--account-id', help='AWS account ID')
    parser.add_argument('--setup', action='store_true', help='Set up complete budget configuration')
    parser.add_argument('--list', action='store_true', help='List existing budgets')
    parser.add_argument('--total-budget', type=float, default=5000, help='Total monthly budget (default: $5000)')
    parser.add_argument('--emails', nargs='+', help='Email addresses for alerts')
    parser.add_argument('--apply', action='store_true', help='Apply changes (default is dry-run)')

    args = parser.parse_args()

    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)

    try:
        manager = BudgetManager(account_id=args.account_id)

        if args.list:
            manager.list_existing_budgets()
        elif args.setup:
            if not args.emails:
                print("Error: --emails required for setup", file=sys.stderr)
                sys.exit(1)
            manager.setup_complete_budget_configuration(
                args.total_budget,
                args.emails,
                dry_run=not args.apply
            )
        else:
            print("Use --setup to configure budgets or --list to view existing budgets")
            print("Example: python budget_alerts.py --setup --total-budget 5000 --emails ops@company.com --apply")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
