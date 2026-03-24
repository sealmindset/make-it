// =============================================================================
// Prisma Seed -- [APP_NAME]
// =============================================================================
// Seeds RBAC tables: roles, permissions, role_permissions, and initial users.
// Users must match mock-oidc subjects for local development.
//
// Usage: npx prisma db seed
// =============================================================================

import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  console.log("Seeding database...");

  // -------------------------------------------------------------------------
  // 1. System roles (4 standard roles)
  // -------------------------------------------------------------------------
  const superAdmin = await prisma.role.upsert({
    where: { name: "Super Admin" },
    update: {},
    create: {
      name: "Super Admin",
      description: "Full system access. Cannot be modified or deleted.",
      isSystem: true,
    },
  });

  const admin = await prisma.role.upsert({
    where: { name: "Admin" },
    update: {},
    create: {
      name: "Admin",
      description: "Administrative access. Can manage users, roles, and settings.",
      isSystem: true,
    },
  });

  const manager = await prisma.role.upsert({
    where: { name: "Manager" },
    update: {},
    create: {
      name: "Manager",
      description: "Can manage team resources and view reports.",
      isSystem: true,
    },
  });

  const user = await prisma.role.upsert({
    where: { name: "User" },
    update: {},
    create: {
      name: "User",
      description: "Standard user access.",
      isSystem: true,
    },
  });

  // -------------------------------------------------------------------------
  // 2. Permissions (CRUD per resource)
  // -------------------------------------------------------------------------
  const resources = [
    "dashboard",
    "users",
    "roles",
    "app_settings",
    // [DOMAIN_PERMISSIONS] -- app-specific resources added here
  ];

  const actions = ["view", "create", "edit", "delete"];

  const permissions: Record<string, string> = {};

  for (const resource of resources) {
    for (const action of actions) {
      const perm = await prisma.permission.upsert({
        where: {
          uq_permission_resource_action: { resource, action },
        },
        update: {},
        create: {
          resource,
          action,
          description: `${action} ${resource}`,
        },
      });
      permissions[`${resource}.${action}`] = perm.id;
    }
  }

  // -------------------------------------------------------------------------
  // 3. Role-permission assignments
  // -------------------------------------------------------------------------
  // Super Admin: all permissions
  const allPermIds = Object.values(permissions);
  for (const permId of allPermIds) {
    await prisma.rolePermission.upsert({
      where: {
        roleId_permissionId: {
          roleId: superAdmin.id,
          permissionId: permId,
        },
      },
      update: {},
      create: { roleId: superAdmin.id, permissionId: permId },
    });
  }

  // Admin: all except role delete
  const adminPermIds = allPermIds.filter(
    (id) => id !== permissions["roles.delete"],
  );
  for (const permId of adminPermIds) {
    await prisma.rolePermission.upsert({
      where: {
        roleId_permissionId: {
          roleId: admin.id,
          permissionId: permId,
        },
      },
      update: {},
      create: { roleId: admin.id, permissionId: permId },
    });
  }

  // Manager: dashboard + view users/roles + domain view/create/edit
  const managerPermKeys = [
    "dashboard.view",
    "users.view",
    "roles.view",
    // [MANAGER_PERMISSIONS] -- app-specific manager permissions
  ];
  for (const key of managerPermKeys) {
    if (permissions[key]) {
      await prisma.rolePermission.upsert({
        where: {
          roleId_permissionId: {
            roleId: manager.id,
            permissionId: permissions[key],
          },
        },
        update: {},
        create: { roleId: manager.id, permissionId: permissions[key] },
      });
    }
  }

  // User: dashboard view + domain view only
  const userPermKeys = [
    "dashboard.view",
    // [USER_PERMISSIONS] -- app-specific user permissions
  ];
  for (const key of userPermKeys) {
    if (permissions[key]) {
      await prisma.rolePermission.upsert({
        where: {
          roleId_permissionId: {
            roleId: user.id,
            permissionId: permissions[key],
          },
        },
        update: {},
        create: { roleId: user.id, permissionId: permissions[key] },
      });
    }
  }

  // -------------------------------------------------------------------------
  // 4. Seed users (must match mock-oidc subjects)
  // -------------------------------------------------------------------------
  await prisma.user.upsert({
    where: { oidcSubject: "[ROLE_1_OIDC_SUB]" },
    update: {},
    create: {
      oidcSubject: "[ROLE_1_OIDC_SUB]",
      email: "[ROLE_1_EMAIL]",
      displayName: "[ROLE_1_DISPLAY_NAME]",
      roleId: superAdmin.id,
    },
  });

  await prisma.user.upsert({
    where: { oidcSubject: "[ROLE_2_OIDC_SUB]" },
    update: {},
    create: {
      oidcSubject: "[ROLE_2_OIDC_SUB]",
      email: "[ROLE_2_EMAIL]",
      displayName: "[ROLE_2_DISPLAY_NAME]",
      roleId: admin.id,
    },
  });

  await prisma.user.upsert({
    where: { oidcSubject: "[ROLE_3_OIDC_SUB]" },
    update: {},
    create: {
      oidcSubject: "[ROLE_3_OIDC_SUB]",
      email: "[ROLE_3_EMAIL]",
      displayName: "[ROLE_3_DISPLAY_NAME]",
      roleId: manager.id,
    },
  });

  await prisma.user.upsert({
    where: { oidcSubject: "[ROLE_4_OIDC_SUB]" },
    update: {},
    create: {
      oidcSubject: "[ROLE_4_OIDC_SUB]",
      email: "[ROLE_4_EMAIL]",
      displayName: "[ROLE_4_DISPLAY_NAME]",
      roleId: user.id,
    },
  });

  // [DOMAIN_SEED_DATA] -- app-specific seed data added here

  console.log("Database seeded successfully.");
}

main()
  .catch((e) => {
    console.error("Seed failed:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
