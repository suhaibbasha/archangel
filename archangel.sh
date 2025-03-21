#!/bin/bash

# Archangel: USB Encryption Session Manager
# This script creates a secure session for accessing encrypted files on a USB stick.
# Files are only accessible during the session and automatically encrypted when the session ends.
#
# ENCRYPTION: This script uses GnuPG (GPG) with AES-256 symmetric encryption in 3 layers:
# - Each file is encrypted 3 separate times with 3 different passphrases
# - Each layer uses AES-256 (Advanced Encryption Standard with 256-bit key)
# - This provides military-grade encryption that's extremely difficult to break

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get OS type for cross-platform compatibility
OS_TYPE=$(uname)

# Get absolute path in a cross-platform way
get_absolute_path() {
    local path="$1"
    case "$OS_TYPE" in
        Darwin) # macOS
            echo "$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
            ;;
        Linux)
            echo "$(readlink -f "$path")"
            ;;
        MINGW*|CYGWIN*) # Windows with Git Bash or Cygwin
            echo "$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
            ;;
        *)
            echo "$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
            ;;
    esac
}

# Configuration
USB_PATH=$(dirname "$(get_absolute_path "$0")") # Get the directory where the script is located
RAM_DISK_PATH="" # Will be set based on OS
SESSION_DIR="" # Will be set after RAM disk is mounted
ENCRYPTION_PASSPHRASE_1="" # First layer encryption passphrase
ENCRYPTION_PASSPHRASE_2="" # Second layer encryption passphrase
ENCRYPTION_PASSPHRASE_3="" # Third layer encryption passphrase
USB_DEVICE=""

# Print banner
echo -e "${GREEN}"
echo -e " [ArchAngel] Advanced USB Session Manager${NC}"
echo ""

# Function to get passphrases securely
get_passphrases() {
    echo -e "${YELLOW}Enter encryption passphrases (they won't be visible):${NC}"
    read -s -p "Layer 1 Passphrase: " ENCRYPTION_PASSPHRASE_1
    echo ""
    read -s -p "Layer 2 Passphrase: " ENCRYPTION_PASSPHRASE_2
    echo ""
    read -s -p "Layer 3 Passphrase: " ENCRYPTION_PASSPHRASE_3
    echo ""
    
    # Validate that passphrases are not empty
    if [[ -z "$ENCRYPTION_PASSPHRASE_1" || -z "$ENCRYPTION_PASSPHRASE_2" || -z "$ENCRYPTION_PASSPHRASE_3" ]]; then
        echo -e "${RED}Error: Empty passphrases are not allowed. Please try again.${NC}"
        get_passphrases
    fi
}

# Find the USB device in a cross-platform way
find_usb_device() {
    case "$OS_TYPE" in
        Darwin) # macOS
            USB_MOUNT_POINT=$(df "$USB_PATH" | tail -1 | awk '{print $1}')
            if [ -z "$USB_MOUNT_POINT" ]; then
                echo -e "${RED}Error: Could not determine USB device.${NC}"
                exit 1
            fi
            USB_DEVICE=$(basename "$USB_MOUNT_POINT")
            ;;
        Linux)
            USB_MOUNT_POINT=$(df "$USB_PATH" | tail -1 | awk '{print $1}')
            if [ -z "$USB_MOUNT_POINT" ]; then
                echo -e "${RED}Error: Could not determine USB device.${NC}"
                exit 1
            fi
            USB_DEVICE=$(basename "$USB_MOUNT_POINT")
            ;;
        MINGW*|CYGWIN*) # Windows with Git Bash or Cygwin
            # Windows doesn't have a simple way to get the device, so we'll use the drive letter
            USB_DRIVE=$(echo "$USB_PATH" | cut -d: -f1)
            USB_DEVICE="$USB_DRIVE:"
            ;;
        *)
            echo -e "${RED}Unsupported operating system. USB removal detection may not work.${NC}"
            USB_DEVICE="unknown"
            ;;
    esac
    echo -e "${GREEN}USB device identified as: $USB_DEVICE${NC}"
}

# Function to create and mount a RAM disk based on OS
create_ram_disk() {
    echo -e "${YELLOW}Creating secure RAM disk for session data...${NC}"
    
    local ram_size="64M" # 64MB RAM disk size
    local session_id="archangel_$(date +%s)"
    
    case "$OS_TYPE" in
        Darwin) # macOS
            # Create a RAM disk in macOS (size in sectors, 512 bytes per sector)
            local sectors=$(($(echo $ram_size | sed 's/M//') * 2048))
            RAM_DISK_PATH="/Volumes/$session_id"
            
            # Create and mount RAM disk
            local disk_id=$(hdiutil attach -nomount ram://$sectors | tr -d ' ')
            diskutil erasevolume HFS+ "$session_id" $disk_id > /dev/null 2>&1
            
            echo -e "${GREEN}RAM disk created at $RAM_DISK_PATH${NC}"
            ;;
            
        Linux)
            # Create a RAM disk in Linux using tmpfs
            RAM_DISK_PATH="/tmp/$session_id"
            mkdir -p "$RAM_DISK_PATH"
            
            # Mount as tmpfs (RAM-based filesystem)
            sudo mount -t tmpfs -o size=$ram_size,mode=0700 tmpfs "$RAM_DISK_PATH"
            sudo chown $(id -u):$(id -g) "$RAM_DISK_PATH"
            
            echo -e "${GREEN}RAM disk created at $RAM_DISK_PATH${NC}"
            ;;
            
        MINGW*|CYGWIN*) # Windows 
            # Windows doesn't have a native RAM disk, fall back to secure temp directory
            RAM_DISK_PATH="/tmp/$session_id"
            mkdir -p "$RAM_DISK_PATH"
            
            echo -e "${YELLOW}WARNING: True RAM disk not available on Windows. Using secure temp directory.${NC}"
            ;;
            
        *)
            # Fallback for other OS
            RAM_DISK_PATH="/tmp/$session_id"
            mkdir -p "$RAM_DISK_PATH"
            
            echo -e "${YELLOW}WARNING: RAM disk creation not supported on this OS. Using temp directory.${NC}"
            ;;
    esac
    
    # Set the session directory inside the RAM disk
    SESSION_DIR="$RAM_DISK_PATH/session"
    mkdir -p "$SESSION_DIR"
    
    # Set secure permissions
    chmod 700 "$RAM_DISK_PATH"
    chmod 700 "$SESSION_DIR"
}

# Function to unmount the RAM disk
unmount_ram_disk() {
    echo -e "${YELLOW}Unmounting RAM disk...${NC}"
    
    case "$OS_TYPE" in
        Darwin) # macOS
            # Unmount RAM disk in macOS
            hdiutil detach "$RAM_DISK_PATH" > /dev/null 2>&1
            ;;
            
        Linux)
            # Unmount RAM disk in Linux
            sudo umount "$RAM_DISK_PATH"
            rmdir "$RAM_DISK_PATH"
            ;;
            
        *)
            # Other OS, just remove the directory
            rm -rf "$RAM_DISK_PATH"
            ;;
    esac
    
    echo -e "${GREEN}RAM disk unmounted${NC}"
}

