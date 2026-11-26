import React, { useEffect, useState } from 'react';
import { adminClient, AdminPrincipal, setAdminToken } from './api/adminClient';
import {
  IconApprovals,
  IconDashboard,
  IconLogs,
  IconLogout,
  IconMenu,
  IconMoon,
  IconPosts,
  IconShield,
  IconSun,
  IconUsers,
  TelefamEmblem,
} from './components/Icons';
import { ApprovalsView } from './pages/ApprovalsView';
import { DashboardView } from './pages/DashboardView';
import { ForcePasswordChangeView } from './pages/ForcePasswordChangeView';
import { LoginView } from './pages/LoginView';
import { LogsView } from './pages/LogsView';
import { PostsView } from './pages/PostsView';
import { TeamView } from './pages/TeamView';
import { UsersView } from './pages/UsersView';

type NavTab = 'dashboard' | 'users' | 'posts' | 'approvals' | 'staff' | 'logs';

export const App: React.FC = () => {
  const [principal, setPrincipal] = useState<AdminPrincipal | null>(null);
  const [tempPasswordBuffer, setTempPasswordBuffer] = useState<string>('');
  const [activeTab, setActiveTab] = useState<NavTab>('dashboard');
  const [theme, setTheme] = useState<'dark' | 'light'>('dark');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingCount, setPendingCount] = useState(0);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
  }, [theme]);

  const refreshPending = async () => {
    if (!principal || principal.must_change_password) return;
    try {
      const dash = await adminClient.dashboard();
      setPendingCount(dash.pending_approvals);
    } catch {
      // ignore background poll errors
    }
  };

  useEffect(() => {
    void refreshPending();
  }, [principal, activeTab]);

  const handleLogout = async () => {
    try {
      await adminClient.logout();
    } catch {
      // clear in-memory session regardless
    }
    setAdminToken(null);
    setTempPasswordBuffer('');
    setPrincipal(null);
    setActiveTab('dashboard');
  };

  if (!principal) {
    return (
      <LoginView
        onAuthenticated={(adm, rawTemp) => {
          setPrincipal(adm);
          setTempPasswordBuffer(rawTemp ?? '');
        }}
      />
    );
  }

  if (principal.must_change_password) {
    return (
      <ForcePasswordChangeView
        email={principal.email}
        initialTempPassword={tempPasswordBuffer}
        onPasswordSaved={() => {
          setTempPasswordBuffer('');
          setPrincipal((prev) => (prev ? { ...prev, must_change_password: false } : null));
        }}
        onLogout={handleLogout}
      />
    );
  }

  const isSuper = principal.role === 'super_admin';
  const canViewUsers = isSuper || principal.granted_permissions.includes('view_users');
  const canViewPosts = isSuper || principal.granted_permissions.includes('view_posts');
  const canViewLogs = isSuper || principal.granted_permissions.includes('view_logs');

  const navItems: { id: NavTab; label: string; icon: React.ReactNode; visible: boolean; count?: number }[] = [
    { id: 'dashboard', label: 'Dashboard', icon: <IconDashboard />, visible: true },
    { id: 'users', label: 'Users', icon: <IconUsers />, visible: canViewUsers },
    { id: 'posts', label: 'Posts', icon: <IconPosts />, visible: canViewPosts },
    { id: 'approvals', label: 'Approvals', icon: <IconApprovals />, visible: true, count: pendingCount || undefined },
    { id: 'staff', label: 'Staff & Roles', icon: <IconShield />, visible: isSuper },
    { id: 'logs', label: 'Activity Logs', icon: <IconLogs />, visible: canViewLogs },
  ];

  const currentTitle = navItems.find((n) => n.id === activeTab)?.label ?? 'Dashboard';

  return (
    <div className="app-shell">
      <div
        className={`sidebar-backdrop ${drawerOpen ? 'open' : ''}`}
        onClick={() => setDrawerOpen(false)}
      />

      <aside className={`sidebar ${drawerOpen ? 'open' : ''}`}>
        <div className="sidebar-brand">
          <TelefamEmblem size={38} />
          <div>
            <strong>Telefam</strong>
            <span>Admin Console</span>
          </div>
        </div>

        <nav className="nav-list" aria-label="Admin sections">
          {navItems
            .filter((item) => item.visible)
            .map((item) => (
              <button
                key={item.id}
                type="button"
                className={`nav-item ${activeTab === item.id ? 'active' : ''}`}
                onClick={() => {
                  setActiveTab(item.id);
                  setDrawerOpen(false);
                }}
              >
                <span className="nav-item-left">
                  {item.icon}
                  <span>{item.label}</span>
                </span>
                {item.count ? <span className="nav-count">{item.count}</span> : null}
              </button>
            ))}
        </nav>

        <button type="button" className="nav-item" onClick={handleLogout}>
          <span className="nav-item-left">
            <IconLogout />
            <span>Sign Out</span>
          </span>
        </button>
      </aside>

      <div className="main-area">
        <header className="topbar">
          <div className="topbar-left">
            <button
              type="button"
              className="btn btn-secondary btn-sm menu-btn"
              onClick={() => setDrawerOpen((prev) => !prev)}
              aria-label="Toggle navigation menu"
            >
              <IconMenu />
            </button>
            <h1 className="topbar-title">{currentTitle}</h1>
          </div>

          <div className="topbar-right">
            <span className="topbar-email" style={{ fontSize: '0.84rem', color: 'var(--text-secondary)' }}>
              {principal.email}
            </span>
            <span className="role-pill">{principal.role.replace('_', ' ')}</span>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() => setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'))}
              aria-label="Toggle color theme"
            >
              {theme === 'dark' ? <IconSun /> : <IconMoon />}
            </button>
          </div>
        </header>

        <main className="page-content">
          {activeTab === 'dashboard' && <DashboardView />}
          {activeTab === 'users' && <UsersView principal={principal} />}
          {activeTab === 'posts' && <PostsView principal={principal} />}
          {activeTab === 'approvals' && <ApprovalsView principal={principal} onChanged={refreshPending} />}
          {activeTab === 'staff' && isSuper && <TeamView principal={principal} />}
          {activeTab === 'logs' && canViewLogs && <LogsView />}
        </main>
      </div>
    </div>
  );
};
