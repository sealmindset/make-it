# RBAC Management System — Claude Code Reproduction Prompt

Use this prompt to consistently generate the full RBAC management system in any FastAPI + Next.js application. Replace `[BRACKET_PLACEHOLDERS]` with app-specific values.

---

## The Prompt

```
Build a complete RBAC (Role-Based Access Control) management system across backend and frontend. This is the EXACT architecture to implement — do not deviate.

## DATABASE SCHEMA (Alembic migration)

Create 4 tables in a single Alembic migration:

### Table: roles
- id: UUID primary key (server_default=gen_random_uuid() or uuid4)
- name: String(100), unique, not null
- description: Text, nullable
- is_system: Boolean, default=false (system roles cannot be deleted via API)
- created_at: DateTime, server_default=now()
- updated_at: DateTime, server_default=now(), onupdate=now()

### Table: permissions
- id: UUID primary key
- resource: String(100), not null
- action: String(50), not null
- description: String(255), nullable
- created_at: DateTime, server_default=now()
- UNIQUE CONSTRAINT on (resource, action)

### Table: role_permissions (junction)
- role_id: UUID, FK→roles.id ON DELETE CASCADE, primary key
- permission_id: UUID, FK→permissions.id ON DELETE CASCADE, primary key

### Table: users (if not already created)
- id: UUID primary key
- oidc_subject: String(255), unique, not null — the OIDC provider's user identifier
- email: String(255), unique, not null
- display_name: String(255), not null
- is_active: Boolean, default=true
- role_id: UUID, FK→roles.id, not null
- created_at: DateTime, server_default=now()
- updated_at: DateTime, server_default=now(), onupdate=now()

## SQLALCHEMY MODELS

### backend/app/models/role.py
```python
class Role(Base):
    __tablename__ = "roles"
    # All columns from schema above
    # Relationships:
    permissions = relationship("RolePermission", back_populates="role", cascade="all, delete-orphan")
    users = relationship("User", back_populates="role")
```

### backend/app/models/permission.py
Two models in one file:

```python
class Permission(Base):
    __tablename__ = "permissions"
    # All columns from schema above
    role_permissions = relationship("RolePermission", back_populates="permission", cascade="all, delete-orphan")

class RolePermission(Base):
    __tablename__ = "role_permissions"
    role_id = mapped_column(ForeignKey("roles.id", ondelete="CASCADE"), primary_key=True)
    permission_id = mapped_column(ForeignKey("permissions.id", ondelete="CASCADE"), primary_key=True)
    role = relationship("Role", back_populates="permissions")
    permission = relationship("Permission", back_populates="role_permissions")
```

### backend/app/models/user.py
```python
class User(Base):
    __tablename__ = "users"
    # All columns from schema above
    role = relationship("Role", back_populates="users", lazy="selectin")
```

## PYDANTIC SCHEMAS

### backend/app/schemas/auth.py
```python
class UserInfo(BaseModel):
    sub: str          # OIDC subject
    email: str
    name: str
    role_id: str
    role_name: str
    permissions: list[str]  # ["resource.action", ...]
```

### backend/app/schemas/role.py
```python
class PermissionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    resource: str
    action: str
    description: str | None = None

class RoleOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    name: str
    description: str | None = None
    is_system: bool
    created_at: datetime
    updated_at: datetime

class RoleWithPermissions(RoleOut):
    permissions: list[PermissionOut] = []

class RoleCreate(BaseModel):
    name: str
    description: str | None = None

class RoleUpdate(BaseModel):
    name: str | None = None
    description: str | None = None

class PermissionAssignment(BaseModel):
    permission_ids: list[UUID]
```

### backend/app/schemas/user.py
```python
class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    oidc_subject: str
    email: str
    display_name: str
    is_active: bool
    role_id: UUID
    role_name: str | None = None
    created_at: datetime
    updated_at: datetime

class UserCreate(BaseModel):
    oidc_subject: str
    email: str
    display_name: str
    role_id: UUID

class UserUpdate(BaseModel):
    email: str | None = None
    display_name: str | None = None
    is_active: bool | None = None
    role_id: UUID | None = None
```

## PERMISSION MIDDLEWARE

### backend/app/middleware/permissions.py
```python
def require_permission(resource: str, action: str):
    async def _check_permission(
        current_user: UserInfo = Depends(get_current_user),
    ) -> UserInfo:
        required = f"{resource}.{action}"
        if required not in current_user.permissions:
            raise HTTPException(status_code=403, detail=f"Permission denied: {required}")
        return current_user
    return _check_permission
```

This is a FastAPI dependency factory. Returns UserInfo so routes can use the current user.

### backend/app/middleware/auth.py
```python
async def get_current_user(request: Request) -> UserInfo:
    token = request.cookies.get("token")
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
        return UserInfo(**payload)
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except (jwt.InvalidTokenError, Exception):
        raise HTTPException(status_code=401, detail="Invalid token")
