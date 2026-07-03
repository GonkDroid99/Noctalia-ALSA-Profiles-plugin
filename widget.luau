-- widget.luau
-- Small bar entry — its only job is to show a glyph/tooltip summary and open the panel

local function summarize(cards)
	if not cards or #cards == 0 then
		return "No cards detected yet"
	end
	local lines = {}
	for _, c in ipairs(cards) do
		table.insert(lines, c.label .. ": " .. (c.active or "?"))
	end
	return table.concat(lines, "\n")
end

local function render()
	local cards = noctalia.state.get("cards")
	barWidget.setGlyph("adjustments-horizontal") -- audio config/routing, distinct from the volume icon
	barWidget.setTooltip(summarize(cards))
end

function update()
	noctalia.setUpdateInterval(3000)
	render()
end

noctalia.state.watch("cards", function()
	render()
end)

function onClick()
	noctalia.togglePanel("matt/alsaprofiles:panel")
end
