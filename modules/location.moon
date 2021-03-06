json = require'json'
simplehttp = require'simplehttp'
httpserver = require'handler.http.server'
ev = require'ev'

loop = ev.Loop.default

on_data = (req, resp, data) ->
  --print('---- start request body')
  --io.write(data) if data
  --print('---- end request body')
  return

on_finished = (req, resp) ->
  channel = req.url\match('channel=(.+)')
  unless channel
    html = 'Invalid channel'
    resp\set_status(404)
    resp\set_header('Content-Type', 'text/html')
    resp\set_header('Content-Length', #html)
    resp\set_body(html)
    resp\send()
    return
  else
    channel = '#'..channel

  html = [[
  <!DOCTYPE html>
  <html>
  <head>

  <!-- adapted from dbot's map by xt -->
  <!-- set location with !location set yourlocation -->

  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1.0, user-scalable=no">
  <title>IRC member map</title>

  <style type="text/css">
  html { height: 100% }
  body { height: 100%; margin: 0; padding: 0 }
  </style>

  <script type="text/javascript" src="//maps.googleapis.com/maps/api/js?key=AIzaSyC2Jfvn8PUvx90DuVE9Ofwui2_3LTU4OPw&amp;sensor=false"></script>
  <script src="//google-maps-utility-library-v3.googlecode.com/svn/trunk/markerclustererplus/src/markerclusterer_packed.js"></script>
  </head><body>
  <div id="map" style="width: 100%; height: 100%"></div>
  <script type="text/javascript">
]]
  markerdata = {}
  for n,t in pairs ivar2.channels[channel].nicks
    pos = ivar2.persist["location:coords:#{n}"]
    if pos
      lat, lon = pos\match('([^,]+),([^,]+)')
      marker = {
        account: n,
        formattedAddress: ivar2.persist["location:place:#{n}"] or 'N/A',
        lng: tonumber(lon),
        lat: tonumber(lat),
        channel: channel
      }
      markerdata[#markerdata + 1] = marker

  if #markerdata == 0 then
    html = 'Invalid channel'
    resp\set_status(404)
    resp\set_header('Content-Type', 'text/html')
    resp\set_header('Content-Length', #html)
    resp\set_body(html)
    resp\send()
    return

  html ..= [[
  var map = new google.maps.Map(document.getElementById("map"), {
    center: new google.maps.LatLng(0, 0),
    zoom: 3
  });
  var infoWindow = null;
  var markers = [];
  
  function makeInfoWindow(info) {
    return new google.maps.InfoWindow({
      content: makeMarkerDiv(info)
    });
  }
  
  function makeMarkerDiv(h) {
    return "<div style='line-height:1.35;overflow:hidden;white-space:nowrap'>" + h + "</div>";
  }
  
  function makeMarkerInfo(m) {
    return "<strong>" + m.get("account") + " on " + m.get("channel") + "</strong> " +
      m.get("formattedAddress");
  }
  
  function dismiss() {
    if (infoWindow !== null) {
      infoWindow.close();
    }
  }
  ]]..json.encode(markerdata)..[[.forEach(function (loc) {
    var marker = new google.maps.Marker({
      position: new google.maps.LatLng(loc.lat, loc.lng)
    });
    marker.setValues(loc);
    markers.push(marker);
    google.maps.event.addListener(marker, "mouseover", function () {
      dismiss();
      infoWindow = makeInfoWindow(makeMarkerInfo(marker));
      infoWindow.open(map, marker);
    });
    google.maps.event.addListener(marker, "mouseout", dismiss);
    google.maps.event.addListener(marker, "click", function () {
      map.setZoom(Math.max(8, map.getZoom()));
      map.setCenter(marker.getPosition());
    });
  });
  var mc = new MarkerClusterer(map, markers, {
    averageCenter: true
  });
  google.maps.event.addListener(mc, "mouseover", function (c) {
    dismiss();
    var markers = c.getMarkers();
    infoWindow = makeInfoWindow(markers.map(makeMarkerInfo).join("<br>"));
    infoWindow.setPosition(c.getCenter());
    infoWindow.open(map);
  });
  google.maps.event.addListener(mc, "mouseout", dismiss);
  google.maps.event.addListener(mc, "click", dismiss);
  
  </script>
  </body>
  </html>
  ]]
  --print('---- request finished, send response')
  resp\set_status(200)
  resp\set_header('Content-Type', 'text/html')
  resp\set_header('Content-Length', #html)
  resp\set_body(html)
  resp\send()

on_response_sent = (resp) ->
  return

on_request = (server, req, resp) ->
  --print('---- start request headers: method =' .. req.method .. ', url = ' .. req.url)
  --for k,v in pairs(req.headers)
  --  print(k .. ": " .. v)
  
  --print('---- end request headers')
  -- check for '/favicon.ico' requests.
  if req.url\lower() == '/favicon.ico'
    -- return 404 Not found error
    resp\set_status(404)
    resp\send()
    return
  -- add callbacks to request.
  req.on_data = on_data
  req.on_finished = on_finished
  -- add response callbacks.
  resp.on_response_sent = on_response_sent


-- Check for already running server
if ivar2.webserver == nil
  print '---- Starting webserver ---- '
  ivar2.webserver = httpserver.new loop, { 
    name: "ivar2-HTTPServer/0.0.1",
    on_request: on_request,
    request_head_timeout: 1.0,
    request_body_timeout: 1.0,
    write_timeout: 10.0,
    keep_alive_timeout: 1.0,
    max_keep_alive_requests: 10,
  }

  ivar2.webserver\listen_uri "tcp://0.0.0.0:#{ivar2.config.webserverport}/"
else
  -- Swap out the request handler with the reloaded one
  ivar2.webserver.on_request = on_request

urlEncode = (str, space) ->
	space = space or '+'

	str = str\gsub '([^%w ])', (c) ->
        string.format  "%%%02X", string.byte(c) 
	return str\gsub(' ', space)

lookup = (address, cb) ->
  API_URL = 'http://maps.googleapis.com/maps/api/geocode/json'
  url = API_URL .. '?address=' .. urlEncode(address) .. '&sensor=false' .. '&language=en-GB'

  simplehttp url, (data) ->
      parsedData = json.decode data 
      if parsedData.status ~= 'OK'
        return false, parsedData.status or 'unknown API error'

      location = parsedData.results[1]
      locality, country, adminArea

      findComponent = (field, ...) ->
        n = select('#', ...)
        for i=1, n 
          searchType = select(i, ...)
          for _, component in ipairs(location.address_components)
            for _, type in ipairs(component.types)
              if type == searchType
                return component[field]

      locality = findComponent('long_name', 'locality', 'postal_town', 'route', 'establishment', 'natural_feature')
      adminArea = findComponent('short_name', 'administrative_area_level_1')
      country = findComponent('long_name', 'country') or 'Nowhereistan'

      if adminArea and #adminArea <= 5
        if not locality
          locality = adminArea
        else
          locality = locality..', '..adminArea

      locality = locality or 'Null'

      place = locality..', '..country

      cb place, location.geometry.location.lat..','..location.geometry.location.lng

PRIVMSG:
  '^%plocation set (.+)$': (source, destination, arg) =>
    lookup arg, (place, loc) ->
      nick = source.nick
      @.persist["location:place:#{nick}"] = place
      @.persist["location:coords:#{nick}"] = loc
      say '%s %s', place, loc
  '^%plocation map$': (source, destination, arg) =>
    channel = destination\sub(2)
    say "http://irc.lart.no:#{ivar2.config.webserverport}/?channel=#{channel}"
