function assignStationInfo(id,name,url) {
  document.getElementById("name"+id).value=name;
  document.getElementById("url"+id).value=url;
}

function deleteUp(e) { e.src="images/btn_delete_over.png"; }
function deleteDown(e) { e.src="images/btn_delete_pressed.png"; }
function deleteOver(e) { e.src="images/btn_delete_over.png"; }
function deleteOut(e) { e.src="images/btn_delete_normal.png"; }


