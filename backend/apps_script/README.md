# Backend Google Apps Script (FS-02)

API Web App untuk aplikasi Flutter Nyatet. Semua data keluarga hidup di satu
Google Spreadsheet (6 tab), diakses lewat Apps Script yang berjalan atas nama
admin — jadi OAuth di HP hanya butuh scope `email` + `profile`.

## File

- `Code.gs` — seluruh backend: setup keluarga, push/pull delta, role, kategori.
- `appsscript.json` — manifest (runtime V8, `executeAs: USER_DEPLOYING`).

## Deploy

1. Buat project Apps Script baru, tempel isi `Code.gs`.
2. Deploy → New deployment → **Web app**.
   - Execute as: **Me** (admin keluarga).
   - Who has access: **Anyone** (perlu akun Google; `Session.getActiveUser()`).
3. Salin URL Web App; URL ini jadi `apiBaseUrl` di aplikasi Flutter (F1).

## Keamanan role

Identitas user dibaca dari `Session.getActiveUser().getEmail()` (diverifikasi
Google saat Web App diakses akun Google). `body.email` hanya fallback uji lokal
— jangan dipakai di produksi. Role dicek di server (`requireAdmin_` /
`requireMember_`), bukan cuma disembunyikan di UI.

## Endpoint (POST, `?action=...`)

| action | body | akses |
|---|---|---|
| `setup_family` | `familyName`, `adminName` | siapa pun (login Google) → jadi admin |
| `push` | `spreadsheetId`, `rows[]` | member; transaksi LWW + `audit_log` |
| `pull` | `spreadsheetId`, `since` (ISO) | member; delta sejak `since`; member hanya transaksi sendiri |
| `invite_member` | `spreadsheetId`, `inviteeEmail`, `role` | admin |
| `remove_member` | `spreadsheetId`, `targetEmail` | admin |
| `get_categories` | `spreadsheetId` | member |
| `save_category` | `spreadsheetId`, `name`, `type`, `icon`, `is_active` | admin |

## Struktur Sheet (dibuat otomatis saat `setup_family`)

| tab | kolom |
|---|---|
| transactions | id, date, type, amount, category_id, account, merchant, note, member_email, source, receipt_url, raw_text, created_at, updated_at, is_deleted |
| members | email, name, role, status, joined_at |
| categories | id, name, type, icon, is_active |
| budgets | id, month, category_id, limit_amount |
| config_parser | id, package_name, bank_group, pattern, field_map, version |
| audit_log | id, ts, member_email, action, txn_id, before, after |

`config_parser.bank_group` memetakan paket aplikasi → grup bank (keputusan
D-12: duplikat dideteksi per grup bank, bukan per nama paket).

Kategori awal di-seed: Makan, Belanja Dapur, Transport, Listrik/Air/Internet,
Sekolah, Kesehatan, Cicilan, Hiburan, Gaji, Lain-lain.
