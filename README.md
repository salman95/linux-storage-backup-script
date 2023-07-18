# linux-storage-backup-script
A simple script that will compress and backup all your drives content into one location. 

The idea is to move the contents of one or multiple drives into another designated backup location. The content will be placed in an archive file(tar.gz) with the source directory name.

This script utilizes Pigz, which is the paralell implementation of Gzip. It allows for the tar command to run in multiple threads rather than just a single thread.

<b>Prequisite:<b>
Install pigz
