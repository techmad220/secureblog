#!/bin/bash
# Privacy-preserving analytics aggregation script

set -euo pipefail

# Configuration
LOG_DIR="${LOG_DIR:-/var/log/secureblog}"
OUTPUT_DIR="${OUTPUT_DIR:-/var/www/secureblog/analytics}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Plugin-based aggregation
aggregate_daily_stats() {
    local date="$1"
    local log_file="$LOG_DIR/access-$date.log"
    local output_file="$OUTPUT_DIR/stats-$date.json"
    
    if [ ! -f "$log_file" ]; then
        echo "No log file for $date"
        return
    fi
    
    echo "Aggregating stats for $date..."
    
    # Parse logs and create aggregated stats (no PII)
    python3 - << 'EOF' "$log_file" "$output_file"
import sys
import json
import re
from collections import defaultdict
from datetime import datetime

log_file = sys.argv[1]
output_file = sys.argv[2]

stats = {
    'date': log_file.split('-')[-1].replace('.log', ''),
    'total_requests': 0,
    'unique_visitors': set(),
    'pages': defaultdict(int),
    'status_codes': defaultdict(int),
    'browsers': defaultdict(int),
    'operating_systems': defaultdict(int),
    'hourly_distribution': defaultdict(int),
    'avg_response_time': [],
    'total_bandwidth': 0
}

# Parse log entries
with open(log_file, 'r') as f:
    for line in f:
        parts = line.strip().split(' | ')
        if len(parts) < 7:
            continue
        
        # Extract fields (privacy-preserved format)
        timestamp = parts[0]
        # ip is already anonymized
        method = parts[2]
        path = parts[3]
        status = int(parts[4]) if parts[4] != '-' else 0
        size = int(parts[5]) if parts[5] != '-' else 0
        response_time = int(parts[6].replace('ms', '')) if len(parts) > 6 else 0
        
        # Extract hour from timestamp
        try:
            dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            hour = dt.hour
            stats['hourly_distribution'][hour] += 1
        except:
            pass
        
        # Aggregate stats
        stats['total_requests'] += 1
        stats['pages'][path] += 1
        stats['status_codes'][str(status)] += 1
        stats['total_bandwidth'] += size
        
        if response_time > 0:
            stats['avg_response_time'].append(response_time)
        
        # Browser/OS from anonymized UA
        if len(parts) > 7:
            ua = parts[7]
            if '/' in ua:
                browser, os = ua.split('/')
                stats['browsers'][browser] += 1
                stats['operating_systems'][os] += 1
        
        # Unique visitors from hash
        if len(parts) > 9:
            visitor_hash = parts[9]
            stats['unique_visitors'].add(visitor_hash)

# Calculate aggregates
stats['unique_visitors'] = len(stats['unique_visitors'])
stats['avg_response_time'] = sum(stats['avg_response_time']) // len(stats['avg_response_time']) if stats['avg_response_time'] else 0

# Convert defaultdicts to regular dicts
stats['pages'] = dict(stats['pages'])
stats['status_codes'] = dict(stats['status_codes'])
stats['browsers'] = dict(stats['browsers'])
stats['operating_systems'] = dict(stats['operating_systems'])
stats['hourly_distribution'] = dict(stats['hourly_distribution'])

# Sort pages by popularity
stats['top_pages'] = sorted(stats['pages'].items(), key=lambda x: x[1], reverse=True)[:10]

# Write aggregated stats
with open(output_file, 'w') as f:
    json.dump(stats, f, indent=2)

print(f"✓ Aggregated {stats['total_requests']} requests, {stats['unique_visitors']} unique visitors")
EOF
}

# Clean old logs
cleanup_old_logs() {
    echo "Cleaning logs older than $RETENTION_DAYS days..."
    
    find "$LOG_DIR" -name "access-*.log" -type f -mtime +$RETENTION_DAYS -delete
    find "$OUTPUT_DIR" -name "stats-*.json" -type f -mtime +$RETENTION_DAYS -delete
    
    echo "✓ Cleanup complete"
}

# Generate monthly summary
generate_monthly_summary() {
    local month="$1"
    local year="$2"
    
    echo "Generating monthly summary for $year-$month..."
    
    python3 - << 'EOF' "$OUTPUT_DIR" "$year" "$month"
import sys
import json
import os
from pathlib import Path
from collections import defaultdict

output_dir = sys.argv[1]
year = sys.argv[2]
month = sys.argv[3]

monthly_stats = {
    'period': f"{year}-{month}",
    'total_requests': 0,
    'unique_visitors_estimate': 0,
    'total_bandwidth': 0,
    'top_pages': defaultdict(int),
    'daily_stats': []
}

# Aggregate daily stats
for stats_file in Path(output_dir).glob(f"stats-{year}-{month}-*.json"):
    with open(stats_file) as f:
        daily = json.load(f)
        
        monthly_stats['total_requests'] += daily.get('total_requests', 0)
        monthly_stats['unique_visitors_estimate'] += daily.get('unique_visitors', 0)
        monthly_stats['total_bandwidth'] += daily.get('total_bandwidth', 0)
        
        # Aggregate top pages
        for page, count in daily.get('pages', {}).items():
            monthly_stats['top_pages'][page] += count
        
        # Add daily summary
        monthly_stats['daily_stats'].append({
            'date': daily['date'],
            'requests': daily.get('total_requests', 0),
            'visitors': daily.get('unique_visitors', 0)
        })

# Sort top pages
monthly_stats['top_pages'] = sorted(
    monthly_stats['top_pages'].items(),
    key=lambda x: x[1],
    reverse=True
)[:20]

# Write monthly summary
summary_file = f"{output_dir}/summary-{year}-{month}.json"
with open(summary_file, 'w') as f:
    json.dump(monthly_stats, f, indent=2)

print(f"✓ Monthly summary: {monthly_stats['total_requests']} requests, ~{monthly_stats['unique_visitors_estimate']} unique visitors")
EOF
}

# GoAccess integration (optional)
generate_goaccess_report() {
    if ! command -v goaccess &> /dev/null; then
        echo "GoAccess not installed, skipping HTML report"
        return
    fi
    
    local date="$1"
    local log_file="$LOG_DIR/access-$date.log"
    local report_file="$OUTPUT_DIR/report-$date.html"
    
    echo "Generating GoAccess report for $date..."
    
    # Custom log format for our privacy-preserved logs
    goaccess "$log_file" \
        --log-format='%d | %h | %m | %U | %s | %b | %Tms | %u | %R | %^' \
        --date-format='%Y-%m-%dT%H:%M:%S' \
        --time-format='%H:%M:%S' \
        --output="$report_file" \
        --no-query-string \
        --no-term-resolver \
        --no-ip-resolver \
        --anonymize-ip \
        --ignore-crawlers \
        2>/dev/null || echo "⚠️  GoAccess report generation failed"
}

# Main execution
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Privacy Analytics Aggregator"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Process yesterday's logs by default
    yesterday=$(date -d "yesterday" +%Y-%m-%d)
    aggregate_daily_stats "$yesterday"
    generate_goaccess_report "$yesterday"
    
    # Generate monthly summary if it's the first of the month
    if [ "$(date +%d)" == "01" ]; then
        last_month=$(date -d "last month" +%m)
        last_month_year=$(date -d "last month" +%Y)
        generate_monthly_summary "$last_month" "$last_month_year"
    fi
    
    # Cleanup old data
    cleanup_old_logs
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   ✅ Analytics aggregation complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi