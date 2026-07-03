-- service.luau
-- Polls `pactl -f json list cards` and publishes a `cards` array via
-- noctalia.state:
--   { { name = "alsa_card.pci-...", label = "Navi 48 HDMI/DP Audio Controller",
--       activeProfile = "output:hdmi-stereo",
--       profiles = { { id = "output:hdmi-stereo", description = "Digital Stereo (HDMI) Output",
--                      available = false }, ... } },
--     ... }
--
-- `label` comes from the card's `device.description` property (the same
-- field pavucontrol shows), falling back to the raw pactl card name.

local function parseCards(json)
	local decoded, err = noctalia.json.decode(json)
	if type(decoded) ~= "table" then
		noctalia.log("alsaprofiles: failed to decode pactl JSON: " .. tostring(err))
		return {}
	end

	local cards = {}
	for _, raw in ipairs(decoded) do
		local props = raw.properties or {}

		local profiles = {}
		for id, p in pairs(raw.profiles or {}) do
			table.insert(profiles, {
				id = id,
				description = (p.description and p.description ~= "") and p.description or id,
				available = p.available ~= false, -- real JSON boolean; missing/nil -> treat as available
				priority = tonumber(p.priority) or 0,
			})
		end
		-- JSON object key order isn't guaranteed, so sort for a stable,
		-- sensible dropdown order: pactl's own priority, highest first.
		table.sort(profiles, function(a, b)
			if a.priority ~= b.priority then
				return a.priority > b.priority
			end
			return a.id < b.id
		end)

		table.insert(cards, {
			name = raw.name,
			label = props["device.description"] or raw.name or "Unknown card",
			active = raw.active_profile,
			profiles = profiles,
		})
	end

	return cards
end

local function refresh()
	noctalia.runAsync("pactl -f json list cards", function(result)
		local output = result.stdout
		if not output or output == "" then
			noctalia.log("alsaprofiles: empty output from pactl -f json list cards")
			return
		end

		local cards = parseCards(output)
		if #cards == 0 then
			noctalia.log("alsaprofiles: no cards parsed from pactl JSON output")
			return
		end

		noctalia.state.set("cards", cards)
	end)
end

noctalia.setUpdateInterval(4000)
refresh()

function update()
	refresh()
end

-- Lets the panel force an immediate re-poll right after it switches a
-- profile, instead of waiting up to 4s for the next tick.
function onIpc(event)
	if event == "refresh" then
		refresh()
	end
end
