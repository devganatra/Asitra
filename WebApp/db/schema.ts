import { index, integer, primaryKey, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

// Better Auth's D1 tables. OAuth tokens and sessions never leave the server.
export const authUsers = sqliteTable("user", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: integer("emailVerified", { mode: "boolean" }).notNull().default(false),
  image: text("image"),
  createdAt: integer("createdAt", { mode: "timestamp" }).notNull(),
  updatedAt: integer("updatedAt", { mode: "timestamp" }).notNull(),
});

export const authSessions = sqliteTable(
  "session",
  {
    id: text("id").primaryKey(),
    expiresAt: integer("expiresAt", { mode: "timestamp" }).notNull(),
    token: text("token").notNull().unique(),
    createdAt: integer("createdAt", { mode: "timestamp" }).notNull(),
    updatedAt: integer("updatedAt", { mode: "timestamp" }).notNull(),
    ipAddress: text("ipAddress"),
    userAgent: text("userAgent"),
    userId: text("userId").notNull().references(() => authUsers.id, { onDelete: "cascade" }),
  },
  (table) => [index("session_userId_index").on(table.userId)],
);

export const authAccounts = sqliteTable(
  "account",
  {
    id: text("id").primaryKey(),
    accountId: text("accountId").notNull(),
    providerId: text("providerId").notNull(),
    userId: text("userId").notNull().references(() => authUsers.id, { onDelete: "cascade" }),
    accessToken: text("accessToken"),
    refreshToken: text("refreshToken"),
    idToken: text("idToken"),
    accessTokenExpiresAt: integer("accessTokenExpiresAt", { mode: "timestamp" }),
    refreshTokenExpiresAt: integer("refreshTokenExpiresAt", { mode: "timestamp" }),
    scope: text("scope"),
    password: text("password"),
    createdAt: integer("createdAt", { mode: "timestamp" }).notNull(),
    updatedAt: integer("updatedAt", { mode: "timestamp" }).notNull(),
  },
  (table) => [index("account_userId_index").on(table.userId)],
);

export const authVerifications = sqliteTable(
  "verification",
  {
    id: text("id").primaryKey(),
    identifier: text("identifier").notNull(),
    value: text("value").notNull(),
    expiresAt: integer("expiresAt", { mode: "timestamp" }).notNull(),
    createdAt: integer("createdAt", { mode: "timestamp" }).notNull(),
    updatedAt: integer("updatedAt", { mode: "timestamp" }).notNull(),
  },
  (table) => [index("verification_identifier_index").on(table.identifier)],
);

export const authRateLimits = sqliteTable(
  "rateLimit",
  {
    id: text("id").primaryKey(),
    key: text("key").notNull(),
    count: integer("count").notNull(),
    lastRequest: integer("lastRequest").notNull(),
  },
  (table) => [uniqueIndex("rateLimit_key_unique").on(table.key)],
);

export const userStates = sqliteTable("user_states", {
  userId: text("user_id").primaryKey(),
  stateJson: text("state_json").notNull(),
  version: integer("version").notNull().default(1),
  updatedAt: text("updated_at").notNull(),
});

export const attachments = sqliteTable("attachments", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull(),
  objectKey: text("object_key").notNull().unique(),
  contentType: text("content_type").notNull(),
  byteSize: integer("byte_size").notNull(),
  kind: text("kind").notNull().default("image"),
  fileName: text("file_name"),
  createdAt: text("created_at").notNull(),
}, (table) => [index("attachments_user_id_index").on(table.userId)]);

export const stateRevisions = sqliteTable(
  "state_revisions",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    stateJson: text("state_json").notNull(),
    version: integer("version").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (table) => [index("state_revisions_user_created_index").on(table.userId, table.createdAt)],
);

export const userConsents = sqliteTable(
  "user_consents",
  {
    userId: text("user_id").notNull(),
    purpose: text("purpose").notNull(),
    granted: integer("granted", { mode: "boolean" }).notNull().default(false),
    policyVersion: text("policy_version").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.purpose] })],
);

export const nativeSessions = sqliteTable(
  "native_sessions",
  {
    tokenHash: text("token_hash").primaryKey(),
    userId: text("user_id").notNull(),
    createdAt: text("created_at").notNull(),
    expiresAt: text("expires_at").notNull(),
    lastUsedAt: text("last_used_at").notNull(),
  },
  (table) => [index("native_sessions_user_id_index").on(table.userId)],
);

export const nativeAIUsage = sqliteTable(
  "native_ai_usage",
  {
    userId: text("user_id").notNull(),
    windowStart: text("window_start").notNull(),
    requestCount: integer("request_count").notNull().default(0),
  },
  (table) => [primaryKey({ columns: [table.userId, table.windowStart] })],
);

export const requestUsage = sqliteTable(
  "request_usage",
  {
    userId: text("user_id").notNull(),
    scope: text("scope").notNull(),
    windowStart: text("window_start").notNull(),
    requestCount: integer("request_count").notNull().default(0),
  },
  (table) => [primaryKey({ columns: [table.userId, table.scope, table.windowStart] })],
);

export const sharedLists = sqliteTable("shared_lists", {
  id: text("id").primaryKey(),
  ownerId: text("owner_id").notNull(),
  listJson: text("list_json").notNull(),
  version: integer("version").notNull().default(1),
  updatedAt: text("updated_at").notNull(),
});

export const sharedListMembers = sqliteTable(
  "shared_list_members",
  {
    listId: text("list_id").notNull(),
    userId: text("user_id").notNull(),
    role: text("role").notNull(),
  },
  (table) => [primaryKey({ columns: [table.listId, table.userId] }), index("shared_list_members_user_index").on(table.userId)],
);

export const sharedListInvites = sqliteTable("shared_list_invites", {
  tokenHash: text("token_hash").primaryKey(),
  listId: text("list_id").notNull(),
  expiresAt: text("expires_at").notNull(),
  createdAt: text("created_at").notNull(),
});
