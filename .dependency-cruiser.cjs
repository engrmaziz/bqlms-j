/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
	forbidden: [
		{
			name: "cross-module-import-only-via-index",
			severity: "error",
			comment:
				"Modules must only import from each other via their index.ts file",
			from: {
				path: "^src/modules/([^/]+)/",
			},
			to: {
				path: "^src/modules/([^/]+)/",
				pathNot: [
					"^src/modules/$1/", // Allow imports within the same module
					"^src/modules/[^/]+/index\\.ts$", // Allow imports to index.ts of other modules
				],
			},
		},
	],
	options: {
		doNotFollow: {
			path: "node_modules",
		},
		includeOnly: "^src",
		tsPreCompilationDeps: true,
		tsConfig: {
			fileName: "tsconfig.json",
		},
	},
};
