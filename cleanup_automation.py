#!/usr/bin/env python3
"""
AWS Resource Cleanup Automation

Identifies and cleans up unused or old resources to reduce costs.
Focus on DynamoDB backups and unused ElastiCache clusters.
"""

import boto3
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any
import sys

try:
    from tabulate import tabulate
except ImportError:
    print("Warning: 'tabulate' not installed. Install with: pip install tabulate")
    tabulate = None


class ResourceCleanup:
    def __init__(self, region: str = 'us-east-1'):
        self.region = region
        self.dynamodb = boto3.client('dynamodb', region_name=region)
        self.elasticache = boto3.client('elasticache', region_name=region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)

    def find_old_dynamodb_backups(self, days_old: int = 30) -> List[Dict[str, Any]]:
        """Find DynamoDB backups older than specified days."""
        old_backups = []
        cutoff_date = datetime.now() - timedelta(days=days_old)

        try:
            paginator = self.dynamodb.get_paginator('list_backups')
            for page in paginator.paginate():
                for backup in page['BackupSummaries']:
                    backup_date = backup['BackupCreationDateTime']
                    if backup_date < cutoff_date:
                        old_backups.append({
                            'backup_arn': backup['BackupArn'],
                            'table_name': backup['TableName'],
                            'creation_date': backup_date,
                            'status': backup['BackupStatus'],
                            'size_bytes': backup.get('BackupSizeBytes', 0),
                            'age_days': (datetime.now() - backup_date.replace(tzinfo=None)).days
                        })
        except Exception as e:
            print(f"Warning: Could not fetch backups: {e}")

        return sorted(old_backups, key=lambda x: x['creation_date'])

    def delete_dynamodb_backup(self, backup_arn: str, dry_run: bool = True) -> bool:
        """Delete a DynamoDB backup."""
        if dry_run:
            print(f"[DRY RUN] Would delete backup: {backup_arn}")
            return True

        try:
            self.dynamodb.delete_backup(BackupArn=backup_arn)
            print(f"✓ Deleted backup: {backup_arn}")
            return True
        except Exception as e:
            print(f"✗ Error deleting backup {backup_arn}: {e}")
            return False

    def find_unused_elasticache_clusters(self, days: int = 7) -> List[Dict[str, Any]]:
        """Find ElastiCache clusters with low or no usage."""
        unused_clusters = []
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)

        # Check Redis clusters
        try:
            paginator = self.elasticache.get_paginator('describe_replication_groups')
            for page in paginator.paginate():
                for cluster in page['ReplicationGroups']:
                    cluster_id = cluster['ReplicationGroupId']

                    # Get connection metrics
                    try:
                        response = self.cloudwatch.get_metric_statistics(
                            Namespace='AWS/ElastiCache',
                            MetricName='CurrConnections',
                            Dimensions=[{'Name': 'ReplicationGroupId', 'Value': cluster_id}],
                            StartTime=start_time,
                            EndTime=end_time,
                            Period=3600,
                            Statistics=['Average']
                        )

                        if response['Datapoints']:
                            avg_connections = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
                        else:
                            avg_connections = 0

                        # Consider unused if less than 1 connection on average
                        if avg_connections < 1:
                            unused_clusters.append({
                                'type': 'redis',
                                'cluster_id': cluster_id,
                                'status': cluster['Status'],
                                'avg_connections': avg_connections,
                                'node_type': 'N/A',  # Would need to query further
                                'arn': cluster['ARN']
                            })
                    except Exception as e:
                        print(f"Warning: Could not fetch metrics for {cluster_id}: {e}")
        except Exception as e:
            print(f"Warning: Could not fetch Redis clusters: {e}")

        # Check Memcached clusters
        try:
            paginator = self.elasticache.get_paginator('describe_cache_clusters')
            for page in paginator.paginate():
                for cluster in page['CacheClusters']:
                    if cluster['Engine'] == 'memcached':
                        cluster_id = cluster['CacheClusterId']

                        # Get connection metrics
                        try:
                            response = self.cloudwatch.get_metric_statistics(
                                Namespace='AWS/ElastiCache',
                                MetricName='CurrConnections',
                                Dimensions=[{'Name': 'CacheClusterId', 'Value': cluster_id}],
                                StartTime=start_time,
                                EndTime=end_time,
                                Period=3600,
                                Statistics=['Average']
                            )

                            if response['Datapoints']:
                                avg_connections = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
                            else:
                                avg_connections = 0

                            if avg_connections < 1:
                                unused_clusters.append({
                                    'type': 'memcached',
                                    'cluster_id': cluster_id,
                                    'status': cluster['CacheClusterStatus'],
                                    'avg_connections': avg_connections,
                                    'node_type': cluster['CacheNodeType'],
                                    'arn': cluster['ARN']
                                })
                        except Exception as e:
                            print(f"Warning: Could not fetch metrics for {cluster_id}: {e}")
        except Exception as e:
            print(f"Warning: Could not fetch Memcached clusters: {e}")

        return unused_clusters

    def find_low_activity_dynamodb_tables(self, days: int = 7) -> List[Dict[str, Any]]:
        """Find DynamoDB tables with low or no activity."""
        low_activity_tables = []
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)

        try:
            paginator = self.dynamodb.get_paginator('list_tables')
            for page in paginator.paginate():
                for table_name in page['TableNames']:
                    try:
                        # Get consumption metrics
                        read_response = self.cloudwatch.get_metric_statistics(
                            Namespace='AWS/DynamoDB',
                            MetricName='ConsumedReadCapacityUnits',
                            Dimensions=[{'Name': 'TableName', 'Value': table_name}],
                            StartTime=start_time,
                            EndTime=end_time,
                            Period=86400,  # Daily
                            Statistics=['Sum']
                        )

                        write_response = self.cloudwatch.get_metric_statistics(
                            Namespace='AWS/DynamoDB',
                            MetricName='ConsumedWriteCapacityUnits',
                            Dimensions=[{'Name': 'TableName', 'Value': table_name}],
                            StartTime=start_time,
                            EndTime=end_time,
                            Period=86400,
                            Statistics=['Sum']
                        )

                        total_reads = sum(dp['Sum'] for dp in read_response['Datapoints']) if read_response['Datapoints'] else 0
                        total_writes = sum(dp['Sum'] for dp in write_response['Datapoints']) if write_response['Datapoints'] else 0

                        # Consider low activity if less than 1000 operations per day
                        daily_operations = (total_reads + total_writes) / days

                        if daily_operations < 1000:
                            table_response = self.dynamodb.describe_table(TableName=table_name)
                            table = table_response['Table']

                            low_activity_tables.append({
                                'table_name': table_name,
                                'daily_operations': daily_operations,
                                'size_gb': table['TableSizeBytes'] / (1024**3),
                                'billing_mode': table.get('BillingModeSummary', {}).get('BillingMode', 'PROVISIONED'),
                                'status': table['TableStatus']
                            })
                    except Exception as e:
                        print(f"Warning: Could not analyze {table_name}: {e}")
        except Exception as e:
            print(f"Warning: Could not fetch DynamoDB tables: {e}")

        return sorted(low_activity_tables, key=lambda x: x['daily_operations'])

    def generate_cleanup_report(self, backup_age_days: int = 30, usage_days: int = 7) -> None:
        """Generate comprehensive cleanup recommendations report."""
        print("=" * 80)
        print("AWS Resource Cleanup Report")
        print(f"Region: {self.region}")
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        print()

        # Find old backups
        print(f"Scanning for DynamoDB backups older than {backup_age_days} days...")
        old_backups = self.find_old_dynamodb_backups(backup_age_days)
        print(f"Found {len(old_backups)} old backups")
        print()

        # Find unused clusters
        print(f"Scanning for unused ElastiCache clusters (last {usage_days} days)...")
        unused_clusters = self.find_unused_elasticache_clusters(usage_days)
        print(f"Found {len(unused_clusters)} potentially unused clusters")
        print()

        # Find low activity tables
        print(f"Scanning for low-activity DynamoDB tables (last {usage_days} days)...")
        low_activity_tables = self.find_low_activity_dynamodb_tables(usage_days)
        print(f"Found {len(low_activity_tables)} low-activity tables")
        print()

        # Old Backups Report
        if old_backups:
            print("=" * 80)
            print(f"OLD DYNAMODB BACKUPS (>{backup_age_days} days)")
            print("=" * 80)

            total_backup_size = sum(b['size_bytes'] for b in old_backups)
            estimated_cost = (total_backup_size / (1024**3)) * 0.10  # $0.10 per GB-month

            if tabulate:
                backup_data = []
                for backup in old_backups[:20]:  # Show first 20
                    backup_data.append([
                        backup['table_name'][:30],
                        backup['creation_date'].strftime('%Y-%m-%d'),
                        backup['age_days'],
                        f"{backup['size_bytes'] / (1024**3):.2f} GB",
                        backup['status']
                    ])

                print(tabulate(
                    backup_data,
                    headers=['Table Name', 'Created', 'Age (days)', 'Size', 'Status'],
                    tablefmt='grid'
                ))
            else:
                for backup in old_backups[:20]:
                    print(f"\n{backup['table_name']}")
                    print(f"  Created: {backup['creation_date'].strftime('%Y-%m-%d')}")
                    print(f"  Age: {backup['age_days']} days")
                    print(f"  Size: {backup['size_bytes'] / (1024**3):.2f} GB")

            if len(old_backups) > 20:
                print(f"\n... and {len(old_backups) - 20} more backups")

            print(f"\nTotal backup size: {total_backup_size / (1024**3):.2f} GB")
            print(f"Estimated monthly cost: ${estimated_cost:.2f}")
            print(f"Potential savings from cleanup: ${estimated_cost:.2f}/month")
            print()

        # Unused Clusters Report
        if unused_clusters:
            print("=" * 80)
            print("POTENTIALLY UNUSED ELASTICACHE CLUSTERS")
            print("=" * 80)

            if tabulate:
                cluster_data = []
                for cluster in unused_clusters:
                    cluster_data.append([
                        cluster['type'].upper(),
                        cluster['cluster_id'][:40],
                        cluster['status'],
                        f"{cluster['avg_connections']:.2f}",
                        'Review manually'
                    ])

                print(tabulate(
                    cluster_data,
                    headers=['Type', 'Cluster ID', 'Status', 'Avg Connections', 'Action'],
                    tablefmt='grid'
                ))
            else:
                for cluster in unused_clusters:
                    print(f"\n{cluster['type'].upper()}: {cluster['cluster_id']}")
                    print(f"  Status: {cluster['status']}")
                    print(f"  Average Connections: {cluster['avg_connections']:.2f}")

            print(f"\nNote: Verify these clusters are truly unused before deletion.")
            print(f"Low connection count may indicate standby or backup clusters.")
            print()

        # Low Activity Tables Report
        if low_activity_tables:
            print("=" * 80)
            print("LOW-ACTIVITY DYNAMODB TABLES")
            print("=" * 80)

            if tabulate:
                table_data = []
                for table in low_activity_tables[:20]:
                    table_data.append([
                        table['table_name'][:40],
                        f"{table['daily_operations']:.0f}",
                        f"{table['size_gb']:.2f} GB",
                        table['billing_mode'],
                        'Consider archival or deletion'
                    ])

                print(tabulate(
                    table_data,
                    headers=['Table Name', 'Daily Ops', 'Size', 'Billing Mode', 'Recommendation'],
                    tablefmt='grid'
                ))
            else:
                for table in low_activity_tables[:20]:
                    print(f"\n{table['table_name']}")
                    print(f"  Daily Operations: {table['daily_operations']:.0f}")
                    print(f"  Size: {table['size_gb']:.2f} GB")
                    print(f"  Billing Mode: {table['billing_mode']}")

            if len(low_activity_tables) > 20:
                print(f"\n... and {len(low_activity_tables) - 20} more tables")

            print(f"\nReview these tables for potential archival or deletion.")
            print()

        # Summary
        print("=" * 80)
        print("CLEANUP SUMMARY")
        print("=" * 80)
        print(f"Old backups to review: {len(old_backups)}")
        print(f"Unused clusters to review: {len(unused_clusters)}")
        print(f"Low-activity tables to review: {len(low_activity_tables)}")
        print()

        # Calculate potential savings
        backup_savings = (sum(b['size_bytes'] for b in old_backups) / (1024**3)) * 0.10
        print(f"Estimated monthly savings from backup cleanup: ${backup_savings:.2f}")
        print()

        # Export data
        output_file = f"cleanup_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump({
                'generated_at': datetime.now().isoformat(),
                'region': self.region,
                'old_backups': [{
                    'table_name': b['table_name'],
                    'backup_arn': b['backup_arn'],
                    'age_days': b['age_days'],
                    'size_gb': b['size_bytes'] / (1024**3)
                } for b in old_backups],
                'unused_clusters': unused_clusters,
                'low_activity_tables': low_activity_tables,
                'estimated_monthly_savings': backup_savings
            }, f, indent=2, default=str)

        print(f"Detailed report exported to: {output_file}")
        print()

    def cleanup_old_backups(self, backup_age_days: int = 30, dry_run: bool = True) -> None:
        """Clean up old DynamoDB backups."""
        print("=" * 80)
        print("DynamoDB Backup Cleanup")
        print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
        print(f"Deleting backups older than {backup_age_days} days")
        print("=" * 80)
        print()

        old_backups = self.find_old_dynamodb_backups(backup_age_days)

        if not old_backups:
            print("No old backups found.")
            return

        print(f"Found {len(old_backups)} backups to delete")
        print()

        success_count = 0
        failed_count = 0

        for backup in old_backups:
            print(f"Processing: {backup['table_name']} ({backup['age_days']} days old)...", end=' ')
            if self.delete_dynamodb_backup(backup['backup_arn'], dry_run):
                success_count += 1
            else:
                failed_count += 1

        print()
        print("=" * 80)
        print("CLEANUP SUMMARY")
        print("=" * 80)
        print(f"Successfully deleted: {success_count}")
        print(f"Failed: {failed_count}")
        print()

        if dry_run:
            print("This was a DRY RUN. Use --apply to make actual deletions.")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Identify and clean up unused AWS resources'
    )
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--profile', help='AWS profile to use')
    parser.add_argument('--report', action='store_true', help='Generate cleanup report')
    parser.add_argument('--cleanup-backups', action='store_true', help='Clean up old DynamoDB backups')
    parser.add_argument('--backup-age-days', type=int, default=30, help='Backup age threshold in days')
    parser.add_argument('--usage-days', type=int, default=7, help='Days to analyze for usage patterns')
    parser.add_argument('--apply', action='store_true', help='Apply changes (default is dry-run)')

    args = parser.parse_args()

    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)

    try:
        cleanup = ResourceCleanup(region=args.region)

        if args.cleanup_backups:
            cleanup.cleanup_old_backups(args.backup_age_days, dry_run=not args.apply)
        else:
            # Default: generate report
            cleanup.generate_cleanup_report(args.backup_age_days, args.usage_days)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
