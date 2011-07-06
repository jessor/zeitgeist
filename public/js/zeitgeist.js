jQuery(function(){

    // unobstrusively clear form fields on focus and restore afterwards
    // http://bassistance.de/2007/01/23/unobtrusive-clear-searchfield-on-focus/
    $.fn.search = function() {
        return this.focus(function() {
            if( this.value == this.defaultValue ) {
                this.value = "";
            }
        }).blur(function() {
            if( !this.value.length ) {
                this.value = this.defaultValue;
            }
        });
    };

    // add noise to body background
    $('body').noisy({
        'intensity':    1, 
        'size':         '200', 
        'opacity':      0.034, 
        'fallback':     '', 
        'monochrome':   false
    });

    // fancybox <3
    $("a.fancy").fancybox({
        'transitionIn':     'fade',
        'transitionOut':    'fade',
        'speedIn':          600, 
        'speedOut':         200
    });

     $("a.youtube").click(function() {
        $.fancybox({
            'transitionIn':     'fade',
            'transitionOut':    'fade',
            'speedIn':          600, 
            'speedOut':         200,
            'width':            680,
            'height':           495,
            'href':             this.href.replace(new RegExp("watch\\?v=", "i"), 'v/'),
            'type':             'swf',
            'swf':              {
                'allowfullscreen':  'true'
            }
        });
        return false;
    });

    $("a.embed").click(function() {
        $.fancybox({
            'href':     '/embed',
            ajax: {
                      type:   "POST",
                      data:   'url=' + this.href + '&provider=' + this.rel
            }
        });
        return false;
    });
        
    // limit default tag list length on index view
    $('.taglist').expander({
        collapseTimer:  5000,
        slicePoint:     200,
        expandText:     '&raquo; more',
        userCollapse:   false
    });

    // search
    function format(item) {
        return item.tagname;
    }
    $.ajaxSetup({ type: 'post' });
    $('#searchsubmit').hide();
    $('#searchquery').search();
    $('#searchquery').autocomplete('/search', {
        width:          300,
        dataType:       'json',
        parse: function(data) {
            return $.map(data, function(row) {
                return {
                    data: row,
                    value: row.tagname,
                    result: row.tagname
                }
            });
        },
        formatItem: function(item) {
            return format(item);
        }
        //multiple:       true,
        //matchContains:  true,
    }).result(function(e, item) {
        $("#content").append("<p>selected " + format(item) + "</p>");
    });

    // Tag Form
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

    $('.message').each(function() {
        $('header').addClass('dragged');
    });

    // When message is clicked, hide it
    $('.message').click(function() {
        $(this).animate({top: -$(this).outerHeight()}, 500).queue(function() {
            $('header').removeClass('dragged');
        });
    });            

});