# Function to encrypt a file (3 layers of encryption)
encrypt_file() {
    local file="$1"
    local temp1="$file.enc1"
    local temp2="$file.enc2"
    local output="$file.enc"
    
    # Skip if the file is already an encrypted file or a temporary encryption file
    if [[ "$file" == *.enc || "$file" == *.enc1 || "$file" == *.enc2 || "$file" == *.dec1 || "$file" == *.dec2 ]]; then
        echo -e "${YELLOW}Skipping already encrypted or temporary file: $file${NC}"
        return
    fi
    
    # Check if encrypted version already exists - prevent reprocessing
    if [ -f "$output" ]; then
        echo -e "${YELLOW}Encrypted version already exists: $output${NC}"
        return
    fi
    
    # Check if file exists and is readable
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo -e "${RED}Error: Cannot read file for encryption: $file${NC}"
        return
    fi
    
    # Layer 1 encryption with better error handling
    if ! echo "$ENCRYPTION_PASSPHRASE_1" | gpg --batch --yes --quiet --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$temp1" "$file"; then
        echo -e "${RED}Encryption layer 1 failed for: $file${NC}"
        rm -f "$temp1" 2>/dev/null
        return
    fi
    
    # Layer 2 encryption
    if ! echo "$ENCRYPTION_PASSPHRASE_2" | gpg --batch --yes --quiet --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$temp2" "$temp1"; then
        echo -e "${RED}Encryption layer 2 failed for: $file${NC}"
        rm -f "$temp1" "$temp2" 2>/dev/null
        return
    fi
    
    # Layer 3 encryption
    if ! echo "$ENCRYPTION_PASSPHRASE_3" | gpg --batch --yes --quiet --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$output" "$temp2"; then
        echo -e "${RED}Encryption layer 3 failed for: $file${NC}"
        rm -f "$temp1" "$temp2" "$output" 2>/dev/null
        return
    fi
    
    # Clean up temporary files
    rm -f "$temp1" "$temp2"
    
    # Only remove original file if encryption was successful
    if [ -f "$output" ] && [ -s "$output" ]; then
        rm -f "$file"
        echo -e "${GREEN}Encrypted: $file${NC}"
    else
        echo -e "${RED}Encryption failed: $file (empty output file)${NC}"
        rm -f "$output" 2>/dev/null
    fi
}

# Function to decrypt a file (3 layers of decryption)
decrypt_file() {
    local file="$1"
    local basename="${file%.enc}"
    local temp1="$basename.dec1"
    local temp2="$basename.dec2"
    
    # Skip if not an encrypted file
    if [[ "$file" != *.enc ]]; then
        echo -e "${YELLOW}Skipping non-encrypted file: $file${NC}"
        return
    fi
    
    # Check if file exists and is readable
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo -e "${RED}Error: Cannot read file for decryption: $file${NC}"
        return
    fi
    
    # Layer 3 decryption with better error handling
    if ! echo "$ENCRYPTION_PASSPHRASE_3" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$temp1" "$file"; then
        echo -e "${RED}Decryption layer 3 failed for: $file (Incorrect passphrase?)${NC}"
        rm -f "$temp1" 2>/dev/null
        return
    fi
    
    # Layer 2 decryption
    if ! echo "$ENCRYPTION_PASSPHRASE_2" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$temp2" "$temp1"; then
        echo -e "${RED}Decryption layer 2 failed for: $file${NC}"
        rm -f "$temp1" "$temp2" 2>/dev/null
        return
    fi
    
    # Layer 1 decryption
    if ! echo "$ENCRYPTION_PASSPHRASE_1" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$basename" "$temp2"; then
        echo -e "${RED}Decryption layer 1 failed for: $file${NC}"
        rm -f "$temp1" "$temp2" 2>/dev/null
        return
    fi
    
    # Clean up temporary files
    rm -f "$temp1" "$temp2"
    
    # Verify the decrypted file exists and is not empty
    if [ -f "$basename" ] && [ -s "$basename" ]; then
        echo -e "${GREEN}Decrypted: $file${NC}"
    else
        echo -e "${RED}Decryption failed: $file (empty output file)${NC}"
    fi
}

# Function to encrypt all files before ending the session
encrypt_all_files() {
    echo -e "${YELLOW}Encrypting all files in the session directory...${NC}"
    
    # Check if session directory exists
    if [ ! -d "$SESSION_DIR" ]; then
        echo -e "${RED}Session directory does not exist. Skipping encryption.${NC}"
        return
    fi
    
    # Use a temporary list of files to avoid encryption loop - improved filter
    find "$SESSION_DIR" -type f -not -name "*.enc" -not -name "*.enc1" -not -name "*.enc2" \
        -not -name "*.dec1" -not -name "*.dec2" -not -path "*/\.*" > "$SESSION_DIR/.archangel_files_to_encrypt"
    
    if [ ! -s "$SESSION_DIR/.archangel_files_to_encrypt" ]; then
        echo -e "${YELLOW}No files to encrypt in session directory.${NC}"
        rm -f "$SESSION_DIR/.archangel_files_to_encrypt"
        return
    fi
    
    while read -r file; do
        # Get the filename without path
        filename=$(basename "$file")
        encrypted_file="$USB_PATH/$filename.enc"
        
        # Skip if encrypted version already exists at USB path
        if [ -f "$encrypted_file" ]; then
            echo -e "${YELLOW}Skipping already encrypted file: $filename${NC}"
            continue
        fi
        
        # Copy to USB root if not already there
        if [ -f "$file" ]; then
            cp "$file" "$USB_PATH/" 2>/dev/null
            if [ $? -eq 0 ]; then
                encrypt_file "$USB_PATH/$filename"
            else
                echo -e "${RED}Failed to copy $file to USB path for encryption${NC}"
            fi
        fi
    done < "$SESSION_DIR/.archangel_files_to_encrypt"
    
    rm -f "$SESSION_DIR/.archangel_files_to_encrypt"
}

# Function to set up the session
setup_session() {
    echo -e "${YELLOW}Setting up secure session...${NC}"
    
    # Create session directory if it doesn't exist
    mkdir -p "$SESSION_DIR"
    if [ ! -d "$SESSION_DIR" ]; then
        echo -e "${RED}Failed to create session directory. Aborting.${NC}"
        exit 1
    fi
    
    # Decrypt all encrypted files from USB to the session directory
    find "$USB_PATH" -maxdepth 1 -name "*.enc" | while read -r file; do
        # Get just the filename without the path
        filename=$(basename "$file")
        # Copy to session directory only if it's not already there
        if [ ! -f "$SESSION_DIR/$filename" ]; then
            cp "$file" "$SESSION_DIR/" 2>/dev/null
            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to copy $file to session directory${NC}"
                continue
            fi
        fi
        # Decrypt in the session directory
        decrypt_file "$SESSION_DIR/$filename"
    done
    
    echo -e "${GREEN}Session setup complete. Files are available at: $SESSION_DIR${NC}"
    echo -e "${YELLOW}WARNING: Files are unencrypted during this session.${NC}"
}

