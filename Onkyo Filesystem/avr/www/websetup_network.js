function isWirelessChecked() {
	var index = document.network_list.networkconnection.selectedIndex;
	if( index < 0 ) {
		return false;
	}
	if( document.network_list.networkconnection.options[index].value == "wireless" ) {
		return true;
	} else {
		return false;
	}
}

function changeWifiHref(id) {
	var element = document.getElementById(id);
	if( isWirelessChecked() ) {
		element.removeAttribute( "disabled" );
		element.className="anchor";
	} else {
		element.setAttribute( "disabled", "true" );
		element.className="disabled";
	}
}

