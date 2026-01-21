#!/usr/bin/env python3
"""
Comprehensive AWS Cost Report Generator

Generates a complete cost optimization report combining all analysis tools.
Provides executive summary with actionable recommendations.
"""

import boto3
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any
import subprocess
import sys
import os

try:
    from tabulate import tabulate
except ImportError:
    print("Warning: 'tabulate' not installed. Install with: pip install tabulate")
    tabulate = None


class ComprehensiveCostReport:
    def __init__(self, region: str = 'us-east-1'):
        self.region = region
        self.ce = boto3.client('ce', region_name='us-east-1')  # Cost Explorer
        self.organizations = None
        try:
            self.organizations = boto3.client('organizations')
        except:
            pass

    def get_current_month_costs(self) -> Dict[str, float]:
        """Get current month-to-date costs."""
        today = datetime.now()
        start_of_month = today.replace(day=1).strftime('%Y-%m-%d')
        today_str = today.strftime('%Y-%m-%d')

        try:
            response = self.ce.get_cost_and_usage(
                TimePeriod={
                    'Start': start_of_month,
                    'End': today_str
                },
                Granularity='MONTHLY',
                Metrics=['UnblendedCost'],
                GroupBy=[
                    {'Type': 'DIMENSION', 'Key': 'SERVICE'}
                ]
            )

            costs = {}
            if response['ResultsByTime']:
                for group in response['ResultsByTime'][0]['Groups']:
                    service = group['Keys'][0]
                    amount = float(group['Metrics']['UnblendedCost']['Amount'])
                    costs[service] = amount

            return costs
        except Exception as e:
            print(f"Warning: Could not fetch cost data: {e}")
            return {}

    def get_last_month_costs(self) -> Dict[str, float]:
        """Get last month's total costs."""
        today = datetime.now()
        first_of_this_month = today.replace(day=1)
        last_month_end = first_of_this_month - timedelta(days=1)
        last_month_start = last_month_end.replace(day=1)

        try:
            response = self.ce.get_cost_and_usage(
                TimePeriod={
                    'Start': last_month_start.strftime('%Y-%m-%d'),
                    'End': first_of_this_month.strftime('%Y-%m-%d')
                },
                Granularity='MONTHLY',
                Metrics=['UnblendedCost'],
                GroupBy=[
                    {'Type': 'DIMENSION', 'Key': 'SERVICE'}
                ]
            )

            costs = {}
            if response['ResultsByTime']:
                for group in response['ResultsByTime'][0]['Groups']:
                    service = group['Keys'][0]
                    amount = float(group['Metrics']['UnblendedCost']['Amount'])
                    costs[service] = amount

            return costs
        except Exception as e:
            print(f"Warning: Could not fetch last month costs: {e}")
            return {}

    def run_analysis_script(self, script_name: str) -> Dict[str, Any]:
        """Run an analysis script and return results."""
        try:
            result = subprocess.run(
                ['python', script_name, '--region', self.region],
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )

            # Try to find and parse JSON output
            output_files = [f for f in os.listdir('.') if f.startswith(script_name.replace('.py', '')) and f.endswith('.json')]
            if output_files:
                # Get most recent file
                latest_file = max(output_files, key=os.path.getctime)
                with open(latest_file, 'r') as f:
                    return json.load(f)

            return {'status': 'completed', 'output': result.stdout}
        except subprocess.TimeoutExpired:
            return {'status': 'timeout', 'error': 'Script execution timed out'}
        except Exception as e:
            return {'status': 'error', 'error': str(e)}

    def generate_executive_summary(self) -> Dict[str, Any]:
        """Generate executive summary of cost optimization opportunities."""
        print("Generating comprehensive cost report...")
        print("This may take several minutes...")
        print()

        summary = {
            'generated_at': datetime.now().isoformat(),
            'region': self.region,
            'current_month_costs': {},
            'last_month_costs': {},
            'optimization_opportunities': [],
            'total_potential_savings': 0.0,
            'recommendations': []
        }

        # Get cost data
        print("Fetching cost data from AWS Cost Explorer...")
        summary['current_month_costs'] = self.get_current_month_costs()
        summary['last_month_costs'] = self.get_last_month_costs()

        current_total = sum(summary['current_month_costs'].values())
        last_month_total = sum(summary['last_month_costs'].values())

        print(f"Current month-to-date spend: ${current_total:.2f}")
        print(f"Last month total spend: ${last_month_total:.2f}")
        print()

        # Calculate top services
        top_services = sorted(
            summary['current_month_costs'].items(),
            key=lambda x: x[1],
            reverse=True
        )[:5]

        summary['top_5_services'] = [
            {'service': svc, 'cost': cost}
            for svc, cost in top_services
        ]

        # Estimate based on typical savings percentages
        dynamodb_cost = summary['current_month_costs'].get('Amazon DynamoDB', 0)
        elasticache_cost = summary['current_month_costs'].get('Amazon ElastiCache', 0)

        # DynamoDB savings: 20-40% with auto-scaling
        dynamodb_savings_low = dynamodb_cost * 0.20
        dynamodb_savings_high = dynamodb_cost * 0.40

        # ElastiCache savings: 15-30% with right-sizing
        elasticache_savings_low = elasticache_cost * 0.15
        elasticache_savings_high = elasticache_cost * 0.30

        summary['optimization_opportunities'].append({
            'service': 'Amazon DynamoDB',
            'current_monthly_cost': dynamodb_cost,
            'potential_savings_low': dynamodb_savings_low,
            'potential_savings_high': dynamodb_savings_high,
            'optimization': 'Auto-scaling and capacity mode optimization'
        })

        summary['optimization_opportunities'].append({
            'service': 'Amazon ElastiCache',
            'current_monthly_cost': elasticache_cost,
            'potential_savings_low': elasticache_savings_low,
            'potential_savings_high': elasticache_savings_high,
            'optimization': 'Right-sizing and Graviton migration'
        })

        summary['total_potential_savings'] = {
            'monthly_low': dynamodb_savings_low + elasticache_savings_low,
            'monthly_high': dynamodb_savings_high + elasticache_savings_high,
            'annual_low': (dynamodb_savings_low + elasticache_savings_low) * 12,
            'annual_high': (dynamodb_savings_high + elasticache_savings_high) * 12
        }

        # Generate recommendations
        if dynamodb_cost > 500:
            summary['recommendations'].append({
                'priority': 'HIGH',
                'service': 'DynamoDB',
                'action': 'Run auto-scaling analysis and implement recommendations',
                'estimated_savings': f"${dynamodb_savings_low:.2f}-${dynamodb_savings_high:.2f}/month",
                'command': 'python dynamodb_autoscaling_analyzer.py'
            })

        if elasticache_cost > 300:
            summary['recommendations'].append({
                'priority': 'HIGH',
                'service': 'ElastiCache',
                'action': 'Analyze cluster utilization and right-size nodes',
                'estimated_savings': f"${elasticache_savings_low:.2f}-${elasticache_savings_high:.2f}/month",
                'command': 'python cost_analysis_elasticache.py'
            })

        summary['recommendations'].append({
            'priority': 'MEDIUM',
            'service': 'All',
            'action': 'Implement tagging strategy for cost allocation',
            'estimated_savings': 'Enables cost tracking and future optimizations',
            'command': 'python tag_enforcement.py --bulk-tag --apply'
        })

        summary['recommendations'].append({
            'priority': 'MEDIUM',
            'service': 'All',
            'action': 'Set up budget alerts to prevent cost overruns',
            'estimated_savings': 'Prevents unexpected costs',
            'command': f'python budget_alerts.py --setup --total-budget {int(last_month_total * 1.1)} --emails your@email.com'
        })

        summary['recommendations'].append({
            'priority': 'LOW',
            'service': 'All',
            'action': 'Clean up old backups and unused resources',
            'estimated_savings': '$50-200/month',
            'command': 'python cleanup_automation.py --report'
        })

        return summary

    def print_report(self, summary: Dict[str, Any]) -> None:
        """Print formatted comprehensive report."""
        print("\n")
        print("=" * 80)
        print("AWS COST OPTIMIZATION - EXECUTIVE SUMMARY")
        print("=" * 80)
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Region: {self.region}")
        print("=" * 80)
        print()

        # Current spending
        print("CURRENT SPENDING")
        print("-" * 80)
        current_total = sum(summary['current_month_costs'].values())
        last_month_total = sum(summary['last_month_costs'].values())

        print(f"Current Month-to-Date:  ${current_total:,.2f}")
        print(f"Last Month Total:       ${last_month_total:,.2f}")

        if last_month_total > 0:
            change_pct = ((current_total - last_month_total) / last_month_total) * 100
            trend = "↑" if change_pct > 0 else "↓"
            print(f"Trend:                  {trend} {abs(change_pct):.1f}%")

        print()

        # Top services
        print("TOP 5 SERVICES BY COST")
        print("-" * 80)

        if tabulate and summary['top_5_services']:
            service_data = [
                [svc['service'], f"${svc['cost']:,.2f}", f"{(svc['cost']/current_total*100):.1f}%"]
                for svc in summary['top_5_services']
            ]
            print(tabulate(
                service_data,
                headers=['Service', 'MTD Cost', '% of Total'],
                tablefmt='grid'
            ))
        else:
            for svc in summary['top_5_services']:
                pct = (svc['cost'] / current_total * 100) if current_total > 0 else 0
                print(f"  {svc['service']:<40} ${svc['cost']:>10,.2f} ({pct:>5.1f}%)")

        print()

        # Optimization opportunities
        print("=" * 80)
        print("OPTIMIZATION OPPORTUNITIES")
        print("=" * 80)
        print()

        for opp in summary['optimization_opportunities']:
            if opp['current_monthly_cost'] > 0:
                print(f"Service: {opp['service']}")
                print(f"  Current Monthly Cost:  ${opp['current_monthly_cost']:,.2f}")
                print(f"  Potential Savings:     ${opp['potential_savings_low']:,.2f} - ${opp['potential_savings_high']:,.2f}/month")
                print(f"  Annual Savings:        ${opp['potential_savings_low']*12:,.2f} - ${opp['potential_savings_high']*12:,.2f}/year")
                print(f"  Optimization Strategy: {opp['optimization']}")
                print()

        # Total potential savings
        savings = summary['total_potential_savings']
        print("-" * 80)
        print(f"TOTAL POTENTIAL SAVINGS")
        print(f"  Monthly:  ${savings['monthly_low']:,.2f} - ${savings['monthly_high']:,.2f}")
        print(f"  Annual:   ${savings['annual_low']:,.2f} - ${savings['annual_high']:,.2f}")
        print()

        if current_total > 0:
            reduction_low = (savings['monthly_low'] / current_total) * 100
            reduction_high = (savings['monthly_high'] / current_total) * 100
            print(f"  Estimated Cost Reduction: {reduction_low:.1f}% - {reduction_high:.1f}%")
        print()

        # Recommendations
        print("=" * 80)
        print("RECOMMENDED ACTIONS")
        print("=" * 80)
        print()

        for i, rec in enumerate(summary['recommendations'], 1):
            print(f"{i}. [{rec['priority']}] {rec['service']}")
            print(f"   Action: {rec['action']}")
            print(f"   Potential Savings: {rec['estimated_savings']}")
            print(f"   Command: {rec['command']}")
            print()

        # Next steps
        print("=" * 80)
        print("NEXT STEPS")
        print("=" * 80)
        print()
        print("1. Review this report with your team")
        print("2. Run detailed analysis scripts for each service")
        print("3. Implement quick wins (tagging, budgets)")
        print("4. Schedule auto-scaling implementation")
        print("5. Monitor results and iterate")
        print()
        print("For detailed implementation guidance, see: IMPLEMENTATION_ROADMAP.md")
        print()

        # Export report
        output_file = f"comprehensive_cost_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump(summary, f, indent=2, default=str)

        print(f"Report exported to: {output_file}")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Generate comprehensive AWS cost optimization report'
    )
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--profile', help='AWS profile to use')

    args = parser.parse_args()

    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)

    try:
        reporter = ComprehensiveCostReport(region=args.region)
        summary = reporter.generate_executive_summary()
        reporter.print_report(summary)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
