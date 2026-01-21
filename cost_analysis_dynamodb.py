#!/usr/bin/env python3
"""
DynamoDB Cost Analysis Tool

Analyzes DynamoDB usage patterns and costs to identify optimization opportunities.
Provides detailed insights into table costs, capacity modes, and recommendations.
"""

import boto3
import json
from datetime import datetime, timedelta
from collections import defaultdict
from typing import Dict, List, Any
import sys

try:
    from tabulate import tabulate
except ImportError:
    print("Warning: 'tabulate' not installed. Install with: pip install tabulate")
    tabulate = None


class DynamoDBCostAnalyzer:
    def __init__(self, region: str = 'us-east-1'):
        self.region = region
        self.dynamodb = boto3.client('dynamodb', region_name=region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.pricing = boto3.client('pricing', region_name='us-east-1')  # Pricing API only in us-east-1
        self.ce = boto3.client('ce', region_name='us-east-1')  # Cost Explorer only in us-east-1

        # DynamoDB pricing (approximate, actual may vary by region)
        self.pricing_data = {
            'provisioned': {
                'read_capacity_unit': 0.00013,  # per hour
                'write_capacity_unit': 0.00065,  # per hour
                'storage_gb': 0.25,  # per GB per month
            },
            'on_demand': {
                'read_request_unit': 0.00000025,  # per RRU
                'write_request_unit': 0.00000125,  # per WRU
                'storage_gb': 0.25,  # per GB per month
            },
            'backup_storage_gb': 0.10,  # per GB per month
            'pitr_storage_gb': 0.20,  # per GB per month
            'streams_read': 0.02,  # per 100,000 reads
        }

    def list_all_tables(self) -> List[str]:
        """List all DynamoDB tables in the region."""
        tables = []
        paginator = self.dynamodb.get_paginator('list_tables')

        for page in paginator.paginate():
            tables.extend(page['TableNames'])

        return tables

    def get_table_details(self, table_name: str) -> Dict[str, Any]:
        """Get detailed information about a table."""
        response = self.dynamodb.describe_table(TableName=table_name)
        table = response['Table']

        # Get table tags
        try:
            tags_response = self.dynamodb.list_tags_of_resource(
                ResourceArn=table['TableArn']
            )
            tags = {tag['Key']: tag['Value'] for tag in tags_response.get('Tags', [])}
        except Exception as e:
            print(f"Warning: Could not fetch tags for {table_name}: {e}")
            tags = {}

        return {
            'name': table_name,
            'status': table['TableStatus'],
            'item_count': table['ItemCount'],
            'size_bytes': table['TableSizeBytes'],
            'billing_mode': table.get('BillingModeSummary', {}).get('BillingMode', 'PROVISIONED'),
            'read_capacity': table.get('ProvisionedThroughput', {}).get('ReadCapacityUnits', 0),
            'write_capacity': table.get('ProvisionedThroughput', {}).get('WriteCapacityUnits', 0),
            'global_secondary_indexes': table.get('GlobalSecondaryIndexes', []),
            'local_secondary_indexes': table.get('LocalSecondaryIndexes', []),
            'stream_enabled': table.get('StreamSpecification', {}).get('StreamEnabled', False),
            'pitr_enabled': False,  # Will fetch separately
            'tags': tags,
            'arn': table['TableArn']
        }

    def check_pitr_status(self, table_name: str) -> bool:
        """Check if Point-in-Time Recovery is enabled."""
        try:
            response = self.dynamodb.describe_continuous_backups(TableName=table_name)
            return response['ContinuousBackupsDescription']['PointInTimeRecoveryDescription']['PointInTimeRecoveryStatus'] == 'ENABLED'
        except Exception as e:
            print(f"Warning: Could not check PITR status for {table_name}: {e}")
            return False

    def get_table_metrics(self, table_name: str, days: int = 7) -> Dict[str, float]:
        """Get CloudWatch metrics for a table."""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)

        metrics = {}
        metric_names = [
            ('ConsumedReadCapacityUnits', 'Sum'),
            ('ConsumedWriteCapacityUnits', 'Sum'),
            ('ProvisionedReadCapacityUnits', 'Average'),
            ('ProvisionedWriteCapacityUnits', 'Average'),
            ('UserErrors', 'Sum'),
            ('SystemErrors', 'Sum'),
        ]

        for metric_name, stat in metric_names:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='AWS/DynamoDB',
                    MetricName=metric_name,
                    Dimensions=[
                        {'Name': 'TableName', 'Value': table_name}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,  # 1 hour
                    Statistics=[stat]
                )

                if response['Datapoints']:
                    values = [dp[stat] for dp in response['Datapoints']]
                    metrics[metric_name] = sum(values) / len(values) if stat == 'Average' else sum(values)
                else:
                    metrics[metric_name] = 0
            except Exception as e:
                print(f"Warning: Could not fetch {metric_name} for {table_name}: {e}")
                metrics[metric_name] = 0

        return metrics

    def estimate_table_cost(self, table_details: Dict[str, Any], metrics: Dict[str, float]) -> Dict[str, float]:
        """Estimate monthly cost for a table."""
        costs = {
            'storage': 0.0,
            'throughput': 0.0,
            'backup': 0.0,
            'pitr': 0.0,
            'streams': 0.0,
            'total': 0.0
        }

        # Storage cost
        size_gb = table_details['size_bytes'] / (1024 ** 3)
        costs['storage'] = size_gb * self.pricing_data['provisioned']['storage_gb']

        # Throughput cost
        if table_details['billing_mode'] == 'PROVISIONED':
            # Provisioned capacity
            read_units = table_details['read_capacity']
            write_units = table_details['write_capacity']

            hours_per_month = 730
            costs['throughput'] = (
                read_units * self.pricing_data['provisioned']['read_capacity_unit'] * hours_per_month +
                write_units * self.pricing_data['provisioned']['write_capacity_unit'] * hours_per_month
            )

            # Add GSI costs
            for gsi in table_details['global_secondary_indexes']:
                gsi_read = gsi.get('ProvisionedThroughput', {}).get('ReadCapacityUnits', 0)
                gsi_write = gsi.get('ProvisionedThroughput', {}).get('WriteCapacityUnits', 0)
                costs['throughput'] += (
                    gsi_read * self.pricing_data['provisioned']['read_capacity_unit'] * hours_per_month +
                    gsi_write * self.pricing_data['provisioned']['write_capacity_unit'] * hours_per_month
                )
        else:
            # On-Demand pricing (estimate from metrics)
            read_requests = metrics.get('ConsumedReadCapacityUnits', 0) * 30 / 7  # Scale to monthly
            write_requests = metrics.get('ConsumedWriteCapacityUnits', 0) * 30 / 7

            costs['throughput'] = (
                read_requests * self.pricing_data['on_demand']['read_request_unit'] +
                write_requests * self.pricing_data['on_demand']['write_request_unit']
            )

        # PITR cost (estimate as 2x storage cost)
        if table_details.get('pitr_enabled', False):
            costs['pitr'] = size_gb * self.pricing_data['pitr_storage_gb']

        # Backup cost (approximate - would need to query actual backups)
        costs['backup'] = size_gb * self.pricing_data['backup_storage_gb'] * 2  # Assuming 2 backups

        costs['total'] = sum(costs.values())
        return costs

    def analyze_utilization(self, table_details: Dict[str, Any], metrics: Dict[str, float]) -> Dict[str, Any]:
        """Analyze capacity utilization and provide recommendations."""
        analysis = {
            'read_utilization': 0.0,
            'write_utilization': 0.0,
            'is_over_provisioned': False,
            'is_under_provisioned': False,
            'recommendations': []
        }

        if table_details['billing_mode'] == 'PROVISIONED':
            provisioned_read = metrics.get('ProvisionedReadCapacityUnits', 1)
            provisioned_write = metrics.get('ProvisionedWriteCapacityUnits', 1)
            consumed_read = metrics.get('ConsumedReadCapacityUnits', 0) / (168 * 3600)  # Per second over 7 days
            consumed_write = metrics.get('ConsumedWriteCapacityUnits', 0) / (168 * 3600)

            analysis['read_utilization'] = (consumed_read / provisioned_read * 100) if provisioned_read > 0 else 0
            analysis['write_utilization'] = (consumed_write / provisioned_write * 100) if provisioned_write > 0 else 0

            # Check for over-provisioning (< 30% utilization)
            if analysis['read_utilization'] < 30 or analysis['write_utilization'] < 30:
                analysis['is_over_provisioned'] = True
                analysis['recommendations'].append(
                    f"Table is over-provisioned. Read: {analysis['read_utilization']:.1f}%, "
                    f"Write: {analysis['write_utilization']:.1f}%. Consider reducing capacity or switching to On-Demand."
                )

            # Check for under-provisioning (> 80% utilization)
            if analysis['read_utilization'] > 80 or analysis['write_utilization'] > 80:
                analysis['is_under_provisioned'] = True
                analysis['recommendations'].append(
                    f"Table may be under-provisioned. Read: {analysis['read_utilization']:.1f}%, "
                    f"Write: {analysis['write_utilization']:.1f}%. Consider increasing capacity or enabling auto-scaling."
                )

            # Check if auto-scaling is configured
            if not table_details.get('autoscaling_enabled', False):
                analysis['recommendations'].append("Consider enabling auto-scaling to optimize costs.")

        # Check for missing tags
        required_tags = ['Environment', 'Application', 'CostCenter', 'Owner']
        missing_tags = [tag for tag in required_tags if tag not in table_details['tags']]
        if missing_tags:
            analysis['recommendations'].append(f"Missing required tags: {', '.join(missing_tags)}")

        # Check for GSI optimization
        if len(table_details['global_secondary_indexes']) > 3:
            analysis['recommendations'].append(
                f"Table has {len(table_details['global_secondary_indexes'])} GSIs. "
                "Each GSI adds significant cost. Review if all are necessary."
            )

        return analysis

    def generate_report(self) -> None:
        """Generate comprehensive cost analysis report."""
        print("=" * 80)
        print("DynamoDB Cost Analysis Report")
        print(f"Region: {self.region}")
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        print()

        tables = self.list_all_tables()
        print(f"Found {len(tables)} DynamoDB tables")
        print()

        if not tables:
            print("No tables found in this region.")
            return

        total_cost = 0.0
        all_table_data = []
        untagged_tables = []
        optimization_opportunities = []

        for table_name in tables:
            print(f"Analyzing: {table_name}...", end=' ')
            try:
                details = self.get_table_details(table_name)
                details['pitr_enabled'] = self.check_pitr_status(table_name)
                metrics = self.get_table_metrics(table_name)
                costs = self.estimate_table_cost(details, metrics)
                analysis = self.analyze_utilization(details, metrics)

                table_data = {
                    'name': table_name,
                    'details': details,
                    'metrics': metrics,
                    'costs': costs,
                    'analysis': analysis
                }
                all_table_data.append(table_data)
                total_cost += costs['total']

                # Check for untagged tables
                required_tags = ['Environment', 'Application', 'CostCenter', 'Owner']
                if not all(tag in details['tags'] for tag in required_tags):
                    untagged_tables.append(table_name)

                # Collect optimization opportunities
                if analysis['recommendations']:
                    optimization_opportunities.append({
                        'table': table_name,
                        'recommendations': analysis['recommendations']
                    })

                print("✓")
            except Exception as e:
                print(f"✗ Error: {e}")

        print()

        # Summary table
        print("=" * 80)
        print("COST SUMMARY")
        print("=" * 80)

        if tabulate:
            summary_data = []
            for table_data in sorted(all_table_data, key=lambda x: x['costs']['total'], reverse=True):
                summary_data.append([
                    table_data['name'][:30],
                    table_data['details']['billing_mode'],
                    f"{table_data['details']['size_bytes'] / (1024**3):.2f} GB",
                    f"{table_data['details']['item_count']:,}",
                    len(table_data['details']['global_secondary_indexes']),
                    f"${table_data['costs']['total']:.2f}"
                ])

            print(tabulate(
                summary_data,
                headers=['Table Name', 'Billing Mode', 'Size', 'Items', 'GSIs', 'Est. Monthly Cost'],
                tablefmt='grid'
            ))
        else:
            for table_data in sorted(all_table_data, key=lambda x: x['costs']['total'], reverse=True):
                print(f"\nTable: {table_data['name']}")
                print(f"  Billing Mode: {table_data['details']['billing_mode']}")
                print(f"  Size: {table_data['details']['size_bytes'] / (1024**3):.2f} GB")
                print(f"  Items: {table_data['details']['item_count']:,}")
                print(f"  GSIs: {len(table_data['details']['global_secondary_indexes'])}")
                print(f"  Estimated Monthly Cost: ${table_data['costs']['total']:.2f}")

        print()
        print(f"Total Estimated Monthly Cost: ${total_cost:.2f}")
        print()

        # Untagged resources
        if untagged_tables:
            print("=" * 80)
            print("UNTAGGED TABLES (HIGH PRIORITY)")
            print("=" * 80)
            for table_name in untagged_tables:
                table_data = next(t for t in all_table_data if t['name'] == table_name)
                missing_tags = [tag for tag in ['Environment', 'Application', 'CostCenter', 'Owner']
                              if tag not in table_data['details']['tags']]
                print(f"  • {table_name}")
                print(f"    Missing tags: {', '.join(missing_tags)}")
                print(f"    Current tags: {table_data['details']['tags']}")
            print()

        # Optimization opportunities
        if optimization_opportunities:
            print("=" * 80)
            print("OPTIMIZATION OPPORTUNITIES")
            print("=" * 80)
            for opp in optimization_opportunities:
                print(f"\n{opp['table']}:")
                for rec in opp['recommendations']:
                    print(f"  • {rec}")
            print()

        # Savings potential
        print("=" * 80)
        print("ESTIMATED SAVINGS POTENTIAL")
        print("=" * 80)

        over_provisioned_savings = 0
        for table_data in all_table_data:
            if table_data['analysis']['is_over_provisioned']:
                # Estimate 30-50% savings from right-sizing
                potential_savings = table_data['costs']['throughput'] * 0.4
                over_provisioned_savings += potential_savings
                print(f"  • {table_data['name']}: ${potential_savings:.2f}/month (right-sizing)")

        print(f"\nTotal Potential Savings: ${over_provisioned_savings:.2f}/month (${over_provisioned_savings * 12:.2f}/year)")
        print(f"Potential Cost Reduction: {(over_provisioned_savings / total_cost * 100):.1f}%")
        print()

        # Export detailed data
        output_file = f"dynamodb_cost_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump({
                'generated_at': datetime.now().isoformat(),
                'region': self.region,
                'total_tables': len(tables),
                'total_cost': total_cost,
                'tables': [{
                    'name': t['name'],
                    'billing_mode': t['details']['billing_mode'],
                    'size_gb': t['details']['size_bytes'] / (1024**3),
                    'item_count': t['details']['item_count'],
                    'costs': t['costs'],
                    'analysis': t['analysis'],
                    'tags': t['details']['tags']
                } for t in all_table_data],
                'optimization_opportunities': optimization_opportunities
            }, f, indent=2, default=str)

        print(f"Detailed analysis exported to: {output_file}")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Analyze DynamoDB costs and identify optimization opportunities'
    )
    parser.add_argument(
        '--region',
        default='us-east-1',
        help='AWS region (default: us-east-1)'
    )
    parser.add_argument(
        '--profile',
        help='AWS profile to use'
    )

    args = parser.parse_args()

    # Set AWS profile if specified
    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)

    try:
        analyzer = DynamoDBCostAnalyzer(region=args.region)
        analyzer.generate_report()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