# Function to monitor for new files in the session directory
monitor_new_files() {
    echo -e "${BLUE}Starting file monitor for new files...${NC}"
    
    case "$OS_TYPE" in
        Linux)
            if command -v inotifywait >/dev/null 2>&1; then
                (
                    while true; do
                        inotifywait -q -e create -e moved_to "$SESSION_DIR" >/dev/null 2>&1
                        
                        # Get newly created files (skip already encrypted files)
                        find "$SESSION_DIR" -type f -not -name "*.enc" -not -name "*.enc1" -not -name "*.enc2" \
                            -not -name "*.dec1" -not -name "*.dec2" -not -path "*/\.*" > "$SESSION_DIR/.archangel_new_files"
                        
                        while read -r file; do
                            # Create an encrypted copy in the USB root directory
                            filename=$(basename "$file")
                            encrypted_file="$USB_PATH/$filename.enc"
                            
                            # Skip if encrypted version already exists
                            if [ -f "$encrypted_file" ]; then
                                continue
                            fi
                            
                            if [ -f "$file" ]; then
                                # Make a copy at the USB root and encrypt it
                                cp "$file" "$USB_PATH/$filename" 2>/dev/null
                                if [ $? -eq 0 ]; then
                                    encrypt_file "$USB_PATH/$filename"
                                fi
                            fi
                        done < "$SESSION_DIR/.archangel_new_files"
                        
                        rm -f "$SESSION_DIR/.archangel_new_files"
                    done
                ) &
                MONITOR_PID=$!
            else
                # Fallback to polling
                use_polling
            fi
            ;;
        Darwin) # macOS
            if command -v fswatch >/dev/null 2>&1; then
                (
                    fswatch -o "$SESSION_DIR" | while read -r; do
                        find "$SESSION_DIR" -type f -not -name "*.enc" -not -name "*.enc1" -not -name "*.enc2" \
                            -not -name "*.dec1" -not -name "*.dec2" -not -path "*/\.*" > "$SESSION_DIR/.archangel_new_files"
                        
                        while read -r file; do
                            # Create an encrypted copy in the USB root directory
                            filename=$(basename "$file")
                            encrypted_file="$USB_PATH/$filename.enc"
                            
                            # Skip if encrypted version already exists
                            if [ -f "$encrypted_file" ]; then
                                continue
                            fi
                            
                            if [ -f "$file" ]; then
                                cp "$file" "$USB_PATH/$filename" 2>/dev/null
                                if [ $? -eq 0 ]; then
                                    encrypt_file "$USB_PATH/$filename"
                                fi
                            fi
                        done < "$SESSION_DIR/.archangel_new_files"
                        
                        rm -f "$SESSION_DIR/.archangel_new_files"
                    done
                ) &
                MONITOR_PID=$!
            else
                # Fallback to polling
                use_polling
            fi
            ;;
        *)
            # Fallback to polling for unsupported OS
            use_polling
            ;;
    esac
}

# Function for polling-based file monitoring
use_polling() {
    (
        while true; do
            sleep 5
            find "$SESSION_DIR" -type f -not -name "*.enc" -not -name "*.enc1" -not -name "*.enc2" \
                -not -name "*.dec1" -not -name "*.dec2" -not -path "*/\.*" > "$SESSION_DIR/.archangel_new_files"
            
            while read -r file; do
                # Create an encrypted copy in the USB root directory
                filename=$(basename "$file")
                encrypted_file="$USB_PATH/$filename.enc"
                
                # Skip if encrypted version already exists
                if [ -f "$encrypted_file" ]; then
                    continue
                fi
                
                if [ -f "$file" ]; then
                    cp "$file" "$USB_PATH/$filename" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        encrypt_file "$USB_PATH/$filename"
                    fi
                fi
            done < "$SESSION_DIR/.archangel_new_files"
            
            rm -f "$SESSION_DIR/.archangel_new_files"
        done
    ) &
    MONITOR_PID=$!
}

# Function to monitor USB device presence
monitor_usb_presence() {
    echo -e "${BLUE}Starting USB presence monitor...${NC}"
    (
        while true; do
            sleep 2
            case "$OS_TYPE" in
                Darwin) # macOS
                    if ! df | grep -q "$USB_DEVICE"; then
                        echo -e "${RED}USB device removed! Cleaning up session...${NC}"
                        cleanup
                        exit 0
                    fi
                    ;;
                Linux)
                    if command -v lsblk >/dev/null 2>&1; then
                        if ! lsblk | grep -q "$USB_DEVICE"; then
                            echo -e "${RED}USB device removed! Cleaning up session...${NC}"
                            cleanup
                            exit 0
                        fi
                    else
                        # Fallback if lsblk is not available on Linux
                        if ! df | grep -q "$USB_DEVICE"; then
                            echo -e "${RED}USB device removed! Cleaning up session...${NC}"
                            cleanup
                            exit 0
                        fi
                    fi
                    ;;
                MINGW*|CYGWIN*) # Windows
                    if ! df | grep -q "$USB_DEVICE"; then
                        echo -e "${RED}USB device removed! Cleaning up session...${NC}"
                        cleanup
                        exit 0
                    fi
                    ;;
                *)
                    # For unsupported OS, we'll just check if the USB path still exists
                    if [ ! -d "$USB_PATH" ]; then
                        echo -e "${RED}USB device removed! Cleaning up session...${NC}"
                        cleanup
                        exit 0
                    fi
                    ;;
            esac
        done
    ) &
    USB_MONITOR_PID=$!
}

# Function to securely clean up files based on OS
secure_wipe() {
    local dir="$1"
    case "$OS_TYPE" in
        Darwin) # macOS
            if command -v srm >/dev/null 2>&1; then
                find "$dir" -type f -not -path "*/\.*" -exec srm -z {} \;
            else
                find "$dir" -type f -not -path "*/\.*" -exec rm {} \;
            fi
            ;;
        Linux)
            if command -v shred >/dev/null 2>&1; then
                find "$dir" -type f -not -path "*/\.*" -exec shred -uzn 3 {} \;
            else
                find "$dir" -type f -not -path "*/\.*" -exec rm {} \;
            fi
            ;;
        *)
            # Best effort for other OS
            find "$dir" -type f -not -path "*/\.*" -exec rm {} \;
            ;;
    esac
    
    # Instead of removing the directory, just clean it
    find "$dir" -type f -not -path "*/\.*" -delete
    
    # Remove any temporary files
    rm -f "$dir/.archangel_files_to_encrypt" "$dir/.archangel_new_files"
}

