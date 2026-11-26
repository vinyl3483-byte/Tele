# Security Summary

**Reviewed Files**: 22
**Issues Resolved**: 10

### Issues Resolved
| Area | File | Line | What Was Happening | Impact | Status | How It Was Fixed |
|---|---|---|---|---|---|---|
| Cross-Tenant Group Membership | `backend/sql/001_schema_and_rls.sql` | 237 | The `conversation_members` insert policy allowed an authenticated user to add members to conversations they did not create. | High | Fixed | Restricted `members_insert` so only the conversation creator (`conversations.created_by = telefam_current_user_id()`) can insert members. |
| Media & Hashtag RLS Scope | `backend/sql/002_posts_media_admin_rls.sql` | 164 | Direct writes to `hashtags` or attachment of unowned `post_media` rows to another user's post were overly permissive under user sessions. | High | Fixed | Split `post_media` policies to require post ownership on update/attach and moved hashtag counter updates behind a security-definer function `telefam_bump_hashtag`. |
| Unauthenticated Media Fetch (SSRF) | `backend/go-gateway/internal/media/video_pipeline.go` | 576 | Downloading song previews accepted URLs without blocking DNS-rebound private networks or HTTP redirects at socket dial time. | High | Fixed | Added `isBlockedIP` (loopback, private, link-local, CGNAT), `net.Dialer.Control` socket-level IP verification, strict HTTPS host allowlisting, redirect rejection, and a 5 MB download cap. |
| Proxy IP Spoofing in Rate Limits & Lockouts | `backend/go-gateway/internal/security/fingerprint.go` | 88 | Trusting unverified forwarded IP headers allowed callers to spoof arbitrary `X-Forwarded-For` values to evade IP lockouts and rate limits. | High | Fixed | Added `ExtractClientIPTrusted` to accept `X-Forwarded-For` only from configured `TELEFAM_TRUSTED_PROXIES` CIDRs scanned right-to-left, falling back to `r.RemoteAddr`. |
| Weak Production Secret Fallbacks | `backend/go-gateway/internal/config/config.go` | 55 | Missing, short, or placeholder JWT secrets, master keys, HMAC peppers, and OAuth client IDs could start up in production or weaken signatures. | High | Fixed | Required validated non-placeholder secrets (`TELEFAM_JWT_SECRET`, 64-hex `TELEFAM_MASTER_KEY_HEX`, `TELEFAM_HMAC_PEPPER`, `GOOGLE_CLIENT_ID`, `APPLE_BUNDLE_ID`) when `APP_ENV=production`. |
| Unbounded CORS & Missing Browser Headers | `backend/go-gateway/internal/middleware/sanitize.go` | 31 | Broad cross-origin handling and missing defensive headers weakened admin browser isolation and error scrubbing. | Medium | Fixed | Added `TELEFAM_ADMIN_ALLOWED_ORIGINS` origin allowlist enforcement, strict `Content-Security-Policy`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `HSTS`, and sanitized error messages. |
| Admin Brute Force & Unapproved Account Deletion | `backend/go-gateway/internal/admin/service.go` | 290 | Admin endpoints needed durable brute-force lockouts across accounts/IPs, mandatory temporary password rotation, activity pause controls, and approval gating for destructive actions. | High | Fixed | Implemented persisted 3-failed-attempt 12-minute lockouts (`423 Locked`), scrypt password hashing, mandatory password rotation on temporary accounts, session-revoking pauses, and a Super Admin approval queue (`admin_action_requests`) for user deletion. |
| Admin Browser Token Exposure | `admin-panel/src/api/adminClient.ts` | 100 | Storing admin bearer tokens in browser storage (`localStorage`/`sessionStorage`) or calling non-HTTPS remote URLs increases session theft risk. | Medium | Fixed | Kept `memoryAdminToken` strictly in JavaScript memory with explicit logout revocation and rejected non-HTTPS remote `VITE_TELEFAM_API_BASE` URLs. |
| Unsalted Desktop Vault Key Derivation | `desktop/src/TelefamDesktopController.cpp` | 60 | Deriving the local encrypted C++ vault key using HKDF without a per-install random salt reduced key entropy across identical machine profiles. | Medium | Fixed | Generated and persisted a 32-byte cryptographic `.vault_salt` (`0600` owner-only permissions) mixed into `hkdf_sha256` vault key derivation. |
| Cleartext Remote Transport Across Clients | `app/src/main/java/com/telefam/company/app/network/TelefamApi.kt` | 535 | Configured API base URLs on Android, iOS, and Desktop lacked uniform runtime checks blocking non-HTTPS remote hosts. | Medium | Fixed | Enforced `https://` across `TelefamApi.kt` (`resolvedBaseUrl`), `TelefamAPIClient.swift` (`isAllowedBaseURL`), and `TelefamDesktopController.cpp`, permitting `http://` only for local loopback development. |

