import { useEffect, useState } from 'react';
import { onAuthStateChanged, signInWithPopup, signOut } from 'firebase/auth';
import { auth, googleProvider } from './firebase.js';
import Moderation from './Moderation.jsx';
import Catalog from './Catalog.jsx';
import PackEditor from './PackEditor.jsx';
import DailyChallenges from './DailyChallenges.jsx';
import Instagram from './Instagram.jsx';
import Players from './Players.jsx';
import PackCreator from './PackCreator.jsx';
import Tournaments from './Tournaments.jsx';

export default function App() {
  const [user, setUser] = useState(undefined); // undefined = chargement
  const [tab, setTab] = useState('moderation');
  const [editingPack, setEditingPack] = useState(null);

  useEffect(() => onAuthStateChanged(auth, setUser), []);

  if (user === undefined) {
    return <div className="center muted">Chargement…</div>;
  }
  if (user === null) {
    return <SignIn />;
  }

  return (
    <div className="app">
      <aside className="rail">
        <div className="logo">K</div>
        <button
          className={tab === 'moderation' ? 'nav active' : 'nav'}
          onClick={() => setTab('moderation')}
        >
          Modération
        </button>
        <button
          className={tab === 'catalog' ? 'nav active' : 'nav'}
          onClick={() => {
            setTab('catalog');
            setEditingPack(null);
          }}
        >
          Catalogue
        </button>
        <button
          className={tab === 'packcreator' ? 'nav active' : 'nav'}
          onClick={() => setTab('packcreator')}
        >
          Pack Creator
        </button>
        <button
          className={tab === 'daily' ? 'nav active' : 'nav'}
          onClick={() => setTab('daily')}
        >
          Du jour
        </button>
        <button
          className={tab === 'players' ? 'nav active' : 'nav'}
          onClick={() => setTab('players')}
        >
          Joueurs
        </button>
        <button
          className={tab === 'tournaments' ? 'nav active' : 'nav'}
          onClick={() => setTab('tournaments')}
        >
          Tournois
        </button>
        <button
          className={tab === 'instagram' ? 'nav active' : 'nav'}
          onClick={() => setTab('instagram')}
        >
          Instagram
        </button>
        <div className="rail-bottom">
          {user.photoURL && <img className="avatar" src={user.photoURL} alt="" />}
          <button className="nav" title={user.email} onClick={() => signOut(auth)}>
            Déconnexion
          </button>
        </div>
      </aside>
      <main className="content">
        {tab === 'moderation' && <Moderation />}
        {tab === 'catalog' &&
          (editingPack ? (
            <PackEditor packId={editingPack} onBack={() => setEditingPack(null)} />
          ) : (
            <Catalog onEdit={setEditingPack} />
          ))}
        {tab === 'packcreator' && <PackCreator />}
        {tab === 'daily' && <DailyChallenges />}
        {tab === 'players' && <Players />}
        {tab === 'tournaments' && <Tournaments />}
        {tab === 'instagram' && <Instagram />}
      </main>
    </div>
  );
}

function SignIn() {
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  async function handleSignIn() {
    setBusy(true);
    setError(null);
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (e) {
      setError(`${e.code || e.name}: ${e.message}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="center">
      <div className="signin">
        <div className="logo big">K</div>
        <h1>Kilimandjaro Admin</h1>
        <p className="muted">Console de modération et de gestion des packs</p>
        <button className="btn primary" disabled={busy} onClick={handleSignIn}>
          {busy ? 'Connexion…' : 'Se connecter avec Google'}
        </button>
        {error && <pre className="error">{error}</pre>}
      </div>
    </div>
  );
}