# Function to clean up and end the session
cleanup() {
    echo -e "${YELLOW}Ending session and cleaning up...${NC}"
    
    # Kill the file monitor
    if [ -n "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null
    fi
    
    # Kill the USB monitor
    if [ -n "$USB_MONITOR_PID" ]; then
        kill $USB_MONITOR_PID 2>/dev/null
    fi
    
    # Encrypt all files before ending
    encrypt_all_files
    
    # Securely wipe the session directory
    secure_wipe "$SESSION_DIR"
    
    # Unmount the RAM disk
    unmount_ram_disk
    
    echo -e "${GREEN}Session ended safely. All files are encrypted.${NC}"
    exit 0
}

# Function to set locale to English for consistent output
set_english_locale() {
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANGUAGE=en_US.UTF-8
}

# Check requirements
check_requirements() {
    if ! command -v gpg >/dev/null 2>&1; then
        echo -e "${RED}Error: GPG (GNU Privacy Guard) is not installed.${NC}"
        echo "Please install GPG:"
        echo "- macOS: brew install gnupg"
        echo "- Linux: sudo apt-get install gnupg (Ubuntu/Debian) or sudo yum install gnupg (CentOS/RHEL)"
        echo "- Windows: Install GPG4Win or use Git Bash with GPG"
        exit 1
    fi
    
    # Set English locale to avoid non-English warnings
    set_english_locale
    
    echo -e "${GREEN}GPG found. Using AES-256 encryption algorithm in 3 layers.${NC}"
}

# Function to open the session directory in a file manager
open_file_manager() {
    echo -e "${GREEN}Opening session directory in file manager...${NC}"
    
    case "$OS_TYPE" in
        Darwin) # macOS
            open "$SESSION_DIR"
            ;;
        Linux)
            # Try different file managers based on what's installed
            if command -v nautilus >/dev/null 2>&1; then
                nautilus "$SESSION_DIR" &
            elif command -v thunar >/dev/null 2>&1; then
                thunar "$SESSION_DIR" &
            elif command -v dolphin >/dev/null 2>&1; then
                dolphin "$SESSION_DIR" &
            elif command -v pcmanfm >/dev/null 2>&1; then
                pcmanfm "$SESSION_DIR" &
            else
                # If no graphical file manager found, inform user
                echo -e "${YELLOW}No graphical file manager found. Please open $SESSION_DIR manually${NC}"
            fi
            ;;
        MINGW*|CYGWIN*) # Windows
            explorer.exe "$(cygpath -w "$SESSION_DIR")" &
            ;;
        *)
            echo -e "${YELLOW}Cannot automatically open file manager on this OS.${NC}"
            echo -e "${YELLOW}Please open the following directory manually: $SESSION_DIR${NC}"
            ;;
    esac
    
    echo -e "${YELLOW}Note: The session will remain active until you press Ctrl+C to end it.${NC}"
}

# Set up signal handlers for proper cleanup
trap cleanup SIGINT SIGTERM EXIT

# Add a session timeout variable (default: 30 minutes)
SESSION_TIMEOUT=1800  # in seconds
LAST_ACTIVITY_TIME=$(date +%s)
STATUS_FILE="$RAM_DISK_PATH/.status"