### Safeguards Verified
| Area | File | How It's Protected |
|---|---|---|
| Database Role & RLS Isolation | `backend/sql/003_admin_rbac_approvals_security.sql` | All sensitive user, media, rate-limit, and admin tables use `ENABLE` + `FORCE ROW LEVEL SECURITY`, while `telefam_app_role` explicitly carries `NOSUPERUSER NOBYPASSRLS`. |
| Password Hashing & Validation | `backend/go-gateway/internal/admin/service.go` | Admin and moderator passwords are hashed and verified with per-password salted scrypt and require strong length and complexity before activation. |
| Admin Role & Approval Boundaries | `backend/go-gateway/internal/admin/service.go` | Role checks enforce least privilege on every endpoint; deleting users immediately is restricted to `super_admin`, while admins and moderators enqueue `admin_action_requests`. |
| Session Refresh & Revocation | `ios/Telefam/ViewModels/TelefamViewModel.swift` | Android, iOS, Desktop, and Admin Web clients rotate expired tokens through `/v1/auth/refresh` and clear plus revoke backend sessions via `/v1/auth/logout` or `/v1/admin/logout` on sign-out. |
| Sanitized Error Responses | `backend/go-gateway/internal/middleware/sanitize.go` | Internal database, SQL, and media processing failures are logged server-side and returned to clients only as generic sanitized messages (`Error has occurred, try again later.`). |

## PoC Verification

### Cross-Tenant Conversation Member Injection

#### Summary
| Field | Value |
|---|---|
| Issue Type | Missing Row-Level Ownership Check on Insert |
| Impact | High |
| Affected File | `backend/sql/001_schema_and_rls.sql:237` |
| Test Scenario | Authenticated user B attempts `INSERT INTO conversation_members (conversation_id, user_id)` targeting a conversation created by user A. |

#### How It Was Fixed
Updated the `members_insert` PostgreSQL row-level security policy to verify that `conversations.created_by` equals `telefam_current_user_id()` inside the target row check rather than allowing arbitrary authenticated inserts.

#### Step-by-Step Trace
| Step | What Happens in the Code | Outcome |
|---|---|---|
| 1 | Session B executes `SET LOCAL app.user_id = '<userB_uuid>'` and issues `INSERT INTO conversation_members` for user A's `conversation_id`. | Query reaches PostgreSQL RLS check |
| 2 | PostgreSQL evaluates `members_insert` at `backend/sql/001_schema_and_rls.sql:237-244` (`EXISTS (SELECT 1 FROM conversations c WHERE c.id = conversation_members.conversation_id AND c.created_by = telefam_current_user_id())`). | `c.created_by` (`userA`) != `telefam_current_user_id()` (`userB`) |
| 3 | PostgreSQL aborts the statement with a row-level security violation under `FORCE ROW LEVEL SECURITY`. | **Handled Safely** |

#### Conclusion
**Fix Verified** - Only the creator of a conversation can insert members into `conversation_members`, preventing unauthorized joins into private chats.

---

### SSRF & DNS Rebinding in Music Preview Fetch

