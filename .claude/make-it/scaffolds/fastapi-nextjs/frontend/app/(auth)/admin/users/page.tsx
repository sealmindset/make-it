"use client";

import { useEffect, useState, useCallback } from "react";
import { type ColumnDef } from "@tanstack/react-table";
import { apiGet, apiPost, apiPut, apiDelete } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { DataTable } from "@/components/data-table";
import { DataTableColumnHeader } from "@/components/data-table-column-header";
import { formatDate } from "@/lib/utils";
import type { User, Role } from "@/lib/types";
import {
  UserPlus,
  Ban,
  CheckCircle,
  Trash2,
  Search,
  Loader2,
} from "lucide-react";

/** Directory user returned from GET /users/directory */
interface DirectoryUser {
  oidc_subject: string;
  email: string;
  display_name: string;
}

export default function UsersPage() {
  const { hasPermission } = useAuth();
  const [users, setUsers] = useState<User[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);

  const canCreate = hasPermission("users", "create");
  const canEdit = hasPermission("users", "edit");
  const canDelete = hasPermission("users", "delete");

  const fetchUsers = useCallback(async () => {
    try {
      const [usersData, rolesData] = await Promise.all([
        apiGet<User[]>("/users"),
        apiGet<Role[]>("/roles"),
      ]);
      setUsers(usersData);
      setRoles(rolesData);
    } catch (err) {
      console.error("Failed to load users:", err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchUsers();
  }, [fetchUsers]);

  const handleToggleActive = async (user: User) => {
    try {
      await apiPut(`/users/${user.id}`, {
        is_active: !user.is_active,
      });
      fetchUsers();
    } catch (err) {
      console.error("Failed to update user:", err);
    }
  };

  const handleChangeRole = async (userId: string, roleId: string) => {
    try {
      await apiPut(`/users/${userId}`, { role_id: roleId });
      fetchUsers();
    } catch (err) {
      console.error("Failed to update role:", err);
    }
  };

  const handleDeleteUser = async (userId: string) => {
    if (!confirm("Are you sure you want to delete this user?")) return;
    try {
      await apiDelete(`/users/${userId}`);
      fetchUsers();
    } catch (err) {
      console.error("Failed to delete user:", err);
    }
  };

  const columns: ColumnDef<User, unknown>[] = [
    {
      accessorKey: "display_name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Name" />
      ),
    },
    {
      accessorKey: "email",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Email" />
      ),
    },
    {
      accessorKey: "role_name",
      header: ({ column }) => (
        <DataTableColumnHeader
          column={column}
          title="Role"
        />
      ),
      cell: ({ row }) => {
        const user = row.original;
        if (!canEdit) return user.role_name || "-";
        return (
          <select
            value={user.role_id}
            onChange={(e) => handleChangeRole(user.id, e.target.value)}
            className="rounded-md border px-2 py-1 text-sm"
            style={{
              borderColor: "var(--input)",
              backgroundColor: "var(--background)",
              color: "var(--foreground)",
            }}
          >
            {roles.map((role) => (
              <option key={role.id} value={role.id}>
                {role.name}
              </option>
            ))}
          </select>
        );
      },
      filterFn: (row, id, value: string[]) => {
        return value.includes(String(row.getValue(id)));
      },
    },
    {
      accessorKey: "is_active",
      header: ({ column }) => (
        <DataTableColumnHeader
          column={column}
          title="Status"
        />
      ),
      cell: ({ row }) => {
        const active = row.original.is_active;
        return (
          <span
            className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
            style={{
              backgroundColor: active
                ? "color-mix(in oklch, var(--success) 15%, transparent)"
                : "color-mix(in oklch, var(--destructive) 15%, transparent)",
              color: active ? "var(--success)" : "var(--destructive)",
            }}
          >
            {active ? "Active" : "Inactive"}
          </span>
        );
      },
      filterFn: (row, id, value: string[]) => {
        const v = row.getValue(id) ? "Active" : "Inactive";
        return value.includes(v);
      },
    },
    {
      accessorKey: "created_at",
      header: ({ column }) => (
        <DataTableColumnHeader
          column={column}
          title="Created"
        />
      ),
      cell: ({ row }) => formatDate(row.original.created_at),
    },
    ...(canEdit || canDelete
      ? [
          {
            id: "actions",
            header: () => <span className="sr-only">Actions</span>,
            cell: ({ row }: { row: { original: User } }) => {
              const user = row.original;
              return (
                <div className="flex items-center gap-1">
                  {canEdit && (
                    <button
                      onClick={() => handleToggleActive(user)}
                      className="rounded p-1 transition-colors"
                      style={{ color: "var(--muted-foreground)" }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.backgroundColor = "var(--accent)";
                        e.currentTarget.style.color = "var(--accent-foreground)";
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.backgroundColor = "transparent";
                        e.currentTarget.style.color = "var(--muted-foreground)";
                      }}
                      title={user.is_active ? "Deactivate" : "Activate"}
                    >
                      {user.is_active ? (
                        <Ban className="h-4 w-4" />
                      ) : (
                        <CheckCircle className="h-4 w-4" />
                      )}
                    </button>
                  )}
                  {canDelete && (
                    <button
                      onClick={() => handleDeleteUser(user.id)}
                      className="rounded p-1 transition-colors"
                      style={{ color: "var(--muted-foreground)" }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.backgroundColor =
                          "color-mix(in oklch, var(--destructive) 10%, transparent)";
                        e.currentTarget.style.color = "var(--destructive)";
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.backgroundColor = "transparent";
                        e.currentTarget.style.color = "var(--muted-foreground)";
                      }}
                      title="Delete"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  )}
                </div>
              );
            },
          } as ColumnDef<User, unknown>,
        ]
      : []),
  ];

  if (loading) {
    return (
      <div className="space-y-4">
        <div
          className="h-8 w-48 animate-pulse rounded"
          style={{ backgroundColor: "var(--muted)" }}
        />
        <div
          className="h-64 animate-pulse rounded-xl border"
          style={{
            backgroundColor: "var(--card)",
            borderColor: "var(--border)",
          }}
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Users</h1>
          <p style={{ color: "var(--muted-foreground)" }}>
            Manage user accounts and role assignments.
          </p>
        </div>
        {canCreate && (
          <button
            onClick={() => setShowAddModal(true)}
            className="inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-medium shadow-sm transition-colors"
            style={{
              backgroundColor: "var(--primary)",
              color: "var(--primary-foreground)",
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.opacity = "0.9";
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.opacity = "1";
            }}
          >
            <UserPlus className="h-4 w-4" />
            Add User
          </button>
        )}
      </div>

      {/* Users data table */}
      <DataTable
        columns={columns}
        data={users}
        storageKey="users-table"
        searchKey="display_name"
        searchPlaceholder="Search users..."
      />

      {/* Add User modal -- provisions from OIDC directory */}
      {showAddModal && (
        <AddUserModal
          roles={roles}
          onClose={() => setShowAddModal(false)}
          onAdded={fetchUsers}
        />
      )}
    </div>
  );
}

