#!/bin/bash

# WordPress Backup Script
# Created on August 25, 2025
# Usage: ./backup.sh [--gdrive=remote_name]
#   --gdrive=remote_name : Upload backup to Google Drive using rclone

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
            echo "WordPress Backup Script"
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --gdrive=REMOTE    Upload backup to Google Drive using rclone remote"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                 Create local backup only"
            echo "  $0 --gdrive=ndev   Create backup and upload to Google Drive using 'ndev' remote"
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
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="$HOME/backups"
SITE_NAME="wordpress"
BACKUP_FILE="${BACKUP_DIR}/${SITE_NAME}_${TIMESTAMP}.tar.gz"
WP_DIR="$HOME/public_html"
DB_CONFIG_FILE="${WP_DIR}/wp-config.php"

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "Created backup directory: $BACKUP_DIR"
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
        exit 1
    fi
else
    echo "Error: wp-config.php file not found at $DB_CONFIG_FILE"
    exit 1
fi

echo "==== Starting WordPress Backup ===="
echo "Site: $SITE_NAME"
echo "Timestamp: $TIMESTAMP"

# Backup database
echo "Backing up database: $DB_NAME"
DB_HOST="127.0.0.1"
# Create database backup in a temporary location first
TEMP_DB_BACKUP="/tmp/${SITE_NAME}_db_${TIMESTAMP}.sql"
mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$TEMP_DB_BACKUP"

if [ $? -eq 0 ]; then
    echo "Database backup successful: $TEMP_DB_BACKUP"
else
    echo "Error: Database backup failed"
    exit 1
fi

# Backup WordPress files
echo "Backing up WordPress files from: $WP_DIR"
# jika folder $HOME/tmp tidak ada
if [ ! -d "$HOME/tmp" ]; then
    mkdir -p "$HOME/tmp"
fi
# Create a list of exclusions for files that might change during backup
cat > $HOME/tmp/wp-backup-exclude.txt << EOF
*.log
*.tmp
cache/
wp-content/cache/
wp-content/uploads/wp-cache-*
wp-content/debug.log
wp-content/upgrade/
wp-content/backup*
wp-content/advanced-cache.php
wp-content/object-cache.php
wp-content/uploads/snapshots/
wp-content/managewp/backups/
wp-content/updraft/
EOF

# Copy database backup to backup directory first to include it in the archive
cp "$TEMP_DB_BACKUP" "$BACKUP_DIR/"
DB_BACKUP_BASENAME=$(basename "$TEMP_DB_BACKUP")

# Use tar with proper path handling to avoid absolute path warnings
cd "$(dirname "$WP_DIR")"
tar --warning=no-file-changed -czf "$BACKUP_FILE" --exclude-from=$HOME/tmp/wp-backup-exclude.txt "$(basename "$WP_DIR")" -C "$BACKUP_DIR" "$DB_BACKUP_BASENAME"
TAR_EXIT_CODE=$?

# tar exit codes: 0 = success, 1 = some files changed during archiving (usually OK), 2 = fatal error
if [ $TAR_EXIT_CODE -eq 0 ] || [ $TAR_EXIT_CODE -eq 1 ]; then
    echo "Files backup successful: $BACKUP_FILE"
    # Remove the temporary database dump files and exclude file
    rm -f "$TEMP_DB_BACKUP" "$BACKUP_DIR/$DB_BACKUP_BASENAME" $HOME/tmp/wp-backup-exclude.txt
else
    echo "Error: Files backup failed with exit code $TAR_EXIT_CODE"
    # Attempt a more robust backup with stricter exclusions if the first one failed
    echo "Trying backup with additional safeguards..."
    
    # Use a different approach with more exclusions and ignore errors
    tar --warning=no-file-changed -czf "$BACKUP_FILE" \
        --exclude="*.log" \
        --exclude="cache" \
        --exclude="*.tmp" \
        --exclude="wp-content/cache" \
        --exclude="wp-content/uploads/wp-cache-*" \
        --exclude="wp-content/debug.log" \
        --exclude="wp-content/upgrade" \
        --exclude="wp-content/backup*" \
        "$(basename "$WP_DIR")" -C "$BACKUP_DIR" "$DB_BACKUP_BASENAME"
    TAR_EXIT_CODE=$?
    
    if [ $TAR_EXIT_CODE -eq 0 ] || [ $TAR_EXIT_CODE -eq 1 ]; then
        echo "Backup successful with additional safeguards"
        rm -f "$TEMP_DB_BACKUP" "$BACKUP_DIR/$DB_BACKUP_BASENAME" $HOME/tmp/wp-backup-exclude.txt
    else
        echo "Error: Backup failed even with additional safeguards (exit code: $TAR_EXIT_CODE)"
        # Clean up temporary files
        rm -f "$TEMP_DB_BACKUP" "$BACKUP_DIR/$DB_BACKUP_BASENAME" $HOME/tmp/wp-backup-exclude.txt
        exit 1
    fi
fi

# Display backup information
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "==== Backup Completed ===="
echo "Backup file: $BACKUP_FILE"
echo "Backup size: $BACKUP_SIZE"
echo "Backup completed at: $(date)"
echo "============================================"

# Upload to Google Drive if requested
if [ -n "$GDRIVE_REMOTE" ]; then
    echo "==== Uploading to Google Drive ===="
    echo "Remote: $GDRIVE_REMOTE"
    
    # Check if the remote exists in rclone config
    if ! rclone listremotes | grep -q "^${GDRIVE_REMOTE}:$"; then
        echo "Error: Remote '$GDRIVE_REMOTE' not found in rclone configuration"
        echo "Available remotes:"
        rclone listremotes
        echo "Local backup completed successfully: $BACKUP_FILE"
        exit 1
    fi
    
    # Create remote backup directory if it doesn't exist
    REMOTE_BACKUP_DIR="${GDRIVE_REMOTE}:backups/wordpress"
    echo "Creating remote directory: $REMOTE_BACKUP_DIR"
    rclone mkdir "$REMOTE_BACKUP_DIR" 2>/dev/null
    
    # Upload the backup file
    echo "Uploading backup to Google Drive..."
    REMOTE_BACKUP_FILE="${REMOTE_BACKUP_DIR}/$(basename "$BACKUP_FILE")"
    
    if rclone copy "$BACKUP_FILE" "$REMOTE_BACKUP_DIR" --progress; then
        echo "✓ Backup successfully uploaded to Google Drive: $REMOTE_BACKUP_FILE"
        
        # Optionally remove local backup after successful upload
        # Uncomment the following lines if you want to keep only cloud backups
        # echo "Removing local backup file..."
        # rm -f "$BACKUP_FILE"
        # echo "Local backup file removed"
    else
        echo "✗ Error: Failed to upload backup to Google Drive"
        echo "Local backup is still available: $BACKUP_FILE"
        exit 1
    fi
    
    echo "==== Google Drive Upload Completed ===="
fi

# List all backups
echo "Available backups:"
ls -lh "$BACKUP_DIR" | grep "$SITE_NAME"
