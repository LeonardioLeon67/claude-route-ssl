#!/bin/bash

# SSL Certificate Auto-Renewal Script for direct.816981.xyz
# This script ensures SSL certificates are automatically renewed

DOMAIN="direct.816981.xyz"
LOG_FILE="/home/leon/claude-route-ssl/claude-route-ssl/nginx/logs/ssl-renewal.log"

echo "🔄 $(date): Starting SSL certificate renewal check for $DOMAIN" >> $LOG_FILE

# Check if certificate needs renewal (within 30 days of expiry)
if sudo certbot renew --quiet --no-self-upgrade --post-hook "systemctl reload nginx"; then
    echo "✅ $(date): SSL certificate renewal check completed successfully" >> $LOG_FILE
else
    echo "❌ $(date): SSL certificate renewal failed" >> $LOG_FILE
    exit 1
fi

echo "📝 $(date): Certificate status for $DOMAIN:" >> $LOG_FILE
sudo certbot certificates --cert-name $DOMAIN >> $LOG_FILE 2>&1

echo "🔄 $(date): SSL renewal check completed" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE