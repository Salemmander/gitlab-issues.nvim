local M = {}

local KEYS = {
	{ key = "<C-o>", action = "view_issue", desc = "open" },
	{ key = "<C-e>", action = "assign_self", desc = "assign" },
	{ key = "<C-f>", action = "toggle_assignee", desc = "mine" },
	{ key = "<C-g>", action = "toggle_scope", desc = "scope" },
	{ key = "<C-s>", action = "toggle_state", desc = "state" },
	{ key = "<C-r>", action = "pick_repo", desc = "repo" },
	{ key = "<C-t>", action = "create_issue", desc = "new" },
	{ key = "<C-x>", action = "close_reopen", desc = "close/open" },
	{ key = "<C-b>", action = "add_comment", desc = "comment" },
}

local FOOTER = table.concat(
	vim.tbl_map(function(k)
		local letter = k.key:match("<C%-(.-)>")
		return "^" .. letter .. " " .. k.desc
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
		ret = { { "✓ ", "DiagnosticInfo" }, { item.text, "Comment" } }
	else
		ret = { { "○ ", "DiagnosticOk" }, { item.text } }
	end

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

return M
