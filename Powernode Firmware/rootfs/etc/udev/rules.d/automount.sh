#!/bin/bash

# NOTE: when this script is run the path does not include the sbin directories!!!

USB_VID=$1
USB_PID=$2

function log
{
	logger -t "$(basename $0)($$)" "$1"
}

function log_cmd
{
	$1 && log "$1: OK" || log "$1: Fail"
}

function get_sovi_info
{
	sed -r "s:.*<$1>(.*)</$1>.*:\1:;t;d" /etc/sovi_info.xml
}

BOARD=$(get_sovi_info board)

function regex
{
	echo "$1" | grep -q "$2"
}

function parse_blkid
{
	if regex "$1" "$2"; then
		echo "$1" | sed -r "s/.*$2=\"([^\"]*)\".*/\1/"
	fi
}

function symlink_name
{
	echo "/var/mnt/SMB-"$(sed -r 's/://g' /sys/class/net/eth0/address | tr 'a-z' 'A-Z')
}

function kill_pid
{
	kill $(cat $1) && rm $1
}

function mount
{
	if [[ $ID_FS_TYPE == "ntfs" && -e /sbin/mount.ntfs-3g ]]; then
		/sbin/mount.ntfs-3g $*
	else
		/bin/mount $*
	fi
}

function muss_start
{
	local SYMLINK_NAME=$(symlink_name)

	log "muss_start"

	# setup required folders
	dir=$1
	mkdir -p $dir/Music && chmod 777 $dir/Music
	mkdir -p $dir/rips && chmod 777 $dir/rips
	rm $SYMLINK_NAME
	ln -sf $dir/Music $SYMLINK_NAME

	# enable MDNS service
	/root/avahi-update.sh /root/muss.service
}

function muss_stop
{
	local SYMLINK_NAME=$(symlink_name)

	log "muss_stop"
	rm /var/avahi/services/muss.service
	rm $SYMLINK_NAME
}

function url_encode
{
	len=${#1}

	for (( pos=0 ; pos<len ; pos++ )); do
		c=${1:$pos:1}
		case "$c" in
			[-_.~a-zA-Z0-9]) echo -n $c ;;
			*) printf "%%%02x" "'$c" ;;
		esac
	done
}

function removable_add
{
	local mnt=$1
	local label=$2
	local dev=$3

	echo $mnt,USB,$label,$dev >> /tmp/mnt/removable.txt
	wget http://127.0.0.1/Removable?add=$mnt\&name=USB\&label=$(url_encode "$label")\&dev=$dev -O /dev/null
}

function removable_remove
{
	local mnt=$1
	local dev=$2

	sed -i "s:$mnt:remove:; /remove/d" /tmp/mnt/removable.txt
	wget http://127.0.0.1/Removable?remove=$mnt\&dev=$dev -O /dev/null
}

if [[ $ACTION == "add" ]]; then
	# udev does not populate ID_FS_XXXX vars for devices with no partition table
	# so we try to get this info from blkid instead
	if regex "$DEVNAME" "sd[a-z]$"; then
		BLKID=$(/sbin/blkid $DEVNAME)
		if [[ $? == 0 ]]; then
			ID_FS_UUID=$(parse_blkid "$BLKID" "UUID")
			ID_FS_LABEL=$(parse_blkid "$BLKID" "LABEL")
			ID_FS_TYPE=$(parse_blkid "$BLKID" "TYPE")
		fi
	fi

	# default mount options
	if [[ $ID_FS_UUID ]]; then
		mnt=/tmp/mnt/$ID_FS_UUID
		label=${ID_FS_LABEL:-No Label}
		mode=777

		if regex "$ID_FS_TYPE" "fat"; then
			opts="-o rw,umask=0"
		else
			opts="-o rw"
		fi
	fi

	if [[ $BOARD == "M50" ]]; then
		# if M50 back USB port
		if regex "$DEVPATH" "usb2/2-1/2-1.1/[^/]*/host"; then
			log "M50 back USB port"
			if regex "$DEVNAME" "sd[a-z]1"; then
				mnt=/tmp/mnt/hdd
			else
				log "Ignoring $DEVNAME"
				mnt=""
			fi
		fi
	elif [[ $BOARD == "V500" ]]; then
		# if internal sata port
		if regex "$DEVPATH" "platform/ahci"; then
			# if main block device set drive standby timeout
			if regex "$DEVNAME" "sd[a-z]$"; then
				log_cmd "/sbin/hdparm -S 120 $DEVNAME"
			# else if first partition mount to fixed location
			elif regex "$DEVNAME" "sd[a-z]1"; then
				mnt=/tmp/mnt/hdd
			fi
		fi
	fi

	if [[ $mnt ]]; then
		log "mount $DEVNAME to $mnt..."
		if mkdir -p -m $mode $mnt && mount $DEVNAME $mnt $opts; then
			log "mount OK"
			log_cmd "chmod $mode $mnt"

			if [[ $mnt == "/tmp/mnt/hdd" ]]; then
				muss_start $mnt
			else
				removable_add $mnt "$label" $DEVNAME
			fi
		else
			log "mount error"
		fi
	fi
elif [[ $ACTION == "remove" ]]; then
	mnt=$(awk '$1=="'$DEVNAME'"{print $2}' /proc/mounts)
	if [[ $mnt ]]; then
		log "umount $DEVNAME from $mnt"
		umount -l $mnt && rmdir $mnt

		if [[ $mnt == "/tmp/mnt/hdd" ]]; then
			muss_stop
		else
			removable_remove $mnt $DEVNAME
		fi
	fi
fi
