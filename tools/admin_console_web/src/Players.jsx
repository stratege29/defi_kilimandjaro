import { useEffect, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { functions } from './firebase.js';

const call = (name, data) => httpsCallable(functions, name, { timeout: 60000 })(data).then((r) => r.data);
const fmt = (e) => `${e.code || e.name}: ${e.message}`;
const inp = { padding: '8px 10px', borderRadius: 8, border: '1px solid var(--hair,#2C4034)', background: '#0e1a14', color: 'inherit', font: 'inherit' };

function Row({ label, value }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, padding: '4px 0', borderBottom: '1px solid rgba(255,255,255,.04)' }}>
      <span className="muted small">{label}</span>
      <span className="small" style={{ textAlign: 'right', wordBreak: 'break-word' }}>{value ?? '—'}</span>
    </div>
  );
}

export default function Players() {
  const [q, setQ] = useState('');
  const [results, setResults] = useState(null);
  const [sel, setSel] = useState(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);
  const [amt, setAmt] = useState('');
  const [reason, setReason] = useState('');
  const [isRecent, setIsRecent] = useState(true);

  useEffect(() => {
    (async () => {
      setBusy(true);
      try { setResults((await call('adminRecentPlayers', { limit: 25 })).players); setIsRecent(true); }
      catch (e2) { setErr(fmt(e2)); } finally { setBusy(false); }
    })();
  }, []);

  async function search(e) {
    e?.preventDefault();
    if (!q.trim()) return;
    setBusy(true); setErr(null); setSel(null);
    try { setResults((await call('adminFindPlayers', { query: q.trim() })).players); setIsRecent(false); }
    catch (e2) { setErr(fmt(e2)); } finally { setBusy(false); }
  }
  async function open(uid) {
    setBusy(true); setErr(null);
    try { setSel((await call('adminGetPlayer', { uid })).player); }
    catch (e2) { setErr(fmt(e2)); } finally { setBusy(false); }
  }
  async function refresh() { if (sel) await open(sel.uid); }

  async function adjust() {
    const n = Math.trunc(Number(String(amt).replace(',', '.').trim()));
    if (!Number.isFinite(n) || n === 0) { setErr('Entre un montant entier non nul, ex. 50 (créditer) ou -20 (débiter).'); return; }
    if (!confirm(`${n > 0 ? 'Créditer' : 'Débiter'} ${Math.abs(n)} cauris à ce joueur ?`)) return;
    setBusy(true); setErr(null);
    try { await call('adminAdjustCauris', { uid: sel.uid, amount: n, reason }); setAmt(''); setReason(''); await refresh(); }
    catch (e2) { setErr(fmt(e2)); } finally { setBusy(false); }
  }
  async function toggleBan() {
    const next = !sel.banned;
    if (!confirm(next ? 'Bannir ce joueur ? (compte désactivé, déconnecté sous ~1h)' : 'Débannir ce joueur ?')) return;
    setBusy(true); setErr(null);
    try { await call('adminSetBan', { uid: sel.uid, banned: next }); await refresh(); }
    catch (e2) { setErr(fmt(e2)); } finally { setBusy(false); }
  }
  async function del() {
    const tag = sel.profile?.display_name || sel.uid.slice(0, 8);
    if (prompt(`SUPPRESSION DÉFINITIVE (RGPD). Tape "${tag}" pour confirmer :`) !== tag) return;
    setBusy(true); setErr(null);
    try {
      await call('adminDeletePlayer', { uid: sel.uid });
      setSel(null);
      setResults((results || []).filter((p) => p.uid !== sel.uid));
    } catch (e2) { setErr(fmt(e2)); } finally { setBusy(false); }
  }

  return (
    <>
      <header className="topbar"><h2>Joueurs / Support</h2><span className="spacer" /></header>

      <form onSubmit={search} className="row" style={{ gap: 8, marginBottom: 12 }}>
        <input style={{ ...inp, flex: 1 }} value={q} onChange={(e) => setQ(e.target.value)}
          placeholder="uid, email, ou début de pseudo…" />
        <button className="btn primary" disabled={busy}>{busy ? '…' : 'Chercher'}</button>
      </form>
      {err && <p className="error block">{err}</p>}

      {!sel && results && results.length === 0 && <p className="muted block">Aucun joueur trouvé. (La plupart des joueurs sont anonymes — cherche par uid, ou par pseudo/email s'ils en ont un.)</p>}
      {!sel && results && results.length > 0 && (
        <p className="muted small block">{isRecent ? 'Joueurs récents (par création de profil) — ou cherche ci-dessus.' : `${results.length} résultat(s).`}</p>
      )}
      {!sel && results && results.length > 0 && (
        <table className="table">
          <thead><tr><th>Pseudo</th><th>Altitude</th><th>Cauris</th><th>Compte</th><th>Statut</th><th></th></tr></thead>
          <tbody>
            {results.map((p) => (
              <tr key={p.uid}>
                <td>{p.display_name || <span className="muted">(sans pseudo)</span>}<div className="mono muted" style={{ fontSize: 11 }}>{p.uid.slice(0, 12)}…</div></td>
                <td className="mono">{p.elo ?? '—'}</td>
                <td className="mono">{p.cauris ?? '—'}</td>
                <td className="small">{p.email || (p.isAnonymous ? 'anonyme' : '—')}</td>
                <td>{p.banned ? <span className="chip red">Banni</span> : <span className="chip green">OK</span>}</td>
                <td className="row-actions"><button className="btn ghost small" onClick={() => open(p.uid)}>Ouvrir</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {sel && (
        <div>
          <button className="btn ghost small" onClick={() => setSel(null)} style={{ marginBottom: 12 }}>← Résultats</button>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
            <div className="card" style={{ padding: 14 }}>
              <div className="row" style={{ alignItems: 'center', marginBottom: 8 }}>
                <h3 style={{ margin: 0 }}>{sel.profile?.display_name || '(sans pseudo)'}</h3>
                <span className="spacer" />
                {sel.banned ? <span className="chip red">Banni</span> : <span className="chip green">Actif</span>}
              </div>
              <Row label="uid" value={<span className="mono" style={{ fontSize: 11 }}>{sel.uid}</span>} />
              <Row label="Altitude (ELO)" value={sel.profile?.elo} />
              <Row label="Record (peak)" value={sel.profile?.peakElo} />
              <Row label="Duels (V / D)" value={`${sel.profile?.totalDuels ?? 0} (${sel.profile?.wins ?? 0} / ${sel.profile?.losses ?? 0})`} />
              <Row label="Créé le" value={sel.profile?.createdAt?.slice(0, 10)} />
              <Row label="Dernier duel" value={sel.profile?.lastDuelAt?.slice(0, 16)?.replace('T', ' ')} />
              <Row label="Email" value={sel.auth?.email} />
              <Row label="Connexion" value={sel.auth ? (sel.auth.isAnonymous ? 'anonyme' : sel.auth.providers.join(', ')) : '—'} />
              <Row label="Dernière connexion" value={sel.auth?.lastSignIn?.slice(0, 16)} />
              <Row label="Cauris" value={<b style={{ color: 'var(--gold,#E9B949)' }}>{sel.wallet?.cauris ?? '— (pas de wallet)'}</b>} />
              <Row label="Packs débloqués" value={(sel.wallet?.owned_packs || []).join(', ') || '—'} />
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div className="card" style={{ padding: 14 }}>
                <h4 style={{ marginTop: 0 }}>Actions support</h4>
                <div className="row" style={{ gap: 6, marginBottom: 8 }}>
                  <input style={{ ...inp, width: 110 }} type="number" step="1" value={amt} onChange={(e) => { setAmt(e.target.value); if (err) setErr(null); }} placeholder="± cauris" />
                  <input style={{ ...inp, flex: 1 }} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="raison (audit)" />
                  <button className="btn primary small" disabled={busy} onClick={adjust}>Appliquer</button>
                </div>
                <div className="row-actions">
                  <button className={sel.banned ? 'btn primary small' : 'btn ghost small'} disabled={busy} onClick={toggleBan}>{sel.banned ? 'Débannir' : 'Bannir'}</button>
                  <button className="btn danger small" disabled={busy} onClick={del}>Supprimer (RGPD)</button>
                </div>
              </div>

              <div className="card" style={{ padding: 14 }}>
                <h4 style={{ marginTop: 0 }}>Derniers duels</h4>
                {(!sel.duels || sel.duels.length === 0) ? <p className="muted small">Aucun.</p> :
                  sel.duels.map((d) => (
                    <div key={d.id} className="small" style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}>
                      <span>{d.did_win ? '🟢' : '🔴'} vs {d.opponent_name || '?'}</span>
                      <span className="mono">{d.elo_delta > 0 ? '+' : ''}{d.elo_delta} · {(d.finished_at || '').slice(5, 10)}</span>
                    </div>
                  ))}
              </div>

              <div className="card" style={{ padding: 14 }}>
                <h4 style={{ marginTop: 0 }}>Historique cauris</h4>
                {(!sel.audit || sel.audit.length === 0) ? <p className="muted small">Aucun.</p> :
                  sel.audit.map((a) => (
                    <div key={a.id} className="small" style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}>
                      <span className="muted">{a.source}{a.details?.admin ? ' (admin)' : ''}</span>
                      <span className="mono">{a.amount > 0 ? '+' : ''}{a.amount} → {a.cauris_after}</span>
                    </div>
                  ))}
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
