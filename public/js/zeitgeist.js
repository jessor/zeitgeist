jQuery(function(){

    $('body').noisy({
        'intensity':    1, 
        'size':         '200', 
        'opacity':      0.034, 
        'fallback':     '', 
        'monochrome':   false
    });

    $().piroBox({
        my_speed:   100, //animation speed
        bg_alpha:   0.8, //background opacity
        slideShow:  'false', // true == slideshow on, false == slideshow off
        close_all:  '.piro_close' // add class .piro_overlay(with comma)if you want overlay click close piroBox
    });

    $('.taglist').expander({
        collapseTimer:  5000,
        slicePoint:     200,
        expandText:     '&raquo; more',
        userCollapse:   false
    });

    $('form.tag').submit(function() {
        var Id = $(this).attr("id")
        var tagtarget = '#' + Id.replace(/formfor/, 'tagsfor')
        var options = {
            target: tagtarget,
            resetForm: true
        };

        $(this).ajaxSubmit(options);
        return false;
    });

});