#### Summary
| Field | Value |
|---|---|
| Issue Type | Server-Side Request Forgery / DNS Rebinding |
| Impact | High |
| Affected File | `backend/go-gateway/internal/media/video_pipeline.go:576` |
| Test Scenario | Attacker submits `https://evil.dzcdn.net.example/preview.mp3` or `http://169.254.169.254/latest/meta-data/` or a redirect to loopback `http://127.0.0.1:8080/internal`. |

#### How It Was Fixed
Enforced strict `https` scheme and suffix matching against approved audio CDNs, blocked redirects in `http.Client.CheckRedirect`, and added `net.Dialer.Control` socket-time IP validation via `isBlockedIP` to reject private, loopback, link-local, and CGNAT ranges even after DNS resolution.

#### Step-by-Step Trace
| Step | What Happens in the Code | Outcome |
|---|---|---|
| 1 | Untrusted `song_preview_url` enters `downloadAllowlistedSongPreview` at `backend/go-gateway/internal/media/video_pipeline.go:576`. | Parsed URL evaluated |
| 2 | Scheme/user/host check at `video_pipeline.go:578-588` rejects non-`https`, userinfo URLs, and non-allowlisted hosts (`169.254.169.254`, `evil.dzcdn.net.example`). | Non-allowlisted input rejected immediately |
| 3 | For any allowlisted host whose DNS resolves to an internal IP, `dialer.Control` at `video_pipeline.go:595-605` inspects the resolved peer IP with `isBlockedIP` before TCP connection completion and aborts on private/link-local/loopback/CGNAT addresses, while `CheckRedirect` (`video_pipeline.go:617-619`) blocks HTTP 3xx hops. | **Handled Safely** |

#### Conclusion
**Fix Verified** - Outbound media preview requests cannot reach internal metadata services or private network hosts via URL manipulation, DNS rebinding, or HTTP redirects.

---

### Spoofed `X-Forwarded-For` Bypass on Rate Limits & Admin Lockouts

#### Summary
| Field | Value |
|---|---|
| Issue Type | Rate Limit & Lockout Bypass via Header Spoofing |
| Impact | High |
| Affected File | `backend/go-gateway/internal/security/fingerprint.go:88` |
| Test Scenario | Client sends `POST /v1/admin/login` with rotating spoofed headers `X-Forwarded-For: 203.0.113.10, 198.51.100.77` directly to the gateway socket (`r.RemoteAddr = 192.0.2.5:41200`). |

#### How It Was Fixed
Replaced blind forwarded-header trust with `ExtractClientIPTrusted`, which only inspects `X-Forwarded-For` when the direct TCP peer IP belongs to `TELEFAM_TRUSTED_PROXIES` and walks hops right-to-left to stop at the first untrusted address; additionally, admin lockouts enforce counters simultaneously on both normalized email hash and IP fingerprint.

#### Step-by-Step Trace
| Step | What Happens in the Code | Outcome |
|---|---|---|
| 1 | Login request reaches `ExtractClientIPTrusted(r, cfg.TrustedProxies)` (`fingerprint.go:88`). | Immediate peer IP `192.0.2.5` extracted from `r.RemoteAddr` |
| 2 | `isTrustedProxy` checks `192.0.2.5` against `TELEFAM_TRUSTED_PROXIES` (`fingerprint.go:98`); if untrusted, spoofed `X-Forwarded-For` is ignored and `192.0.2.5` is returned (`fingerprint.go:112`). Even behind a trusted proxy, right-to-left traversal (`fingerprint.go:101-109`) ignores client-prepended leftmost spoofed IPs. | Genuine client IP fingerprint computed |
| 3 | On 3rd failed login, `admin/service.go:431-466` persists a 12-minute lock on both `email:<hash>` and `ip:<ipFP>` in `admin_login_lockouts`, returning `423 Locked` at `admin/service.go:311-321`. | **Handled Safely** |

