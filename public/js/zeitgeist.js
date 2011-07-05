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

    // Notifications (http://www.red-team-design.com/cool-notification-messages-with-css3-jquery)
    var myMessages = ['info', 'warning', 'error', 'success'];

    function hideAllMessages() {
    var messagesHeights = new Array(); // this array will store height for each

    for (i=0; i<myMessages.length; i++) {
        messagesHeights[i] = $('.' + myMessages[i]).outerHeight(); // fill array
        $('.' + myMessages[i]).css('top', -messagesHeights[i]); //move element outside viewport
        }
    }

    function showMessage(type) {
        $('.'+ type +'-trigger').click(function() {
            hideAllMessages();
            $('.'+type).animate({top:"0"}, 500);
        });
    }

    // Initially, hide them all
    //hideAllMessages();

    // Show message
    for(var i=0;i<myMessages.length;i++) {
        showMessage(myMessages[i]);
    }

    // When message is clicked, hide it
    $('.message').click(function() {
        $(this).animate({top: -$(this).outerHeight()}, 500);
    });            

});
