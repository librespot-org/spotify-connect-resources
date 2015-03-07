var oldFixPng = DD_belatedPNG.fixPng;
DD_belatedPNG.fixPng = function (el) {
  oldFixPng(el);
  if (el.vml && el.vml.image.fill.getAttribute("src").match(/_off\./)) {
    el.vml.image.shape.attachEvent('onmouseover', function() {
      var image = el.vml.image.fill;
      image.setAttribute("src", image.getAttribute("src").replace("_off.", "_over."));
    });
    el.vml.image.shape.attachEvent('onmouseout', function() {
      var image = el.vml.image.fill;
      image.setAttribute("src", image.getAttribute("src").replace("_over.", "_off."));
    });
    el.vml.image.shape.attachEvent('onmousedown', function() {
      var image = el.vml.image.fill;
      image.setAttribute("src", image.getAttribute("src").replace("_over.", "_on."));
    });
  } else if (el.vml && el.vml.image.fill.getAttribute("src").match(/_normal\./)) {
    el.vml.image.shape.attachEvent('onmouseover', function() {
      var image = el.vml.image.fill;
      image.setAttribute("src", image.getAttribute("src").replace("_normal.", "_over."));
    });
    el.vml.image.shape.attachEvent('onmouseout', function() {
      var image = el.vml.image.fill;
      image.setAttribute("src", image.getAttribute("src").replace("_over.", "_normal."));
    });
    el.vml.image.shape.attachEvent('onmousedown', function() {
      var image = el.vml.image.fill;
      image.setAttribute("src", image.getAttribute("src").replace("_over.", "_pressed."));
    });
  }
};
DD_belatedPNG.fix('img.logo');
DD_belatedPNG.fix('img.tab');
DD_belatedPNG.fix('img.refresh');
DD_belatedPNG.fix('img.caution');