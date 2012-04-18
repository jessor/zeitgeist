$(function () {
  var draw_type_pie = function (id, items_image, items_video, items_audio) {
    var graph = Flotr.draw(document.getElementById(id),
      [ {data: [[0,items_image]], label: 'images'},
        {data: [[0,items_video]], label: 'videos'},
        {data: [[0,items_audio]], label: 'audio'} ],
      { HtmlText : false,
        shadowSize: 0,
        grid : {
          verticalLines : false,
          horizontalLines : false,
          outlineWidth: 0
        },
        xaxis : { showLabels : false },
        yaxis : { showLabels : false },
        pie : {
          show : true, 
          explode : 0,
          startAngle: Math.PI/2
        },
        mouse : { track : false },
        legend : {
          position : 'se',
          backgroundColor : '#D2E8FF'
        }
      }
    );
  };

  var draw_type_time = function (id, per_day, per_month, per_year) {
    var container = document.getElementById(id),
        start = new Date(per_day[0][0]).getTime(),
        options,
        graph;

    // per_day.reverse();
    per_day.shift();

    function data_by_selection() {
      var type = $('#items_stats_range option:selected').val(),
        data_set, data = [];
      switch (type) {
      case 'per_day':
        data_set = per_day;
        break;
      case 'per_month':
        data_set = per_month;
        break;
      case 'per_year':
        data_set = per_year;
        break;
      }
      var count = 0,
          incremental = $('#items_stats_incremental').is(':checked');
      for (var i = 0; i < data_set.length; i++) {
        if (incremental) {
          count += data_set[i][1];
        }
        else {
          count = data_set[i][1];
        }
        data.push([new Date(data_set[i][0]).getTime(), count]);
      }
      return data;
    }


    options = {
      fill: true,
      fillColor: '#3f72bf',
      fillOpacity: 0.3,
      xaxis : {
        mode : 'time', 
        labelsAngle : 45
      },
      mouse : {
        track : true,
        relative : true,
        trackFormatter: function (point) {
          return Math.round(point.y) + ' items';
        }
      },
      selection : {
        mode : 'x'
      },
      HtmlText : false
    };

    function draw_graph(opts) {
      var data = data_by_selection();
      // Clone the options, so the 'options' variable always keeps intact.
      o = Flotr._.extend(Flotr._.clone(options), opts || {});

      // Return a new graph.
      return Flotr.draw(
        container,
        [ data ],
        o
      );
    }

    graph = draw_graph();

    Flotr.EventAdapter.observe(container, 'flotr:select', function(area){
      // Draw selected area
      graph = draw_graph({
        xaxis : { min : area.x1, max : area.x2, mode : 'time', labelsAngle : 45 },
        yaxis : { min : area.y1, max : area.y2 }
      });
    });

    // When graph is clicked, draw the graph with default area.
    Flotr.EventAdapter.observe(container, 'flotr:click', function () { graph = draw_graph(); });

    $('#items_stats_range, #items_stats_incremental').change(function (event) {
      graph = draw_graph();
    });
  };

  var draw_user_submissions = function (id, user) {
    var container = document.getElementById(id),
      data = [], labels = [];

    for (var i = 0; i < user.length; i++) {
      data.push([i, user[i][1]]);
      labels.push(user[i][0]);
    }
    Flotr.draw(container,
      [ data ],
      {
        bars : {
          show : true,
          horizontal: false
        },
        mouse : {
          track : true,
          relative : true,
          trackFormatter: function (point) {
            return Math.round(point.y) + ' items';
          }
        },
        xaxis: {
          noTicks: labels.length,
          tickFormatter: function (x) {
            var i = parseInt(x);
                // i = (x-1)%labels.length;
            if (labels[i]) {
              return labels[i];
            }
            return '';
          }
        },
        yaxis : {
          min : 0,
          autoscaleMargin : 1
        }
    });
  };

  $.getJSON('/stats.json', function (data, textStatus, jqXHR) {
    if (textStatus != 'success') {
      console.log('error with json data: ' + textStatus);
      return;
    }

    var items_image = data.image,
        items_video = data.video,
        items_audio = data.audio,
        per_day = data.days,
        per_month = data.months,
        per_year = data.years,
        user = data.user;

    // draw the pie chart for item types
    draw_type_pie('items_piechart_holder', items_image, items_video, items_audio);

    // timeline graph that shows the number of posted items:
    draw_type_time('items_stats_holder', per_day, per_month, per_year);
    
    // barchart of user submissions
    draw_user_submissions('items_users_stats_holder', user);
  });
});

