-- launcher.luau
-- Type "/audio" in the launcher to see every profile across every card,
-- fuzzy-filtered as you type. Selecting one switches to it.
--
-- Respects the same visibility settings as the panel (hidden cards and
-- hidden profiles are skipped here too, except a card/profile that's
-- currently active always stays visible so you're never missing what's
-- actually in use).

local visibilityPath = noctalia.expandPath("~/.local/state/noctalia/plugin-alsaprofiles-visibility.json")

local function loadVisibility()
	local raw = noctalia.readFile(visibilityPath)
	local decoded = raw and noctalia.json.decode(raw) or nil
	if type(decoded) ~= "table" then
		decoded = {}
	end
	decoded.hiddenCards = decoded.hiddenCards or {}
	decoded.hiddenProfiles = decoded.hiddenProfiles or {}
	return decoded
end

local function isCardVisible(visibility, card)
	return not visibility.hiddenCards[card.name]
end

local function isProfileVisible(visibility, card, profile)
	local hidden = visibility.hiddenProfiles[card.name]
	return not (hidden and hidden[profile.id])
end

function onQuery(text)
	local cards = noctalia.state.get("cards") or {}
	local visibility = loadVisibility()

	if #cards == 0 then
		launcher.setResults(text, {
			{ id = "none", title = "No sound cards detected yet", glyph = "alert-circle" },
		})
		return
	end

	local results = {}
	for cardIdx, card in ipairs(cards) do
		if isCardVisible(visibility, card) then
			for _, p in ipairs(card.profiles) do
				local isActive = p.id == card.active
				if isProfileVisible(visibility, card, p) or isActive then
					local title = card.label .. " — " .. p.description
					local score = 1
					if text ~= "" then
						score = noctalia.fuzzyScore(text, title)
					end
					if score then
						table.insert(results, {
							id = tostring(cardIdx) .. "::" .. p.id,
							title = title,
							subtitle = p.id .. (p.available and "" or " (unavailable)"),
							glyph = isActive and "check" or "adjustments-horizontal",
							score = score,
						})
					end
				end
			end
		end
	end

	if #results == 0 then
		results = { { id = "none", title = "No matching profiles" } }
	end

	launcher.setResults(text, results)
end

function onActivate(id)
	if id == "none" then
		return
	end

	local cardIdxStr, profileId = id:match("^(%d+)::(.+)$")
	local cardIdx = tonumber(cardIdxStr)
	if not cardIdx then
		return
	end

	local cards = noctalia.state.get("cards") or {}
	local card = cards[cardIdx]
	if not card then
		noctalia.notifyError("ALSA Profiles", "No card known yet")
		return
	end

	noctalia.runAsync(string.format("pactl set-card-profile %q %q", card.name, profileId), function(result)
		if result.exitCode == 0 then
			noctalia.notify("ALSA Profiles", card.label .. " → " .. profileId)
		else
			local reason = (result.stderr and result.stderr ~= "") and noctalia.string.trim(result.stderr) or ("exit code " .. result.exitCode)
			noctalia.notifyError("ALSA Profiles", "Failed to switch " .. card.label .. ": " .. reason)
		end
		noctalia.runAsync("noctalia msg plugin matt/alsaprofiles:poller all refresh")
	end)
end
