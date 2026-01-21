#!/usr/bin/env python3
"""
DynamoDB Auto-Scaling Implementation Tool

Implements auto-scaling configuration for DynamoDB tables based on
analysis recommendations.
"""

import boto3
import json
from typing import Dict, List, Any
import sys


class AutoScalingImplementer:
    def __init__(self, region: str = 'us-east-1'):
        self.region = region
        self.dynamodb = boto3.client('dynamodb', region_name=region)
        self.app_autoscaling = boto3.client('application-autoscaling', region_name=region)
        self.target_utilization = 70

    def register_scalable_target(self, table_name: str, dimension: str, min_capacity: int, max_capacity: int, dry_run: bool = True) -> bool:
        """Register a scalable target for auto-scaling."""
        resource_id = f"table/{table_name}"

        if dry_run:
            print(f"[DRY RUN] Would register scalable target:")
            print(f"  Resource: {resource_id}")
            print(f"  Dimension: {dimension}")
            print(f"  Min: {min_capacity}, Max: {max_capacity}")
            return True

        try:
            self.app_autoscaling.register_scalable_target(
                ServiceNamespace='dynamodb',
                ResourceId=resource_id,
                ScalableDimension=dimension,
                MinCapacity=min_capacity,
                MaxCapacity=max_capacity
            )
            print(f"✓ Registered scalable target for {table_name} ({dimension})")
            return True
        except Exception as e:
            print(f"✗ Error registering scalable target: {e}")
            return False

    def put_scaling_policy(self, table_name: str, dimension: str, target_value: float, dry_run: bool = True) -> bool:
        """Create target tracking scaling policy."""
        resource_id = f"table/{table_name}"
        policy_name = f"{table_name}-{dimension}-scaling-policy"

        if dry_run:
            print(f"[DRY RUN] Would create scaling policy:")
            print(f"  Policy: {policy_name}")
            print(f"  Target Utilization: {target_value}%")
            return True

        try:
            self.app_autoscaling.put_scaling_policy(
                PolicyName=policy_name,
                ServiceNamespace='dynamodb',
                ResourceId=resource_id,
                ScalableDimension=dimension,
                PolicyType='TargetTrackingScaling',
                TargetTrackingScalingPolicyConfiguration={
                    'TargetValue': target_value,
                    'PredefinedMetricSpecification': {
                        'PredefinedMetricType': 'DynamoDBReadCapacityUtilization' if 'Read' in dimension
                                                else 'DynamoDBWriteCapacityUtilization'
                    },
                    'ScaleInCooldown': 60,
                    'ScaleOutCooldown': 60
                }
            )
            print(f"✓ Created scaling policy for {table_name} ({dimension})")
            return True
        except Exception as e:
            print(f"✗ Error creating scaling policy: {e}")
            return False

    def enable_autoscaling(self, table_name: str, read_min: int, read_max: int,
                          write_min: int, write_max: int, dry_run: bool = True) -> bool:
        """Enable auto-scaling for a table."""
        print(f"\nEnabling auto-scaling for {table_name}:")

        # Register read capacity
        success = self.register_scalable_target(
            table_name,
            'dynamodb:table:ReadCapacityUnits',
            read_min,
            read_max,
            dry_run
        )
        if success:
            success = self.put_scaling_policy(
                table_name,
                'dynamodb:table:ReadCapacityUnits',
                self.target_utilization,
                dry_run
            )

        # Register write capacity
        if success:
            success = self.register_scalable_target(
                table_name,
                'dynamodb:table:WriteCapacityUnits',
                write_min,
                write_max,
                dry_run
            )
        if success:
            success = self.put_scaling_policy(
                table_name,
                'dynamodb:table:WriteCapacityUnits',
                self.target_utilization,
                dry_run
            )

        return success

    def switch_to_provisioned(self, table_name: str, read_capacity: int, write_capacity: int, dry_run: bool = True) -> bool:
        """Switch table from On-Demand to Provisioned mode."""
        if dry_run:
            print(f"[DRY RUN] Would switch {table_name} to Provisioned mode")
            print(f"  Read Capacity: {read_capacity}")
            print(f"  Write Capacity: {write_capacity}")
            return True

        try:
            self.dynamodb.update_table(
                TableName=table_name,
                BillingMode='PROVISIONED',
                ProvisionedThroughput={
                    'ReadCapacityUnits': read_capacity,
                    'WriteCapacityUnits': write_capacity
                }
            )
            print(f"✓ Switched {table_name} to Provisioned mode")
            return True
        except Exception as e:
            print(f"✗ Error switching to Provisioned mode: {e}")
            return False

    def switch_to_on_demand(self, table_name: str, dry_run: bool = True) -> bool:
        """Switch table to On-Demand mode."""
        if dry_run:
            print(f"[DRY RUN] Would switch {table_name} to On-Demand mode")
            return True

        try:
            self.dynamodb.update_table(
                TableName=table_name,
                BillingMode='PAY_PER_REQUEST'
            )
            print(f"✓ Switched {table_name} to On-Demand mode")
            return True
        except Exception as e:
            print(f"✗ Error switching to On-Demand mode: {e}")
            return False

    def implement_recommendations(self, analysis_file: str, dry_run: bool = True) -> None:
        """Implement recommendations from analysis file."""
        print("=" * 80)
        print("DynamoDB Auto-Scaling Implementation")
        print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
        print("=" * 80)
        print()

        with open(analysis_file, 'r') as f:
            data = json.load(f)

        success_count = 0
        failed_count = 0

        for analysis in data['analysis']:
            table_name = analysis['table_name']
            pattern = analysis['pattern']
            capacity = analysis['recommended_capacity']

            print(f"\nProcessing: {table_name}")
            print(f"  Pattern: {pattern['pattern']}")
            print(f"  Recommendation: {pattern['recommendation']}")

            try:
                if pattern['recommendation'] == 'on-demand':
                    if self.switch_to_on_demand(table_name, dry_run):
                        success_count += 1
                    else:
                        failed_count += 1
                else:
                    # Switch to provisioned and enable auto-scaling
                    if analysis['current_mode'] == 'PAY_PER_REQUEST':
                        if not self.switch_to_provisioned(
                            table_name,
                            capacity['read_min'],
                            capacity['write_min'],
                            dry_run
                        ):
                            failed_count += 1
                            continue

                    if self.enable_autoscaling(
                        table_name,
                        capacity['read_min'],
                        capacity['read_max'],
                        capacity['write_min'],
                        capacity['write_max'],
                        dry_run
                    ):
                        success_count += 1
                    else:
                        failed_count += 1
            except Exception as e:
                print(f"✗ Error implementing for {table_name}: {e}")
                failed_count += 1

        print()
        print("=" * 80)
        print("IMPLEMENTATION SUMMARY")
        print("=" * 80)
        print(f"Successfully configured: {success_count}")
        print(f"Failed: {failed_count}")
        print()

        if dry_run:
            print("This was a DRY RUN. Use --apply to make actual changes.")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Implement DynamoDB auto-scaling configuration'
    )
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--profile', help='AWS profile to use')
    parser.add_argument('--analysis-file', required=True, help='Path to analysis JSON file')
    parser.add_argument('--apply', action='store_true', help='Apply changes (default is dry-run)')

    args = parser.parse_args()

    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)

    try:
        implementer = AutoScalingImplementer(region=args.region)
        implementer.implement_recommendations(args.analysis_file, dry_run=not args.apply)
    except FileNotFoundError:
        print(f"Error: Analysis file '{args.analysis_file}' not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
