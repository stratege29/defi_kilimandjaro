import { useEffect, useState } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';

export default function Catalog({ onEdit }) {
  const [packs, setPacks] = useState(null);
  const [error, setError] = useState(null);
  const [publishing, setPublishing] = useState(null); // packId en cours
  const [result, setResult] = useState(null); // {packId, msg, ok}

  useEffect(() => {
    return onSnapshot(
      doc(db, 'catalog', 'index'),
      (snap) => {
        const data = snap.data() || {};
        const list = Array.isArray(data.packs) ? [...data.packs] : [];
        list.sort((a, b) => (a.ordering ?? 100) - (b.ordering ?? 100));
        setPacks(list);
      },
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, []);

  async function publish(packId) {
    if (!confirm(`Publier une nouvelle version du pack "${packId}" ?`)) return;
    setPublishing(packId);
    setResult(null);
    try {
      const call = httpsCallable(functions, 'publishPack');
      const res = await call({ packId });
      const r = res.data || {};
      setResult({
        packId,
        ok: true,
        msg: `v${r.version} publiée · ${r.count} devinettes · ${Math.round(
          (r.sizeBytes || 0) / 1024,
        )} Ko · catalog v${r.catalogVersion}`,
      });
    } catch (e) {
      setResult({ packId, ok: false, msg: `${e.code || e.name}: ${e.message}` });
    } finally {
      setPublishing(null);
    }
  }

  return (
    <>
      <header className="topbar">
        <h2>Catalogue des packs</h2>
      </header>

      {error && <p className="error block">Accès refusé / erreur : {error}</p>}
      {!error && packs === null && <p className="muted block">Chargement…</p>}
      {!error && packs?.length === 0 && (
        <p className="muted block">Aucun pack dans catalog/index.</p>
      )}

      {result && (
        <p className={result.ok ? 'success block' : 'error block'}>
          {result.ok ? '✅' : '❌'} {result.packId} — {result.msg}
        </p>
      )}

      {packs?.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Pack</th>
              <th>Statut</th>
              <th className="num">Devinettes</th>
              <th className="num">Version</th>
              <th>Dernière publication</th>
              <th>Par</th>
              <th className="num">Prix (♦)</th>
              <th>Bundle</th>
              <th className="num">Ordre</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {packs.map((p) => (
              <tr key={p.id}>
                <td>
                  <span
                    className="dot"
                    style={{ background: p.theme_color_hex || '#888' }}
                  />
                  {p.id}
                </td>
                <td>
                  <span className={p.visible ? 'chip green' : 'chip grey'}>
                    {p.visible ? 'Actif' : 'Masqué'}
                  </span>
                </td>
                <td className="num">{p.count ?? 0}</td>
                <td className="num">v{p.current_version ?? 1}</td>
                <td className="muted small">{fmtDate(p.last_published_at)}</td>
                <td className="muted small truncate">{p.last_published_by || '—'}</td>
                <td className="num">
                  {(p.unlock_cost_cauris ?? 0) === 0
                    ? 'Gratuit'
                    : p.unlock_cost_cauris}
                </td>
                <td>{p.bundled ? '✓' : '—'}</td>
                <td className="num">{p.ordering ?? 100}</td>
                <td className="row-actions">
                  <button className="btn ghost small" onClick={() => onEdit?.(p.id)}>
                    Éditer
                  </button>
                  <button
                    className="btn primary small"
                    disabled={publishing === p.id}
                    onClick={() => publish(p.id)}
                  >
                    {publishing === p.id ? 'Publication…' : 'Publier'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}

function fmtDate(v) {
  if (!v) return '—';
  let d;
  if (typeof v?.toDate === 'function') d = v.toDate();
  else if (typeof v === 'string') d = new Date(v);
  else if (typeof v === 'number') d = new Date(v);
  else if (typeof v?.seconds === 'number') d = new Date(v.seconds * 1000);
  else return '—';
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString('fr-FR');
}