```

## AUTH ROUTER — PERMISSION LOADING ON LOGIN

### backend/app/routers/auth.py (callback endpoint)

After OIDC code exchange and userinfo fetch, load permissions into JWT:

```python
# Look up user by oidc_subject (NOT email)
stmt = select(User).where(User.oidc_subject == oidc_subject).options(selectinload(User.role))
result = await db.execute(stmt)
user = result.scalar_one_or_none()

if not user:
    raise HTTPException(status_code=403, detail="User not provisioned. Contact your administrator.")
if not user.is_active:
    raise HTTPException(status_code=403, detail="Account deactivated. Contact your administrator.")

# Load role permissions eagerly
role = user.role
perm_stmt = (
    select(RolePermission)
    .where(RolePermission.role_id == role.id)
    .options(selectinload(RolePermission.permission))
)
perm_result = await db.execute(perm_stmt)
role_perms = perm_result.scalars().all()
permissions = [f"{rp.permission.resource}.{rp.permission.action}" for rp in role_perms]

# Sign JWT with permissions baked in
payload = {
    "sub": user.oidc_subject,
    "email": user.email,
    "name": user.display_name,
    "role_id": str(user.role_id),
    "role_name": role.name,
    "permissions": permissions,
    "exp": datetime.now(timezone.utc) + timedelta(hours=8),
    "iat": datetime.now(timezone.utc),
}
token = jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")
```

Set token as httpOnly cookie (samesite=lax, secure based on FRONTEND_URL protocol). Clear OIDC state cookie. Return HTML meta-refresh redirect to /dashboard (workaround for Next.js 16+ stripping Set-Cookie from 307 redirects).

## BACKEND API ROUTES

### backend/app/routers/roles.py (prefix: /api/roles)

5 endpoints, all protected by require_permission:

1. `GET /` — List all roles. Query param `?include_permissions=true` eagerly loads permissions via selectinload chain: `Role.permissions → RolePermission.permission`. Permission: `admin.roles.read`.

2. `POST /` — Create custom role (is_system=false). Check name uniqueness (409 if exists). Permission: `admin.roles.create`.

3. `PUT /{role_id}` — Update role name/description. Uses `model_dump(exclude_unset=True)` for partial updates. Permission: `admin.roles.update`.

4. `DELETE /{role_id}` — Delete role. Reject system roles with 400. Permission: `admin.roles.delete`.

5. `PUT /{role_id}/permissions` — Replace ALL permissions for a role (permission matrix save). Accepts `PermissionAssignment { permission_ids: [UUID] }`. Deletes all existing role_permissions, inserts new ones, validates each permission_id exists. Reloads role with permissions after save. Permission: `admin.roles.update`.

Helper function `_role_to_out(role, include_permissions)` converts SQLAlchemy model to RoleOut or RoleWithPermissions schema.

### backend/app/routers/permissions.py (prefix: /api/permissions)

1. `GET /` — List all permissions sorted by resource, action. Used by frontend to build the permission matrix. Permission: `admin.roles.read`.

### backend/app/routers/users.py (prefix: /api/users)

6 endpoints:

1. `GET /directory?q=<query>` — Search OIDC directory for users to provision. Queries mock-oidc admin API in dev, real OIDC provider in prod. Permission: `admin.users.create`.

2. `GET /` — List all provisioned users with role_name computed from role relationship. Permission: `admin.users.read`.

3. `POST /` — Provision user from OIDC directory. Accepts `UserCreate { oidc_subject, email, display_name, role_id }`. Permission: `admin.users.create`.

4. `GET /{user_id}` — Get single user. Permission: `admin.users.read`.

5. `PUT /{user_id}` — Update user (change role, deactivate, rename). Uses partial update pattern. Permission: `admin.users.update`.

6. `DELETE /{user_id}` — Delete user. Permission: `admin.users.delete`.

## SEED DATA (Alembic migration)

### System Roles (is_system=true, use deterministic UUIDs for reproducibility)
Seed these [APP_ROLE_COUNT] system roles with descriptions matching app domain:
[LIST_APP_ROLES_HERE]

CRITICAL: Always include an Admin role with ALL permissions.

### Permissions
Generate permissions using `resource × action` cross-product:
- Actions: create, read, update, delete (always these 4)
- Resources: One per admin section (admin.users, admin.roles, admin.settings, admin.logs, admin.prompts) plus one per domain page (dashboard, [DOMAIN_RESOURCES])
- Use deterministic UUID generation (sequential counter) so role_permissions mapping can reference them

### Role-Permission Mapping
Map each role to its specific permissions. Admin gets everything. Other roles get domain-specific subsets.

### Seed Users (one per role, matching mock-oidc users)
Create one test user per role with deterministic UUIDs and oidc_subjects that match mock-oidc seed data.

## FRONTEND — AUTH CONTEXT

### frontend/lib/auth.tsx

AuthProvider wrapping the app:
```typescript
interface AuthContextValue {
  authMe: AuthMe | null;
  loading: boolean;
  hasPermission: (resource: string, action: string) => boolean;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
}
```

- `fetchMe()` calls `GET /api/auth/me`, stores response in state
- `hasPermission(resource, action)` checks `authMe.permissions.includes(\`${resource}.${action}\`)`
- `logout()` calls `POST /api/auth/logout`, clears state, redirects to /
- `refresh()` re-fetches /me (used after role changes)

### frontend/lib/types.ts
```typescript
interface AuthMe {
  sub: string;
  email: string;
  name: string;
  role_id: string;
  role_name: string;
  permissions: string[];
}

interface Role {
  id: string; name: string; description: string;
  is_system: boolean; created_at: string; updated_at: string;
}

interface Permission {
  id: string; resource: string; action: string; description: string | null;
}

interface RoleWithPermissions extends Role {
  permissions: Permission[];
}

interface User {
  id: string; oidc_subject: string; email: string; display_name: string;
  is_active: boolean; role_id: string; role_name: string | null;
  created_at: string; updated_at: string;
}
```

## FRONTEND — ROLES ADMIN PAGE

### frontend/app/(auth)/admin/roles/page.tsx

Single page with 3 sections:

**1. Role Card Grid (2-column on desktop)**
Each card shows:
- Shield icon + role name + "SYSTEM" badge if is_system
- Description
- Permission count + expand/collapse toggle
- Action buttons: Edit (pencil, if canEdit), Delete (trash, if canDelete AND !is_system)
- Expandable inline permission matrix (read-only): resource×action table with disabled checkboxes

Page header: "Roles" title + "Create Role" button (if canCreate)

Permission checks at top of component:
```typescript
const canCreate = hasPermission("admin.roles", "create");
const canEdit = hasPermission("admin.roles", "update");
const canDelete = hasPermission("admin.roles", "delete");
```

Data loading: Parallel fetch `GET /roles?include_permissions=true` + `GET /permissions`

**2. PermissionMatrixModal (edit existing role)**
- Opens when pencil icon clicked
- Full resource×action checkbox grid
- Clicking resource name = toggle all permissions for that resource
- Shows "X of Y permissions selected" counter
- Save calls `PUT /api/roles/{id}/permissions` with selected permission UUIDs
- Warning text for system roles: "This is a system role. Changes will affect all users with this role."

**3. CreateRoleModal**
- Name + description inputs
- Same permission matrix as edit modal
- Submit calls `POST /api/roles` then refreshes role list

Both modals: fixed overlay with bg-black/50, centered card, max-w-3xl, max-h-96 scrollable matrix with sticky thead.

## FRONTEND — USERS ADMIN PAGE

### frontend/app/(auth)/admin/users/page.tsx

Data table with columns: Name, Email, Role, Status, Created, Actions

Features:
- Add User button (if canCreate) opens modal with OIDC directory search
- Directory search: debounced input (300ms) calls `GET /api/users/directory?q=<query>`
- User selects from search results, picks role, submits → `POST /api/users`
- Inline role change: dropdown (if canEdit) → `PUT /api/users/{id}` with new role_id
- Toggle active: button → `PUT /api/users/{id}` with { is_active: !current }
- Delete: button (if canDelete) → `DELETE /api/users/{id}` with confirmation

## CRITICAL IMPLEMENTATION RULES

1. Permission format is ALWAYS `"resource.action"` — stored as 2 columns in DB, concatenated with dot for JWT and frontend checks
2. JWT contains flattened permission strings — no DB lookup on each request
3. `require_permission(resource, action)` on EVERY route handler — never check role names, always check permissions
4. System roles (is_system=true) cannot be deleted via API — return 400
5. User lookup in OIDC callback uses oidc_subject, NOT email
6. User must be pre-provisioned in DB before OIDC login succeeds (no auto-create)
7. Logout is POST to backend API, NOT a GET link
8. Permission matrix save replaces ALL permissions (delete old, insert new) — not incremental
9. Frontend hasPermission() mirrors backend require_permission() — both check "resource.action" format
10. Use selectinload for eager loading relationships (avoid N+1)
11. All modals use fixed overlay positioning with max-height scrollable content
12. Use CSS variables (var(--primary), var(--border), etc.) not hardcoded colors
13. Use oklch color-mix for subtle backgrounds: color-mix(in oklch, var(--primary) 12%, transparent)
14. Deterministic UUIDs in seed data so role_permissions can reference specific roles and permissions
```

---

## Usage

Copy the prompt above into Claude Code. Before running, replace:
- `[APP_ROLE_COUNT]` — number of system roles for your app
- `[LIST_APP_ROLES_HERE]` — your app's role definitions (name, description, permissions)
- `[DOMAIN_RESOURCES]` — your app's domain-specific permission resources

The prompt assumes FastAPI + Next.js + SQLAlchemy async + Alembic + OIDC auth already exist. It builds the RBAC layer on top.