#### Conclusion
**Fix Verified** - Rotating spoofed `X-Forwarded-For` headers neither resets IP-based rate limits nor bypasses the 3-strike 12-minute admin login lockout.

---

### Admin Session Hijack & Unauthorized Destructive Actions

#### Summary
| Field | Value |
|---|---|
| Issue Type | Privileged Action Escalation & Persisted Web Token Exposure |
| Impact | High |
| Affected File | `backend/go-gateway/internal/admin/service.go:818` |
| Test Scenario | A moderator or standard admin calls `DELETE /v1/admin/users/{id}`, or a paused staff account tries to reuse an active bearer token, or an admin attempts login using an unrotated temporary password. |

#### How It Was Fixed
Restricted immediate user deletion exclusively to `super_admin` while routing `admin`/`moderator` requests through `admin_action_requests`; enforced `is_paused = FALSE` inside `AuthenticateAdmin` queries; forced temporary password rotation via `must_change_password` before dashboard access; stored web admin bearer tokens strictly in memory (`adminClient.ts:116`) protected by allowlisted CORS headers.

#### Step-by-Step Trace
| Step | What Happens in the Code | Outcome |
|---|---|---|
| 1 | Admin or moderator calls `DELETE /v1/admin/users/{id}` with a valid bearer token. | `AuthenticateAdmin` (`admin/service.go:498-524`) verifies active non-paused session |
| 2 | `DeleteUserOrRequest` checks `actor.Role == "super_admin"` (`admin/service.go:819`). Non-super-admins branch to `admin/service.go:837-876`, inserting a `pending` row in `admin_action_requests` without touching `users`. | Direct user deletion blocked (`202 Accepted` queued) |
| 3 | Only a `super_admin` invoking `DecideApproval` (`admin/service.go:948-996`) can approve and execute the deletion transactionally with an immutable audit entry. | **Handled Safely** |

#### Conclusion
**Fix Verified** - Paused accounts lose API access immediately, web tokens are never written to browser storage, and destructive user deletions require Super Admin execution or explicit approval.

---

### Unsalted Local Vault Key & Cleartext Remote Transport

#### Summary
| Field | Value |
|---|---|
| Issue Type | Weak Key Derivation Salt & Cleartext Network Configuration |
| Impact | Medium |
| Affected File | `desktop/src/TelefamDesktopController.cpp:45` |
| Test Scenario | Build configuration injects `http://attacker-proxy.example.com` into client API base settings, or Desktop initializes the local encrypted C++ vault on a new installation. |

#### How It Was Fixed
Rejected remote `http://` endpoints in favor of `https://` across Android (`TelefamApi.kt:535`), iOS (`TelefamAPIClient.swift:252-259`), Desktop (`TelefamDesktopController.cpp:45-51`), and Admin Web (`adminClient.ts:105-109`), and replaced the empty Desktop HKDF salt with a randomly generated 32-byte per-install `.vault_salt` (`0600`).

#### Step-by-Step Trace
| Step | What Happens in the Code | Outcome |
|---|---|---|
| 1 | Misconfigured or injected `http://attacker-proxy.example.com` is passed to client startup config. | Client base URL validator inspects scheme & host |
| 2 | Because `host` is not loopback (`localhost`/`127.0.0.1`/`10.0.2.2`), `TelefamDesktopController.cpp:45-51`, `TelefamAPIClient.swift:252-270`, and `TelefamApi.kt:530-537` reject cleartext HTTP and fall back to `https://api.telefam.app` (`adminClient.ts:107-109` throws). | Cleartext remote traffic blocked |
| 3 | During Desktop initialization, `TelefamDesktopController.cpp:60-86` generates or reads 32 random bytes from `.vault_salt` (`ReadOwner | WriteOwner`) and derives the AES-GCM vault key via `hkdf_sha256`. | **Handled Safely** |

#### Conclusion
**Fix Verified** - Remote client traffic is pinned to HTTPS and local desktop vault encryption keys derive from a unique per-installation cryptographic salt.