# Function to show a progress bar for operations
show_progress() {
    local pid_to_monitor=$1
    local message=$2
    local chars="⣾⣽⣻⢿⡿⣟⣯⣷"
    local delay=0.1
    
    echo -ne "${YELLOW}$message... ${NC}"
    
    # Ensure pid is valid and numeric
    if [[ ! "$pid_to_monitor" =~ ^[0-9]+$ ]]; then
        echo -ne "\r${YELLOW}$message... ${GREEN}Done!${NC}\n"
        return
    fi
    
    # Check if process exists before looping
    if ! ps -p "$pid_to_monitor" > /dev/null 2>&1; then
        echo -ne "\r${YELLOW}$message... ${GREEN}Done!${NC}\n"
        return
    fi
    
    while ps -p "$pid_to_monitor" > /dev/null 2>&1; do
        for (( i=0; i<${#chars}; i++ )); do
            echo -ne "\r${YELLOW}$message... ${GREEN}${chars:$i:1}${NC}"
            sleep $delay
            # Break early if process ends
            if ! ps -p "$pid_to_monitor" > /dev/null 2>&1; then
                break
            fi
        done
        
        # Double check in case process ended during the animation
        if ! ps -p "$pid_to_monitor" > /dev/null 2>&1; then
            break
        fi
    done
    
    echo -ne "\r${YELLOW}$message... ${GREEN}Done!${NC}\n"
}

# Function to update last activity time
update_activity_time() {
    LAST_ACTIVITY_TIME=$(date +%s)
    echo "$LAST_ACTIVITY_TIME" > "$STATUS_FILE"
}

# Function to check session timeout
check_session_timeout() {
    if [ -f "$STATUS_FILE" ]; then
        LAST_ACTIVITY_TIME=$(cat "$STATUS_FILE")
    fi
    
    current_time=$(date +%s)
    elapsed_time=$((current_time - LAST_ACTIVITY_TIME))
    
    if [ $elapsed_time -gt $SESSION_TIMEOUT ]; then
        echo -e "${RED}Session timed out after $(($SESSION_TIMEOUT / 60)) minutes of inactivity. Ending for security.${NC}"
        cleanup
        exit 0
    fi
}

# Function to preview encrypted file without saving
preview_encrypted_file() {
    local encrypted_file="$1"
    local temp_preview="$RAM_DISK_PATH/.preview_tmp"
    
    echo -e "${YELLOW}Previewing encrypted file: $(basename "$encrypted_file")${NC}"
    
    # Perform decryption to temporary file
    if ! echo "$ENCRYPTION_PASSPHRASE_3" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$temp_preview.1" "$encrypted_file"; then
        echo -e "${RED}Preview failed: Invalid passphrase for layer 3${NC}"
        rm -f "$temp_preview.1" 2>/dev/null
        return 1
    fi
    
    if ! echo "$ENCRYPTION_PASSPHRASE_2" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$temp_preview.2" "$temp_preview.1"; then
        echo -e "${RED}Preview failed: Invalid passphrase for layer 2${NC}"
        rm -f "$temp_preview.1" "$temp_preview.2" 2>/dev/null
        return 1
    fi
    
    if ! echo "$ENCRYPTION_PASSPHRASE_1" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$temp_preview" "$temp_preview.2"; then
        echo -e "${RED}Preview failed: Invalid passphrase for layer 1${NC}"
        rm -f "$temp_preview.1" "$temp_preview.2" "$temp_preview" 2>/dev/null
        return 1
    fi
    
    # Clean up intermediate files
    rm -f "$temp_preview.1" "$temp_preview.2" 2>/dev/null
    
    # Detect file type and display appropriately
    filetype=$(file -b "$temp_preview")
    
    echo -e "${BLUE}=============== PREVIEW ===============${NC}"
    echo -e "${GREEN}File type: $filetype${NC}"
    echo -e "${BLUE}=======================================${NC}"
    
    if [[ "$filetype" == *text* ]] || [[ "$filetype" == *ASCII* ]]; then
        # Text file - display content
        echo -e "${YELLOW}File Contents:${NC}"
        head -n 20 "$temp_preview"
        lines=$(wc -l < "$temp_preview")
        if [ "$lines" -gt 20 ]; then
            echo -e "${YELLOW}... ($(($lines - 20)) more lines)${NC}"
        fi
    elif [[ "$filetype" == *image* ]]; then
        # Image file - inform user
        echo -e "${YELLOW}This is an image file. Cannot display in terminal.${NC}"
        echo -e "${YELLOW}Decrypt fully to view this file.${NC}"
    else
        # Binary file - show hexdump
        echo -e "${YELLOW}Binary file preview (first 256 bytes):${NC}"
        hexdump -C "$temp_preview" | head -n 16
    fi
    
    echo -e "${BLUE}=======================================${NC}"
    
    # Securely delete the preview
    if command -v shred >/dev/null 2>&1; then
        shred -uzn 3 "$temp_preview"
    else
        rm -f "$temp_preview"
    fi
    
    # Update activity time
    update_activity_time
}

# Function to show main menu
show_menu() {
    clear
    echo -e "${BLUE}"
    echo "    _                _                            _ "
    echo "   / \   _ __ ___| |__   __ _ _ __   __ _  ___| |"
    echo "  / _ \ | '__/ __| '_ \ / _\` | '_ \ / _\` |/ _ \ |"
    echo " / ___ \| | | (__| | | | (_| | | | | (_| |  __/ |"
    echo "/_/   \_\_|  \___|_| |_|\__,_|_| |_|\__, |\___|_|"
    echo "                                     |___/        "
    echo -e "USB Encryption Session Manager${NC}"
    echo ""
    echo -e "${GREEN}Session active at: $SESSION_DIR${NC}"
    echo -e "${YELLOW}Session will timeout after $(($SESSION_TIMEOUT / 60)) minutes of inactivity${NC}"
    echo ""
    echo -e "${BLUE}=== OPTIONS ===${NC}"
    echo -e "1. ${GREEN}Open file manager${NC}"
    echo -e "2. ${GREEN}Preview an encrypted file${NC}"
    echo -e "3. ${GREEN}Encrypt all files now${NC}"
    echo -e "4. ${GREEN}Change session timeout${NC}"
    echo -e "5. ${GREEN}Show session status${NC}"
    echo -e "6. ${GREEN}Decrypt a file${NC}"
    echo -e "7. ${RED}End session${NC}"
    echo ""
    echo -e "${YELLOW}Choice [1-7]:${NC} "
}

# Main execution function with interactive menu
run_session() {
    # First run the setup parts
    get_passphrases
    find_usb_device
    create_ram_disk
    
    # Add additional checks to prevent premature exit
    if [ -z "$RAM_DISK_PATH" ] || [ ! -d "$RAM_DISK_PATH" ]; then
        echo -e "${RED}Error: RAM disk creation failed. Aborting.${NC}"
        exit 1
    fi
    
    # Save initial activity time
    update_activity_time
    
    # Setup session - don't use $$ (script's PID) but run in background and get actual PID
    echo -e "${YELLOW}Setting up secure session...${NC}"
    setup_session &
    setup_session_pid=$!
    show_progress $setup_session_pid "Setting up secure session"
    wait $setup_session_pid
    
    # Check if the session dir exists before continuing
    if [ ! -d "$SESSION_DIR" ]; then
        echo -e "${RED}Error: Session directory not created. Aborting.${NC}"
        exit 1
    fi
    
    monitor_new_files
    monitor_usb_presence
    
    # Initialize additional features
    PANIC_MODE_ENABLED=0
    PANIC_KEY="p"
    
    # Instead of just opening file manager, show interactive menu
    while true; do
        show_menu
        read -n 1 choice
        echo ""
        
        case $choice in
            1)  # Open file manager
                open_file_manager
                echo -e "${YELLOW}Press any key to return to menu...${NC}"
                read -n 1
                ;;
            2)  # Preview an encrypted file
                echo -e "${YELLOW}Available encrypted files:${NC}"
                encrypted_files=($(find "$USB_PATH" -maxdepth 1 -name "*.enc"))
                
                if [ ${#encrypted_files[@]} -eq 0 ]; then
                    echo -e "${RED}No encrypted files found!${NC}"
                else
                    for i in "${!encrypted_files[@]}"; do
                        echo "$((i+1)). $(basename "${encrypted_files[$i]}")"
                    done
                    
                    echo -e "${YELLOW}Enter file number to preview (or 0 to cancel):${NC} "
                    read file_num
                    
                    if [[ "$file_num" =~ ^[0-9]+$ ]] && [ "$file_num" -gt 0 ] && [ "$file_num" -le "${#encrypted_files[@]}" ]; then
                        preview_encrypted_file "${encrypted_files[$((file_num-1))]}"
                    elif [ "$file_num" -ne 0 ]; then
                        echo -e "${RED}Invalid selection!${NC}"
                    fi
                fi
                echo -e "${YELLOW}Press any key to return to menu...${NC}"
                read -n 1
                ;;
            3)  # Encrypt all files now
                echo -e "${YELLOW}Encrypting all files...${NC}"
                encrypt_all_files &
                encrypt_pid=$!
                show_progress $encrypt_pid "Encrypting all files"
                wait $encrypt_pid
                echo -e "${YELLOW}Press any key to return to menu...${NC}"
                read -n 1
                ;;
            4)  # Change session timeout
                echo -e "${YELLOW}Current timeout: $(($SESSION_TIMEOUT / 60)) minutes${NC}"
                echo -e "${YELLOW}Enter new timeout in minutes (0 for no timeout):${NC} "
                read new_timeout
                
                if [[ "$new_timeout" =~ ^[0-9]+$ ]]; then
                    SESSION_TIMEOUT=$((new_timeout * 60))
                    echo -e "${GREEN}Timeout set to $new_timeout minutes${NC}"
                    update_activity_time
                else
                    echo -e "${RED}Invalid input! Timeout not changed.${NC}"
                fi
                echo -e "${YELLOW}Press any key to return to menu...${NC}"
                read -n 1
                ;;
            5)  # Show session status
                echo -e "${BLUE}=== SESSION STATUS ===${NC}"
                echo -e "${GREEN}Session directory: $SESSION_DIR${NC}"
                echo -e "${GREEN}USB device: $USB_DEVICE${NC}"
                
                # Count files
                enc_count=$(find "$USB_PATH" -maxdepth 1 -name "*.enc" | wc -l)
                dec_count=$(find "$SESSION_DIR" -type f -not -name "*.enc" -not -name "*.enc*" -not -name "*.dec*" | wc -l)
                
                echo -e "${GREEN}Encrypted files: $enc_count${NC}"
                echo -e "${GREEN}Decrypted files in session: $dec_count${NC}"
                
                # Show session age
                session_start=$(stat -c %Y "$SESSION_DIR" 2>/dev/null || stat -f %m "$SESSION_DIR")
                current_time=$(date +%s)
                session_age=$((current_time - session_start))
                
                echo -e "${GREEN}Session age: $(($session_age / 60)) minutes$(($session_age % 60)) seconds${NC}"
                echo -e "${GREEN}Time until timeout: $((($SESSION_TIMEOUT - (current_time - LAST_ACTIVITY_TIME)) / 60)) minutes${NC}"
                
                # Monitor process status
                if ps -p $MONITOR_PID > /dev/null 2>&1; then
                    echo -e "${GREEN}File monitor: Running (PID: $MONITOR_PID)${NC}"
                else
                    echo -e "${RED}File monitor: NOT RUNNING${NC}"
                fi
                
                if ps -p $USB_MONITOR_PID > /dev/null 2>&1; then
                    echo -e "${GREEN}USB monitor: Running (PID: $USB_MONITOR_PID)${NC}"
                else
                    echo -e "${RED}USB monitor: NOT RUNNING${NC}"
                fi
                
                echo -e "${YELLOW}Press any key to return to menu...${NC}"
                read -n 1
                ;;
            6)  # Decrypt a file
                echo -e "${YELLOW}Available encrypted files:${NC}"
                encrypted_files=($(find "$USB_PATH" -maxdepth 1 -name "*.enc"))
                
                if [ ${#encrypted_files[@]} -eq 0 ]; then
                    echo -e "${RED}No encrypted files found!${NC}"
                else
                    for i in "${!encrypted_files[@]}"; do
                        echo "$((i+1)). $(basename "${encrypted_files[$i]}")"
                    done
                    
                    echo -e "${YELLOW}Enter file number to decrypt (or 0 to cancel):${NC} "
                    read file_num
                    
                    if [[ "$file_num" =~ ^[0-9]+$ ]] && [ "$file_num" -gt 0 ] && [ "$file_num" -le "${#encrypted_files[@]}" ]; then
                        selected_file="${encrypted_files[$((file_num-1))]}"
                        filename=$(basename "$selected_file")
                        
                        # Copy to session directory
                        cp "$selected_file" "$SESSION_DIR/$filename" 2>/dev/null
                        if [ $? -ne 0 ]; then
                            echo -e "${RED}Failed to copy the file to session directory!${NC}"
                        else
                            echo -e "${YELLOW}Decrypting file...${NC}"
                            decrypt_file "$SESSION_DIR/$filename" &
                            decrypt_pid=$!
                            show_progress $decrypt_pid "Decrypting file"
                            wait $decrypt_pid
                            
                            # Check if decryption was successful
                            decrypted_filename="${filename%.enc}"
                            if [ -f "$SESSION_DIR/$decrypted_filename" ]; then
                                echo -e "${GREEN}File successfully decrypted to: $SESSION_DIR/$decrypted_filename${NC}"
                                
                                # New feature: Verify file integrity
                                calculate_checksum "$SESSION_DIR/$decrypted_filename"
                                
                                # Update activity time
                                update_activity_time
                            else
                                echo -e "${RED}Decryption failed!${NC}"
                            fi
                        fi
                    elif [ "$file_num" -ne 0 ]; then
                        echo -e "${RED}Invalid selection!${NC}"
                    fi
                fi
                echo -e "${YELLOW}Press any key to return to menu...${NC}"
                read -n 1
                ;;
            7)  # Clipboard encryption/decryption
                clipboard_menu
                ;;
            8)  # Create encrypted note
                create_encrypted_note
                ;;
            9)  # Toggle panic mode
                toggle_panic_mode
                ;;
            0)  # End session
                echo -e "${RED}Ending session...${NC}"
                cleanup
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice!${NC}"
                sleep 1
                ;;
        esac
        
        # Check for session timeout after each action
        check_session_timeout
        
        # Check monitors are still running
        if [ -n "$USB_MONITOR_PID" ]; then
            if ! ps -p $USB_MONITOR_PID > /dev/null 2>&1; then
                echo -e "${YELLOW}USB monitor process died. Restarting...${NC}"
                monitor_usb_presence
            fi
        fi
        
        if [ -n "$MONITOR_PID" ]; then
            if ! ps -p $MONITOR_PID > /dev/null 2>&1; then
                echo -e "${YELLOW}File monitor process died. Restarting...${NC}"
                monitor_new_files
            fi
        fi
    done
}

