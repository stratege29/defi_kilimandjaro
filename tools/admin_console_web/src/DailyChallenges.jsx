import { useEffect, useState } from 'react';
import {
  collection,
  documentId,
  doc,
  getDocs,
  onSnapshot,
  orderBy,
  query,
  where,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';
import { normalize, lettersPoolFromAnswer } from './normalize.js';

const COUNTRIES = ['ci', 'sn', 'ml', 'cm', 'bj'];

function todayKey() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function dateKeyDaysAgo(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export default function DailyChallenges() {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [assignOpen, setAssignOpen] = useState(false);
  const [editing, setEditing] = useState(null);

  useEffect(() => {
    // Docs = yyyy-MM-dd. On évite orderBy(__name__ desc) (réclame un index) :
    // range sur le doc id (index automatique, ordre ascendant) + tri client desc.
    const start = dateKeyDaysAgo(180);
    const q = query(
      collection(db, 'daily_challenges'),
      where(documentId(), '>=', start),
      orderBy(documentId()),
    );
    return onSnapshot(
      q,
      (snap) => {
        const arr = snap.docs.map((d) => ({ date: d.id, ...d.data() }));
        arr.sort((a, b) => b.date.localeCompare(a.date));
        setItems(arr);
      },
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
                  <button className="btn ghost small" onClick={() => setEditing(it)}>
                    Éditer
                  </button>
                  <button className="btn danger small" onClick={() => remove(it.date)}>
                    Retirer
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {(assignOpen || editing) && (
        <AssignForm
          initial={editing}
          onClose={() => {
            setAssignOpen(false);
            setEditing(null);
          }}
        />
      )}
    </>
  );
}

function AssignForm({ onClose, initial }) {
  const isEdit = !!initial;
  const [date, setDate] = useState(initial?.date ?? todayKey());
  const [mode, setMode] = useState(initial ? 'custom' : 'source'); // 'source' | 'custom'
  // mode source
  const [packs, setPacks] = useState([]);
  const [packId, setPackId] = useState('');
  const [devis, setDevis] = useState([]);
  const [deviId, setDeviId] = useState('');
  // mode custom
  const [answer, setAnswer] = useState(initial?.answer ?? '');
  const [country, setCountry] = useState(initial?.country ?? 'ci');
  const [riddleFr, setRiddleFr] = useState(initial?.riddle?.fr ?? '');
  const [explFr, setExplFr] = useState(initial?.explanation?.fr ?? '');
  const [difficulty, setDifficulty] = useState(initial?.difficulty ?? 2);
  const [estTime, setEstTime] = useState(initial?.estimated_time_s ?? 30);
  const [tags, setTags] = useState((initial?.tags ?? []).join(', '));

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
    if (mode !== 'source' || !packId) return;
    setDevis([]);
    setDeviId('');
    getDocs(
      query(collection(db, 'packs', packId, 'devinettes'), orderBy('id')),
    ).then((snap) => {
      setDevis(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
  }, [packId, mode]);

  const pool = lettersPoolFromAnswer(answer);
  const answerLen = answer.replace(/\s/g, '').length;
  const customOk = answerLen >= 4 && answerLen <= 12 && riddleFr.trim().length > 0;

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      const payload =
        mode === 'custom'
          ? {
              date,
              custom: {
                // Conserve l'id/pack d'origine en édition (sinon id par défaut).
                ...(initial?.id ? { id: initial.id } : {}),
                ...(initial?.pack ? { pack: initial.pack } : {}),
                country,
                answer,
                riddle: { fr: riddleFr.trim() },
                explanation: explFr.trim() ? { fr: explFr.trim() } : {},
                difficulty: Number(difficulty),
                estimated_time_s: Number(estTime),
                tags: tags.split(',').map((t) => t.trim()).filter(Boolean),
              },
            }
          : { date, sourcePackId: packId, sourceDeviId: deviId };
      await httpsCallable(functions, 'upsertDailyChallenge')(payload);
      onClose();
    } catch (e) {
      setErr(`${e.code || e.name}: ${e.message}`);
    } finally {
      setBusy(false);
    }
  }

  const canSave = mode === 'custom' ? customOk : packId && deviId;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{isEdit ? `Éditer la devinette du ${date}` : 'Assigner une devinette du jour'}</h3>
        <label>Date (yyyy-MM-dd, heure locale)</label>
        <input
          type="date"
          value={date}
          disabled={isEdit}
          onChange={(e) => setDate(e.target.value)}
        />

        {!isEdit && (
          <div className="tabs">
            <button
              className={mode === 'source' ? 'tab active' : 'tab'}
              onClick={() => setMode('source')}
            >
              Depuis un pack
            </button>
            <button
              className={mode === 'custom' ? 'tab active' : 'tab'}
              onClick={() => setMode('custom')}
            >
              Personnalisée
            </button>
          </div>
        )}

        {mode === 'source' ? (
          <>
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
          </>
        ) : (
          <>
            <div className="grid2">
              <div>
                <label>Pays</label>
                <select value={country} onChange={(e) => setCountry(e.target.value)}>
                  {COUNTRIES.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
              </div>
              <div>
                <label>Difficulté (1–4)</label>
                <input type="number" min={1} max={4} value={difficulty}
                  onChange={(e) => setDifficulty(e.target.value)} />
              </div>
            </div>
            <label>Réponse {!(answerLen >= 4 && answerLen <= 12) && <span className="error small">(4–12 lettres)</span>}</label>
            <input value={answer} onChange={(e) => setAnswer(e.target.value)} />
            <p className="muted small mono">
              normalisé: {normalize(answer) || '—'} · lettres: [{pool.join(',')}]
            </p>
            <label>Énigme (fr)</label>
            <textarea rows={2} value={riddleFr} onChange={(e) => setRiddleFr(e.target.value)} />
            <label>Explication (fr)</label>
            <textarea rows={2} value={explFr} onChange={(e) => setExplFr(e.target.value)} />
            <div className="grid2">
              <div>
                <label>Temps estimé (s)</label>
                <input type="number" min={5} max={300} value={estTime}
                  onChange={(e) => setEstTime(e.target.value)} />
              </div>
              <div>
                <label>Tags (virgules)</label>
                <input value={tags} onChange={(e) => setTags(e.target.value)} />
              </div>
            </div>
          </>
        )}

        {err && <pre className="error">{err}</pre>}
        <div className="row actions">
          <span className="muted small">→ daily_challenges/{date}</span>
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy || !canSave} onClick={save}>
            {busy ? 'Enregistrement…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}
