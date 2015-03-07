#!/bin/bash

function get_sovi_info
{
	sed -r "s:.*<$1>(.*)</$1>.*:\1:;t;d" /etc/sovi_info.xml
}

VOLUME_MIN=$(get_sovi_info volume_min)

chrt -r 2 dspout -m $VOLUME_MIN
