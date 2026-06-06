import { useEffect, useState } from 'react';
import {
  collection,
  query,
  where,
  orderBy,
  limit,
  onSnapshot,
  doc,
  updateDoc,
  serverTimestamp,
} from 'firebase/firestore';
import { auth, db } from './firebase.js';

const FILTERS = [
  { value: 'review', label: 'À modérer' },
  { value: 'approve', label: 'Approuvées' },
  { value: 'reject', label: 'Rejetées' },
  { value: 'pending', label: 'En attente LLM' },
];

export default function Moderation() {
  const [filter, setFilter] = useState('review');
  const [docs, setDocs] = useState(null); // null = chargement
  const [error, setError] = useState(null);

  useEffect(() => {
    setDocs(null);
    setError(null);
    const q = query(
      collection(db, 'submissions'),
      where('status', '==', filter),
      orderBy('score', 'desc'),
      limit(100),
    );
    return onSnapshot(
      q,
      (snap) => setDocs(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, [filter]);

  async function setStatus(id, status) {
    await updateDoc(doc(db, 'submissions', id), {
      status,
      moderatedAt: serverTimestamp(),
      moderatedBy: auth.currentUser?.uid ?? null,
    });
  }

  return (
    <>
      <header className="topbar">
        <h2>File de modération</h2>
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          {FILTERS.map((f) => (
            <option key={f.value} value={f.value}>
              {f.label}
            </option>
          ))}
        </select>
      </header>

      {error && <p className="error block">Accès refusé / erreur : {error}</p>}
      {!error && docs === null && <p className="muted block">Chargement…</p>}
      {!error && docs?.length === 0 && <p className="muted block">File vide.</p>}

      <div className="cards">
        {docs?.map((s) => (
          <div className="card" key={s.id}>
            <div className="row">
              <span className={'chip score ' + scoreClass(s.score)}>
                {s.score ?? 0}/100
              </span>
              <span className="muted small">
                {s.country} · {s.locale} · diff. {s.difficulty}/5
              </span>
              <span className="spacer" />
              <span className="muted small">{fmtDate(s.createdAt)}</span>
            </div>
            <p className="question">{s.question}</p>
            <p className="answer">Réponse : {s.answer}</p>
            {s.proverb && <p className="proverb">Proverbe : {s.proverb}</p>}
            {Array.isArray(s.tags) && s.tags.length > 0 && (
              <div className="tags">
                {s.tags.map((t) => (
                  <span className="tag" key={t}>
                    {t}
                  </span>
                ))}
              </div>
            )}
            <div className="row actions">
              {s.curatedBy && (
                <span className="muted small">Curator : {s.curatedBy}</span>
              )}
              <span className="spacer" />
              <button className="btn ghost" onClick={() => setStatus(s.id, 'reject')}>
                Rejeter
              </button>
              <button className="btn primary" onClick={() => setStatus(s.id, 'approve')}>
                Approuver
              </button>
            </div>
          </div>
        ))}
      </div>
    </>
  );
}

function scoreClass(score = 0) {
  if (score >= 80) return 'green';
  if (score >= 55) return 'orange';
  return 'red';
}

function fmtDate(v) {
  if (!v) return '—';
  // Timestamp Firestore, String ISO, ou epoch → tolérant (cf bug date Flutter).
  let d;
  if (typeof v?.toDate === 'function') d = v.toDate();
  else if (typeof v === 'string') d = new Date(v);
  else if (typeof v === 'number') d = new Date(v);
  else return '—';
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString('fr-FR');
}
