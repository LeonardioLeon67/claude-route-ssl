#!/bin/bash

# Setup Cron Job for SSL Auto-Renewal
# This script sets up a cron job to automatically renew SSL certificates

SCRIPT_PATH="/home/leon/claude-route-ssl/claude-route-ssl/nginx/auto-renew.sh"

echo "📋 Setting up cron job for SSL auto-renewal..."

# Create cron job that runs twice daily at 12:00 and 00:00
CRON_JOB="0 0,12 * * * $SCRIPT_PATH"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
    echo "⚠️  Cron job for SSL renewal already exists"
else
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ Cron job added successfully"
fi

echo ""
echo "📋 Current cron jobs:"
crontab -l | grep -E "(auto-renew|certbot)" || echo "No SSL renewal cron jobs found"

echo ""
echo "🎉 SSL Auto-Renewal Setup Complete!"
echo "=================================="
echo "✅ Auto-renewal script: $SCRIPT_PATH"
echo "✅ Cron schedule: Twice daily (00:00 and 12:00)"
echo "✅ Log file: /home/leon/claude-route-ssl/claude-route-ssl/nginx/logs/ssl-renewal.log"
echo ""
echo "📊 Test renewal:"
echo "   $SCRIPT_PATH"
echo ""
echo "📋 Check cron jobs:"
echo "   crontab -l"