#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$PROJECT_DIR" <<'PY'
import faulthandler
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

faulthandler.dump_traceback_later(60, exit=True)
project = Path(sys.argv[1])
emacs = shutil.which('emacs')
client = shutil.which('emacsclient')
assert emacs and client, 'emacs and emacsclient are required'

with tempfile.TemporaryDirectory(prefix='kaizen-terminal-input-') as folder:
    root = Path(folder).resolve()
    server = root.name
    config = root / 'init.el'
    config.write_text('''
(require 'json)
(load TESTS nil t)
(when-let* ((directory (getenv "KAIZEN_KKP_DIRECTORY")))
  (add-to-list 'load-path directory))
(require 'kkp)
(eval (kaizen-test-form "dotfiles/dot_emacs.d/README.org" "(defun kkp--pre-delete-frame"))
(require 'corfu)
(require 'helixel)
(kaizen-test-corfu-bindings)
(eval (kaizen-test-form "dotfiles/dot_emacs.d/bindings/helixel.el" "(dolist (map (list minibuffer-local-map"))
(setq inhibit-startup-screen t
      initial-scratch-message nil
      xterm-query-timeout nil
      kkp-restore-legacy-keys-around-subprocesses t)
(global-kkp-mode 1)
(xterm-mouse-mode 1)
(defun kaizen-input-frame ()
  (seq-find (lambda (frame)
              (and (not (frame-parent frame))
                   (not (equal (terminal-name frame) "initial_terminal"))))
            (frame-list)))
(defun kaizen-input-state ()
  (with-selected-frame (kaizen-input-frame)
    (with-current-buffer (window-buffer (selected-window))
      (json-encode
       (list :active (kkp--active-p (frame-terminal))
             :text (buffer-substring-no-properties (if (minibufferp) (minibuffer-prompt-end) (point-min)) (point-max))
             :completion (and completion-in-region-mode t)
             :mode helixel--current-state
             :point (point)
             :minibuffer (minibufferp)
             :popup (and (frame-live-p corfu--frame)
                         (frame-visible-p corfu--frame) t))))))
(defun kaizen-input-start ()
  (with-selected-frame (kaizen-input-frame)
    (switch-to-buffer (get-buffer-create "kaizen-input-test"))
    (erase-buffer)
    (buffer-enable-undo)
    (insert "env")
    (helixel-mode)
    (helixel-insert)
    (corfu-mode 1)
    (setq-local completion-in-region-mode-predicate (lambda () t))
    (corfu--setup (point-min) (point) '("environment" "env") nil)
    (redisplay t)
    (corfu--exhibit)))
'''.replace('TESTS', json.dumps(str(project / 'tests/emacs-input.el'))))
    log = open(root / 'daemon.log', 'wb')
    daemon = subprocess.Popen([emacs, '-Q', f'--fg-daemon={server}', '-l', str(config)], stdout=log, stderr=log)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 100, 0, 0))
    tty = None
    flags = 0
    pending = bytearray()
    replies = []

    def reply(data):
        replies.append((time.monotonic() + 0.2, data))

    def pump(seconds=0.15):
        global flags
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            while replies and replies[0][0] <= time.monotonic():
                os.write(master, replies.pop(0)[1])
            if not select.select([master], [], [], 0.01)[0]:
                continue
            try:
                pending.extend(os.read(master, 65536))
            except OSError:
                break
            while b'\x1b[' in pending:
                start = pending.index(b'\x1b[')
                end = start + 2
                while end < len(pending) and not (0x40 <= pending[end] <= 0x7e):
                    end += 1
                if end == len(pending):
                    del pending[:start]
                    break
                command = bytes(pending[start:end + 1])
                del pending[:end + 1]
                if command == b'\x1b[6n':
                    reply(b'\x1b[1;1R')
                elif command == b'\x1b[c':
                    reply(b'\x1b[?1;2c')
                elif command == b'\x1b[?u':
                    reply(f'\x1b[?{flags}u'.encode())
                elif command.startswith(b'\x1b[>') and command.endswith(b'u'):
                    flags = int(command[3:-1])
                elif command == b'\x1b[<u':
                    flags = 0
                elif command.startswith(b'\x1b[=') and command.endswith(b'u'):
                    flags = int(command[3:-1].split(b';')[0])
            if b'\x1b[' not in pending:
                pending.clear()

    def evaluate(form):
        process = subprocess.Popen([client, '-s', server, '--eval', form], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 5
        while process.poll() is None and time.monotonic() < deadline:
            pump(0.02)
        if process.poll() is None:
            process.kill()
            process.communicate()
            raise TimeoutError(form)
        output, error = process.communicate()
        assert process.returncode == 0, output + error
        return output.strip()

    def state():
        return json.loads(json.loads(evaluate('(kaizen-input-state)')))

    def send(sequence, split=False):
        if split:
            os.write(master, sequence[:1])
            pump(0.01)
            sequence = sequence[1:]
        os.write(master, sequence)
        pump()
        return state()

    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            ready = subprocess.run([client, '-s', server, '--eval', '(emacs-pid)'], capture_output=True, timeout=2)
            if ready.returncode == 0:
                break
            assert daemon.poll() is None, (root / 'daemon.log').read_text()
            time.sleep(0.05)
        else:
            raise TimeoutError('test daemon did not start')
        tty = subprocess.Popen([client, '-s', server, '-nw'], env={**os.environ, 'TERM': 'xterm-256color'}, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        slave = None
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            pump()
            if evaluate('(and (kaizen-input-frame) (with-selected-frame (kaizen-input-frame) (kkp--active-p (frame-terminal))))') == '5':
                break
        else:
            raise TimeoutError('KKP negotiation failed: ' + evaluate('(kaizen-input-state)'))

        current = state()
        assert current['text'] == '', current
        print('passed: asynchronous xterm and KKP negotiation with delayed terminal replies', flush=True)
        for cycle in range(2):
            evaluate('(kaizen-input-start)')
            current = state()
            assert current['active'] == 5 and current['popup'] and current['completion'], current
            current = send(b'\x1b[<35;9;12M', split=True)
            assert current['text'] == 'env' and current['completion'], current
            current = send(b'\x1b[27u')
            assert not current['completion'] and current['mode'] == 'insert' and current['text'] == 'env', current
            current = send(b'\x1b[<35;92;8M\x1b[<35;81;18M')
            assert current['text'] == 'env' and current['mode'] == 'insert', current
            current = send(b'\x1b[D', split=True)
            assert current['text'] == 'env' and current['mode'] == 'insert' and current['point'] == 3, current
            current = send(b'\x1b[27u')
            assert current['mode'] == 'normal' and current['text'] == 'env', current
            current = send(b'\x1b[120;3u')
            assert current['minibuffer'] and current['text'] == '', current
            current = send(b'\x1b[<35;9;12M\x1b[<35;92;8M\x1b[<35;81;18M')
            assert current['minibuffer'] and current['text'] == '', current
            current = send(b'\x1b[27u')
            assert not current['minibuffer'] and current['text'] == 'env' and current['active'] == 5, current
        evaluate('(with-selected-frame (kaizen-input-frame) (delete-frame corfu--frame t))')
        evaluate('(kaizen-input-start)')
        current = state()
        assert current['active'] == 5 and current['popup'] and current['completion'], current
        current = send(b'\x1b[27u')
        assert current['active'] == 5 and not current['completion'] and current['mode'] == 'insert', current
        current = send(b'\x1b[27u')
        assert current['mode'] == 'normal' and current['text'] == 'env', current
        current = send(b'\x1b[<35;9;12M', split=True)
        assert current['active'] == 5 and current['text'] == 'env', current
        print('passed: dead Corfu frame recreation, repeated dismissal, modal exit, arrows, M-x and SGR mouse input', flush=True)
    finally:
        if daemon.poll() is None:
            try:
                evaluate('(kill-emacs 0)')
            except (AssertionError, TimeoutError):
                daemon.kill()
        if tty and tty.poll() is None:
            tty.kill()
        if tty:
            tty.wait(timeout=3)
        try:
            daemon.wait(timeout=3)
        except subprocess.TimeoutExpired:
            daemon.kill()
            daemon.wait(timeout=3)
        os.close(master)
        if slave is not None:
            os.close(slave)
        log.close()

print('Emacs terminal input tests passed')
PY
