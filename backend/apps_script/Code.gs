/**
 * Nyatet — backend Google Apps Script (FS-02).
 *
 * Peran:
 *  - API Web App untuk aplikasi Flutter (doGet/doPost).
 *  - Membuat buku keluarga: satu spreadsheet dengan 6 tab + header.
 *  - Menegakkan role (admin/member) di SISI SERVER.
 *  - Sinkronisasi delta + last-write-wins dengan LockService.
 *
 * Cara deploy (lihat README.md):
 *  - Deploy sebagai Web App, "Execute as: Me", "Who has access: Anyone with Google account".
 *  - Identitas user dibaca dari Session.getActiveUser().getEmail() (diverifikasi Google),
 *    BUKAN dipercaya dari body. Body `email` hanya fallback untuk pengujian lokal.
 */

const TABS = {
  TRANSACTIONS: 'transactions',
  MEMBERS: 'members',
  CATEGORIES: 'categories',
  BUDGETS: 'budgets',
  CONFIG_PARSER: 'config_parser',
  AUDIT_LOG: 'audit_log',
};

const HEADERS = {
  [TABS.TRANSACTIONS]: [
    'id', 'date', 'type', 'amount', 'category_id', 'account', 'merchant',
    'note', 'member_email', 'source', 'receipt_url', 'raw_text',
    'created_at', 'updated_at', 'is_deleted',
  ],
  [TABS.MEMBERS]: ['email', 'name', 'role', 'status', 'joined_at'],
  [TABS.CATEGORIES]: ['id', 'name', 'type', 'icon', 'is_active'],
  [TABS.BUDGETS]: ['id', 'month', 'category_id', 'limit_amount'],
  [TABS.CONFIG_PARSER]: ['id', 'package_name', 'bank_group', 'pattern', 'field_map', 'version'],
  [TABS.AUDIT_LOG]: ['id', 'ts', 'member_email', 'action', 'txn_id', 'before', 'after'],
};

const SEED_CATEGORIES = [
  ['Makan', 'out'], ['Belanja Dapur', 'out'], ['Transport', 'out'],
  ['Listrik/Air/Internet', 'out'], ['Sekolah', 'out'], ['Kesehatan', 'out'],
  ['Cicilan', 'out'], ['Hiburan', 'out'], ['Gaji', 'in'], ['Lain-lain', 'out'],
];

const ROLE_ADMIN = 'admin';
const ROLE_MEMBER = 'member';

function doPost(e) {
  return handle_(e);
}

function doGet(e) {
  return handle_(e);
}

