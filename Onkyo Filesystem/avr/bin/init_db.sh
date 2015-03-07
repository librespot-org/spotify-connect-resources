#! /bin/sh

DB_MNT_PATH="/tmp/prepro_db"
DB_FILE_PATH="/opt/onkyo/avr/etc/prepro.db"
DB_TMP_FILE_PATH="/tmp/prepro.db"
DB_FLAG_PATH="/tmp/prepro.flag.db"

set_flag(){
    echo "mount ok" > $DB_FLAG_PATH
}

if [ -f $DB_FLAG_PATH ]; then
    echo prepro.db is already mounted.
    exit
fi

if [ ! -d $DB_MNT_PATH ]; then
    mkdir $DB_MNT_PATH
else
    umount $DB_MNT_PATH
fi 

cp $DB_FILE_PATH $DB_TMP_FILE_PATH

# mount -t cramfs  $DB_TMP_FILE_PATH $DB_MNT_PATH -o loop,blocksize=512 && set_flag
mount -t squashfs  $DB_TMP_FILE_PATH $DB_MNT_PATH -o loop,blocksize=512 && set_flag

