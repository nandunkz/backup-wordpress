#!/bin/bash

# WordPress Restore Script
# Created on August 25, 2025
# Usage: ./restore.sh [--gdrive=remote_name]
#   --gdrive=remote_name : List and restore backups from Google Drive using rclone

# Parse command line arguments
GDRIVE_REMOTE=""
for arg in "$@"; do
    case $arg in
        --gdrive=*)
            GDRIVE_REMOTE="${arg#*=}"
            # Early validation: Check if rclone is installed when --gdrive is used
            if ! command -v rclone &> /dev/null; then
                echo "Error: Harus memasang rclone terlebih dahulu!"
                echo "Install rclone first: https://rclone.org/install/"
                exit 1
            fi
            shift
            ;;
        --help|-h)
            echo "WordPress Restore Script"
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --gdrive=REMOTE    List and restore backups from Google Drive using rclone remote"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                 Restore from local backups only"
            echo "  $0 --gdrive=ndev   List and restore backups from Google Drive using 'ndev' remote"
            echo ""
            echo "Available rclone remotes:"
            rclone listremotes 2>/dev/null || echo "  (rclone not configured)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--gdrive=remote_name]"
            echo "Use --help for more information"
            exit 1
            ;;
    esac
done

# Set variables
BACKUP_DIR="$HOME/backups"
WP_DIR="$HOME/public_html"
DB_CONFIG_FILE="${WP_DIR}/wp-config.php"

# Handle Google Drive backups if requested
if [ -n "$GDRIVE_REMOTE" ]; then
    echo "==== Google Drive Backup Restore ===="
    echo "Remote: $GDRIVE_REMOTE"
    
    # Check if the remote exists in rclone config
    if ! rclone listremotes | grep -q "^${GDRIVE_REMOTE}:$"; then
        echo "Error: Remote '$GDRIVE_REMOTE' not found in rclone configuration"
        echo "Available remotes:"
        rclone listremotes
        exit 1
    fi
    
    # List available backups from Google Drive
    REMOTE_BACKUP_DIR="${GDRIVE_REMOTE}:backups/wordpress"
    echo "Available backups from Google Drive:"
    
    # Get list of backup files from Google Drive
    GDRIVE_BACKUPS=$(rclone ls "$REMOTE_BACKUP_DIR" 2>/dev/null | grep "\.tar\.gz$" | awk '{print $2}' | sort -r)
    
    if [ -z "$GDRIVE_BACKUPS" ]; then
        echo "No backup files found in Google Drive at $REMOTE_BACKUP_DIR"
        exit 1
    fi
    
    # Display available backups with numbers
    echo "Select a backup to restore:"
    echo "0) Use latest backup automatically"
    
    IFS=$'\n'
    BACKUP_ARRAY=($GDRIVE_BACKUPS)
    unset IFS
    
    for i in "${!BACKUP_ARRAY[@]}"; do
        echo "$((i+1))) ${BACKUP_ARRAY[$i]}"
    done
    
    echo "Enter your choice (0-${#BACKUP_ARRAY[@]}):"
    read CHOICE
    
    # Handle user choice
    if [ "$CHOICE" = "0" ] || [ -z "$CHOICE" ]; then
        SELECTED_BACKUP="${BACKUP_ARRAY[0]}"
        echo "Using latest backup: $SELECTED_BACKUP"
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#BACKUP_ARRAY[@]}" ]; then
        SELECTED_BACKUP="${BACKUP_ARRAY[$((CHOICE-1))]}"
        echo "Selected backup: $SELECTED_BACKUP"
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi
    
    # Download the selected backup
    echo "Downloading backup from Google Drive..."
    BACKUP_FILE="${BACKUP_DIR}/${SELECTED_BACKUP}"
    
    # Create local backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    if rclone copy "${REMOTE_BACKUP_DIR}/${SELECTED_BACKUP}" "$BACKUP_DIR" --progress; then
        echo "✓ Backup successfully downloaded from Google Drive: $BACKUP_FILE"
        BACKUP_FILE_NAME="$SELECTED_BACKUP"
    else
        echo "✗ Error: Failed to download backup from Google Drive"
        exit 1
    fi
    
else
    # Show available local backups
    echo "Available local backups:"
    ls -lh "$BACKUP_DIR" | grep "wordpress_" | grep ".tar.gz"
    
    if [ $? -ne 0 ]; then
        echo "No backup files found in $BACKUP_DIR"
        exit 1
    fi
    
    # Ask user to select backup file
    echo "Enter the backup filename to restore (e.g., wordpress_2025-08-25_12-00-00.tar.gz):"
    echo "Press Enter without input to use the latest backup:"
    read BACKUP_FILE_NAME
    
    # If no input provided, use the latest backup
    if [ -z "$BACKUP_FILE_NAME" ]; then
        BACKUP_FILE_NAME=$(ls -t "$BACKUP_DIR"/wordpress_*.tar.gz 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
        if [ -z "$BACKUP_FILE_NAME" ]; then
            echo "Error: No backup files found in $BACKUP_DIR"
            exit 1
        fi
        echo "Using latest backup: $BACKUP_FILE_NAME"
    fi
fi

# Set the backup file path
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE_NAME}"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Confirm restoration
echo "WARNING: This will overwrite your current WordPress installation and database."
echo "Are you sure you want to restore from $BACKUP_FILE_NAME? (yes/no)"
read CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
    echo "Restoration cancelled."
    exit 0
