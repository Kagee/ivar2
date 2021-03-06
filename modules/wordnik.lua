local simplehttp = require'simplehttp'
local json = require'json'

local headers = {
	['api_key'] = ivar2.config.wordnikAPIKey
}

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
end

local outFormat = '\002%s\002 <%s>'
local parseData = function(source, destination, data)
	data = json.decode(data)

	if(data.canonicalForm) then
		ivar2:Msg('privmsg', destination, source, "%s: That's correct.", source.nick)
	elseif(data.suggestions) then
		ivar2:Msg('privmsg', destination, source, "%s: %s", source.nick, table.concat(data.suggestions, ", "))
	else
		ivar2:Msg('privmsg', destination, source, "%s: I have no idea...", source.nick)
	end
end

local urlFormat = 'https://api.wordnik.com/v4/word.json/%s?&includeSuggestions=true'
local handler = function(self, source, destination, input)
	local word = urlEncode(input)

	simplehttp(
		{
			url = urlFormat:format(word),
			headers = headers,
		},

		function(data)
			parseData(source, destination, data)
		end
	)
end

return {
	PRIVMSG = {
		['(%S+)%s*%(sp%?%)'] = handler,
	},
}
