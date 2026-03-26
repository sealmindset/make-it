// AuthMe matches JWT payload EXACTLY -- flat, no .user wrapper
export interface AuthMe {
  sub: string;
  email: string;
  name: string;
  role_id: string;
  role_name: string;
  permissions: string[];
}

export interface User {
  id: string;
  oidc_subject: string;
  email: string;
  display_name: string;
  is_active: boolean;
  role_id: string;
  role_name: string | null;
  created_at: string;
  updated_at: string;
}

export interface Role {
  id: string;
  name: string;
  description: string;
  is_system: boolean;
  created_at: string;
  updated_at: string;
}

export interface Permission {
  id: string;
  resource: string;
  action: string;
  description: string | null;
}

export interface RoleWithPermissions extends Role {
  permissions: Permission[];
}

// ---------------------------------------------------------------------------
// AI Prompt Management
// ---------------------------------------------------------------------------

export interface ManagedPrompt {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  category: string;
  provider: string | null;
  model: string | null;
  current_version: number;
  is_active: boolean;
  is_locked: boolean;
  locked_by: string | null;
  locked_reason: string | null;
  source_file: string | null;
  created_by: string;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
  tags: string[];
  primary_usage_location: string | null;
  version_count?: number;
  usage_count?: number;
}

export interface ManagedPromptListItem {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  category: string;
  provider: string | null;
  model: string | null;
  current_version: number;
  is_active: boolean;
  is_locked: boolean;
  updated_at: string;
  tags: string[];
  primary_usage_location: string | null;
}

export interface PromptVersion {
  id: string;
  prompt_id: string;
  version: number;
  content: string;
  system_message: string | null;
  parameters: Record<string, unknown> | null;
  model: string | null;
  change_summary: string | null;
  created_by: string;
  created_at: string;
}

export interface PromptVersionDiff {
  version_a: number;
  version_b: number;
  content_diff: string | null;
  system_message_diff: string | null;
  parameters_a: Record<string, unknown> | null;
  parameters_b: Record<string, unknown> | null;
}

export interface PromptUsage {
  id: string;
  prompt_id: string;
  usage_type: string;
  location: string;
  description: string | null;
  is_primary: boolean;
  call_count: number;
  avg_latency_ms: number | null;
  avg_tokens_in: number | null;
  avg_tokens_out: number | null;
  error_count: number;
  created_at: string;
  updated_at: string;
}

export interface PromptTestCase {
  id: string;
  prompt_id: string;
  name: string;
  input_data: Record<string, unknown> | null;
  expected_output: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface PromptTestRun {
  output: string;
  tokens_in: number | null;
  tokens_out: number | null;
  latency_ms: number | null;
  success: boolean;
  error: string | null;
}

export interface PromptAuditLogEntry {
  id: string;
  action: string;
  prompt_id: string | null;
  prompt_slug: string | null;
  version: number | null;
  user_id: string | null;
  user_email: string | null;
  old_value: Record<string, unknown> | null;
  new_value: Record<string, unknown> | null;
  created_at: string;
}

export interface PromptStats {
  total: number;
  active: number;
  versions_count: number;
  categories_count: number;
}

export interface PromptTag {
  tag: string;
  count: number;
}

// [DOMAIN_TYPES] -- app-specific types added here
