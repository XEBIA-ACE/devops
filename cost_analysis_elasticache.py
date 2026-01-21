#!/usr/bin/env python3
"""
ElastiCache Cost Analysis Tool

Analyzes ElastiCache usage patterns and costs to identify optimization opportunities.
Provides insights into cluster utilization, node sizing, and cost optimization.
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


class ElastiCacheCostAnalyzer:
    def __init__(self, region: str = 'us-east-1'):
        self.region = region
        self.elasticache = boto3.client('elasticache', region_name=region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)

        # ElastiCache pricing (approximate - varies by region and instance type)
        # Prices in USD per hour
        self.pricing_redis = {
            # Standard instances
            't4g.micro': 0.016,
            't4g.small': 0.032,
            't4g.medium': 0.064,
            't3.micro': 0.017,
            't3.small': 0.034,
            't3.medium': 0.068,
            # Memory optimized
            'r7g.large': 0.201,
            'r7g.xlarge': 0.403,
            'r7g.2xlarge': 0.806,
            'r6g.large': 0.182,
            'r6g.xlarge': 0.364,
            'r6g.2xlarge': 0.728,
            'r6i.large': 0.252,
            'r6i.xlarge': 0.504,
            'r6i.2xlarge': 1.008,
        }

        self.pricing_memcached = {
            't4g.micro': 0.016,
            't4g.small': 0.032,
            't4g.medium': 0.064,
            't3.micro': 0.017,
            't3.small': 0.034,
            't3.medium': 0.068,
            'r7g.large': 0.201,
            'r7g.xlarge': 0.403,
            'r7g.2xlarge': 0.806,
            'r6g.large': 0.182,
            'r6g.xlarge': 0.364,
            'r6g.2xlarge': 0.728,
        }

        # Reserved instance discounts
        self.reserved_discounts = {
            '1year_no_upfront': 0.33,     # 33% savings
            '1year_partial_upfront': 0.38, # 38% savings
            '1year_all_upfront': 0.42,     # 42% savings
            '3year_no_upfront': 0.48,      # 48% savings
            '3year_partial_upfront': 0.53, # 53% savings
            '3year_all_upfront': 0.55,     # 55% savings
        }

    def list_all_clusters(self) -> Dict[str, List[Dict]]:
        """List all ElastiCache clusters (Redis and Memcached)."""
        clusters = {'redis': [], 'memcached': []}

        # Redis clusters
        try:
            paginator = self.elasticache.get_paginator('describe_replication_groups')
            for page in paginator.paginate():
                clusters['redis'].extend(page['ReplicationGroups'])
        except Exception as e:
            print(f"Warning: Could not fetch Redis clusters: {e}")

        # Memcached clusters
        try:
            paginator = self.elasticache.get_paginator('describe_cache_clusters')
            for page in paginator.paginate():
                memcached = [c for c in page['CacheClusters']
                           if c['Engine'] == 'memcached']
                clusters['memcached'].extend(memcached)
        except Exception as e:
            print(f"Warning: Could not fetch Memcached clusters: {e}")

        return clusters

    def get_redis_cluster_details(self, cluster_id: str) -> Dict[str, Any]:
        """Get detailed information about a Redis replication group."""
        response = self.elasticache.describe_replication_groups(
            ReplicationGroupId=cluster_id
        )
        cluster = response['ReplicationGroups'][0]

        # Get node details
        node_groups = cluster.get('NodeGroups', [])
        total_nodes = sum(len(ng.get('NodeGroupMembers', [])) for ng in node_groups)

        # Get first node details for instance type
        cache_cluster_id = cluster['MemberClusters'][0] if cluster.get('MemberClusters') else None
        node_type = None
        if cache_cluster_id:
            node_response = self.elasticache.describe_cache_clusters(
                CacheClusterId=cache_cluster_id
            )
            if node_response['CacheClusters']:
                node_type = node_response['CacheClusters'][0]['CacheNodeType']

        # Get tags
        try:
            tags_response = self.elasticache.list_tags_for_resource(
                ResourceName=cluster['ARN']
            )
            tags = {tag['Key']: tag['Value'] for tag in tags_response.get('TagList', [])}
        except Exception as e:
            print(f"Warning: Could not fetch tags for {cluster_id}: {e}")
            tags = {}

        return {
            'cluster_id': cluster_id,
            'engine': 'redis',
            'engine_version': cluster.get('CacheNodeType', 'unknown'),
            'status': cluster['Status'],
            'node_type': node_type,
            'num_node_groups': len(node_groups),
            'total_nodes': total_nodes,
            'automatic_failover': cluster.get('AutomaticFailover', 'disabled'),
            'multi_az': cluster.get('MultiAZ', 'disabled'),
            'at_rest_encryption': cluster.get('AtRestEncryptionEnabled', False),
            'transit_encryption': cluster.get('TransitEncryptionEnabled', False),
            'snapshot_retention': cluster.get('SnapshotRetentionLimit', 0),
            'snapshot_window': cluster.get('SnapshotWindow', 'N/A'),
            'tags': tags,
            'arn': cluster['ARN']
        }

    def get_memcached_cluster_details(self, cluster_id: str) -> Dict[str, Any]:
        """Get detailed information about a Memcached cluster."""
        response = self.elasticache.describe_cache_clusters(
            CacheClusterId=cluster_id,
            ShowCacheNodeInfo=True
        )
        cluster = response['CacheClusters'][0]

        # Get tags
        try:
            tags_response = self.elasticache.list_tags_for_resource(
                ResourceName=cluster['ARN']
            )
            tags = {tag['Key']: tag['Value'] for tag in tags_response.get('TagList', [])}
        except Exception as e:
            print(f"Warning: Could not fetch tags for {cluster_id}: {e}")
            tags = {}

        return {
            'cluster_id': cluster_id,
            'engine': 'memcached',
            'engine_version': cluster.get('EngineVersion', 'unknown'),
            'status': cluster['CacheClusterStatus'],
            'node_type': cluster['CacheNodeType'],
            'num_nodes': cluster['NumCacheNodes'],
            'az_mode': cluster.get('PreferredAvailabilityZone', 'single-az'),
            'tags': tags,
            'arn': cluster['ARN']
        }

    def get_cluster_metrics(self, cluster_id: str, engine: str, days: int = 7) -> Dict[str, float]:
        """Get CloudWatch metrics for a cluster."""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)

        metrics = {}

        if engine == 'redis':
            metric_configs = [
                ('CPUUtilization', 'Average', 'Percent'),
                ('DatabaseMemoryUsagePercentage', 'Average', 'Percent'),
                ('NetworkBytesIn', 'Average', 'Bytes'),
                ('NetworkBytesOut', 'Average', 'Bytes'),
                ('CurrConnections', 'Average', 'Count'),
                ('Evictions', 'Sum', 'Count'),
                ('CacheHits', 'Sum', 'Count'),
                ('CacheMisses', 'Sum', 'Count'),
            ]
        else:  # memcached
            metric_configs = [
                ('CPUUtilization', 'Average', 'Percent'),
                ('BytesUsedForCacheItems', 'Average', 'Bytes'),
                ('NetworkBytesIn', 'Average', 'Bytes'),
                ('NetworkBytesOut', 'Average', 'Bytes'),
                ('CurrConnections', 'Average', 'Count'),
                ('Evictions', 'Sum', 'Count'),
                ('CacheHits', 'Sum', 'Count'),
                ('CacheMisses', 'Sum', 'Count'),
            ]

        for metric_name, stat, unit in metric_configs:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='AWS/ElastiCache',
                    MetricName=metric_name,
                    Dimensions=[
                        {'Name': 'CacheClusterId' if engine == 'memcached' else 'ReplicationGroupId',
                         'Value': cluster_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,  # 1 hour
                    Statistics=[stat],
                    Unit=unit
                )

                if response['Datapoints']:
                    values = [dp[stat] for dp in response['Datapoints']]
                    metrics[metric_name] = sum(values) / len(values) if stat == 'Average' else sum(values)
                else:
                    metrics[metric_name] = 0
            except Exception as e:
                print(f"Warning: Could not fetch {metric_name} for {cluster_id}: {e}")
                metrics[metric_name] = 0

        # Calculate cache hit rate
        total_requests = metrics.get('CacheHits', 0) + metrics.get('CacheMisses', 0)
        if total_requests > 0:
            metrics['CacheHitRate'] = (metrics.get('CacheHits', 0) / total_requests) * 100
        else:
            metrics['CacheHitRate'] = 0

        return metrics

    def estimate_cluster_cost(self, cluster_details: Dict[str, Any]) -> Dict[str, float]:
        """Estimate monthly cost for a cluster."""
        costs = {
            'compute': 0.0,
            'backup': 0.0,
            'data_transfer': 0.0,
            'total': 0.0,
            'reserved_1yr_savings': 0.0,
            'reserved_3yr_savings': 0.0
        }

        node_type = cluster_details['node_type']
        if not node_type:
            return costs

        # Extract base node type (remove cache. prefix)
        node_type_key = node_type.replace('cache.', '')

        # Get hourly rate
        if cluster_details['engine'] == 'redis':
            hourly_rate = self.pricing_redis.get(node_type_key, 0.1)  # Default to $0.10 if unknown
            num_nodes = cluster_details['total_nodes']
        else:
            hourly_rate = self.pricing_memcached.get(node_type_key, 0.1)
            num_nodes = cluster_details['num_nodes']

        hours_per_month = 730
        costs['compute'] = hourly_rate * num_nodes * hours_per_month

        # Backup costs (Redis only, approximate)
        if cluster_details['engine'] == 'redis' and cluster_details['snapshot_retention'] > 0:
            # Estimate backup size as 50% of node memory, $0.085 per GB-month
            # This is a rough estimate
            costs['backup'] = 5.0 * cluster_details['snapshot_retention']  # Simplified

        # Calculate reserved instance savings
        costs['reserved_1yr_savings'] = costs['compute'] * self.reserved_discounts['1year_all_upfront']
        costs['reserved_3yr_savings'] = costs['compute'] * self.reserved_discounts['3year_all_upfront']

        costs['total'] = costs['compute'] + costs['backup'] + costs['data_transfer']
        return costs

    def analyze_utilization(self, cluster_details: Dict[str, Any], metrics: Dict[str, float]) -> Dict[str, Any]:
        """Analyze cluster utilization and provide recommendations."""
        analysis = {
            'cpu_utilization': metrics.get('CPUUtilization', 0),
            'memory_utilization': metrics.get('DatabaseMemoryUsagePercentage',
                                             metrics.get('BytesUsedForCacheItems', 0)),
            'cache_hit_rate': metrics.get('CacheHitRate', 0),
            'evictions': metrics.get('Evictions', 0),
            'is_oversized': False,
            'is_undersized': False,
            'recommendations': []
        }

        engine = cluster_details['engine']

        # CPU Analysis
        if analysis['cpu_utilization'] < 20:
            analysis['is_oversized'] = True
            analysis['recommendations'].append(
                f"Low CPU utilization ({analysis['cpu_utilization']:.1f}%). "
                "Consider downsizing to a smaller node type."
            )
        elif analysis['cpu_utilization'] > 75:
            analysis['is_undersized'] = True
            analysis['recommendations'].append(
                f"High CPU utilization ({analysis['cpu_utilization']:.1f}%). "
                "Consider upgrading to a larger node type."
            )

        # Memory Analysis
        if engine == 'redis':
            mem_util = analysis['memory_utilization']
            if mem_util < 40:
                analysis['is_oversized'] = True
                analysis['recommendations'].append(
                    f"Low memory utilization ({mem_util:.1f}%). "
                    "Consider downsizing to reduce costs."
                )
            elif mem_util > 80:
                analysis['is_undersized'] = True
                analysis['recommendations'].append(
                    f"High memory utilization ({mem_util:.1f}%). "
                    "Risk of evictions. Consider upgrading node type or adding nodes."
                )

        # Cache Hit Rate Analysis
        if analysis['cache_hit_rate'] < 90:
            analysis['recommendations'].append(
                f"Low cache hit rate ({analysis['cache_hit_rate']:.1f}%). "
                "Review caching strategy and TTL settings."
            )

        # Evictions Analysis
        if analysis['evictions'] > 1000:
            analysis['recommendations'].append(
                f"High eviction count ({analysis['evictions']:.0f}). "
                "Memory pressure detected. Consider increasing cluster size."
            )

        # Graviton recommendation
        node_type = cluster_details['node_type']
        if node_type and not any(x in node_type for x in ['t4g', 'r7g', 'r6g']):
            analysis['recommendations'].append(
                "Consider migrating to Graviton-based instances (t4g, r6g, r7g) for 20% cost savings."
            )

        # Multi-AZ recommendation for Redis
        if engine == 'redis' and cluster_details['multi_az'] == 'disabled':
            analysis['recommendations'].append(
                "Consider enabling Multi-AZ for high availability in production."
            )

        # Reserved Instance recommendation
        if cluster_details['status'] == 'available':
            analysis['recommendations'].append(
                "Consider Reserved Instances for production workloads to save up to 55%."
            )

        # Tag compliance
        required_tags = ['Environment', 'Application', 'CostCenter', 'Owner']
        missing_tags = [tag for tag in required_tags if tag not in cluster_details['tags']]
        if missing_tags:
            analysis['recommendations'].append(f"Missing required tags: {', '.join(missing_tags)}")

        return analysis

    def generate_report(self) -> None:
        """Generate comprehensive cost analysis report."""
        print("=" * 80)
        print("ElastiCache Cost Analysis Report")
        print(f"Region: {self.region}")
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        print()

        clusters = self.list_all_clusters()
        total_clusters = len(clusters['redis']) + len(clusters['memcached'])

        print(f"Found {len(clusters['redis'])} Redis clusters and {len(clusters['memcached'])} Memcached clusters")
        print()

        if total_clusters == 0:
            print("No clusters found in this region.")
            return

        total_cost = 0.0
        all_cluster_data = []
        untagged_clusters = []
        optimization_opportunities = []

        # Analyze Redis clusters
        for cluster in clusters['redis']:
            cluster_id = cluster['ReplicationGroupId']
            print(f"Analyzing Redis: {cluster_id}...", end=' ')
            try:
                details = self.get_redis_cluster_details(cluster_id)
                metrics = self.get_cluster_metrics(cluster_id, 'redis')
                costs = self.estimate_cluster_cost(details)
                analysis = self.analyze_utilization(details, metrics)

                cluster_data = {
                    'details': details,
                    'metrics': metrics,
                    'costs': costs,
                    'analysis': analysis
                }
                all_cluster_data.append(cluster_data)
                total_cost += costs['total']

                # Check for untagged clusters
                required_tags = ['Environment', 'Application', 'CostCenter', 'Owner']
                if not all(tag in details['tags'] for tag in required_tags):
                    untagged_clusters.append(cluster_id)

                # Collect optimization opportunities
                if analysis['recommendations']:
                    optimization_opportunities.append({
                        'cluster': cluster_id,
                        'engine': 'redis',
                        'recommendations': analysis['recommendations']
                    })

                print("✓")
            except Exception as e:
                print(f"✗ Error: {e}")

        # Analyze Memcached clusters
        for cluster in clusters['memcached']:
            cluster_id = cluster['CacheClusterId']
            print(f"Analyzing Memcached: {cluster_id}...", end=' ')
            try:
                details = self.get_memcached_cluster_details(cluster_id)
                metrics = self.get_cluster_metrics(cluster_id, 'memcached')
                costs = self.estimate_cluster_cost(details)
                analysis = self.analyze_utilization(details, metrics)

                cluster_data = {
                    'details': details,
                    'metrics': metrics,
                    'costs': costs,
                    'analysis': analysis
                }
                all_cluster_data.append(cluster_data)
                total_cost += costs['total']

                # Check for untagged clusters
                required_tags = ['Environment', 'Application', 'CostCenter', 'Owner']
                if not all(tag in details['tags'] for tag in required_tags):
                    untagged_clusters.append(cluster_id)

                # Collect optimization opportunities
                if analysis['recommendations']:
                    optimization_opportunities.append({
                        'cluster': cluster_id,
                        'engine': 'memcached',
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
            for cluster_data in sorted(all_cluster_data, key=lambda x: x['costs']['total'], reverse=True):
                details = cluster_data['details']
                costs = cluster_data['costs']
                analysis = cluster_data['analysis']

                summary_data.append([
                    details['cluster_id'][:30],
                    details['engine'].upper(),
                    details['node_type'] if details['node_type'] else 'N/A',
                    details.get('total_nodes', details.get('num_nodes', 0)),
                    f"{analysis['cpu_utilization']:.1f}%",
                    f"{analysis['cache_hit_rate']:.1f}%",
                    f"${costs['total']:.2f}"
                ])

            print(tabulate(
                summary_data,
                headers=['Cluster ID', 'Engine', 'Node Type', 'Nodes', 'CPU', 'Hit Rate', 'Monthly Cost'],
                tablefmt='grid'
            ))
        else:
            for cluster_data in sorted(all_cluster_data, key=lambda x: x['costs']['total'], reverse=True):
                details = cluster_data['details']
                costs = cluster_data['costs']
                analysis = cluster_data['analysis']

                print(f"\nCluster: {details['cluster_id']}")
                print(f"  Engine: {details['engine'].upper()}")
                print(f"  Node Type: {details['node_type']}")
                print(f"  Nodes: {details.get('total_nodes', details.get('num_nodes', 0))}")
                print(f"  CPU Utilization: {analysis['cpu_utilization']:.1f}%")
                print(f"  Cache Hit Rate: {analysis['cache_hit_rate']:.1f}%")
                print(f"  Estimated Monthly Cost: ${costs['total']:.2f}")

        print()
        print(f"Total Estimated Monthly Cost: ${total_cost:.2f}")
        print()

        # Untagged resources
        if untagged_clusters:
            print("=" * 80)
            print("UNTAGGED CLUSTERS (HIGH PRIORITY)")
            print("=" * 80)
            for cluster_id in untagged_clusters:
                cluster_data = next(c for c in all_cluster_data if c['details']['cluster_id'] == cluster_id)
                missing_tags = [tag for tag in ['Environment', 'Application', 'CostCenter', 'Owner']
                              if tag not in cluster_data['details']['tags']]
                print(f"  • {cluster_id}")
                print(f"    Missing tags: {', '.join(missing_tags)}")
                print(f"    Current tags: {cluster_data['details']['tags']}")
            print()

        # Optimization opportunities
        if optimization_opportunities:
            print("=" * 80)
            print("OPTIMIZATION OPPORTUNITIES")
            print("=" * 80)
            for opp in optimization_opportunities:
                print(f"\n{opp['cluster']} ({opp['engine'].upper()}):")
                for rec in opp['recommendations']:
                    print(f"  • {rec}")
            print()

        # Savings potential
        print("=" * 80)
        print("ESTIMATED SAVINGS POTENTIAL")
        print("=" * 80)

        oversized_savings = 0
        reserved_savings = 0

        for cluster_data in all_cluster_data:
            if cluster_data['analysis']['is_oversized']:
                # Estimate 30-40% savings from right-sizing
                potential_savings = cluster_data['costs']['compute'] * 0.35
                oversized_savings += potential_savings
                print(f"  • {cluster_data['details']['cluster_id']}: ${potential_savings:.2f}/month (right-sizing)")

            # Reserved instance savings
            reserved_savings += cluster_data['costs']['reserved_1yr_savings']

        print(f"\nRight-Sizing Savings: ${oversized_savings:.2f}/month (${oversized_savings * 12:.2f}/year)")
        print(f"Reserved Instance Savings (1yr): ${reserved_savings:.2f}/month (${reserved_savings * 12:.2f}/year)")
        print(f"Total Potential Savings: ${oversized_savings + reserved_savings:.2f}/month")
        print(f"Potential Cost Reduction: {((oversized_savings + reserved_savings) / total_cost * 100):.1f}%")
        print()

        # Export detailed data
        output_file = f"elasticache_cost_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump({
                'generated_at': datetime.now().isoformat(),
                'region': self.region,
                'total_clusters': total_clusters,
                'total_cost': total_cost,
                'clusters': [{
                    'cluster_id': c['details']['cluster_id'],
                    'engine': c['details']['engine'],
                    'node_type': c['details']['node_type'],
                    'costs': c['costs'],
                    'analysis': c['analysis'],
                    'tags': c['details']['tags']
                } for c in all_cluster_data],
                'optimization_opportunities': optimization_opportunities
            }, f, indent=2, default=str)

        print(f"Detailed analysis exported to: {output_file}")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Analyze ElastiCache costs and identify optimization opportunities'
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
        analyzer = ElastiCacheCostAnalyzer(region=args.region)
        analyzer.generate_report()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
