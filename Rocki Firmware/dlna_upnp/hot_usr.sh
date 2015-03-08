ushare_var=$(ps -ef | grep -v grep | grep  "ushare")
echo $ushare_var

if [ -n "$ushare_var" ];then
	echo "AC+MSTOP" > /tmp/GMR_fifo_read
	usleep 300000
	echo "AC+MSSEL=1" > /tmp/GMR_fifo_read
	/mnt/sd/dlna_upnp/airaudio/sh_airaudio_end
	sleep 1
	echo "NC+DLRESCAN" > /tmp/NET_CTL_fifo_read
fi
