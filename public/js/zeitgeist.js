jQuery(function(){

    $('body').noisy({
        'intensity':    1, 
        'size':         '200', 
        'opacity':      0.034, 
        'fallback':     '', 
        'monochrome':   false
    });

    $("a.fancy").fancybox({
        'transitionIn':     'fade',
        'transitionOut':    'fade',
        'speedIn':          600, 
        'speedOut':         200
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
