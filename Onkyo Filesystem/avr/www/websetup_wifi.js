function displayWepId(sec, wepId) {
  if( sec == 1 ) {
    wepId.removeAttribute( "disabled" );
  } else {
    wepId.setAttribute( "disabled", "true" );
  }
}

function InitWepIdSelect() {
  selectApSec();
  selectDiSec();
}

function selectAp() {
  var n = document.wifi_setup.apchoose.selectedIndex;
  apsecurity.innerHTML = ap_security_list[n];
  document.wifi_setup.apchoosessid.value = document.wifi_setup.apchoose.options[n].text;
  document.wifi_setup.apchoosesec.value = ap_securityid_list[n];
  selectApSec();
}


function selectApSec() {
  displayWepId( document.wifi_setup.apchoosesec.value, document.getElementById("apWepId") );
}


function selectDiSec() {
  var elem = document.wifi_setup.disecchoose;
  displayWepId( elem.options[elem.selectedIndex].value, document.getElementById("diWepId") );
}
