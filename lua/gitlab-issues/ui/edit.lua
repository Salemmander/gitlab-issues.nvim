local backend = require("gitlab-issues.backend.glab")
local scratch = require("gitlab-issues.ui.scratch")

local M = {}

local function parse(text)
	local title
	local body = text:gsub("^(%-%-%-\n.-\n%-%-%-\n%s*)", function(fm)
		fm = fm:gsub("^%-%-%-\n", ""):gsub("\n%-%-%-\n%s*$", "")
		for _, line in ipairs(vim.split(fm, "\n")) do
			local field, value = line:match("^(%w+):%s*(.-)%s*$")
			if field == "Title" then
				title = vim.trim(value or "")
			elseif field and field ~= "" then
				vim.notify(("gitlab-issues: unknown field `%s` in frontmatter"):format(field), vim.log.levels.WARN)
			end
		end
		return ""
	end)

	if not title or title == "" then
		vim.notify("gitlab-issues: missing required field `Title` in frontmatter", vim.log.levels.ERROR)
		return
	end

	return title, vim.trim(body)
end

local function template(item)
	return table.concat({
		"---",
		"Title: " .. (item.title or ""),
		"---",
		"",
		item.description or "",
	}, "\n")
end

function M.submit(item, win, ctx, close)
	local title, description = parse(win:text())
	if not title then
		return
	end

	vim.cmd.stopinsert()
	vim.notify("Updating issue #" .. item.iid .. "...", vim.log.levels.INFO)
	backend.update_issue(item, title, description, function(raw_issue, err)
		if err then
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			return
		end

		vim.notify("Updated issue #" .. item.iid, vim.log.levels.INFO)
		close(win)
		if ctx and ctx.picker and ctx.refresh_item and not ctx.picker.closed then
			ctx.refresh_item(ctx.picker, item, raw_issue)
			ctx.picker:focus()
		end
	end)
end

function M.open(item, ctx)
	scratch.open({
		name = "Edit issue #" .. item.iid,
		template = template(item),
		filekey = item.repo .. "/issue/" .. tostring(item.iid) .. "/edit",
		ctx = ctx,
		height = 15,
		cursor = { 2, #"Title: " },
		on_submit = function(win, close)
			M.submit(item, win, ctx, close)
		end,
	})
end

return M
