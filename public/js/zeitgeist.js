jQuery(function(){

    // masonry!
    var $container = $('.thumbnails');
    $container.imagesLoaded(function(){
        $container.masonry({
            itemSelector: '.thumbnail',
            width: 240,
            animate: true
        });
    });

    // show/hide add tag form
    var showText='+';
    var hideText='-';
    //var is_visible = false;
    // hide all of the elements with a class of 'toggle'
    $('.toggle').hide();
    // capture clicks on the toggle links
    $('a.togglelink').click(function() {
        // switch visibility
        $(this).data('is_visible', !$(this).data('is_visible'));
        // change the link depending on whether the element is shown or hidden
        $(this).html( (!$(this).data('is_visible')) ? showText : hideText);
        // toggle the display
        $(this).closest('ul').next().next().toggle();
        $container.masonry();
        // return false so any link destination is not followed
        return false;
    });

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

    // Fancybox for images
    $(".fancybox-button").fancybox({
		prevEffect:     'none',
		nextEffect:     'none',
        closeBtn:       false,
        beforeShow:     function() {
            this.title = $(this.element).attr('data-htmltitle');
        },
        helpers:        { buttons:    {} },
	});
 
    // Fancybox for video/audio
    $("a.embed").livequery(function() {
        $(this).fancybox({
            prevEffect:     'none',
            nextEffect:     'none',
            closeBtn:       true,
            autoSize:       true,
            maxWidth:       800,
            maxHeight:      600,
            fitToView:      false,
            width:          '70%',
            height:         '70%',
            href:           '/embed',
            beforeShow:     function() {
                this.title = $(this.element).attr('data-htmltitle');
            },
            ajax:           {
                type:   "POST",
                data:   { 'url': this.href }
            },
            helpers:        { buttons: {} }
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
            inputClass:     'ac_input',
            resultsClass:   'ac_results',
            loadingClass:   'ac_loading',
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
        })
        // submit on selection of suggested tag
        .result(function(e, item) {
            $(this).parent().submit();
        });
    });

    // Tag Form
    // Add tag to taglist after a successful POST
    $('form.tag').livequery(function() {
        $(this).submit(function() {
            var tagtarget = $(this).prevAll('ul');
            var options = {
                target:     tagtarget,
                dataType:   'json',
                success:    function(data) {
                                $.each(data.added_tags, function(i,tag) {
                                    var tagname = tag.tagname.replace(/[\<\>\/~\^,+]/gi, '');
                                    var tagshort = tagname.substr(0, 11) + (tagname.length > 11 ? '...' : '');
                                    $(tagtarget).append('<li><a href="/filter/by/tag/' + escape(tagname) + '" class="tag label label-info">' + tagshort + '</a></li>');
                                    $container.masonry();
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
});
    

