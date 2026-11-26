import React, { useEffect, useState } from 'react';
import { adminClient, AdminPrincipal, ApiError, setAdminToken } from '../api/adminClient';
import { IconLock, TelefamEmblem } from '../components/Icons';

interface Props {
  onAuthenticated: (principal: AdminPrincipal, rawTempPassword?: string) => void;
}

function formatCountdown(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

export const LoginView: React.FC<Props> = ({ onAuthenticated }) => {
  const [initialized, setInitialized] = useState<boolean | null>(null);
  const [email, setEmail] = useState('');
  const [fullName, setFullName] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [lockSeconds, setLockSeconds] = useState(0);

  useEffect(() => {
    let active = true;
    adminClient
      .bootstrapStatus()
      .then((res) => {
        if (active) setInitialized(res.initialized);
      })
      .catch(() => {
        if (active) setInitialized(true);
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (lockSeconds <= 0) return;
    const timer = window.setInterval(() => {
      setLockSeconds((prev) => (prev <= 1 ? 0 : prev - 1));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [lockSeconds]);

  const handleBootstrap = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');
    if (password !== confirmPassword) {
      setErrorMsg('Passwords do not match.');
      return;
    }
    setLoading(true);
    try {
      await adminClient.bootstrapSuperAdmin(email, fullName, password);
      const loginRes = await adminClient.login(email, password);
      if (loginRes.token && loginRes.admin) {
        setAdminToken(loginRes.token);
        onAuthenticated(loginRes.admin);
      }
    } catch (err) {
      setErrorMsg(err instanceof ApiError ? err.message : 'Unable to initialize account.');
    } finally {
      setLoading(false);
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (lockSeconds > 0) return;
    setErrorMsg('');
    setLoading(true);
    try {
      const res = await adminClient.login(email, password);
      if (res.token && res.admin) {
        setAdminToken(res.token);
        onAuthenticated(
          { ...res.admin, must_change_password: res.must_change_password },
          res.must_change_password ? password : undefined,
        );
      } else {
        setErrorMsg(res.error || 'Invalid email or password.');
      }
    } catch (err) {
      if (err instanceof ApiError && err.status === 423) {
        setLockSeconds(err.retryAfterSeconds ?? 720);
        setErrorMsg(err.message);
      } else {
        setErrorMsg(err instanceof ApiError ? err.message : 'Invalid email or password.');
      }
    } finally {
      setLoading(false);
    }
  };

  if (initialized === null) {
    return (
      <div className="auth-shell">
        <div className="auth-card">
          <div className="brand-header">
            <TelefamEmblem size={56} />
            <h1>Telefam Admin</h1>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <div className="auth-card">
        <div className="brand-header">
          <TelefamEmblem size={56} />
          <h1>{initialized ? 'Telefam Admin' : 'Super Admin Setup'}</h1>
          <p>{initialized ? 'Sign in with email and password' : 'Create the primary Super Admin account'}</p>
        </div>

        {lockSeconds > 0 && (
          <div className="alert alert-danger" role="alert">
            <IconLock size={18} />
            <span>
              Too many failed attempts. Locked for {formatCountdown(lockSeconds)}.
            </span>
          </div>
        )}

        {errorMsg && lockSeconds === 0 && (
          <div className="alert alert-danger" role="alert">
            <span>{errorMsg}</span>
          </div>
        )}

        {!initialized ? (
          <form onSubmit={handleBootstrap}>
            <div className="field">
              <label htmlFor="setup-name">Full Name</label>
              <input
                id="setup-name"
                className="input"
                type="text"
                required
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Super Admin"
              />
            </div>
            <div className="field">
              <label htmlFor="setup-email">Email</label>
              <input
                id="setup-email"
                className="input"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="admin@telefam.app"
              />
            </div>
            <div className="field">
              <label htmlFor="setup-password">Password (10+ chars, upper, lower, number/symbol)</label>
              <input
                id="setup-password"
                className="input"
                type="password"
                required
                minLength={10}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>
            <div className="field">
              <label htmlFor="setup-confirm">Confirm Password</label>
              <input
                id="setup-confirm"
                className="input"
                type="password"
                required
                minLength={10}
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
              />
            </div>
            <button type="submit" className="btn btn-primary btn-full" disabled={loading}>
              {loading ? 'Creating...' : 'Create Super Admin'}
            </button>
          </form>
        ) : (
          <form onSubmit={handleLogin}>
            <div className="field">
              <label htmlFor="login-email">Email</label>
              <input
                id="login-email"
                className="input"
                type="email"
                autoComplete="username"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="Enter your email"
              />
            </div>
            <div className="field">
              <label htmlFor="login-password">Password or Temporary Password</label>
              <input
                id="login-password"
                className="input"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Enter password"
              />
            </div>
            <button
              type="submit"
              className="btn btn-primary btn-full"
              disabled={loading || lockSeconds > 0}
            >
              {lockSeconds > 0 ? `Locked (${formatCountdown(lockSeconds)})` : loading ? 'Signing in...' : 'Sign In'}
            </button>
          </form>
        )}
      </div>
    </div>
  );
};
