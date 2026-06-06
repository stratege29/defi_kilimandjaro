import { useEffect, useMemo, useState } from 'react';
import { collection, onSnapshot, orderBy, query } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';
import { normalize, lettersPoolFromAnswer } from './normalize.js';

const COUNTRIES = ['ci', 'sn', 'ml', 'cm', 'bj'];

export default function PackEditor({ packId, onBack }) {
  const [devis, setDevis] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(null); // null | devinette obj | {__new:true}
  const [bulkOpen, setBulkOpen] = useState(false);
  const [validation, setValidation] = useState(null);
  const [validating, setValidating] = useState(false);

  useEffect(() => {
    setDevis(null);
    const q = query(
      collection(db, 'packs', packId, 'devinettes'),
      orderBy('id'),
    );
    return onSnapshot(
      q,
      (snap) => setDevis(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, [packId]);

  const nextId = useMemo(() => {
    let max = 0;
    for (const d of devis ?? []) {
      const m = /_(\d+)$/.exec(d.id);
      if (m) max = Math.max(max, parseInt(m[1], 10));
    }
    return `${packId}_${String(max + 1).padStart(3, '0')}`;
  }, [devis, packId]);

  async function runValidate() {
    setValidating(true);
    setValidation(null);
    try {
      const call = httpsCallable(functions, 'validatePackDraft');
      const res = await call({ packId });
      setValidation(res.data);
    } catch (e) {
      setValidation({ error: `${e.code || e.name}: ${e.message}` });
    } finally {
      setValidating(false);
    }
  }

  return (
    <>
      <header className="topbar">
        <button className="btn ghost small" onClick={onBack}>
          ← Catalogue
        </button>
        <h2>Pack : {packId}</h2>
        <span className="spacer" />
        <button className="btn ghost small" onClick={() => setBulkOpen(true)}>
          Import JSON
        </button>
        <button className="btn ghost small" onClick={runValidate} disabled={validating}>
          {validating ? 'Validation…' : 'Valider le brouillon'}
        </button>
        <button className="btn primary small" onClick={() => setEditing({ __new: true })}>
          + Devinette
        </button>
      </header>

      {error && <p className="error block">Erreur : {error}</p>}

      {validation && (
        <div className="block">
          {validation.error ? (
            <p className="error">{validation.error}</p>
          ) : (
            <div className={validation.valid ? 'success' : 'error'}>
              {validation.valid ? '✅ Brouillon valide' : '❌ Brouillon invalide'}{' '}
              ({validation.total} devinettes · {validation.errors?.length || 0} erreurs ·{' '}
              {validation.warnings?.length || 0} avertissements)
              {(validation.errors || []).slice(0, 20).map((e, i) => (
                <div key={i} className="small">• {e.deviId}: {e.code} — {e.message}</div>
              ))}
              {(validation.warnings || []).slice(0, 20).map((w, i) => (
                <div key={'w' + i} className="small muted">⚠ {w.deviId}: {w.code}</div>
              ))}
            </div>
          )}
        </div>
      )}

      {devis === null && !error && <p className="muted block">Chargement…</p>}
      {devis?.length === 0 && <p className="muted block">Aucune devinette.</p>}

      {devis?.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Réponse</th>
              <th>Énigme (fr)</th>
              <th className="num">Diff.</th>
              <th>Statut</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {devis.map((d) => (
              <tr key={d.id}>
                <td className="mono small">{d.id}</td>
                <td>{d.answer}</td>
                <td className="truncate">{d.riddle?.fr || '—'}</td>
                <td className="num">{d.difficulty}</td>
                <td>
                  <span className={'chip ' + statusClass(d.status)}>{d.status}</span>
                </td>
                <td>
                  <button className="btn ghost small" onClick={() => setEditing(d)}>
                    Éditer
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing && (
        <DevinetteForm
          packId={packId}
          initial={editing.__new ? null : editing}
          newId={nextId}
          onClose={() => setEditing(null)}
        />
      )}
      {bulkOpen && (
        <BulkImport packId={packId} onClose={() => setBulkOpen(false)} />
      )}
    </>
  );
}

function statusClass(s) {
  if (s === 'published') return 'green';
  if (s === 'draft') return 'orange';
  return 'grey';
}

function DevinetteForm({ packId, initial, newId, onClose }) {
  const isNew = !initial;
  const [id] = useState(initial?.id ?? newId);
  const [country, setCountry] = useState(initial?.country ?? 'ci');
  const [answer, setAnswer] = useState(initial?.answer ?? '');
  const [riddleFr, setRiddleFr] = useState(initial?.riddle?.fr ?? '');
  const [explFr, setExplFr] = useState(initial?.explanation?.fr ?? '');
  const [difficulty, setDifficulty] = useState(initial?.difficulty ?? 2);
  const [estTime, setEstTime] = useState(initial?.estimated_time_s ?? 30);
  const [tags, setTags] = useState((initial?.tags ?? []).join(', '));
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);

  const pool = lettersPoolFromAnswer(answer);
  const normalized = normalize(answer);
  const answerLen = answer.replace(/\s/g, '').length;
  const answerOk = answerLen >= 4 && answerLen <= 12;

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      const tagList = tags
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean);
      const devinette = {
        id,
        pack: packId,
        country,
        answer, // le serveur upper-case + recalcule normalized/letters_pool
        riddle: { fr: riddleFr.trim() },
        explanation: explFr.trim() ? { fr: explFr.trim() } : {},
        difficulty: Number(difficulty),
        estimated_time_s: Number(estTime),
        tags: tagList,
      };
      const call = httpsCallable(functions, 'upsertDevinette');
      await call({ packId, devinette });
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
        <h3>{isNew ? 'Nouvelle devinette' : `Éditer ${id}`}</h3>
        <label>ID</label>
        <input value={id} disabled />
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
            <input
              type="number" min={1} max={4}
              value={difficulty}
              onChange={(e) => setDifficulty(e.target.value)}
            />
          </div>
        </div>
        <label>Réponse {!answerOk && <span className="error small">(4–12 lettres)</span>}</label>
        <input value={answer} onChange={(e) => setAnswer(e.target.value)} />
        <p className="muted small mono">
          normalisé: {normalized || '—'} · lettres: [{pool.join(',')}]
        </p>
        <label>Énigme (fr)</label>
        <textarea rows={2} value={riddleFr} onChange={(e) => setRiddleFr(e.target.value)} />
        <label>Explication (fr)</label>
        <textarea rows={2} value={explFr} onChange={(e) => setExplFr(e.target.value)} />
        <div className="grid2">
          <div>
            <label>Temps estimé (s)</label>
            <input
              type="number" min={5} max={300}
              value={estTime}
              onChange={(e) => setEstTime(e.target.value)}
            />
          </div>
          <div>
            <label>Tags (séparés par virgule)</label>
            <input value={tags} onChange={(e) => setTags(e.target.value)} />
          </div>
        </div>
        {err && <pre className="error">{err}</pre>}
        <div className="row actions">
          <span className="muted small">Sauvegarde → statut "draft" (à publier ensuite)</span>
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy || !answerOk || !riddleFr.trim()} onClick={save}>
            {busy ? 'Sauvegarde…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}

function BulkImport({ packId, onClose }) {
  const [text, setText] = useState('');
  const [mode, setMode] = useState('append');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);

  async function run() {
    setBusy(true);
    setResult(null);
    let arr;
    try {
      arr = JSON.parse(text);
      if (!Array.isArray(arr)) throw new Error('Le JSON doit être un tableau []');
    } catch (e) {
      setResult({ error: `JSON invalide : ${e.message}` });
      setBusy(false);
      return;
    }
    try {
      const call = httpsCallable(functions, 'bulkImportDevinettes');
      const res = await call({ packId, mode, devinettes: arr });
      setResult(res.data);
    } catch (e) {
      setResult({ error: `${e.code || e.name}: ${e.message}` });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Import JSON — {packId}</h3>
        <p className="muted small">
          Tableau JSON de devinettes ({'{'}id, answer, riddle, explanation, difficulty, tags…{'}'}).
          answer_normalized / letters_pool sont recalculés serveur.
        </p>
        <label>Mode</label>
        <select value={mode} onChange={(e) => setMode(e.target.value)}>
          <option value="append">append (ajouter)</option>
          <option value="replace">replace (remplace les brouillons)</option>
        </select>
        <label>JSON</label>
        <textarea rows={10} className="mono" value={text} onChange={(e) => setText(e.target.value)} />
        {result && (
          result.error ? (
            <pre className="error">{result.error}</pre>
          ) : (
            <p className="success small">
              ✅ {result.accepted} importées · {result.rejected?.length || 0} rejetées
              {result.rejected?.length > 0 && (
                <span className="error">
                  {' '}— {result.rejected.slice(0, 5).map((r) => `${r.id}: ${r.error}`).join(' | ')}
                </span>
              )}
            </p>
          )
        )}
        <div className="row actions">
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Fermer</button>
          <button className="btn primary" disabled={busy || !text.trim()} onClick={run}>
            {busy ? 'Import…' : 'Importer'}
          </button>
        </div>
      </div>
    </div>
  );
}
