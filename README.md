# WordPress Backup & Restore Scripts

Automated WordPress backup and restore solution with Google Drive integration using rclone.

## Features

- 🔄 **Complete WordPress Backup**: Database + Files
- ☁️ **Google Drive Integration**: Upload/download backups to/from cloud
- 🎯 **Interactive Restore**: Select from local or cloud backups
- 🚀 **Smart Automation**: Latest backup auto-selection
- ⚡ **Progress Tracking**: Real-time upload/download progress
- 🛡️ **Safety Features**: Pre-restore backups and validation
- 📝 **Detailed Logging**: Comprehensive operation feedback

## Prerequisites

### Required Software

1. **bash** - Shell scripting environment
2. **mysql/mysqldump** - Database operations
3. **tar** - Archive creation and extraction
4. **rclone** (for Google Drive features) - Cloud storage integration

### Install rclone

```bash
# Ubuntu/Debian
sudo apt install rclone

# CentOS/RHEL
sudo yum install rclone

# Or download from official site
curl https://rclone.org/install.sh | sudo bash
```

### Configure rclone for Google Drive

```bash
rclone config
```

Follow the interactive setup to create a Google Drive remote named `ndev` (or your preferred name).

## Installation

1. Download the scripts:
   ```bash
   wget https://example.com/backup.sh
   wget https://example.com/restore.sh
   ```

2. Make them executable:
   ```bash
   chmod +x backup.sh restore.sh
   ```

3. Ensure your WordPress directory structure matches:
   ```
   $HOME/
   ├── public_html/          # WordPress files
   │   └── wp-config.php     # WordPress configuration
   └── backups/              # Local backups (auto-created)
   ```

## Usage

### Backup Operations

#### Local Backup Only
```bash
./backup.sh
```

#### Backup + Google Drive Upload
```bash
./backup.sh --gdrive=ndev
```

#### Help and Options
```bash
./backup.sh --help
```

**Example Output:**
```
==== Starting WordPress Backup ====
Site: wordpress
Timestamp: 2025-08-25_04-23-51
Backing up database: your_db_name
Database backup successful: /tmp/wordpress_db_2025-08-25_04-23-51.sql
Backing up WordPress files from: /home/user/public_html
Files backup successful: /home/user/backups/wordpress_2025-08-25_04-23-51.tar.gz
==== Backup Completed ====
Backup file: /home/user/backups/wordpress_2025-08-25_04-23-51.tar.gz
Backup size: 22M
```

### Restore Operations

#### Local Restore (Interactive)
```bash
./restore.sh
```

#### Google Drive Restore (Interactive)
```bash
./restore.sh --gdrive=ndev
```

#### Help and Options
```bash
./restore.sh --help
```

**Example Interactive Menu:**
```
Available backups from Google Drive:
Select a backup to restore:
0) Use latest backup automatically
1) wordpress_2025-08-25_03-52-38.tar.gz
2) wordpress_2025-08-24_15-30-22.tar.gz
3) wordpress_2025-08-23_10-15-45.tar.gz
Enter your choice (0-3):
```

## Configuration

### Environment Variables

Both scripts automatically detect your environment:

- `$HOME/public_html` - WordPress installation directory
- `$HOME/backups` - Local backup storage directory
- `$HOME/tmp` - Temporary files directory

### WordPress Database Credentials

Scripts automatically extract database credentials from `wp-config.php`:
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`
- `DB_HOST`

### Google Drive Structure

Backups are stored in Google Drive as:
```
Google Drive/
└── backups/
    └── wordpress/
        ├── wordpress_2025-08-25_04-23-51.tar.gz
        ├── wordpress_2025-08-24_15-30-22.tar.gz
        └── wordpress_2025-08-23_10-15-45.tar.gz
