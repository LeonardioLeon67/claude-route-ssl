#!/bin/bash

# SSL Setup Script for direct.816981.xyz
# This script sets up SSL certificate and nginx configuration

DOMAIN="direct.816981.xyz"
NGINX_CONF_DIR="/home/leon/claude-route-ssl/claude-route-ssl/nginx/conf.d"
NGINX_CONF_FILE="$NGINX_CONF_DIR/$DOMAIN.conf"
EMAIL="admin@816981.xyz"  # Change this to your email

echo "🔐 SSL Setup for $DOMAIN"
echo "=================================="

# Step 1: Test nginx configuration syntax
echo "📋 Step 1: Testing nginx configuration..."
if ! sudo nginx -t -c $NGINX_CONF_FILE 2>/dev/null; then
    echo "⚠️  Will test with system nginx after linking configuration"
fi

# Step 2: Link our configuration to system nginx
echo "📋 Step 2: Linking nginx configuration..."
sudo ln -sf $NGINX_CONF_FILE /etc/nginx/sites-available/$DOMAIN.conf
sudo ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/$DOMAIN.conf

# Remove default nginx site if exists
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    sudo rm /etc/nginx/sites-enabled/default
    echo "✅ Removed default nginx site"
fi

# Step 3: Test nginx configuration
echo "📋 Step 3: Testing nginx configuration..."
if ! sudo nginx -t; then
    echo "❌ Nginx configuration test failed!"
    exit 1
fi

# Step 4: Reload nginx to apply HTTP configuration (for certbot challenge)
echo "📋 Step 4: Reloading nginx..."
sudo systemctl reload nginx

# Step 5: Obtain SSL certificate using certbot
echo "📋 Step 5: Obtaining SSL certificate for $DOMAIN..."
sudo certbot certonly \
    --nginx \
    --non-interactive \
    --agree-tos \
    --email $EMAIL \
    --domains $DOMAIN \
    --expand

if [ $? -ne 0 ]; then
    echo "❌ Failed to obtain SSL certificate!"
    exit 1
fi

echo "✅ SSL certificate obtained successfully!"

# Step 6: Update nginx configuration to enable SSL
echo "📋 Step 6: Updating nginx configuration with SSL..."
sed -i 's/# ssl_certificate /ssl_certificate /g' $NGINX_CONF_FILE
sed -i 's/# ssl_certificate_key /ssl_certificate_key /g' $NGINX_CONF_FILE

# Step 7: Test updated nginx configuration
echo "📋 Step 7: Testing updated nginx configuration..."
if ! sudo nginx -t; then
    echo "❌ Updated nginx configuration test failed!"
    exit 1
fi

# Step 8: Reload nginx with SSL configuration
echo "📋 Step 8: Reloading nginx with SSL configuration..."
sudo systemctl reload nginx

# Step 9: Set up automatic renewal
echo "📋 Step 9: Setting up automatic SSL renewal..."
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Add renewal hook to reload nginx after certificate renewal
echo '#!/bin/bash' | sudo tee /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
echo 'systemctl reload nginx' | sudo tee -a /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh

echo ""
echo "🎉 SSL Setup Complete!"
echo "=================================="
echo "✅ Domain: $DOMAIN"
echo "✅ SSL Certificate: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
echo "✅ SSL Private Key: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
echo "✅ Nginx Configuration: $NGINX_CONF_FILE"
echo "✅ Automatic Renewal: Enabled"
echo ""
echo "🔗 Your site is now available at: https://$DOMAIN"
echo "🔄 Proxying to: http://127.0.0.1:8080"
echo ""
echo "📊 Test the setup:"
echo "   curl -I https://$DOMAIN"
echo ""
echo "🔄 Check renewal status:"
echo "   sudo certbot renew --dry-run"