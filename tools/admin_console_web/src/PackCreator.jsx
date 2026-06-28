import { useEffect, useMemo, useState } from 'react';
import {
  collection,
  collectionGroup,
  query,
  where,
  orderBy,
  onSnapshot,
  doc,
  getDoc,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase.js';

const call = (name, data) =>
  httpsCallable(functions, name, { timeout: 120000 })(data).then((r) => r.data);

const STATUS_LABELS = {
  queued: 'En file',
  planning: 'Plan en cours…',
  plan_review: 'Plan à valider',
  plan_approved: 'Plan validé',
  generating: 'Génération…',
  review: 'Revue questions',
  ready: 'Prêt',
  published: 'Publié',
  failed: 'Échec',
  cancelled: 'Annulé',
};

export default function PackCreator() {
  const [jobs, setJobs] = useState(null);
  const [error, setError] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [showCreate, setShowCreate] = useState(false);
  const [packIds, setPackIds] = useState([]);
  const [mode, setMode] = useState('jobs'); // 'jobs' | 'bypack'

  useEffect(() => {
    const q = query(collection(db, 'pack_jobs'), orderBy('createdAt', 'desc'));
    return onSnapshot(
      q,
      (snap) => setJobs(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (e) => setError(`${e.code}: ${e.message}`),
    );
  }, []);

  // Liste des packs existants (catalog/index) pour la réaffectation des questions.
  useEffect(() => {
    getDoc(doc(db, 'catalog', 'index'))
      .then((s) => {
        const packs = Array.isArray(s.data()?.packs) ? s.data().packs : [];
        setPackIds(packs.map((p) => p.id).filter(Boolean).sort());
      })
      .catch(() => setPackIds([]));
  }, []);

  const selected = useMemo(
    () => jobs?.find((j) => j.id === selectedId) ?? null,
    [jobs, selectedId],
  );

  return (
    <>
      <header className="topbar">
        <h2>Pack Creator</h2>
        <div className="tabs" style={{ margin: 0, border: 0 }}>
          <button
            className={mode === 'jobs' ? 'tab active' : 'tab'}
            onClick={() => setMode('jobs')}
          >
            Jobs
          </button>
          <button
            className={mode === 'bypack' ? 'tab active' : 'tab'}
            onClick={() => setMode('bypack')}
          >
            En attente par pack
          </button>
        </div>
        <span className="spacer" />
        <button className="btn primary" onClick={() => setShowCreate(true)}>
          Nouveau pack
        </button>
      </header>

      {error && <p className="error block">Accès refusé / erreur : {error}</p>}

      {mode === 'bypack' ? (
        <PackReview packIds={packIds} />
      ) : (
        <>
          {!error && jobs === null && <p className="muted block">Chargement…</p>}
          <div className="row" style={{ alignItems: 'flex-start', gap: 16 }}>
            <div style={{ flex: '0 0 360px' }}>
              {jobs?.length === 0 && <p className="muted block">Aucun job.</p>}
              {jobs?.map((j) => (
                <JobRow
                  key={j.id}
                  job={j}
                  active={j.id === selectedId}
                  onClick={() => setSelectedId(j.id)}
                />
              ))}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              {selected ? (
                <JobDetail job={selected} packIds={packIds} />
              ) : (
                <p className="muted block">Sélectionne un job.</p>
              )}
            </div>
          </div>
        </>
      )}

      {showCreate && <CreateModal onClose={() => setShowCreate(false)} />}
    </>
  );
}

function JobRow({ job, active, onClick }) {
  const p = job.progress ?? {};
  const pct = p.batchesTotal ? Math.round((p.batchesDone / p.batchesTotal) * 100) : 0;
  return (
    <div
      className="card"
      style={{ cursor: 'pointer', borderColor: active ? 'var(--or)' : undefined }}
      onClick={onClick}
    >
      <div className="row">
        <span className={'chip ' + statusClass(job.status)}>
          {STATUS_LABELS[job.status] ?? job.status}
        </span>
        <span className="spacer" />
        <span className="muted small">{p.generated ?? 0}/{p.targetTotal ?? 0}</span>
      </div>
      <p className="question" style={{ marginBottom: 4 }}>{job.topic}</p>
      <div className="muted small">pack: {job.packId}</div>
      {(job.status === 'generating' || job.status === 'review') && (
        <div className="progressbar"><span style={{ width: `${pct}%` }} /></div>
      )}
    </div>
  );
}

function JobDetail({ job, packIds }) {
  const [busy, setBusy] = useState(null);

  const run = async (label, fn) => {
    setBusy(label);
    try {
      await fn();
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
    } finally {
      setBusy(null);
    }
  };

  const p = job.progress ?? {};
  const usage = job.usage ?? {};

  return (
    <div className="card">
      <div className="row">
        <span className={'chip ' + statusClass(job.status)}>
          {STATUS_LABELS[job.status] ?? job.status}
        </span>
        <span className="spacer" />
        <span className="muted small">
          ~${(usage.estUsd ?? 0).toFixed(2)} · {usage.claudeCalls ?? 0} appels
        </span>
      </div>
      <h3 style={{ margin: '8px 0' }}>{job.topic}</h3>
      <div className="muted small">
        pack: {job.packId} · généré {p.generated ?? 0}/{p.targetTotal ?? 0} ·
        rejetés {p.rejectedAuto ?? 0} · doublons {p.duplicatesDropped ?? 0}
        {job.ecoQuota ? ' · ⚡ éco quota' : ''}
      </div>
      {p.lastError && <p className="error block">Dernière erreur : {p.lastError}</p>}

      <div className="row actions" style={{ marginTop: 12, flexWrap: 'wrap', gap: 8 }}>
        {job.status === 'queued' && (
          <button
            className="btn primary"
            disabled={busy}
            onClick={() => run('plan', () => call('generateResearchPlan', { jobId: job.id }))}
          >
            {busy === 'plan' ? 'Génération du plan…' : 'Générer le plan'}
          </button>
        )}
        {job.status === 'failed' && (
          <button
            className="btn"
            disabled={busy}
            onClick={() => run('retry', () => call('retryPackJob', { jobId: job.id }))}
          >
            Relancer
          </button>
        )}
        {!['published', 'cancelled', 'failed'].includes(job.status) && (
          <button
            className="btn danger"
            disabled={busy}
            onClick={() => {
              if (confirm('Annuler ce job ?')) run('cancel', () => call('cancelPackJob', { jobId: job.id }));
            }}
          >
            Annuler
          </button>
        )}
      </div>

      {job.status === 'plan_review' && <PlanEditor job={job} />}

      {job.status === 'plan_approved' && (
        <p className="success block">
          Plan validé ✓ — la génération démarre au prochain passage du cron
          (≤ 2 min). Le statut passera à « Génération… ».
        </p>
      )}

      {['generating', 'review', 'ready', 'published'].includes(job.status) && (
        <CandidateReview job={job} packIds={packIds} />
      )}
    </div>
  );
}

function PlanEditor({ job }) {
  const [plan, setPlan] = useState(() => normalizePlan(job.plan));
  const [busy, setBusy] = useState(false);

  const total = plan.subThemes.reduce((s, t) => s + (Number(t.targetCount) || 0), 0);
  const diffTotal = ['1', '2', '3', '4'].reduce(
    (s, d) => s + (Number(plan.difficultyDistribution[d]) || 0),
    0,
  );

  const approve = async () => {
    setBusy(true);
    try {
      await call('approveResearchPlan', {
        jobId: job.id,
        plan: {
          subThemes: plan.subThemes.map((t) => ({
            name: t.name,
            targetCount: Number(t.targetCount) || 0,
            tags: t.tags.slice(0, 20),
          })),
          difficultyDistribution: {
            1: Number(plan.difficultyDistribution['1']) || 0,
            2: Number(plan.difficultyDistribution['2']) || 0,
            3: Number(plan.difficultyDistribution['3']) || 0,
            4: Number(plan.difficultyDistribution['4']) || 0,
          },
          targetTotal: total,
        },
      });
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={{ marginTop: 16 }}>
      <h4>Plan de recherche</h4>
      {job.plan?.rationale && <p className="muted small">{job.plan.rationale}</p>}

      <table className="table">
        <thead>
          <tr><th>Sous-thème</th><th>Cible</th><th>Tags</th></tr>
        </thead>
        <tbody>
          {plan.subThemes.map((t, i) => (
            <tr key={i}>
              <td>
                <input
                  value={t.name}
                  onChange={(e) => updateSub(i, { name: e.target.value })}
                />
              </td>
              <td style={{ width: 80 }}>
                <input
                  type="number"
                  value={t.targetCount}
                  onChange={(e) => updateSub(i, { targetCount: e.target.value })}
                />
              </td>
              <td>
                <input
                  value={t.tags.join(', ')}
                  onChange={(e) =>
                    updateSub(i, {
                      tags: e.target.value.split(',').map((s) => s.trim()).filter(Boolean),
                    })
                  }
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="row" style={{ gap: 8, marginTop: 8 }}>
        {['1', '2', '3', '4'].map((d) => (
          <label key={d} className="muted small">
            Niv. {d}{' '}
            <input
              type="number"
              style={{ width: 60 }}
              value={plan.difficultyDistribution[d]}
              onChange={(e) =>
                setPlan((p) => ({
                  ...p,
                  difficultyDistribution: { ...p.difficultyDistribution, [d]: e.target.value },
                }))
              }
            />
          </label>
        ))}
      </div>

      <div className="muted small" style={{ marginTop: 6 }}>
        Total sous-thèmes : {total} · total difficulté : {diffTotal}
        {total !== diffTotal && <span className="error"> (à équilibrer)</span>}
      </div>

      <button className="btn primary" style={{ marginTop: 10 }} disabled={busy} onClick={approve}>
        {busy ? 'Validation…' : 'Approuver le plan → générer'}
      </button>
    </div>
  );

  function updateSub(i, patch) {
    setPlan((p) => {
      const subThemes = [...p.subThemes];
      subThemes[i] = { ...subThemes[i], ...patch };
      return { ...p, subThemes };
    });
  }
}

function CandidateReview({ job, packIds }) {
  const [filter, setFilter] = useState('pending');
  const [cands, setCands] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    setCands(null);
    setError(null);
    // Pas d'orderBy serveur (éviterait un index composite avec le where) :
    // on trie par candId côté client.
    const q = query(
      collection(db, 'pack_jobs', job.id, 'candidates'),
      where('reviewStatus', '==', filter),
    );
    return onSnapshot(
      q,
      (snap) =>
        setCands(
          snap.docs
            .map((d) => ({ id: d.id, ...d.data() }))
            .sort((a, b) => (a.candId || '').localeCompare(b.candId || '')),
        ),
      (e) => {
        setCands([]);
        setError(`${e.code}: ${e.message}`);
      },
    );
  }, [job.id, filter]);

  const counts = job.progress ?? {};

  return (
    <div style={{ marginTop: 16 }}>
      <div className="row">
        <h4 style={{ margin: 0 }}>Revue des questions</h4>
        <span className="spacer" />
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="pending">En attente</option>
          <option value="approved">Approuvées</option>
          <option value="rejected">Rejetées</option>
        </select>
        <button
          className="btn primary"
          style={{ marginLeft: 8 }}
          onClick={() => {
            if (confirm(`Publier le pack ${job.packId} ? (valide les drafts approuvés)`))
              call('publishPack', { packId: job.packId })
                .then((r) => alert(`Publié v${r.version} (${r.count} devinettes).`))
                .catch((e) => alert(`${e.code || ''} ${e.message}`));
          }}
        >
          Publier le pack
        </button>
      </div>
      <div className="muted small">
        vérifiées OK : {counts.verified ?? 0} · généré {counts.generated ?? 0}
      </div>

      {error && <p className="error block">Erreur : {error}</p>}
      {!error && cands === null && <p className="muted block">Chargement…</p>}
      {!error && cands?.length === 0 && (
        <p className="muted block">Aucun candidat ({filter}).</p>
      )}

      <div className="cards">
        {cands?.map((c) => (
          <CandidateCard key={c.id} jobId={job.id} cand={c} packIds={packIds} />
        ))}
      </div>
    </div>
  );
}

function CandidateCard({ jobId, cand, packIds = [] }) {
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState(cand);
  const [busy, setBusy] = useState(false);
  const effPack = cand.effectivePackId || cand.packId;
  const [targetPack, setTargetPack] = useState(effPack);
  const [dailyDate, setDailyDate] = useState(() => new Date().toISOString().slice(0, 10));
  const isDaily = targetPack === '__daily__';

  // Options du sélecteur : packs existants + le pack du candidat (toujours présent).
  const packOptions = Array.from(new Set([cand.packId, effPack, ...packIds])).filter(Boolean);
  const moved = targetPack && targetPack !== effPack && !isDaily;

  const act = async (name, data) => {
    setBusy(true);
    try {
      await call(name, data);
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
    } finally {
      setBusy(false);
    }
  };

  const v = cand.verification ?? {};
  return (
    <div className="card">
      <div className="row">
        <span className={'chip ' + verdictClass(v.verdict)}>
          {v.verdict ?? '—'}{v.confidence ? ` ${Math.round(v.confidence * 100)}%` : ''}
        </span>
        <span className="muted small">diff. {cand.difficulty}/4 · {cand.subTheme}</span>
        <span className="spacer" />
        <span className="answer">{cand.answer}</span>
      </div>

      {!editing ? (
        <>
          <p className="question">{cand.riddleFr}</p>
          <p className="muted small">{cand.explanationFr}</p>
        </>
      ) : (
        <div style={{ display: 'grid', gap: 6, marginTop: 8 }}>
          <input value={form.answer} onChange={(e) => setForm({ ...form, answer: e.target.value })} placeholder="Réponse" />
          <input value={form.riddleFr} onChange={(e) => setForm({ ...form, riddleFr: e.target.value })} placeholder="Énigme" />
          <input value={form.explanationFr} onChange={(e) => setForm({ ...form, explanationFr: e.target.value })} placeholder="Explication" />
          <input type="number" min="1" max="4" value={form.difficulty} onChange={(e) => setForm({ ...form, difficulty: Number(e.target.value) })} placeholder="Difficulté" />
        </div>
      )}

      {Array.isArray(v.sources) && v.sources.length > 0 && (
        <div className="muted small" style={{ marginTop: 6 }}>
          Sources :{' '}
          {v.sources.map((s, i) => (
            <a key={i} href={s.url} target="_blank" rel="noreferrer" style={{ marginRight: 8 }}>
              {s.title || s.url}
            </a>
          ))}
        </div>
      )}
      {v.notes && <p className="muted small">Note : {v.notes}</p>}
      {cand.promotedDeviId && (
        <p className="muted small">
          {cand.promotedPackId === 'daily'
            ? `→ 📅 Question du jour ${cand.promotedDailyDate || ''}`
            : `→ ${cand.promotedDeviId}${
                cand.promotedPackId && cand.promotedPackId !== cand.packId
                  ? ` (pack ${cand.promotedPackId})`
                  : ''
              }`}
        </p>
      )}

      {effPack !== cand.packId && (
        <p className="muted small">en attente sous le pack <b>{effPack}</b></p>
      )}

      {cand.reviewStatus !== 'approved' && (
        <div className="row" style={{ marginTop: 8, gap: 6 }}>
          <span className="muted small">Pack :</span>
          <select
            value={targetPack}
            onChange={(e) => setTargetPack(e.target.value)}
            style={{ margin: 0, maxWidth: 220 }}
          >
            <option value="__daily__">📅 Question du jour</option>
            {packOptions.map((p) => (
              <option key={p} value={p}>
                {p}
                {p === cand.packId ? ' (ce job)' : ''}
              </option>
            ))}
          </select>
          {isDaily && (
            <input
              type="date"
              value={dailyDate}
              onChange={(e) => setDailyDate(e.target.value)}
              style={{ margin: 0, maxWidth: 160 }}
            />
          )}
          {moved && (
            <button
              className="btn ghost"
              disabled={busy}
              title="Déplace la question (toujours en attente) vers ce pack"
              onClick={() =>
                act('reassignCandidate', { jobId, candId: cand.candId, targetPackId: targetPack })
              }
            >
              Réaffecter
            </button>
          )}
        </div>
      )}

      <div className="row actions" style={{ marginTop: 8, gap: 8 }}>
        {!editing ? (
          <button className="btn ghost" disabled={busy} onClick={() => { setForm(cand); setEditing(true); }}>
            Éditer
          </button>
        ) : (
          <>
            <button className="btn ghost" onClick={() => setEditing(false)}>Annuler</button>
            <button
              className="btn"
              disabled={busy}
              onClick={() =>
                act('updateCandidate', {
                  jobId,
                  candId: cand.candId,
                  patch: {
                    answer: form.answer.toUpperCase(),
                    riddleFr: form.riddleFr,
                    explanationFr: form.explanationFr,
                    difficulty: Number(form.difficulty),
                  },
                }).then(() => setEditing(false))
              }
            >
              Enregistrer
            </button>
          </>
        )}
        <span className="spacer" />
        {cand.reviewStatus !== 'rejected' && (
          <button
            className="btn danger"
            disabled={busy}
            onClick={() => act('rejectCandidate', { jobId, candId: cand.candId })}
          >
            Rejeter
          </button>
        )}
        {cand.reviewStatus !== 'approved' && (
          <button
            className="btn primary"
            disabled={busy}
            onClick={() =>
              isDaily
                ? act('assignCandidateToDaily', { jobId, candId: cand.candId, date: dailyDate })
                : act('approveCandidate', {
                    jobId,
                    candId: cand.candId,
                    ...(targetPack ? { targetPackId: targetPack } : {}),
                  })
            }
          >
            {isDaily
              ? `Affecter au jour ${dailyDate}`
              : targetPack && targetPack !== cand.packId
                ? `Approuver → ${targetPack}`
                : 'Approuver'}
          </button>
        )}
      </div>
    </div>
  );
}

function PackReview({ packIds }) {
  const [pack, setPack] = useState('');
  const [filter, setFilter] = useState('pending');
  const [cands, setCands] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!pack) {
      setCands(null);
      return undefined;
    }
    setCands(null);
    setError(null);
    // Agrège tous les jobs : candidats dont le pack de destination = pack choisi.
    const q = query(
      collectionGroup(db, 'candidates'),
      where('effectivePackId', '==', pack),
      where('reviewStatus', '==', filter),
    );
    return onSnapshot(
      q,
      (snap) =>
        setCands(
          snap.docs
            .map((d) => ({
              id: d.id,
              jobId: d.ref.parent.parent?.id,
              ...d.data(),
            }))
            .sort((a, b) => (a.candId || '').localeCompare(b.candId || '')),
        ),
      (e) => {
        setCands([]);
        setError(`${e.code}: ${e.message}`);
      },
    );
  }, [pack, filter]);

  return (
    <div style={{ padding: '0 24px' }}>
      <div className="row" style={{ marginTop: 16, gap: 8 }}>
        <span className="muted small">Pack :</span>
        <select
          value={pack}
          onChange={(e) => setPack(e.target.value)}
          style={{ margin: 0, maxWidth: 260 }}
        >
          <option value="">— choisir un pack —</option>
          {packIds.map((p) => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>
        <select value={filter} onChange={(e) => setFilter(e.target.value)} style={{ margin: 0 }}>
          <option value="pending">En attente</option>
          <option value="approved">Approuvées</option>
          <option value="rejected">Rejetées</option>
        </select>
      </div>

      {!pack && (
        <p className="muted block">Choisis un pack pour voir ses questions en revue.</p>
      )}
      {pack && error && <p className="error block">Erreur : {error}</p>}
      {pack && !error && cands === null && <p className="muted block">Chargement…</p>}
      {pack && !error && cands?.length === 0 && (
        <p className="muted block">Aucune question ({filter}) destinée à {pack}.</p>
      )}

      <div className="cards">
        {cands?.map((c) => (
          <CandidateCard
            key={`${c.jobId}_${c.id}`}
            jobId={c.jobId}
            cand={c}
            packIds={packIds}
          />
        ))}
      </div>
    </div>
  );
}

function CreateModal({ onClose }) {
  const [packId, setPackId] = useState('');
  const [idTouched, setIdTouched] = useState(false);
  const [topic, setTopic] = useState('');
  const [targetTotal, setTargetTotal] = useState(500);
  const [eco, setEco] = useState(false);
  const [busy, setBusy] = useState(false);

  const idValid = /^[a-z][a-z0-9_]{1,31}$/.test(packId);

  const onTopic = (v) => {
    setTopic(v);
    if (!idTouched) setPackId(slugifyPackId(v)); // auto-dérive l'id tant qu'il n'est pas édité
  };

  const submit = async () => {
    if (!idValid) return;
    setBusy(true);
    try {
      await call('createPackJob', {
        packId,
        topic: topic.trim(),
        targetTotal: Number(targetTotal),
        ecoQuota: eco,
      });
      onClose();
    } catch (e) {
      alert(`${e.code || ''} ${e.message}`);
      setBusy(false);
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Nouveau pack</h3>
        <label className="muted small">Sujet / thème</label>
        <input
          value={topic}
          onChange={(e) => onTopic(e.target.value)}
          placeholder="ex: Histoire de la Côte d'Ivoire"
          autoFocus
        />
        <label className="muted small">Identifiant (snake_case)</label>
        <input
          value={packId}
          onChange={(e) => {
            setIdTouched(true);
            setPackId(slugifyPackId(e.target.value));
          }}
          placeholder="ex: histoire_ci"
        />
        <div className="muted small" style={{ marginTop: 4 }}>
          {packId
            ? idValid
              ? `Sera créé : ${packId}`
              : 'Min. 2 caractères, commence par une lettre.'
            : 'Généré depuis le sujet, éditable.'}
        </div>
        <label className="muted small">Nombre de questions</label>
        <input type="number" value={targetTotal} onChange={(e) => setTargetTotal(e.target.value)} />
        <label className="check" style={{ marginTop: 12 }}>
          <input type="checkbox" checked={eco} onChange={(e) => setEco(e.target.checked)} />
          Mode éco quota (free tier Gemini)
        </label>
        <div className="muted small" style={{ marginTop: 4 }}>
          Lots de 50 + vérification Wikipedia seule (0 appel IA en vérif) → ~11
          appels pour 500 questions, dans la limite des 20/jour. Les questions
          arrivent en « à valider » (pas d'auto-vérification IA).
        </div>
        <div className="row actions" style={{ marginTop: 12 }}>
          <span className="spacer" />
          <button className="btn ghost" onClick={onClose}>Annuler</button>
          <button className="btn primary" disabled={busy || !idValid || !topic.trim()} onClick={submit}>
            {busy ? 'Création…' : 'Créer'}
          </button>
        </div>
      </div>
    </div>
  );
}

/** Transforme un texte libre en identifiant snake_case (^[a-z][a-z0-9_]{1,31}$). */
function slugifyPackId(input) {
  return (input || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // retire les accents
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_') // non-alphanumérique → _
    .replace(/_+/g, '_') // collapse les _ multiples
    .replace(/^[^a-z]+/, '') // doit commencer par une lettre
    .slice(0, 32);
}

function normalizePlan(plan) {
  return {
    subThemes: (plan?.subThemes ?? []).map((t) => ({
      name: t.name ?? '',
      targetCount: t.targetCount ?? 0,
      tags: Array.isArray(t.tags) ? t.tags : [],
    })),
    difficultyDistribution: {
      1: plan?.difficultyDistribution?.['1'] ?? 0,
      2: plan?.difficultyDistribution?.['2'] ?? 0,
      3: plan?.difficultyDistribution?.['3'] ?? 0,
      4: plan?.difficultyDistribution?.['4'] ?? 0,
    },
  };
}

function statusClass(status) {
  if (['published', 'ready', 'plan_approved'].includes(status)) return 'green';
  if (['failed', 'cancelled'].includes(status)) return 'red';
  if (['review', 'plan_review'].includes(status)) return 'orange';
  return '';
}

function verdictClass(verdict) {
  if (verdict === 'pass') return 'green';
  if (verdict === 'fail') return 'red';
  return 'orange';
}
