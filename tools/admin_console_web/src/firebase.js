// Init Firebase (JS SDK modulaire) — même projet/app web que le jeu (kilimandjaro-dev).
// Config publique (clé web app), récupérée via `firebase apps:sdkconfig WEB`.
import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider } from 'firebase/auth';
import {
  initializeFirestore,
  persistentLocalCache,
} from 'firebase/firestore';
import { getFunctions } from 'firebase/functions';

const firebaseConfig = {
  apiKey: 'AIzaSyAbFTn3FiASP2PsjizyWuZfMGs3UBTTz38',
  authDomain: 'kilimandjaro-dev.firebaseapp.com',
  projectId: 'kilimandjaro-dev',
  storageBucket: 'kilimandjaro-dev.firebasestorage.app',
  messagingSenderId: '526025535286',
  appId: '1:526025535286:web:288f90dcaa34f98e1a0d97',
};

export const app = initializeApp(firebaseConfig);

export const auth = getAuth(app);
export const googleProvider = new GoogleAuthProvider();
googleProvider.addScope('email');
googleProvider.addScope('profile');

// Auto-détection du long-polling : Safari/WebKit (ITP) bloque parfois le
// WebChannel streaming de Firestore → le SDK bascule alors automatiquement.
export const db = initializeFirestore(app, {
  localCache: persistentLocalCache(),
  experimentalAutoDetectLongPolling: true,
});

// publishPack et les autres callables admin sont déployées en europe-west1.
export const functions = getFunctions(app, 'europe-west1');
