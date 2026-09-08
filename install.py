#!/usr/bin/env python3
"""Install this checkout as the user's calendar widget; back up the bar config."""
import json
from datetime import datetime
from pathlib import Path
import shutil

source = Path(__file__).resolve().parent
config_dir = Path.home() / '.config/omarchy'
plugin = config_dir / 'plugins/smo.calendar'
config = config_dir / 'shell.json'
if plugin.is_symlink():
    if plugin.resolve() != source:
        raise SystemExit(f'{plugin} points to a different checkout; leave it intact.')
elif plugin.exists():
    raise SystemExit(f'{plugin} already exists; leave it intact.')
# Read and validate config before changing either path.
doc = json.loads(config.read_text())
bar = doc.setdefault('bar', {})
layout = bar.setdefault('layout', {})
found = False
for entries in layout.values():
    if not isinstance(entries, list):
        continue
    for i, entry in enumerate(entries):
        if isinstance(entry, dict) and entry.get('id') in ('omarchy.clock', 'smo.calendar'):
            entries[i] = dict(entry, id='smo.calendar')
            found = True
if not found:
    layout.setdefault('center', []).append({'id':'smo.calendar'})
if bar.get('centerAnchor') == 'omarchy.clock':
    bar['centerAnchor'] = 'smo.calendar'
backup = config.with_name('shell.json.before-calendar-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
shutil.copy2(config, backup)
plugin.parent.mkdir(parents=True, exist_ok=True)
if not plugin.is_symlink():
    plugin.symlink_to(source, target_is_directory=True)
temporary = config.with_suffix('.calendar.tmp')
temporary.write_text(json.dumps(doc, indent=2) + '\n')
temporary.replace(config)
print(f'Installed smo.calendar from {source}')
print(f'Bar config backup: {backup}')
