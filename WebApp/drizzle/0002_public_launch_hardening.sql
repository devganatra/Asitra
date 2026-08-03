CREATE TABLE `request_usage` (
	`user_id` text NOT NULL,
	`scope` text NOT NULL,
	`window_start` text NOT NULL,
	`request_count` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`user_id`, `scope`, `window_start`)
);
