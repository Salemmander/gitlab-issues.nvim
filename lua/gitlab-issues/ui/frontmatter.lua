local M = {}

function M.parse(text)
	local lines = vim.split(text, "\n", { plain = true })
	local title

	if lines[1] ~= "---" then
		vim.notify("gitlab-issues: missing frontmatter", vim.log.levels.ERROR)
		return
	end

	local body_start
	for index = 2, #lines do
		local line = lines[index]
		if line == "---" then
			body_start = index + 1
			break
		end

		local field, value = line:match("^(%w+):%s*(.-)%s*$")
		if field == "Title" then
			title = vim.trim(value or "")
		elseif field and field ~= "" then
			vim.notify(("gitlab-issues: unknown field `%s` in frontmatter"):format(field), vim.log.levels.WARN)
		end
	end

	if not title or title == "" then
		vim.notify("gitlab-issues: missing required field `Title` in frontmatter", vim.log.levels.ERROR)
		return
	end

	if not body_start then
		vim.notify("gitlab-issues: missing closing frontmatter delimiter", vim.log.levels.ERROR)
		return
	end

	local body = table.concat(vim.list_slice(lines, body_start), "\n")
	return title, body:find("%S") and body or ""
end

function M.template(title, body)
	return table.concat({
		"---",
		"Title: " .. (title or ""),
		"---",
		"",
		body or "",
	}, "\n")
end

return M
