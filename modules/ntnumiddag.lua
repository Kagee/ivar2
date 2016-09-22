local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local apiurl = 'https://middag.hild1.no/middag.txt'

local function is_weekday(str)
    return say("localfunc")
end

local shipmentLocate = function(self, source, destination, pid)
	local nick = source.nick
	simplehttp(string.format(apiurl, pid), function(data)
		local info = json.decode(data)
		local root = info['TrackingInformationResponse']
		local cs = root['shipments']
		if not cs[1] then
			say('%s: Found nothing for shipment %s', nick, pid)
			return
		else
			cs = cs[1]
		end
		local out = {}
		local items = cs['items'][1]
		local status = string.format('\002%s\002', titlecase(items['status']))
		table.insert(out, string.format('Status: %s', status))
		for i, event in pairs(items['events']) do
			table.insert(out, eventHandler(event))
		end
		say('%s: %s', nick, table.concat(out, ', '))
	end)
end

local lunchTwo = function(self, source, destination, pid)
	return two("lunch", pid)
end

local lunchOne = function(self, source, destination, pid, alias)
	return say('For lookup: (!lunsj|!middag) <place (defaults to Gjøvik)> [<weekday (defaults to today)>]')
end

local dinnerTwo = function(self, source, destination, pid)
	return say('Not implemented')
end

local dinnerOne = function(self, source, destination, pid, alias)
	return say('For lookup: (!lunsj|!middag) <place (defaults to Gjøvik)> [<weekday (defaults to today)>]')
end

local middagHelp = function(self, source, destination)
	return say('For lookup: (!lunsj|!middag) <place (defaults to Gjøvik)> [<weekday (defaults to today)>]')
end

return {
	PRIVMSG = {
		['^%plunsj (%d+) (.*)$'] = lunchTwo,
		['^%plunsj (%d+)$'] = lunchOne,
		['^%plunsj$'] = dinnerHelp,
		['^%pmiddag (%d+) (.*)$'] = dinnerTwo,
		['^%pmiddag (%d+)$'] = dinnerOne,
		['^%pmiddag$'] = dinnerHelp,

	},
}
