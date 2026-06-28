import { useEffect, useState } from 'react';
import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';

const STATUS_LABEL = {
  scheduled: { label: 'À venir', cls: 'chip' },
  live: { label: 'En cours', cls: 'chip green' },
  finished: { label: 'Terminé', cls: 'chip' },
  cancelled: { label: 'Annulé', cls: 'chip' },
};

function fmt(ts) {
  if (!ts) return '—';
  const ms = ts.seconds ? ts.seconds * 1000 : ts._seconds ? ts._seconds * 1000 : null;
  return ms ? new Date(ms).toLocaleString() : '—';
}

export default function Tournaments() {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [createOpen, setCreateOpen] = useState(false);

  useEffect(() => {
    const q = query(collection(db, 'tournaments'), orderBy('start_at', 'desc'));
    return onSnapshot(
      q,
      (snap) => setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, []);

  async function cancel(id) {
    if (!confirm('Annuler ce tournoi ? (uniquement avant le démarrage)')) return;
    try {
      await httpsCallable(functions, 'cancelTournament')({ tournament_id: id });
    } catch (e) {
      alert(`Erreur : ${e.code || e.name}: ${e.message}`);
    }
  }

  return (
    <>
      <header className="topbar">
        <h2>Tournois</h2>
        <span className="spacer" />
        <button className="btn primary small" onClick={() => setCreateOpen(true)}>
          + Créer un tournoi
        </button>
      </header>

      {error && <p className="error block">Erreur : {error}</p>}
      {!error && items === null && <p className="muted block">Chargement…</p>}
      {!error && items?.length === 0 && (
        <p className="muted block">Aucun tournoi. Crée le premier !</p>
      )}

      {items?.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Nom</th>
              <th>Statut</th>
              <th>Début</th>
              <th>Fin</th>
              <th>Durée</th>
              <th>Inscrits</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((t) => {
              const s = STATUS_LABEL[t.status] || STATUS_LABEL.scheduled;
              return (
                <tr key={t.id}>
                  <td>{t.name}</td>
                  <td>
                    <span className={s.cls}>{s.label}</span>
                  </td>
                  <td className="mono small">{fmt(t.start_at)}</td>
                  <td className="mono small">{fmt(t.end_at)}</td>
                  <td className="mono small">{t.duration_min} min</td>
                  <td className="mono">{t.participant_count ?? 0}</td>
                  <td className="row-actions">
                    {t.status === 'scheduled' && (
                      <button className="btn danger small" onClick={() => cancel(t.id)}>
                        Annuler
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      {createOpen && <CreateForm onClose={() => setCreateOpen(false)} />}
    </>
  );
}

function defaultStartLocal() {
  // Maintenant + 15 min, formaté pour <input type="datetime-local">.
  const d = new Date(Date.now() + 15 * 60_000);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

function CreateForm({ onClose }) {
  const [name, setName] = useState('Tournoi du soir');
  const [startLocal, setStartLocal] = useState(defaultStartLocal());
  const [durationMin, setDurationMin] = useState(20);
  const [packId, setPackId] = useState('');
  const [packs, setPacks] = useState([]);
  const [pointsWin, setPointsWin] = useState(3);
  const [pointsDraw, setPointsDraw] = useState(1);
  const [minParticipants, setMinParticipants] = useState(2);
  const [tiers, setTiers] = useState([
    { rank_min: 1, rank_max: 1, cauris: 500, badge_id: 'tournament_gold' },
    { rank_min: 2, rank_max: 3, cauris: 250, badge_id: 'tournament_silver' },
    { rank_min: 4, rank_max: 10, cauris: 100, badge_id: '' },
  ]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);

  // Liste optionnelle des packs (scope des devinettes) depuis catalog/index.
  useEffect(() => {
    return onSnapshot(doc(db, 'catalog', 'index'), (snap) => {
      const list = snap.data()?.packs;
      setPacks(Array.isArray(list) ? list.map((p) => p.id).filter(Boolean) : []);
    });
  }, []);

  function updateTier(i, key, value) {
    setTiers((prev) =>
      prev.map((t, idx) => (idx === i ? { ...t, [key]: value } : t)),
    );
  }
  function addTier() {
    setTiers((prev) => [...prev, { rank_min: 1, rank_max: 1, cauris: 0, badge_id: '' }]);
  }
  function removeTier(i) {
    setTiers((prev) => prev.filter((_, idx) => idx !== i));
  }

  const startMs = new Date(startLocal).getTime();
  const startOk = Number.isFinite(startMs) && startMs > Date.now();
  const canSave = name.trim().length > 0 && startOk && durationMin >= 1;

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      const rewards = tiers.map((t) => ({
        rank_min: Number(t.rank_min),
        rank_max: Number(t.rank_max),
        cauris: Number(t.cauris) || 0,
        badge_id: t.badge_id?.trim() ? t.badge_id.trim() : null,
      }));
      await httpsCallable(functions, 'createTournament')({
        name: name.trim(),
        start_at: startMs,
        duration_min: Number(durationMin),
        pack_id: packId || null,
        points_win: Number(pointsWin),
        points_draw: Number(pointsDraw),
        min_participants: Number(minParticipants),
        rewards,
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
        <h3>Créer un tournoi</h3>

        <label>Nom</label>
        <input value={name} onChange={(e) => setName(e.target.value)} />

        <div className="grid2">
          <div>
            <label>
              Début {!startOk && <span className="error small">(futur requis)</span>}
            </label>
            <input
              type="datetime-local"
              value={startLocal}
              onChange={(e) => setStartLocal(e.target.value)}
            />
          </div>
          <div>
            <label>Durée (min)</label>
            <input
              type="number"
              min={1}
              max={1440}
              value={durationMin}
              onChange={(e) => setDurationMin(e.target.value)}
            />
          </div>
        </div>

        <label>Pack de devinettes (optionnel)</label>
        <select value={packId} onChange={(e) => setPackId(e.target.value)}>
          <option value="">— tous (pool global) —</option>
          {packs.map((p) => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>

        <div className="grid2">
          <div>
            <label>Points victoire</label>
            <input type="number" min={0} value={pointsWin}
              onChange={(e) => setPointsWin(e.target.value)} />
          </div>
          <div>
            <label>Points nul</label>
            <input type="number" min={0} value={pointsDraw}
              onChange={(e) => setPointsDraw(e.target.value)} />
          </div>
        </div>

        <label>Participants min. (sous ce seuil, pas de récompense)</label>
        <input type="number" min={1} value={minParticipants}
          onChange={(e) => setMinParticipants(e.target.value)} />

        <label>Récompenses par rang</label>
        <table className="table">
          <thead>
            <tr>
              <th>Rang min</th>
              <th>Rang max</th>
              <th>Cauris</th>
              <th>Badge id</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {tiers.map((t, i) => (
              <tr key={i}>
                <td>
                  <input type="number" min={1} value={t.rank_min}
                    onChange={(e) => updateTier(i, 'rank_min', e.target.value)} />
                </td>
                <td>
                  <input type="number" min={1} value={t.rank_max}
                    onChange={(e) => updateTier(i, 'rank_max', e.target.value)} />
                </td>
                <td>
                  <input type="number" min={0} max={5000} value={t.cauris}
                    onChange={(e) => updateTier(i, 'cauris', e.target.value)} />
                </td>
                <td>
                  <input value={t.badge_id}
                    onChange={(e) => updateTier(i, 'badge_id', e.target.value)} />
                </td>
                <td>
                  <button className="btn ghost small" onClick={() => removeTier(i)}>✕</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <button className="btn ghost small" onClick={addTier}>+ Ajouter un palier</button>

        {err && <pre className="error">{err}</pre>}
        <div className="row actions">
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy || !canSave} onClick={save}>
            {busy ? 'Création…' : 'Créer'}
          </button>
        </div>
      </div>
    </div>
  );
}