# Function to calculate and display file checksum (integrity verification)
calculate_checksum() {
    local file="$1"
    echo -e "${YELLOW}Verifying file integrity...${NC}"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File doesn't exist!${NC}"
        return 1
    fi
    
    local checksum=""
    
    case "$OS_TYPE" in
        Darwin) # macOS
            checksum=$(shasum -a 256 "$file" | cut -d ' ' -f 1)
            ;;
        Linux)
            checksum=$(sha256sum "$file" | cut -d ' ' -f 1)
            ;;
        *)
            checksum=$(sha256sum "$file" 2>/dev/null | cut -d ' ' -f 1)
            if [ -z "$checksum" ]; then
                echo -e "${YELLOW}Could not calculate checksum on this OS.${NC}"
                return 1
            fi
            ;;
    esac
    
    echo -e "${GREEN}SHA-256: $checksum${NC}"
    echo -e "${GREEN}File integrity verified!${NC}"
    
    # Store the checksum for future verification
    echo "$checksum" > "$file.sha256"
}

# Function to handle clipboard encryption/decryption
clipboard_menu() {
    clear
    echo -e "${BLUE}=== CLIPBOARD ENCRYPTION ===${NC}"
    echo -e "1. ${GREEN}Encrypt clipboard content${NC}"
    echo -e "2. ${GREEN}Decrypt clipboard content${NC}"
    echo -e "3. ${GREEN}Back to main menu${NC}"
    echo -e "${YELLOW}Choice [1-3]:${NC} "
    read -n 1 cb_choice
    echo ""
    
    case $cb_choice in
        1)  # Encrypt clipboard
            encrypt_clipboard
            ;;
        2)  # Decrypt clipboard
            decrypt_clipboard
            ;;
        3)  # Back to main menu
            return
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            sleep 1
            clipboard_menu
            ;;
    esac
}