```

## Script Details

### backup.sh

**Functions:**
- Extract database credentials from wp-config.php
- Create MySQL dump in temporary location
- Archive WordPress files with exclusions
- Optional Google Drive upload with progress

**File Exclusions:**
- `*.log` - Log files
- `*.tmp` - Temporary files
- `cache/` - Cache directories
- `wp-content/cache/` - WordPress cache
- `wp-content/uploads/wp-cache-*` - Cache files
- `wp-content/debug.log` - Debug logs
- `wp-content/upgrade/` - Update files
- `wp-content/backup*` - Existing backups

**Exit Codes:**
- `0` - Success
- `1` - Error (missing dependencies, failed operations)

### restore.sh

**Functions:**
- List available backups (local or Google Drive)
- Interactive backup selection with auto-latest option
- Download backup from Google Drive (if applicable)
- Extract and restore database + files
- Create pre-restore safety backup
- Optional cleanup of downloaded files

**Safety Features:**
- Creates pre-restore backup: `pre_restore_YYYY-MM-DD_HH-MM-SS.tar.gz`
- Validates backup archive before proceeding
- Confirms destructive operations with user

## Error Handling

### Common Issues and Solutions

**1. "Harus memasang rclone terlebih dahulu!"**
- **Problem**: rclone not installed
- **Solution**: Install rclone using package manager or official installer

**2. "Remote 'ndev' not found in rclone configuration"**
- **Problem**: Google Drive remote not configured
- **Solution**: Run `rclone config` to set up Google Drive remote

**3. "Could not extract database credentials from wp-config.php"**
- **Problem**: Invalid wp-config.php or wrong path
- **Solution**: Ensure wp-config.php exists in `$HOME/public_html/`

**4. "Database backup failed"**
- **Problem**: MySQL connection issues
- **Solution**: Check database credentials and MySQL service

**5. "Files backup failed"**
- **Problem**: Permission issues or disk space
- **Solution**: Check file permissions and available disk space

### Validation Checks

Both scripts perform comprehensive validation:

✅ **Pre-execution Checks:**
- rclone installation (when using --gdrive)
- WordPress directory structure
- Database connectivity
- Remote configuration (for Google Drive)

✅ **During Execution:**
- Database dump success
- Archive creation success
- Upload/download progress
- File integrity

✅ **Post-execution:**
- Backup file verification
- Cleanup operations
- Success confirmation

## Examples

### Daily Automated Backup

Create a cron job for daily backups:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM with Google Drive upload
0 2 * * * /home/user/backup.sh --gdrive=ndev >> /home/user/backup.log 2>&1
```

### Disaster Recovery Workflow

1. **Immediate Restore from Latest Backup:**
   ```bash
   ./restore.sh --gdrive=ndev
   # Press Enter to select latest backup automatically
   ```

2. **Restore from Specific Date:**
   ```bash
   ./restore.sh --gdrive=ndev
   # Select specific backup from interactive menu
   ```

3. **Local Development Setup:**
   ```bash
   # Download production backup
   ./restore.sh --gdrive=ndev
   # Choose production backup
   # Development environment ready
   ```

### Migration Between Servers

1. **Source Server:**
   ```bash
   ./backup.sh --gdrive=ndev
   ```

2. **Destination Server:**
   ```bash
   # Install scripts and configure rclone
   ./restore.sh --gdrive=ndev
   ```

## Security Considerations

### Database Credentials
- Scripts read credentials from wp-config.php
- No credentials stored in script files
- Temporary database dumps are securely cleaned up

### File Permissions
After restore, you may need to fix file permissions:

```bash
# Fix directory permissions
find $HOME/public_html -type d -exec chmod 755 {} \;

# Fix file permissions
find $HOME/public_html -type f -exec chmod 644 {} \;

# Fix ownership (replace user:group with your actual user/group)
chown -R your_user:your_group $HOME/public_html
```

### Google Drive Access
- Uses OAuth2 for secure authentication
- Tokens stored in rclone configuration
- No direct credential exposure

## Troubleshooting

### Debug Mode

Enable verbose output for debugging:

```bash
# Enable bash debug mode
bash -x ./backup.sh --gdrive=ndev

# Check rclone configuration
rclone config show

# Test rclone connectivity
rclone lsd ndev:
```

### Log Files

Scripts output detailed information:
- Success/failure status
- File paths and sizes
- Timestamps
- Error messages with context

### Manual Verification

Verify backup integrity:

```bash
# Check archive contents
tar -tzf backup_file.tar.gz | head -20

# Verify database dump
head -50 database_dump.sql
```

## License

This project is released under the MIT License.

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Verify all prerequisites are met
3. Check rclone configuration and connectivity
4. Review script output for specific error messages

## Version History

- **v1.0** - Initial release with local backup/restore
- **v1.1** - Added Google Drive integration
- **v1.2** - Improved error handling and validation
- **v1.3** - Enhanced user experience and documentation

---

**⚠️ Important**: Always test backup and restore procedures in a development environment before using in production.
