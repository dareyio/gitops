#!/usr/bin/env python3
import boto3
from datetime import datetime

ce = boto3.client('ce', region_name='eu-west-2')
today = datetime.now()
month_start = today.replace(day=1).strftime('%Y-%m-%d')
today_str = today.strftime('%Y-%m-%d')

print("=== Querying AWS Cost Explorer for Service Costs ===")
print(f"Period: {month_start} to {today_str}\n")

try:
    result = ce.get_cost_and_usage(
        TimePeriod={'Start': month_start, 'End': today_str},
        Granularity='MONTHLY',
        Metrics=['BlendedCost'],
        GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
    )
    
    if result.get('ResultsByTime'):
        print("Service costs (sorted by cost):")
        print("-" * 70)
        services = []
        for group in result['ResultsByTime'][0].get('Groups', []):
            service = group['Keys'][0] if group['Keys'] else 'Unknown'
            cost = float(group['Metrics']['BlendedCost']['Amount'])
            currency = group['Metrics']['BlendedCost']['Unit']
            services.append((service, cost, currency))
        
        # Sort by cost descending
        services.sort(key=lambda x: x[1], reverse=True)
        
        for service, cost, currency in services:
            if cost > 0 or abs(cost) > 0.0001:  # Show non-zero or significant values
                print(f"{service:50s} ${cost:15.2f} {currency}")
        
        print("-" * 70)
        total = sum(cost for _, cost, _ in services)
        print(f"{'TOTAL':50s} ${total:15.2f}")
        
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()

