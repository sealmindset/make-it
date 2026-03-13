"use client";

import { useEffect, useState, useCallback } from "react";
import { apiGet, apiPost, apiPut, apiDelete } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatDate } from "@/lib/utils";
import type { RoleWithPermissions, Permission } from "@/lib/types";
import { Shield, Plus, Pencil, Trash2, ChevronDown, ChevronUp } from "lucide-react";

export default function RolesPage() {
  const { hasPermission } = useAuth();
  const [roles, setRoles] = useState<RoleWithPermissions[]>([]);
  const [allPermissions, setAllPermissions] = useState<Permission[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedRoleId, setExpandedRoleId] = useState<string | null>(null);
  const [editingRole, setEditingRole] = useState<RoleWithPermissions | null>(
    null,
  );
  const [showCreateModal, setShowCreateModal] = useState(false);

  const canCreate = hasPermission("roles", "create");
  const canEdit = hasPermission("roles", "edit");
  const canDelete = hasPermission("roles", "delete");

  const fetchRoles = useCallback(async () => {
    try {
      const [rolesData, permsData] = await Promise.all([
        apiGet<RoleWithPermissions[]>("/roles?include_permissions=true"),
        apiGet<Permission[]>("/permissions"),
      ]);
      setRoles(rolesData);
      setAllPermissions(permsData);
    } catch (err) {
      console.error("Failed to load roles:", err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchRoles();
  }, [fetchRoles]);

  const handleDeleteRole = async (roleId: string) => {
    if (!confirm("Are you sure you want to delete this role?")) return;
    try {
      await apiDelete(`/roles/${roleId}`);
      fetchRoles();
    } catch (err) {
      console.error("Failed to delete role:", err);
    }
  };

  // Group all permissions by resource for the inline matrix
  const grouped = allPermissions.reduce(
    (acc, perm) => {
      if (!acc[perm.resource]) acc[perm.resource] = [];
      acc[perm.resource].push(perm);
      return acc;
    },
    {} as Record<string, Permission[]>,
  );
  const resources = Object.keys(grouped).sort();
  const actions = [...new Set(allPermissions.map((p) => p.action))].sort();

  if (loading) {
    return (
      <div className="space-y-4">
        <div
          className="h-8 w-48 animate-pulse rounded"
          style={{ backgroundColor: "var(--muted)" }}
        />
        <div className="grid gap-4 sm:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="h-32 animate-pulse rounded-xl border"
              style={{
                backgroundColor: "var(--card)",
                borderColor: "var(--border)",
              }}
            />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Roles</h1>
          <p style={{ color: "var(--muted-foreground)" }}>
            Manage roles and their permission assignments.
          </p>
        </div>
        {canCreate && (
          <button
            onClick={() => setShowCreateModal(true)}
            className="inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-medium shadow-sm transition-colors"
            style={{
              backgroundColor: "var(--primary)",
              color: "var(--primary-foreground)",
            }}
          >
            <Plus className="h-4 w-4" />
            Create Role
          </button>
        )}
      </div>

      {/* Roles card grid */}
      <div className="grid gap-4 sm:grid-cols-2">
        {roles.map((role) => {
          const isExpanded = expandedRoleId === role.id;
          const rolePermIds = new Set(role.permissions.map((p) => p.id));

          return (
            <div
              key={role.id}
              className="rounded-xl border"
              style={{
                backgroundColor: "var(--card)",
                borderColor: "var(--border)",
                color: "var(--card-foreground)",
              }}
            >
              {/* Role card header */}
              <div className="flex items-start justify-between p-5">
                <div className="flex items-center gap-3">
                  <div
                    className="flex h-10 w-10 items-center justify-center rounded-lg"
                    style={{
                      backgroundColor:
                        "color-mix(in oklch, var(--primary) 12%, transparent)",
                      color: "var(--primary)",
                    }}
                  >
                    <Shield className="h-5 w-5" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="font-semibold">{role.name}</h3>
                      {role.is_system && (
                        <span
                          className="rounded px-1.5 py-0.5 text-[10px] font-medium"
                          style={{
                            backgroundColor: "var(--muted)",
                            color: "var(--muted-foreground)",
                          }}
                        >
                          SYSTEM
                        </span>
                      )}
                    </div>
                    <p
                      className="mt-0.5 text-sm"
                      style={{ color: "var(--muted-foreground)" }}
                    >
                      {role.description || "No description"}
                    </p>
                  </div>
                </div>

                {/* Actions */}
                <div className="flex items-center gap-1">
                  {canEdit && (
                    <button
                      onClick={() => setEditingRole(role)}
                      className="rounded p-1.5 transition-colors"
                      style={{ color: "var(--muted-foreground)" }}
                      title="Edit permissions"
                    >
                      <Pencil className="h-4 w-4" />
                    </button>
                  )}
                  {canDelete && !role.is_system && (
                    <button
                      onClick={() => handleDeleteRole(role.id)}
                      className="rounded p-1.5 transition-colors"
                      style={{ color: "var(--muted-foreground)" }}
                      title="Delete role"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  )}
                </div>
              </div>

              {/* Permission count + expand toggle */}
              <div
                className="flex items-center justify-between border-t px-5 py-3"
                style={{ borderColor: "var(--border)" }}
              >
                <span
                  className="text-sm"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  {role.permissions.length} permission
                  {role.permissions.length !== 1 ? "s" : ""}
                </span>
                <button
                  onClick={() =>
                    setExpandedRoleId(isExpanded ? null : role.id)
                  }
                  className="inline-flex items-center gap-1 rounded px-2 py-1 text-xs transition-colors"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  {isExpanded ? (
                    <>
                      Hide <ChevronUp className="h-3 w-3" />
                    </>
                  ) : (
                    <>
                      View <ChevronDown className="h-3 w-3" />
                    </>
                  )}
                </button>
              </div>

              {/* Inline permission matrix (read-only) */}
              {isExpanded && (
                <div
                  className="border-t px-5 pb-5 pt-3"
                  style={{ borderColor: "var(--border)" }}
                >
                  <div className="overflow-auto rounded-md border" style={{ borderColor: "var(--border)" }}>
                    <table className="w-full text-xs">
                      <thead>
                        <tr
                          className="border-b"
                          style={{ borderColor: "var(--border)" }}
                        >
                          <th
                            className="px-2 py-1.5 text-left font-medium"
                            style={{ color: "var(--muted-foreground)" }}
                          >
                            Resource
                          </th>
                          {actions.map((action) => (
                            <th
                              key={action}
                              className="px-2 py-1.5 text-center font-medium capitalize"
                              style={{ color: "var(--muted-foreground)" }}
                            >
                              {action}
                            </th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {resources.map((resource) => (
                          <tr
                            key={resource}
                            className="border-b last:border-b-0"
                            style={{ borderColor: "var(--border)" }}
                          >
                            <td className="px-2 py-1.5 font-medium capitalize">
                              {resource}
                            </td>
                            {actions.map((action) => {
                              const perm = grouped[resource]?.find(
                                (p) => p.action === action,
                              );
                              if (!perm) {
                                return (
                                  <td
                                    key={action}
                                    className="px-2 py-1.5 text-center"
                                    style={{
                                      color:
                                        "color-mix(in oklch, var(--muted-foreground) 30%, transparent)",
                                    }}
                                  >
                                    -
                                  </td>
                                );
                              }
                              return (
                                <td
                                  key={action}
                                  className="px-2 py-1.5 text-center"
                                >
                                  <input
                                    type="checkbox"
                                    checked={rolePermIds.has(perm.id)}
                                    disabled
                                    className="rounded"
                                    style={{ borderColor: "var(--border)" }}
                                  />
                                </td>
                              );
                            })}
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}

              {/* Created date */}
              <div
                className="border-t px-5 py-2"
                style={{ borderColor: "var(--border)" }}
              >
                <span
                  className="text-xs"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  Created {formatDate(role.created_at)}
                </span>
              </div>
            </div>
          );
        })}
      </div>

      {/* Permission matrix editor modal */}
      {editingRole && (
        <PermissionMatrixModal
          role={editingRole}
          allPermissions={allPermissions}
          onClose={() => setEditingRole(null)}
          onSaved={fetchRoles}
        />
      )}

      {/* Create role modal */}
      {showCreateModal && (
        <CreateRoleModal
          allPermissions={allPermissions}
          onClose={() => setShowCreateModal(false)}
          onCreated={fetchRoles}
        />
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Permission Matrix Modal (edit existing role)                              */
/* -------------------------------------------------------------------------- */

function PermissionMatrixModal({
  role,
  allPermissions,
  onClose,
  onSaved,
}: {
  role: RoleWithPermissions;
  allPermissions: Permission[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [selected, setSelected] = useState<Set<string>>(
    new Set(role.permissions.map((p) => p.id)),
  );
  const [saving, setSaving] = useState(false);

  const grouped = allPermissions.reduce(
    (acc, perm) => {
      if (!acc[perm.resource]) acc[perm.resource] = [];
      acc[perm.resource].push(perm);
      return acc;
    },
    {} as Record<string, Permission[]>,
  );

  const resources = Object.keys(grouped).sort();
  const actions = [...new Set(allPermissions.map((p) => p.action))].sort();

  const toggle = (permId: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(permId)) next.delete(permId);
      else next.add(permId);
      return next;
    });
  };

  const toggleAll = (resource: string) => {
    const perms = grouped[resource] || [];
    const allSelected = perms.every((p) => selected.has(p.id));
    setSelected((prev) => {
      const next = new Set(prev);
      perms.forEach((p) => {
        if (allSelected) next.delete(p.id);
        else next.add(p.id);
      });
      return next;
    });
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await apiPut(`/roles/${role.id}/permissions`, {
        permission_ids: Array.from(selected),
      });
      onSaved();
      onClose();
    } catch (err) {
      console.error("Failed to save permissions:", err);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        className="w-full max-w-3xl rounded-xl border p-6 shadow-lg"
        style={{
          backgroundColor: "var(--card)",
          borderColor: "var(--border)",
          color: "var(--card-foreground)",
        }}
      >
        <h2 className="text-lg font-semibold">
          Edit Permissions: {role.name}
        </h2>
        {role.is_system && (
          <p
            className="mt-1 text-sm"
            style={{ color: "var(--warning)" }}
          >
            This is a system role. Changes will affect all users with this role.
          </p>
        )}

        <div
          className="mt-4 max-h-96 overflow-auto rounded-md border"
          style={{ borderColor: "var(--border)" }}
        >
          <table className="w-full text-sm">
            <thead
              className="sticky top-0"
              style={{ backgroundColor: "var(--card)" }}
            >
              <tr
                className="border-b"
                style={{ borderColor: "var(--border)" }}
              >
                <th
                  className="px-3 py-2 text-left font-medium"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  Resource
                </th>
                {actions.map((action) => (
                  <th
                    key={action}
                    className="px-3 py-2 text-center font-medium capitalize"
                    style={{ color: "var(--muted-foreground)" }}
                  >
                    {action}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {resources.map((resource) => (
                <tr
                  key={resource}
                  className="border-b"
                  style={{ borderColor: "var(--border)" }}
                >
                  <td className="px-3 py-2">
                    <button
                      type="button"
                      onClick={() => toggleAll(resource)}
                      className="font-medium capitalize transition-colors"
                      style={{ color: "var(--foreground)" }}
                      title="Toggle all permissions for this resource"
                    >
                      {resource}
                    </button>
                  </td>
                  {actions.map((action) => {
                    const perm = grouped[resource]?.find(
                      (p) => p.action === action,
                    );
                    if (!perm) {
                      return (
                        <td
                          key={action}
                          className="px-3 py-2 text-center"
                          style={{
                            color:
                              "color-mix(in oklch, var(--muted-foreground) 30%, transparent)",
                          }}
                        >
                          -
                        </td>
                      );
                    }
                    return (
                      <td key={action} className="px-3 py-2 text-center">
                        <input
                          type="checkbox"
                          checked={selected.has(perm.id)}
                          onChange={() => toggle(perm.id)}
                          className="rounded"
                          style={{ borderColor: "var(--border)" }}
                        />
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="mt-4 flex items-center justify-between">
          <span
            className="text-sm"
            style={{ color: "var(--muted-foreground)" }}
          >
            {selected.size} of {allPermissions.length} permissions selected
          </span>
          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="rounded-md border px-4 py-2 text-sm transition-colors"
              style={{
                borderColor: "var(--input)",
                backgroundColor: "var(--background)",
              }}
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={saving}
              className="rounded-md px-4 py-2 text-sm font-medium shadow-sm transition-colors disabled:opacity-50"
              style={{
                backgroundColor: "var(--primary)",
                color: "var(--primary-foreground)",
              }}
            >
              {saving ? "Saving..." : "Save Permissions"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Create Role Modal                                                         */
/* -------------------------------------------------------------------------- */

function CreateRoleModal({
  allPermissions,
  onClose,
  onCreated,
}: {
  allPermissions: Permission[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const grouped = allPermissions.reduce(
    (acc, perm) => {
      if (!acc[perm.resource]) acc[perm.resource] = [];
      acc[perm.resource].push(perm);
      return acc;
    },
    {} as Record<string, Permission[]>,
  );

  const resources = Object.keys(grouped).sort();
  const actions = [...new Set(allPermissions.map((p) => p.action))].sort();

  const toggle = (permId: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(permId)) next.delete(permId);
      else next.add(permId);
      return next;
    });
  };

  const toggleAll = (resource: string) => {
    const perms = grouped[resource] || [];
    const allSelected = perms.every((p) => selected.has(p.id));
    setSelected((prev) => {
      const next = new Set(prev);
      perms.forEach((p) => {
        if (allSelected) next.delete(p.id);
        else next.add(p.id);
      });
      return next;
    });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError("");
    try {
      await apiPost("/roles", {
        name,
        description,
        permission_ids: Array.from(selected),
      });
      onCreated();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create role");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        className="w-full max-w-3xl rounded-xl border p-6 shadow-lg"
        style={{
          backgroundColor: "var(--card)",
          borderColor: "var(--border)",
          color: "var(--card-foreground)",
        }}
      >
        <h2 className="text-lg font-semibold">Create Role</h2>

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label className="text-sm font-medium">Name</label>
              <input
                type="text"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g. Team Lead"
                className="mt-1 w-full rounded-md border px-3 py-2 text-sm"
                style={{
                  borderColor: "var(--input)",
                  backgroundColor: "var(--background)",
                }}
              />
            </div>
            <div>
              <label className="text-sm font-medium">Description</label>
              <input
                type="text"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="e.g. Can manage team members"
                className="mt-1 w-full rounded-md border px-3 py-2 text-sm"
                style={{
                  borderColor: "var(--input)",
                  backgroundColor: "var(--background)",
                }}
              />
            </div>
          </div>

          <div>
            <label className="text-sm font-medium">
              Permissions ({selected.size} selected)
            </label>
            <div
              className="mt-1 max-h-64 overflow-auto rounded-md border"
              style={{ borderColor: "var(--border)" }}
            >
              <table className="w-full text-sm">
                <thead
                  className="sticky top-0"
                  style={{ backgroundColor: "var(--card)" }}
                >
                  <tr
                    className="border-b"
                    style={{ borderColor: "var(--border)" }}
                  >
                    <th
                      className="px-3 py-2 text-left font-medium"
                      style={{ color: "var(--muted-foreground)" }}
                    >
                      Resource
                    </th>
                    {actions.map((action) => (
                      <th
                        key={action}
                        className="px-3 py-2 text-center font-medium capitalize"
                        style={{ color: "var(--muted-foreground)" }}
                      >
                        {action}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {resources.map((resource) => (
                    <tr
                      key={resource}
                      className="border-b"
                      style={{ borderColor: "var(--border)" }}
                    >
                      <td className="px-3 py-2">
                        <button
                          type="button"
                          onClick={() => toggleAll(resource)}
                          className="font-medium capitalize transition-colors"
                          style={{ color: "var(--foreground)" }}
                          title="Toggle all permissions for this resource"
                        >
                          {resource}
                        </button>
                      </td>
                      {actions.map((action) => {
                        const perm = grouped[resource]?.find(
                          (p) => p.action === action,
                        );
                        if (!perm) {
                          return (
                            <td
                              key={action}
                              className="px-3 py-2 text-center"
                              style={{
                                color:
                                  "color-mix(in oklch, var(--muted-foreground) 30%, transparent)",
                              }}
                            >
                              -
                            </td>
                          );
                        }
                        return (
                          <td key={action} className="px-3 py-2 text-center">
                            <input
                              type="checkbox"
                              checked={selected.has(perm.id)}
                              onChange={() => toggle(perm.id)}
                              className="rounded"
                              style={{ borderColor: "var(--border)" }}
                            />
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Error */}
          {error && (
            <p className="text-sm" style={{ color: "var(--destructive)" }}>
              {error}
            </p>
          )}

          {/* Actions */}
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-md border px-4 py-2 text-sm transition-colors"
              style={{
                borderColor: "var(--input)",
                backgroundColor: "var(--background)",
              }}
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="rounded-md px-4 py-2 text-sm font-medium shadow-sm transition-colors disabled:opacity-50"
              style={{
                backgroundColor: "var(--primary)",
                color: "var(--primary-foreground)",
              }}
            >
              {submitting ? "Creating..." : "Create Role"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