fi

# Create a temporary directory for restoration
TEMP_DIR="/tmp/wp_restore_$(date +%s)"
mkdir -p "$TEMP_DIR"

# Extract backup archive
echo "Extracting backup archive..."
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

if [ $? -ne 0 ]; then
    echo "Error: Failed to extract backup archive"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check for database dump file (could be in root of temp dir or in a subfolder)
DB_DUMP_FILE=$(find "$TEMP_DIR" -name "*_db_*.sql" | head -n 1)

if [ -z "$DB_DUMP_FILE" ]; then
    # Try looking for any .sql file
    DB_DUMP_FILE=$(find "$TEMP_DIR" -name "*.sql" | head -n 1)
fi

if [ -z "$DB_DUMP_FILE" ]; then
    echo "Error: No database dump file found in the backup"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Extract database credentials from wp-config.php
if [ -f "$DB_CONFIG_FILE" ]; then
    DB_NAME=$(grep DB_NAME "$DB_CONFIG_FILE" | cut -d \' -f 4)
    DB_USER=$(grep DB_USER "$DB_CONFIG_FILE" | cut -d \' -f 4)
    DB_PASS=$(grep DB_PASSWORD "$DB_CONFIG_FILE" | cut -d \' -f 4)
    DB_HOST=$(grep DB_HOST "$DB_CONFIG_FILE" | cut -d \' -f 4)
    
    # Check if we got all the database details
    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_HOST" ]; then
        echo "Error: Could not extract database credentials from wp-config.php"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    echo "Error: wp-config.php file not found at $DB_CONFIG_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Restore database
echo "Restoring database..."
DB_HOST="127.0.0.1"
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$DB_DUMP_FILE"

if [ $? -eq 0 ]; then
    echo "Database restore successful"
else
    echo "Error: Database restore failed"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Backup current WordPress installation
CURRENT_BACKUP="${BACKUP_DIR}/pre_restore_$(date +"%Y-%m-%d_%H-%M-%S").tar.gz"
echo "Creating backup of current WordPress installation: $CURRENT_BACKUP"
tar -czf "$CURRENT_BACKUP" -C "$(dirname "$WP_DIR")" "$(basename "$WP_DIR")"

# Restore WordPress files
echo "Restoring WordPress files..."
# Look for the WordPress directory in the backup
WP_FILES=$(find "$TEMP_DIR" -name "public_html" -type d | head -n 1)

if [ -z "$WP_FILES" ]; then
    # If public_html not found, check if files are directly in temp dir
    if [ -f "$TEMP_DIR/wp-config.php" ] || [ -d "$TEMP_DIR/wp-content" ]; then
        WP_FILES="$TEMP_DIR"
    else
        echo "Error: WordPress files not found in the backup"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# Remove current WordPress installation
echo "Removing current WordPress installation..."
rm -rf "${WP_DIR}"/*

# Copy restored files
echo "Copying restored files to ${WP_DIR}..."
if [ "$(basename "$WP_FILES")" = "public_html" ]; then
    # If we found a public_html directory, copy its contents
    cp -a "${WP_FILES}"/* "${WP_DIR}"/
else
    # If files are directly in temp dir, copy them (excluding .sql files)
    find "$WP_FILES" -maxdepth 1 -type f ! -name "*.sql" -exec cp -a {} "${WP_DIR}/" \;
    find "$WP_FILES" -maxdepth 1 -type d ! -path "$WP_FILES" -exec cp -a {} "${WP_DIR}/" \;
fi

if [ $? -ne 0 ]; then
    echo "Error: Failed to copy WordPress files"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clean up
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

# Optionally clean up downloaded backup file from Google Drive
if [ -n "$GDRIVE_REMOTE" ]; then
    echo "Remove downloaded backup file? (y/N):"
    read REMOVE_BACKUP
    if [ "$REMOVE_BACKUP" = "y" ] || [ "$REMOVE_BACKUP" = "Y" ]; then
        rm -f "$BACKUP_FILE"
        echo "Downloaded backup file removed: $BACKUP_FILE"
    else
        echo "Downloaded backup file kept: $BACKUP_FILE"
    fi
fi

echo "==== Restoration Completed ===="
if [ -n "$GDRIVE_REMOTE" ]; then
    echo "WordPress has been restored from Google Drive backup: $BACKUP_FILE_NAME"
else
    echo "WordPress has been restored from local backup: $BACKUP_FILE_NAME"
fi
echo "Previous installation backed up to: $CURRENT_BACKUP"
echo "Restoration completed at: $(date)"
echo "============================================"

# Suggest fixing permissions
echo "You may need to fix permissions on your WordPress files:"
echo "find ${WP_DIR} -type d -exec chmod 755 {} \;"
echo "find ${WP_DIR} -type f -exec chmod 644 {} \;"
echo "chown -R your_user:your_group ${WP_DIR}"
