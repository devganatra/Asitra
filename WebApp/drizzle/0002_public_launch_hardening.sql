CREATE TABLE `request_usage` (
	`user_id` text NOT NULL,
	`scope` text NOT NULL,
	`window_start` text NOT NULL,
	`request_count` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`user_id`, `scope`, `window_start`)
);
--> statement-breakpoint
CREATE TABLE `shared_lists` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_id` text NOT NULL,
	`list_json` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `shared_list_members` (
	`list_id` text NOT NULL,
	`user_id` text NOT NULL,
	`role` text NOT NULL,
	PRIMARY KEY(`list_id`, `user_id`)
);
--> statement-breakpoint
CREATE INDEX `shared_list_members_user_index` ON `shared_list_members` (`user_id`);
--> statement-breakpoint
CREATE TABLE `shared_list_invites` (
	`token_hash` text PRIMARY KEY NOT NULL,
	`list_id` text NOT NULL,
	`expires_at` text NOT NULL,
	`created_at` text NOT NULL
);
