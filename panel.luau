--!nonstrict
-- panel.luau
-- Scrollable list of every sound card with a profile dropdown each plus a settings
-- view (gear icon) for choosing which cards to show, and which profiles
-- to include in each card's dropdown.

-- Visibility choices persist to disk (survives Noctalia restarts) at:
--   ~/.local/state/noctalia/plugin-alsaprofiles-visibility.json

local MAX_CARDS = 10
local MAX_PROFILES = 64

local cards = noctalia.state.get("cards") or {}
local configuring = false
local expanded = {} -- [cardIndex] = true/false, which card's profile list is open

-- Persisted visibility settings

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

local visibility = loadVisibility()

local function saveVisibility()
	local encoded = noctalia.json.encode(visibility, false)
	if encoded then
		noctalia.writeFile(visibilityPath, encoded)
	end
end

local function isCardVisible(card)
	return not visibility.hiddenCards[card.name]
end

local function isProfileVisible(card, profile)
	local hidden = visibility.hiddenProfiles[card.name]
	return not (hidden and hidden[profile.id])
end

local function setProfileVisible(card, profile, visible)
	local hidden = visibility.hiddenProfiles[card.name]
	if not hidden then
		hidden = {}
		visibility.hiddenProfiles[card.name] = hidden
	end
	hidden[profile.id] = (not visible) or nil
	if next(hidden) == nil then
		visibility.hiddenProfiles[card.name] = nil
	end
end

-- Profiles shown in the normal-mode dropdown: hidden ones dropped, except
-- the currently active profile is always kept so the dropdown never shows
-- a wrong/blank selection if you hide the profile you're actively using.

local function visibleProfilesFor(card)
	local list = {}
	for _, p in ipairs(card.profiles) do
		if isProfileVisible(card, p) or p.id == card.active then
			table.insert(list, p)
		end
	end
	return list
end

-- Normal view: dropdown per visible card

local function findIndex(profiles, activeId)
	for i, p in ipairs(profiles) do
		if p.id == activeId then
			return i - 1 -- ui.select is 0-indexed
		end
	end
	return 0
end

local function cardSection(card, idx)
	local visibleProfiles = visibleProfilesFor(card)
	local options = {}
	for _, p in ipairs(visibleProfiles) do
		table.insert(options, p.available and p.description or (p.description .. " (unavailable)"))
	end

	local handlerName = idx <= MAX_CARDS and ("onProfileChange" .. idx) or nil

	return ui.column({ gap = 6 }, {
		ui.row({ align = "center", gap = 8 }, {
			ui.glyph({ name = "music" }),
			ui.label({ text = card.label, fontWeight = "medium", flexGrow = 1, color = "primary" }),
		}),
		ui.row({ align = "center", gap = 8 }, {
			ui.label({ text = "Profile:", color = "primary" }),
			ui.select({
				options = options,
				selectedIndex = findIndex(visibleProfiles, card.active),
				onChange = handlerName,
				flexGrow = 1,
			}),
		}),
	})
end

-- Configure view: show/hide cards, tickbox list of profiles 

local function configureSection(card, idx)
	local cardHandler = idx <= MAX_CARDS and ("onCardVisible" .. idx) or nil
	local expandHandler = idx <= MAX_CARDS and ("onExpandToggle" .. idx) or nil

	local rows = {
		ui.row({ align = "center", gap = 8 }, {
			ui.toggle({ checked = isCardVisible(card), onChange = cardHandler }),
			ui.label({ text = card.label, fontWeight = "medium", flexGrow = 1, color = "primary" }),
			ui.button({
				glyph = expanded[idx] and "chevron-up" or "chevron-down",
				onClick = expandHandler,
			}),
		}),
	}

	if expanded[idx] then
		local profileRows = {}
		for p_idx, p in ipairs(card.profiles) do
			if p_idx <= MAX_PROFILES then
				local toggleHandler = "onProfileToggle_" .. idx .. "_" .. p_idx
				table.insert(profileRows, ui.row({ align = "center", gap = 8 }, {
					ui.toggle({ checked = isProfileVisible(card, p), onChange = toggleHandler }),
					ui.label({ text = p.description, flexGrow = 1, color = "primary" }),
					ui.label({ text = p.id, color = "primary", fontSize = 11 }),
				}))
			end
		end
		if #card.profiles > MAX_PROFILES then
			table.insert(profileRows, ui.label({
				text = ("(%d more profiles not shown -- raise MAX_PROFILES in panel.luau)"):format(#card.profiles - MAX_PROFILES),
				color = "primary",
				fontSize = 11,
			}))
		end
		table.insert(rows, ui.column({ gap = 4, flexGrow = 1 }, profileRows))
	end

	return ui.column({ gap = 6 }, rows)
end

-- Render 

local function render()
	local rows = {}

	if configuring then
		for i, card in ipairs(cards) do
			table.insert(rows, configureSection(card, i))
			if i < #cards then
				table.insert(rows, ui.separator({}))
			end
		end
		if #rows == 0 then
			table.insert(rows, ui.label({ text = "No sound cards detected yet.", color = "primary" }))
		end
	else
		local shown = 0
		for i, card in ipairs(cards) do
			if isCardVisible(card) and #card.profiles > 0 then
				if shown > 0 then
					table.insert(rows, ui.separator({}))
				end
				table.insert(rows, cardSection(card, i))
				shown += 1
			end
		end
		if shown == 0 then
			table.insert(rows, ui.label({
				text = #cards == 0 and "No sound cards detected yet." or "All cards are hidden -- tap the gear icon to show one.",
				color = "primary",
			}))
		end
	end

	panel.render(ui.column({ flexGrow = 1, gap = 16 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.label({
				text = configuring and "Configure Visibility" or "Audio Configuration",
				fontSize = 16,
				fontWeight = "bold",
				color = "primary",
				flexGrow = 1,
			}),
			ui.button({ glyph = configuring and "check" or "settings", onClick = "onToggleConfigure" }),
			ui.button({ glyph = "close", onClick = "onCloseClicked" }),
		}),
		ui.scroll({ flexGrow = 1, gap = 16, align = "stretch" }, rows),
	}))
end

-- Actions 


local function switchProfile(cardIndex, optionIndex)
	local card = cards[cardIndex]
	if not card then
		return
	end
	local visibleProfiles = visibleProfilesFor(card)
	local profile = visibleProfiles[optionIndex + 1] -- optionIndex is 0-based
	if not profile then
		return
	end

	if not profile.available then
		noctalia.notify(
			"ALSA Profiles",
			profile.description .. " is marked unavailable by pactl (no device plugged into that port) -- switching to it usually won't produce sound."
		)
	end

	noctalia.runAsync(string.format("pactl set-card-profile %q %q", card.name, profile.id), function(result)
		noctalia.log(string.format(
			"alsaprofiles: set-card-profile %s %s -> exit %d, stderr: %s",
			card.name, profile.id, result.exitCode, result.stderr or ""
		))

		if result.exitCode == 0 then
			card.active = profile.id -- optimistic update so the UI feels instant
			noctalia.notify("ALSA Profiles", card.label .. " -> " .. profile.description)
		else
			local reason = (result.stderr and result.stderr ~= "") and noctalia.string.trim(result.stderr) or ("exit code " .. result.exitCode)
			noctalia.notifyError("ALSA Profiles", "Failed to switch " .. card.label .. ": " .. reason)
		end
		render()
		noctalia.runAsync("noctalia msg plugin matt/alsaprofiles:poller all refresh") -- resync from real state
	end)
end

local function setCardVisible(cardIndex, visible)
	local card = cards[cardIndex]
	if not card then
		return
	end
	visibility.hiddenCards[card.name] = (not visible) or nil
	saveVisibility()
	render()
end

local function toggleProfileVisible(cardIndex, profileIndex, visible)
	local card = cards[cardIndex]
	if not card then
		return
	end
	local profile = card.profiles[profileIndex]
	if not profile then
		return
	end
	setProfileVisible(card, profile, visible)
	saveVisibility()
	render()
end

local function toggleExpanded(cardIndex)
	expanded[cardIndex] = not expanded[cardIndex]
	render()
end

-- Pre-declared per-row handlers, probably a better way to do this....

function onProfileChange1(index, _text) switchProfile(1, tonumber(index) or 0) end
function onProfileChange2(index, _text) switchProfile(2, tonumber(index) or 0) end
function onProfileChange3(index, _text) switchProfile(3, tonumber(index) or 0) end
function onProfileChange4(index, _text) switchProfile(4, tonumber(index) or 0) end
function onProfileChange5(index, _text) switchProfile(5, tonumber(index) or 0) end
function onProfileChange6(index, _text) switchProfile(6, tonumber(index) or 0) end
function onProfileChange7(index, _text) switchProfile(7, tonumber(index) or 0) end
function onProfileChange8(index, _text) switchProfile(8, tonumber(index) or 0) end
function onProfileChange9(index, _text) switchProfile(9, tonumber(index) or 0) end
function onProfileChange10(index, _text) switchProfile(10, tonumber(index) or 0) end

