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

    // globals for fancybox <-> isotope <-> infinitescroll
    var fb2Instance;
    var itemsLoading = false;

    // fancybox <3
    var randomPage = window.location.href.indexOf('/random') !== -1;
    $('.fancybox').fancybox({
        openEffect: 'none',
        closeEffect: 'none',
        nextEffect: 'none',
        prevEffect: 'none',
        padding: 0,
        margin: [20, 60, 20, 60], // Increase left/right margin
        preload: 6,
        loop: false,
        keys: {
            next: {
                74: 'left', // vim J
                72: 'left', // vim H
                13 : 'left', // enter
                34 : 'up',   // page down
                39 : 'left', // right arrow
            },
            prev: {
                75: 'right', // vim K
                76: 'right', // vim L
                8  : 'right',  // backspace
                33 : 'down',   // page up
                37 : 'right',  // left arrow
            }
        },
        helpers: {
            buttons: { 
                // remove close button, because buttons aren't always there
                tpl: '<div id="fancybox-buttons"><ul style="width:128px"><li><a class="btnPrev" title="Previous (J/H/Left/Up)" href="javascript:;"></a></li><li><a class="btnPlay" title="Start slideshow (Space)" href="javascript:;"></a></li><li><a class="btnNext" title="Next (K/L/Right/Down)" href="javascript:;"></a></li><li><a class="btnToggle" title="Toggle size (f)" href="javascript:;"></a></li></ul></div>' 
            }
        },
        ajax: {
            type: 'GET'
        },
        afterLoad: function (current, previous) {
            var max = this.group.length - 1;

            if (previous && current.index == max && previous.index == 0) {
                return false;
            }
            if (current) {
                $(current.element).scrollintoview();
                var threshold = 8;
                if (!itemsLoading && current.index >= max - threshold) {
                    fb2Instance = this;
                    // load next page of items
                    $('.items').infinitescroll('retrieve');
                    itemsLoading = true;
                }
            }
        }
    });
    // autoload parameter:
    var hash = window.location.hash;
    if (hash && hash.substr(0,10) == '#autoload=') {
        var max = $('.fancybox[rel=gallery]').length - 1;
        var index = hash.substr(10) == 'first' ? 0 : max;
        $('.fancybox')[index].click();
    }

    // isotope
    $('.items').isotope({
        sortBy: 'id',
        itemSelector: '.item',
        layoutMode: 'masonry', // (default)
        transformsEnabled: false, // broken in ff
        masonry: {
        },
        sortAscending : false,
        getSortData: {
            id: function (elem) {
                return $(elem).data('id');
            }
        }
    });
    // infinitescroll
    // define our own zeitgeist behavior
    $.extend($.infinitescroll.prototype,{
        // callback when new items are loaded (as html currently):
        _callback_zeitgeist: function infscr_callback_zeitgeist (newElements) {
            //$(this).masonry('appended',$(newElements));
            $('.items').isotope( 'appended', $( newElements ) ); 

            // manually update fancybox group array structure
            if (fb2Instance) {
                for (var i = 0, l = newElements.length; i < l; i++) {
                    var element = $(newElements[i]), link = $('a', element);
                    fb2Instance.group.push({
                        element: element,
                        href: link.attr('data-fancybox-href'),
                        title: link.attr('data-fancybox-title'),
                        isDom: true,
                        type: link.hasClass('fancybox.ajax') ? 'ajax' : 'image'
                    });
                }
            }
            itemsLoading = false;
        },

        // find the number to increment in the path
        _determinepath_zeitgeist: function infscr_determinepath_zeitgeist (path) {
            var match = path.match(/^(.*?page=).*(.*|$)/);
            if (match) {
                return match.slice(1);
            }
            else if (path.match(/\/random/)) {
                return [path + '#'];
            }
            return false;
        }
    });

    $('.items').infinitescroll({
        behavior: 'zeitgeist',
        navSelector: '#pagination ul',
        nextSelector: '#pagination ul li.next a',
        itemSelector: '.item',
        loading: {
            msgText: '<em>loading more</em>',
            finishedMsg: 'No more pages to load.',
            img: '/images/ajax-loader.gif'
        }
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
    $(':input').livequery(function () {
        $(this).keydown(function(e) {
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
    });
    // hide default value on focus
    $('input#searchquery').livequery(function() {
        $(this).search();
    });

    // autocomplete for search form and add/remove tags form,
    //   can display suggestions for tagnames, title and source urls
    $(':input.autocomplete').livequery(function () {
        $(this).autocomplete({
            source: function (request, response) {
                // look for search type radio buttons and use their value,
                // otherwise its not a search form but a tag add autocomplete
                var elem = $('#searchtype input[name="type"]:checked');
                var type = (elem.length > 0) ? elem.val() : 'tags';
                $.ajax({
                    url: '/search', // via GET (default)
                    type: 'GET',
                    data: {q: request.term, type: type},
                    dataType: 'json',
                    success: function (data) {
                        var prop;
                        if (data.type == 'source') {
                            data = data.items;
                            prop = 'source';
                        }
                        else if (data.type == 'title') {
                            data = data.items;
                            prop = 'title';
                        }
                        else {
                            data = data.tags;
                            prop = 'tagname';
                        }
                        response($.map(data, function(item) {
                            return {
                                label: item[prop],
                                value: item[prop]
                            }
                        }));
                    }
                });
            },
            minLength: 2,
            select: function (event, ui) {
                var value = ui.item ? ui.item.label : this.value;
                $(this).val(value);
                $(this).parent().submit();
            }
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
                    $.each(data.item.tags, function (i, tag) {
                        var tagname = tag.tagname.replace(/[\<\>\/~\^,+]/gi, '');
                        var tagshort = tagname.substr(0, 11) + (tagname.length > 11 ? '...' : '');
                        taglist.append('<li><a href="/show/tag/' + escape(tagname) + '">' + tagshort + '</a></li>');
                    });
                    $('.items').isotope('reLayout');
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
    $('#nsfw_checkbox').click(function (event) {
        var flag = $(this).is(':checked');
        
        // ajax request the flag
        $.ajax({
            url: '/update/nsfw',
            type: 'POST',
            data: {nsfw: flag},
            dataType: 'json',
            success: function (data) {
                console.log(data)
                // reload page
                location.reload();
            }
        });
    });
    $('#ratio_select').change(function (event) {
        var ratio = $(this).val();
        location.href = '/list/dimensions/' + ratio;
    });
});
    

