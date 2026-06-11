local M = {}

local KEYS = {
	{ key = "<CR>", action = "issue_actions", desc = "actions" },
	{ key = "<C-f>", action = "toggle_assignee", desc = "mine" },
	{ key = "<C-g>", action = "toggle_scope", desc = "scope" },
	{ key = "<C-s>", action = "toggle_state", desc = "state" },
	{ key = "<C-r>", action = "pick_repo", desc = "repo" },
	{ key = "<C-y>", action = "pick_group", desc = "group" },
	{ key = "<C-t>", action = "create_issue", desc = "new" },
}

local FOOTER = table.concat(
	vim.tbl_map(function(k)
		local letter = k.key:match("<C%-(.-)>")
		local key = letter and ("^" .. letter) or k.key
		return key .. " " .. k.desc
	end, KEYS),
	"  "
)

M.picker = {
	layout = {
		box = "vertical",
		width = 0.8,
		height = 0.7,
		border = true,
		title = "{title} {live} {flags}",
		title_pos = "center",
		footer = FOOTER,
		footer_pos = "center",
		{ win = "input", height = 1, border = "bottom" },
		{ win = "list", border = "none" },
		{ win = "preview", title = "{preview}", height = 0.7, border = "top" },
	},
}

M.actions_picker = {
	layout = {
		preset = "select",
		layout = { max_width = 54 },
	},
}

function M.input_keys()
	local keys = {}
	for _, entry in ipairs(KEYS) do
		keys[entry.key] = { entry.action, mode = { "i", "n" } }
	end
	return keys
end

function M.format(item)
	local ret
	if item.state == "closed" then
		ret = { { "✓ ", "DiagnosticInfo" }, { "#" .. tostring(item.iid), "Comment" }, { " " } }
	else
		ret = { { "○ ", "DiagnosticOk" }, { "#" .. tostring(item.iid), "SnacksPickerDimmed" }, { " " } }
	end

	vim.list_extend(ret, Snacks.picker.format.commit_message({ msg = item.title or "" }, {}))

	if item.repo and item.repo ~= "" then
		local repo_name = item.repo:match("[^/]+$") or item.repo
		ret[#ret + 1] = {
			col = 0,
			virt_text = { { "[" .. repo_name .. "]  " } },
			virt_text_pos = "right_align",
			hl_mode = "combine",
		}
	end

	return ret
end

function M.format_action(item, picker)
	local ret = {}

	if item.icon then
		ret[#ret + 1] = { item.icon, "Special" }
		ret[#ret + 1] = { " " }
	end

	local count = picker:count()
	local idx = tostring(item.idx)
	idx = (" "):rep(#tostring(count) - #idx) .. idx
	ret[#ret + 1] = { idx .. ".", "SnacksPickerIdx" }
	ret[#ret + 1] = { " " }
	ret[#ret + 1] = { item.desc or item.name }

	Snacks.picker.highlight.highlight(ret, {
		["#%d+"] = "Number",
	})

	return ret
end

return M
