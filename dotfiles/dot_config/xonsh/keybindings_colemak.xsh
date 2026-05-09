"""Colemak HNEI navigation overrides for xonsh/prompt_toolkit."""
from prompt_toolkit.keys import Keys
from prompt_toolkit.filters import Condition, vi_insert_mode, vi_mode
from prompt_toolkit.key_binding.vi_state import InputMode


@Condition
def not_in_insert_mode():
    return not vi_insert_mode()


@Condition
def in_vi_navigation_mode():
    return vi_mode() and not vi_insert_mode()


@events.on_ptk_create
def colemak_keybindings(bindings, **kw):
    # h = left
    @bindings.add('h', filter=in_vi_navigation_mode, eager=True)
    def vi_h_left(event):
        buffer = event.current_buffer
        buffer.cursor_position = max(0, buffer.cursor_position - 1)

    # n = down (was j in QWERTY)
    @bindings.add('n', filter=in_vi_navigation_mode, eager=True)
    def vi_n_down(event):
        event.current_buffer.history_forward(count=1)

    # e = up (was k in QWERTY)
    @bindings.add('e', filter=in_vi_navigation_mode, eager=True)
    def vi_e_up(event):
        event.current_buffer.history_backward(count=1)

    # i = right
    @bindings.add('i', filter=in_vi_navigation_mode, eager=True)
    def vi_i_right(event):
        buffer = event.current_buffer
        buffer.cursor_position = min(len(buffer.text), buffer.cursor_position + 1)

    # l = enter insert mode (l is where 'i' is in QWERTY)
    @bindings.add('l', filter=in_vi_navigation_mode, eager=True)
    def vi_l_insert(event):
        event.app.vi_state.input_mode = InputMode.INSERT

    # Ctrl+E = history backward (was Ctrl+K)
    @bindings.add(Keys.ControlE)
    def history_backward_prefix(event):
        event.current_buffer.history_backward(count=1)

    # Ctrl+N = history forward (was Ctrl+J)
    @bindings.add(Keys.ControlN)
    def history_forward_prefix(event):
        event.current_buffer.history_forward(count=1)
