local backend = require("gitlab-issues.backend.glab")

local M = {}

function M.open(item)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].bufhidden = "wipe"

	local width = math.floor(vim.o.columns * 0.6)
	local height = 15
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Comment on #" .. item.iid .. ": " .. item.title .. " ",
		title_pos = "center",
		footer = " <C-s> submit  ·  <Esc> cancel ",
		footer_pos = "center",
		zindex = 250,
	})

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function submit()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
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

			vim.notify("Comment posted on #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
		end)
	end

	vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf })
	vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = buf })
	vim.cmd("startinsert")
end

return M
