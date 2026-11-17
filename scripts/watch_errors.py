"""Watch WoW Forever for Ultimate's recorded problems and the game's taint log.

Emits one line per NEW or GROWN entry in UltimateDB.errorLog (written by the game on /reload
or logout), and new taint.log lines that mention a blocked/forbidden action.
"""
import os, sys, time, re

GAME = r'C:\Program Files (x86)\World of Warcraft\_forever_'
SV = os.path.join(GAME, r'WTF\Account\DEMONICTRIGGER\SavedVariables\Ultimate.lua')
TAINT = os.path.join(GAME, r'Logs\taint.log')

from lupa import LuaRuntime


def read_errors():
    lua = LuaRuntime(register_eval=False)
    try:
        src = open(SV, encoding='utf-8', errors='replace').read()
        lua.execute(src)
    except Exception as e:  # half-written file: try again next poll
        return None
    db = lua.globals().UltimateDB
    out = {}
    if db is None or db['errorLog'] is None:
        return out
    log = db['errorLog']
    for i in range(1, len(log) + 1):
        e = log[i]
        if e is None:
            continue
        key = f"{e['kind']}|{e['key']}"
        detail = e['detail'] or ''
        out[key] = {
            'kind': e['kind'], 'count': e['count'] or 1, 'addon': e['addon'], 'func': e['func'],
            'combat': e['inCombat'], 'first': str(detail).split('\n')[0][:300],
        }
    return out


def emit(line):
    print(line, flush=True)


def main():
    seen = read_errors() or {}
    sv_mtime = os.path.getmtime(SV) if os.path.exists(SV) else 0
    taint_size = os.path.getsize(TAINT) if os.path.exists(TAINT) else 0
    emit(f"watching: {len(seen)} problems already recorded; taint log {'present' if os.path.exists(TAINT) else 'absent'}")
    while True:
        time.sleep(5)
        try:
            if os.path.exists(SV) and os.path.getmtime(SV) != sv_mtime:
                time.sleep(1)  # let the game finish writing
                sv_mtime = os.path.getmtime(SV)
                now = read_errors()
                if now is not None:
                    for key, e in now.items():
                        old = seen.get(key)
                        if old is None or e['count'] > old['count']:
                            what = (f"{e['addon']}: {e['func']}" if e['kind'] != 'lua' else e['first'])
                            tag = 'NEW' if old is None else f"AGAIN (x{e['count']})"
                            emit(f"ULTIMATE {tag} [{e['kind']}{' in combat' if e['combat'] else ''}] {what}")
                    seen = now
            if os.path.exists(TAINT):
                size = os.path.getsize(TAINT)
                if size < taint_size:
                    taint_size = 0
                if size > taint_size:
                    with open(TAINT, encoding='utf-8', errors='replace') as f:
                        f.seek(taint_size)
                        chunk = f.read()
                    taint_size = size
                    for line in chunk.splitlines():
                        if re.search(r'blocked|forbidden|Ultimate', line, re.I):
                            emit('TAINT ' + line.strip()[:300])
        except Exception as ex:
            emit(f'watcher error: {ex}')


if __name__ == '__main__':
    main()
