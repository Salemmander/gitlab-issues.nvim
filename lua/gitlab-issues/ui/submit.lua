local M = {}

function M.is_submitting(win)
	return win and win.buf and vim.api.nvim_buf_is_valid(win.buf) and vim.b[win.buf].gitlab_issues_submitting
end

function M.set_submitting(win, value)
	if win and win.buf and vim.api.nvim_buf_is_valid(win.buf) then
		vim.b[win.buf].gitlab_issues_submitting = value
	end
end

return M
