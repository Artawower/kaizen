function setup(config)
  config.action("open in editor", function()
    local file = context.file()
    if not file then
      flash("Select file first (press l for details)")
      return
    end
    exec_shell("emacsclient -nw '" .. file:gsub("'", "'\\''") .. "'")
  end, {
    key = "O",
    scope = "revisions.details",
    desc = "open in editor",
  })
end
