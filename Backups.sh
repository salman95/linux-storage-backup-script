#!/bin/bash
set -euo pipefail

# --- Configuration ---
source_dirs=(
    "/mnt/Tech"
    "/mnt/Personal"
    "/mnt/Vids"
)
backup_root="/mnt/Backups"

KEEP=3
MIN_FREE_KB=$((2 * 1024 * 1024))   # 2 GB

# --- Set up multi‑threaded compression ---
# Prefer pzstd (parallel zstd) if available; otherwise use zstd with threads via environment.
if command -v pzstd &>/dev/null; then
    COMPRESS_CMD="pzstd"                      # pzstd defaults to all cores
    export PZSTD_NUM_THREADS=$(nproc)          # explicitly set if needed
elif command -v zstd &>/dev/null; then
    COMPRESS_CMD="zstd"
    # Enable multi‑threading via environment variable (works on all zstd versions)
    export ZSTD_NBTHREADS=$(nproc)
else
    echo "WARNING: zstd not found. Falling back to gzip (slower, worse compression)."
    COMPRESS_CMD="gzip"
fi

# --- Progress bar support ---
USE_PV=false
if command -v pv &>/dev/null; then
    USE_PV=true
else
    echo "pv not found – progress bar disabled."
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
    echo "Continue anyway? (y/N)"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- Create timestamped directory for this run ---
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="$backup_root/backup-$timestamp"
mkdir -p "$backup_dir"
echo "[$(date)] Created run directory: $backup_dir"

# --- Backup each source directory ---
for dir in "${source_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "WARNING: Source directory $dir does not exist. Skipping."
        continue
    fi

    base_name=$(basename "$dir")
    archive_file="$backup_dir/$base_name.tar.zst"
    echo "[$(date)] Archiving $dir -> $archive_file"

    # Common tar options: exclude lost+found, change to parent dir, store relative path
    tar_opts=(
        --exclude='lost+found'
        -C "$(dirname "$dir")"
        "$base_name"
    )

    tar_status=0
    if [ "$USE_PV" = true ]; then
        # Attempt to get total size for progress bar; if it fails, fall back to direct compression
        size_bytes=$(du -sb "$dir" 2>/dev/null | cut -f1) || size_bytes=0
        if [ "$size_bytes" -gt 0 ]; then
            # We have a valid size – use pv
            tar cf - "${tar_opts[@]}" | pv -s "$size_bytes" | $COMPRESS_CMD > "$archive_file"
            tar_status=${PIPESTATUS[0]}
        else
            echo "  (Cannot calculate total size for $dir – disabling progress bar for this archive.)"
            # Fall back to direct tar + compressor
            tar -I "$COMPRESS_CMD" -cf "$archive_file" "${tar_opts[@]}"
            tar_status=$?
        fi
    else
        # pv not available at all – direct compression
        tar -I "$COMPRESS_CMD" -cf "$archive_file" "${tar_opts[@]}"
        tar_status=$?
    fi

    # Check result and verify archive
    if [ $tar_status -eq 0 ] && [ -f "$archive_file" ]; then
        # Test integrity using the appropriate command
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