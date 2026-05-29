const http = require('http');
const fs = require('fs');
const log = [];

function logit(msg) { log.push(msg); process.stderr.write(msg + '\n'); }
function post(path, body, hdrs = {}) {
  return new Promise((resolve, reject) => {
    const opts = { hostname: '127.0.0.1', port: 8123, path, method: 'POST', headers: { 'Content-Type': 'application/json', ...hdrs } };
    const r = http.request(opts, res => { let d = ''; res.on('data', c => d += c); res.on('end', () => resolve({ status: res.statusCode, body: d })); });
    r.on('error', reject);
    if (body) r.write(JSON.stringify(body));
    r.end();
  });
}
function get(path, hdrs = {}) {
  return new Promise((resolve, reject) => {
    const opts = { hostname: '127.0.0.1', port: 8123, path, method: 'GET', headers: { ...hdrs } };
    const r = http.request(opts, res => { let d = ''; res.on('data', c => d += c); res.on('end', () => resolve({ status: res.statusCode, body: d })); });
    r.on('error', reject);
    r.end();
  });
}

(async () => {
  try {
    // 1. REGISTER (may fail if email exists — that's fine, we login either way)
    const email = 'smoke' + Date.now() + '@test.com';
    const password = 'Test123!@#';
    let r = await post('/api/v1/auth/register', { email, password, full_name: 'Smoke', company_legal_name: 'SmokeCo' });
    logit('1. Register: ' + r.status + ' ' + (r.status === 201 || r.status === 400 ? 'OK' : 'body=' + r.body.slice(0, 80)));

    // 2. LOGIN
    r = await post('/api/v1/auth/login', { email, password });
    const loginData = JSON.parse(r.body);
    const tok = loginData.access_token;
    logit('2. Login: ' + r.status + ' ' + (tok ? 'OK got token' : 'FAIL - ' + r.body.slice(0, 60)));

    // 3. GET TENANT
    r = await get('/api/v1/auth/memberships', { Authorization: 'Bearer ' + tok });
    const mems = JSON.parse(r.body);
    const tid = mems[0]?.tenant_id;
    logit('3. Tenant: ' + (tid ? 'OK id=' + tid : 'FAIL - ' + r.body.slice(0, 60)));

    // 4. CREATE INVOICE
    const invPayload = {
      contact_id: '00000000-0000-0000-0000-000000000001',
      invoice_number: 'INV-TEST-003',
      issue_date: '2026-05-28',
      due_date: '2026-06-12',
      pos_state_code: '27',
      line_items: [{ product_id: '00000000-0000-0000-0000-000000000001', quantity: 2, rate: 500, discount: 0, hsn_sac: '84716050', gst_rate: 18 }]
    };
    r = await post('/api/v1/invoices', invPayload, { Authorization: 'Bearer ' + tok, 'X-Tenant-ID': tid });
    logit('4. Create invoice: ' + r.status + ' ' + (r.status === 201 ? 'OK' : 'body=' + r.body.slice(0, 80)));
    const inv = JSON.parse(r.body);

    // 5. FINALIZE
    r = await post('/api/v1/invoices/' + inv.id + '/finalize', null, { Authorization: 'Bearer ' + tok, 'X-Tenant-ID': tid });
    const finalStatus = JSON.parse(r.body).status;
    logit('5. Finalize: ' + r.status + ' status=' + finalStatus + ' ' + (finalStatus === 'POSTED' || finalStatus === 'SENT' ? 'PASS' : 'FAIL'));

    // 6. CANCEL
    r = await post('/api/v1/invoices/' + inv.id + '/cancel', null, { Authorization: 'Bearer ' + tok, 'X-Tenant-ID': tid });
    const cancelStatus = JSON.parse(r.body).status;
    logit('6. Cancel: ' + r.status + ' status=' + cancelStatus + ' ' + (cancelStatus === 'CANCELLED' ? 'PASS' : 'FAIL'));

    // 7. IDEMPOTENCY
    const idemKey = 'idem-smoke-' + Date.now();
    const idemPayload = { ...invPayload, invoice_number: 'INV-IDEM-003' };
    r = await post('/api/v1/invoices', idemPayload, { Authorization: 'Bearer ' + tok, 'X-Tenant-ID': tid, 'Idempotency-Key': idemKey });
    logit('7a. Idem 1st: ' + r.status + ' ' + (r.status === 201 ? 'OK' : 'FAIL'));
    r = await post('/api/v1/invoices', idemPayload, { Authorization: 'Bearer ' + tok, 'X-Tenant-ID': tid, 'Idempotency-Key': idemKey });
    logit('7b. Idem dup: ' + r.status + ' ' + (r.status === 409 ? '409 CONFLICT - PASS' : 'UNEXPECTED ' + r.status));

    const results = log.join('\n');
    fs.writeFileSync('C:/Bookkeeping-master/backend/smoke_results.txt', results, 'utf8');
    logit('\nResults written to smoke_results.txt');
  } catch (e) {
    logit('FATAL: ' + e.message);
    fs.writeFileSync('C:/Bookkeeping-master/backend/smoke_results.txt', log.join('\n') + '\nFATAL: ' + e.message, 'utf8');
  }
})();