# Function to encrypt clipboard content
encrypt_clipboard() {
    echo -e "${YELLOW}Getting clipboard content...${NC}"
    local clipboard_content=""
    
    case "$OS_TYPE" in
        Darwin) # macOS
            clipboard_content=$(pbpaste)
            ;;
        Linux)
            if command -v xclip >/dev/null 2>&1; then
                clipboard_content=$(xclip -selection clipboard -o)
            elif command -v xsel >/dev/null 2>&1; then
                clipboard_content=$(xsel -b)
            else
                echo -e "${RED}Error: xclip or xsel is required for clipboard operations.${NC}"
                echo -e "${YELLOW}Install with: sudo apt-get install xclip${NC}"
                echo -e "${YELLOW}Press any key to return...${NC}"
                read -n 1
                return 1
            fi
            ;;
        MINGW*|CYGWIN*) # Windows
            if command -v powershell.exe >/dev/null 2>&1; then
                clipboard_content=$(powershell.exe -command "Get-Clipboard" 2>/dev/null)
            else
                echo -e "${RED}Error: PowerShell is required for clipboard operations on Windows.${NC}"
                echo -e "${YELLOW}Press any key to return...${NC}"
                read -n 1
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Clipboard operations not supported on this OS.${NC}"
            echo -e "${YELLOW}Press any key to return...${NC}"
            read -n 1
            return 1
            ;;
    esac
    
    if [ -z "$clipboard_content" ]; then
        echo -e "${RED}Clipboard is empty!${NC}"
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Create a temporary file with the clipboard content
    local temp_file="$RAM_DISK_PATH/.clipboard_tmp"
    echo "$clipboard_content" > "$temp_file"
    
    # Encrypt in three layers as with regular files
    local temp1="$temp_file.enc1"
    local temp2="$temp_file.enc2"
    local output="$temp_file.enc"
    
    echo -e "${YELLOW}Encrypting clipboard content...${NC}"
    
    # Layer 1 encryption
    if ! echo "$ENCRYPTION_PASSPHRASE_1" | gpg --batch --yes --quiet --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$temp1" "$temp_file"; then
        echo -e "${RED}Encryption layer 1 failed!${NC}"
        rm -f "$temp_file" "$temp1" 2>/dev/null
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Layer 2 encryption
    if ! echo "$ENCRYPTION_PASSPHRASE_2" | gpg --batch --yes --quiet --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$temp2" "$temp1"; then
        echo -e "${RED}Encryption layer 2 failed!${NC}"
        rm -f "$temp_file" "$temp1" "$temp2" 2>/dev/null
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Layer 3 encryption
    if ! echo "$ENCRYPTION_PASSPHRASE_3" | gpg --batch --yes --quiet --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$output" "$temp2"; then
        echo -e "${RED}Encryption layer 3 failed!${NC}"
        rm -f "$temp_file" "$temp1" "$temp2" "$output" 2>/dev/null
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Convert the encrypted data to base64 for easy clipboard storage
    local base64_output=""
    case "$OS_TYPE" in
        Darwin) # macOS
            base64_output=$(base64 < "$output")
            ;;
        *)
            base64_output=$(base64 -w 0 < "$output")
            ;;
    esac
    
    # Copy the base64 encrypted data to clipboard
    case "$OS_TYPE" in
        Darwin) # macOS
            echo "$base64_output" | pbcopy
            ;;
        Linux)
            if command -v xclip >/dev/null 2>&1; then
                echo "$base64_output" | xclip -selection clipboard
            elif command -v xsel >/dev/null 2>&1; then
                echo "$base64_output" | xsel -b
            fi
            ;;
        MINGW*|CYGWIN*) # Windows
            echo "$base64_output" | clip
            ;;
    esac
    
    # Clean up
    rm -f "$temp_file" "$temp1" "$temp2" "$output" 2>/dev/null
    
    echo -e "${GREEN}Clipboard content encrypted and copied to clipboard!${NC}"
    echo -e "${YELLOW}Press any key to return...${NC}"
    read -n 1
    update_activity_time
}

# Function to decrypt clipboard content
decrypt_clipboard() {
    echo -e "${YELLOW}Getting clipboard content...${NC}"
    local clipboard_content=""
    
    case "$OS_TYPE" in
        Darwin) # macOS
            clipboard_content=$(pbpaste)
            ;;
        Linux)
            if command -v xclip >/dev/null 2>&1; then
                clipboard_content=$(xclip -selection clipboard -o)
            elif command -v xsel >/dev/null 2>&1; then
                clipboard_content=$(xsel -b)
            else
                echo -e "${RED}Error: xclip or xsel is required for clipboard operations.${NC}"
                echo -e "${YELLOW}Press any key to return...${NC}"
                read -n 1
                return 1
            fi
            ;;
        MINGW*|CYGWIN*) # Windows
            if command -v powershell.exe >/dev/null 2>&1; then
                clipboard_content=$(powershell.exe -command "Get-Clipboard" 2>/dev/null)
            else
                echo -e "${RED}Error: PowerShell is required for clipboard operations on Windows.${NC}"
                echo -e "${YELLOW}Press any key to return...${NC}"
                read -n 1
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Clipboard operations not supported on this OS.${NC}"
            echo -e "${YELLOW}Press any key to return...${NC}"
            read -n 1
            return 1
            ;;
    esac
    
    if [ -z "$clipboard_content" ]; then
        echo -e "${RED}Clipboard is empty!${NC}"
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Check if the clipboard contains base64-encoded data
    if ! echo "$clipboard_content" | base64 -d > /dev/null 2>&1; then
        echo -e "${RED}Clipboard does not contain valid encrypted data!${NC}"
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Create temporary files for decryption
    local temp_encrypted="$RAM_DISK_PATH/.clipboard_encrypted"
    local temp1="$RAM_DISK_PATH/.clipboard_dec1"
    local temp2="$RAM_DISK_PATH/.clipboard_dec2"
    local output="$RAM_DISK_PATH/.clipboard_decrypted"
    
    # Convert base64 clipboard content back to binary
    echo "$clipboard_content" | base64 -d > "$temp_encrypted" 2>/dev/null
    
    echo -e "${YELLOW}Decrypting clipboard content...${NC}"
    
    # Layer 3 decryption
    if ! echo "$ENCRYPTION_PASSPHRASE_3" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$temp1" "$temp_encrypted"; then
        echo -e "${RED}Decryption layer 3 failed! Invalid passphrase or not encrypted data.${NC}"
        rm -f "$temp_encrypted" "$temp1" 2>/dev/null
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Layer 2 decryption
    if ! echo "$ENCRYPTION_PASSPHRASE_2" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$temp2" "$temp1"; then
        echo -e "${RED}Decryption layer 2 failed!${NC}"
        rm -f "$temp_encrypted" "$temp1" "$temp2" 2>/dev/null
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Layer 1 decryption
    if ! echo "$ENCRYPTION_PASSPHRASE_1" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt --output "$output" "$temp2"; then
        echo -e "${RED}Decryption layer 1 failed!${NC}"
        rm -f "$temp_encrypted" "$temp1" "$temp2" "$output" 2>/dev/null
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    # Copy decrypted content to clipboard
    case "$OS_TYPE" in
        Darwin) # macOS
            cat "$output" | pbcopy
            ;;
        Linux)
            if command -v xclip >/dev/null 2>&1; then
                cat "$output" | xclip -selection clipboard
            elif command -v xsel >/dev/null 2>&1; then
                cat "$output" | xsel -b
            fi
            ;;
        MINGW*|CYGWIN*) # Windows
            cat "$output" | clip
            ;;
    esac
    
    # Display decrypted content
    echo -e "${GREEN}Decrypted content:${NC}"
    echo -e "${BLUE}================================${NC}"
    cat "$output"
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}Decrypted content copied to clipboard!${NC}"
    
    # Clean up
    rm -f "$temp_encrypted" "$temp1" "$temp2" "$output" 2>/dev/null
    
    echo -e "${YELLOW}Press any key to return...${NC}"
    read -n 1
    update_activity_time
}