function onCardVisible1(value) setCardVisible(1, value == "true") end
function onCardVisible2(value) setCardVisible(2, value == "true") end
function onCardVisible3(value) setCardVisible(3, value == "true") end
function onCardVisible4(value) setCardVisible(4, value == "true") end
function onCardVisible5(value) setCardVisible(5, value == "true") end
function onCardVisible6(value) setCardVisible(6, value == "true") end
function onCardVisible7(value) setCardVisible(7, value == "true") end
function onCardVisible8(value) setCardVisible(8, value == "true") end
function onCardVisible9(value) setCardVisible(9, value == "true") end
function onCardVisible10(value) setCardVisible(10, value == "true") end

function onExpandToggle1() toggleExpanded(1) end
function onExpandToggle2() toggleExpanded(2) end
function onExpandToggle3() toggleExpanded(3) end
function onExpandToggle4() toggleExpanded(4) end
function onExpandToggle5() toggleExpanded(5) end
function onExpandToggle6() toggleExpanded(6) end
function onExpandToggle7() toggleExpanded(7) end
function onExpandToggle8() toggleExpanded(8) end
function onExpandToggle9() toggleExpanded(9) end
function onExpandToggle10() toggleExpanded(10) end

function onProfileToggle_1_1(value) toggleProfileVisible(1, 1, value == "true") end
function onProfileToggle_1_2(value) toggleProfileVisible(1, 2, value == "true") end
function onProfileToggle_1_3(value) toggleProfileVisible(1, 3, value == "true") end
function onProfileToggle_1_4(value) toggleProfileVisible(1, 4, value == "true") end
function onProfileToggle_1_5(value) toggleProfileVisible(1, 5, value == "true") end
function onProfileToggle_1_6(value) toggleProfileVisible(1, 6, value == "true") end
function onProfileToggle_1_7(value) toggleProfileVisible(1, 7, value == "true") end
function onProfileToggle_1_8(value) toggleProfileVisible(1, 8, value == "true") end
function onProfileToggle_1_9(value) toggleProfileVisible(1, 9, value == "true") end
function onProfileToggle_1_10(value) toggleProfileVisible(1, 10, value == "true") end
function onProfileToggle_1_11(value) toggleProfileVisible(1, 11, value == "true") end
function onProfileToggle_1_12(value) toggleProfileVisible(1, 12, value == "true") end
function onProfileToggle_1_13(value) toggleProfileVisible(1, 13, value == "true") end
function onProfileToggle_1_14(value) toggleProfileVisible(1, 14, value == "true") end
function onProfileToggle_1_15(value) toggleProfileVisible(1, 15, value == "true") end
function onProfileToggle_1_16(value) toggleProfileVisible(1, 16, value == "true") end
function onProfileToggle_1_17(value) toggleProfileVisible(1, 17, value == "true") end
function onProfileToggle_1_18(value) toggleProfileVisible(1, 18, value == "true") end
function onProfileToggle_1_19(value) toggleProfileVisible(1, 19, value == "true") end
function onProfileToggle_1_20(value) toggleProfileVisible(1, 20, value == "true") end
function onProfileToggle_1_21(value) toggleProfileVisible(1, 21, value == "true") end
function onProfileToggle_1_22(value) toggleProfileVisible(1, 22, value == "true") end
function onProfileToggle_1_23(value) toggleProfileVisible(1, 23, value == "true") end
function onProfileToggle_1_24(value) toggleProfileVisible(1, 24, value == "true") end
function onProfileToggle_1_25(value) toggleProfileVisible(1, 25, value == "true") end
function onProfileToggle_1_26(value) toggleProfileVisible(1, 26, value == "true") end
function onProfileToggle_1_27(value) toggleProfileVisible(1, 27, value == "true") end
function onProfileToggle_1_28(value) toggleProfileVisible(1, 28, value == "true") end
function onProfileToggle_1_29(value) toggleProfileVisible(1, 29, value == "true") end
function onProfileToggle_1_30(value) toggleProfileVisible(1, 30, value == "true") end
function onProfileToggle_1_31(value) toggleProfileVisible(1, 31, value == "true") end
function onProfileToggle_1_32(value) toggleProfileVisible(1, 32, value == "true") end
function onProfileToggle_1_33(value) toggleProfileVisible(1, 33, value == "true") end
function onProfileToggle_1_34(value) toggleProfileVisible(1, 34, value == "true") end
function onProfileToggle_1_35(value) toggleProfileVisible(1, 35, value == "true") end
function onProfileToggle_1_36(value) toggleProfileVisible(1, 36, value == "true") end
function onProfileToggle_1_37(value) toggleProfileVisible(1, 37, value == "true") end
function onProfileToggle_1_38(value) toggleProfileVisible(1, 38, value == "true") end
function onProfileToggle_1_39(value) toggleProfileVisible(1, 39, value == "true") end
function onProfileToggle_1_40(value) toggleProfileVisible(1, 40, value == "true") end
function onProfileToggle_1_41(value) toggleProfileVisible(1, 41, value == "true") end
function onProfileToggle_1_42(value) toggleProfileVisible(1, 42, value == "true") end
function onProfileToggle_1_43(value) toggleProfileVisible(1, 43, value == "true") end
function onProfileToggle_1_44(value) toggleProfileVisible(1, 44, value == "true") end
function onProfileToggle_1_45(value) toggleProfileVisible(1, 45, value == "true") end
function onProfileToggle_1_46(value) toggleProfileVisible(1, 46, value == "true") end
function onProfileToggle_1_47(value) toggleProfileVisible(1, 47, value == "true") end
function onProfileToggle_1_48(value) toggleProfileVisible(1, 48, value == "true") end
function onProfileToggle_1_49(value) toggleProfileVisible(1, 49, value == "true") end
function onProfileToggle_1_50(value) toggleProfileVisible(1, 50, value == "true") end
function onProfileToggle_1_51(value) toggleProfileVisible(1, 51, value == "true") end
function onProfileToggle_1_52(value) toggleProfileVisible(1, 52, value == "true") end
function onProfileToggle_1_53(value) toggleProfileVisible(1, 53, value == "true") end
function onProfileToggle_1_54(value) toggleProfileVisible(1, 54, value == "true") end
function onProfileToggle_1_55(value) toggleProfileVisible(1, 55, value == "true") end
function onProfileToggle_1_56(value) toggleProfileVisible(1, 56, value == "true") end
function onProfileToggle_1_57(value) toggleProfileVisible(1, 57, value == "true") end
function onProfileToggle_1_58(value) toggleProfileVisible(1, 58, value == "true") end
function onProfileToggle_1_59(value) toggleProfileVisible(1, 59, value == "true") end
function onProfileToggle_1_60(value) toggleProfileVisible(1, 60, value == "true") end
function onProfileToggle_1_61(value) toggleProfileVisible(1, 61, value == "true") end
function onProfileToggle_1_62(value) toggleProfileVisible(1, 62, value == "true") end
function onProfileToggle_1_63(value) toggleProfileVisible(1, 63, value == "true") end
function onProfileToggle_1_64(value) toggleProfileVisible(1, 64, value == "true") end
function onProfileToggle_2_1(value) toggleProfileVisible(2, 1, value == "true") end
function onProfileToggle_2_2(value) toggleProfileVisible(2, 2, value == "true") end
function onProfileToggle_2_3(value) toggleProfileVisible(2, 3, value == "true") end
function onProfileToggle_2_4(value) toggleProfileVisible(2, 4, value == "true") end
function onProfileToggle_2_5(value) toggleProfileVisible(2, 5, value == "true") end
function onProfileToggle_2_6(value) toggleProfileVisible(2, 6, value == "true") end
function onProfileToggle_2_7(value) toggleProfileVisible(2, 7, value == "true") end
function onProfileToggle_2_8(value) toggleProfileVisible(2, 8, value == "true") end
function onProfileToggle_2_9(value) toggleProfileVisible(2, 9, value == "true") end
function onProfileToggle_2_10(value) toggleProfileVisible(2, 10, value == "true") end
function onProfileToggle_2_11(value) toggleProfileVisible(2, 11, value == "true") end
function onProfileToggle_2_12(value) toggleProfileVisible(2, 12, value == "true") end
function onProfileToggle_2_13(value) toggleProfileVisible(2, 13, value == "true") end
function onProfileToggle_2_14(value) toggleProfileVisible(2, 14, value == "true") end
function onProfileToggle_2_15(value) toggleProfileVisible(2, 15, value == "true") end
function onProfileToggle_2_16(value) toggleProfileVisible(2, 16, value == "true") end
function onProfileToggle_2_17(value) toggleProfileVisible(2, 17, value == "true") end
function onProfileToggle_2_18(value) toggleProfileVisible(2, 18, value == "true") end
function onProfileToggle_2_19(value) toggleProfileVisible(2, 19, value == "true") end
function onProfileToggle_2_20(value) toggleProfileVisible(2, 20, value == "true") end
function onProfileToggle_2_21(value) toggleProfileVisible(2, 21, value == "true") end
function onProfileToggle_2_22(value) toggleProfileVisible(2, 22, value == "true") end
function onProfileToggle_2_23(value) toggleProfileVisible(2, 23, value == "true") end
function onProfileToggle_2_24(value) toggleProfileVisible(2, 24, value == "true") end
function onProfileToggle_2_25(value) toggleProfileVisible(2, 25, value == "true") end
function onProfileToggle_2_26(value) toggleProfileVisible(2, 26, value == "true") end
function onProfileToggle_2_27(value) toggleProfileVisible(2, 27, value == "true") end
function onProfileToggle_2_28(value) toggleProfileVisible(2, 28, value == "true") end
function onProfileToggle_2_29(value) toggleProfileVisible(2, 29, value == "true") end
function onProfileToggle_2_30(value) toggleProfileVisible(2, 30, value == "true") end
function onProfileToggle_2_31(value) toggleProfileVisible(2, 31, value == "true") end
function onProfileToggle_2_32(value) toggleProfileVisible(2, 32, value == "true") end
function onProfileToggle_2_33(value) toggleProfileVisible(2, 33, value == "true") end
function onProfileToggle_2_34(value) toggleProfileVisible(2, 34, value == "true") end
function onProfileToggle_2_35(value) toggleProfileVisible(2, 35, value == "true") end
function onProfileToggle_2_36(value) toggleProfileVisible(2, 36, value == "true") end
function onProfileToggle_2_37(value) toggleProfileVisible(2, 37, value == "true") end
function onProfileToggle_2_38(value) toggleProfileVisible(2, 38, value == "true") end
function onProfileToggle_2_39(value) toggleProfileVisible(2, 39, value == "true") end
function onProfileToggle_2_40(value) toggleProfileVisible(2, 40, value == "true") end
function onProfileToggle_2_41(value) toggleProfileVisible(2, 41, value == "true") end
function onProfileToggle_2_42(value) toggleProfileVisible(2, 42, value == "true") end
function onProfileToggle_2_43(value) toggleProfileVisible(2, 43, value == "true") end
function onProfileToggle_2_44(value) toggleProfileVisible(2, 44, value == "true") end
function onProfileToggle_2_45(value) toggleProfileVisible(2, 45, value == "true") end
function onProfileToggle_2_46(value) toggleProfileVisible(2, 46, value == "true") end
function onProfileToggle_2_47(value) toggleProfileVisible(2, 47, value == "true") end
function onProfileToggle_2_48(value) toggleProfileVisible(2, 48, value == "true") end
function onProfileToggle_2_49(value) toggleProfileVisible(2, 49, value == "true") end
function onProfileToggle_2_50(value) toggleProfileVisible(2, 50, value == "true") end
function onProfileToggle_2_51(value) toggleProfileVisible(2, 51, value == "true") end
function onProfileToggle_2_52(value) toggleProfileVisible(2, 52, value == "true") end
function onProfileToggle_2_53(value) toggleProfileVisible(2, 53, value == "true") end
function onProfileToggle_2_54(value) toggleProfileVisible(2, 54, value == "true") end
function onProfileToggle_2_55(value) toggleProfileVisible(2, 55, value == "true") end
function onProfileToggle_2_56(value) toggleProfileVisible(2, 56, value == "true") end
function onProfileToggle_2_57(value) toggleProfileVisible(2, 57, value == "true") end
function onProfileToggle_2_58(value) toggleProfileVisible(2, 58, value == "true") end
function onProfileToggle_2_59(value) toggleProfileVisible(2, 59, value == "true") end
function onProfileToggle_2_60(value) toggleProfileVisible(2, 60, value == "true") end
function onProfileToggle_2_61(value) toggleProfileVisible(2, 61, value == "true") end
function onProfileToggle_2_62(value) toggleProfileVisible(2, 62, value == "true") end
function onProfileToggle_2_63(value) toggleProfileVisible(2, 63, value == "true") end
function onProfileToggle_2_64(value) toggleProfileVisible(2, 64, value == "true") end
function onProfileToggle_3_1(value) toggleProfileVisible(3, 1, value == "true") end
function onProfileToggle_3_2(value) toggleProfileVisible(3, 2, value == "true") end
function onProfileToggle_3_3(value) toggleProfileVisible(3, 3, value == "true") end
function onProfileToggle_3_4(value) toggleProfileVisible(3, 4, value == "true") end
function onProfileToggle_3_5(value) toggleProfileVisible(3, 5, value == "true") end
function onProfileToggle_3_6(value) toggleProfileVisible(3, 6, value == "true") end
function onProfileToggle_3_7(value) toggleProfileVisible(3, 7, value == "true") end
function onProfileToggle_3_8(value) toggleProfileVisible(3, 8, value == "true") end
function onProfileToggle_3_9(value) toggleProfileVisible(3, 9, value == "true") end
function onProfileToggle_3_10(value) toggleProfileVisible(3, 10, value == "true") end
function onProfileToggle_3_11(value) toggleProfileVisible(3, 11, value == "true") end
function onProfileToggle_3_12(value) toggleProfileVisible(3, 12, value == "true") end
function onProfileToggle_3_13(value) toggleProfileVisible(3, 13, value == "true") end
function onProfileToggle_3_14(value) toggleProfileVisible(3, 14, value == "true") end
function onProfileToggle_3_15(value) toggleProfileVisible(3, 15, value == "true") end
function onProfileToggle_3_16(value) toggleProfileVisible(3, 16, value == "true") end
function onProfileToggle_3_17(value) toggleProfileVisible(3, 17, value == "true") end
function onProfileToggle_3_18(value) toggleProfileVisible(3, 18, value == "true") end
function onProfileToggle_3_19(value) toggleProfileVisible(3, 19, value == "true") end
function onProfileToggle_3_20(value) toggleProfileVisible(3, 20, value == "true") end
function onProfileToggle_3_21(value) toggleProfileVisible(3, 21, value == "true") end
function onProfileToggle_3_22(value) toggleProfileVisible(3, 22, value == "true") end
function onProfileToggle_3_23(value) toggleProfileVisible(3, 23, value == "true") end
function onProfileToggle_3_24(value) toggleProfileVisible(3, 24, value == "true") end
function onProfileToggle_3_25(value) toggleProfileVisible(3, 25, value == "true") end
function onProfileToggle_3_26(value) toggleProfileVisible(3, 26, value == "true") end
function onProfileToggle_3_27(value) toggleProfileVisible(3, 27, value == "true") end
function onProfileToggle_3_28(value) toggleProfileVisible(3, 28, value == "true") end
function onProfileToggle_3_29(value) toggleProfileVisible(3, 29, value == "true") end
function onProfileToggle_3_30(value) toggleProfileVisible(3, 30, value == "true") end
function onProfileToggle_3_31(value) toggleProfileVisible(3, 31, value == "true") end
function onProfileToggle_3_32(value) toggleProfileVisible(3, 32, value == "true") end
function onProfileToggle_3_33(value) toggleProfileVisible(3, 33, value == "true") end
function onProfileToggle_3_34(value) toggleProfileVisible(3, 34, value == "true") end
function onProfileToggle_3_35(value) toggleProfileVisible(3, 35, value == "true") end
function onProfileToggle_3_36(value) toggleProfileVisible(3, 36, value == "true") end
function onProfileToggle_3_37(value) toggleProfileVisible(3, 37, value == "true") end
function onProfileToggle_3_38(value) toggleProfileVisible(3, 38, value == "true") end
function onProfileToggle_3_39(value) toggleProfileVisible(3, 39, value == "true") end
function onProfileToggle_3_40(value) toggleProfileVisible(3, 40, value == "true") end
function onProfileToggle_3_41(value) toggleProfileVisible(3, 41, value == "true") end
function onProfileToggle_3_42(value) toggleProfileVisible(3, 42, value == "true") end
function onProfileToggle_3_43(value) toggleProfileVisible(3, 43, value == "true") end
function onProfileToggle_3_44(value) toggleProfileVisible(3, 44, value == "true") end
function onProfileToggle_3_45(value) toggleProfileVisible(3, 45, value == "true") end
function onProfileToggle_3_46(value) toggleProfileVisible(3, 46, value == "true") end
function onProfileToggle_3_47(value) toggleProfileVisible(3, 47, value == "true") end
function onProfileToggle_3_48(value) toggleProfileVisible(3, 48, value == "true") end
function onProfileToggle_3_49(value) toggleProfileVisible(3, 49, value == "true") end
function onProfileToggle_3_50(value) toggleProfileVisible(3, 50, value == "true") end
function onProfileToggle_3_51(value) toggleProfileVisible(3, 51, value == "true") end
function onProfileToggle_3_52(value) toggleProfileVisible(3, 52, value == "true") end
function onProfileToggle_3_53(value) toggleProfileVisible(3, 53, value == "true") end
function onProfileToggle_3_54(value) toggleProfileVisible(3, 54, value == "true") end
function onProfileToggle_3_55(value) toggleProfileVisible(3, 55, value == "true") end
function onProfileToggle_3_56(value) toggleProfileVisible(3, 56, value == "true") end
function onProfileToggle_3_57(value) toggleProfileVisible(3, 57, value == "true") end
function onProfileToggle_3_58(value) toggleProfileVisible(3, 58, value == "true") end
function onProfileToggle_3_59(value) toggleProfileVisible(3, 59, value == "true") end
function onProfileToggle_3_60(value) toggleProfileVisible(3, 60, value == "true") end
function onProfileToggle_3_61(value) toggleProfileVisible(3, 61, value == "true") end
function onProfileToggle_3_62(value) toggleProfileVisible(3, 62, value == "true") end
function onProfileToggle_3_63(value) toggleProfileVisible(3, 63, value == "true") end
function onProfileToggle_3_64(value) toggleProfileVisible(3, 64, value == "true") end
function onProfileToggle_4_1(value) toggleProfileVisible(4, 1, value == "true") end
function onProfileToggle_4_2(value) toggleProfileVisible(4, 2, value == "true") end
function onProfileToggle_4_3(value) toggleProfileVisible(4, 3, value == "true") end
function onProfileToggle_4_4(value) toggleProfileVisible(4, 4, value == "true") end
function onProfileToggle_4_5(value) toggleProfileVisible(4, 5, value == "true") end
function onProfileToggle_4_6(value) toggleProfileVisible(4, 6, value == "true") end
function onProfileToggle_4_7(value) toggleProfileVisible(4, 7, value == "true") end
function onProfileToggle_4_8(value) toggleProfileVisible(4, 8, value == "true") end
function onProfileToggle_4_9(value) toggleProfileVisible(4, 9, value == "true") end
function onProfileToggle_4_10(value) toggleProfileVisible(4, 10, value == "true") end
function onProfileToggle_4_11(value) toggleProfileVisible(4, 11, value == "true") end
function onProfileToggle_4_12(value) toggleProfileVisible(4, 12, value == "true") end
function onProfileToggle_4_13(value) toggleProfileVisible(4, 13, value == "true") end
function onProfileToggle_4_14(value) toggleProfileVisible(4, 14, value == "true") end
function onProfileToggle_4_15(value) toggleProfileVisible(4, 15, value == "true") end
function onProfileToggle_4_16(value) toggleProfileVisible(4, 16, value == "true") end
function onProfileToggle_4_17(value) toggleProfileVisible(4, 17, value == "true") end
function onProfileToggle_4_18(value) toggleProfileVisible(4, 18, value == "true") end
function onProfileToggle_4_19(value) toggleProfileVisible(4, 19, value == "true") end
function onProfileToggle_4_20(value) toggleProfileVisible(4, 20, value == "true") end
function onProfileToggle_4_21(value) toggleProfileVisible(4, 21, value == "true") end
function onProfileToggle_4_22(value) toggleProfileVisible(4, 22, value == "true") end
function onProfileToggle_4_23(value) toggleProfileVisible(4, 23, value == "true") end
function onProfileToggle_4_24(value) toggleProfileVisible(4, 24, value == "true") end
function onProfileToggle_4_25(value) toggleProfileVisible(4, 25, value == "true") end
function onProfileToggle_4_26(value) toggleProfileVisible(4, 26, value == "true") end
function onProfileToggle_4_27(value) toggleProfileVisible(4, 27, value == "true") end
function onProfileToggle_4_28(value) toggleProfileVisible(4, 28, value == "true") end
function onProfileToggle_4_29(value) toggleProfileVisible(4, 29, value == "true") end
function onProfileToggle_4_30(value) toggleProfileVisible(4, 30, value == "true") end
function onProfileToggle_4_31(value) toggleProfileVisible(4, 31, value == "true") end
function onProfileToggle_4_32(value) toggleProfileVisible(4, 32, value == "true") end
function onProfileToggle_4_33(value) toggleProfileVisible(4, 33, value == "true") end
function onProfileToggle_4_34(value) toggleProfileVisible(4, 34, value == "true") end
function onProfileToggle_4_35(value) toggleProfileVisible(4, 35, value == "true") end
function onProfileToggle_4_36(value) toggleProfileVisible(4, 36, value == "true") end
function onProfileToggle_4_37(value) toggleProfileVisible(4, 37, value == "true") end
function onProfileToggle_4_38(value) toggleProfileVisible(4, 38, value == "true") end
function onProfileToggle_4_39(value) toggleProfileVisible(4, 39, value == "true") end
function onProfileToggle_4_40(value) toggleProfileVisible(4, 40, value == "true") end
function onProfileToggle_4_41(value) toggleProfileVisible(4, 41, value == "true") end
function onProfileToggle_4_42(value) toggleProfileVisible(4, 42, value == "true") end
function onProfileToggle_4_43(value) toggleProfileVisible(4, 43, value == "true") end
function onProfileToggle_4_44(value) toggleProfileVisible(4, 44, value == "true") end
function onProfileToggle_4_45(value) toggleProfileVisible(4, 45, value == "true") end
function onProfileToggle_4_46(value) toggleProfileVisible(4, 46, value == "true") end
function onProfileToggle_4_47(value) toggleProfileVisible(4, 47, value == "true") end
function onProfileToggle_4_48(value) toggleProfileVisible(4, 48, value == "true") end
function onProfileToggle_4_49(value) toggleProfileVisible(4, 49, value == "true") end
function onProfileToggle_4_50(value) toggleProfileVisible(4, 50, value == "true") end
function onProfileToggle_4_51(value) toggleProfileVisible(4, 51, value == "true") end
function onProfileToggle_4_52(value) toggleProfileVisible(4, 52, value == "true") end
function onProfileToggle_4_53(value) toggleProfileVisible(4, 53, value == "true") end
function onProfileToggle_4_54(value) toggleProfileVisible(4, 54, value == "true") end
function onProfileToggle_4_55(value) toggleProfileVisible(4, 55, value == "true") end
function onProfileToggle_4_56(value) toggleProfileVisible(4, 56, value == "true") end
function onProfileToggle_4_57(value) toggleProfileVisible(4, 57, value == "true") end
function onProfileToggle_4_58(value) toggleProfileVisible(4, 58, value == "true") end
function onProfileToggle_4_59(value) toggleProfileVisible(4, 59, value == "true") end
function onProfileToggle_4_60(value) toggleProfileVisible(4, 60, value == "true") end
function onProfileToggle_4_61(value) toggleProfileVisible(4, 61, value == "true") end
function onProfileToggle_4_62(value) toggleProfileVisible(4, 62, value == "true") end
function onProfileToggle_4_63(value) toggleProfileVisible(4, 63, value == "true") end
function onProfileToggle_4_64(value) toggleProfileVisible(4, 64, value == "true") end
function onProfileToggle_5_1(value) toggleProfileVisible(5, 1, value == "true") end
function onProfileToggle_5_2(value) toggleProfileVisible(5, 2, value == "true") end
function onProfileToggle_5_3(value) toggleProfileVisible(5, 3, value == "true") end
function onProfileToggle_5_4(value) toggleProfileVisible(5, 4, value == "true") end
function onProfileToggle_5_5(value) toggleProfileVisible(5, 5, value == "true") end
function onProfileToggle_5_6(value) toggleProfileVisible(5, 6, value == "true") end
function onProfileToggle_5_7(value) toggleProfileVisible(5, 7, value == "true") end
function onProfileToggle_5_8(value) toggleProfileVisible(5, 8, value == "true") end
function onProfileToggle_5_9(value) toggleProfileVisible(5, 9, value == "true") end
function onProfileToggle_5_10(value) toggleProfileVisible(5, 10, value == "true") end
function onProfileToggle_5_11(value) toggleProfileVisible(5, 11, value == "true") end
function onProfileToggle_5_12(value) toggleProfileVisible(5, 12, value == "true") end
function onProfileToggle_5_13(value) toggleProfileVisible(5, 13, value == "true") end
function onProfileToggle_5_14(value) toggleProfileVisible(5, 14, value == "true") end
function onProfileToggle_5_15(value) toggleProfileVisible(5, 15, value == "true") end
function onProfileToggle_5_16(value) toggleProfileVisible(5, 16, value == "true") end
function onProfileToggle_5_17(value) toggleProfileVisible(5, 17, value == "true") end
function onProfileToggle_5_18(value) toggleProfileVisible(5, 18, value == "true") end
function onProfileToggle_5_19(value) toggleProfileVisible(5, 19, value == "true") end
function onProfileToggle_5_20(value) toggleProfileVisible(5, 20, value == "true") end
function onProfileToggle_5_21(value) toggleProfileVisible(5, 21, value == "true") end
function onProfileToggle_5_22(value) toggleProfileVisible(5, 22, value == "true") end
function onProfileToggle_5_23(value) toggleProfileVisible(5, 23, value == "true") end
function onProfileToggle_5_24(value) toggleProfileVisible(5, 24, value == "true") end
function onProfileToggle_5_25(value) toggleProfileVisible(5, 25, value == "true") end
function onProfileToggle_5_26(value) toggleProfileVisible(5, 26, value == "true") end
function onProfileToggle_5_27(value) toggleProfileVisible(5, 27, value == "true") end
function onProfileToggle_5_28(value) toggleProfileVisible(5, 28, value == "true") end
function onProfileToggle_5_29(value) toggleProfileVisible(5, 29, value == "true") end
function onProfileToggle_5_30(value) toggleProfileVisible(5, 30, value == "true") end
function onProfileToggle_5_31(value) toggleProfileVisible(5, 31, value == "true") end
function onProfileToggle_5_32(value) toggleProfileVisible(5, 32, value == "true") end
function onProfileToggle_5_33(value) toggleProfileVisible(5, 33, value == "true") end
function onProfileToggle_5_34(value) toggleProfileVisible(5, 34, value == "true") end
function onProfileToggle_5_35(value) toggleProfileVisible(5, 35, value == "true") end
function onProfileToggle_5_36(value) toggleProfileVisible(5, 36, value == "true") end
function onProfileToggle_5_37(value) toggleProfileVisible(5, 37, value == "true") end
function onProfileToggle_5_38(value) toggleProfileVisible(5, 38, value == "true") end
function onProfileToggle_5_39(value) toggleProfileVisible(5, 39, value == "true") end
function onProfileToggle_5_40(value) toggleProfileVisible(5, 40, value == "true") end
function onProfileToggle_5_41(value) toggleProfileVisible(5, 41, value == "true") end
function onProfileToggle_5_42(value) toggleProfileVisible(5, 42, value == "true") end
function onProfileToggle_5_43(value) toggleProfileVisible(5, 43, value == "true") end
function onProfileToggle_5_44(value) toggleProfileVisible(5, 44, value == "true") end
function onProfileToggle_5_45(value) toggleProfileVisible(5, 45, value == "true") end
function onProfileToggle_5_46(value) toggleProfileVisible(5, 46, value == "true") end
function onProfileToggle_5_47(value) toggleProfileVisible(5, 47, value == "true") end
function onProfileToggle_5_48(value) toggleProfileVisible(5, 48, value == "true") end
function onProfileToggle_5_49(value) toggleProfileVisible(5, 49, value == "true") end
function onProfileToggle_5_50(value) toggleProfileVisible(5, 50, value == "true") end
function onProfileToggle_5_51(value) toggleProfileVisible(5, 51, value == "true") end
function onProfileToggle_5_52(value) toggleProfileVisible(5, 52, value == "true") end
function onProfileToggle_5_53(value) toggleProfileVisible(5, 53, value == "true") end
function onProfileToggle_5_54(value) toggleProfileVisible(5, 54, value == "true") end
function onProfileToggle_5_55(value) toggleProfileVisible(5, 55, value == "true") end
function onProfileToggle_5_56(value) toggleProfileVisible(5, 56, value == "true") end
function onProfileToggle_5_57(value) toggleProfileVisible(5, 57, value == "true") end
function onProfileToggle_5_58(value) toggleProfileVisible(5, 58, value == "true") end
function onProfileToggle_5_59(value) toggleProfileVisible(5, 59, value == "true") end
function onProfileToggle_5_60(value) toggleProfileVisible(5, 60, value == "true") end
function onProfileToggle_5_61(value) toggleProfileVisible(5, 61, value == "true") end
function onProfileToggle_5_62(value) toggleProfileVisible(5, 62, value == "true") end
function onProfileToggle_5_63(value) toggleProfileVisible(5, 63, value == "true") end
function onProfileToggle_5_64(value) toggleProfileVisible(5, 64, value == "true") end
function onProfileToggle_6_1(value) toggleProfileVisible(6, 1, value == "true") end
function onProfileToggle_6_2(value) toggleProfileVisible(6, 2, value == "true") end
function onProfileToggle_6_3(value) toggleProfileVisible(6, 3, value == "true") end
function onProfileToggle_6_4(value) toggleProfileVisible(6, 4, value == "true") end
function onProfileToggle_6_5(value) toggleProfileVisible(6, 5, value == "true") end
function onProfileToggle_6_6(value) toggleProfileVisible(6, 6, value == "true") end
function onProfileToggle_6_7(value) toggleProfileVisible(6, 7, value == "true") end
function onProfileToggle_6_8(value) toggleProfileVisible(6, 8, value == "true") end
function onProfileToggle_6_9(value) toggleProfileVisible(6, 9, value == "true") end
function onProfileToggle_6_10(value) toggleProfileVisible(6, 10, value == "true") end
function onProfileToggle_6_11(value) toggleProfileVisible(6, 11, value == "true") end
function onProfileToggle_6_12(value) toggleProfileVisible(6, 12, value == "true") end
function onProfileToggle_6_13(value) toggleProfileVisible(6, 13, value == "true") end
function onProfileToggle_6_14(value) toggleProfileVisible(6, 14, value == "true") end
function onProfileToggle_6_15(value) toggleProfileVisible(6, 15, value == "true") end
function onProfileToggle_6_16(value) toggleProfileVisible(6, 16, value == "true") end
function onProfileToggle_6_17(value) toggleProfileVisible(6, 17, value == "true") end
function onProfileToggle_6_18(value) toggleProfileVisible(6, 18, value == "true") end
function onProfileToggle_6_19(value) toggleProfileVisible(6, 19, value == "true") end
function onProfileToggle_6_20(value) toggleProfileVisible(6, 20, value == "true") end
function onProfileToggle_6_21(value) toggleProfileVisible(6, 21, value == "true") end
function onProfileToggle_6_22(value) toggleProfileVisible(6, 22, value == "true") end
function onProfileToggle_6_23(value) toggleProfileVisible(6, 23, value == "true") end
function onProfileToggle_6_24(value) toggleProfileVisible(6, 24, value == "true") end
function onProfileToggle_6_25(value) toggleProfileVisible(6, 25, value == "true") end
function onProfileToggle_6_26(value) toggleProfileVisible(6, 26, value == "true") end
function onProfileToggle_6_27(value) toggleProfileVisible(6, 27, value == "true") end
function onProfileToggle_6_28(value) toggleProfileVisible(6, 28, value == "true") end
function onProfileToggle_6_29(value) toggleProfileVisible(6, 29, value == "true") end
function onProfileToggle_6_30(value) toggleProfileVisible(6, 30, value == "true") end
function onProfileToggle_6_31(value) toggleProfileVisible(6, 31, value == "true") end
function onProfileToggle_6_32(value) toggleProfileVisible(6, 32, value == "true") end
function onProfileToggle_6_33(value) toggleProfileVisible(6, 33, value == "true") end
function onProfileToggle_6_34(value) toggleProfileVisible(6, 34, value == "true") end
function onProfileToggle_6_35(value) toggleProfileVisible(6, 35, value == "true") end
function onProfileToggle_6_36(value) toggleProfileVisible(6, 36, value == "true") end
function onProfileToggle_6_37(value) toggleProfileVisible(6, 37, value == "true") end
function onProfileToggle_6_38(value) toggleProfileVisible(6, 38, value == "true") end
function onProfileToggle_6_39(value) toggleProfileVisible(6, 39, value == "true") end
function onProfileToggle_6_40(value) toggleProfileVisible(6, 40, value == "true") end
function onProfileToggle_6_41(value) toggleProfileVisible(6, 41, value == "true") end
function onProfileToggle_6_42(value) toggleProfileVisible(6, 42, value == "true") end
function onProfileToggle_6_43(value) toggleProfileVisible(6, 43, value == "true") end
function onProfileToggle_6_44(value) toggleProfileVisible(6, 44, value == "true") end
function onProfileToggle_6_45(value) toggleProfileVisible(6, 45, value == "true") end
function onProfileToggle_6_46(value) toggleProfileVisible(6, 46, value == "true") end
function onProfileToggle_6_47(value) toggleProfileVisible(6, 47, value == "true") end
function onProfileToggle_6_48(value) toggleProfileVisible(6, 48, value == "true") end
function onProfileToggle_6_49(value) toggleProfileVisible(6, 49, value == "true") end
function onProfileToggle_6_50(value) toggleProfileVisible(6, 50, value == "true") end
function onProfileToggle_6_51(value) toggleProfileVisible(6, 51, value == "true") end
function onProfileToggle_6_52(value) toggleProfileVisible(6, 52, value == "true") end
function onProfileToggle_6_53(value) toggleProfileVisible(6, 53, value == "true") end
function onProfileToggle_6_54(value) toggleProfileVisible(6, 54, value == "true") end
function onProfileToggle_6_55(value) toggleProfileVisible(6, 55, value == "true") end
function onProfileToggle_6_56(value) toggleProfileVisible(6, 56, value == "true") end
function onProfileToggle_6_57(value) toggleProfileVisible(6, 57, value == "true") end
function onProfileToggle_6_58(value) toggleProfileVisible(6, 58, value == "true") end
function onProfileToggle_6_59(value) toggleProfileVisible(6, 59, value == "true") end
function onProfileToggle_6_60(value) toggleProfileVisible(6, 60, value == "true") end
function onProfileToggle_6_61(value) toggleProfileVisible(6, 61, value == "true") end
function onProfileToggle_6_62(value) toggleProfileVisible(6, 62, value == "true") end
function onProfileToggle_6_63(value) toggleProfileVisible(6, 63, value == "true") end
function onProfileToggle_6_64(value) toggleProfileVisible(6, 64, value == "true") end
function onProfileToggle_7_1(value) toggleProfileVisible(7, 1, value == "true") end
function onProfileToggle_7_2(value) toggleProfileVisible(7, 2, value == "true") end
function onProfileToggle_7_3(value) toggleProfileVisible(7, 3, value == "true") end
function onProfileToggle_7_4(value) toggleProfileVisible(7, 4, value == "true") end
function onProfileToggle_7_5(value) toggleProfileVisible(7, 5, value == "true") end
function onProfileToggle_7_6(value) toggleProfileVisible(7, 6, value == "true") end
function onProfileToggle_7_7(value) toggleProfileVisible(7, 7, value == "true") end
function onProfileToggle_7_8(value) toggleProfileVisible(7, 8, value == "true") end
function onProfileToggle_7_9(value) toggleProfileVisible(7, 9, value == "true") end
function onProfileToggle_7_10(value) toggleProfileVisible(7, 10, value == "true") end
function onProfileToggle_7_11(value) toggleProfileVisible(7, 11, value == "true") end
function onProfileToggle_7_12(value) toggleProfileVisible(7, 12, value == "true") end
function onProfileToggle_7_13(value) toggleProfileVisible(7, 13, value == "true") end
function onProfileToggle_7_14(value) toggleProfileVisible(7, 14, value == "true") end
function onProfileToggle_7_15(value) toggleProfileVisible(7, 15, value == "true") end
function onProfileToggle_7_16(value) toggleProfileVisible(7, 16, value == "true") end
function onProfileToggle_7_17(value) toggleProfileVisible(7, 17, value == "true") end
function onProfileToggle_7_18(value) toggleProfileVisible(7, 18, value == "true") end
function onProfileToggle_7_19(value) toggleProfileVisible(7, 19, value == "true") end
function onProfileToggle_7_20(value) toggleProfileVisible(7, 20, value == "true") end
function onProfileToggle_7_21(value) toggleProfileVisible(7, 21, value == "true") end
function onProfileToggle_7_22(value) toggleProfileVisible(7, 22, value == "true") end
function onProfileToggle_7_23(value) toggleProfileVisible(7, 23, value == "true") end
function onProfileToggle_7_24(value) toggleProfileVisible(7, 24, value == "true") end
function onProfileToggle_7_25(value) toggleProfileVisible(7, 25, value == "true") end
function onProfileToggle_7_26(value) toggleProfileVisible(7, 26, value == "true") end
function onProfileToggle_7_27(value) toggleProfileVisible(7, 27, value == "true") end
function onProfileToggle_7_28(value) toggleProfileVisible(7, 28, value == "true") end
function onProfileToggle_7_29(value) toggleProfileVisible(7, 29, value == "true") end
function onProfileToggle_7_30(value) toggleProfileVisible(7, 30, value == "true") end
function onProfileToggle_7_31(value) toggleProfileVisible(7, 31, value == "true") end
function onProfileToggle_7_32(value) toggleProfileVisible(7, 32, value == "true") end
function onProfileToggle_7_33(value) toggleProfileVisible(7, 33, value == "true") end
function onProfileToggle_7_34(value) toggleProfileVisible(7, 34, value == "true") end
function onProfileToggle_7_35(value) toggleProfileVisible(7, 35, value == "true") end
function onProfileToggle_7_36(value) toggleProfileVisible(7, 36, value == "true") end
function onProfileToggle_7_37(value) toggleProfileVisible(7, 37, value == "true") end
function onProfileToggle_7_38(value) toggleProfileVisible(7, 38, value == "true") end
function onProfileToggle_7_39(value) toggleProfileVisible(7, 39, value == "true") end
function onProfileToggle_7_40(value) toggleProfileVisible(7, 40, value == "true") end
function onProfileToggle_7_41(value) toggleProfileVisible(7, 41, value == "true") end
function onProfileToggle_7_42(value) toggleProfileVisible(7, 42, value == "true") end
function onProfileToggle_7_43(value) toggleProfileVisible(7, 43, value == "true") end
function onProfileToggle_7_44(value) toggleProfileVisible(7, 44, value == "true") end
function onProfileToggle_7_45(value) toggleProfileVisible(7, 45, value == "true") end
function onProfileToggle_7_46(value) toggleProfileVisible(7, 46, value == "true") end
function onProfileToggle_7_47(value) toggleProfileVisible(7, 47, value == "true") end
function onProfileToggle_7_48(value) toggleProfileVisible(7, 48, value == "true") end
function onProfileToggle_7_49(value) toggleProfileVisible(7, 49, value == "true") end
function onProfileToggle_7_50(value) toggleProfileVisible(7, 50, value == "true") end
function onProfileToggle_7_51(value) toggleProfileVisible(7, 51, value == "true") end
function onProfileToggle_7_52(value) toggleProfileVisible(7, 52, value == "true") end
function onProfileToggle_7_53(value) toggleProfileVisible(7, 53, value == "true") end
function onProfileToggle_7_54(value) toggleProfileVisible(7, 54, value == "true") end
function onProfileToggle_7_55(value) toggleProfileVisible(7, 55, value == "true") end
function onProfileToggle_7_56(value) toggleProfileVisible(7, 56, value == "true") end
function onProfileToggle_7_57(value) toggleProfileVisible(7, 57, value == "true") end
function onProfileToggle_7_58(value) toggleProfileVisible(7, 58, value == "true") end
function onProfileToggle_7_59(value) toggleProfileVisible(7, 59, value == "true") end
function onProfileToggle_7_60(value) toggleProfileVisible(7, 60, value == "true") end
function onProfileToggle_7_61(value) toggleProfileVisible(7, 61, value == "true") end
function onProfileToggle_7_62(value) toggleProfileVisible(7, 62, value == "true") end
function onProfileToggle_7_63(value) toggleProfileVisible(7, 63, value == "true") end
function onProfileToggle_7_64(value) toggleProfileVisible(7, 64, value == "true") end
function onProfileToggle_8_1(value) toggleProfileVisible(8, 1, value == "true") end
function onProfileToggle_8_2(value) toggleProfileVisible(8, 2, value == "true") end
function onProfileToggle_8_3(value) toggleProfileVisible(8, 3, value == "true") end
function onProfileToggle_8_4(value) toggleProfileVisible(8, 4, value == "true") end
function onProfileToggle_8_5(value) toggleProfileVisible(8, 5, value == "true") end
function onProfileToggle_8_6(value) toggleProfileVisible(8, 6, value == "true") end
function onProfileToggle_8_7(value) toggleProfileVisible(8, 7, value == "true") end
function onProfileToggle_8_8(value) toggleProfileVisible(8, 8, value == "true") end
function onProfileToggle_8_9(value) toggleProfileVisible(8, 9, value == "true") end
function onProfileToggle_8_10(value) toggleProfileVisible(8, 10, value == "true") end
function onProfileToggle_8_11(value) toggleProfileVisible(8, 11, value == "true") end
function onProfileToggle_8_12(value) toggleProfileVisible(8, 12, value == "true") end
function onProfileToggle_8_13(value) toggleProfileVisible(8, 13, value == "true") end
function onProfileToggle_8_14(value) toggleProfileVisible(8, 14, value == "true") end
function onProfileToggle_8_15(value) toggleProfileVisible(8, 15, value == "true") end
function onProfileToggle_8_16(value) toggleProfileVisible(8, 16, value == "true") end
function onProfileToggle_8_17(value) toggleProfileVisible(8, 17, value == "true") end
function onProfileToggle_8_18(value) toggleProfileVisible(8, 18, value == "true") end
function onProfileToggle_8_19(value) toggleProfileVisible(8, 19, value == "true") end
function onProfileToggle_8_20(value) toggleProfileVisible(8, 20, value == "true") end
function onProfileToggle_8_21(value) toggleProfileVisible(8, 21, value == "true") end
function onProfileToggle_8_22(value) toggleProfileVisible(8, 22, value == "true") end
function onProfileToggle_8_23(value) toggleProfileVisible(8, 23, value == "true") end
function onProfileToggle_8_24(value) toggleProfileVisible(8, 24, value == "true") end
function onProfileToggle_8_25(value) toggleProfileVisible(8, 25, value == "true") end
function onProfileToggle_8_26(value) toggleProfileVisible(8, 26, value == "true") end
function onProfileToggle_8_27(value) toggleProfileVisible(8, 27, value == "true") end
function onProfileToggle_8_28(value) toggleProfileVisible(8, 28, value == "true") end
function onProfileToggle_8_29(value) toggleProfileVisible(8, 29, value == "true") end
function onProfileToggle_8_30(value) toggleProfileVisible(8, 30, value == "true") end
function onProfileToggle_8_31(value) toggleProfileVisible(8, 31, value == "true") end
function onProfileToggle_8_32(value) toggleProfileVisible(8, 32, value == "true") end
function onProfileToggle_8_33(value) toggleProfileVisible(8, 33, value == "true") end
function onProfileToggle_8_34(value) toggleProfileVisible(8, 34, value == "true") end
function onProfileToggle_8_35(value) toggleProfileVisible(8, 35, value == "true") end
function onProfileToggle_8_36(value) toggleProfileVisible(8, 36, value == "true") end
function onProfileToggle_8_37(value) toggleProfileVisible(8, 37, value == "true") end
function onProfileToggle_8_38(value) toggleProfileVisible(8, 38, value == "true") end
function onProfileToggle_8_39(value) toggleProfileVisible(8, 39, value == "true") end
function onProfileToggle_8_40(value) toggleProfileVisible(8, 40, value == "true") end
function onProfileToggle_8_41(value) toggleProfileVisible(8, 41, value == "true") end
function onProfileToggle_8_42(value) toggleProfileVisible(8, 42, value == "true") end
function onProfileToggle_8_43(value) toggleProfileVisible(8, 43, value == "true") end
function onProfileToggle_8_44(value) toggleProfileVisible(8, 44, value == "true") end
function onProfileToggle_8_45(value) toggleProfileVisible(8, 45, value == "true") end
function onProfileToggle_8_46(value) toggleProfileVisible(8, 46, value == "true") end
function onProfileToggle_8_47(value) toggleProfileVisible(8, 47, value == "true") end
function onProfileToggle_8_48(value) toggleProfileVisible(8, 48, value == "true") end
function onProfileToggle_8_49(value) toggleProfileVisible(8, 49, value == "true") end
function onProfileToggle_8_50(value) toggleProfileVisible(8, 50, value == "true") end
function onProfileToggle_8_51(value) toggleProfileVisible(8, 51, value == "true") end
function onProfileToggle_8_52(value) toggleProfileVisible(8, 52, value == "true") end
function onProfileToggle_8_53(value) toggleProfileVisible(8, 53, value == "true") end
function onProfileToggle_8_54(value) toggleProfileVisible(8, 54, value == "true") end
function onProfileToggle_8_55(value) toggleProfileVisible(8, 55, value == "true") end
function onProfileToggle_8_56(value) toggleProfileVisible(8, 56, value == "true") end
function onProfileToggle_8_57(value) toggleProfileVisible(8, 57, value == "true") end
function onProfileToggle_8_58(value) toggleProfileVisible(8, 58, value == "true") end
function onProfileToggle_8_59(value) toggleProfileVisible(8, 59, value == "true") end
function onProfileToggle_8_60(value) toggleProfileVisible(8, 60, value == "true") end
function onProfileToggle_8_61(value) toggleProfileVisible(8, 61, value == "true") end
function onProfileToggle_8_62(value) toggleProfileVisible(8, 62, value == "true") end
function onProfileToggle_8_63(value) toggleProfileVisible(8, 63, value == "true") end
function onProfileToggle_8_64(value) toggleProfileVisible(8, 64, value == "true") end
function onProfileToggle_9_1(value) toggleProfileVisible(9, 1, value == "true") end
function onProfileToggle_9_2(value) toggleProfileVisible(9, 2, value == "true") end
function onProfileToggle_9_3(value) toggleProfileVisible(9, 3, value == "true") end
function onProfileToggle_9_4(value) toggleProfileVisible(9, 4, value == "true") end
function onProfileToggle_9_5(value) toggleProfileVisible(9, 5, value == "true") end
function onProfileToggle_9_6(value) toggleProfileVisible(9, 6, value == "true") end
function onProfileToggle_9_7(value) toggleProfileVisible(9, 7, value == "true") end
function onProfileToggle_9_8(value) toggleProfileVisible(9, 8, value == "true") end
function onProfileToggle_9_9(value) toggleProfileVisible(9, 9, value == "true") end
function onProfileToggle_9_10(value) toggleProfileVisible(9, 10, value == "true") end
function onProfileToggle_9_11(value) toggleProfileVisible(9, 11, value == "true") end
function onProfileToggle_9_12(value) toggleProfileVisible(9, 12, value == "true") end
function onProfileToggle_9_13(value) toggleProfileVisible(9, 13, value == "true") end
function onProfileToggle_9_14(value) toggleProfileVisible(9, 14, value == "true") end
function onProfileToggle_9_15(value) toggleProfileVisible(9, 15, value == "true") end
function onProfileToggle_9_16(value) toggleProfileVisible(9, 16, value == "true") end
function onProfileToggle_9_17(value) toggleProfileVisible(9, 17, value == "true") end
function onProfileToggle_9_18(value) toggleProfileVisible(9, 18, value == "true") end
function onProfileToggle_9_19(value) toggleProfileVisible(9, 19, value == "true") end
function onProfileToggle_9_20(value) toggleProfileVisible(9, 20, value == "true") end
function onProfileToggle_9_21(value) toggleProfileVisible(9, 21, value == "true") end
function onProfileToggle_9_22(value) toggleProfileVisible(9, 22, value == "true") end
function onProfileToggle_9_23(value) toggleProfileVisible(9, 23, value == "true") end
function onProfileToggle_9_24(value) toggleProfileVisible(9, 24, value == "true") end
function onProfileToggle_9_25(value) toggleProfileVisible(9, 25, value == "true") end
function onProfileToggle_9_26(value) toggleProfileVisible(9, 26, value == "true") end
function onProfileToggle_9_27(value) toggleProfileVisible(9, 27, value == "true") end
function onProfileToggle_9_28(value) toggleProfileVisible(9, 28, value == "true") end
function onProfileToggle_9_29(value) toggleProfileVisible(9, 29, value == "true") end
function onProfileToggle_9_30(value) toggleProfileVisible(9, 30, value == "true") end
function onProfileToggle_9_31(value) toggleProfileVisible(9, 31, value == "true") end
function onProfileToggle_9_32(value) toggleProfileVisible(9, 32, value == "true") end
function onProfileToggle_9_33(value) toggleProfileVisible(9, 33, value == "true") end
function onProfileToggle_9_34(value) toggleProfileVisible(9, 34, value == "true") end
function onProfileToggle_9_35(value) toggleProfileVisible(9, 35, value == "true") end
function onProfileToggle_9_36(value) toggleProfileVisible(9, 36, value == "true") end
function onProfileToggle_9_37(value) toggleProfileVisible(9, 37, value == "true") end
function onProfileToggle_9_38(value) toggleProfileVisible(9, 38, value == "true") end
function onProfileToggle_9_39(value) toggleProfileVisible(9, 39, value == "true") end
function onProfileToggle_9_40(value) toggleProfileVisible(9, 40, value == "true") end
function onProfileToggle_9_41(value) toggleProfileVisible(9, 41, value == "true") end
function onProfileToggle_9_42(value) toggleProfileVisible(9, 42, value == "true") end
function onProfileToggle_9_43(value) toggleProfileVisible(9, 43, value == "true") end
function onProfileToggle_9_44(value) toggleProfileVisible(9, 44, value == "true") end
function onProfileToggle_9_45(value) toggleProfileVisible(9, 45, value == "true") end
function onProfileToggle_9_46(value) toggleProfileVisible(9, 46, value == "true") end
function onProfileToggle_9_47(value) toggleProfileVisible(9, 47, value == "true") end
function onProfileToggle_9_48(value) toggleProfileVisible(9, 48, value == "true") end
function onProfileToggle_9_49(value) toggleProfileVisible(9, 49, value == "true") end
function onProfileToggle_9_50(value) toggleProfileVisible(9, 50, value == "true") end
function onProfileToggle_9_51(value) toggleProfileVisible(9, 51, value == "true") end
function onProfileToggle_9_52(value) toggleProfileVisible(9, 52, value == "true") end
function onProfileToggle_9_53(value) toggleProfileVisible(9, 53, value == "true") end
function onProfileToggle_9_54(value) toggleProfileVisible(9, 54, value == "true") end
function onProfileToggle_9_55(value) toggleProfileVisible(9, 55, value == "true") end
function onProfileToggle_9_56(value) toggleProfileVisible(9, 56, value == "true") end
function onProfileToggle_9_57(value) toggleProfileVisible(9, 57, value == "true") end
function onProfileToggle_9_58(value) toggleProfileVisible(9, 58, value == "true") end
function onProfileToggle_9_59(value) toggleProfileVisible(9, 59, value == "true") end
function onProfileToggle_9_60(value) toggleProfileVisible(9, 60, value == "true") end
function onProfileToggle_9_61(value) toggleProfileVisible(9, 61, value == "true") end
function onProfileToggle_9_62(value) toggleProfileVisible(9, 62, value == "true") end
function onProfileToggle_9_63(value) toggleProfileVisible(9, 63, value == "true") end
function onProfileToggle_9_64(value) toggleProfileVisible(9, 64, value == "true") end
function onProfileToggle_10_1(value) toggleProfileVisible(10, 1, value == "true") end
function onProfileToggle_10_2(value) toggleProfileVisible(10, 2, value == "true") end
function onProfileToggle_10_3(value) toggleProfileVisible(10, 3, value == "true") end
function onProfileToggle_10_4(value) toggleProfileVisible(10, 4, value == "true") end
function onProfileToggle_10_5(value) toggleProfileVisible(10, 5, value == "true") end
function onProfileToggle_10_6(value) toggleProfileVisible(10, 6, value == "true") end
function onProfileToggle_10_7(value) toggleProfileVisible(10, 7, value == "true") end
function onProfileToggle_10_8(value) toggleProfileVisible(10, 8, value == "true") end
function onProfileToggle_10_9(value) toggleProfileVisible(10, 9, value == "true") end
function onProfileToggle_10_10(value) toggleProfileVisible(10, 10, value == "true") end
function onProfileToggle_10_11(value) toggleProfileVisible(10, 11, value == "true") end
function onProfileToggle_10_12(value) toggleProfileVisible(10, 12, value == "true") end
function onProfileToggle_10_13(value) toggleProfileVisible(10, 13, value == "true") end
function onProfileToggle_10_14(value) toggleProfileVisible(10, 14, value == "true") end
function onProfileToggle_10_15(value) toggleProfileVisible(10, 15, value == "true") end
function onProfileToggle_10_16(value) toggleProfileVisible(10, 16, value == "true") end
function onProfileToggle_10_17(value) toggleProfileVisible(10, 17, value == "true") end
function onProfileToggle_10_18(value) toggleProfileVisible(10, 18, value == "true") end
function onProfileToggle_10_19(value) toggleProfileVisible(10, 19, value == "true") end
function onProfileToggle_10_20(value) toggleProfileVisible(10, 20, value == "true") end
function onProfileToggle_10_21(value) toggleProfileVisible(10, 21, value == "true") end
function onProfileToggle_10_22(value) toggleProfileVisible(10, 22, value == "true") end
function onProfileToggle_10_23(value) toggleProfileVisible(10, 23, value == "true") end
function onProfileToggle_10_24(value) toggleProfileVisible(10, 24, value == "true") end
function onProfileToggle_10_25(value) toggleProfileVisible(10, 25, value == "true") end
function onProfileToggle_10_26(value) toggleProfileVisible(10, 26, value == "true") end
function onProfileToggle_10_27(value) toggleProfileVisible(10, 27, value == "true") end
function onProfileToggle_10_28(value) toggleProfileVisible(10, 28, value == "true") end
function onProfileToggle_10_29(value) toggleProfileVisible(10, 29, value == "true") end
function onProfileToggle_10_30(value) toggleProfileVisible(10, 30, value == "true") end
function onProfileToggle_10_31(value) toggleProfileVisible(10, 31, value == "true") end
function onProfileToggle_10_32(value) toggleProfileVisible(10, 32, value == "true") end
function onProfileToggle_10_33(value) toggleProfileVisible(10, 33, value == "true") end
function onProfileToggle_10_34(value) toggleProfileVisible(10, 34, value == "true") end
function onProfileToggle_10_35(value) toggleProfileVisible(10, 35, value == "true") end
function onProfileToggle_10_36(value) toggleProfileVisible(10, 36, value == "true") end
function onProfileToggle_10_37(value) toggleProfileVisible(10, 37, value == "true") end
function onProfileToggle_10_38(value) toggleProfileVisible(10, 38, value == "true") end
function onProfileToggle_10_39(value) toggleProfileVisible(10, 39, value == "true") end
function onProfileToggle_10_40(value) toggleProfileVisible(10, 40, value == "true") end
function onProfileToggle_10_41(value) toggleProfileVisible(10, 41, value == "true") end
function onProfileToggle_10_42(value) toggleProfileVisible(10, 42, value == "true") end
function onProfileToggle_10_43(value) toggleProfileVisible(10, 43, value == "true") end
function onProfileToggle_10_44(value) toggleProfileVisible(10, 44, value == "true") end
function onProfileToggle_10_45(value) toggleProfileVisible(10, 45, value == "true") end
function onProfileToggle_10_46(value) toggleProfileVisible(10, 46, value == "true") end
function onProfileToggle_10_47(value) toggleProfileVisible(10, 47, value == "true") end
function onProfileToggle_10_48(value) toggleProfileVisible(10, 48, value == "true") end
function onProfileToggle_10_49(value) toggleProfileVisible(10, 49, value == "true") end
function onProfileToggle_10_50(value) toggleProfileVisible(10, 50, value == "true") end
function onProfileToggle_10_51(value) toggleProfileVisible(10, 51, value == "true") end
function onProfileToggle_10_52(value) toggleProfileVisible(10, 52, value == "true") end
function onProfileToggle_10_53(value) toggleProfileVisible(10, 53, value == "true") end
function onProfileToggle_10_54(value) toggleProfileVisible(10, 54, value == "true") end
function onProfileToggle_10_55(value) toggleProfileVisible(10, 55, value == "true") end
function onProfileToggle_10_56(value) toggleProfileVisible(10, 56, value == "true") end
function onProfileToggle_10_57(value) toggleProfileVisible(10, 57, value == "true") end
function onProfileToggle_10_58(value) toggleProfileVisible(10, 58, value == "true") end
function onProfileToggle_10_59(value) toggleProfileVisible(10, 59, value == "true") end
function onProfileToggle_10_60(value) toggleProfileVisible(10, 60, value == "true") end
function onProfileToggle_10_61(value) toggleProfileVisible(10, 61, value == "true") end
function onProfileToggle_10_62(value) toggleProfileVisible(10, 62, value == "true") end
function onProfileToggle_10_63(value) toggleProfileVisible(10, 63, value == "true") end
function onProfileToggle_10_64(value) toggleProfileVisible(10, 64, value == "true") end

function onToggleConfigure()
	configuring = not configuring
	render()
end

function onOpen(_context)
	cards = noctalia.state.get("cards") or {}
	render()
end

noctalia.state.watch("cards", function(value)
	cards = value or {}
	render()
end)

function onCloseClicked()
	panel.close()
end
