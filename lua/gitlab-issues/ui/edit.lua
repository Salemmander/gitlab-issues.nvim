local backend = require("gitlab-issues.backend.glab")
local frontmatter = require("gitlab-issues.ui.frontmatter")
local scratch = require("gitlab-issues.ui.scratch")
local submit = require("gitlab-issues.ui.submit")

local M = {}

function M.submit(item, win, ctx, close)
	if submit.is_submitting(win) then
		return
	end

	local title, description = frontmatter.parse(win:text())
	if not title then
		return
	end

	submit.set_submitting(win, true)
	vim.cmd.stopinsert()
	vim.notify("Updating issue #" .. item.iid .. "...", vim.log.levels.INFO)
	backend.update_issue(item, title, description, function(raw_issue, err)
		if err then
			submit.set_submitting(win, false)
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
		template = frontmatter.template(item.title, item.description),
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
