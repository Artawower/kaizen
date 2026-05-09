"""Shared keybindings — loaded for all layouts."""
from prompt_toolkit.keys import Keys
import re


@events.on_ptk_create
def shared_keybindings(bindings, **kw):
    @bindings.add(Keys.ControlA)
    def _(event):
        event.current_buffer.cursor_position = 0

    @bindings.add(Keys.ControlU)
    def _(event):
        buffer = event.current_buffer
        buffer.delete_before_cursor(count=buffer.cursor_position)

    @bindings.add(Keys.ControlB)
    def _(event):
        buffer = event.current_buffer
        buffer.cursor_position = buffer.document.find_previous_word_beginning() or 0

    @bindings.add(Keys.ControlW)
    def _(event):
        """Delete word back including separator (space, /, ., -, _, :, etc.)"""
        buffer = event.current_buffer
        if buffer.complete_state:
            buffer.cancel_completion()
        text = buffer.document.text_before_cursor

        if not text:
            return

        separators_pattern = r'[\s/.\-_:;,@=|]'
        text_stripped = re.sub(f'{separators_pattern}+$', '', text)

        if not text_stripped:
            buffer.delete_before_cursor(count=len(text))
            return

        match = None
        for m in re.finditer(separators_pattern, text_stripped):
            match = m

        if match:
            delete_count = len(text) - match.end()
        else:
            delete_count = len(text)

        if delete_count > 0:
            buffer.delete_before_cursor(count=delete_count)

    @bindings.add(Keys.Escape, Keys.Delete)
    def _(event):
        """Delete word back (standard Ctrl+W: delete to whitespace)"""
        buffer = event.current_buffer
        pos = buffer.cursor_position
        text = buffer.text[:pos]

        if not text:
            return

        i = len(text) - 1
        while i >= 0 and text[i] in ' \t':
            i -= 1

        while i >= 0 and text[i] not in ' \t':
            i -= 1

        delete_count = len(text) - i - 1
        if delete_count > 0:
            buffer.delete_before_cursor(count=delete_count)
