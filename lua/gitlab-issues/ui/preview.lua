local backend = require("gitlab-issues.backend.glab")

local M = {}

local ns = vim.api.nvim_create_namespace("gitlab-issues-preview")
local highlight = nil
local markdown = nil

local function setup_deps()
	highlight = highlight or Snacks.picker.highlight
	markdown = markdown or require("snacks.picker.util.markdown")
	require("snacks.gh")
end

local function parse_time(value)
	if type(value) ~= "string" or value == "" then
		return nil
	end

	local year, month, day, hour, min, sec = value:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
	if not year then
		return nil
	end

	local timestamp = os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec),
		isdst = false,
	})

	local now = os.time()
	local utc_date = os.date("!*t", now)
	utc_date.isdst = false
	return timestamp + os.difftime(now, os.time(utc_date))
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

local function time_prop(name, value)
	local timestamp = parse_time(value)
	if not timestamp then
		return nil
	end

	return plain_prop(name, Snacks.picker.util.reltime(timestamp), "SnacksPickerGitDate")
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
	local text = (description or ""):gsub("<%!%-%-.-%-%->%s*", "")
	local body = vim.split(text, "\n", { plain = true })

	while #body > 0 and body[1]:match("^%s*$") do
		table.remove(body, 1)
	end

	if #body == 0 then
		body = { "_No description._" }
	end

	return vim.tbl_map(function(line)
		return { { line } }
	end, body)
end

local function item_key(item)
	return (item.repo or "") .. "#" .. tostring(item.iid or "")
end

function M.refresh(picker)
	if picker and not picker.closed and picker.preview then
		picker.preview:show(picker, { force = true })
	end
end

local function fetch_comments(item, picker)
	if item._comments_loading or item._comments then
		return
	end

	item._comments_loading = true
	backend.list_comments(item, function(comments, err)
		item._comments_loading = false
		if err then
			item._comments_error = err
		else
			item._comments_error = nil
			item._comments = vim.tbl_filter(function(comment)
				return not comment.system and type(comment.body) == "string" and comment.body ~= ""
			end, comments or {})
			table.sort(item._comments, function(a, b)
				return (a.created_at or "") < (b.created_at or "")
			end)
		end

		if picker and not picker.closed then
			local current = picker:current()
			if current and item_key(current) == item_key(item) then
				M.refresh(picker)
			end
		end
	end)
end

function M.prefetch(items, limit)
	for index, item in ipairs(items or {}) do
		if limit and index > limit then
			break
		end

		fetch_comments(item)
	end
end

local function format_title(item)
	local ret = Snacks.picker.format.commit_message({ msg = item.title or "" }, {})
	ret[#ret + 1] = { " " }
	ret[#ret + 1] = { "#" .. tostring(item.iid or ""), "SnacksPickerDimmed" }
	return ret
end

local function metadata_lines(item)
	local lines = {
		format_title(item),
		{},
		status_prop(item),
		plain_prop("Repo", item.repo ~= "" and item.repo or "unknown", "@markup.link"),
		plain_prop("Author", item.author or "", "Identifier"),
		assignees_prop(item),
		labels_prop(item),
	}

	for _, line in ipairs({
		time_prop("Created", item.created_at),
		time_prop("Updated", item.updated_at),
		time_prop("Closed", item.closed_at),
	}) do
		if line then
			lines[#lines + 1] = line
		end
	end

	lines[#lines + 1] = {}
	lines[#lines + 1] = { { "---", "@punctuation.special.markdown" } }
	lines[#lines + 1] = {}

	return lines
end

local function comment_header(comment)
	local author = comment.author or {}
	local login = author.username or author.name or "unknown"
	local line = {
		{ " " .. login, "Identifier" },
	}

	local timestamp = parse_time(comment.created_at)
	if timestamp then
		line[#line + 1] = { " " }
		line[#line + 1] = { Snacks.picker.util.reltime(timestamp), "SnacksPickerGitDate" }
	end

	return line
end

local function comments_lines(item)
	if item._comments_error or item._comments_loading or not item._comments or #item._comments == 0 then
		return {}
	end

	local lines = { {} }
	for idx, comment in ipairs(item._comments) do
		if idx > 1 then
			lines[#lines + 1] = {}
		end

		lines[#lines + 1] = comment_header(comment)
		vim.list_extend(lines, body_lines(comment.body))
	end

	return lines
end

local function configure(buf, win)
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

function M.render(ctx)
	setup_deps()
	fetch_comments(ctx.item, ctx.picker)

	local buf = ctx.preview.win.buf
	ctx.preview:reset()
	configure(buf, ctx.preview.win.win)

	local lines = metadata_lines(ctx.item)
	vim.list_extend(lines, body_lines(ctx.item.description))
	vim.list_extend(lines, comments_lines(ctx.item))

	local changed = highlight.render(buf, ns, lines)
	if changed then
		markdown.render(buf, { bullets = false, images = false })
	end
end

return M
