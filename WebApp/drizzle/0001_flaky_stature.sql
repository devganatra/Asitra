CREATE TABLE `native_ai_usage` (
	`user_id` text NOT NULL,
	`window_start` text NOT NULL,
	`request_count` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`user_id`, `window_start`)
);
--> statement-breakpoint
CREATE TABLE `native_sessions` (
	`token_hash` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`created_at` text NOT NULL,
	`expires_at` text NOT NULL,
	`last_used_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `native_sessions_user_id_index` ON `native_sessions` (`user_id`);