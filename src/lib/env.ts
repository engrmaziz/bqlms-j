import { createEnv } from "@t3-oss/env-nextjs";
import { z } from "zod";

export const env = createEnv({
	server: {
		NODE_ENV: z
			.enum(["development", "test", "production"])
			.default("development"),
		PORT: z.coerce.number().default(8080),
		DATABASE_URL: z.string().url(),
		DATABASE_URL_SESSION: z.string().url(),
		STORAGE_ENDPOINT: z.string().url(),
		STORAGE_ACCESS_KEY: z.string().min(1),
		STORAGE_SECRET_KEY: z.string().min(1),
		STORAGE_BUCKET: z.string().min(1),
		MAIL_SMTP_HOST: z.string().min(1),
		MAIL_SMTP_PORT: z.coerce.number().default(1025),
	},
	client: {},
	runtimeEnv: {
		NODE_ENV: process.env.NODE_ENV,
		PORT: process.env.PORT,
		DATABASE_URL: process.env.DATABASE_URL,
		DATABASE_URL_SESSION: process.env.DATABASE_URL_SESSION,
		STORAGE_ENDPOINT: process.env.STORAGE_ENDPOINT,
		STORAGE_ACCESS_KEY: process.env.STORAGE_ACCESS_KEY,
		STORAGE_SECRET_KEY: process.env.STORAGE_SECRET_KEY,
		STORAGE_BUCKET: process.env.STORAGE_BUCKET,
		MAIL_SMTP_HOST: process.env.MAIL_SMTP_HOST,
		MAIL_SMTP_PORT: process.env.MAIL_SMTP_PORT,
	},
	skipValidation: !!process.env.SKIP_ENV_VALIDATION,
	emptyStringAsUndefined: true,
});
