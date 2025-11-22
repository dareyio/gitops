#!/usr/bin/env python3
import boto3
from datetime import datetime

ce = boto3.client('ce', region_name='eu-west-2')
today = datetime.now()
month_start = today.replace(day=1).strftime('%Y-%m-%d')
today_str = today.strftime('%Y-%m-%d')

print("=== Querying AWS for Current Month Cost ===")
print(f"Period: {month_start} to {today_str}\n")

# Get current month cost using DAILY granularity (the correct method)
try:
    result = ce.get_cost_and_usage(
        TimePeriod={'Start': month_start, 'End': today_str},
        Granularity='DAILY',
        Metrics=['BlendedCost']
    )
    
    if result.get('ResultsByTime'):
        total_cost = sum(float(day['Total']['BlendedCost']['Amount']) 
                        for day in result['ResultsByTime'])
        currency = result['ResultsByTime'][0]['Total']['BlendedCost']['Unit']
        print(f"Current Month Cost (DAILY sum): ${total_cost:.2f} {currency}")
        
        # Also show what MONTHLY granularity would return
        monthly_result = ce.get_cost_and_usage(
            TimePeriod={'Start': month_start, 'End': today_str},
            Granularity='MONTHLY',
            Metrics=['BlendedCost']
        )
        if monthly_result.get('ResultsByTime'):
            monthly_cost = float(monthly_result['ResultsByTime'][0]['Total']['BlendedCost']['Amount'])
            print(f"Current Month Cost (MONTHLY): ${monthly_cost:.2f} {currency}")
            print(f"\nDifference: ${abs(total_cost - monthly_cost):.2f}")
            
        # Show breakdown by day
        print("\nDaily breakdown:")
        for day_result in result['ResultsByTime']:
            date = day_result['TimePeriod']['Start']
            cost = float(day_result['Total']['BlendedCost']['Amount'])
            print(f"  {date}: ${cost:.2f}")
            
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()

