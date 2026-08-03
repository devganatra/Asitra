import { index, integer, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";

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
  createdAt: text("created_at").notNull(),
});

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
