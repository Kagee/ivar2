local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local apiurl = 'http://www.tollpost.no/XMLServer/rest/trackandtrace/%s'

return {
	PRIVMSG = {
		['^%plunsj (%d+) (.*)$'] = shipmentTrack,
		['^%plunsj (%d+)$'] = shipmentLocate,
		['^%plunsj$'] = matHelp,
		['^%pmiddag (%d+) (.*)$'] = shipmentTrack,
		['^%pmiddag (%d+)$'] = shipmentLocate,
		['^%pmiddag$'] = matHelp,

	},
}
