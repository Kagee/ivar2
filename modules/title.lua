local iconv = require"iconv"
local uri = require"handler.uri"

local simplehttp = require'simplehttp'
local x0 = require'x0'
local html2unicode = require'html'
local base58 = require'base58'

local uri_parse = uri.parse
local DL_LIMIT = 2^16

local patterns = {
	-- X://Y url
	"^(https?://%S+)",
	"%f[%S](https?://%S+)",
	-- www.X.Y url
	"^(www%.[%w_-%%]+%.%S+)",
	"%f[%S](www%.[%w_-%%]+%.%S+)",
}

local translateCharset = {
	utf8 = 'utf-8',
	['x-sjis'] = 'sjis',
}

local verify = function(charset)
	if(charset) then
		charset = charset:lower()
		charset = translateCharset[charset] or charset

		return charset
	end
end

local guessCharset = function(headers, data)
	local charset
	-- XML:
	charset = verify(data:match('<%?xml .-encoding=[\'"]([^\'"]+)[\'"].->'))
	if(charset) then return charset end

	-- HTML5:
	charset = verify(data:match('<meta charset=[\'"]([\'"]+)[\'"]>'))
	if(charset) then return charset end

	-- HTML:
	charset = data:lower():match('<meta.-content=[\'"].-(charset=.-)[\'"].->')
	if(charset) then
		charset = verify(charset:match'=([^;]+)')
		if(charset) then return charset end
	end

	-- Header:
	local contentType = headers['Content-Type']
	if(contentType and contentType:match'charset') then
		charset = verify(contentType:match('charset=([^;]+)'))
		if(charset) then return charset end
	end
end

local handleData = function(headers, data)
	local charset = guessCharset(headers, data)
	if(charset and charset ~= 'utf-8') then
		local cd, err = iconv.new("utf-8", charset)
		if(cd) then
			data = cd:iconv(data)
		end
	end

	local title = data:match('<[tT][iI][tT][lL][eE]>(.-)</[tT][iI][tT][lL][eE]>')
	if(title) then
		for _, pattern in ipairs(patterns) do
			title = title:gsub(pattern, '<snip />')
		end

		title = html2unicode(title)
		title = title:gsub('%s%s+', ' ')

		if(title ~= '<snip />') then
			return title
		end
	end
end

local limitOutput = function(str)
	local limit = 100
	if(#str > limit) then
		str = str:sub(1, limit)
		if(#str == limit) then
			-- Clip it at the last space:
			str = str:match('^.* ')
		end
	end

	return str
end

local handleOutput = function(metadata)
	local output = {}
	for i=1, #metadata.processed do
		local lookup = metadata.processed[i]
		if(lookup.output) then
			table.insert(output, string.format('\002[%s]\002 %s', lookup.index, limitOutput(lookup.output)))
		end
	end

	if(#output > 0) then
		ivar2:Msg('privmsg', metadata.destination, metadata.source, table.concat(output, ' '))
	end
end

local customHosts = {
	['%.donmai%.us'] = function(metadata, index, info, indexString)
		local path = info.path

		if(path and path:match('/data/([^%.]+)')) then
			local md5 = path:match('/data/([^%.]+)')
			local domain = info.host
			simplehttp(
				string.format('http://%s/post/index.xml?tags=md5:%s', domain, md5),

				function(data, url, response)
					local id = data:match(' id="(%d+)"')
					local tags = data:match('tags="([^"]+)')

					metadata.processed[index] = {
						index = indexString,
						output = string.format('http://%s/post/show/%s/ - %s', domain, id, tags)
					}
					metadata.num = metadata.num - 1

					if(metadata.num == 0) then
						handleOutput(metadata)
					end
				end
			)
		end
	end,

	['open.spotify.com'] = function(metadata, index, info, indexString)
		local path = info.path

		if(path and path:match'/(%w+)/(.+)') then
			simplehttp(
				info.url,

				function(data, url, response)
					local title = html2unicode(data:match'<title>(.-) on Spotify</title>')
					local uri = data:match('property="og:audio" content="([^"]+)"')

					metadata.processed[index] = {
						index = indexString,
						output = string.format('%s: %s', title, uri)
					}
					metadata.num = metadata.num - 1

					if(metadata.num == 0) then
						handleOutput(metadata)
					end
				end
			)
		end
	end,

	['farm%d+%.static%.flickr.com'] = function(metadata, index, info, indexString)
		local path = info.path

		-- http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{secret}.jpg
		-- http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{secret}_[mstzb].jpg
		-- http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{o-secret}_o.(jpg|gif|png)
		if(path and path:match('/[^/]+/([^_]+)')) then
			local photoid = path:match('/[^/]+/([^_]+)')
			local url = string.format(
				"http://api.flickr.com/services/rest/?method=flickr.photos.getInfo&api_key=%s&photo_id=%s",
				ivar2.config.flickrAPIKey,
				photoid
			)

			simplehttp(
				url,

				function(data, url, response)
					local title = html2unicode(data:match('<title>([^<]+)</title>'))
					local owner = html2unicode(data:match('realname="([^"]+)"') or data:match('nsid="([^"]+)"'))

					metadata.processed[index] = {
						index = indexString,
						output = string.format(
							'%s by %s <http://flic.kr/p/%s/>',
							title,
							owner,
							base58.encode(photoid)
						)
					}
					metadata.num = metadata.num - 1

					if(metadata.num == 0) then
						handleOutput(metadata)
					end
				end
			)
		end
	end,
}

local fetchInformation = function(metadata, index, url, indexString)
	local info = uri_parse(url)
	info.url = url
	if(info.path == '') then
		url = url .. '/'
	end

	local host = info.host:gsub('^www%.', '')
	for pattern, customHandler in next, customHosts do
		if(host:match(pattern)) then
			return customHandler(metadata, index, info, indexString)
		end
	end

	simplehttp(
		url:gsub('#.*$', ''),

		function(data, url, response)
			local message = handleData(response.headers, data)
			metadata.processed[index] = {index = indexString, output = message}
			metadata.num = metadata.num - 1

			if(metadata.num == 0) then
				handleOutput(metadata)
			end
		end,
		true,
		DL_LIMIT
	)
end

return {
	PRIVMSG = {
		function(self, source, destination, argument)
			-- We don't want to pick up URLs from commands.
			if(argument:sub(1,1) == '!') then return end

			local tmp = {}
			local tmpOrder = {}
			local index = 1
			for split in argument:gmatch('%S+') do
				for i=1, #patterns do
					local _, count = split:gsub(patterns[i], function(url)
						if(url:sub(1,4) ~= 'http') then
							url = 'http://' .. url
						end

						if(not tmp[url]) then
							table.insert(tmpOrder, url)
							tmp[url] = index
						else
							tmp[url] = string.format('%s+%d', tmp[url], index)
						end
					end)

					if(count > 0) then
						index = index + 1
						break
					end
				end
			end

			if(#tmpOrder > 0) then
				local output = {
					num = #tmpOrder,
					source = source,
					destination = destination,
					processed = {},
				}

				for i=1, #tmpOrder do
					local url = tmpOrder[i]
					fetchInformation(output, i, url, tmp[url])
				end
			end
		end,
	},
}
