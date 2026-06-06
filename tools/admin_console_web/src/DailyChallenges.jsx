import { useEffect, useState } from 'react';
import {
  collection,
  documentId,
  doc,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';

function todayKey() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export default function DailyChallenges() {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [assignOpen, setAssignOpen] = useState(false);

  useEffect(() => {
    // Docs = yyyy-MM-dd → l'ordre lexicographique sur l'id = chronologique.
    const q = query(
      collection(db, 'daily_challenges'),
      orderBy(documentId(), 'desc'),
      limit(120),
    );
    return onSnapshot(
      q,
      (snap) => setItems(snap.docs.map((d) => ({ date: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, []);

  async function remove(date) {
    if (!confirm(`Retirer la devinette du jour du ${date} ?`)) return;
    try {
      await httpsCallable(functions, 'deleteDailyChallenge')({ date });
    } catch (e) {
      alert(`Erreur : ${e.code || e.name}: ${e.message}`);
    }
  }

  const today = todayKey();

  return (
    <>
      <header className="topbar">
        <h2>Devinettes du jour</h2>
        <span className="spacer" />
        <button className="btn primary small" onClick={() => setAssignOpen(true)}>
          + Assigner une date
        </button>
      </header>

      {error && <p className="error block">Erreur : {error}</p>}
      {!error && items === null && <p className="muted block">Chargement…</p>}
      {!error && items?.length === 0 && (
        <p className="muted block">Aucune devinette du jour en base (l'app utilise le bundle).</p>
      )}

      {items?.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Date</th>
              <th>Réponse</th>
              <th>Énigme (fr)</th>
              <th>Source</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((it) => (
              <tr key={it.date} className={it.date === today ? 'today' : undefined}>
                <td className="mono">
                  {it.date} {it.date === today && <span className="chip green">aujourd'hui</span>}
                </td>
                <td>{it.answer}</td>
                <td className="truncate">{it.riddle?.fr || '—'}</td>
                <td className="mono small muted">
                  {it.source_pack ? `${it.source_pack}/${it.source_devi_id || it.id}` : it.id}
                </td>
                <td className="row-actions">
                  <button className="btn danger small" onClick={() => remove(it.date)}>
                    Retirer
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {assignOpen && <AssignForm onClose={() => setAssignOpen(false)} />}
    </>
  );
}

function AssignForm({ onClose }) {
  const [date, setDate] = useState(todayKey());
  const [packs, setPacks] = useState([]);
  const [packId, setPackId] = useState('');
  const [devis, setDevis] = useState([]);
  const [deviId, setDeviId] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);

  // Liste des packs depuis catalog/index.packs[].
  useEffect(() => {
    return onSnapshot(doc(db, 'catalog', 'index'), (snap) => {
      const list = snap.data()?.packs;
      const ids = Array.isArray(list) ? list.map((p) => p.id).filter(Boolean) : [];
      setPacks(ids);
      if (ids.length && !packId) setPackId(ids[0]);
    });
  }, []);

  // Devinettes du pack sélectionné.
  useEffect(() => {
    if (!packId) return;
    setDevis([]);
    setDeviId('');
    getDocs(
      query(collection(db, 'packs', packId, 'devinettes'), orderBy('id')),
    ).then((snap) => {
      setDevis(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
  }, [packId]);

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      await httpsCallable(functions, 'upsertDailyChallenge')({
        date,
        sourcePackId: packId,
        sourceDeviId: deviId,
      });
      onClose();
    } catch (e) {
      setErr(`${e.code || e.name}: ${e.message}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Assigner une devinette du jour</h3>
        <label>Date (yyyy-MM-dd, heure locale)</label>
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        <label>Pack</label>
        <select value={packId} onChange={(e) => setPackId(e.target.value)}>
          {packs.map((p) => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>
        <label>Devinette ({devis.length})</label>
        <select value={deviId} onChange={(e) => setDeviId(e.target.value)}>
          <option value="">— choisir —</option>
          {devis.map((d) => (
            <option key={d.id} value={d.id}>
              {d.id} · {d.answer} · {(d.riddle?.fr || '').slice(0, 50)}
            </option>
          ))}
        </select>
        {err && <pre className="error">{err}</pre>}
        <div className="row actions">
          <span className="muted small">Copie le contenu de la devinette vers daily_challenges/{date}</span>
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy || !packId || !deviId} onClick={save}>
            {busy ? 'Assignation…' : 'Assigner'}
          </button>
        </div>
      </div>
    </div>
  );
}