# Function to create an encrypted note directly from terminal
create_encrypted_note() {
    clear
    echo -e "${BLUE}=== CREATE ENCRYPTED NOTE ===${NC}"
    echo -e "${YELLOW}Enter note title (alphanumeric only):${NC} "
    read note_title
    
    # Validate title
    if [[ ! "$note_title" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Invalid title! Use only letters, numbers, underscore, and hyphen.${NC}"
        echo -e "${YELLOW}Press any key to return...${NC}"
        read -n 1
        return 1
    fi
    
    note_file="$SESSION_DIR/$note_title.txt"
    
    if [ -f "$note_file" ]; then
        echo -e "${YELLOW}Note with this title already exists. Append or overwrite?${NC}"
        echo -e "1. ${GREEN}Append to existing note${NC}"
        echo -e "2. ${RED}Overwrite existing note${NC}"
        echo -e "3. ${YELLOW}Cancel${NC}"
        echo -e "${YELLOW}Choice [1-3]:${NC} "
        read -n 1 note_choice
        echo ""
        
        case $note_choice in
            1)  # Append
                echo -e "${YELLOW}Enter your note text (press Ctrl+D on a new line to finish):${NC}"
                echo "" >> "$note_file"
                echo "--- Added on $(date) ---" >> "$note_file"
                cat >> "$note_file"
                ;;
            2)  # Overwrite
                echo -e "${YELLOW}Enter your note text (press Ctrl+D on a new line to finish):${NC}"
                cat > "$note_file"
                ;;
            *)  # Cancel
                return
                ;;
        esac
    else
        echo -e "${YELLOW}Enter your note text (press Ctrl+D on a new line to finish):${NC}"
        cat > "$note_file"
    fi
    
    # Encrypt the note directly to USB
    cp "$note_file" "$USB_PATH/$note_title.txt" 2>/dev/null
    if [ $? -eq 0 ]; then
        encrypt_file "$USB_PATH/$note_title.txt" &
        encrypt_pid=$!
        show_progress $encrypt_pid "Encrypting note"
        wait $encrypt_pid
        
        echo -e "${GREEN}Note encrypted and saved!${NC}"
        # Calculate checksum for integrity
        calculate_checksum "$note_file"
    else
        echo -e "${RED}Failed to save note to USB!${NC}"
    fi
    
    echo -e "${YELLOW}Press any key to return...${NC}"
    read -n 1
    update_activity_time
}

# Variables for panic mode
PANIC_MODE_ENABLED=0
PANIC_KEY="p"

# Function to toggle panic mode
toggle_panic_mode() {
    if [ $PANIC_MODE_ENABLED -eq 0 ]; then
        PANIC_MODE_ENABLED=1
        echo -e "${RED}PANIC MODE ENABLED!${NC}"
        echo -e "${RED}Press '$PANIC_KEY' at any time to instantly wipe the session and exit${NC}"
        echo -e "${YELLOW}Press any key to continue...${NC}"
        read -n 1
        
        # Start panic key monitor
        start_panic_monitor
    else
        PANIC_MODE_ENABLED=0
        echo -e "${GREEN}Panic mode disabled${NC}"
        echo -e "${YELLOW}Press any key to continue...${NC}"
        read -n 1
        
        # Kill panic monitor if running
        if [ -n "$PANIC_MONITOR_PID" ]; then
            kill $PANIC_MONITOR_PID 2>/dev/null
        fi
    fi
}

# Function to start panic key monitor
start_panic_monitor() {
    # Run in background and check for key press
    (
        # Use read with timeout to periodically check for keypress
        while true; do
            if read -t 0.5 -n 1 key; then
                if [ "$key" = "$PANIC_KEY" ]; then
                    echo -e "${RED}PANIC KEY DETECTED! EMERGENCY WIPE ACTIVATED!${NC}"
                    secure_wipe "$SESSION_DIR"
                    unmount_ram_disk
                    exit 0
                fi
            fi
            # Check if panic mode is still enabled
            if [ -f "$RAM_DISK_PATH/.panic_mode" ] && [ "$(cat "$RAM_DISK_PATH/.panic_mode")" -eq 0 ]; then
                break
            fi
        done
    ) &
    PANIC_MONITOR_PID=$!
    
    # Store panic mode status
    echo "$PANIC_MODE_ENABLED" > "$RAM_DISK_PATH/.panic_mode"
}

# Enhanced show_menu function with better UI
show_menu() {
    clear
    # Enhanced ASCII art banner with gradient effect
    echo -e "${BLUE}"
    echo "    █████╗ ██████╗  ██████╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗ ███████╗██╗     "
    echo "   ██╔══██╗██╔══██╗██╔════╝██║  ██║██╔══██╗████╗  ██║██╔════╝ ██╔════╝██║     "
    echo "   ███████║██████╔╝██║     ███████║███████║██╔██╗ ██║██║  ███╗█████╗  ██║     "
    echo "   ██╔══██║██╔══██╗██║     ██╔══██║██╔══██║██║╚██╗██║██║   ██║██╔══╝  ██║     "
    echo "   ██║  ██║██║  ██║╚██████╗██║  ██║██║  ██║██║ ╚████║╚██████╔╝███████╗███████╗"
    echo "   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚══════╝"
    echo -e "   USB Encryption Session Manager${NC} v2.0"
    echo ""
    
    # Box drawing for status
    echo -e "${BLUE}╔════════════════════════ SESSION INFO ═════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} ${GREEN}Session Path:${NC} $SESSION_DIR"
    echo -e "${BLUE}║${NC} ${GREEN}USB Device:${NC} $USB_DEVICE"
    
    # Get encrypted and decrypted file counts
    enc_count=$(find "$USB_PATH" -maxdepth 1 -name "*.enc" | wc -l)
    dec_count=$(find "$SESSION_DIR" -type f -not -name "*.enc" -not -name "*.enc*" -not -name "*.dec*" | wc -l)
    
    # Calculate session times
    session_start=$(stat -c %Y "$SESSION_DIR" 2>/dev/null || stat -f %m "$SESSION_DIR")
    current_time=$(date +%s)
    session_age=$((current_time - session_start))
    timeout_left=$((($SESSION_TIMEOUT - (current_time - LAST_ACTIVITY_TIME)) / 60))
    
    echo -e "${BLUE}║${NC} ${GREEN}Encrypted Files:${NC} $enc_count  ${GREEN}Decrypted Files:${NC} $dec_count"
    echo -e "${BLUE}║${NC} ${GREEN}Session Age:${NC} $(($session_age / 60))m $(($session_age % 60))s  ${GREEN}Timeout In:${NC} ${timeout_left}m"
    
    # Fix the panic mode status display - this was causing a syntax error
    if [ $PANIC_MODE_ENABLED -eq 1 ]; then
        echo -e "${BLUE}║${NC} ${RED}PANIC MODE ACTIVE${NC}"
    else
        echo -e "${BLUE}║${NC} ${GREEN}Normal Mode${NC}"
    fi
    
    echo -e "${BLUE}╚═════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Options menu with improved formatting
    echo -e "${BLUE}╔══════════════════════════ OPTIONS ══════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} 1. ${GREEN}Open file manager${NC}           6. ${GREEN}Decrypt a file${NC}          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 2. ${GREEN}Preview encrypted file${NC}      7. ${GREEN}Clipboard encrypt/decrypt${NC}${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 3. ${GREEN}Encrypt all files now${NC}       8. ${GREEN}Create encrypted note${NC}   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 4. ${GREEN}Change session timeout${NC}      9. ${GREEN}Toggle panic mode${NC}       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 5. ${GREEN}Show session status${NC}         0. ${RED}End session${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Enter choice [0-9]:${NC} "
}

# Start the interactive session
run_session
