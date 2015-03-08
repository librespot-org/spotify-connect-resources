#!/bin/sh

SPOTIFY_ROOT=/mnt/sd/dlna_upnp/spotify
#SPOTIFY_ROOT=/mnt/sd/dlna_upnp/boa_dlna/tmp

if [ -d $SPOTIFY_ROOT ]; then
	echo "exist $SPOTIFY_ROOT..."
else
	echo "no $SPOTIFY_ROOT, create it."
	mkdir -p $SPOTIFY_ROOT
	mkdir -p $SPOTIFY_ROOT/lib
fi

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$SPOTIFY_ROOT/lib:/mnt/sd/dlna_upnp/airaudio/dbus_avahi_airaudio_lib_so

dev_name=$(cat /mnt/sd/dlna_upnp/dlna/gmediarender-0.0.6/bin/arg/device_name_utf8)
echo $dev_name

cd $SPOTIFY_ROOT
./bin/spotify-rocki -t 8 -k spotify_appkey.key -w 5000 -z -u tbbzxhh -n "$dev_name" &

#./telnet.sh
#echo "Telnet have been started..."

