local M = {}

local ns = vim.api.nvim_create_namespace("gitlab-issues-preview")
local highlight = nil
local markdown = nil

local function setup_preview_deps()
	highlight = highlight or Snacks.picker.highlight
	markdown = markdown or require("snacks.picker.util.markdown")
	require("snacks.gh")
end

local function state_highlight(state)
	if state == "opened" then
		return "DiagnosticOk"
	end
	if state == "closed" then
		return "DiagnosticError"
	end
	return "Title"
end

local function state_label(state)
	if state == "opened" then
		return "Open"
	end
	if state == "closed" then
		return "Closed"
	end
	return state or "Unknown"
end

local function state_icon(state)
	if state == "opened" then
		return " "
	end
	if state == "closed" then
		return " "
	end
	return " "
end

local function format_assignees(item)
	if item.assignee_usernames and #item.assignee_usernames > 0 then
		return table.concat(
			vim.tbl_map(function(username)
				return "@" .. username
			end, item.assignee_usernames),
			", "
		)
	end

	return item.assignees ~= "" and item.assignees or "none"
end

local function labels_from_item(item)
	if item.labels == "" then
		return {}
	end

	return vim.tbl_map(function(label)
		return vim.trim(label)
	end, vim.split(item.labels, ",", { plain = true, trimempty = true }))
end

local function prop_line(name, value)
	local line = {
		{ name, "SnacksGhLabel" },
		{ ":", "SnacksGhDelim" },
		{ " " },
	}

	highlight.extend(line, value)
	return line
end

local function plain_prop(name, value, hl)
	return prop_line(name, { { value, hl } })
end

local function status_prop(item)
	local state = state_label(item.state)
	local hl = state_highlight(item.state)
	local badge = highlight.badge(state_icon(item.state) .. state, hl)
	return prop_line("Status", badge)
end

local function assignees_prop(item)
	local assignees = item.assignee_usernames or {}
	if #assignees == 0 then
		return plain_prop("Assignees", format_assignees(item), "Comment")
	end

	local values = {}
	for _, username in ipairs(assignees) do
		highlight.extend(values, highlight.badge(" " .. username, "Identifier"))
	end

	return prop_line("Assignees", values)
end

local function labels_prop(item)
	local labels = labels_from_item(item)
	if #labels == 0 then
		return plain_prop("Labels", "none", "Comment")
	end

	local values = {}
	for _, label in ipairs(labels) do
		highlight.extend(values, highlight.badge(label, "Title"))
	end

	return prop_line("Labels", values)
end

local function body_lines(description)
	local lines = {}
	local text = (description or ""):gsub("<%!%-%-.-%-%->%s*", "")
	local body = vim.split(text, "\n", { plain = true })

	while #body > 0 and body[1]:match("^%s*$") do
		table.remove(body, 1)
	end

	if #body == 0 then
		body = { "_No description._" }
	end

	for _, line in ipairs(body) do
		lines[#lines + 1] = { { line } }
	end

	return lines
end

local function format_title(item)
	local ret = Snacks.picker.format.commit_message({ msg = item.title or "" }, {})
	ret[#ret + 1] = { " " }
	ret[#ret + 1] = { "#" .. tostring(item.iid or ""), "SnacksPickerDimmed" }

	return ret
end

local function render_preview(buf, item)
	setup_preview_deps()

	local lines = {
		format_title(item),
		{},
		status_prop(item),
		plain_prop("Repo", item.repo ~= "" and item.repo or "unknown", "@markup.link"),
		plain_prop("Author", item.author or "", "Identifier"),
		assignees_prop(item),
		labels_prop(item),
		plain_prop("Created", item.created or "", "SnacksPickerGitDate"),
		{},
		{ { "---", "@punctuation.special.markdown" } },
		{},
	}

	vim.list_extend(lines, body_lines(item.description))

	local changed = highlight.render(buf, ns, lines)
	if changed then
		markdown.render(buf, { bullets = false, images = false })
	end
end

local function configure_preview(buf, win)
	vim.bo[buf].filetype = "markdown.gitlab"
	vim.bo[buf].buftype = "nofile"
	if win and vim.api.nvim_win_is_valid(win) then
		vim.wo[win].wrap = true
		vim.wo[win].linebreak = true
		vim.wo[win].breakindent = true
		vim.wo[win].number = false
		vim.wo[win].relativenumber = false
		vim.wo[win].conceallevel = 2
		vim.wo[win].concealcursor = "n"
	end
end

function M.preview(ctx)
	local i = ctx.item
	ctx.preview:reset()
	configure_preview(ctx.preview.win.buf, ctx.preview.win.win)
	render_preview(ctx.preview.win.buf, i)
end

function M.filter(items, opts)
	return vim.tbl_filter(function(item)
		if opts.repo and item.repo ~= opts.repo then
			return false
		end
		if opts.assignee and not vim.tbl_contains(item.assignee_usernames, opts.assignee) then
			return false
		end
		if opts.state and item.state ~= opts.state then
			return false
		end
		return true
	end, items)
end

local function get_assignees(issue)
	return table.concat(
		vim.tbl_map(function(a)
			return a.name
		end, issue.assignees or {}),
		", "
	)
end

local function get_assignee_usernames(issue)
	return vim.tbl_map(function(a)
		return a.username
	end, issue.assignees or {})
end

local function get_labels(issue)
	return table.concat(
		vim.tbl_map(function(l)
			return type(l) == "string" and l or l.name
		end, issue.labels or {}),
		", "
	)
end

function M.make_item(raw_issue)
	local repo = raw_issue.references and (raw_issue.references.full or ""):match("(.+)#%d+") or ""
	return {
		text = string.format("#%-5d %s", raw_issue.iid, raw_issue.title),
		iid = raw_issue.iid,
		repo = repo or "",
		title = raw_issue.title,
		state = raw_issue.state,
		author = raw_issue.author and raw_issue.author.name or "",
		assignees = get_assignees(raw_issue),
		assignee_usernames = get_assignee_usernames(raw_issue),
		labels = get_labels(raw_issue),
		created = (raw_issue.created_at or ""):sub(1, 10),
		description = raw_issue.description or "",
		url = raw_issue.web_url or "",
	}
end

function M.make_items(raw_issues)
	return vim.tbl_map(M.make_item, raw_issues or {})
end

function M.replace(items, new_item)
	for idx, item in ipairs(items) do
		if item.iid == new_item.iid and item.repo == new_item.repo then
			items[idx] = new_item
			return
		end
	end
end

function M.repos_from_items(items)
	local seen = {}
	local repos = {}

	for _, item in ipairs(items) do
		if item.repo ~= "" and not seen[item.repo] then
			seen[item.repo] = true
			table.insert(repos, item.repo)
		end
	end

	table.sort(repos)
	table.insert(repos, 1, "All repos")

	return repos
end

return M
