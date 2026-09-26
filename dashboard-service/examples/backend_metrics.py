"""Synthetic data only. No account/credential discovery, no automatic publication."""
import copy
import os
from pathlib import Path
from turbo_dashboard.client import Client
from turbo_dashboard.contracts import TEMPLATES

client = Client(os.environ.get('TURBOIO_API_URL', 'http://127.0.0.1:18796'),
                Path(os.environ['TURBOIO_TOKEN_FILE']).read_text().strip())
try:
    doc = copy.deepcopy(TEMPLATES[0])
    existing = next((c for c in client.cards() if c['document']['id'] == doc['id']), None)
    saved = existing or client.save(doc)
    changed = client.update(doc['id'], {'cpu_label': {'text': 'CPU 42% · 示例'}, 'cpu_bar': {'value': 42}}, saved['revision'])
    print({'revision': changed['revision'], 'hash': changed['hash'], 'published': False})
finally:
    client.close()
