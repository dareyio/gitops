#!/usr/bin/env python3
import boto3
from datetime import datetime

ce = boto3.client('ce', region_name='eu-west-2')
today = datetime.now()
month_start = today.replace(day=1).strftime('%Y-%m-%d')
today_str = today.strftime('%Y-%m-%d')

print("=== Calculating Gross vs Net Cost ===")
print(f"Period: {month_start} to {today_str}\n")

# Get cost with RECORD_TYPE to separate usage from credits
try:
    result = ce.get_cost_and_usage(
        TimePeriod={'Start': month_start, 'End': today_str},
        Granularity='DAILY',
        Metrics=['BlendedCost'],
        GroupBy=[{'Type': 'DIMENSION', 'Key': 'RECORD_TYPE'}]
    )
    
    total_usage = 0.0
    total_credits = 0.0
    net_cost = 0.0
    
    if result.get('ResultsByTime'):
        for day_result in result['ResultsByTime']:
            if day_result.get('Groups'):
                for group in day_result['Groups']:
                    record_type = group['Keys'][0] if group['Keys'] else 'Unknown'
                    cost = float(group['Metrics']['BlendedCost']['Amount'])
                    
                    if 'Usage' in record_type:
                        total_usage += cost
                    elif 'Credit' in record_type:
                        total_credits += abs(cost)
                    net_cost += cost
    
    currency = 'USD'
    print(f"Gross Cost (Usage only): ${total_usage:.2f} {currency}")
    print(f"Credits Applied: ${total_credits:.2f} {currency}")
    print(f"Net Cost (After credits): ${net_cost:.2f} {currency}")
    print(f"\nCurrent calculation shows: ${net_cost:.2f} (net)")
    print(f"Should show: ${total_usage:.2f} (gross)")
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()

