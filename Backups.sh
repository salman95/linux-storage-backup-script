#!/bin/bash

#Enter your drive location(s) here that need to be backed up.
#For Ubuntu Server, drive directory locations are located in /media/.
source_dirs=(
  "/media/E_Drive_1"
  "/media/E_Drive_2"
  "/media/Vids"
)

#Enter the drive location where you want to place the backups.
backup_dir="/media/Backup_Drive"

#Removes previously archived files.
rm "${backup_dir}"/*.tar.gz

#timestamp=$(date +%Y%m%d%H%M%S)

# Compress and backup each source directory
for dir in "${source_dirs[@]}"; do
  base_dir=$(basename "$dir")
  #archive_file="$backup_dir/$base_dir-$timestamp.tar.gz"
  archive_file="$backup_dir/$base_dir.tar.gz"

  # Create the backup archive
  tar -I pigz -cf "$archive_file" "$dir"

  # Verify the backup archive
  if [ -f "$archive_file" ]; then
    echo "Backup created: $archive_file"
  else
    echo "Backup failed: $archive_file"
  fi
done
