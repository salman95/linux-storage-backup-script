# linux-storage-backup-script
A simple script that will compress and backup all your drives content into one location. 

The idea is to move the contents of one or multiple drives into another designated backup location. The content will be placed in an archive file(tar.gz) with the source directory name.

This script utilizes Pigz, which is the paralell implementation of Gzip. It allows for the tar command to run in multiple threads rather than just a single thread.

You can also run this as a cronjob. Just edit the crontab to have this script automated whenever you like.

![2023-07-19_16-17](https://github.com/salman95/linux-storage-backup-script/assets/25572063/a8230db6-d4c7-483b-a0e8-aba6a2d1485b)


<ins><b>Prequisite:</b></ins>

Install pigz

Edit crontab with: <b>sudo crontab -e</b>
