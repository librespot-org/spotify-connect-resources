function selectAccount( selectEl, service, addname ) {
  var n = selectEl.selectedIndex;
  var name = selectEl.options[n].text;
  if( name == addname ) {
    document.getElementById( 'user_'+service ).value = "";
    document.getElementById( 'pswd_'+service ).value = "";
  } else {
    eval( "var pswd = "+service+"_password_list[n];" );
    document.getElementById( 'user_'+service ).value = name;
    document.getElementById( 'pswd_'+service ).value = pswd;
  }
}

function inputUsername( username, password ) {
  var nameEl = document.getElementById( username );
  var passEl = document.getElementById( password );
  if( nameEl.value != nameEl.defaultValue ) {
    passEl.value = "";
  }
}

function focusPassword( passwordEl ) {
  eval( passwordEl.id + "_value = passwordEl.value;" );
  passwordEl.value="";
}

function blurPassword( passwordEl ) {
//  if( passwordEl.value == "" ) {
//    eval( "passwordEl.value= " + passwordEl.id + "_value;" );
//  }
}

