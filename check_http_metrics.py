#!/usr/bin/env python3
import json
import sys

data = json.load(sys.stdin)
result = data.get('data', {}).get('result', [])
print(f'Found {len(result)} series')
if result:
    print('\nSample metrics with labels:')
    for i, r in enumerate(result[:3]):
        print(f'\nSeries {i+1}:')
        metric = r.get('metric', {})
        for key, value in metric.items():
            print(f'  {key}: {value}')

