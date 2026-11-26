export interface AdminPrincipal {
  id: string;
  email: string;
  full_name: string;
  role: 'super_admin' | 'admin' | 'moderator';
  granted_permissions: string[];
  must_change_password: boolean;
  is_paused: boolean;
}

export interface LoginResponse {
  token?: string;
  expires_in?: number;
  must_change_password: boolean;
  admin?: AdminPrincipal;
  locked?: boolean;
  retry_after_seconds?: number;
  error?: string;
}

export interface ActivityLogRecord {
  id: string;
  source: 'admin' | 'user_risk';
  actor_id: string;
  actor_email: string;
  actor_role: string;
  action_type: string;
  target_user_id: string;
  target_post_id: string;
  outcome: string;
  created_at: number;
}

export interface DashboardStats {
  total_users: number;
  total_posts: number;
  total_staff: number;
  paused_staff: number;
  pending_approvals: number;
  active_lockouts: number;
  recent_logs: ActivityLogRecord[];
}

export interface UserRecord {
  user_id: string;
  email: string;
  full_name: string;
  username: string;
  auth_provider: string;
  profile_completed: boolean;
  is_suspended: boolean;
  risk_score: number;
  created_at: number;
}

export interface PostRecord {
  post_id: string;
  author_id: string;
  author_name: string;
  author_handle: string;
  post_type: string;
  body: string;
  media_count: number;
  primary_media_id: string;
  content_fingerprint_hash: string;
  created_at: number;
}

export interface StaffMember {
  id: string;
  email: string;
  full_name: string;
  role: 'super_admin' | 'admin' | 'moderator';
  granted_permissions: string[];
  must_change_password: boolean;
  is_paused: boolean;
  failed_attempts: number;
  locked_until_ms: number;
  last_active_at_ms: number;
  created_at_ms: number;
}

export interface ApprovalRequest {
  id: string;
  requested_by_id: string;
  requested_by_email: string;
  requested_by_role: string;
  action_type: string;
  target_user_id: string;
  target_user_email: string;
  target_post_id: string;
  reason: string;
  status: 'pending' | 'approved' | 'rejected' | 'executed';
  reviewed_by_email: string;
  review_note: string;
  created_at: number;
  reviewed_at: number;
}

function resolveApiBase(): string {
  const configured = (import.meta.env.VITE_TELEFAM_API_BASE as string | undefined)?.trim() || '';
  if (!configured) {
    return '';
  }
  const url = new URL(configured);
  const isLocal = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
  if (!isLocal && url.protocol !== 'https:') {
    throw new Error('Production admin API base must use HTTPS');
  }
  return configured.replace(/\/+$/, '');
}

const API_BASE = resolveApiBase();

// Keep session token strictly in memory — never written to localStorage or sessionStorage.
let memoryAdminToken: string | null = null;

export function setAdminToken(token: string | null) {
  memoryAdminToken = token;
}

export class ApiError extends Error {
  status: number;
  retryAfterSeconds?: number;
  mustChangePassword?: boolean;

  constructor(status: number, message: string, retryAfterSeconds?: number, mustChangePassword?: boolean) {
    super(message);
    this.status = status;
    this.retryAfterSeconds = retryAfterSeconds;
    this.mustChangePassword = mustChangePassword;
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (!headers.has('Content-Type') && init.body) {
    headers.set('Content-Type', 'application/json');
  }
  if (memoryAdminToken) {
    headers.set('Authorization', `Bearer ${memoryAdminToken}`);
  }

  const resp = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers,
    credentials: 'omit',
  });

  const data = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    throw new ApiError(
      resp.status,
      (data as { error?: string }).error || 'Error has occurred, try again later.',
      (data as { retry_after_seconds?: number }).retry_after_seconds,
      (data as { must_change_password?: boolean }).must_change_password,
    );
  }
  return data as T;
}

export const adminClient = {
  bootstrapStatus: () => request<{ initialized: boolean }>('/v1/admin/bootstrap/status'),

  bootstrapSuperAdmin: (email: string, fullName: string, password: string) =>
    request<AdminPrincipal>('/v1/admin/bootstrap', {
      method: 'POST',
      body: JSON.stringify({ email, full_name: fullName, password }),
    }),

  login: (email: string, password: string) =>
    request<LoginResponse>('/v1/admin/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),

  me: () => request<AdminPrincipal>('/v1/admin/auth/me'),

  changePassword: (currentPassword: string, newPassword: string) =>
    request<{ changed: boolean; must_change_password: boolean }>('/v1/admin/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
    }),

  logout: () => request<{ logged_out: boolean }>('/v1/admin/auth/logout', { method: 'POST' }),

  dashboard: () => request<DashboardStats>('/v1/admin/dashboard'),

  listUsers: (q = '') =>
    request<{ users: UserRecord[] }>(`/v1/admin/panel/users?q=${encodeURIComponent(q)}`),

  setUserSuspended: (userId: string, suspended: boolean) =>
    request<{ suspended: boolean }>(`/v1/admin/panel/users/${encodeURIComponent(userId)}/suspend`, {
      method: 'POST',
      body: JSON.stringify({ suspended }),
    }),

  deleteUserOrRequest: (userId: string, reason = '') =>
    request<{ status: string; requires_approval: boolean; request_id?: string }>(
      `/v1/admin/panel/users/${encodeURIComponent(userId)}`,
      {
        method: 'DELETE',
        body: JSON.stringify({ reason }),
      },
    ),

  listPosts: (q = '') =>
    request<{ posts: PostRecord[] }>(`/v1/admin/panel/posts?q=${encodeURIComponent(q)}`),

  removePost: (postId: string) =>
    request<{ removed: boolean }>(`/v1/admin/panel/posts/${encodeURIComponent(postId)}`, {
      method: 'DELETE',
    }),

  listApprovals: () => request<{ approvals: ApprovalRequest[] }>('/v1/admin/panel/approvals'),

  decideApproval: (requestId: string, approve: boolean, note = '') =>
    request<{ decided: boolean; approved: boolean }>(
      `/v1/admin/panel/approvals/${encodeURIComponent(requestId)}/decide`,
      {
        method: 'POST',
        body: JSON.stringify({ approve, note }),
      },
    ),

  listStaff: () => request<{ staff: StaffMember[] }>('/v1/admin/panel/staff'),

  createStaff: (payload: {
    email: string;
    full_name: string;
    role: 'super_admin' | 'admin' | 'moderator';
    password: string;
    is_temporary: boolean;
    permissions: string[];
  }) =>
    request<StaffMember>('/v1/admin/panel/staff', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  updateStaffRole: (staffId: string, role: string, permissions: string[]) =>
    request<{ updated: boolean }>(`/v1/admin/panel/staff/${encodeURIComponent(staffId)}/role`, {
      method: 'PATCH',
      body: JSON.stringify({ role, permissions }),
    }),

  setStaffPaused: (staffId: string, paused: boolean) =>
    request<{ paused: boolean }>(`/v1/admin/panel/staff/${encodeURIComponent(staffId)}/pause`, {
      method: 'POST',
      body: JSON.stringify({ paused }),
    }),

  removeStaff: (staffId: string) =>
    request<{ removed: boolean }>(`/v1/admin/panel/staff/${encodeURIComponent(staffId)}`, {
      method: 'DELETE',
    }),

  listLogs: (limit = 150) =>
    request<{ logs: ActivityLogRecord[] }>(`/v1/admin/panel/logs?limit=${limit}`),
};