function handle_(e) {
  try {
    const action = String(e.parameter.action || '');
    const body = parseBody_(e);

    switch (action) {
      case 'setup_family':
        return json_(setupFamily_(body));
      case 'push':
        return json_(push_(body));
      case 'pull':
        return json_(pull_(body));
      case 'invite_member':
        return json_(inviteMember_(body));
      case 'remove_member':
        return json_(removeMember_(body));
      case 'get_categories':
        return json_(getCategories_(body));
      case 'save_category':
        return json_(saveCategory_(body));
      default:
        return json_({ ok: false, error: 'unknown_action: ' + action });
    }
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

function json_(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

function parseBody_(e) {
  if (e.postData && e.postData.contents) {
    try {
      return JSON.parse(e.postData.contents);
    } catch (_) {
      return {};
    }
  }
  return {};
}

/** Identitas terverifikasi. Jangan percaya `body.email` di produksi. */
function identity_(body) {
  const active = Session.getActiveUser().getEmail();
  if (active) return active;
  return String(body && body.email ? body.email : '');
}

function requireIdentity_(email) {
  if (!email) throw new Error('unauthenticated');
  return email;
}

// ---------------------------------------------------------------------------
// Setup keluarga
// ---------------------------------------------------------------------------

function setupFamily_(body) {
  const email = requireIdentity_(identity_(body));
  const familyName = String(body.familyName || 'Nyatet');
  const memberName = String(body.adminName || email);

  const ss = SpreadsheetApp.create(familyName);
  ensureTabs_(ss);
  seedCategories_(ss);

  // Admin pertama = pemanggil.
  appendRow_(ss, TABS.MEMBERS, {
    email: email,
    name: memberName,
    role: ROLE_ADMIN,
    status: 'active',
    joined_at: nowIso_(),
  });

  return {
    ok: true,
    spreadsheetId: ss.getId(),
    sheetUrl: ss.getUrl(),
    role: ROLE_ADMIN,
  };
}

function ensureTabs_(ss) {
  const existing = ss.getSheets().map(function (s) { return s.getName(); });
  const order = [
    TABS.TRANSACTIONS, TABS.MEMBERS, TABS.CATEGORIES, TABS.BUDGETS,
    TABS.CONFIG_PARSER, TABS.AUDIT_LOG,
  ];
  order.forEach(function (name) {
    let sheet = ss.getSheetByName(name);
    if (!sheet) sheet = ss.insertSheet(name);
    if (sheet.getLastRow() === 0) sheet.appendRow(HEADERS[name]);
  });
  // Hapus sheet bawaan "Sheet1" bila masih ada.
  const sheet1 = ss.getSheetByName('Sheet1');
  if (sheet1 && ss.getSheets().length > order.length) ss.deleteSheet(sheet1);
}

function seedCategories_(ss) {
  const sheet = ss.getSheetByName(TABS.CATEGORIES);
  const existing = sheet.getLastRow();
  if (existing > 1) return; // sudah di-seed
  SEED_CATEGORIES.forEach(function (c) {
    appendRow_(ss, TABS.CATEGORIES, {
      id: Utilities.getUuid(),
      name: c[0],
      type: c[1],
      icon: '',
      is_active: 'TRUE',
    });
  });
}

// ---------------------------------------------------------------------------
// Role & akses (ditegakkan di server)
// ---------------------------------------------------------------------------

function getMember_(ss, email) {
  const sheet = ss.getSheetByName(TABS.MEMBERS);
  const values = sheet.getDataRange().getValues();
  const header = values[0];
  for (let i = 1; i < values.length; i++) {
    const row = rowToObject_(header, values[i]);
    if (String(row.email).toLowerCase() === String(email).toLowerCase()) {
      return row;
    }
  }
  return null;
}

function requireMember_(ss, email) {
  const m = getMember_(ss, email);
  if (!m) throw new Error('not_a_member');
  return m;
}

function requireAdmin_(ss, email) {
  const m = requireMember_(ss, email);
  if (m.role !== ROLE_ADMIN) throw new Error('forbidden: admin_only');
  return m;
}

// ---------------------------------------------------------------------------
// Push (sinkronisasi lokal -> Sheet)
// ---------------------------------------------------------------------------

function push_(body) {
  const email = requireIdentity_(identity_(body));
  const rows = body.rows || [];
  if (!Array.isArray(rows) || rows.length === 0) return { ok: true, applied: 0 };

  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const ss = SpreadsheetApp.openById(String(body.spreadsheetId));
    requireMember_(ss, email);

    let applied = 0;
    rows.forEach(function (r) {
      if (String(r.table) === TABS.TRANSACTIONS) {
        if (applyTransactionPush_(ss, email, r)) applied++;
      }
    });
    return { ok: true, applied: applied };
  } finally {
    lock.releaseLock();
  }
}

/** Last-write-wins saat push: hanya baris dengan updated_at lebih baru yang menang. */
function applyTransactionPush_(ss, email, r) {
  const payload = r.payload || {};
  const id = String(payload.id || r.rowId || '');
  if (!id) return false;

  const sheet = ss.getSheetByName(TABS.TRANSACTIONS);
  const values = sheet.getDataRange().getValues();
  const header = values[0];
  let rowIndex = -1;
  let existing = null;

  for (let i = 1; i < values.length; i++) {
    const row = rowToObject_(header, values[i]);
    if (String(row.id) === id) {
      rowIndex = i + 1;
      existing = row;
      break;
    }
  }

  const incomingUpdated = new Date(payload.updated_at).getTime();
  const existingUpdated = existing ? new Date(existing.updated_at).getTime() : -1;

  if (existing && existingUpdated >= incomingUpdated) {
    // Versi server lebih baru/sama: tolak, catat bentrok.
    appendRow_(ss, TABS.AUDIT_LOG, {
      id: Utilities.getUuid(),
      ts: nowIso_(),
      member_email: email,
      action: 'conflict_rejected',
      txn_id: id,
      before: JSON.stringify(existing),
      after: JSON.stringify(payload),
    });
    return false;
  }

  const newRow = objectToRow_(header, {
    id: id,
    date: payload.date || '',
    type: payload.type || '',
    amount: payload.amount || 0,
    category_id: payload.category_id || '',
    account: payload.account || '',
    merchant: payload.merchant || '',
    note: payload.note || '',
    member_email: payload.member_email || email,
    source: payload.source || '',
    receipt_url: payload.receipt_url || '',
    raw_text: payload.raw_text || '',
    created_at: payload.created_at || nowIso_(),
    updated_at: payload.updated_at || nowIso_(),
    is_deleted: payload.is_deleted ? 'TRUE' : 'FALSE',
  });

  if (rowIndex === -1) {
    sheet.appendRow(newRow);
  } else {
    sheet.getRange(rowIndex, 1, 1, newRow.length).setValues([newRow]);
  }

  if (existing) {
    appendRow_(ss, TABS.AUDIT_LOG, {
      id: Utilities.getUuid(),
      ts: nowIso_(),
      member_email: email,
      action: 'upsert',
      txn_id: id,
      before: JSON.stringify(existing),
      after: JSON.stringify(payload),
    });
  }
  return true;
}

// ---------------------------------------------------------------------------
// Pull (delta Sheet -> lokal)
// ---------------------------------------------------------------------------

function pull_(body) {
  const email = requireIdentity_(identity_(body));
  const ss = SpreadsheetApp.openById(String(body.spreadsheetId));
  const member = requireMember_(ss, email);

  const since = body.since ? new Date(body.since).getTime() : 0;
  const result = { ok: true, serverTime: nowIso_(), rows: {} };

  // Transaksi: admin semua; member hanya miliknya.
  const tx = readDelta_(ss, TABS.TRANSACTIONS, since);
  result.rows[TABS.TRANSACTIONS] = member.role === ROLE_ADMIN
    ? tx
    : tx.filter(function (r) { return r.member_email === email; });

  result.rows[TABS.MEMBERS] = readDelta_(ss, TABS.MEMBERS, since);
  result.rows[TABS.CATEGORIES] = readDelta_(ss, TABS.CATEGORIES, since);
  result.rows[TABS.BUDGETS] = readDelta_(ss, TABS.BUDGETS, since);
  result.rows[TABS.CONFIG_PARSER] = readDelta_(ss, TABS.CONFIG_PARSER, since);

  return result;
}

function readDelta_(ss, tab, since) {
  const sheet = ss.getSheetByName(tab);
  const values = sheet.getDataRange().getValues();
  const header = values[0];
  const out = [];
  for (let i = 1; i < values.length; i++) {
    const row = rowToObject_(header, values[i]);
    const updatedAt = row.updated_at || row.joined_at || row.ts || '';
    if (updatedAt && new Date(updatedAt).getTime() > since) {
      out.push(row);
    } else if (!updatedAt && since === 0) {
      out.push(row);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Undang & keluarkan anggota (admin only)
// ---------------------------------------------------------------------------

function inviteMember_(body) {
  const email = requireIdentity_(identity_(body));
  const ss = SpreadsheetApp.openById(String(body.spreadsheetId));
  requireAdmin_(ss, email);

  const invitee = String(body.inviteeEmail || '');
  if (!invitee) throw new Error('missing_invitee');
  const role = body.role === ROLE_ADMIN ? ROLE_ADMIN : ROLE_MEMBER;

  const existing = getMember_(ss, invitee);
  if (existing) {
    setCellByKey_(ss, TABS.MEMBERS, 'email', invitee, { role: role, status: 'active' });
  } else {
    appendRow_(ss, TABS.MEMBERS, {
      email: invitee, name: invitee, role: role, status: 'active', joined_at: nowIso_(),
    });
  }
  return { ok: true };
}

function removeMember_(body) {
  const email = requireIdentity_(identity_(body));
  const ss = SpreadsheetApp.openById(String(body.spreadsheetId));
  requireAdmin_(ss, email);
  const target = String(body.targetEmail || '');
  if (!target) throw new Error('missing_target');
  setCellByKey_(ss, TABS.MEMBERS, 'email', target, { status: 'removed' });
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Kategori & budget (admin only)
// ---------------------------------------------------------------------------

function getCategories_(body) {
  const email = requireIdentity_(identity_(body));
  const ss = SpreadsheetApp.openById(String(body.spreadsheetId));
  requireMember_(ss, email);
  return { ok: true, categories: readAll_(ss, TABS.CATEGORIES) };
}

function saveCategory_(body) {
  const email = requireIdentity_(identity_(body));
  const ss = SpreadsheetApp.openById(String(body.spreadsheetId));
  requireAdmin_(ss, email);
  const id = String(body.id || Utilities.getUuid());
  appendRow_(ss, TABS.CATEGORIES, {
    id: id,
    name: body.name || '',
    type: body.type || 'out',
    icon: body.icon || '',
    is_active: body.is_active === false ? 'FALSE' : 'TRUE',
  });
  return { ok: true, id: id };
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

function nowIso_() {
  return new Date().toISOString();
}

function rowToObject_(header, values) {
  const obj = {};
  header.forEach(function (h, i) {
    if (h !== '') obj[String(h)] = values[i];
  });
  return obj;
}

function objectToRow_(header, obj) {
  return header.map(function (h) {
    const v = obj[h];
    if (v === undefined || v === null) return '';
    return v;
  });
}

function appendRow_(ss, tab, obj) {
  const sheet = ss.getSheetByName(tab);
  const header = sheet.getDataRange().getValues()[0];
  sheet.appendRow(objectToRow_(header, obj));
}

function setCellByKey_(ss, tab, keyColumn, key, patch) {
  const sheet = ss.getSheetByName(tab);
  const values = sheet.getDataRange().getValues();
  const header = values[0];
  const keyIndex = header.indexOf(keyColumn);
  for (let i = 1; i < values.length; i++) {
    if (String(values[i][keyIndex]).toLowerCase() === String(key).toLowerCase()) {
      Object.keys(patch).forEach(function (col) {
        const colIndex = header.indexOf(col);
        if (colIndex >= 0) sheet.getRange(i + 1, colIndex + 1).setValue(patch[col]);
      });
      return;
    }
  }
}

function readAll_(ss, tab) {
  const sheet = ss.getSheetByName(tab);
  const values = sheet.getDataRange().getValues();
  const header = values[0];
  const out = [];
  for (let i = 1; i < values.length; i++) {
    out.push(rowToObject_(header, values[i]));
  }
  return out;
}
