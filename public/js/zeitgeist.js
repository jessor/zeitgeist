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

    // Focus the next logical input field (according to the DOM)
    // based on http://jqueryminute.com/set-focus-to-the-next-input-field-with-jquery/
    $.fn.focusInputField = function(direction) {
        return this.each(function() {
            var fields = $(this).parents('body').find(':input[type=text], :input[type=password]');
            var index = fields.index( this );
            if ( index > -1 && ( index + 1 ) < fields.length ) {
                if(direction == 'prev') {
                    fields.eq( index - 1 ).focus();
                }
                else {
                    fields.eq( index + 1 ).focus();
                }
            }
            return false;
        });
    };

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
            'title':            $(this).attr('data-htmltitle'),
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

    $("a.embed").livequery(function() {
        $(this).fancybox({
            'overlayColor':     fancyoverlay,
            'overlayOpacity':   fancyopacity,
            'showNavArrows':    false,
            'href':             '/embed',
            'title':            $(this).attr('data-htmltitle'),
            ajax:       {
                        type:   "POST",
                        data:   { 'url': this.href }
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
            slicePoint:     300,
            expandPrefix:   '',
            expandText:     '&raquo;',
            userCollapse:   false,
            collapseTimer:  '10000',
            afterExpand:    function($element) {
                $element.parent().css({'overflow': 'visible', 'height': 'auto'});
            },
            onCollapse:     function($element) {
                $element.parent().css({'overflow': 'hidden', 'height': '25px'});
            }
        });
    });

    // Search
    $.ajaxSetup({ type: 'post' });
    // hide submit button
    $('input#searchsubmit').hide();
    // autofocus input field
    $('input#searchquery').livequery(function() {
        $(this).focus()
    });
    // redirect tab to focus next/previous input[type=text] field
    $(':input').keydown(function(e) {
        var keycode = e.keycode || e.which;
        // shift+tab
        if(keycode == 9 && e.shiftKey) {
            e.preventDefault();
            $(this).focusInputField('prev');
        }
        // only tab
        else if(keycode == 9) {
            e.preventDefault();
            $(this).focusInputField('next');
        }
    });
    // hide default value on focus
    $('input#searchquery').livequery(function() {
        $(this).search();
    });

    // Autocomplete
    $(':input.autocomplete').livequery(function() {
        $(this).autocomplete('/search', {
            minChars:       2,
            selectFirst:    false,
            width:          300,
            dataType:       'json',
            // parse json response
            parse: function(data) {
                //alert(data);
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
        })
        // submit on selection of suggested tag
        .result(function(e, item) {
            $(this).parent().submit();
        });
    });

    // Tag Form
    $('form.tag').livequery(function() {
        $(this).submit(function() {

            // detect -tags and move them into del_tags:
            var add_tags = $('input[name="add_tags"]', this),
                del_tags = $('input[name="del_tags"]', this),
                taglist = add_tags.val().split(','),
                add_taglist = [], del_taglist = [];
            $.each(taglist, function (i, tag) {
                tag = tag.replace(/^\s+|\s+$/g, ''); // trims the tag
                if (/^-.*/.test(tag)) {
                    del_taglist.push(tag.substr(1));
                }
                else {
                    add_taglist.push(tag);
                }
            });
            add_tags.val(add_taglist.join(','));
            del_tags.val(del_taglist.join(','));

            var Id = $(this).attr("id");
            var tagtarget = '#' + Id.replace(/formfor/, 'tagsfor')
            var options = {
                target:     tagtarget,
                dataType:   'json',
                success:    function(data) {
                    var taglist = $(tagtarget);

                    // reset
                    taglist.html('');
                    $.each(data.tags, function (i, tag) {
                        var tagname = tag.tagname.replace(/[\<\>\/~\^,+]/gi, '');
                        var tagshort = tagname.substr(0, 11) + (tagname.length > 11 ? '...' : '');
                        taglist.append('<li><a href="/show/tag/' + escape(tagname) + '">' + tagshort + '</a></li>');
                    });
                },
                resetForm:  true,
                clearForm:  true
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


//
// Analog Clock using Canvas, Zeitgeist Logo Overlay
// More recent browsers support canvas, drawing surfaces:
// http://diveintohtml5.org/canvas.html
//
var ZeitgeistClock = {
    init: 
        function() {
            this.canvas = document.getElementById('logo_canvas_clock');
            if(!this.canvas.getContext) {
              return; /* no canvas support */
            }
            /* make visible the blank version (without clockhands) of 
             * the clock dial in the logo */
            $('#logo_blank_clock').show();

            this.context = this.canvas.getContext('2d');
            this.width = this.canvas.width;
            this.height = this.canvas.height;
            this.center_x = this.width/2;
            this.center_y = this.height/2+1;

            this.updateClock();
        },

    drawClockhand: 
        function(radius, angle, style) {
            this.context.save();
            this.context.translate(this.center_x, this.center_y);
            this.context.rotate(angle*Math.PI/180);
            this.context.strokeStyle = style;

            this.context.beginPath();
            this.context.moveTo(0, 1);
            this.context.lineTo(0, -radius);
            this.context.stroke();

            this.context.restore();
        },

    updateClock:
        function() {
            var date = new Date(),
                second = date.getSeconds(),
                minute = date.getMinutes(),
                hour = date.getHours();

            // "clear screen"
            this.context.clearRect(0, 0, this.width-1, this.height-1);

            // second: 20px
            this.drawClockhand(20, second * 6, '#a72f2f');

            // minute: 22px
            this.drawClockhand(22, minute * 6, '#242323');

            // hour: 14px
            this.drawClockhand(14, 30 * hour + (minute/2.5), '#242323');

            var self = this;
            window.setTimeout(function() { self.updateClock(); }, 1000);
        }
};

$(document).ready(function() {
    ZeitgeistClock.init();
    $('.upvote form').submit(function (event) {
        event.preventDefault();
        var image = $('input[type="image"]', this),
            id = $('input[name="id"]', this).val(),
            remove = $('input[name="remove"]', this);

        $.post('/upvote', {id: id, remove: remove.val()}, 
            function (data, textStatus, xhr) {
                if (data.error) {
                    alert('An error occured: ' + data.error);
                    return;
                }

                if (remove.val() == 'true') {
                    image.attr('src', '/images/upvote.png');
                    remove.val('false');

                }
                else {
                    image.attr('src', '/images/upvote_on.png');
                    remove.val('true');
                }

                // TODO: find better image, and display data.upvotes somehow
                //       (!interface)
            });

    });
});
    

