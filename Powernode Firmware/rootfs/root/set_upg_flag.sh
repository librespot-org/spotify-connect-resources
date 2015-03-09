#!/bin/bash

dd if=/root/upgrade_flag.bin of=/dev/mmcblk0 bs=512 seek=1529 && sync