/**
 * Add User modal with OIDC directory search.
 * Searches the organization directory via GET /users/directory?q=<search>,
 * lets the admin select a user and assign a role before provisioning.
 */
function AddUserModal({
  roles,
  onClose,
  onAdded,
}: {
  roles: Role[];
  onClose: () => void;
  onAdded: () => void;
}) {
  const [searchQuery, setSearchQuery] = useState("");
  const [directoryResults, setDirectoryResults] = useState<DirectoryUser[]>([]);
  const [searching, setSearching] = useState(false);
  const [selectedUser, setSelectedUser] = useState<DirectoryUser | null>(null);
  const [roleId, setRoleId] = useState(roles[roles.length - 1]?.id || "");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  // Search the OIDC directory when query changes
  useEffect(() => {
    if (searchQuery.length < 2) {
      setDirectoryResults([]);
      return;
    }

    const debounce = setTimeout(async () => {
      setSearching(true);
      try {
        const results = await apiGet<DirectoryUser[]>(
          `/users/directory?q=${encodeURIComponent(searchQuery)}`,
        );
        setDirectoryResults(results);
      } catch (err) {
        console.error("Directory search failed:", err);
        setDirectoryResults([]);
      } finally {
        setSearching(false);
      }
    }, 300);

    return () => clearTimeout(debounce);
  }, [searchQuery]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUser) {
      setError("Select a user from the directory first.");
      return;
    }
    setSubmitting(true);
    setError("");
    try {
      await apiPost("/users", {
        oidc_subject: selectedUser.oidc_subject,
        email: selectedUser.email,
        display_name: selectedUser.display_name,
        role_id: roleId,
      });
      onAdded();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to add user");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        className="w-full max-w-md rounded-xl border p-6 shadow-lg"
        style={{
          backgroundColor: "var(--card)",
          borderColor: "var(--border)",
          color: "var(--card-foreground)",
        }}
      >
        <h2 className="text-lg font-semibold">Add User</h2>
        <p
          className="mt-1 text-sm"
          style={{ color: "var(--muted-foreground)" }}
        >
          Provision a user from the organization directory.
        </p>

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          {/* Directory search */}
          <div>
            <label className="text-sm font-medium">Search Directory</label>
            <div className="relative mt-1">
              <Search
                className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2"
                style={{ color: "var(--muted-foreground)" }}
              />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => {
                  setSearchQuery(e.target.value);
                  setSelectedUser(null);
                }}
                placeholder="Search by name or email..."
                className="w-full rounded-md border py-2 pl-8 pr-3 text-sm"
                style={{
                  borderColor: "var(--input)",
                  backgroundColor: "var(--background)",
                }}
              />
              {searching && (
                <Loader2
                  className="absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin"
                  style={{ color: "var(--muted-foreground)" }}
                />
              )}
            </div>

            {/* Directory results dropdown */}
            {directoryResults.length > 0 && !selectedUser && (
              <ul
                className="mt-1 max-h-40 overflow-y-auto rounded-md border text-sm"
                style={{
                  borderColor: "var(--border)",
                  backgroundColor: "var(--popover)",
                  color: "var(--popover-foreground)",
                }}
              >
                {directoryResults.map((user) => (
                  <li key={user.oidc_subject}>
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedUser(user);
                        setSearchQuery(user.display_name);
                      }}
                      className="flex w-full flex-col px-3 py-2 text-left transition-colors"
                      onMouseEnter={(e) => {
                        e.currentTarget.style.backgroundColor = "var(--accent)";
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.backgroundColor = "transparent";
                      }}
                    >
                      <span className="font-medium">{user.display_name}</span>
                      <span
                        className="text-xs"
                        style={{ color: "var(--muted-foreground)" }}
                      >
                        {user.email}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}

            {/* Selected user badge */}
            {selectedUser && (
              <div
                className="mt-2 flex items-center justify-between rounded-md border px-3 py-2 text-sm"
                style={{
                  backgroundColor: "color-mix(in oklch, var(--primary) 8%, transparent)",
                  borderColor: "color-mix(in oklch, var(--primary) 30%, transparent)",
                }}
              >
                <div>
                  <span className="font-medium">{selectedUser.display_name}</span>
                  <span
                    className="ml-2 text-xs"
                    style={{ color: "var(--muted-foreground)" }}
                  >
                    {selectedUser.email}
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedUser(null);
                    setSearchQuery("");
                  }}
                  className="text-xs underline"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  Change
                </button>
              </div>
            )}
          </div>

          {/* Role selector */}
          <div>
            <label className="text-sm font-medium">Role</label>
            <select
              value={roleId}
              onChange={(e) => setRoleId(e.target.value)}
              className="mt-1 w-full rounded-md border px-3 py-2 text-sm"
              style={{
                borderColor: "var(--input)",
                backgroundColor: "var(--background)",
              }}
            >
              {roles.map((role) => (
                <option key={role.id} value={role.id}>
                  {role.name}
                </option>
              ))}
            </select>
          </div>

          {/* Error message */}
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
              disabled={submitting || !selectedUser}
              className="rounded-md px-4 py-2 text-sm font-medium shadow-sm transition-colors disabled:opacity-50"
              style={{
                backgroundColor: "var(--primary)",
                color: "var(--primary-foreground)",
              }}
            >
              {submitting ? "Adding..." : "Add User"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
