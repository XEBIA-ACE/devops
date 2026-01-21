#!/usr/bin/env python3
"""
AWS Tag Enforcement Tool

Enforces tagging policies across AWS resources, with focus on DynamoDB and ElastiCache.
Supports automated tagging, compliance checking, and remediation.
"""

import boto3
import json
import re
from datetime import datetime
from typing import Dict, List, Any, Tuple
import sys

try:
    from tabulate import tabulate
except ImportError:
    print("Warning: 'tabulate' not installed. Install with: pip install tabulate")
    tabulate = None


class TagEnforcer:
    def __init__(self, region: str = 'us-east-1', policy_file: str = 'tagging_policy.json'):
        self.region = region
        self.dynamodb = boto3.client('dynamodb', region_name=region)
        self.elasticache = boto3.client('elasticache', region_name=region)
        self.resourcegroupstaggingapi = boto3.client('resourcegroupstaggingapi', region_name=region)

        # Load tagging policy
        with open(policy_file, 'r') as f:
            self.policy = json.load(f)

        self.mandatory_tags = list(self.policy['mandatory_tags'].keys())
        self.recommended_tags = list(self.policy['recommended_tags'].keys())

    def validate_tag_value(self, tag_key: str, tag_value: str) -> Tuple[bool, str]:
        """Validate a tag value against policy rules."""
        # Check if it's a mandatory or recommended tag
        tag_config = self.policy['mandatory_tags'].get(
            tag_key,
            self.policy['recommended_tags'].get(tag_key)
        )

        if not tag_config:
            # Not a defined tag, but still validate basic constraints
            if len(tag_value) > 256:
                return False, "Tag value exceeds maximum length of 256 characters"
            return True, "OK"

        # Check allowed values
        if 'allowed_values' in tag_config:
            allowed = tag_config['allowed_values']
            case_sensitive = tag_config.get('case_sensitive', False)

            if case_sensitive:
                if tag_value not in allowed:
                    return False, f"Value must be one of: {', '.join(allowed)}"
            else:
                if tag_value.lower() not in [v.lower() for v in allowed]:
                    return False, f"Value must be one of: {', '.join(allowed)}"

        # Check validation pattern
        if 'validation_pattern' in tag_config:
            pattern = tag_config['validation_pattern']
            if not re.match(pattern, tag_value):
                examples = tag_config.get('examples', [])
                examples_str = f" Examples: {', '.join(examples)}" if examples else ""
                return False, f"Value doesn't match required pattern.{examples_str}"

        # Check max length
        if 'max_length' in tag_config:
            if len(tag_value) > tag_config['max_length']:
                return False, f"Value exceeds maximum length of {tag_config['max_length']}"

        return True, "OK"

    def check_resource_compliance(self, resource_arn: str, tags: Dict[str, str]) -> Dict[str, Any]:
        """Check if a resource is compliant with tagging policy."""
        compliance = {
            'compliant': True,
            'missing_mandatory_tags': [],
            'missing_recommended_tags': [],
            'invalid_tag_values': [],
            'warnings': []
        }

        # Check mandatory tags
        for tag_key in self.mandatory_tags:
            if tag_key not in tags:
                compliance['missing_mandatory_tags'].append(tag_key)
                compliance['compliant'] = False
            else:
                # Validate tag value
                is_valid, message = self.validate_tag_value(tag_key, tags[tag_key])
                if not is_valid:
                    compliance['invalid_tag_values'].append({
                        'tag': tag_key,
                        'value': tags[tag_key],
                        'reason': message
                    })
                    compliance['compliant'] = False

        # Check recommended tags
        for tag_key in self.recommended_tags:
            if tag_key not in tags:
                compliance['missing_recommended_tags'].append(tag_key)
                compliance['warnings'].append(f"Missing recommended tag: {tag_key}")

        return compliance

    def get_all_dynamodb_resources(self) -> List[Dict[str, Any]]:
        """Get all DynamoDB tables and their tags."""
        resources = []
        paginator = self.dynamodb.get_paginator('list_tables')

        for page in paginator.paginate():
            for table_name in page['TableNames']:
                try:
                    # Get table details
                    table_response = self.dynamodb.describe_table(TableName=table_name)
                    table_arn = table_response['Table']['TableArn']

                    # Get tags
                    tags_response = self.dynamodb.list_tags_of_resource(ResourceArn=table_arn)
                    tags = {tag['Key']: tag['Value'] for tag in tags_response.get('Tags', [])}

                    resources.append({
                        'type': 'dynamodb',
                        'name': table_name,
                        'arn': table_arn,
                        'tags': tags
                    })
                except Exception as e:
                    print(f"Warning: Could not fetch tags for {table_name}: {e}")

        return resources

    def get_all_elasticache_resources(self) -> List[Dict[str, Any]]:
        """Get all ElastiCache clusters and their tags."""
        resources = []

        # Redis clusters
        try:
            paginator = self.elasticache.get_paginator('describe_replication_groups')
            for page in paginator.paginate():
                for cluster in page['ReplicationGroups']:
                    try:
                        cluster_id = cluster['ReplicationGroupId']
                        cluster_arn = cluster['ARN']

                        # Get tags
                        tags_response = self.elasticache.list_tags_for_resource(
                            ResourceName=cluster_arn
                        )
                        tags = {tag['Key']: tag['Value'] for tag in tags_response.get('TagList', [])}

                        resources.append({
                            'type': 'elasticache-redis',
                            'name': cluster_id,
                            'arn': cluster_arn,
                            'tags': tags
                        })
                    except Exception as e:
                        print(f"Warning: Could not fetch tags for Redis cluster: {e}")
        except Exception as e:
            print(f"Warning: Could not fetch Redis clusters: {e}")

        # Memcached clusters
        try:
            paginator = self.elasticache.get_paginator('describe_cache_clusters')
            for page in paginator.paginate():
                for cluster in page['CacheClusters']:
                    if cluster['Engine'] == 'memcached':
                        try:
                            cluster_id = cluster['CacheClusterId']
                            cluster_arn = cluster['ARN']

                            # Get tags
                            tags_response = self.elasticache.list_tags_for_resource(
                                ResourceName=cluster_arn
                            )
                            tags = {tag['Key']: tag['Value'] for tag in tags_response.get('TagList', [])}

                            resources.append({
                                'type': 'elasticache-memcached',
                                'name': cluster_id,
                                'arn': cluster_arn,
                                'tags': tags
                            })
                        except Exception as e:
                            print(f"Warning: Could not fetch tags for Memcached cluster: {e}")
        except Exception as e:
            print(f"Warning: Could not fetch Memcached clusters: {e}")

        return resources

    def apply_tags_to_resource(self, resource_arn: str, tags: Dict[str, str], dry_run: bool = True) -> bool:
        """Apply tags to a resource."""
        if dry_run:
            print(f"[DRY RUN] Would apply tags to {resource_arn}: {tags}")
            return True

        try:
            # Determine resource type from ARN
            if ':dynamodb:' in resource_arn:
                tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
                self.dynamodb.tag_resource(ResourceArn=resource_arn, Tags=tag_list)
                print(f"✓ Applied tags to DynamoDB table: {resource_arn}")
                return True
            elif ':elasticache:' in resource_arn:
                tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
                self.elasticache.add_tags_to_resource(ResourceName=resource_arn, Tags=tag_list)
                print(f"✓ Applied tags to ElastiCache cluster: {resource_arn}")
                return True
            else:
                print(f"✗ Unsupported resource type: {resource_arn}")
                return False
        except Exception as e:
            print(f"✗ Error applying tags to {resource_arn}: {e}")
            return False

    def generate_default_tags(self, resource: Dict[str, Any]) -> Dict[str, str]:
        """Generate default tags for a resource based on context."""
        default_tags = {}

        # Try to infer Environment from resource name
        name_lower = resource['name'].lower()
        if any(env in name_lower for env in ['prod', 'production']):
            default_tags['Environment'] = 'production'
        elif any(env in name_lower for env in ['stag', 'staging']):
            default_tags['Environment'] = 'staging'
        elif any(env in name_lower for env in ['dev', 'development']):
            default_tags['Environment'] = 'development'
        elif any(env in name_lower for env in ['test', 'testing']):
            default_tags['Environment'] = 'test'

        # Set default ManagedBy
        if 'ManagedBy' not in resource['tags']:
            default_tags['ManagedBy'] = 'manual'

        return default_tags

    def auto_remediate_resource(self, resource: Dict[str, Any], compliance: Dict[str, Any], dry_run: bool = True) -> None:
        """Automatically remediate non-compliant resources where possible."""
        tags_to_apply = {}

        # Generate default tags for missing mandatory tags
        if compliance['missing_mandatory_tags']:
            print(f"\nResource: {resource['name']}")
            print(f"Missing mandatory tags: {', '.join(compliance['missing_mandatory_tags'])}")

            default_tags = self.generate_default_tags(resource)

            for tag in compliance['missing_mandatory_tags']:
                if tag in default_tags:
                    tags_to_apply[tag] = default_tags[tag]
                    print(f"  Auto-generating {tag} = {default_tags[tag]}")
                else:
                    print(f"  Cannot auto-generate {tag} - manual intervention required")

        if tags_to_apply:
            self.apply_tags_to_resource(resource['arn'], tags_to_apply, dry_run)

    def generate_compliance_report(self, output_format: str = 'console') -> None:
        """Generate comprehensive compliance report."""
        print("=" * 80)
        print("Tag Compliance Report")
        print(f"Region: {self.region}")
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        print()

        # Gather all resources
        print("Gathering resources...")
        dynamodb_resources = self.get_all_dynamodb_resources()
        elasticache_resources = self.get_all_elasticache_resources()
        all_resources = dynamodb_resources + elasticache_resources

        print(f"Found {len(dynamodb_resources)} DynamoDB tables")
        print(f"Found {len(elasticache_resources)} ElastiCache clusters")
        print(f"Total: {len(all_resources)} resources")
        print()

        if not all_resources:
            print("No resources found.")
            return

        # Check compliance for each resource
        compliant_count = 0
        non_compliant_count = 0
        compliance_results = []

        for resource in all_resources:
            compliance = self.check_resource_compliance(resource['arn'], resource['tags'])
            compliance_results.append({
                'resource': resource,
                'compliance': compliance
            })

            if compliance['compliant']:
                compliant_count += 1
            else:
                non_compliant_count += 1

        # Summary
        print("=" * 80)
        print("COMPLIANCE SUMMARY")
        print("=" * 80)
        print(f"Compliant Resources: {compliant_count} ({compliant_count/len(all_resources)*100:.1f}%)")
        print(f"Non-Compliant Resources: {non_compliant_count} ({non_compliant_count/len(all_resources)*100:.1f}%)")
        print()

        # Non-compliant resources detail
        if non_compliant_count > 0:
            print("=" * 80)
            print("NON-COMPLIANT RESOURCES")
            print("=" * 80)

            if tabulate:
                table_data = []
                for result in compliance_results:
                    if not result['compliance']['compliant']:
                        resource = result['resource']
                        compliance = result['compliance']
                        issues = []
                        if compliance['missing_mandatory_tags']:
                            issues.append(f"Missing: {', '.join(compliance['missing_mandatory_tags'])}")
                        if compliance['invalid_tag_values']:
                            invalid = [f"{item['tag']}={item['value']}" for item in compliance['invalid_tag_values']]
                            issues.append(f"Invalid: {', '.join(invalid)}")

                        table_data.append([
                            resource['type'],
                            resource['name'][:40],
                            '\n'.join(issues)
                        ])

                print(tabulate(
                    table_data,
                    headers=['Type', 'Resource Name', 'Issues'],
                    tablefmt='grid'
                ))
            else:
                for result in compliance_results:
                    if not result['compliance']['compliant']:
                        resource = result['resource']
                        compliance = result['compliance']
                        print(f"\n{resource['type']}: {resource['name']}")
                        if compliance['missing_mandatory_tags']:
                            print(f"  Missing mandatory tags: {', '.join(compliance['missing_mandatory_tags'])}")
                        if compliance['invalid_tag_values']:
                            for item in compliance['invalid_tag_values']:
                                print(f"  Invalid tag: {item['tag']}={item['value']} ({item['reason']})")
                        print(f"  Current tags: {resource['tags']}")

            print()

        # Resources missing recommended tags
        missing_recommended = sum(
            1 for r in compliance_results
            if r['compliance']['missing_recommended_tags']
        )

        if missing_recommended > 0:
            print("=" * 80)
            print(f"RESOURCES MISSING RECOMMENDED TAGS: {missing_recommended}")
            print("=" * 80)
            for result in compliance_results[:10]:  # Show first 10
                if result['compliance']['missing_recommended_tags']:
                    resource = result['resource']
                    print(f"  • {resource['name']}: {', '.join(result['compliance']['missing_recommended_tags'])}")
            if missing_recommended > 10:
                print(f"  ... and {missing_recommended - 10} more")
            print()

        # Tag usage statistics
        print("=" * 80)
        print("TAG USAGE STATISTICS")
        print("=" * 80)

        tag_usage = {}
        for tag in self.mandatory_tags + self.recommended_tags:
            count = sum(1 for r in all_resources if tag in r['tags'])
            percentage = (count / len(all_resources)) * 100
            tag_usage[tag] = {'count': count, 'percentage': percentage}

        if tabulate:
            stats_data = []
            for tag in self.mandatory_tags:
                stats = tag_usage[tag]
                tag_type = "Mandatory"
                stats_data.append([tag, tag_type, stats['count'], f"{stats['percentage']:.1f}%"])
            for tag in self.recommended_tags:
                stats = tag_usage[tag]
                tag_type = "Recommended"
                stats_data.append([tag, tag_type, stats['count'], f"{stats['percentage']:.1f}%"])

            print(tabulate(
                stats_data,
                headers=['Tag Name', 'Type', 'Resources Tagged', 'Coverage'],
                tablefmt='grid'
            ))
        else:
            for tag in self.mandatory_tags:
                stats = tag_usage[tag]
                print(f"  {tag} (Mandatory): {stats['count']}/{len(all_resources)} ({stats['percentage']:.1f}%)")
            for tag in self.recommended_tags:
                stats = tag_usage[tag]
                print(f"  {tag} (Recommended): {stats['count']}/{len(all_resources)} ({stats['percentage']:.1f}%)")

        print()

        # Export detailed results
        output_file = f"tag_compliance_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump({
                'generated_at': datetime.now().isoformat(),
                'region': self.region,
                'total_resources': len(all_resources),
                'compliant_count': compliant_count,
                'non_compliant_count': non_compliant_count,
                'compliance_percentage': (compliant_count / len(all_resources)) * 100,
                'results': [{
                    'resource_type': r['resource']['type'],
                    'resource_name': r['resource']['name'],
                    'resource_arn': r['resource']['arn'],
                    'tags': r['resource']['tags'],
                    'compliant': r['compliance']['compliant'],
                    'missing_mandatory_tags': r['compliance']['missing_mandatory_tags'],
                    'missing_recommended_tags': r['compliance']['missing_recommended_tags'],
                    'invalid_tag_values': r['compliance']['invalid_tag_values']
                } for r in compliance_results]
            }, f, indent=2)

        print(f"Detailed report exported to: {output_file}")
        print()

    def bulk_tag_resources(self, dry_run: bool = True) -> None:
        """Bulk tag all non-compliant resources with auto-generated tags."""
        print("=" * 80)
        print("Bulk Tagging Operation")
        print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
        print("=" * 80)
        print()

        # Gather resources
        dynamodb_resources = self.get_all_dynamodb_resources()
        elasticache_resources = self.get_all_elasticache_resources()
        all_resources = dynamodb_resources + elasticache_resources

        remediated = 0
        failed = 0

        for resource in all_resources:
            compliance = self.check_resource_compliance(resource['arn'], resource['tags'])

            if not compliance['compliant'] and compliance['missing_mandatory_tags']:
                try:
                    self.auto_remediate_resource(resource, compliance, dry_run)
                    remediated += 1
                except Exception as e:
                    print(f"✗ Failed to remediate {resource['name']}: {e}")
                    failed += 1

        print()
        print("=" * 80)
        print("BULK TAGGING SUMMARY")
        print("=" * 80)
        print(f"Resources processed: {len(all_resources)}")
        print(f"Resources remediated: {remediated}")
        print(f"Failures: {failed}")
        print()

        if dry_run:
            print("This was a DRY RUN. Use --apply to make actual changes.")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Enforce AWS tagging policies and remediate non-compliant resources'
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
    parser.add_argument(
        '--policy-file',
        default='tagging_policy.json',
        help='Path to tagging policy file (default: tagging_policy.json)'
    )
    parser.add_argument(
        '--report',
        action='store_true',
        help='Generate compliance report'
    )
    parser.add_argument(
        '--bulk-tag',
        action='store_true',
        help='Bulk tag all non-compliant resources'
    )
    parser.add_argument(
        '--apply',
        action='store_true',
        help='Apply changes (default is dry-run)'
    )

    args = parser.parse_args()

    # Set AWS profile if specified
    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)

    try:
        enforcer = TagEnforcer(region=args.region, policy_file=args.policy_file)

        if args.report:
            enforcer.generate_compliance_report()
        elif args.bulk_tag:
            enforcer.bulk_tag_resources(dry_run=not args.apply)
        else:
            # Default: generate report
            enforcer.generate_compliance_report()

    except FileNotFoundError:
        print(f"Error: Policy file '{args.policy_file}' not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
