"""Single-owner SQLite store. Device grants are issued locally, never by model tools."""
import hashlib
import json
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path

from .contracts import Fault, canonical, digest, integer, patch_data, validate


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", value):
        raise Fault("identifier", "Invalid identifier")
    return value


class Store:
    def __init__(self, path, clock=time.time):
        self.path, self.clock = Path(path), clock
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self.connect() as db:
            db.executescript('''
              CREATE TABLE IF NOT EXISTS tokens(hash TEXT PRIMARY KEY, role TEXT, device TEXT);
              CREATE TABLE IF NOT EXISTS cards(device TEXT, id TEXT, revision INTEGER,
                document TEXT, PRIMARY KEY(device,id));
              CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, device TEXT, card TEXT,
                revision INTEGER, hash TEXT, document TEXT, state TEXT, expires REAL,
                idem TEXT, request_hash TEXT, lease TEXT, code TEXT,
                UNIQUE(device,idem));
            ''')
        self.path.chmod(0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def issue(self, role, device):
        if role not in ("writer", "phone", "reader"):
            raise Fault("role", "Unknown role")
        identifier(device)
        token = secrets.token_urlsafe(32)
        with self.connect() as db:
            db.execute("INSERT INTO tokens VALUES(?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), role, device))
        return token

    def authenticate(self, token):
        if not isinstance(token, str) or not 32 <= len(token) <= 128:
            raise Fault("unauthorized", "Bearer token required", 401)
        with self.connect() as db:
            row = db.execute("SELECT role,device FROM tokens WHERE hash=?", (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
        if not row:
            raise Fault("unauthorized", "Invalid bearer token", 401)
        return dict(row)

    @staticmethod
    def card_row(row):
        if row is None:
            raise Fault("not_found", "Card not found", 404)
        document = json.loads(row['document'])
        return dict(document=document, revision=row['revision'], hash=digest(document))

    def cards(self, device):
        with self.connect() as db:
            return [self.card_row(r) for r in db.execute("SELECT * FROM cards WHERE device=? ORDER BY id", (device,))]

    def get(self, device, ident):
        with self.connect() as db:
            return self.card_row(db.execute("SELECT * FROM cards WHERE device=? AND id=?", (device, ident)).fetchone())

    def save(self, device, ident, expected, document=None, updates=None):
        integer(expected)
        with self.connect() as db:
            row = db.execute("SELECT * FROM cards WHERE device=? AND id=?", (device, ident)).fetchone()
            revision = row['revision'] if row else 0
            if revision != expected:
                raise Fault("revision_conflict", "Fetch the current revision before editing", 409)
            if updates is not None:
                document = patch_data(self.card_row(row)['document'], updates)
            validate(document)
            if document['id'] != ident:
                raise Fault("identity", "Path and document ID differ")
            if not row and db.execute("SELECT count(*) FROM cards WHERE device=?", (device,)).fetchone()[0] >= 128:
                raise Fault("card_limit", "Device draft limit reached", 409)
            db.execute("INSERT OR REPLACE INTO cards VALUES(?,?,?,?)", (device, ident, revision+1, canonical(document).decode()))
        return dict(document=document, revision=revision+1, hash=digest(document))

    @staticmethod
    def job_row(row):
        if row is None:
            raise Fault("not_found", "Job not found", 404)
        return {k: row[k] for k in ('id', 'device', 'card', 'revision', 'hash', 'state', 'expires', 'code')} | {'physicalVerified': False}

    def publish(self, device, ident, revision, doc_hash, idem, ttl):
        integer(revision, 1); integer(ttl, 30, 3600); identifier(idem)
        signature = digest([ident, revision, doc_hash, ttl])
        with self.connect() as db:
            previous = db.execute("SELECT * FROM jobs WHERE device=? AND idem=?", (device, idem)).fetchone()
            if previous:
                if previous['request_hash'] != signature:
                    raise Fault("idempotency_conflict", "Idempotency key was used for a different request", 409)
                return self.job_row(previous)
            card = self.card_row(db.execute("SELECT * FROM cards WHERE device=? AND id=?", (device, ident)).fetchone())
            if card['revision'] != revision or card['hash'] != doc_hash:
                raise Fault("revision_conflict", "Publish must reference the exact reviewed revision/hash", 409)
            if db.execute("SELECT count(*) FROM jobs WHERE device=?", (device,)).fetchone()[0] >= 1000:
                raise Fault("job_limit", "Job retention limit reached; operator maintenance required", 409)
            job = secrets.token_hex(16)
            db.execute("INSERT INTO jobs VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (job, device, ident, revision, doc_hash,
                canonical(card['document']).decode(), 'awaiting_phone_approval', self.clock()+ttl, idem, signature, None, None))
            return self.job_row(db.execute("SELECT * FROM jobs WHERE id=?", (job,)).fetchone())

    def expire(self, db, device):
        db.execute("UPDATE jobs SET state='expired' WHERE device=? AND state='awaiting_phone_approval' AND expires<?", (device, self.clock()))
        # Never silently retry an in-flight operation after losing the phone.
        db.execute("UPDATE jobs SET state='outcome_unknown' WHERE device=? AND state='sending' AND expires<?", (device, self.clock()))

    def jobs(self, device):
        with self.connect() as db:
            self.expire(db, device)
            return [self.job_row(r) for r in db.execute("SELECT * FROM jobs WHERE device=? ORDER BY rowid DESC LIMIT 100", (device,))]

    def job(self, device, ident, include_document=False):
        with self.connect() as db:
            self.expire(db, device)
            row = db.execute("SELECT * FROM jobs WHERE device=? AND id=?", (device, ident)).fetchone()
            result = self.job_row(row)
            if include_document:
                result['document'] = json.loads(row['document'])
            return result

    def approve(self, device, ident, doc_hash):
        with self.connect() as db:
            self.expire(db, device)
            row = db.execute("SELECT * FROM jobs WHERE device=? AND id=?", (device, ident)).fetchone()
            self.job_row(row)
            if row['state'] != 'awaiting_phone_approval' or row['hash'] != doc_hash:
                raise Fault("approval_conflict", "Job expired, already claimed, or hash differs", 409)
            if db.execute("SELECT 1 FROM jobs WHERE device=? AND state IN ('sending','outcome_unknown')", (device,)).fetchone():
                raise Fault("device_busy", "Resolve the previous device operation first", 409)
            lease = secrets.token_urlsafe(32)
            db.execute("UPDATE jobs SET state='sending',lease=? WHERE id=?", (hashlib.sha256(lease.encode()).hexdigest(), ident))
            return dict(id=ident, hash=row['hash'], document=json.loads(row['document']), receiptToken=lease)

    def receipt(self, device, ident, token, state, code):
        if state not in ('device_accepted', 'failed', 'outcome_unknown'):
            raise Fault("receipt_state", "Invalid receipt state")
        identifier(code)
        if not isinstance(token, str) or len(token) > 128:
            raise Fault("receipt_token", "Invalid receipt token", 403)
        with self.connect() as db:
            row = db.execute("SELECT * FROM jobs WHERE device=? AND id=?", (device, ident)).fetchone()
            self.job_row(row)
            if row['lease'] != hashlib.sha256(token.encode()).hexdigest():
                raise Fault("receipt_token", "Receipt token does not match claimed job", 403)
            if row['state'] not in ('sending', 'outcome_unknown'):
                if row['state'] == state and row['code'] == code:
                    return self.job_row(row)
                raise Fault("receipt_conflict", "Terminal receipt cannot be overwritten", 409)
            db.execute("UPDATE jobs SET state=?,code=? WHERE id=?", (state, code, ident))
            return self.job_row(db.execute("SELECT * FROM jobs WHERE id=?", (ident,)).fetchone())
