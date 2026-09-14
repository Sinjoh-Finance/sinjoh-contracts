"""Run Foundry's native keystore prompt through a private, echo-disabled PTY."""
import errno
import os
import pty
import re
import select
import signal
import termios

PROMPT = re.compile(r'(?:Enter[^\r\n]*password[^\r\n]*:)[ \t]*', re.I)

def run_keystore_command(args, password, cwd, env, emit=None):
    pid, fd = pty.fork()
    if pid == 0:
        try:
            attributes = termios.tcgetattr(0)
            attributes[3] &= ~(termios.ECHO | termios.ECHONL)
            termios.tcsetattr(0, termios.TCSANOW, attributes)
            os.chdir(cwd)
            os.execvpe(str(args[0]), [str(a) for a in args], env)
        except Exception:
            os._exit(127)
    output = ''
    tail = ''
    finished = False
    try:
        while True:
            if not select.select([fd], [], [], 1)[0]:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO: break
                raise
            if not chunk: break
            text = chunk.decode('utf-8', errors='replace')
            output += text
            tail = (tail + text)[-4096:]
            if PROMPT.search(tail):
                attributes = termios.tcgetattr(fd)
                attributes[3] &= ~(termios.ECHO | termios.ECHONL)
                termios.tcsetattr(fd, termios.TCSANOW, attributes)
                os.write(fd, password.encode() + b'\n')
                tail = ''
            if emit:
                emit(PROMPT.sub('', text).replace(password, '[redacted]') if password else PROMPT.sub('', text))
        _, status = os.waitpid(pid, 0)
        finished = True
        clean = PROMPT.sub('', output).replace('\r\n', '\n')
        if password: clean = clean.replace(password, '[redacted]')
        return os.waitstatus_to_exitcode(status), clean
    finally:
        os.close(fd)
        if not finished:
            try: os.kill(pid, signal.SIGTERM)
            except ProcessLookupError: pass
            os.waitpid(pid, 0)
