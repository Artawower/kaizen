"""QWERTY standard keybindings for xonsh/prompt_toolkit."""
from prompt_toolkit.keys import Keys


@events.on_ptk_create
def qwerty_keybindings(bindings, **kw):
    @bindings.add(Keys.ControlK)
    def history_backward_prefix(event):
        event.current_buffer.history_backward(count=1)

    @bindings.add(Keys.ControlJ)
    def history_forward_prefix(event):
        event.current_buffer.history_forward(count=1)

    # Ctrl+E = end of line (standard readline)
    @bindings.add(Keys.ControlE)
    def _(event):
        event.current_buffer.cursor_position = len(event.current_buffer.text)
