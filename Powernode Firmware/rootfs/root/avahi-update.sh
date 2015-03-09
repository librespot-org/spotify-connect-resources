#!/bin/bash

function get_sovi_info
{
	sed -r "s:.*<$1>(.*)</$1>.*:\1:;t;d" /etc/sovi_info.xml
}

# We need to escape special characters in player_name for sed and XML
# sed: : \ &
# XML: & < >

name=$(sed 's/[:\]/\\&/g; s/&/\\\&amp;/g; s/</\\\&lt;/g; s/>/\\\&gt;/g' /var/data/player_name)
mac=$(sed 's/://g' /sys/class/net/eth0/address | tr 'a-z' 'A-Z')

if ps | grep sovi_hal | grep -v grep; then
	model=$(echo Model? | socat -T 1 unix-client:/tmp/sovi_hal stdio)
else
	model=$(sovi_hal --model)
fi

if [[ -z $model ]]; then
	model="BluOS"
fi

version=$(get_sovi_info git)

regex="
	s:(<name>)(.*)(</name>):\1$name\3:;
	s:(<txt-record>model=).*(</txt-record>):\1$model\2:;
	s:(<txt-record>version=).*(</txt-record>):\1$version\2:;
	s:(<txt-record>mac=).*(</txt-record>):\1$mac\2:;
"

if [[ $1 ]]; then
	sed -r "$regex" $1 > /var/avahi/services/$(basename $1)
else
	sed -r -i "$regex" /var/avahi/services/*
fi
