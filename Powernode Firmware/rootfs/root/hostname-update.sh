#!/bin/bash

# set hostname
hostname $(sed 's/[^[:alnum:]-]//g; s/^-*//' /var/data/player_name)

# update avahi hostname and services
avahi-set-host-name $(hostname)
/root/avahi-update.sh

# restart nmbd
if [[ -e /var/run/nmbd.pid ]]; then
	kill $(cat /var/run/nmbd.pid) && nmbd -D
fi

# reset bluetooth alias
gdbus call --system --dest org.sovibt --object-path /sovibt --method org.sovibt.commands.ResetAlias
