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

faulthandler.dump_traceback_later(90, exit=True)
project = Path(sys.argv[1])
source = (project / 'dotfiles/dot_emacs.d/README.org').read_text()
blocks = source.split('** Disable menu bar mode and other stuff\n#+BEGIN_SRC emacs-lisp\n', 1)[1].split('#+END_SRC', 1)[0]
blocks += '\n' + '\n'.join(source.split(f'*** {heading}\n#+BEGIN_SRC emacs-lisp\n', 1)[1].split('#+END_SRC', 1)[0]
                          for heading in ['Terminal background', 'Terminal client colors', 'Terminal cursor', 'Terminal mouse'])
emacs = shutil.which('emacs')
client = shutil.which('emacsclient')
assert emacs and client and shutil.which('tic'), 'emacs, emacsclient and tic are required'

with tempfile.TemporaryDirectory(prefix='kaizen-emacs-terminal-') as folder:
    root = Path(folder).resolve()
    env = os.environ.copy()
    for key in ['TERM', 'COLORTERM', 'TERMINFO', 'TERMINFO_DIRS', 'TERMCAP']:
        env.pop(key, None)
    env['HOME'] = str(root)
    install = [sys.executable, str(project / 'features/hooks/emacs/post_install.py'), 'linux']
    subprocess.run(install, env=env, check=True, capture_output=True)
    entries = list((root / '.terminfo').glob('*/xterm-kaizen-direct'))
    assert len(entries) == 1, entries
    original = entries[0].read_bytes()
    subprocess.run(install, env=env, check=True, capture_output=True)
    assert entries[0].read_bytes() == original
    print('passed: idempotent user terminfo installation', flush=True)
    guards = root / 'guards.el'
    guards.write_text("(require 'ert)\n(require 'cl-lib)\n" + blocks + '''
(ert-deftest terminal-menu-bars-are-hidden-without-changing-gui-frames ()
  (let (changes)
    (cl-letf (((symbol-function 'frame-list) (lambda () '(terminal graphical)))
              ((symbol-function 'display-graphic-p) (lambda (frame) (eq frame 'graphical)))
              ((symbol-function 'set-frame-parameter)
               (lambda (frame parameter value)
                 (push (list frame parameter value) changes))))
      (my/hide-terminal-menu-bars 'graphical)
      (should (equal changes '((terminal menu-bar-lines 0)))))))

(ert-deftest graphical-background-is-untouched ()
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (_) t))
            ((symbol-function 'set-face-background)
             (lambda (&rest _) (ert-fail "GUI face was changed"))))
    (my/setup-terminal-background 'graphical-frame)))

(ert-deftest only-explicit-truecolor-clients-are-upgraded ()
  (let ((process-environment '("COLORTERM=truecolor")))
    (dolist (environment '(nil ("HOME=/tmp") ("COLORTERM") ("COLORTERM=256color")))
      (cl-letf (((symbol-function 'process-get) (lambda (&rest _) environment))
                ((symbol-function 'file-readable-p) (lambda (_) t)))
        (let ((arguments '("/dev/tty" "xterm-256color" client)))
          (should (eq arguments (my/server-truecolor-tty arguments))))))))

(ert-deftest missing-terminfo-preserves-terminal-type ()
  (cl-letf (((symbol-function 'process-get) (lambda (&rest _) '("COLORTERM=truecolor")))
            ((symbol-function 'file-readable-p) (lambda (_) nil)))
    (let ((arguments '("/dev/tty" "xterm-256color" client)))
      (should (eq arguments (my/server-truecolor-tty arguments))))))

(ert-deftest other-terminal-types-are-untouched ()
  (cl-letf (((symbol-function 'process-get) (lambda (&rest _) '("COLORTERM=truecolor")))
            ((symbol-function 'file-readable-p) (lambda (_) t)))
    (dolist (terminal '("screen-256color" "linux" "xterm-kitty"))
      (let ((arguments (list "/dev/tty" terminal 'client)))
        (should (eq arguments (my/server-truecolor-tty arguments)))))))

(ert-deftest truecolor-upgrade-preserves-client-and-parameters ()
  (cl-letf (((symbol-function 'process-get) (lambda (&rest _) '("COLORTERM=TRUECOLOR")))
            ((symbol-function 'file-readable-p) (lambda (_) t)))
    (let ((arguments '("/dev/tty" "xterm-256color" client ((name . "Client")))))
      (should (equal (my/server-truecolor-tty arguments)
                     '("/dev/tty" "xterm-kaizen-direct" client ((name . "Client")))))
      (should (equal (nth 1 arguments) "xterm-256color")))))
''')
    guard_result = subprocess.run([emacs, '-Q', '--batch', '-l', str(guards), '-f', 'ert-run-tests-batch-and-exit'], env=env, capture_output=True, text=True)
    assert guard_result.returncode == 0, guard_result.stdout + guard_result.stderr
    print('passed: 6 ERT guards for menu bars, GUI, client capabilities, missing terminfo and argument preservation', flush=True)

    for index, (daemon, colorterm) in enumerate([(False, 'truecolor'), (True, 'truecolor'), (True, '24bit'), (True, None)]):
        result = root / f'result-{index}.json'
        config = root / f'config-{index}.el'
        server = f'kaizen-test-{root.name}-{index}'
        prelude = '''
(require 'json)
(require 'server)
(setq inhibit-startup-screen t initial-scratch-message nil)
(defface margin '((t :background "black")) "Test margin.")
(defun spacious-padding-set-faces (&rest _)
  (set-face-background 'margin "black"))
(provide 'spacious-padding)
(set-face-background 'region "#343955")
'''
        report = '''
(defun kaizen-report ()
  (let ((initial-margin (face-background 'margin nil t))
        (cursor-type 'bar))
    (spacious-padding-set-faces)
    (xterm--post-command-hook)
    (let ((insert-cursor (terminal-parameter nil 'xterm--cursor-type)))
      (setq cursor-type 'box)
      (xterm--post-command-hook)
      (with-temp-file RESULT
      (insert (json-encode
               (list :colors (display-color-cells)
                     :tty (tty-type)
                     :default (face-background 'default nil t)
                     :margin initial-margin
                     :margin-after-spacing (face-background 'margin nil t)
                     :insert-cursor insert-cursor
                     :normal-cursor (terminal-parameter nil 'xterm--cursor-type)
                     :menu-bar-lines (frame-parameter nil 'menu-bar-lines)
                     :mouse (terminal-parameter nil 'xterm-mouse-mode)
                     :mouse-click (symbol-name (key-binding [mouse-1]))
                     :mouse-drag (symbol-name (key-binding [down-mouse-1]))
                     :region (color-values "#343955"))))))))
'''.replace('RESULT', json.dumps(str(result)))
        hooks = '''
(add-hook 'after-make-frame-functions (lambda (_) (spacious-padding-set-faces)))
(add-hook 'server-after-make-frame-hook #'spacious-padding-set-faces)
'''
        if daemon:
            hooks += "(add-hook 'server-after-make-frame-hook #'kaizen-report 100)\n"
        else:
            hooks += "(add-hook 'window-setup-hook (lambda () (kaizen-report) (kill-emacs 0)) 100)\n"
        config.write_text(prelude + blocks + report + hooks)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        log = open(root / f'log-{index}', 'wb')
        process = tty_process = None
        output = bytearray()
        try:
            tty_env = {**env, 'TERM': 'xterm-256color'}
            if colorterm:
                tty_env['COLORTERM'] = colorterm
            if daemon:
                process = subprocess.Popen([emacs, '-Q', f'--fg-daemon={server}', '-l', str(config)], env=env, stdout=log, stderr=log)
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    ready = subprocess.run([client, '-s', server, '--eval', '(emacs-pid)'], env=env, capture_output=True, timeout=2)
                    if ready.returncode == 0:
                        break
                    assert process.poll() is None, (root / f'log-{index}').read_text()
                    time.sleep(0.05)
                else:
                    raise TimeoutError('test daemon did not start')
                command = [client, '-s', server, '-nw']
            else:
                command = [emacs, '-Q', '-nw', '-l', str(config)]
            tty_process = subprocess.Popen(command, env=tty_env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
            os.close(slave)
            slave = None
            deadline = time.monotonic() + 15
            while not result.exists() and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    output.extend(data)
                    if b'\x1b[6n' in output:
                        os.write(master, b'\x1b[1;1R')
                        output.clear()
                if tty_process.poll() is not None and not result.exists():
                    break
            assert result.exists(), (daemon, colorterm, repr(output[-1500:]), (root / f'log-{index}').read_text())
            state = json.loads(result.read_text())
            expected_colors = 16777216 if colorterm else 256
            assert state['colors'] == expected_colors, (daemon, colorterm, state)
            assert state['default'] == state['margin'] == state['margin-after-spacing'] == 'unspecified-bg', state
            assert state['insert-cursor'] == 5 and state['normal-cursor'] == 1, state
            assert state['menu-bar-lines'] == 0, state
            assert state['mouse'] and state['mouse-click'] == 'mouse-set-point', state
            assert state['mouse-drag'] == 'mouse-drag-region', state
            if colorterm:
                assert state['region'] == [52 * 257, 57 * 257, 85 * 257], state
            if daemon:
                assert state['tty'] == ('xterm-kaizen-direct' if colorterm else 'xterm-256color'), state
            print(f'passed: {"daemon client" if daemon else "standalone"}, COLORTERM={colorterm}, {state["colors"]} colors, transparent margins', flush=True)
        finally:
            if process and process.poll() is None:
                try:
                    subprocess.run([client, '-s', server, '--eval', '(kill-emacs 0)'], env=env, capture_output=True, timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
            if tty_process and tty_process.poll() is None:
                tty_process.terminate()
                deadline = time.monotonic() + 3
                while tty_process.poll() is None and time.monotonic() < deadline:
                    if select.select([master], [], [], 0.05)[0]:
                        try:
                            os.read(master, 65536)
                        except OSError:
                            break
                if tty_process.poll() is None:
                    tty_process.kill()
                tty_process.wait(timeout=3)
            if process:
                process.wait(timeout=3)
            if slave is not None:
                os.close(slave)
            os.close(master)
            log.close()

print('Emacs terminal frame tests passed')
PY
