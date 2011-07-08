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
    var fancyoverlay = '#171717';
    var fancyopacity = 0.8;
    $("a.fancy").livequery(function() {
        $(this).fancybox({
            'overlayColor':     fancyoverlay,
            'overlayOpacity':   fancyopacity,
            'transitionIn':     'fade',
            'transitionOut':    'fade',
            'speedIn':          600, 
            'speedOut':         200,
            'href':             $(this).attr('href'),
            'type':             'image',
            'paginatenext':     function() {
                if ($('div#pagination .next a').length) {
                    window.location.href = $('div#pagination .next a').attr('href') + '&autoload=first';
                } else {
                    alert ("That's it for now!");
                }
            },
            'paginateprev':     function() {
                if ($('div#pagination .previous a').length) {
                    window.location.href = $('div#pagination .previous a').attr('href') + '&autoload=last';
                } else {
                    alert ("That's it for now!");
                }
            },
        });
        return false;
    });

     $("a.youtube").livequery(function() {
        $(this).fancybox({
            'overlayColor':     fancyoverlay,
            'overlayOpacity':   fancyopacity,
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

    $("a.embed").livequery(function() {
        $(this).fancybox({
            'overlayColor':     fancyoverlay,
            'overlayOpacity':   fancyopacity,
            'href':     '/embed',
            ajax:       {
                        type:   "POST",
                        data:   'url=' + this.href + '&provider=' + this.rel
            }
        });
        return false;
    });

     $("a.fancynav").click(function() {
        $.fancybox({
            'overlayColor':     fancyoverlay,
            'overlayOpacity':   fancyopacity,
            'href':     this.href,
            ajax:       {
                        type:   "GET",
            }
        });
        return false;
    });
        
    // limit default tag list length on index view
    $('.taglist').livequery(function() {
        $(this).expander({
            collapseTimer:  5000,
            slicePoint:     200,
            expandText:     '&raquo; more',
            userCollapse:   false
        });
    });

    // search
    $.ajaxSetup({ type: 'post' });
    // hide submit button
    $('input#searchsubmit').hide();
    // hide default value on focus
    $('input#searchquery').livequery(function() {
        $(this).search();
    });
    // autocomplete
    $('input#searchquery').livequery(function() {
        $(this).autocomplete('/search', {
            //matchContains:  true,
            width:          300,
            dataType:       'json',
            // parse json response
            parse: function(data) {
                return $.map(data, function(row) {
                    return {
                        data: row,
                        value: row.tagname,
                        result: row.tagname
                    }
                });
            },
            // format items in autocomplete select box
            formatItem: function(item) {
                return item.tagname;
            }
        }).result(function(e, item) {
            $('form#searchform').submit();
        });
    });

    // Tag Form
    $('form.tag').livequery(function() {
        $(this).submit(function() {
            var Id = $(this).attr("id")
            var tagtarget = '#' + Id.replace(/formfor/, 'tagsfor')
            var options = {
                target:     tagtarget,
                dataType:   'json',
                success:    function(data) {
                                $.each(data.added_tags, function(i,tag) {
                                    $(tagtarget).prepend(' ' + tag.tagname + ' ');
                                });
                            },
                resetForm:  true
            };

            $(this).ajaxSubmit(options);
            return false;
        });
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
