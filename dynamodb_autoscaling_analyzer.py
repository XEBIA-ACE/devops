#!/usr/bin/env python3
"""
DynamoDB Auto-Scaling Analyzer

Analyzes DynamoDB tables to determine optimal auto-scaling configuration
and capacity mode (On-Demand vs Provisioned with Auto-Scaling).
"""

import boto3
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any, Tuple
import sys

try:
    from tabulate import tabulate
except ImportError:
    print("Warning: 'tabulate' not installed. Install with: pip install tabulate")
    tabulate = None


class DynamoDBAutoScalingAnalyzer:
    def __init__(self, region: str = 'us-east-1'):
        self.region = region
        self.dynamodb = boto3.client('dynamodb', region_name=region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.app_autoscaling = boto3.client('application-autoscaling', region_name=region)

        # Auto-scaling thresholds and recommendations
        self.target_utilization = 70  # Target 70% utilization
        self.min_capacity_default = 5
        self.max_capacity_multiplier = 10  # Max = Min * 10

        # Pricing (approximate)
        self.pricing = {
            'provisioned_rcu_hour': 0.00013,
            'provisioned_wcu_hour': 0.00065,
            'on_demand_rru': 0.00000025,
            'on_demand_wru': 0.00000125
        }

    def list_all_tables(self) -> List[str]:
        """List all DynamoDB tables."""
        tables = []
        paginator = self.dynamodb.get_paginator('list_tables')
        for page in paginator.paginate():
            tables.extend(page['TableNames'])
        return tables

    def get_table_details(self, table_name: str) -> Dict[str, Any]:
        """Get table configuration including billing mode and capacity."""
        response = self.dynamodb.describe_table(TableName=table_name)
        table = response['Table']

        return {
            'name': table_name,
            'billing_mode': table.get('BillingModeSummary', {}).get('BillingMode', 'PROVISIONED'),
            'read_capacity': table.get('ProvisionedThroughput', {}).get('ReadCapacityUnits', 0),
            'write_capacity': table.get('ProvisionedThroughput', {}).get('WriteCapacityUnits', 0),
            'gsi_count': len(table.get('GlobalSecondaryIndexes', [])),
            'gsis': table.get('GlobalSecondaryIndexes', []),
            'table_arn': table['TableArn']
        }

    def check_autoscaling_config(self, table_name: str) -> Dict[str, Any]:
        """Check if auto-scaling is configured for a table."""
        autoscaling_config = {
            'table_read_enabled': False,
            'table_write_enabled': False,
            'gsi_configs': {}
        }

        resource_ids = [
            f"table/{table_name}",  # Table read/write
        ]

        # Get table details to find GSI names
        table_details = self.get_table_details(table_name)
        for gsi in table_details['gsis']:
            gsi_name = gsi['IndexName']
            resource_ids.append(f"table/{table_name}/index/{gsi_name}")

        for resource_id in resource_ids:
            try:
                # Check read capacity auto-scaling
                read_targets = self.app_autoscaling.describe_scalable_targets(
                    ServiceNamespace='dynamodb',
                    ResourceIds=[resource_id],
                    ScalableDimension='dynamodb:table:ReadCapacityUnits' if 'index' not in resource_id
                                     else 'dynamodb:index:ReadCapacityUnits'
                )

                if read_targets['ScalableTargets']:
                    target = read_targets['ScalableTargets'][0]
                    if resource_id == f"table/{table_name}":
                        autoscaling_config['table_read_enabled'] = True
                        autoscaling_config['table_read_config'] = {
                            'min': target['MinCapacity'],
                            'max': target['MaxCapacity']
                        }
                    else:
                        gsi_name = resource_id.split('/')[-1]
                        if gsi_name not in autoscaling_config['gsi_configs']:
                            autoscaling_config['gsi_configs'][gsi_name] = {}
                        autoscaling_config['gsi_configs'][gsi_name]['read_enabled'] = True
                        autoscaling_config['gsi_configs'][gsi_name]['read_config'] = {
                            'min': target['MinCapacity'],
                            'max': target['MaxCapacity']
                        }

                # Check write capacity auto-scaling
                write_targets = self.app_autoscaling.describe_scalable_targets(
                    ServiceNamespace='dynamodb',
                    ResourceIds=[resource_id],
                    ScalableDimension='dynamodb:table:WriteCapacityUnits' if 'index' not in resource_id
                                     else 'dynamodb:index:WriteCapacityUnits'
                )

                if write_targets['ScalableTargets']:
                    target = write_targets['ScalableTargets'][0]
                    if resource_id == f"table/{table_name}":
                        autoscaling_config['table_write_enabled'] = True
                        autoscaling_config['table_write_config'] = {
                            'min': target['MinCapacity'],
                            'max': target['MaxCapacity']
                        }
                    else:
                        gsi_name = resource_id.split('/')[-1]
                        if gsi_name not in autoscaling_config['gsi_configs']:
                            autoscaling_config['gsi_configs'][gsi_name] = {}
                        autoscaling_config['gsi_configs'][gsi_name]['write_enabled'] = True
                        autoscaling_config['gsi_configs'][gsi_name]['write_config'] = {
                            'min': target['MinCapacity'],
                            'max': target['MaxCapacity']
                        }

            except Exception as e:
                # Auto-scaling not configured for this dimension
                pass

        return autoscaling_config

    def get_usage_metrics(self, table_name: str, days: int = 14) -> Dict[str, Any]:
        """Get usage metrics for a table over the specified period."""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)

        metrics = {}
        metric_queries = [
            ('ConsumedReadCapacityUnits', 'Sum'),
            ('ConsumedWriteCapacityUnits', 'Sum'),
            ('ProvisionedReadCapacityUnits', 'Average'),
            ('ProvisionedWriteCapacityUnits', 'Average'),
            ('ReadThrottleEvents', 'Sum'),
            ('WriteThrottleEvents', 'Sum'),
        ]

        for metric_name, stat in metric_queries:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='AWS/DynamoDB',
                    MetricName=metric_name,
                    Dimensions=[{'Name': 'TableName', 'Value': table_name}],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,  # 1 hour
                    Statistics=[stat]
                )

                if response['Datapoints']:
                    datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
                    values = [dp[stat] for dp in datapoints]

                    metrics[metric_name] = {
                        'values': values,
                        'mean': sum(values) / len(values),
                        'max': max(values),
                        'min': min(values),
                        'p95': sorted(values)[int(len(values) * 0.95)] if len(values) > 0 else 0
                    }
                else:
                    metrics[metric_name] = {
                        'values': [],
                        'mean': 0,
                        'max': 0,
                        'min': 0,
                        'p95': 0
                    }
            except Exception as e:
                print(f"Warning: Could not fetch {metric_name} for {table_name}: {e}")
                metrics[metric_name] = {'values': [], 'mean': 0, 'max': 0, 'min': 0, 'p95': 0}

        return metrics

    def analyze_workload_pattern(self, metrics: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze workload pattern to determine best capacity mode."""
        read_values = metrics.get('ConsumedReadCapacityUnits', {}).get('values', [0])
        write_values = metrics.get('ConsumedWriteCapacityUnits', {}).get('values', [0])

        if not read_values or not write_values:
            return {
                'pattern': 'unknown',
                'variability': 0,
                'recommendation': 'on-demand'
            }

        # Calculate coefficient of variation (CV)
        def calculate_cv(values):
            if not values or len(values) < 2:
                return 0
            mean = sum(values) / len(values)
            if mean == 0:
                return 0
            variance = sum((x - mean) ** 2 for x in values) / len(values)
            std_dev = variance ** 0.5
            return (std_dev / mean) * 100

        read_cv = calculate_cv(read_values)
        write_cv = calculate_cv(write_values)
        avg_cv = (read_cv + write_cv) / 2

        # Determine pattern
        if avg_cv < 20:
            pattern = 'steady'
            recommendation = 'provisioned-autoscaling'
        elif avg_cv < 50:
            pattern = 'moderate'
            recommendation = 'provisioned-autoscaling'
        else:
            pattern = 'unpredictable'
            recommendation = 'on-demand'

        # Check for traffic spikes
        read_mean = metrics['ConsumedReadCapacityUnits']['mean']
        read_max = metrics['ConsumedReadCapacityUnits']['max']
        write_mean = metrics['ConsumedWriteCapacityUnits']['mean']
        write_max = metrics['ConsumedWriteCapacityUnits']['max']

        spike_factor = max(
            read_max / read_mean if read_mean > 0 else 0,
            write_max / write_mean if write_mean > 0 else 0
        )

        if spike_factor > 5:
            pattern = 'spiky'
            recommendation = 'on-demand'

        return {
            'pattern': pattern,
            'variability': avg_cv,
            'read_cv': read_cv,
            'write_cv': write_cv,
            'spike_factor': spike_factor,
            'recommendation': recommendation
        }

    def calculate_optimal_capacity(self, metrics: Dict[str, Any]) -> Dict[str, int]:
        """Calculate optimal min/max capacity for auto-scaling."""
        # Use P95 for sizing to handle most traffic without over-provisioning
        read_p95 = metrics['ConsumedReadCapacityUnits']['p95']
        write_p95 = metrics['ConsumedWriteCapacityUnits']['p95']

        # Convert from per-hour to per-second
        read_per_second = read_p95 / 3600 if read_p95 > 0 else 5
        write_per_second = write_p95 / 3600 if write_p95 > 0 else 5

        # Calculate capacity based on target utilization
        read_min = max(5, int(read_per_second / (self.target_utilization / 100)))
        write_min = max(5, int(write_per_second / (self.target_utilization / 100)))

        # Max capacity should handle spikes
        read_max = max(read_min * 3, 10)
        write_max = max(write_min * 3, 10)

        return {
            'read_min': read_min,
            'read_max': read_max,
            'write_min': write_min,
            'write_max': write_max
        }

    def estimate_cost_comparison(self, table_details: Dict[str, Any], metrics: Dict[str, Any]) -> Dict[str, float]:
        """Compare costs between On-Demand and Provisioned with Auto-Scaling."""
        hours_per_month = 730

        # Current cost (if provisioned)
        if table_details['billing_mode'] == 'PROVISIONED':
            current_monthly = (
                table_details['read_capacity'] * self.pricing['provisioned_rcu_hour'] * hours_per_month +
                table_details['write_capacity'] * self.pricing['provisioned_wcu_hour'] * hours_per_month
            )
        else:
            # Estimate from actual consumption
            monthly_reads = metrics['ConsumedReadCapacityUnits']['mean'] * 30 / 14  # Scale to monthly
            monthly_writes = metrics['ConsumedWriteCapacityUnits']['mean'] * 30 / 14
            current_monthly = (
                monthly_reads * self.pricing['on_demand_rru'] +
                monthly_writes * self.pricing['on_demand_wru']
            )

        # On-Demand cost
        monthly_reads = metrics['ConsumedReadCapacityUnits']['mean'] * 30 / 14
        monthly_writes = metrics['ConsumedWriteCapacityUnits']['mean'] * 30 / 14
        on_demand_monthly = (
            monthly_reads * self.pricing['on_demand_rru'] +
            monthly_writes * self.pricing['on_demand_wru']
        )

        # Provisioned with auto-scaling cost
        optimal_capacity = self.calculate_optimal_capacity(metrics)
        provisioned_monthly = (
            optimal_capacity['read_min'] * self.pricing['provisioned_rcu_hour'] * hours_per_month +
            optimal_capacity['write_min'] * self.pricing['provisioned_wcu_hour'] * hours_per_month
        )

        return {
            'current': current_monthly,
            'on_demand': on_demand_monthly,
            'provisioned_autoscaling': provisioned_monthly
        }

    def generate_report(self) -> None:
        """Generate comprehensive auto-scaling analysis report."""
        print("=" * 80)
        print("DynamoDB Auto-Scaling Analysis Report")
        print(f"Region: {self.region}")
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        print()

        tables = self.list_all_tables()
        print(f"Found {len(tables)} DynamoDB tables")
        print()

        if not tables:
            print("No tables found.")
            return

        all_analysis = []

        for table_name in tables:
            print(f"Analyzing: {table_name}...", end=' ')
            try:
                details = self.get_table_details(table_name)
                autoscaling = self.check_autoscaling_config(table_name)
                metrics = self.get_usage_metrics(table_name)
                pattern = self.analyze_workload_pattern(metrics)
                capacity = self.calculate_optimal_capacity(metrics)
                costs = self.estimate_cost_comparison(details, metrics)

                analysis = {
                    'table_name': table_name,
                    'details': details,
                    'autoscaling': autoscaling,
                    'metrics': metrics,
                    'pattern': pattern,
                    'recommended_capacity': capacity,
                    'cost_comparison': costs
                }
                all_analysis.append(analysis)
                print("✓")
            except Exception as e:
                print(f"✗ Error: {e}")

        print()

        # Summary table
        print("=" * 80)
        print("AUTO-SCALING CONFIGURATION SUMMARY")
        print("=" * 80)

        if tabulate:
            summary_data = []
            for analysis in all_analysis:
                details = analysis['details']
                autoscaling = analysis['autoscaling']
                pattern = analysis['pattern']

                current_mode = details['billing_mode']
                has_autoscaling = autoscaling['table_read_enabled'] and autoscaling['table_write_enabled']

                summary_data.append([
                    analysis['table_name'][:30],
                    current_mode,
                    'Yes' if has_autoscaling else 'No',
                    pattern['pattern'],
                    f"{pattern['variability']:.1f}%",
                    pattern['recommendation']
                ])

            print(tabulate(
                summary_data,
                headers=['Table Name', 'Current Mode', 'Auto-Scaling', 'Pattern', 'Variability', 'Recommended'],
                tablefmt='grid'
            ))
        else:
            for analysis in all_analysis:
                details = analysis['details']
                autoscaling = analysis['autoscaling']
                pattern = analysis['pattern']

                print(f"\n{analysis['table_name']}")
                print(f"  Current Mode: {details['billing_mode']}")
                print(f"  Auto-Scaling: {'Yes' if autoscaling['table_read_enabled'] else 'No'}")
                print(f"  Pattern: {pattern['pattern']} (Variability: {pattern['variability']:.1f}%)")
                print(f"  Recommended: {pattern['recommendation']}")

        print()

        # Detailed recommendations
        print("=" * 80)
        print("DETAILED RECOMMENDATIONS")
        print("=" * 80)

        total_potential_savings = 0

        for analysis in all_analysis:
            table_name = analysis['table_name']
            details = analysis['details']
            pattern = analysis['pattern']
            capacity = analysis['recommended_capacity']
            costs = analysis['cost_comparison']

            print(f"\n{table_name}:")
            print(f"  Current Mode: {details['billing_mode']}")
            print(f"  Workload Pattern: {pattern['pattern']} (CV: {pattern['variability']:.1f}%)")

            if pattern['recommendation'] == 'on-demand':
                print(f"  ✓ RECOMMENDATION: Switch to On-Demand mode")
                print(f"    Reason: {pattern['pattern']} workload with {pattern['variability']:.1f}% variability")
                print(f"    Current Cost: ${costs['current']:.2f}/month")
                print(f"    On-Demand Cost: ${costs['on_demand']:.2f}/month")
                savings = costs['current'] - costs['on_demand']
                if savings > 0:
                    print(f"    Potential Savings: ${savings:.2f}/month (${savings * 12:.2f}/year)")
                    total_potential_savings += savings
            else:
                print(f"  ✓ RECOMMENDATION: Use Provisioned mode with Auto-Scaling")
                print(f"    Reason: {pattern['pattern']} workload suitable for auto-scaling")
                print(f"    Recommended Capacity:")
                print(f"      Read: Min={capacity['read_min']}, Max={capacity['read_max']}")
                print(f"      Write: Min={capacity['write_min']}, Max={capacity['write_max']}")
                print(f"    Target Utilization: {self.target_utilization}%")
                print(f"    Current Cost: ${costs['current']:.2f}/month")
                print(f"    Optimized Cost: ${costs['provisioned_autoscaling']:.2f}/month")
                savings = costs['current'] - costs['provisioned_autoscaling']
                if savings > 0:
                    print(f"    Potential Savings: ${savings:.2f}/month (${savings * 12:.2f}/year)")
                    total_potential_savings += savings

        print()
        print("=" * 80)
        print("TOTAL POTENTIAL SAVINGS")
        print("=" * 80)
        print(f"Monthly: ${total_potential_savings:.2f}")
        print(f"Annual: ${total_potential_savings * 12:.2f}")
        print()

        # Export configuration scripts
        output_file = f"dynamodb_autoscaling_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump({
                'generated_at': datetime.now().isoformat(),
                'region': self.region,
                'total_tables': len(tables),
                'total_potential_savings_monthly': total_potential_savings,
                'total_potential_savings_annual': total_potential_savings * 12,
                'analysis': [{
                    'table_name': a['table_name'],
                    'current_mode': a['details']['billing_mode'],
                    'pattern': a['pattern'],
                    'recommended_capacity': a['recommended_capacity'],
                    'cost_comparison': a['cost_comparison']
                } for a in all_analysis]
            }, f, indent=2, default=str)

        print(f"Detailed analysis exported to: {output_file}")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Analyze DynamoDB tables for auto-scaling optimization'
    )
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--profile', help='AWS profile to use')

    args = parser.parse_args()

    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)

    try:
        analyzer = DynamoDBAutoScalingAnalyzer(region=args.region)
        analyzer.generate_report()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
