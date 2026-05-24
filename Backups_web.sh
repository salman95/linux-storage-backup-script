#!/bin/bash
set -euo pipefail

# --- Web-friendly backup script ---
# This version accepts source directories as arguments, emits structured
# progress markers for the web UI, and has no interactive prompts.
#
# Usage: ./Backups_web.sh /mnt/Tech /mnt/Personal /mnt/Vids
#        ./Backups_web.sh /mnt/Tech   (backup only Tech)

# --- Validate arguments ---
if [ $# -eq 0 ]; then
    echo "ERROR: No source directories specified."
    echo "Usage: $0 <dir1> [dir2] [dir3] ..."
    exit 1
fi

source_dirs=("$@")
backup_root="/mnt/Backups"

KEEP=3
MIN_FREE_KB=$((2 * 1024 * 1024))   # 2 GB

# --- Set up multi-threaded compression ---
if command -v pzstd &>/dev/null; then
    COMPRESS_CMD="pzstd"
    export PZSTD_NUM_THREADS=$(nproc)
elif command -v zstd &>/dev/null; then
    COMPRESS_CMD="zstd"
    export ZSTD_NBTHREADS=$(nproc)
else
    echo "WARNING: zstd not found. Falling back to gzip (slower, worse compression)."
    COMPRESS_CMD="gzip"
fi

# --- Sanity checks on backup root ---
if [ ! -d "$backup_root" ]; then
    echo "ERROR: Backup root $backup_root does not exist or is not mounted."
    exit 1
fi

available_kb=$(df "$backup_root" | awk 'NR==2 {print $4}')
if [ "$available_kb" -lt "$MIN_FREE_KB" ]; then
    echo "WARNING: Less than $((MIN_FREE_KB/1024)) MB free on $backup_root."
    echo "         Current free: $((available_kb/1024)) MB"
    echo "         Continuing anyway (web mode, no interactive prompt)."
fi

# --- Create timestamped directory for this run ---
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="$backup_root/backup-$timestamp"
mkdir -p "$backup_dir"
echo "[$(date)] Created run directory: $backup_dir"

# --- Backup each source directory ---
total=${#source_dirs[@]}
completed=0

echo "PROGRESS:${completed}/${total}"

for dir in "${source_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "WARNING: Source directory $dir does not exist. Skipping."
        completed=$((completed + 1))
        echo "PROGRESS:${completed}/${total}"
        continue
    fi

    base_name=$(basename "$dir")
    archive_file="$backup_dir/$base_name.tar.zst"
    echo "[$(date)] Archiving $dir -> $archive_file"

    # Common tar options
    tar_opts=(
        --exclude='lost+found'
        -C "$(dirname "$dir")"
        "$base_name"
    )

    tar_status=0
    tar -I "$COMPRESS_CMD" -cf "$archive_file" "${tar_opts[@]}" 2>&1
    tar_status=$?

    # Check result and verify archive
    if [ $tar_status -eq 0 ] && [ -f "$archive_file" ]; then
        if [ "$COMPRESS_CMD" = "gzip" ]; then
            gzip -t "$archive_file" &>/dev/null
        else
            $COMPRESS_CMD -t "$archive_file" &>/dev/null
        fi
        if [ $? -eq 0 ]; then
            echo "OK: $archive_file verified."
        else
            echo "ERROR: $archive_file is corrupt. Removing."
            rm -f "$archive_file"
        fi
    else
        echo "ERROR: tar failed for $dir. Removing partial archive if any."
        rm -f "$archive_file"
    fi

    completed=$((completed + 1))
    echo "PROGRESS:${completed}/${total}"
done

# --- Retention: keep only the most recent K backup directories ---
echo "[$(date)] Applying retention policy (keeping last $KEEP directories)..."
mapfile -t dirs < <(find "$backup_root" -maxdepth 1 -type d -name "backup-*" | sort -r)
total_dirs=${#dirs[@]}
if [ "$total_dirs" -gt "$KEEP" ]; then
    for ((i=KEEP; i<total_dirs; i++)); do
        echo "  Removing old backup directory: ${dirs[i]}"
        rm -rf "${dirs[i]}"
    done
fi

# --- Final space check ---
available_kb=$(df "$backup_root" | awk 'NR==2 {print $4}')
echo "[$(date)] Backup completed. Free space on $backup_root: $((available_kb/1024)) MB"
