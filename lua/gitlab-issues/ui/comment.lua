local backend = require("gitlab-issues.backend.glab")

local M = {}

function M.open(item)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"# Comment on #" .. item.iid .. ": " .. item.title,
		"",
	})

	local width = math.floor(vim.o.columns * 0.6)
	local height = math.floor(vim.o.lines * 0.35)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " GitLab Comment ",
		title_pos = "center",
		footer = " <C-s> submit  ·  <Esc> cancel ",
		footer_pos = "center",
	})

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function submit()
		local lines = vim.api.nvim_buf_get_lines(buf, 2, -1, false)
		local content = vim.trim(table.concat(lines, "\n"))
		if content == "" then
			vim.notify("gitlab-issues: comment is empty", vim.log.levels.WARN)
			return
		end

		close()
		vim.notify("Posting comment on #" .. item.iid .. "...", vim.log.levels.INFO)
		backend.add_comment(item, content, function(_, err)
			if err then
				vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
				return
			end

			vim.notify("Comment posted on #" .. item.iid, vim.log.levels.INFO)
		end)
	end

	vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf })
	vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = buf })
	vim.api.nvim_win_set_cursor(win, { 3, 0 })
	vim.cmd.startinsert()
end

return M
