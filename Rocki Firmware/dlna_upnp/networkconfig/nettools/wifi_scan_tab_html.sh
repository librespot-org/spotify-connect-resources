
VALUE1=$1

VALUE2=$2


if [ -e  ${VALUE1}/wifi_scan_tab.info ]
then   

if [ -e  ${VALUE2}wifi_scan_tab_html.info ]
then 
    rm  ${VALUE2}wifi_scan_tab_html.info

    awk 'BEGIN{RS="\"\n";FS=":\""}NF>1{print $NF}'  ${VALUE1}wifi_scan_tab.info >  ${VALUE2}wifi_scan_tab_html.info
else     

    awk 'BEGIN{RS="\"\n";FS=":\""}NF>1{print $NF}'  ${VALUE1}wifi_scan_tab.info >  ${VALUE2}wifi_scan_tab_html.info
fi 

else
	rm  ${VALUE2}wifi_scan_tab_html.info
   
    touch  ${VALUE2}wifi_scan_tab_html.info

 fi

    
